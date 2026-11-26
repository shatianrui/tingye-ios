"""本地检查 Xcode Cloud CLI。使用临时密钥和假接口，不访问 Apple，也不启动构建。"""

import base64
import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tempfile
import threading
import unittest
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = Path(__file__).with_name("xcode_cloud.py")

spec = importlib.util.spec_from_file_location("xcode_cloud", SCRIPT)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

ISSUER = "issuer-test"
KEY_ID = "KEYTEST"
APP_ID = mod.DEFAULT_APP_ID
PRODUCT_ID = mod.DEFAULT_PRODUCT_ID
TEAM_ID = mod.DEFAULT_TEAM_ID
WORKFLOW_ID = "11111111-2222-4333-8444-555555555555"
OTHER_WORKFLOW_ID = "22222222-2222-4333-8444-555555555555"
NIGHTLY_ID = "33333333-3333-4333-8333-333333333333"
REPO_ID = "99999999-8888-4777-8666-555555555555"
REF_ID = "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"
TAG_REF_ID = "bbbbbbbb-bbbb-4ccc-8ddd-eeeeeeeeeeee"
RUN_ID = "c7f15f14-fde2-49bc-aeb9-2398aec480c8"
ASC_BUILD_ID = "10000000-0000-4000-8000-000000000159"
CREATED_ID = "00000000-0000-4000-8000-000000000161"
SECRET_MARK = "UNIQUEKEYMATERIALABCDEFGHIJKLMNOPQRSTUVWXYZ"


def b64decode(segment):
    return base64.urlsafe_b64decode(segment + "=" * (-len(segment) % 4))


def raw_to_der(raw):
    def encode_int(part):
        value = part.lstrip(b"\x00") or b"\x00"
        if value[0] & 0x80:
            value = b"\x00" + value
        return b"\x02" + bytes([len(value)]) + value

    body = encode_int(raw[:32]) + encode_int(raw[32:])
    return b"\x30" + bytes([len(body)]) + body


def pem_header():
    return "-----BEGIN " + "PRIVATE KEY-----"


def pem_footer():
    return "-----END " + "PRIVATE KEY-----"


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.0"

    def log_message(self, fmt, *args):
        return

    def do_GET(self):
        self._handle()

    def do_POST(self):
        self._handle()

    def _handle(self):
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length) if length else b""
        parsed = urllib.parse.urlparse(self.path)
        token = self.headers.get("Authorization") or ""
        ok = token.startswith("Bearer ") and self.server.verify(token.split(" ", 1)[1])
        self.server.seen.append({
            "method": self.command,
            "path": parsed.path,
            "query": urllib.parse.parse_qs(parsed.query),
            "body": body.decode("utf-8"),
            "token_ok": ok,
        })
        if not ok:
            self._send(401, {"errors": [{"status": "401", "title": "Unauthorized", "detail": "bad token"}]})
            return
        route = self.server.routes.get((self.command, parsed.path))
        if route is None:
            self._send(404, {"errors": [{"status": "404", "title": "Not Found", "detail": parsed.path}]})
            return
        status, payload = route(parsed.query, body)
        self._send(status, payload)

    def _send(self, status, payload):
        if status in (301, 302, 303, 307, 308):
            self.send_response(status)
            self.send_header("Location", payload.get("location") or "https://example.com/steal")
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        raw = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)


class ApiServer:
    def __init__(self, pubkey_path):
        self.pubkey_path = pubkey_path
        self.seen = []
        self.routes = {}
        self.tests_enabled = True
        self.empty_products = False
        self.httpd = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.httpd.verify = self.verify
        self.httpd.seen = self.seen
        self.httpd.routes = self.routes
        port = self.httpd.server_address[1]
        self.base = f"http://127.0.0.1:{port}"
        self.thread = threading.Thread(target=self.httpd.serve_forever, daemon=True)
        self.thread.start()
        self._install_routes()

    def close(self):
        self.httpd.shutdown()
        self.httpd.server_close()

    def verify(self, token):
        sig_path = None
        try:
            header_b64, payload_b64, sig_b64 = token.split(".")
            header = json.loads(b64decode(header_b64))
            payload = json.loads(b64decode(payload_b64))
            if header.get("alg") != "ES256" or header.get("typ") != "JWT" or header.get("kid") != KEY_ID:
                return False
            if payload.get("iss") != ISSUER or payload.get("aud") != "appstoreconnect-v1":
                return False
            if int(payload["exp"]) - int(payload["iat"]) > 20 * 60 or int(payload["exp"]) <= int(payload["iat"]):
                return False
            raw = b64decode(sig_b64)
            if len(raw) != 64:
                return False
            fd, sig_path = tempfile.mkstemp(prefix="asc-sig-")
            os.write(fd, raw_to_der(raw))
            os.close(fd)
            proc = subprocess.run(
                ["openssl", "dgst", "-sha256", "-verify", self.pubkey_path, "-signature", sig_path],
                input=f"{header_b64}.{payload_b64}".encode(),
                capture_output=True,
                check=False,
            )
            return proc.returncode == 0
        except Exception:
            return False
        finally:
            if sig_path:
                try:
                    os.unlink(sig_path)
                except OSError:
                    pass

    def _install_routes(self):
        self.routes[("GET", f"/v1/apps/{APP_ID}")] = lambda query, body: (200, {
            "data": {"type": "apps", "id": APP_ID, "attributes": {"name": "Tingye", "bundleId": "local.tingye"}},
        })
        self.routes[("GET", "/v1/ciProducts")] = self._products
        self.routes[("GET", f"/v1/ciProducts/{PRODUCT_ID}")] = lambda query, body: (200, {"data": self._product("Tingye", PRODUCT_ID)})
        self.routes[("GET", f"/v1/ciProducts/{PRODUCT_ID}/workflows")] = self._workflows
        self.routes[("GET", f"/v1/ciProducts/{PRODUCT_ID}/buildRuns")] = self._build_runs
        self.routes[("GET", f"/v1/ciProducts/{PRODUCT_ID}/primaryRepositories")] = lambda query, body: (200, {"data": [self._repository()]})
        self.routes[("GET", f"/v1/ciWorkflows/{WORKFLOW_ID}")] = lambda query, body: (200, {"data": self._workflow("Tests", WORKFLOW_ID, self.tests_enabled)})
        self.routes[("GET", f"/v1/scmRepositories/{REPO_ID}")] = lambda query, body: (200, {"data": self._repository()})
        self.routes[("GET", f"/v1/scmRepositories/{REPO_ID}/gitReferences")] = self._git_refs
        self.routes[("GET", f"/v1/ciBuildRuns/{RUN_ID}")] = lambda query, body: (200, {"data": self._run(159, RUN_ID)})
        self.routes[("GET", f"/v1/ciBuildRuns/{RUN_ID}/actions")] = lambda query, body: (200, {"data": self._actions()})
        self.routes[("GET", f"/v1/ciBuildRuns/{RUN_ID}/builds")] = lambda query, body: (200, {"data": [self._asc_build()]})
        self.routes[("GET", "/v1/ciBuildActions/action-archive/issues")] = lambda query, body: (200, {"data": [{
            "type": "ciIssues",
            "id": "issue-1",
            "attributes": {
                "issueType": "ERROR",
                "message": "archive failed in tests",
                "fileSource": {"path": "Tingye/App.swift", "lineNumber": 12},
            },
        }]})
        self.routes[("POST", "/v1/ciBuildRuns")] = lambda query, body: (201, {"data": {
            "type": "ciBuildRuns",
            "id": CREATED_ID,
            "attributes": {"number": 161, "executionProgress": "PENDING", "completionStatus": None, "startReason": "MANUAL"},
        }})

    def _products(self, query, body):
        if self.empty_products:
            return 200, {"data": [], "links": {}}
        return 200, {"data": [self._product("Nightly", NIGHTLY_ID), self._product("Tingye", PRODUCT_ID)], "links": {}}

    def _workflows(self, query, body):
        return 200, {
            "data": [
                self._workflow("Release", OTHER_WORKFLOW_ID, False),
                self._workflow("Tests", WORKFLOW_ID, self.tests_enabled),
            ],
            "included": [self._repository()],
            "links": {},
        }

    def _build_runs(self, query, body):
        if "page=2" in query:
            return 200, {"data": [self._run(159, RUN_ID)], "links": {}}
        return 200, {
            "data": [self._run(160, "00000000-0000-4000-8000-000000000160")],
            "links": {"next": f"{self.base}/v1/ciProducts/{PRODUCT_ID}/buildRuns?page=2"},
        }

    def _git_refs(self, query, body):
        if "page=2" in query:
            return 200, {"data": [
                {"type": "scmGitReferences", "id": REF_ID, "attributes": {
                    "name": "main", "canonicalName": "refs/heads/main", "kind": "BRANCH", "isDeleted": False}},
                {"type": "scmGitReferences", "id": TAG_REF_ID, "attributes": {
                    "name": "v1", "canonicalName": "refs/tags/v1", "kind": "TAG", "isDeleted": False}},
                {"type": "scmGitReferences", "id": "dddddddd-dddd-4ddd-8ddd-dddddddddddd", "attributes": {
                    "name": "main", "canonicalName": "refs/heads/main", "kind": "BRANCH", "isDeleted": True}},
            ], "links": {}}
        return 200, {
            "data": [{"type": "scmGitReferences", "id": "cccccccc-cccc-4ccc-8ccc-cccccccccccc", "attributes": {
                "name": "develop", "canonicalName": "refs/heads/develop", "kind": "BRANCH", "isDeleted": False}}],
            "links": {"next": f"{self.base}/v1/scmRepositories/{REPO_ID}/gitReferences?page=2"},
        }

    @staticmethod
    def _product(name, product_id):
        return {"type": "ciProducts", "id": product_id, "attributes": {"name": name, "productType": "APP"}}

    def _workflow(self, name, workflow_id, enabled):
        return {
            "type": "ciWorkflows",
            "id": workflow_id,
            "attributes": {
                "name": name,
                "isEnabled": enabled,
                "manualBranchStartCondition": {
                    "source": {"isAllMatch": False, "patterns": [{"pattern": "main", "isPrefix": False}]},
                },
            },
            "relationships": {"repository": {"data": {"type": "scmRepositories", "id": REPO_ID}}},
        }

    @staticmethod
    def _repository():
        return {"type": "scmRepositories", "id": REPO_ID, "attributes": {
            "ownerName": "shatianrui", "repositoryName": "tingye-ios"}}

    @staticmethod
    def _run(number, run_id):
        return {
            "type": "ciBuildRuns",
            "id": run_id,
            "attributes": {
                "number": number,
                "createdDate": "2026-11-01T00:00:00Z",
                "startedDate": "2026-11-01T00:01:00Z",
                "finishedDate": "2026-11-01T00:20:00Z",
                "executionProgress": "COMPLETE",
                "completionStatus": "SUCCEEDED",
                "startReason": "MANUAL",
                "sourceCommit": {
                    "commitSha": "a" * 40,
                    "message": "测试提交\n第二行",
                    "webUrl": "https://example.com/commit/local",
                    "author": {"displayName": "Owner"},
                },
            },
            "relationships": {
                "workflow": {"data": {"type": "ciWorkflows", "id": WORKFLOW_ID}},
                "product": {"data": {"type": "ciProducts", "id": PRODUCT_ID}},
            },
        }

    @staticmethod
    def _actions():
        return [
            {"type": "ciBuildActions", "id": "action-test", "attributes": {
                "name": "Test", "actionType": "TEST", "executionProgress": "COMPLETE",
                "completionStatus": "SUCCEEDED", "isRequiredToPass": True,
                "issueCounts": {"errors": 0, "testFailures": 0, "warnings": 0, "analyzerWarnings": 0}}},
            {"type": "ciBuildActions", "id": "action-archive", "attributes": {
                "name": "Archive", "actionType": "ARCHIVE", "executionProgress": "COMPLETE",
                "completionStatus": "FAILED", "isRequiredToPass": True,
                "issueCounts": {"errors": 1, "testFailures": 0, "warnings": 0, "analyzerWarnings": 0}}},
        ]

    @staticmethod
    def _asc_build():
        return {"type": "builds", "id": ASC_BUILD_ID, "attributes": {
            "version": "159", "processingState": "VALID", "buildAudienceType": "INTERNAL_ONLY",
            "uploadedDate": "2026-11-01T00:21:00Z", "expired": False}}


class XcodeCloudCliTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.key_path = str(Path(cls.tmp.name) / "key.pem")
        cls.pub_path = str(Path(cls.tmp.name) / "key.pub")
        subprocess.run(
            ["openssl", "genpkey", "-algorithm", "EC", "-pkeyopt", "ec_paramgen_curve:P-256", "-out", cls.key_path],
            check=True, capture_output=True,
        )
        subprocess.run(
            ["openssl", "pkey", "-in", cls.key_path, "-pubout", "-out", cls.pub_path],
            check=True, capture_output=True,
        )
        os.chmod(cls.key_path, 0o600)
        cls.pem = Path(cls.key_path).read_text()

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def setUp(self):
        self.server = ApiServer(self.pub_path)

    def tearDown(self):
        self.server.close()

    def run_cli(self, args, include_key=True, env_extra=None, use_server=True):
        env = os.environ.copy()
        for name in (
            "APP_STORE_CONNECT_ISSUER_ID",
            "APP_STORE_CONNECT_KEY_ID",
            "APP_STORE_CONNECT_PRIVATE_KEY_PATH",
            "APP_STORE_CONNECT_PRIVATE_KEY",
            "APP_STORE_CONNECT_API_BASE",
        ):
            env.pop(name, None)
        env["APP_STORE_CONNECT_ISSUER_ID"] = ISSUER
        env["APP_STORE_CONNECT_KEY_ID"] = KEY_ID
        if include_key:
            env["APP_STORE_CONNECT_PRIVATE_KEY_PATH"] = self.key_path
        if use_server:
            env["APP_STORE_CONNECT_API_BASE"] = self.server.base
        if env_extra:
            env.update(env_extra)
        return subprocess.run(
            [sys.executable, str(SCRIPT), *args],
            capture_output=True, text=True, env=env, check=False,
        )

    def test_signature_roundtrip_and_token_claims(self):
        raw = b"\xff" + b"\x11" * 31 + b"\x80" + b"\x22" * 31
        self.assertEqual(mod.der_to_raw(raw_to_der(raw)), raw)
        with patch.dict(os.environ, {
            "APP_STORE_CONNECT_PRIVATE_KEY_PATH": self.key_path,
            "APP_STORE_CONNECT_PRIVATE_KEY": "",
        }):
            token = mod.build_jwt(ISSUER, KEY_ID, now=1_700_000_000)
        self.assertNotIn(self.pem, token)
        self.assertNotIn("PRIVATE KEY", token)
        header_b64, payload_b64, _sig = token.split(".")
        payload = json.loads(b64decode(payload_b64))
        self.assertEqual(payload["iss"], ISSUER)
        self.assertEqual(payload["aud"], "appstoreconnect-v1")
        self.assertEqual(payload["exp"] - payload["iat"], mod.TOKEN_TTL_SECONDS)
        self.assertLessEqual(payload["exp"] - payload["iat"], 20 * 60)
        self.assertTrue(self.server.verify(token))
        header = json.loads(b64decode(header_b64))
        self.assertEqual(header, {"alg": "ES256", "kid": KEY_ID, "typ": "JWT"})

    def test_base_url_stays_on_apple_or_loopback(self):
        self.assertEqual(mod.validate_base_url("https://api.appstoreconnect.apple.com"), "https://api.appstoreconnect.apple.com")
        self.assertEqual(mod.resolve_base_url({}), mod.API_ROOT)
        self.assertTrue(mod.validate_base_url("http://127.0.0.1:9").startswith("http://127.0.0.1:9"))
        with self.assertRaises(mod.CliError):
            mod.validate_base_url("http://example.com")
        with self.assertRaises(mod.CliError):
            mod.validate_base_url("https://user:secret@api.appstoreconnect.apple.com")

    def test_manual_pattern_and_product_choice(self):
        condition = {"source": {"isAllMatch": False, "patterns": [
            {"pattern": "main", "isPrefix": False},
            {"pattern": "release/", "isPrefix": True},
        ]}}
        self.assertTrue(mod.reference_matches(condition, "main"))
        self.assertTrue(mod.reference_matches(condition, "release/1"))
        self.assertFalse(mod.reference_matches(condition, "develop"))
        self.assertIsNone(mod.reference_matches(None, "main"))
        self.assertIn("main", mod.describe_patterns(condition))
        nightly = {"id": NIGHTLY_ID, "attributes": {"name": "Nightly"}}
        tingye = {"id": PRODUCT_ID, "attributes": {"name": "Tingye"}}
        chosen, _how = mod._pick_product([nightly, tingye], "Tingye")
        self.assertEqual(chosen["id"], PRODUCT_ID)
        with self.assertRaises(mod.CliError):
            mod._pick_product([tingye, {"id": "x", "attributes": {"name": "Tingye"}}], "Tingye")

    def test_lookup_discovers_tests_workflow(self):
        proc = self.run_cli(["lookup"])
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn(PRODUCT_ID, proc.stdout)
        self.assertIn(WORKFLOW_ID, proc.stdout)
        self.assertIn("Tests", proc.stdout)
        self.assertIn(TEAM_ID, proc.stdout)
        self.assertIn("手动启动分支: main", proc.stdout)
        self.assertNotIn(NIGHTLY_ID, proc.stdout)
        self.assertNotIn(OTHER_WORKFLOW_ID, proc.stdout)
        self.assertNotIn("PRIVATE KEY", proc.stdout + proc.stderr)
        listed = [item for item in self.server.seen if item["path"] == "/v1/ciProducts"]
        self.assertEqual(listed[0]["query"].get("filter[app]"), [APP_ID])
        self.assertTrue(all(item["token_ok"] for item in self.server.seen))

    def test_lookup_json_and_fallback_product(self):
        proc = self.run_cli(["lookup", "--json"])
        self.assertEqual(proc.returncode, 0, proc.stderr)
        document = json.loads(proc.stdout)
        self.assertEqual(document["workflow"]["name"], "Tests")
        self.assertEqual(document["product"]["id"], PRODUCT_ID)
        self.assertTrue(document["workflow"]["manualBranchMatchesMain"])
        self.assertEqual(document["repository"]["repositoryName"], "tingye-ios")
        self.assertEqual(document["teamIdSource"], "script-default")

        self.server.seen.clear()
        self.server.empty_products = True
        proc = self.run_cli(["lookup"])
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("默认产品 ID", proc.stdout)
        self.assertTrue(any(item["path"] == f"/v1/ciProducts/{PRODUCT_ID}" for item in self.server.seen))

    def test_status_by_id_includes_test_archive_and_testflight(self):
        proc = self.run_cli(["status", RUN_ID])
        self.assertEqual(proc.returncode, 0, proc.stderr)
        for label in ("Test:", "Archive:", "TestFlight:"):
            self.assertIn(label, proc.stdout)
        self.assertIn("#159", proc.stdout)
        self.assertIn("SUCCEEDED", proc.stdout)
        self.assertIn("FAILED", proc.stdout)
        self.assertIn("VALID", proc.stdout)
        self.assertIn("INTERNAL_ONLY", proc.stdout)
        self.assertIn("archive failed in tests", proc.stdout)
        self.assertIn("Tingye/App.swift:12", proc.stdout)
        self.assertNotIn(self.pem, proc.stdout + proc.stderr)

    def test_status_by_build_number_pages(self):
        proc = self.run_cli(["status", "159", "--json"])
        self.assertEqual(proc.returncode, 0, proc.stderr)
        document = json.loads(proc.stdout)
        self.assertEqual(document["id"], RUN_ID)
        self.assertEqual(document["number"], 159)
        self.assertEqual(document["summary"]["testflight"].count("VALID"), 1)
        pages = [item for item in self.server.seen if item["path"].endswith("/buildRuns")]
        self.assertEqual(pages[0]["query"].get("sort"), ["-number"])
        self.assertTrue(any(item["query"].get("page") == ["2"] for item in pages))

    def test_start_posts_git_reference_not_sha(self):
        proc = self.run_cli(["start", "--branch", "main"])
        self.assertEqual(proc.returncode, 0, proc.stderr)
        posts = [item for item in self.server.seen if item["method"] == "POST"]
        self.assertEqual(len(posts), 1)
        self.assertEqual(json.loads(posts[0]["body"]), {
            "data": {
                "type": "ciBuildRuns",
                "relationships": {
                    "workflow": {"data": {"type": "ciWorkflows", "id": WORKFLOW_ID}},
                    "sourceBranchOrTag": {"data": {"type": "scmGitReferences", "id": REF_ID}},
                },
            },
        })
        self.assertNotIn("main", posts[0]["body"])
        self.assertNotIn("a" * 40, posts[0]["body"])
        self.assertIn(CREATED_ID, proc.stdout)
        self.assertIn("MANUAL", proc.stdout)
        self.assertIn("Git 引用", proc.stdout)
        self.assertTrue(all(item["token_ok"] for item in self.server.seen))

    def test_dry_run_and_tag_do_not_post(self):
        proc = self.run_cli(["start", "--dry-run"])
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("未发送", proc.stdout)
        self.assertIn(REF_ID, proc.stdout)
        self.assertFalse(any(item["method"] == "POST" for item in self.server.seen))

        self.server.seen.clear()
        proc = self.run_cli(["start", "--tag", "v1", "--dry-run"])
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn(TAG_REF_ID, proc.stdout)
        self.assertNotIn(REF_ID, proc.stdout)
        self.assertFalse(any(item["method"] == "POST" for item in self.server.seen))

    def test_disabled_workflow_and_foreign_page_do_not_post(self):
        self.server.tests_enabled = False
        proc = self.run_cli(["start"])
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("停用", proc.stderr)
        self.assertFalse(any(item["method"] == "POST" for item in self.server.seen))

        self.server.tests_enabled = True
        self.server.seen.clear()
        self.server.routes[("GET", f"/v1/scmRepositories/{REPO_ID}/gitReferences")] = (
            lambda query, body: (200, {"data": [], "links": {"next": "https://example.com/gitReferences"}})
        )
        proc = self.run_cli(["start", "--dry-run"])
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("其他主机", proc.stderr)
        self.assertFalse(any(item["method"] == "POST" for item in self.server.seen))

    def test_redirect_is_not_followed(self):
        self.server.routes[("GET", f"/v1/apps/{APP_ID}")] = (
            lambda query, body: (302, {"location": "https://example.com/steal"})
        )
        proc = self.run_cli(["lookup"])
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("重定向", proc.stderr)
        self.assertEqual(len(self.server.seen), 1)

    def test_sha_branch_and_missing_env_make_no_request(self):
        before = len(self.server.seen)
        proc = self.run_cli(["start", "--branch", "a" * 40], include_key=False, use_server=False)
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("SHA", proc.stderr)
        proc = self.run_cli(["start", "--branch", "main", "--tag", "v1"], include_key=False, use_server=False)
        self.assertIn("同时", proc.stderr)
        proc = self.run_cli(["status", "not-an-id"], include_key=False, use_server=False)
        self.assertIn("ciBuildRun", proc.stderr)
        proc = self.run_cli(
            ["lookup"], include_key=False, use_server=False,
            env_extra={"APP_STORE_CONNECT_ISSUER_ID": ""},
        )
        self.assertEqual(proc.returncode, 2)
        self.assertIn("APP_STORE_CONNECT_ISSUER_ID", proc.stderr)
        self.assertIn("APP_STORE_CONNECT_PRIVATE_KEY_PATH", proc.stderr)
        self.assertEqual(len(self.server.seen), before)

    def test_inline_key_is_not_printed_or_left_behind(self):
        marker = next(line for line in self.pem.splitlines() if line and "PRIVATE" not in line)
        scratch = tempfile.mkdtemp()
        try:
            proc = self.run_cli(["lookup"], env_extra={
                "APP_STORE_CONNECT_PRIVATE_KEY_PATH": "",
                "APP_STORE_CONNECT_PRIVATE_KEY": self.pem,
                "TMPDIR": scratch,
            })
            self.assertEqual(proc.returncode, 0, proc.stderr)
            self.assertNotIn(marker, proc.stdout)
            self.assertNotIn(marker, proc.stderr)
            self.assertNotIn(pem_header(), proc.stdout + proc.stderr)
            self.assertEqual(list(Path(scratch).rglob("*")), [])
        finally:
            shutil.rmtree(scratch)

        blob = pem_header() + "\n" + SECRET_MARK + "\n" + pem_footer() + "\n"
        proc = self.run_cli(["lookup"], include_key=False, env_extra={"APP_STORE_CONNECT_PRIVATE_KEY": blob})
        self.assertNotEqual(proc.returncode, 0)
        self.assertNotIn(SECRET_MARK, proc.stdout)
        self.assertNotIn(SECRET_MARK, proc.stderr)

        proc = self.run_cli(["lookup"], env_extra={"APP_STORE_CONNECT_PRIVATE_KEY": blob})
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertNotIn(SECRET_MARK, proc.stdout + proc.stderr)

    def test_tree_has_no_private_key_material(self):
        readme = (SCRIPT.parent / "README.md").read_text()
        for text in (
            APP_ID, PRODUCT_ID, TEAM_ID, RUN_ID, "159", "Tests", "main",
            "Users and Access", "Integrations", "App Store Connect API",
            "APP_STORE_CONNECT_ISSUER_ID", "APP_STORE_CONNECT_KEY_ID",
            "APP_STORE_CONNECT_PRIVATE_KEY_PATH", "Manual Start", "scmGitReferences",
        ):
            self.assertIn(text, readme)
        self.assertIn("*.p8", (ROOT / ".gitignore").read_text())
        for path in SCRIPT.parent.rglob("*"):
            if not path.is_file():
                continue
            self.assertNotEqual(path.suffix, ".p8")
            if path.suffix not in {".py", ".md"}:
                continue
            text = path.read_text()
            self.assertNotIn(pem_header(), text)
            self.assertNotIn(pem_footer(), text)
            self.assertNotIn("-----BEGIN EC " + "PRIVATE KEY-----", text)


if __name__ == "__main__":
    unittest.main()
