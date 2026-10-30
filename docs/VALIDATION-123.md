# 听页 1.24.0（123）悬浮阅读工具验收

2026-10-24，本轮「悬浮菜单开合保持正文」改动已完成 **112 项核心测试与 12 项相关 UI 测试的最终验证**。iPhone SE（第 3 代）补充验证了章内翻页、最大辅助字号工具、摘记与搜索三个场景；Mac Catalyst Debug 构建通过。

上述 124 项为本轮去重后的核心与相关 UI 覆盖范围，包含失败分析后的复核，**没有重跑当前全部 138 项测试，也不将 122 版的 135 项完整回归计作本轮执行结果**。早期失败与后续通过的证据均保留如下。

版本已设为 **1.24.0（123）**。双端 Release 归档及 iOS 28 项 / Mac 29 项包检查已通过；上传回执与 TestFlight 可安装状态统一以 [123 发布证据](testflight-123.json)为准。本地测试、Debug 构建及归档检查通过不表示上传完成。122 版历史见 [VALIDATION-122.md](VALIDATION-122.md)。

## 本轮行为

- 底部阅读工具改为覆盖在正文上的悬浮层。显示、隐藏工具时，正文使用固定视口，保持原来分页、文字位置与阅读断点。
- 顶部阅读信息、章节标题和底部阅读信息保留稳定的布局空间。阅读页状态栏始终隐藏，其显隐不再随工具菜单改变安全区。
- 原书图文保持实际 WebView 尺寸及同一文字节点的位置；PDF 保持实际页码、页内位置与缩放比例。
- 目录、排版、摘记、更多和原有辅助听书流程保留。最大辅助字号下，工具面板可滚动，顶部返回入口保持可达。

图标、配色以及阅读与听书独立保存的行为延续 122；相关背景见 [READING-FIRST.md](READING-FIRST.md)。

## 测试范围与结果

自动化使用 Debug 隔离临时书库。主设备为 **iPhone 17e / iOS 27.0 模拟器**，小屏设备为 **iPhone SE（第 3 代）/ iOS 27.0 模拟器**（设备名 `Tingye Action Layout SE`）。

| 范围 | 最终结果 | 主要证据 |
| --- | --- | --- |
| 核心逻辑 | 112 项通过：`NativeCoreTests` 89、`ProgressAndBackupTests` 20、`ExtendedReadingTests` 3 | `work/reader-overlay/reading-regression.log`、`reading-regression.xcresult` |
| 新增固定正文 UI | 3 项通过，0 失败、0 跳过 | `work/reader-overlay/layout-tests.log`、`layout-tests.xcresult`、`layout-summary.json` |
| 既有相关阅读 UI | 9 项最终通过；首轮 8 项通过，搜索可点击等待失败，随后修正测试条件并复核通过 | `reading-regression.xcresult`、`search-check.xcresult`、`final-interactions.xcresult` |
| SE 3 小屏补测 | 3 项最终通过；首轮分页、搜索通过，最大字号工具完整可见条件修正后通过 | `small-screen.log`、`small-screen.xcresult`、`final-interactions.xcresult` |
| 两处测试修正后的交互复核 | 搜索、最大字号两个用例，在两台设备各执行一次，共 4 次执行，0 失败、0 跳过 | `final-interactions.log`、`final-interactions.xcresult`、`final-summary.json` |
| iOS Debug 构建 | 通过 | `work/reader-overlay/build.log`，末尾 `BUILD SUCCEEDED` |
| Mac Catalyst Debug 构建 | 通过，`CODE_SIGNING_ALLOWED=NO` | `work/reader-overlay/mac-build.log`，末尾 `BUILD SUCCEEDED` |

SE 3 的三个场景与主设备用例有重叠，不另计为新增测试方法。`final-summary.json` 的 `passedTests: 2` 表示两个测试方法；其中两个设备配置各记录 2 次通过，合计 **4 次设备执行**。

三个新增回归均先离开首页或第一页，连续两轮隐藏、显示工具，再返回上一页验证阅读操作仍可用：

| 用例 | 实际验证对象 |
| --- | --- |
| `testPagedReaderChromeDoesNotReflowOrMoveReadingPosition` | CoreText 实际页面的完整文字与 UIView 坐标；开合前后逐字、逐框一致，回翻恢复原页文字 |
| `testOriginalReaderChromeDoesNotResizeOrMoveItsColumn` | 原书 WebView 的实际坐标，以及非首页同一真实文字节点的文字和坐标；回翻可见原章标题与首段 |
| `testPDFReaderChromeDoesNotResizeScaleOrMoveItsPage` | 实际 PDFView 坐标及 PDFKit 读取的页码、缩放、当前页转换坐标；开合前后保持一致并能返回原页 |

其余九项相关 UI 覆盖阅读工具与排版、摘记与搜索、独立读听位置、更多菜单与日夜纸色、最大辅助字号、原书浅色与夜间目录、PDF 工具与摘记，以及夜间阅读和播放器入口。测试没有只依靠「WebView 存在」或「章节编号未变」判断正文稳定；实际正文内容、渲染坐标和 PDF 缩放均参与断言。

## 两处测试条件修正

首轮 `reading-regression.xcresult` 共记录 **120 次通过、1 次失败**：112 项核心全部通过，9 项 UI 中搜索结果已存在但当时尚不可点击。单独复现中，将截图提前约 0.4 秒后可成功点击，说明 `exists` 不能代表列表完成交互布局。最终测试先等待实际结果计数，精确匹配 `02、第二章` 章节结果，再用谓词等待 `isHittable`；保留输入、结果命中、跳到第 2 章及不启动声音的断言。

首轮 `small-screen.xcresult` 记录 **2 次通过、1 次失败**。SE 3 最大字号下，「更多」按钮仅露出顶部约 12.5pt，仍被系统判为 `isHittable`；其中心已在工具视口与屏幕外。最终测试先将目标完整滚入工具视口与屏幕的交集，再验证触点、边距、返回入口和菜单打开。没有使用坐标绕过裁切，也没有删除菜单功能断言。

以上两处修正仅调整测试对「可交互」和「完整可见」的判断，未因此改动生产搜索逻辑或工具布局。最终 `final-interactions.xcresult` 在 iPhone 17e 与 SE 3 上复核两项均通过，日志为 `TEST SUCCEEDED`。早期结果包保持原始失败记录，不能单独解读为最终状态。

## 证据与发布输入

本地验收汇总及最终四个相关源码 / 测试文件的 SHA-256 位于 `outputs/悬浮菜单正文保持/验证记录.json` 的 `source_sha256`。同目录保存分页、原书图文、PDF 的工具显隐对照截图，以及 SE 3 最大字号工具完整显示截图。该汇总文件保留本地验收时尚未发布本次改动的状态；123 的后续发布状态以 `docs/testflight-123.json` 为准。

`work/reader-overlay/tested-source-hashes.json` 是早期快照，早于两处测试条件的最终修正；不将它作为最终 UI 测试文件的哈希证明。

123 的 `work/release-123/source-manifest.json` 于 **2026-10-24 00:35:51 +08:00** 冻结 **149 个构建输入**的 SHA-256，版本为 1.24.0、构建号为 123。归档前后均复核 149 项与当前输入一致。测试完成后仅将构建号 122 递增为 123，营销版本仍为 1.24.0，业务代码、UI 与资源未改变；未因单独递增版本号重跑测试。`work/release-123/release-notes-zh.txt` 保存本次发布说明，`verify_archives.py` 用于 123 归档检查。

上述 `work/`、`outputs/` 路径相对于本次 Codex 工作目录 `/Users/a1234/Documents/Codex/2026-10-23/figma-plugin-figma-openai-curated-remote`；`docs/`、`build/` 路径相对于项目目录。

## Release 与 TestFlight 状态

两端 Release 归档均成功、退出码 0：`build/Tingye-123.xcarchive` 与 `build/Tingye-123-mac.xcarchive`。iOS 包检查 **28 项通过**，Mac 包检查 **29 项通过**，无检查警告；分别为 arm64 与 arm64 / x86_64。版本、签名、团队、iCloud / Keychain 权限、dSYM、隐私清单、加密声明、图标及 Release 调试内容隔离均通过。包内图标摘要与 122 一致。

对应日志及检查结果位于 `work/release-123/archive-ios.log`、`archive-mac.log`、`archive-verification-ios.json`、`archive-verification-mac.json`。上传均已成功：iOS 于 **00:43:13.545**、Mac 于 **00:52:36.264**（2026-10-24，+08:00）收到 `Upload succeeded` / `EXPORT SUCCEEDED`，两端退出码 0。iOS TestFlight 已显示 **1.24.0 Build 123** 与安装按钮（54.2 MB），确认当前测试账号可安装；Mac TestFlight 已显示 **1.24.0 Build 123** 与更新按钮（60.6 MB），确认当前测试账号可更新；未执行安装或更新。

归档检查结果、两端上传回执及 TestFlight 可安装状态由 [123 发布证据](testflight-123.json)记录。Mac Debug 编译通过与双端 Release 发布是不同验证阶段。

本轮覆盖所用模拟器、字体级别和样本；未新增真机长时间音频、蓝牙 / 来电、付费云语音、双设备 iCloud 或完整 Catalyst 桌面交互验收。核心音频测试日志包含 AVAudioSession 主线程调用的运行时警告，测试通过不表示这些警告已消除。
