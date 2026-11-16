# Readium 单元 3：Locator、范围标注与统一跳转

实施日期：2026-11-16 UTC。动手前完整阅读 PLAN、UNIT1、UNIT2；实现使用固定的 Readium 3.11.1 与 SwiftSoup 2.13.5 API。本轮没有任何 git 操作，没有触发 CI，没有改构建号 142、workflow、依赖版本或锁文件，没有改其他格式的导入器与排版引擎。

交付状态：**已按 CI 报错修复，待重新验证。** 实现、工程挂接及 25 个 XCTest 方法已落盘；据本次提供的 CI 日志，Build #30 成功，Tests #14 的 unit-tests 与 ui-tests 在编译阶段失败，0 用例执行。不能记为单元 3 验收通过。本环境只有 Linux/Python/Node/GCC，没有 swift、xcodebuild 或 iOS SDK。

## 改动清单

| 文件 | 实际改动 |
| --- | --- |
| `Models.swift` | ReadingProgress（含 listeningProgress）、Bookmark、Highlight 各增加 Optional locator / locatorVersion / publicationRevision；保留旧坐标、TextAnchor、ID、日期、全文与笔记。未重命名听页自有 `enum Locator`。 |
| `Readium/StoredLocator.swift` | 听页 JSONValue 对象包装，使用 Readium JSON API 校验/桥接，不假定 Readium Locator 是 Codable。缺键与非法对象仅清空该 Locator；有效未知扩展保留；编码 nil 时省略字段。校验 progression、totalProgression、position 和体积。 |
| `Readium/TextDOMIndex.swift` | 原生 UTF-16、规范化文本与 DOM 文本节点索引，CSS selector / textNodeIndex / charOffset 范围；处理实体、标题、空白、表格、ruby、脚注、emoji。XHTML 使用 XML 解析，避免隐式 tbody 改变 selector；HTML 使用 HTML 解析。共用 TextOffsetMap 支持长度变化与不确定替换块。 |
| `Readium/LocatorBridge.swift` | LocatorTarget、双向转换、四级解析状态及置信度、资源映射、受限全书查找、完整划线范围、原文/显示文 Locator 投影、逻辑页/章 href。显式使用 ReadiumShared.Locator / ReadiumShared.JSONValue。 |
| `Readium/LocatorMigration.swift` | 每书快照、四类引用转换、引用快照 token、取消/重试、按书状态与 receipt；仅 precise 结果更新兼容坐标/锚点，approximate 进度保留原坐标，unresolved 标注逐字段原样保留。 |
| `AppModel.swift` | 打开书优先迁移，空闲扫描书库，CRUD/进度后补齐；提交前核对库代次、owner、同书写入锁及四类引用 token；原子 catalog 提交。修书/同 ID 替换撤销 Locator revision；还原取消并等待在途任务。阅读跳转携带完整 LocatorTarget；同 ID 替换的会话代次屏障阻止旧 Navigator 回写。 |
| `Readium/EPUBDisplayTransform.swift`、`ReadiumService.swift` | 通过 Publication.Builder 与 TransformingContainer/TransformingResource 按需转换正文文本节点；整段 ICU 简繁转换保留词语语义，映射由同一纯函数生成。关闭时原容器/字节直通。按 manifest MIME 识别 XHTML/HTML，不只看扩展名；不写 source.epub、派生包或 Book.text。 |
| `Readium/ReadiumAnnotations.swift` | user / tts / search 三组命名隔离；仅应用 user。五种现行颜色加旧 green；background、underline、自定义 wavy 模板；选区 DOM 范围捕获；无法精确投影时不生成 Decoration。 |
| `EPUBNavigatorHost.swift` | 选区菜单划线/书签/笔记，实际 DOM 范围附到选区 Locator；Decoration 数据刷新与点击；分页位置结合首个可见元素 Locator 与有界 DOM 范围搜索定位可见字符，长段落中间翻页也保留字符偏移；保留初始化、请求 UUID 和旧 Navigator 隔离。 |
| `ReadiumReaderView.swift` | 顶栏书签切换；原文 Locator 落盘；选区映射回章句/范围后走 bookmark / addHighlight；复用 SelectionPanel/NoteEditor 编辑、删除、改色/样式；目录、书签、摘记、搜索都经桥；逐条显示未定位标注。简繁切换以原文位置重开显示资源。 |
| `Library.swift` | 继续使用原有划线合并/排序/笔记 CRUD；CRUD 后补 Locator；增加按 UUID 删除书签通道。 |
| `ReaderView.swift`、`ReaderAnnotations.swift` | ContentsView 可传完整目标，搜索保留 UTF-16 命中范围；共用标注列表可显示未定位状态。原生排版仍使用原章句/页号。 |
| `LibraryViews.swift`、`NotesUnifiedView.swift`、`DailyQuoteCard.swift`、`BookFinishView.swift`、`PlayerView.swift` | 详情书签不再丢失锚点/Locator；摘记、今日一句、收尾摘句与 EPUB 听书返回原文携带完整目标。非 EPUB 播放器返回保留原分支。 |
| `ICloudBackup.swift` | KVS 在 c/p/t 旁双写有上限的 Locator / anchor / revision / version，Locator 感知去重，旧端同句回声不抹去精度；继续单调时钟及阅读保护。归档还原撤销旧 revision。归档与 BackupPacket 的现有范围自动保留模型新字段，没有扩大单书 packet 到书签/划线。 |
| `Tingye.xcodeproj/project.pbxproj` | 五个新 app Source、两个新 test Source 各唯一挂接；已有 Fixtures folder resource 自动包含新文本夹具。生成器原有递归扫描已覆盖，无需改生成器或增加 Toolkit product。 |
| 两个新测试文件及 `Fixtures/readium/` | 25 个 XCTest 方法；catalog-141 / catalog-142 / locator-book JSON 文本夹具；沿用 original.epub.b64 的临时解码方式。未加入二进制文件。 |

## PLAN 5.3 转换合同

| 合同 | 落实情况与边界 |
| --- | --- |
| 1. 旧引用选资源 | 原包复用 PublicationMap 的规范 path / 唯一标题映射；派生包用显式章映射，绝不按 spine 下标配章。文本层先调用 142 Locator.resolve 并验证 quote/全文；本章不存在匹配才受限扩展。存储标题、上下文参与消歧，模棱两可时拒绝精确匹配。 |
| 2. 文本与 DOM 对齐 | TextOffsetMap 保留规范化 UTF-16 到原始范围，TextDOMIndex 保留 DOM 节点范围。142 拼接上下文先去空白再比较；保存 DOM 实际 before/highlight/after，另外写 domRange、tingyeRange、tingyeChapter。不把 locations.position 写成句号。 |
| 3. 完整划线 | 同资源一个范围，使用 Highlight.text 全文与句跨度恢复尾端；>120 字不会截成起始锚点。已存 Locator 也需校验完整 highlight 文本。选区持久化原文范围，同时保留 Navigator 其他扩展；简繁显示选区只在内存中存在。 |
| 4. 反向转换 | href 映射章，DOM 范围/quote 对齐 UTF-16，Sentence.index 得 start/end，并生成新 TextAnchor。未映射资源的选区可在预算内用全文查找原生章；没有唯一原文依据则 unresolved。Readium 首个可见元素的 CSS selector 也可回到原文句。 |
| 5. 优先级与失败 | 同 revision 有效 Locator → TextAnchor/全文重定位 → 有效 href + progression → 钳制章句的资源开头。exact=1、textRelocated=0.9、approximate=0.25、unresolved=0；这些是算法等级分数，不是实测成功率。标注不使用仅比例的近似范围；找不到时保留全部业务数据。初始化/显式跳转未确认前不保存默认页。 |
| 6. 非 EPUB | TXT/Markdown/MOBI/DOCX/HTML 用 tingye://book/<id>/chapter/<n>、text/plain、tingyeRange；PDF 用 page href 和 page fragment；漫画用 page href、实际图片 MIME 与资源引用扩展。仍进原生视图，未改其导入/排版。逻辑 Locator 可由桥反解。 |
| 7. 迁移事务 | 先保存全库原始 catalog 备份，再保存每书本次条目快照；后台生成候选，提交时校验快照仍有效，单次原子写 catalog。转换抛错/取消整书不提交；混合结果中 unresolved 引用原样保留，其他可解析项可同书提交。 |
| 8. 同步与备份 | KVS 双键仍有 c/p/t；Locator ≤8 KiB、anchor ≤2 KiB、revision ≤256 UTF-8 字节；超限只省扩展。每 10 次推送按原时间排序清理，保留 ≤900 个进度键并控制约 768 KiB 占用。整库含四类引用，单书 packet 仍只有阅读进度；非法 Locator 字段隔离。 |

旧坐标/锚点字段保留供旧端和文本层使用。精确/文本重定位成功时可更新其值，使书签状态、合并与排序继续对应当前文本；快照保存迁移前数据。失败或 unresolved 不更新这些值，不删除标注。approximate 只用于导航/进度，不作为精确划线。

## 调度、事务和状态口径

- AppModel 初始化/还原后延迟 2 秒扫描本机书；空闲扫描遇到正文、音频或还原会等待，不占启动同步路径。打开书、保存位置与标注 CRUD 有独立优先路径，同书 200 ms 防抖并取消旧任务。
- 书籍读取、快照写入、文本查找、DOM 构建与逻辑 revision 计算在后台；Navigator/Publication API、状态发布与最终 catalog 原子提交在 MainActor。提交复用原书库写盘方式，未做新大库性能测量。
- 每书转换进度、听书进度（存在时）、全部书签与划线。提交前校验 libraryGeneration、owner、publicationWrites、任务 token 与四类引用快照；用户期间编辑导致取消时会重新排队；也可通过后续打开/保存/显式重试再跑。没有把部分候选发布到内存。
- `locatorMigration.states[id]`：waiting / running / cancelled / failed(reason) / completed(四级计数)。completed 表示事务成功提交，**不代表全部 exact**；unresolved 数量必须参与验收。
- `locatorMigrationReceipt(id)` 可取内存或持久 receipt，包含 bookID、revision、转换版本、每条引用的状态与时间。文件位于 `LocatorMigration/<id>-receipt.json`；`catalog-before-v1.json` 保留首次全库快照，`<id>-before-v1.json` 原子保存本次书条目快照。receipt 写入为诊断，不代替 catalog 权威数据。
- `migrateLocators(id)` 可显式重试，`cancelLocatorMigration(id)` / `cancelAllLocatorMigrations()` 可取消。中断没有完成标记依赖；重新执行按现有数据重算。修书/替换清 revision 后重跑；还原取消并等待后台任务结束，原包/派生缓存继续复用单元 1 的持久代次机制。
- 同 ID 替换同时更新会话代次并重开显示资源；携带旧代次的 Navigator 进度/书签不能写入新条目。阅读与听书继续写各自字段，听书不推阅读 KVS；阅读 Locator 首次补齐需要同步时仍用原混合时钟。

## 有界处理与未做项

索引资源读取最多 4 MiB；单资源原生/DOM 文本合计超过 350,000 UTF-16 单位会明确失败，缓存按约 16 MiB 估算成本做 LRU 淘汰。全书原生搜索最多前 512 章、8 MiB 文本；资源候选最多前 64 个 readingOrder 项、8 MiB DOM 文本；重复 quote 候选最多 256；可见字符扫描最多 12,000 个 DOM 文本节点并在节点内二分定位。预算之外不承诺定位成功，不将其伪装成精确匹配。实际峰值还包含解析器、在途索引和 Book，不能把缓存预算写成应用总内存实测值。

简繁按完整文本节点调用 ICU，保留词语转换语义；只转换正文文本，不改属性、CSS、脚本或隐藏 head 内容。长度变化使用同一映射；不能确定内部字符边界的替换块只承认有据可依的整体边界，内部选择不制造精确范围，Decoration 保留未定位状态。关闭转换时返回原资源。本轮未完成大书、特殊字形/竖排/fixed-layout 的设备覆盖，不能据静态映射宣称全部显示选区已验收。

本单元没有实现跨资源选择分段数组（任务合同留未来扩展），没有实现句级 TTS Decoration / 搜索 Decoration（仅保留分组）；没有替换 EPUB 文本导入结构解析器，没有增加 source 备份附件。这些仍属于单元 4。没有新做异常杀进程、ENOSPC、真实 iCloud 多设备、VoiceOver 选区或性能测量。无原生文本对应且无唯一 quote 的额外资源仍只允许浏览，不伪造文本章来创建标注。

## 测试与实际验证

新增 `ReadiumLocatorTests.swift` 15 个方法、`LocatorMigrationTests.swift` 10 个方法，覆盖：141/142 四类引用与往返、重复 quote/上下文、长多句划线、emoji UTF-16、实体/空白、表格/ruby/脚注、简繁开关与词语语义、长度变化映射、spine 改动与缺 path 资源搜索、原包路径、重复 path、空/插图型资源、五色加旧 green × 三样式、逻辑全格式、非法字段、幂等/取消/重试、unresolved 保留、真实同 ID 修书调用、catalog 写入失败、KVS 新旧字段/去重/上限、归档与 packet 现有范围。

实际执行的只有 `/tmp/readium-unit3/validate.py`：

1. 完整解析 OpenStep pbxproj，共 203 个对象；检查所有对象引用、Sources 实际文件；7 个新 Source 唯一挂接至正确 app/test target。四处显式 CURRENT_PROJECT_VERSION 都为 142。
2. 修改 Swift 文件的词法定界符/注释/普通与 raw 字符串/插值闭合、行尾空白检查；三个模型均有可选 Locator 包装；听页旧 `enum Locator` 仍在原位置。
3. 新 JSON 夹具可解码，141 缺 anchor、142 有 anchor，四类引用齐全；现有 base64 EPUB 可解码且 ZIP CRC/XML 检查通过。新文件均为文本。
4. 对照动手前 SHA-256 快照，workflows、Package.resolved、create-project.rb 未改变；未新增依赖或构建号。
5. Node 对两个嵌入脚本执行语法检查；`/tmp/readium-unit3/check-js.cjs` 在 mock DOM 中验证长段落多个可见起点、emoji 代理对边界及选区 UTF-16 偏移。通过，但不代表真实 WebKit/滚动/分栏/竖排验收。

以上不是 Swift 类型检查、XCTest 或 UI 测试。没有执行 xcodebuild、SwiftPM resolve、archive、EPUBCheck，也没有观察 CI。接下来须在 Mac/CI 跑两个新测试类、ReadiumPublicationTests、ReadiumPreferencesTests 与全量 TingyeTests，再做原包/派生包、所有跳转入口、选区/CRUD、简繁重开、修书/还原及 KVS 双端的 UI/设备回归。

API 核对使用版本化上游源码：[Locator](https://github.com/readium/swift-toolkit/blob/3.11.1/Sources/Shared/Publication/Locator.swift)、[DOMRange](https://github.com/readium/swift-toolkit/blob/3.11.1/Sources/Shared/Publication/Extensions/HTML/DOMRange.swift)、[TransformingContainer](https://github.com/readium/swift-toolkit/blob/3.11.1/Sources/Shared/Toolkit/Data/Container/TransformingContainer.swift)、[TransformingResource](https://github.com/readium/swift-toolkit/blob/3.11.1/Sources/Shared/Toolkit/Data/Resource/TransformingResource.swift)、[SelectableNavigator](https://github.com/readium/swift-toolkit/blob/3.11.1/Sources/Navigator/SelectableNavigator.swift)、[DecorableNavigator](https://github.com/readium/swift-toolkit/blob/3.11.1/Sources/Navigator/Decorator/DecorableNavigator.swift)、[HTMLDecorationTemplate](https://github.com/readium/swift-toolkit/blob/3.11.1/Sources/Navigator/EPUB/HTMLDecorationTemplate.swift)、[SwiftSoup 2.13.5](https://github.com/scinfu/SwiftSoup/blob/2.13.5/Sources/SwiftSoup.swift)。未按 main 或 4.x API 编写。

## 对照 PLAN 单元 3 验收

| 验收项 | 本轮状态 |
| --- | --- |
| 四类旧无/有 anchor 转换、重复 quote、长范围、UTF-16、实体/空白 | 已实现并写测试；未执行，待 Mac。 |
| 表格、ruby、脚注、插图章、spine 增删重排、重复 path、修书/替换 | 有对应实现/测试，预算与未映射资源按上述保守规则处理；真实出版物及非线性 UI 未实测。 |
| 所有阅读恢复/书签/搜索/摘记/今日一句/听书跳阅读统一 | 已接 LocatorTarget/LocatorBridge，详情书签缺口已改；全部入口 UI 未实测。 |
| 五色加 green、三种样式、全文范围、笔记/ID/date 保留 | Decoration/现有 CRUD 已接，数据测试已写；波浪线及竖排视觉未实测。 |
| 阅读/听书互不覆盖、迁移打断可重跑、unresolved 保留可见 | 有独立字段、事务状态、快照与未定位提示，取消/失败/修书测试已写；进程被杀与大库性能未实测。 |
| 简繁资源、原文/显示选区往返 | 包装与共用映射已实现，纯函数/桥测试已写；不确定内部边界拒绝精确标注；完整设备矩阵未验收。 |
| Locator JSON 往返、非法字段隔离、旧备份/设备兼容 | 模型/KVS/归档实现与测试已写；未执行 XCTest 或真实旧端往返。 |
| 非 EPUB 逻辑 Locator 与原生引擎 | 全格式逻辑 href/范围可双向转换，未改其他格式导入和排版；原生全量回归未执行。 |
| 同句精细更新不被 c/p 去重吞掉、KVS 单调时钟/阅读保护 | Locator 感知更新和有界兼容字段已接，单测已写；真实 iCloud 尚未测。 |
| 工程、测试资源、失败不破坏 catalog | 静态工程/夹具检查通过，原子提交与失败测试已写；Swift 编译、iOS 文件系统故障与 CI 尚未验证。 |

## CI 修复记录

2026-11-16 UTC，针对提供的 Tests #14 编译日志定向修复；交付状态为**已按 CI 报错修复，待重新验证**。

- `ReadiumLocatorTests.swift:218` 的 `[JSONValue]` 与 `ReadiumShared.JSONValue` 撞名，导致编译歧义及 ui-tests 中 `.string` / `.object` / `.number` 的级联错误。逐处核对后，将该数组类型、同测试内的解码类型及编码构造共三处全部限定为 `Tingye.JSONValue`：它们承载听页模型的 Codable 枚举，不使用 `ReadiumShared.JSONValue`。
- `LocatorMigrationTests.swift:34` 的幂等性断言第二个 `LocatorMigration.token(next)` 调用缺少 `try`，已补齐；断言两侧与预期含义保持不变。
- 排查范围覆盖两个新文件 `ReadiumLocatorTests.swift`、`LocatorMigrationTests.swift`，以及其余全部导入 `ReadiumShared` 的测试文件 `ReadiumPublicationTests.swift`、`ReadiumPreferencesTests.swift`。逐项检查显式类型引用，包含 `JSONValue`、`Link`、`Locator`、`Location`、`Decoration` 及其他模型/偏好类型；并核对测试目录中的 ReadiumShared / SwiftUI 导入情况。
- 防复发补齐两处限定：旧文本锚点工具调用使用 `Tingye.Locator.anchor`；装饰样式配置使用 `ReadiumNavigator.Decoration.Style.HighlightConfig`。原有 `ReadiumShared.Locator` 构造已限定并保留；排查文件没有 `Link`、`Location` 的显式类型引用，没有其他未限定的上述同名类型。其余显式引用为标准库/Foundation/XCTest 类型、听页自有模型或唯一的 Readium 类型（如 `EPUBPreferences`、`AnyURL`），未发现其他同名歧义风险。两个既有测试文件无需修改。
- 本轮仅修改上述两个新测试文件与本文档；未改断言预期值或测试逻辑，未做 git 操作，未改 App、构建号 142、workflows、依赖或工程配置。已静态核对六处代码修改仅为五处类型限定与一处 `try`，保留全部 25 个测试方法，并对照修改前文件校验值检查改动范围。
- 本环境无 Swift / xcodebuild / iOS SDK，未执行测试编译或 XCTest，也未触发 CI；需在 Mac/CI 重新验证 unit-tests 与 ui-tests，不能将本次静态核对记为编译或用例通过。
