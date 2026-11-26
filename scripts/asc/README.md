# Xcode Cloud（App Store Connect API）

`xcode_cloud.py` 用来查看听页的 Xcode Cloud 产品、名为 Tests 的工作流，以及某一次 `ciBuildRun`，也可以按分支或标签启动一次构建。

只需要 Python 3.9+ 标准库，以及本机的 `openssl`（macOS 自带）。没有 pip 依赖。签名是 App Store Connect 要求的 ES256 JWT，有效期 10 分钟，不超过 Apple 的 20 分钟上限。

## 私钥

`.p8` 在 **App Store Connect › Users and Access › Integrations › App Store Connect API** 创建 Team API 密钥时下载。这个文件只能下载一次，Apple 之后不再提供。

把 `.p8` 放在仓库外面，只留在自己的机器上，保持私有，不要提交。本仓库的 `.gitignore` 已忽略 `*.p8`。建议 `chmod 600`。脚本发现其他人也能读这个文件时，只会在 stderr 提醒，不会打印密钥内容。

## 环境变量

| 变量 | 作用 |
| --- | --- |
| `APP_STORE_CONNECT_ISSUER_ID` | Integrations 页上的 Issuer ID |
| `APP_STORE_CONNECT_KEY_ID` | 密钥的 Key ID |
| `APP_STORE_CONNECT_PRIVATE_KEY_PATH` | `.p8` 的文件路径。设置了就用它 |
| `APP_STORE_CONNECT_PRIVATE_KEY` | 可选。PEM 正文。上面的路径也设置时，以路径为准 |

不要把私钥写进命令、shell 历史或仓库。下面的示例只用占位符。

```sh
export APP_STORE_CONNECT_ISSUER_ID="<Issuer ID>"
export APP_STORE_CONNECT_KEY_ID="<Key ID>"
export APP_STORE_CONNECT_PRIVATE_KEY_PATH="$HOME/private/AuthKey.p8"

python3 scripts/asc/xcode_cloud.py lookup
python3 scripts/asc/xcode_cloud.py status c7f15f14-fde2-49bc-aeb9-2398aec480c8
python3 scripts/asc/xcode_cloud.py status 159
python3 scripts/asc/xcode_cloud.py start --branch main
python3 scripts/asc/xcode_cloud.py start --dry-run
```

`c7f15f14-fde2-49bc-aeb9-2398aec480c8` 是构建 159 的 ciBuildRun ID，只作命令示例。

## 默认值

不传参数时，脚本先向接口查询，查不到再用下面的已知 ID。

| 项目 | 值 |
| --- | --- |
| App Store Connect App | `6808449893` |
| Xcode Cloud 产品 | `3cbe429b-609e-4432-b6f5-e16445a60b01`（名称 Tingye） |
| 团队 ID | `f8e71983-075b-4048-a3e7-772dc41ae2c5` |
| 工作流 | `Tests` |
| 分支 | `main` |

团队 ID 只印在 `lookup` 的结果里，方便和 App Store Connect 对照。接口不返回它，请求里也不会带上。产品和工作流以接口结果为准：按 App 列出 `ciProducts`，再按名称找 Tests。

## 命令

### `lookup`

确认 App、Xcode Cloud 产品和 Tests 工作流，并打印仓库，以及手动启动接受的分支和标签。

```sh
python3 scripts/asc/xcode_cloud.py lookup
python3 scripts/asc/xcode_cloud.py lookup --json
```

### `status`

查看一次构建的进度、结果、启动原因、提交，以及动作。摘要里固定有 Test、Archive 和 TestFlight 三行。

动作类型来自接口：`TEST`、`ARCHIVE`，另外还可能有 `BUILD` 和 `ANALYZE`。TestFlight 不是单独的动作类型；Archive 上传之后，关联的 App Store Connect build 会出现在这次 `ciBuildRun` 的 `builds` 里，脚本用它的 `processingState` 表示 TestFlight 处理状态。失败的动作会再取少量 `ciIssues`。

可以传 ciBuildRun ID，也可以传构建编号。编号会在该产品的构建列表里按编号从新到旧查找。

```sh
python3 scripts/asc/xcode_cloud.py status c7f15f14-fde2-49bc-aeb9-2398aec480c8
python3 scripts/asc/xcode_cloud.py status 159
```

### `start`

为 Tests 工作流启动一次构建，默认分支是 `main`。`--tag` 用来指定标签，不能和 `--branch` 一起用。

通过 API 启动的构建算**手动构建**。Tests 工作流已经对 `main` 打开了 Manual Start。接口要的是一个 Git 引用（分支或标签的 `scmGitReferences` ID），不是提交 SHA。脚本会先读工作流的仓库，再按名字找到分支或标签，然后 `POST /v1/ciBuildRuns`。传入 40 或 64 位的提交哈希会被拒绝，不会发请求。

`start` 会在 Apple 上创建一次真实构建。`--dry-run` 只解析引用并打印请求体，不 POST。

```sh
python3 scripts/asc/xcode_cloud.py start --branch main
python3 scripts/asc/xcode_cloud.py start --dry-run
```

## 本地检查

`python3 scripts/asc/test_xcode_cloud.py` 使用临时密钥和本机假接口，不访问 App Store Connect，也不会启动线上构建。
