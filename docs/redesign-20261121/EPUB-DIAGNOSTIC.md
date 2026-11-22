# 派生 EPUB 单用例取证

复现 run `44931620062` 的 EPUB 首次加载失败。保留原用例 `TingyeUITests/DesignFlowTests/testEPUBDerivedFixtureSmokeAndSearch`、原样本及 XCTest 等待条件。一次调用 `xcodebuild test`，沿用默认单次执行，禁用并行克隆以便用同一模拟器 UDID 关联日志。失败退出码原样传给 Actions，诊断附件始终尝试上传。

## 执行

协调方将已审查的文件正常提交并推送到重设计分支后，通过已注册的 [Tests 工作流](../../.github/workflows/tests.yml) 派发一次。只有在该分支手动显式选择 `epub-derived-once` 才运行「EPUB diagnostic (one case only)」。省略参数、显式选 `full`、原 push 和 PR 事件仍运行完整 Unit/UI。诊断和完整测试使用独立的并发组，权限保持 `contents: read`。

```bash
gh workflow run tests.yml --ref redesign/full-product-20261121 -f diagnostic_mode=epub-derived-once
```

Actions 有两次独立 checkout。`GITHUB_SHA` 与诊断配置 HEAD 对应。实际编译、运行的源码 HEAD 固定为 `cbbe25c8060635199995dae7cbdea461806578da`，脚本在执行前验证 SHA 和干净状态。`provenance.json`、`source-sha256.json` 和 `test-command.json` 用来核对配置 SHA、源码 SHA、关键文件和命令。Actions 手动重跑的 attempt 2 及以上在启动测试前退出。诊断结果不代表完整 Unit/UI 来源证明。

失败运行的 Checkout 和 Xcode 日志给出 Xcode 26.6（17F113）、Apple Silicon、iPhone 17 Pro。xcresult 的 `operatingSystemVersionWithBuildNumber` 是 iOS `26.4.1 (23E254a)`。脚本从 `simctl list runtimes -j` 和设备类型 JSON 获取实际标识符，用版本和构建号精确匹配。若 SDK 只显示主次版本，还要求该 runtime 的 SystemVersion.plist 确认修订版本。缺少匹配项时退出并保留已获取的环境证据。脚本不安装 runtime。Actions 记录当次镜像元数据，托管镜像修订可能与历史运行不同。

## 首次诊断启动结果

Run `44935673186` 核对通过配置 `0fe158b`、应用/测试源码 `cbbe25c` 和精确 Xcode、模拟器环境。Xcode 26.6 在测试开始前拒绝 `-test-iterations 1`，报错 `Must specify -test-iterations with more than 1 iteration.`，退出码 64，原用例启动 0 次。该结果只记录诊断命令的参数错误，没有复现 EPUB 故障。

修订移除了这两个参数，沿用 `xcodebuild test` 的默认单次执行。原 `-only-testing` 选择及成功时原用例启动次数必须等于 1 的检查保留。修订后的单次诊断结果见下文。

## 已完成的单用例实验

Run `44936246544` 的配置 SHA 为 `51df34e97321b3e11cb2275646688f3a8761b25c`，干净的应用及原测试 SHA 为 `cbbe25c8060635199995dae7cbdea461806578da`。实际运行于 arm64 镜像 `20261117.0516.1`、Xcode 26.6（17F113）、iPhone 17 Pro、iOS 26.4.1（23E254a）。Xcode 退出码 0，用例启动 1 次，xcresult 记录 1 通过、0 失败、0 跳过。原用例耗时 107.520 秒。诊断模式没有执行完整 Unit/UI。新建模拟器、关闭并行测试和省去前序用例均与整套运行不同。

以下用 UTC 的 `simulator-log-show.ndjson` 对齐 `xcodebuild.log`。实时 stream 中同一 `machTimestamp` 的事件约晚 0.293 秒，合并时按该时间戳去重。统一日志中 Tingye 为 PID 14682，两个 WebContent 为 14750 和 14757，Networking 为 14753，XCTest runner 为 14408。

| 时间 | 观察 |
| --- | --- |
| 18:45:43.300 | XCTest 用例起点。SpringBoard 约 18:45:52.484 已报告应用 PID 14682。 |
| 18:46:01.368、18:46:01.484 | 应用进程的两个 WebKit 页面发出 `loadRequest`，后续主 frame 事件将它们分别关联到 WebContent 14750 和 14757。 |
| 18:46:05.552–18:46:05.894 | 两个主 frame 开始 provisional load。首批本地 scheme 任务约 18:46:05.555 开始，约 18:46:05.894 记录完成。 |
| 18:46:13.578、18:46:13.940 | 两个主 frame 报告加载完成。18:46:13.803 的较早无障碍快照仍显示「未分页」。 |
| 18:46:15.466、18:46:15.668 | 首次观察到真实 `reader.contents` 目录按钮。随后快照记录首章 `page\|EPUB/text/ch-000001.xhtml\|…` 及首章标题。快照只能界定首次观察时间，精确位置回调时间未单独记录。 |
| XCTest t=33.45–106.51 | 目录等待于 t=16.95 开始，至 t=33.45 已进入 WebView 检查。随后实际网页标题和正文通过可见性断言。t=47.56 点击目录，t=50.72 点击搜索，t=66.83 输入关键词，t=90.35 点击匹配结果。排版验证通过并返回书库。 |

两份过滤日志中均未检出 `tryAuthorize`、`SOAuthorization` 或 AppSSO 查询事件。实时日志仅在 18:46:01.374 出现一次 `WebKit2ExtensibleSSOEnabled` 偏好键读取未找到值。该记录只表明读取偏好，无法确认授权查询发生或钩子的实际效果。后置服务列表含空 PID 的 AppSSO daemon 项，无法补证启动阶段发生查询。成功路径在本地任务开始前约有 4.1 秒，原因未定。

整套失败 run `44931620062` 的 PID 14184 在 t=44.67 的快照中同样已挂载 WebView，但仍未分页且无目录按钮。它缺少可与该窗口关联的 WebKit 时间线。更早的全套 run `44929297226` 中，这个用例在相同的 EPUB 路径代码上通过，目录等待从 t=9.49 到随后 t=15.99 的 WebView 检查。本次等待至下一断言约 16.50 秒。本次证实同一应用/测试源码在精确版本环境的单独运行中能完成加载与搜索，结合整套失败支持间歇性表现。现有证据无法在旧失败中区分 WebKit、本地交付、位置回调或运行调度，也无法确认历史 AppSSO 问题重现。

本次已取得完整 Xcode 日志、xcresult、实时及回查统一日志。服务前置快照与结束截图各超时 15 秒（`services_before=null`、`screenshot=null`）。后置服务列表、统一日志回查、结果摘要和附件导出命令均返回 0。导出 manifest 为空，本次成功用例没有导出的截图附件，也没有结束截图可用。旧失败无障碍快照为独立证据。

## 证据读取

- `test-exit.json` 记录原始 xcodebuild 退出码与 UTC 窗口。构建期限耗尽时记录超时，退出码为 124。`observed-test-starts.json` 显示用例是否进入执行，`xcodebuild.log` 保留完整输出。
- `TingyeUITests.xcresult` 保留 Xcode 自带附件及失败层级。`attachments/` 和结果摘要尽力导出。`after-test.png` 是结束后的画面，失败时应以 xcresult 的断言快照为准。
- Unified Log 只从新建的 fixture 模拟器取证。按 Tingye、WebKit WebContent/Networking、AppSSO 及相关服务过滤，保留带时间/PID 的 live stream 和目标窗口 `log show`。另记过滤后的服务前后状态，用来佐证进程存在。`evidence-status.json` 区分各辅助采集步骤的状态，清理只作用于本次创建的模拟器和本次日志进程。
- 用 `milestones.txt` 查找启动、`loadRequest`、AppSSO、scheme handler、provisional load、位置及目录断言的线索。用原日志和断言快照对齐时间及进程。目前源码没有位置回调的专用日志，可能只能由分页、目录和 WebView 状态间接确认。没有可见日志的阶段仍需保留不确定性。
- 单跑通过仅表示该次未复现。单跑没有前序测试，同款环境也可能出现不同调度。历史构建 146 的 AppSSO 修复仅供对照。真机及完整套件验收仍按 [STATUS](STATUS.md) 追踪。

固定构建 148 的 `verify-local.py` 将 `.github` 整体列为保护区。针对本实验编译的旧源码，仍在 `cbbe25c` 源码副本中运行原守卫。含已授权的 `tests.yml` 诊断入口的配置提交与构建 148 比对时，原有全目录守卫会报告差异。诊断配置单独检查触发器、权限、源 SHA 和执行次数。
