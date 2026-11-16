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

### 2. Tests #15 唯一失败：revision 失效时保留迁移后的锚点

2026-11-16 UTC，据本次提供的 Tests #15 日志，unit-tests 共 160 个、159 通过，唯一失败为 `LocatorMigrationTests.testRevisionInvalidationPreservesReferencesAndMigratesAgain`；ReadiumLocatorTests 为 15/15，LocatorMigrationTests 为 9/10。以下为本轮定向裁定，交付状态保持**待重新验证**。

- **裁定：测试期望错误，实现保持不变。** 报错断言位于首次 `migration.convert(entry, using: bridge)` 及 `invalidated(migrated)` 之后、新文本 `changed` 构造之前，并非再次迁移后的比较。原断言把失效后的锚点与首次迁移前手写的仅含 quote 的 `entry.progress.anchor` 比较，混淆了迁移与失效两个阶段。
- **夹具证据：** 本用例使用内联 TXT 夹具；`LocatorTestSupport.book` 将传入字符串原样作为章节 text。旧文本 `第一句。目标句。` 分句为索引 0 的 `第一句。` 和索引 1 的 `目标句。`；目标句唯一且位于章末。`Locator.anchor` 从相邻至多两句拼接上下文，因此首次精确迁移得到完整 `TextAnchor(quote: "目标句。", before: "第一句。", after: nil)`，不是 before 为 nil 的手写初始锚点。新文本 `新增句。第一句。目标句。` 中目标句移动至索引 2，重定位后 before 应为 `新增句。第一句。`，after 仍为 nil。
- **合同依据：** PLAN 5.3 第 4 条要求由文本范围求出句号/跨度并“生成新的 TextAnchor”；第 5 条要求无效/变版走 TextAnchor 重定位，禁止覆盖的是失败条目的旧文本与锚点；第 6 条明确 TXT 同样采用逻辑 Locator。本文“PLAN 5.3 转换合同”已明确精确/文本重定位成功时可更新兼容坐标/锚点，失败或 unresolved 不更新。因此“保留旧引用”不等于成功迁移后锚点必须逐字段维持初始值。
- **实现依据：** `LocatorBridge.resolve` 对 TXT 先经 `textTarget` 验证/重定位，再由 `logical` 按当前文本调用 `Locator.anchor`；`LocatorMigration.convert` 仅在 precise（exact / textRelocated）时回写兼容坐标与锚点。`invalidated` 仅清四类引用的 publicationRevision，保留传入的已迁移锚点，不负责恢复迁移前数据。这也与构建 142 以来 `AppModel.repair` 调用 `Locator.resolve` / `Locator.relocated`、位置移动时按新文本重建并回写锚点的既有语义一致；此处上下文没有取错句子。
- **最小修改：** 仅在该用例把失效保留断言的比较对象从 `entry.progress.anchor` 改为 `migrated.progress.anchor`，并增加首次迁移和再次迁移的上述两个完整 TextAnchor 等值断言，明确检验 quote、before、after。原有 revision、Locator 存在性、位置 2 和反向转换断言全部保留，未删除或弱化断言。另一个实际锚点上下文生成缺陷未在本轮排查路径中发现。
- **验证与范围：** 本轮仅修改 `TingyeTests/LocatorMigrationTests.swift` 中该方法与本文追加记录；已做修改前后文件内容/校验值对照、断言及夹具/上下文规则静态核对。未修改实现、其他测试、构建号 142、workflows、依赖或工程配置，未做 git 操作。本环境无 Swift / xcodebuild / iOS SDK，未执行 XCTest、未触发 CI；须在 Mac/CI 重新运行该用例及 unit-tests，不能据静态核对宣称 160/160 通过。

### 3. Tests #16 三例跨运行不稳定：迁移等待边界与 WebKit 就绪条件

2026-11-16 UTC，据提供的记录，Tests #15 为 159/160，#16 为 157/160；两次之间 App 代码未变。此次仅修改 `AppModel.swift` 的迁移调度、下述三个测试及本文；交付状态保持**待重新验证**。下面区分可由代码证明的缺陷、能产生所报结果的执行交错与尚无运行轨迹证明的部分；15.572 秒耗时只说明不能依赖通常的执行速度，不能单凭耗时认定磁盘、Readium 或 WebKit 故障。

**逐例裁定与证据（失败行号指修复前，其他行号指修复后）：**

| 用例及原失败点 | 根因裁定 | 代码证据与结果来源 |
| --- | --- | --- |
| `testAtomicAppMigrationCreatesSnapshotAndCanBeRetriedAfterFailure`，原 `LocatorMigrationTests.swift:97` | **实现调度竞态，显式 async 等待边界错误**；Locator 非 nil 的期望正确。 | `AppModel.init:125–130` 自动安排空闲扫描；原 `migrateLocators` 安排任务 A 后仅等待一次 `locatorTasks[id]?.value`。原空闲循环无条件调用 `scheduleLocatorMigration`，后者取消 A、发布新 token 和任务 B（现 `AppModel.swift:814–826` 仍是前台防抖入口）。A 的取消处理及 defer 都只处理自己的 token，因此不会清掉 B；等待 A 的调用者却已经可以返回，磁盘 catalog 尚未被 B 提交，Locator 仍为 nil。快照在转换前写入（`:830`），所以“快照已经存在”也不能充当“catalog 已提交”的条件。 |
| `testRepairSameIDRevokesOldLocatorAndRelocatesOnlyOnPreciseConversion`，原 `:138–139` | **同一实现调度竞态导致读取修书后、迁移提交前的合法中间状态**；两个 0 的期望都正确。 | 这里比较的不是迁移计数：`progress.chapter` 与 Locator `locations.tingyeChapter` 都是零基章节索引。夹具把唯一的 `目标句。后句。` 从旧索引 1 移到新索引 0。`repair` 对 EPUB 保留旧兼容坐标，`LocatorMigration.invalidated:33–42` 仅清 revision、保留旧 Locator，故此时两字段都仍为 **1**。若 A 被空闲扫描替换而显式等待提前结束，测试恰好读到这两个旧值；`XCTAssertNotEqual(nil, oldRevision)` 还会通过，不能证明已迁移。`LocatorBridge.textTarget:103–153` 应在旧第 1 章找不到 quote 后找到唯一的新第 0 章；`resolve:155–219` 生成 `tingyeChapter = 0`，`LocatorMigration.convert:52–54` 仅在 precise 时把兼容 chapter 更新为 0。因此应修等待边界，不能把期望改成 1。 |
| `testOriginalReaderRestoresSavesAndJumpsWithoutSpeech`，原 `NativeCoreTests.swift:1808` | **测试异步写法缺少完成条件**；页差 `0...1` 的期望保留。没有证据把它归因于迁移共享状态。 | `OriginalBookView.Coordinator.restorePosition:421–425` 先清 pending，再异步发 `.defaultClient` JavaScript，completion 为 nil；`apply:536–544` 自身也异步，`didFinish:558–569` 另有 400 ms 后的布局校正，`viewportDidChange:427–442` 有 120 ms 防抖。旧测试用 700/500/400 ms 固定等待代替这些操作的完成条件，并在两次显式 restore 后立即从 `.page` 查询页码。`settled:505–515` 的保存回调只证明读出了目标页的句号，不证明 DOM 与 UIKit 的滚动位置已一致。因而 `manualPage` 与 `restored` 可能取自不同阶段，页差越界不等于句级恢复合同错误。修复的是这些可证的等待缺口；没有 #16 的 WebKit/任务时间线，不能宣称已经实测重现其唯一调度顺序。 |

前两例可静态构造同一执行序列：显式调用创建 A 并等待 → 空闲扫描取消 A、创建 B → A 在取消检查处退出（若正在等待 detached I/O，需先等该 I/O 返回）→ 调用者恢复执行、读取旧 catalog/旧章节 → B 稍后才提交。此交错不需要两个测试共享 AppModel，也不需要测试执行顺序变化。最终 catalog 校验/写入均在 MainActor 且中间不 suspension，因此不是半写 catalog。

**repair、快照/receipt 与共享状态核对：**

- `AppModel.repair:616–675` 在导入/准备期间持有 `publicationWrites`，提交时清 revision、更新会话 generation，并安排新迁移；迁移提交前还校验库代次、owner、同书写锁、任务 token 及四类引用 token（`:854–858`）。旧任务在 repair 之前完成只会写旧书的合法结果；repair 期间不能提交；repair 后旧 token 或含旧 revision 的引用快照不能通过校验。本路径没有证据需要另加 repair 撤销/提交锁，原会话回写屏障断言完整保留。
- `LocatorMigration.swift:98–118` 先保存首次全库 catalog 备份，再保存每书本次引用快照。`AppModel.swift:865–868` 顺序为原子 catalog → 内存 entries → 尽力写 receipt → 内存 committed；receipt 是诊断，不是事务权威，写盘失败被允许，不能反过来据 receipt 存在推断本次重试完成。测试现在同时检查终态、内存与磁盘结果；故障阶段仍要求 catalog 字节不变，重试后首次 catalog 快照也要求字节不变。
- 原两个测试已经各有 UUID 临时 base 和 defaults suite（`LocatorTestSupport.temporary:12–16`），KVS 是独立 `LocatorKeyValueStore`、account=false、同步关闭；不存在它们共同写同一 catalog 或标准 ProgressSync 时钟的证据。`LocatorMigration`、AppModel entries/tasks 和 `ReadiumService` 都是实例状态。原 book ID 固定为 `locator-book`，owner 固定；`PublicationStore.swift:19–21` 的派生缓存路径只取 owner，不含临时 base，故修书测试跨运行会复用缓存命名空间。内容 hash/epoch 可防止直接选错内容，但旧清理只 cancel、不 join，也不清缓存，不能用这种清理保证后台工作不跨用例存活。
- 本轮两个测试改用独立 UUID book ID、owner、defaults suite 和临时 base；`LocatorMigrationTests.isolatedModel:17–32` 注册 async teardown，在临时目录删除前调用现有 `beginLibraryRestore:296–307` 暂停写入并取消、等待索引与迁移，再清理该 owner 的缓存和 defaults。清理用于隔离，不作为成功断言的替代。修书中 replacement 仍通过 repair 强制采用原书 ID，继续覆盖同 ID 合同。
- Native 用例自身创建 WKWebView/Coordinator，websiteDataStore 已为 nonPersistent，不读 catalog/KVS；`OriginalDocument.html` 默认使用新的 ReaderPreferences 值。唯一相关的静态分句 memo（`OriginalBookView.swift:67–77`）由完整文本键控并加锁；没有复用别本书分句的证据。本轮在 defer 中撤销 delegate/callback、停加载并改变 document key，使延迟 apply/viewport 回调失效。AppModel 的 SpeechPlayer 构造会读取标准语音配置，但本例不构造播放器、不读取该配置；不能把这种全局读取当作三例的泄漏根因。

**最小修复及确定性：**

- `AppModel.swift:780–809`：空闲扫描发现同书任务时直接等待，不调用前台防抖入口取消它；显式 `migrateLocators` 循环等待当前任务，如果等待期间已有新的前台任务替换它，就继续等待替代任务。默认 2 秒空闲启动、前台 200 ms 防抖及编辑取消语义保持不变。空闲方法增加 `after` 参数，默认仍为 2 秒，测试传 `.zero` 强制制造重叠，避免依赖 CI 负载碰巧跨过 2 秒。
- 原子迁移测试（`:102` 起）在显式任务的防抖窗口触发空闲扫描，要求状态只经过 waiting → running → completed(exact:1)，并保留坏 JSON 故障与重试断言。即使显式等待被修好，若空闲路径回退到取消重建，额外 waiting 仍会使测试失败。修书测试（`:138` 起）也强制该重叠，新增 reading/bookmark/highlight 三项均为 textRelocated、completed(relocated:3)、receipt revision 及磁盘进度一致的断言，再检查原有 chapter/tingyeChapter=0。此处的 relocated:3 才是引用条数，与原失败的章节索引无关。
- Native 测试（`:1730` 起）删除全部固定 sleep，保留手动保存 expectation；其余操作按条件轮询，10 秒是失败上限、20 ms 仅是轮询间隔，不是“睡够即可通过”。等待要求加载完成、pending 已被消费、字体已加载、目标句首字在指定视口内、DOM 已停在目标整页、UIKit 与 DOM 横向位置一致；页码读取统一在 `.defaultClient`，最后也等待同 world 的请求完成。原有页差、跳转、缩放几何、无朗读标记、旧回调不能覆盖新 revision 等所有断言均保留，超时立即失败并抛错，不带默认页继续执行。此条件不能保证 WebKit 永不超时，但不会因机器快慢而在未就绪时拿中间页码充当结果。
- PLAN 5.3 第 7 条的“先备份、每书原子、可取消、可重复”与本文既有事务口径均不变：只改变谁等待/替换任务及测试何时观察结果；没有改转换等级、precise 写兼容字段、unresolved 保留业务数据、catalog 权威或 receipt 尽力落盘的合同。

**范围外发现，仅记录：** `snapshotForLocatorMigration:102–104` 的首次全库快照是 fileExists 后再原子写，两个不同书的 detached 快照任务可同时看到文件不存在；若其中一本先提交 catalog，另一个随后读取/覆盖备份，首次备份可能含已迁移内容。`.atomic` 不等于“仅首次创建”。这是多书并发下的独立实现缺陷；本次三个测试各只有一书，没有以它解释本次失败，也没有按本轮要求扩大修复范围。后续应单独做首次快照并发创建的事务保护与多书回归。

**实际验证与待验证项：** 已用修改前文件副本做逐方法比较，确认只改这三个测试、原断言全部保留、测试方法数不变；两个内嵌 JavaScript 块经 Node 语法检查通过。文件 SHA-256 清单核对只允许上述四个文件改变，构建号 142、workflows、依赖/锁文件及工程配置均未改；未执行任何 git 操作。环境无 Swift、xcodebuild、iOS SDK，因此未进行 Swift 类型检查、XCTest 或真实 WebKit 复现，不能把静态交错分析记为测试通过。Mac/CI 仍需分别单跑三例、合跑 LocatorMigrationTests → NativeCoreTests、重复运行全量 160 例，并确认独跑/整套结果一致；状态保持**待重新验证**。
