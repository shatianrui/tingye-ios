# 派生 EPUB 单用例取证

复现 run `44931620062` 的 EPUB 首次加载失败。保留原用例 `TingyeUITests/DesignFlowTests/testEPUBDerivedFixtureSmokeAndSearch`、原样本及 XCTest 等待条件。一次调用、一次迭代，禁用 Xcode 并行克隆以便用同一模拟器 UDID 关联日志。失败退出码原样传给 Actions，诊断附件始终尝试上传。

## 执行

协调方将已审查的文件正常提交并推送到重设计分支后，通过已注册的 [Tests 工作流](../../.github/workflows/tests.yml) 派发一次。只有在该分支手动显式选择 `epub-derived-once` 才运行「EPUB diagnostic (one case only)」。省略参数、显式选 `full`、原 push 和 PR 事件仍运行完整 Unit/UI。诊断和完整测试使用独立的并发组，权限保持 `contents: read`。

```bash
gh workflow run tests.yml --ref redesign/full-product-20261121 -f diagnostic_mode=epub-derived-once
```

Actions 有两次独立 checkout。`GITHUB_SHA` 与诊断配置 HEAD 对应。实际编译、运行的源码 HEAD 固定为 `cbbe25c8060635199995dae7cbdea461806578da`，脚本在执行前验证 SHA 和干净状态。`provenance.json`、`source-sha256.json` 和 `test-command.json` 用来核对配置 SHA、源码 SHA、关键文件和命令。Actions 手动重跑的 attempt 2 及以上在启动测试前退出。诊断结果不代表完整 Unit/UI 来源证明。

失败运行的 Checkout 和 Xcode 日志给出 Xcode 26.6（17F113）、Apple Silicon、iPhone 17 Pro。xcresult 的 `operatingSystemVersionWithBuildNumber` 是 iOS `26.4.1 (23E254a)`。脚本从 `simctl list runtimes -j` 和设备类型 JSON 获取实际标识符，用版本和构建号精确匹配。若 SDK 只显示主次版本，还要求该 runtime 的 SystemVersion.plist 确认修订版本。缺少匹配项时退出并保留已获取的环境证据。脚本不安装 runtime。Actions 记录当次镜像元数据，托管镜像修订可能与历史运行不同。

## 证据读取

- `test-exit.json` 记录原始 xcodebuild 退出码与 UTC 窗口。构建期限耗尽时记录超时，退出码为 124。`observed-test-starts.json` 显示用例是否进入执行，`xcodebuild.log` 保留完整输出。
- `TingyeUITests.xcresult` 保留 Xcode 自带附件及失败层级。`attachments/` 和结果摘要尽力导出。`after-test.png` 是结束后的画面，失败时应以 xcresult 的断言快照为准。
- Unified Log 只从新建的 fixture 模拟器取证。按 Tingye、WebKit WebContent/Networking、AppSSO 及相关服务过滤，保留带时间/PID 的 live stream 和目标窗口 `log show`。另记过滤后的服务前后状态，用来佐证进程存在。`evidence-status.json` 区分各辅助采集步骤的状态，清理只作用于本次创建的模拟器和本次日志进程。
- 用 `milestones.txt` 查找启动、`loadRequest`、AppSSO、scheme handler、provisional load、位置及目录断言的线索。用原日志和断言快照对齐时间及进程。目前源码没有位置回调的专用日志，可能只能由分页、目录和 WebView 状态间接确认。没有可见日志的阶段仍需保留不确定性。
- 单跑通过仅表示该次未复现。单跑没有前序测试，同款环境也可能出现不同调度。历史构建 146 的 AppSSO 修复仅供对照。真机及完整套件验收仍按 [STATUS](STATUS.md) 追踪。

固定构建 148 的 `verify-local.py` 将 `.github` 整体列为保护区。针对本实验编译的旧源码，仍在 `cbbe25c` 源码副本中运行原守卫。含已授权的 `tests.yml` 诊断入口的配置提交与构建 148 比对时，原有全目录守卫会报告差异。诊断配置单独检查触发器、权限、源 SHA 和执行次数。
