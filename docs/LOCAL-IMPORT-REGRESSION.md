# 本地文件导入回归：选择后必须有响应

状态：**源码中识别的失败模式已缓解；静态检查完成。尚未在 Xcode 编译、执行 iOS 回归或完成真机文件提供方验证。用户故障尚未关闭。**

本次从正确 `readium-engine@18481af8008b27266af661b03bf16cf5b10e07a0` 开始；这是良好 IPA `unsigned-1.25.0-20261116.34` 的 Actions run 43874481526 实际 build head。旧 tag 错指 main，不能用 tag 当基线。废弃 v30 / `0a338be` / PR15 的 UI、资源与 AppModel 没有移入；本次保留 Readium 引擎、原包、Locator、迁移、依赖及全部原测试。

## 用户症状、历史与实际源码证据

用户描述：选择文件后无反应，也没有报错。与历史相似是调查线索，不能推断同一设备根因已被复现。

历史链：PR10 `c965f131` / merge `4dfff84` 记录 ImportHub 嵌套 sheet 内 fileImporter 的回调可能被吞，改成登记请求、关闭后由根宿主消费。后来 `8e38777f1b1c8e55b81b063556eee124b39e5132` 和 `81acce157c5664a4ac3624e4bcccbf3270f58daf` 包含复制单选、独立批量、delegate 直达与协调读取的修复方向。本次只参考该逻辑与精简交接记录，没有 cherry-pick 旧非 Readium AppModel。

正确 Readium 基线已包含 PR10 的 request/consume，但源码还存在：

1. BookImportModifier 始终使用多选 SwiftUI fileImporter，没有普通单选复制入口。
2. ImportResultsView 在自己页面上挂另一个 fileImporter；该页面又可能来自 FeedbackOverlay 的结果 sheet、书库结果 sheet，或 ImportHub 内 push。这会重新引入与历史类似的多层呈现争抢风险。
3. importFiles/repair 持有 security scope 后直接异步 BookImporter.read；没有本地 provider 协调读取。ICloudBackup 自身的协调读取不覆盖它们。EPUBSourceStaging 的直接 copy 保证原包留存，但也不等于 provider 协调访问。
4. 外部文件、回调、异步解析、保存、结果呈现任一环没有明确的终态，都会让用户看到“没有响应”。本次保留既有逐项结果并补齐入口交接；没有以延迟获取权限为已证明根因。

## 当前具体修改

| 文件/符号 | 行为 |
| --- | --- |
| ShelfView.swift / LocalBookPicker | 使用 UIDocumentPickerViewController(forOpeningContentTypes: [.data], asCopy: true)，默认单选；批量入口显式传 multiple=true。Coordinator 在调用 completion **之前**设置 completed，一次交付，拒绝迟到/重复回调 |
| Sources.swift / SourcesView | “选择文件”单选；另有“批量导入文件”。登记请求并关闭 ImportHub；不在其中嵌套系统选择器 |
| AppModel / request、consume、presentation gate | 保留 request/consume；记录单/批模式。呈现 token 在真正 onDismiss 才释放；最后一个宿主关闭后仅创建一次根选择器。普通请求重新设回单选 |
| TingyeApp / StudyRootView | 唯一 LocalBookPicker 宿主。发生文件请求时关闭外层阅读/播放 surface，等待 onDismiss；不是靠固定毫秒延时抢呈现 |
| ShelfView、SettingsDirectoryView、FeedbackOverlay | ImportHub/结果 modal 注册占用 token，请求时收起，onDismiss 释放。重复释放不重复弹窗。嵌套结果与外层 hub 都关闭后才放行 |
| ImportResultsView | 删除本地选择器；重选/继续仅 requestFileImport 然后 dismiss。保留逐项结果、失败原因与成功书籍 |
| AppModel / completeFileImportSelection | nil 是取消，无导入；非 nil 空数组给出“没有选中…”错误；有 URL 当场 beginImport，立即设置 busy/activity，旧提示不会遮新进度 |
| BookImporter / readCoordinated、CoordinatedBookFile | 在后台同步 NSFileCoordinator accessor 内复制 **readableURL** 到唯一私有目录，保留原文件名/扩展名；协调错误、复制错误、无交付均抛出。随后异步解析该稳定快照，defer 删除快照 |
| AppModel / importFiles、repair | scope 仍在 await 外层获取并在实际异步读取完成后平衡停止；改用 readCoordinated。owner、libraryGeneration、restoringLibrary、事务、重复书籍处理和批次部分成功逻辑保持 |
| Readium 原包 | BookImporter.read 在快照内建立自己拥有的 EPUBSourceStaging，Readium 异步文本快照按相同源包生成。provider 快照删除后，原包 staging 仍独立存在；repair/backup/source digest/Locator 代际失效不改 |

协调 accessor 只负责同步复制，不把 async Task 脱离 accessor 后继续读取 provider URL，也不阻塞主线程等待异步 Readium。scope 包住完整 await；本机复制返回 startAccessing=false 不是错误，也不会调用不匹配的 stop。

API 依据：[Apple 文档选择器](https://developer.apple.com/documentation/uikit/uidocumentpickerviewcontroller)、[复制选择器初始化](https://developer.apple.com/documentation/uikit/uidocumentpickerviewcontroller/init(foropeningcontenttypes:ascopy:))、[文件协调读取](https://developer.apple.com/documentation/foundation/nsfilecoordinator/coordinate(readingitemat:options:error:byaccessor:))。API 文档核对不代表设备行为已验证。

## 新增回归（源码已加入，iOS 尚未执行）

NativeCoreTests 追加 7 项：

- 实际 UIKit picker 复制模式、普通单选与显式批量配置。
- delegate 同步交付、重复回调抑制。
- 取消与成功空结果的区别、取消后迟到选择抑制。
- hub + result 多层占用的关闭门槛、单次消费、取消批量后恢复普通模式。
- nil 取消无忙碌/结果，空成功必须报错。
- 协调快照在 provider 源被替换后仍读原内容、清理自己的副本、丢失文件错误。
- delegate 当场开始可见进度，协调读取成功/缺失混合批次保留成功项并落盘。

ReadiumPublicationTests 追加 1 项：协调 EPUB 导入后删除外部源，内部原包 digest、章节与 Readium 可打开性仍成立。

DesignFlowTests 追加 2 项：真实系统 Files 选择一个 DEBUG TXT 并看到结果；批量取消后单选重开、结果 sheet 重选经根 picker 再取消。测试使用隔离书库；文件写入真实应用 Documents，不注入模拟 delegate 代替系统操作。Files 的语言/目录组织可能随 simulator 版本变化；若失败，应根据 xcresult 诊断真实到达路径，不能改为跳过断言。

原有 **174 单元 + 28 UI** 全部原字节作为前缀保留，新计数 **182 单元 + 30 UI**。原 fixture、test target、scheme、Tests 工作流均保持。包括原导入混合结果、EPUB import/repair、源包/备份/迁移与原书/PDF 视口回归，不得删除或放宽。

## 复现和验收步骤

1. 启动真实应用，书库 → 添书 → 选择文件；点一本 TXT/EPUB 应立即关闭选择器并出现解析/保存进度，然后反馈成功或明确失败。
2. 我的 → 设置 → 传书与导入重复同一路径；确认只出现一个选择器。
3. 批量导入混合有效/损坏/不支持文件，逐项处理，成功项保留。取消批量，再开普通入口应是单选。
4. 从导入结果页重选失败文件：结果页与外层 hub 先关闭，再出现根选择器。取消后可继续操作，不残留空白或第二个 picker。
5. picker 取消不报错、不导入；空成功回调在单元测试中给明确错误；重复/迟到回调不能执行第二次。
6. Open In、WiFi、WebDAV/OPDS/SMB 下载后的文件走既有管线；修复原 EPUB 后原书 ID、摘记、进度、源包与 Locator 迁移保持。
7. 阅读/播放器上查看导入结果后重选，也要等全部外层 modal onDismiss；关闭 reader 应正常保存阅读位置。

## Provider / 场景矩阵

下表全部 **pending device/simulator verification**，不是通过记录。

| 提供方 | 普通单选 | 批量/混合错误 | 取消再开 | 结果重选 | 修书/Open In |
| --- | --- | --- | --- | --- | --- |
| 本机 Files / On My iPhone | pending | pending | pending | pending | pending |
| iCloud Drive 已下载 | pending | pending | pending | pending | pending |
| iCloud Drive 未下载/离线 | pending | pending | pending | pending | pending |
| 实际第三方网盘 provider | pending | pending | pending | pending | pending |
| Files 中 SMB/网络 provider | pending | pending | pending | pending | pending |
| 应用内 WebDAV/OPDS/SMB/WiFi | pending | pending | pending | pending | pending |

另需覆盖小屏、最大辅助字号、VoiceOver、深色、高对比、长文件名、首次权限拒绝、读取时被撤销/替换、解析较慢的大文件。不能把本机快照单元测试当成 iCloud 或第三方 provider 的真实交付证明。

## 检查与排查

Linux 可执行 `python3 scripts/check-redesign-structure.py`、`git diff --check`、标准 Python 发布守卫单测与语法/结构检查；本机无 Xcode，8+2 项新增 iOS 回归与全部既有套件均未运行。UI 和真机完成前，发布说明必须保留未完成验收标记。

若仍出现无响应：记录入口、提供方、普通/批量、是否关闭了选择器、是否出现 busy/activity、结果列表是否有该文件、出现时的时间和应用日志。先确认实际安装版本/build/source SHA；废弃 pre1 不能用来判断此改动。然后区分“选择器未交付”“modal 未关闭”“协调复制失败”“解析失败”“写入失败”“结果页不可达”。不要要求用户复制密钥、账户凭据或书籍内容到日志。可尝试先下载到本机 Files 再选；这是定位 provider 问题的比较路径，不是故障关闭依据。
