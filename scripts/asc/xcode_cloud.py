#!/usr/bin/env python3
"""查看和启动听页的 Xcode Cloud 构建。

凭据只从环境变量读取。脚本用系统 openssl 做 ES256 签名，不安装第三方包，
也不打印私钥或 JWT。用法见 scripts/asc/README.md。
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

API_ROOT = "https://api.appstoreconnect.apple.com"
USER_AGENT = "tingye-xcode-cloud/1.0"
TOKEN_TTL_SECONDS = 10 * 60
MAX_PAGES = 25
TIMEOUT_SECONDS = 60

# 听页在 App Store Connect / Xcode Cloud 上的已知 ID。能向接口查到时以接口为准。
DEFAULT_APP_ID = "6808449893"
DEFAULT_PRODUCT_ID = "3cbe429b-609e-4432-b6f5-e16445a60b01"
DEFAULT_TEAM_ID = "f8e71983-075b-4048-a3e7-772dc41ae2c5"
DEFAULT_PRODUCT_NAME = "Tingye"
DEFAULT_WORKFLOW_NAME = "Tests"
DEFAULT_BRANCH = "main"

UUID_RE = re.compile(
    r"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"
)
SHA_RE = re.compile(r"[0-9a-fA-F]{40}|[0-9a-fA-F]{64}")
PEM_RE = re.compile(
    r"-----BEGIN [A-Z ]*PRIVATE KEY-----.*?-----END [A-Z ]*PRIVATE KEY-----",
    re.S,
)

ISSUE_LABELS = (
    ("errors", "错误"),
    ("testFailures", "测试失败"),
    ("warnings", "警告"),
    ("analyzerWarnings", "分析警告"),
)


class CliError(Exception):
    def __init__(self, message: str, code: int = 1):
        super().__init__(message)
        self.code = code


class ApiError(CliError):
    def __init__(self, message: str, status: int):
        super().__init__(message)
        self.status = status


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def redact(text: str) -> str:
    text = PEM_RE.sub("[redacted-private-key]", text)
    return re.sub(r"Bearer\s+\S+", "Bearer [redacted-token]", text)


def _read_der_length(data: bytes, index: int) -> tuple[int, int]:
    if index >= len(data):
        raise CliError("openssl 返回的 ECDSA 签名无法解析。")
    first = data[index]
    index += 1
    if first < 0x80:
        return first, index
    count = first & 0x7F
    if count == 0 or count > 2 or index + count > len(data):
        raise CliError("openssl 返回的 ECDSA 签名无法解析。")
    return int.from_bytes(data[index:index + count], "big"), index + count


def _read_der_int(data: bytes, index: int) -> tuple[bytes, int]:
    if index >= len(data) or data[index] != 0x02:
        raise CliError("openssl 返回的 ECDSA 签名无法解析。")
    length, index = _read_der_length(data, index + 1)
    if length < 1 or index + length > len(data):
        raise CliError("openssl 返回的 ECDSA 签名无法解析。")
    raw = data[index:index + length].lstrip(b"\x00")
    if len(raw) > 32:
        raise CliError("openssl 返回的 ECDSA 签名无法解析。")
    return raw.rjust(32, b"\x00"), index + length


def der_to_raw(der: bytes) -> bytes:
    """把 openssl 的 DER ECDSA 签名转成 JWT ES256 需要的 R‖S（各 32 字节）。"""
    if not der or der[0] != 0x30:
        raise CliError("openssl 返回的 ECDSA 签名无法解析。")
    seq_len, index = _read_der_length(der, 1)
    if index + seq_len > len(der):
        raise CliError("openssl 返回的 ECDSA 签名无法解析。")
    r_bytes, index = _read_der_int(der, index)
    s_bytes, index = _read_der_int(der, index)
    return r_bytes + s_bytes


def validate_base_url(raw: str) -> str:
    parsed = urllib.parse.urlparse(raw.strip())
    if parsed.username or parsed.password:
        raise CliError("API 地址不能包含用户名或密码。")
    host = parsed.hostname or ""
    if parsed.scheme == "https" and host:
        return raw.rstrip("/")
    if parsed.scheme == "http" and host in {"127.0.0.1", "localhost"}:
        return raw.rstrip("/")
    raise CliError("API 地址必须是 https。只有本机测试可以使用 http://127.0.0.1。")


def resolve_base_url(environ: dict[str, str] | None = None) -> str:
    source = os.environ if environ is None else environ
    raw = (source.get("APP_STORE_CONNECT_API_BASE") or API_ROOT).strip() or API_ROOT
    return validate_base_url(raw)


def _private_key_file() -> tuple[str, str | None]:
    """返回 (路径, 用完后要删除的临时路径)。文件路径优先，正文不会被打印。"""
    path = os.environ.get("APP_STORE_CONNECT_PRIVATE_KEY_PATH", "").strip()
    if path:
        file = Path(path)
        if not file.is_file():
            raise CliError(f"找不到私钥文件：{path}")
        if not os.access(file, os.R_OK):
            raise CliError(f"无法读取私钥文件：{path}")
        if file.stat().st_mode & 0o077:
            print("注意: 私钥文件不只有所有者可读。建议 chmod 600。脚本不会打印密钥内容。", file=sys.stderr)
        return str(file), None

    inline = os.environ.get("APP_STORE_CONNECT_PRIVATE_KEY", "").strip()
    if "PRIVATE KEY" not in inline:
        raise CliError("APP_STORE_CONNECT_PRIVATE_KEY 不是 PEM 私钥。请改用 APP_STORE_CONNECT_PRIVATE_KEY_PATH。")
    fd, name = tempfile.mkstemp(prefix="asc-key-", suffix=".pem")
    try:
        payload = inline if inline.endswith("\n") else inline + "\n"
        os.write(fd, payload.encode("utf-8"))
        os.fchmod(fd, 0o600)
    except Exception:
        os.close(fd)
        os.unlink(name)
        raise
    os.close(fd)
    return name, name


def es256_sign(message: bytes) -> bytes:
    openssl = shutil.which("openssl")
    if not openssl:
        raise CliError("找不到 openssl。ES256 签名使用系统 openssl，不需要 pip 包。")
    key_path, cleanup = _private_key_file()
    try:
        proc = subprocess.run(
            [openssl, "dgst", "-sha256", "-sign", key_path],
            input=message,
            capture_output=True,
            check=False,
        )
        if proc.returncode != 0 or not proc.stdout:
            raise CliError("ES256 签名失败。请确认 .p8 是 App Store Connect 的私钥，并且 openssl 可以读取。")
        return der_to_raw(proc.stdout)
    finally:
        if cleanup:
            try:
                os.unlink(cleanup)
            except OSError:
                pass


def build_jwt(issuer_id: str, key_id: str, now: int | None = None) -> str:
    """按 Apple 的 App Store Connect 文档签 Team Key：ES256，aud=appstoreconnect-v1。"""
    issued = int(time.time() if now is None else now)
    header = {"alg": "ES256", "kid": key_id, "typ": "JWT"}
    payload = {
        "iss": issuer_id,
        "iat": issued,
        "exp": issued + TOKEN_TTL_SECONDS,
        "aud": "appstoreconnect-v1",
    }
    signing_input = ".".join((
        b64url(json.dumps(header, separators=(",", ":")).encode("utf-8")),
        b64url(json.dumps(payload, separators=(",", ":")).encode("utf-8")),
    ))
    signature = es256_sign(signing_input.encode("ascii"))
    return signing_input + "." + b64url(signature)


def require_key_names() -> tuple[str, str]:
    issuer = os.environ.get("APP_STORE_CONNECT_ISSUER_ID", "").strip()
    key_id = os.environ.get("APP_STORE_CONNECT_KEY_ID", "").strip()
    has_key = bool(os.environ.get("APP_STORE_CONNECT_PRIVATE_KEY_PATH", "").strip()
                   or os.environ.get("APP_STORE_CONNECT_PRIVATE_KEY", "").strip())
    missing = []
    if not issuer:
        missing.append("APP_STORE_CONNECT_ISSUER_ID")
    if not key_id:
        missing.append("APP_STORE_CONNECT_KEY_ID")
    if not has_key:
        missing.append("APP_STORE_CONNECT_PRIVATE_KEY_PATH 或 APP_STORE_CONNECT_PRIVATE_KEY")
    if missing:
        raise CliError("缺少环境变量：" + "、".join(missing), code=2)
    return issuer, key_id


def make_client() -> "Client":
    issuer, key_id = require_key_names()
    return Client(resolve_base_url(), build_jwt(issuer, key_id))


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise CliError(f"API 返回了重定向 {code}，已停止，不会把令牌带到其他地址。")


class Client:
    def __init__(self, base: str, token: str):
        self.base = base.rstrip("/")
        self._token = token
        self._opener = urllib.request.build_opener(_NoRedirect)

    def __repr__(self) -> str:
        return f"<Client {self.base}>"

    def _prepare_url(self, path: str, query: dict | None) -> str:
        if path.startswith("https://") or path.startswith("http://"):
            self._ensure_same_host(path)
            url = path
        elif path.startswith("/"):
            url = self.base + path
        else:
            raise CliError("接口路径无效。")
        encoded = _encode_query(query)
        if encoded:
            url += ("&" if "?" in url else "?") + encoded
        return url

    def _ensure_same_host(self, url: str) -> None:
        target = urllib.parse.urlparse(url)
        base = urllib.parse.urlparse(self.base)
        if target.username or target.password:
            raise CliError("分页链接包含用户信息，已停止。")
        if (target.scheme, (target.hostname or "").lower(), target.port) != (
            base.scheme, (base.hostname or "").lower(), base.port,
        ):
            raise CliError("分页链接指向了其他主机，已停止。")

    def request(self, method: str, path: str, query: dict | None = None, body: dict | None = None) -> dict:
        url = self._prepare_url(path, query)
        data = None
        if body is not None:
            data = json.dumps(body, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
        raw = b""
        status = 0
        headers = None
        for attempt in range(2):
            req = urllib.request.Request(url, data=data, method=method)
            req.add_header("Authorization", "Bearer " + self._token)
            req.add_header("Accept", "application/json")
            req.add_header("User-Agent", USER_AGENT)
            if data is not None:
                req.add_header("Content-Type", "application/json")
            try:
                with self._opener.open(req, timeout=TIMEOUT_SECONDS) as response:
                    status = getattr(response, "status", response.getcode())
                    raw = response.read()
                    headers = response.headers
            except urllib.error.HTTPError as exc:
                status = exc.code
                raw = exc.read()
                headers = exc.headers
            except urllib.error.URLError as exc:
                raise CliError(f"连不上 App Store Connect API：{exc.reason}") from None
            delay = _retry_delay(headers)
            if status == 429 and method == "GET" and attempt == 0 and delay is not None:
                time.sleep(delay)
                continue
            break
        text = raw.decode("utf-8", "replace")
        parsed = None
        if text:
            try:
                parsed = json.loads(text)
            except json.JSONDecodeError:
                parsed = None
        if status >= 400 or not isinstance(parsed, dict):
            raise ApiError(_format_api_error(status, parsed, text), status)
        return parsed

    def get_one(self, path: str, query: dict | None = None) -> tuple[dict, list]:
        payload = self.request("GET", path, query=query)
        data = payload.get("data")
        if not isinstance(data, dict) or not data.get("id"):
            raise CliError(f"接口没有返回资源：{path}")
        included = payload.get("included") or []
        return data, included if isinstance(included, list) else []

    def get_collection(self, path: str, query: dict | None = None, stop_after=None) -> tuple[list, list, bool]:
        items: list = []
        included: list = []
        seen: set[tuple] = set()
        truncated = False
        url = path
        current_query = query
        for page_index in range(MAX_PAGES):
            payload = self.request("GET", url, query=current_query)
            data = payload.get("data") or []
            if isinstance(data, dict):
                data = [data]
            if not isinstance(data, list):
                raise CliError("接口返回的列表无法读取。")
            for item in data:
                if not isinstance(item, dict):
                    continue
                key = (item.get("type"), item.get("id"))
                if item.get("id") and key in seen:
                    continue
                if item.get("id"):
                    seen.add(key)
                items.append(item)
            extra = payload.get("included") or []
            if isinstance(extra, list):
                included.extend(item for item in extra if isinstance(item, dict))
            if stop_after and stop_after(data):
                break
            nxt = str((payload.get("links") or {}).get("next") or "").strip()
            if not nxt:
                break
            if page_index == MAX_PAGES - 1:
                truncated = True
                break
            url = self._normalize_next(nxt)
            current_query = None
        return items, included, truncated

    def _normalize_next(self, nxt: str) -> str:
        if nxt.startswith("/"):
            resolved = self.base + nxt
        elif nxt.startswith("https://") or nxt.startswith("http://"):
            resolved = nxt
        else:
            raise CliError("分页链接无效。")
        self._ensure_same_host(resolved)
        return resolved


def _encode_query(query: dict | None) -> str:
    if not query:
        return ""
    parts = []
    for key, value in query.items():
        if value is None:
            continue
        parts.append(
            urllib.parse.quote(str(key), safe="[]") + "=" + urllib.parse.quote(str(value), safe=",")
        )
    return "&".join(parts)


def _retry_delay(headers) -> int | None:
    if headers is None:
        return 1
    raw = headers.get("Retry-After")
    if raw is None:
        return 1
    if str(raw).isdigit() and int(raw) <= 30:
        return int(raw)
    return None


def _format_api_error(status: int, payload, raw_text: str) -> str:
    errors = payload.get("errors") if isinstance(payload, dict) else None
    if isinstance(errors, list) and errors:
        parts = []
        for item in errors[:5]:
            if not isinstance(item, dict):
                continue
            bits = [str(status)]
            for key in ("code", "title", "detail"):
                if item.get(key):
                    bits.append(str(item[key]))
            parts.append(" ".join(bits))
        if parts:
            return "App Store Connect API：" + "；".join(parts)
    snippet = redact(raw_text).replace("\n", " ").strip()[:300]
    suffix = f" {snippet}" if snippet else ""
    return f"App Store Connect API 返回 HTTP {status}。{suffix}".rstrip()


def resource_attributes(resource: dict) -> dict:
    value = resource.get("attributes") or {}
    return value if isinstance(value, dict) else {}


def relationship_id(resource: dict, name: str) -> str | None:
    data = ((resource.get("relationships") or {}).get(name) or {}).get("data")
    if isinstance(data, dict) and data.get("id"):
        return str(data["id"])
    return None


def find_included(included: list, type_name: str, resource_id: str | None) -> dict | None:
    if not resource_id:
        return None
    for item in included:
        if item.get("type") == type_name and item.get("id") == resource_id:
            return item
    return None


def match_name(resources: list, name: str) -> list:
    exact = [item for item in resources if resource_attributes(item).get("name") == name]
    if exact:
        return exact
    folded = name.casefold()
    return [
        item for item in resources
        if str(resource_attributes(item).get("name") or "").casefold() == folded
    ]


def describe_patterns(condition) -> str:
    if not isinstance(condition, dict):
        return "未设置"
    source = condition.get("source") or {}
    if not isinstance(source, dict):
        return "未设置"
    if source.get("isAllMatch"):
        return "全部"
    parts = []
    for item in source.get("patterns") or []:
        if not isinstance(item, dict) or not item.get("pattern"):
            continue
        text = str(item["pattern"])
        if item.get("isPrefix"):
            text += "（前缀）"
        parts.append(text)
    return "、".join(parts) if parts else "未设置"


def reference_matches(condition, name: str) -> bool | None:
    if not isinstance(condition, dict):
        return None
    source = condition.get("source") or {}
    if not isinstance(source, dict):
        return None
    if source.get("isAllMatch"):
        return True
    matched = False
    saw_pattern = False
    for item in source.get("patterns") or []:
        if not isinstance(item, dict):
            continue
        pattern = str(item.get("pattern") or "")
        if not pattern:
            continue
        saw_pattern = True
        if item.get("isPrefix"):
            matched = matched or name.startswith(pattern)
        else:
            matched = matched or name == pattern
    if not saw_pattern:
        return False
    return matched


def _named_list(resources: list) -> str:
    parts = []
    for item in resources[:20]:
        parts.append(f"{resource_attributes(item).get('name') or '（无名称）'} ({item.get('id')})")
    return "、".join(parts) if parts else "无"


def resolve_product(client: Client, args) -> tuple[dict, str]:
    if args.product_id:
        product, _ = client.get_one(f"/v1/ciProducts/{args.product_id}")
        return product, "使用 --product-id"
    found, _, _ = client.get_collection(
        "/v1/ciProducts",
        {"filter[app]": args.app_id, "limit": "200"},
    )
    chosen, how = _pick_product(found, args.product_name)
    if chosen:
        return chosen, how
    if args.app_id != DEFAULT_APP_ID:
        raise CliError(f"App {args.app_id} 下没有 Xcode Cloud 产品。")
    product, _ = client.get_one(f"/v1/ciProducts/{DEFAULT_PRODUCT_ID}")
    return product, "App 下没有返回产品，改用默认产品 ID"


def _pick_product(products: list, name: str) -> tuple[dict | None, str]:
    if not products:
        return None, ""
    matches = match_name(products, name)
    if len(matches) == 1:
        return matches[0], "按 App 查询"
    if len(matches) > 1:
        raise CliError(f"有多个名为「{name}」的产品：{_named_list(matches)}")
    known = [item for item in products if item.get("id") == DEFAULT_PRODUCT_ID]
    if len(known) == 1:
        return known[0], "按 App 查询，名称不同，使用已知产品 ID"
    if len(products) == 1:
        return products[0], "按 App 查询，该 App 只有一个产品"
    raise CliError(
        f"App 下有多个产品，没有名为「{name}」的。请用 --product-id 指定。\n{_named_list(products)}"
    )


def resolve_workflow(client: Client, product_id: str, name: str) -> tuple[dict, dict | None]:
    items, included, truncated = client.get_collection(
        f"/v1/ciProducts/{product_id}/workflows",
        {"limit": "200", "include": "repository"},
    )
    matches = match_name(items, name)
    if len(matches) != 1:
        extra = "，结果被截断" if truncated else ""
        raise CliError(f"没有唯一的工作流「{name}」。接口返回：{_named_list(items)}{extra}")
    workflow = matches[0]
    repo_id = relationship_id(workflow, "repository")
    repo = find_included(included, "scmRepositories", repo_id)
    if repo_id and repo is None:
        repo, _ = client.get_one(f"/v1/scmRepositories/{repo_id}")
    if repo_id is None:
        repo = _primary_repository(client, product_id)
    return workflow, repo


def _primary_repository(client: Client, product_id: str) -> dict:
    items, _, _ = client.get_collection(
        f"/v1/ciProducts/{product_id}/primaryRepositories",
        {"limit": "20"},
    )
    if len(items) == 1:
        return items[0]
    if not items:
        raise CliError("工作流没有关联仓库，产品也没有主仓库，无法选择分支或标签。")
    names = "、".join(
        f"{resource_attributes(item).get('repositoryName') or item.get('id')} ({item.get('id')})"
        for item in items[:10]
    )
    raise CliError(f"工作流没有关联仓库，主仓库有多个：{names}")


def fetch_app(client: Client, app_id: str) -> dict:
    try:
        data, _ = client.get_one(f"/v1/apps/{app_id}")
    except ApiError as exc:
        if exc.status in (401, 403):
            raise
        print(f"注意: 没能读取 App {app_id}：{exc}", file=sys.stderr)
        return {"id": app_id, "name": None, "bundleId": None}
    info = resource_attributes(data)
    return {"id": data.get("id") or app_id, "name": info.get("name"), "bundleId": info.get("bundleId")}


def lookup_document(client: Client, args) -> dict:
    app = fetch_app(client, args.app_id)
    product, source = resolve_product(client, args)
    workflow, repo = resolve_workflow(client, product["id"], args.workflow)
    info = resource_attributes(workflow)
    repo_info = resource_attributes(repo) if repo else {}
    manual_branch = info.get("manualBranchStartCondition")
    return {
        "teamId": DEFAULT_TEAM_ID,
        "teamIdSource": "script-default",
        "app": app,
        "product": {
            "id": product.get("id"),
            "name": resource_attributes(product).get("name"),
            "productType": resource_attributes(product).get("productType"),
            "source": source,
        },
        "workflow": {
            "id": workflow.get("id"),
            "name": info.get("name"),
            "isEnabled": info.get("isEnabled"),
            "manualBranchStart": describe_patterns(manual_branch),
            "manualTagStart": describe_patterns(info.get("manualTagStartCondition")),
            "manualBranchMatchesMain": reference_matches(manual_branch, DEFAULT_BRANCH),
        },
        "repository": None if repo is None else {
            "id": repo.get("id"),
            "ownerName": repo_info.get("ownerName"),
            "repositoryName": repo_info.get("repositoryName"),
        },
    }


def render_lookup(document: dict) -> str:
    product = document["product"]
    workflow = document["workflow"]
    app = document["app"]
    repo = document.get("repository") or {}
    enabled = "已启用" if workflow.get("isEnabled") else "未启用"
    if workflow.get("isEnabled") is None:
        enabled = "启用状态未知"
    app_name = f"  {app['name']}" if app.get("name") else ""
    repo_line = "仓库: 没有关联仓库"
    if repo:
        owner = repo.get("ownerName") or ""
        name = repo.get("repositoryName") or ""
        label = "/".join(part for part in (owner, name) if part) or "（名称未返回）"
        repo_line = f"仓库: {repo.get('id')}  {label}"
    main_state = {True: "包含 main", False: "不包含 main", None: "无法判断"}[
        workflow.get("manualBranchMatchesMain")
    ]
    lines = [
        "听页 Xcode Cloud",
        f"团队 ID（脚本默认值，接口不返回）: {document['teamId']}",
        f"App: {app.get('id')}{app_name}",
        f"产品: {product.get('id')}  {product.get('name') or '（无名称）'}  （{product.get('source')}）",
        f"工作流: {workflow.get('id')}  {workflow.get('name')}  {enabled}",
        repo_line,
        f"手动启动分支: {workflow.get('manualBranchStart')}（{main_state}）",
        f"手动启动标签: {workflow.get('manualTagStart')}",
    ]
    return "\n".join(lines)


def _same_number(value, wanted: int) -> bool:
    try:
        return int(value) == wanted
    except (TypeError, ValueError):
        return False


def _page_is_past_number(items: list, target: int) -> bool:
    numbers = []
    for item in items:
        try:
            numbers.append(int(resource_attributes(item).get("number")))
        except (TypeError, ValueError):
            continue
    if not numbers:
        return False
    return numbers == sorted(numbers, reverse=True) and max(numbers) < target


def find_run_by_number(client: Client, product_id: str, number: int) -> dict:
    def stop_after(page: list) -> bool:
        if any(_same_number(resource_attributes(item).get("number"), number) for item in page):
            return True
        return _page_is_past_number(page, number)

    items, _, truncated = client.get_collection(
        f"/v1/ciProducts/{product_id}/buildRuns",
        {"limit": "200", "sort": "-number"},
        stop_after=stop_after,
    )
    for item in items:
        if _same_number(resource_attributes(item).get("number"), number):
            return item
    extra = "已读完的页里没有更早的构建。" if not truncated else "列表被截断。"
    raise CliError(f"产品 {product_id} 没有编号 {number} 的构建。{extra}请改用 ciBuildRun ID。")


def _issue_text(issue: dict) -> dict:
    info = resource_attributes(issue)
    source = info.get("fileSource") if isinstance(info.get("fileSource"), dict) else {}
    return {
        "issueType": info.get("issueType"),
        "message": info.get("message"),
        "path": source.get("path") or source.get("filePath"),
        "lineNumber": source.get("lineNumber"),
    }


def _needs_issues(info: dict) -> bool:
    if info.get("completionStatus") in {"FAILED", "ERRORED"}:
        return True
    counts = info.get("issueCounts") if isinstance(info.get("issueCounts"), dict) else {}
    return any(counts.get(key) for key, _label in ISSUE_LABELS)


def _load_issues(client: Client, action_id: str) -> tuple[list, bool, str | None]:
    try:
        payload = client.request("GET", f"/v1/ciBuildActions/{action_id}/issues", {"limit": "15"})
    except ApiError as exc:
        if exc.status == 404:
            return [], False, None
        return [], False, str(exc)
    data = payload.get("data") or []
    if not isinstance(data, list):
        return [], False, "问题列表无法读取。"
    issues = [_issue_text(item) for item in data if isinstance(item, dict)]
    truncated = bool((payload.get("links") or {}).get("next")) or len(issues) >= 15
    return issues[:8], truncated and len(issues) > 8, None


def _action_document(client: Client, action: dict) -> dict:
    info = resource_attributes(action)
    issues: list = []
    truncated = False
    error = None
    if action.get("id") and _needs_issues(info):
        issues, truncated, error = _load_issues(client, action["id"])
    return {
        "id": action.get("id"),
        "name": info.get("name"),
        "actionType": info.get("actionType"),
        "executionProgress": info.get("executionProgress"),
        "completionStatus": info.get("completionStatus"),
        "isRequiredToPass": info.get("isRequiredToPass"),
        "startedDate": info.get("startedDate"),
        "finishedDate": info.get("finishedDate"),
        "issueCounts": info.get("issueCounts") if isinstance(info.get("issueCounts"), dict) else None,
        "issues": issues,
        "issuesTruncated": truncated,
        "issuesError": error,
    }


def _build_document(build: dict) -> dict:
    info = resource_attributes(build)
    return {
        "id": build.get("id"),
        "version": info.get("version"),
        "processingState": info.get("processingState"),
        "buildAudienceType": info.get("buildAudienceType"),
        "uploadedDate": info.get("uploadedDate"),
        "expired": info.get("expired"),
    }


def _best_effort_collection(client: Client, path: str) -> tuple[list, str | None]:
    try:
        items, _, truncated = client.get_collection(path, {"limit": "200"})
    except ApiError as exc:
        return [], str(exc)
    if truncated:
        return items, "结果被截断。"
    return items, None


def _load_related_name(client: Client, resource_id: str | None, included: list, type_name: str, path: str) -> dict | None:
    found = find_included(included, type_name, resource_id)
    if found or not resource_id:
        return found
    try:
        data, _ = client.get_one(path.format(id=resource_id))
    except ApiError:
        return None
    return data


def status_document(client: Client, args) -> dict:
    kind, value = _parse_selector(args.selector)
    if kind == "number":
        product, _source = resolve_product(client, args)
        run = find_run_by_number(client, product["id"], value)
        run, workflow_included, product_included = _refetch_run(client, run["id"])
    else:
        run, workflow_included, product_included = _refetch_run(client, value)
    actions, actions_error = _best_effort_collection(client, f"/v1/ciBuildRuns/{run['id']}/actions")
    builds, builds_error = _best_effort_collection(client, f"/v1/ciBuildRuns/{run['id']}/builds")
    action_docs = [_action_document(client, item) for item in actions]
    build_docs = [_build_document(item) for item in builds]
    info = resource_attributes(run)
    commit = info.get("sourceCommit") if isinstance(info.get("sourceCommit"), dict) else None
    workflow = resource_attributes(workflow_included) if workflow_included else {}
    product = resource_attributes(product_included) if product_included else {}
    return {
        "id": run.get("id"),
        "number": info.get("number"),
        "executionProgress": info.get("executionProgress"),
        "completionStatus": info.get("completionStatus"),
        "startReason": info.get("startReason"),
        "cancelReason": info.get("cancelReason"),
        "isPullRequestBuild": info.get("isPullRequestBuild"),
        "createdDate": info.get("createdDate"),
        "startedDate": info.get("startedDate"),
        "finishedDate": info.get("finishedDate"),
        "sourceCommit": None if commit is None else {
            "commitSha": commit.get("commitSha"),
            "message": commit.get("message"),
            "webUrl": commit.get("webUrl"),
            "author": (commit.get("author") or {}).get("displayName") if isinstance(commit.get("author"), dict) else None,
        },
        "workflow": {"id": relationship_id(run, "workflow"), "name": workflow.get("name")},
        "product": {"id": relationship_id(run, "product"), "name": product.get("name")},
        "actions": action_docs,
        "actionsError": actions_error,
        "testflight": build_docs,
        "testflightError": builds_error,
        "summary": {
            "test": _action_summary(action_docs, "TEST"),
            "archive": _action_summary(action_docs, "ARCHIVE"),
            "testflight": _testflight_summary(build_docs, builds_error),
        },
    }


def _refetch_run(client: Client, run_id: str) -> tuple[dict, dict | None, dict | None]:
    payload = client.request("GET", f"/v1/ciBuildRuns/{run_id}", {"include": "workflow,product"})
    run = payload.get("data")
    if not isinstance(run, dict) or not run.get("id"):
        raise CliError("接口没有返回这次构建。")
    included = payload.get("included") or []
    if not isinstance(included, list):
        included = []
    workflow = _load_related_name(
        client, relationship_id(run, "workflow"), included, "ciWorkflows", "/v1/ciWorkflows/{id}",
    )
    product = _load_related_name(
        client, relationship_id(run, "product"), included, "ciProducts", "/v1/ciProducts/{id}",
    )
    return run, workflow, product


def _parse_selector(text: str) -> tuple[str, str | int]:
    raw = text.strip()
    if UUID_RE.fullmatch(raw):
        return "id", raw
    if raw.isdigit():
        return "number", int(raw)
    raise CliError("请传入 ciBuildRun ID，或构建编号。例如 c7f15f14-fde2-49bc-aeb9-2398aec480c8 或 159。")


def _state_text(item: dict) -> str:
    return str(item.get("completionStatus") or item.get("executionProgress") or "—")


def _action_summary(actions: list, action_type: str) -> str:
    chosen = [item for item in actions if item.get("actionType") == action_type]
    label = "Test" if action_type == "TEST" else "Archive"
    if not chosen:
        return f"这次构建没有 {label} 动作"
    return "；".join(f"{item.get('name') or label} {_state_text(item)}" for item in chosen)


def _testflight_summary(builds: list, error: str | None) -> str:
    if error:
        return "获取失败"
    if not builds:
        return "还没有关联的 TestFlight build"
    parts = []
    for item in builds:
        bits = [str(item.get("id"))]
        if item.get("version"):
            bits.append(f"版本 {item['version']}")
        if item.get("processingState"):
            bits.append(str(item["processingState"]))
        if item.get("buildAudienceType"):
            bits.append(str(item["buildAudienceType"]))
        parts.append(" ".join(bits))
    return "；".join(parts)


def _format_counts(counts: dict | None) -> str:
    if not counts:
        return ""
    parts = [f"{label} {counts[key]}" for key, label in ISSUE_LABELS if counts.get(key)]
    return "，".join(parts)


def render_status(document: dict) -> str:
    title = f"构建 {document.get('id')}"
    if document.get("number") is not None:
        title += f"  #{document['number']}"
    lines = [title]
    workflow = document.get("workflow") or {}
    product = document.get("product") or {}
    if workflow.get("name") or workflow.get("id"):
        lines.append(f"工作流: {workflow.get('name') or ''} {workflow.get('id') or ''}".rstrip())
    if product.get("name") or product.get("id"):
        lines.append(f"产品: {product.get('name') or ''} {product.get('id') or ''}".rstrip())
    lines.append(
        f"进度: {document.get('executionProgress') or '—'}    "
        f"结果: {document.get('completionStatus') or '—'}    "
        f"原因: {document.get('startReason') or '—'}"
    )
    if document.get("cancelReason"):
        lines.append(f"取消原因: {document['cancelReason']}")
    if document.get("isPullRequestBuild"):
        lines.append("这是 Pull Request 构建。")
    commit = document.get("sourceCommit") or {}
    if commit:
        message = str(commit.get("message") or "").splitlines()
        first = message[0] if message else ""
        lines.append(f"提交: {commit.get('commitSha') or '—'}  {first}".rstrip())
        if commit.get("webUrl"):
            lines.append(str(commit["webUrl"]))
    for label, key in (("创建", "createdDate"), ("开始", "startedDate"), ("结束", "finishedDate")):
        if document.get(key):
            lines.append(f"{label}: {document[key]}")
    lines.append("")
    lines.append("动作")
    if document.get("actionsError"):
        lines.append(f"  获取失败: {document['actionsError']}")
    elif not document.get("actions"):
        lines.append("  （没有动作）")
    for action in document.get("actions") or []:
        counts = _format_counts(action.get("issueCounts"))
        suffix = f"  {counts}" if counts else ""
        lines.append(
            f"  {str(action.get('actionType') or '—'):<8} "
            f"{action.get('name') or '（无名称）'}  {_state_text(action)}{suffix}"
        )
        if action.get("issuesError"):
            lines.append(f"    问题列表获取失败: {action['issuesError']}")
        for issue in action.get("issues") or []:
            where = ""
            if issue.get("path"):
                where = str(issue["path"])
                if issue.get("lineNumber"):
                    where += f":{issue['lineNumber']}"
                where = "  " + where
            lines.append(f"    - {issue.get('issueType') or '问题'} {issue.get('message') or ''}{where}".rstrip())
        if action.get("issuesTruncated"):
            lines.append("    - 还有更多问题未列出。")
    lines.append("")
    lines.append("TestFlight")
    if document.get("testflightError"):
        lines.append(f"  获取失败: {document['testflightError']}")
    elif not document.get("testflight"):
        lines.append("  还没有关联的 build。Archive 上传完成后，这里会显示 TestFlight 处理状态。")
    else:
        for build in document["testflight"]:
            bits = [str(build.get("id"))]
            if build.get("version"):
                bits.append(f"版本 {build['version']}")
            if build.get("processingState"):
                bits.append(f"处理 {build['processingState']}")
            if build.get("buildAudienceType"):
                bits.append(f"受众 {build['buildAudienceType']}")
            if build.get("expired"):
                bits.append("已过期")
            lines.append("  " + "  ".join(bits))
    summary = document["summary"]
    lines.extend([
        "",
        "摘要",
        f"  Test: {summary['test']}",
        f"  Archive: {summary['archive']}",
        f"  TestFlight: {summary['testflight']}",
    ])
    return "\n".join(lines)


def reject_commit_sha(name: str) -> None:
    if SHA_RE.fullmatch(name or ""):
        raise CliError("API 选择的是 Git 分支或标签，不能是提交 SHA。请传分支名，例如 main。")


def selected_reference(args) -> tuple[str, str]:
    branch = (args.branch or "").strip()
    tag = (args.tag or "").strip()
    if branch and tag:
        raise CliError("不能同时指定 --branch 和 --tag。")
    if tag:
        reject_commit_sha(tag)
        return "TAG", tag
    name = branch or DEFAULT_BRANCH
    reject_commit_sha(name)
    return "BRANCH", name


def find_git_reference(client: Client, repo_id: str, name: str, kind: str) -> dict:
    items, _, truncated = client.get_collection(
        f"/v1/scmRepositories/{repo_id}/gitReferences",
        {"limit": "200"},
    )
    canonical = f"refs/heads/{name}" if kind == "BRANCH" else f"refs/tags/{name}"
    matches = []
    for item in items:
        info = resource_attributes(item)
        if info.get("isDeleted") or info.get("kind") != kind:
            continue
        if info.get("name") == name or info.get("canonicalName") == canonical:
            matches.append(item)
    if len(matches) == 1:
        return matches[0]
    label = "分支" if kind == "BRANCH" else "标签"
    if len(matches) > 1:
        ids = "、".join(str(item.get("id")) for item in matches)
        raise CliError(f"有多个同名{label}「{name}」：{ids}")
    names = []
    for item in items:
        info = resource_attributes(item)
        if info.get("isDeleted") or info.get("kind") != kind or not info.get("name"):
            continue
        names.append(str(info["name"]))
        if len(names) >= 15:
            break
    hint = "、".join(names) if names else "无"
    extra = "（已读取的页被截断）" if truncated else ""
    raise CliError(f"仓库里没有{label}「{name}」{extra}。API 只能选择分支或标签，不能选择提交 SHA。附近的{label}：{hint}")


def _warn_manual_start(workflow: dict, kind: str, name: str) -> None:
    key = "manualBranchStartCondition" if kind == "BRANCH" else "manualTagStartCondition"
    condition = resource_attributes(workflow).get(key)
    if reference_matches(condition, name) is True:
        return
    label = "分支" if kind == "BRANCH" else "标签"
    print(
        f"注意: 工作流的手动启动{label}条件是「{describe_patterns(condition)}」，与 {name} 不一定相符。"
        f"请求仍会提交；Apple 可能拒绝。API 启动的构建按手动构建处理。",
        file=sys.stderr,
    )


def start_document(client: Client, args) -> dict:
    kind, name = selected_reference(args)
    product, _source = resolve_product(client, args)
    workflow, repo = resolve_workflow(client, product["id"], args.workflow)
    if resource_attributes(workflow).get("isEnabled") is False:
        raise CliError(f"工作流「{args.workflow}」已停用，没有发送启动请求。")
    if repo is None or not repo.get("id"):
        raise CliError("没有仓库，无法把分支或标签解析成 Git 引用。")
    _warn_manual_start(workflow, kind, name)
    git_ref = find_git_reference(client, repo["id"], name, kind)
    # Apple 的创建请求关联的是 scmGitReferences，不是 commit SHA。
    # 见 WWDC24 session 10200：workflow + sourceBranchOrTag。
    request_body = {
        "data": {
            "type": "ciBuildRuns",
            "relationships": {
                "workflow": {"data": {"type": "ciWorkflows", "id": workflow["id"]}},
                "sourceBranchOrTag": {"data": {"type": "scmGitReferences", "id": git_ref["id"]}},
            },
        }
    }
    created = None
    if not args.dry_run:
        payload = client.request("POST", "/v1/ciBuildRuns", body=request_body)
        data = payload.get("data")
        if not isinstance(data, dict) or not data.get("id"):
            raise CliError("启动请求已发送，但响应里没有新的 ciBuildRun。")
        info = resource_attributes(data)
        created = {
            "id": data.get("id"),
            "number": info.get("number"),
            "executionProgress": info.get("executionProgress"),
            "completionStatus": info.get("completionStatus"),
            "startReason": info.get("startReason"),
        }
    ref_info = resource_attributes(git_ref)
    return {
        "dryRun": bool(args.dry_run),
        "kind": kind,
        "name": name,
        "product": {"id": product.get("id"), "name": resource_attributes(product).get("name")},
        "workflow": {"id": workflow.get("id"), "name": resource_attributes(workflow).get("name")},
        "repository": {"id": repo.get("id")},
        "gitReference": {
            "id": git_ref.get("id"),
            "name": ref_info.get("name"),
            "kind": ref_info.get("kind"),
            "canonicalName": ref_info.get("canonicalName"),
        },
        "request": request_body,
        "buildRun": created,
    }


def render_start(document: dict) -> str:
    kind_label = "分支" if document["kind"] == "BRANCH" else "标签"
    ref = document["gitReference"]
    lines = [
        "API 启动的构建按手动构建处理。选择的是 Git 引用，不是提交 SHA。",
        f"产品: {document['product'].get('name') or ''} {document['product'].get('id')}".rstrip(),
        f"工作流: {document['workflow'].get('name')}  {document['workflow'].get('id')}",
        f"{kind_label}: {document['name']}  →  {ref.get('id')}  {ref.get('canonicalName') or ref.get('name') or ''}".rstrip(),
    ]
    if document["dryRun"]:
        lines.append("未发送 POST /v1/ciBuildRuns。")
        lines.append(json.dumps(document["request"], ensure_ascii=False, indent=2))
        return "\n".join(lines)
    created = document.get("buildRun") or {}
    lines.append(
        f"已创建构建 {created.get('id')}  #{created.get('number') if created.get('number') is not None else '—'}"
        f"  进度 {created.get('executionProgress') or '—'}  原因 {created.get('startReason') or '—'}"
    )
    lines.append(f"查看状态: python3 scripts/asc/xcode_cloud.py status {created.get('id')}")
    return "\n".join(lines)


def emit(document: dict, as_json: bool, render) -> None:
    if as_json:
        print(json.dumps(document, ensure_ascii=False, indent=2))
        return
    text = render(document)
    print(text, end="" if text.endswith("\n") else "\n")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="xcode_cloud.py",
        description="查看和启动听页的 Xcode Cloud 构建（App Store Connect API）。",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "环境变量（不要把私钥写进仓库或命令示例）:\n"
            "  APP_STORE_CONNECT_ISSUER_ID\n"
            "  APP_STORE_CONNECT_KEY_ID\n"
            "  APP_STORE_CONNECT_PRIVATE_KEY_PATH    .p8 文件路径（优先）\n"
            "  APP_STORE_CONNECT_PRIVATE_KEY         可选，PEM 正文\n"
            "\n"
            "示例:\n"
            "  python3 scripts/asc/xcode_cloud.py lookup\n"
            "  python3 scripts/asc/xcode_cloud.py status c7f15f14-fde2-49bc-aeb9-2398aec480c8\n"
            "  python3 scripts/asc/xcode_cloud.py status 159\n"
            "  python3 scripts/asc/xcode_cloud.py start --branch main\n"
            "  python3 scripts/asc/xcode_cloud.py start --dry-run\n"
        ),
    )
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--app-id", default=DEFAULT_APP_ID, help=f"App Store Connect App ID，默认 {DEFAULT_APP_ID}")
    common.add_argument("--product-id", help=f"指定 ciProduct。不填则按 App 查询，查不到时用 {DEFAULT_PRODUCT_ID}")
    common.add_argument("--product-name", default=DEFAULT_PRODUCT_NAME, help=f"产品名称，默认 {DEFAULT_PRODUCT_NAME}")
    common.add_argument("--workflow", default=DEFAULT_WORKFLOW_NAME, help=f"工作流名称，默认 {DEFAULT_WORKFLOW_NAME}")
    common.add_argument("--json", action="store_true", help="把结果打印成 JSON")
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("lookup", parents=[common], help="查找 Tingye 产品和 Tests 工作流")
    status = sub.add_parser("status", parents=[common], help="查看一次 ciBuildRun 的状态、动作和 TestFlight")
    status.add_argument(
        "selector",
        help="ciBuildRun ID 或构建编号，例如 c7f15f14-fde2-49bc-aeb9-2398aec480c8 或 159",
    )
    start = sub.add_parser("start", parents=[common], help="为 Tests 工作流启动一次手动构建")
    start.add_argument("--branch", help=f"分支名，默认 {DEFAULT_BRANCH}。不能是提交 SHA。")
    start.add_argument("--tag", help="标签名。与 --branch 互斥。")
    start.add_argument("--dry-run", action="store_true", help="只解析 Git 引用并打印请求，不 POST")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        if args.command == "start":
            selected_reference(args)
        elif args.command == "status":
            _parse_selector(args.selector)
        client = make_client()
        if args.command == "lookup":
            emit(lookup_document(client, args), args.json, render_lookup)
        elif args.command == "status":
            emit(status_document(client, args), args.json, render_status)
        elif args.command == "start":
            emit(start_document(client, args), args.json, render_start)
        else:
            raise CliError(f"未知命令：{args.command}")
    except CliError as exc:
        print(f"错误: {exc}", file=sys.stderr)
        return exc.code
    return 0


if __name__ == "__main__":
    sys.exit(main())
