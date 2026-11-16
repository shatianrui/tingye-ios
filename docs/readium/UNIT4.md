# Readium 单元 4：文本快照、句级听书、搜索、原包备份与回归

实施日期：2026-11-16 UTC。依据为完整 PLAN、UNIT1–3 及 `/home/hatch/workspace/readium-ui-audit-notes.md` 的最终三方对齐。构建号保持 **142**，营销版本保持 1.25.0；没有 git 操作，没有改 workflows、Package.resolved 或依赖约束，没有触发 CI/发布。

交付状态：**实现、工程与测试源码已落盘，等待 Mac 编译和运行验收。** Linux 没有 swift、xcodebuild、iOS SDK、模拟器；本轮 XCTest/UI 执行数均为 0，不能把静态检查记为 173/173 或 28/28 通过，UI 恢复全绿目标尚未获得实测证据。全量清单见 [ACCEPTANCE.md](ACCEPTANCE.md)。

## 改动清单

| 文件 | 改动 |
| --- | --- |
| `Readium/EPUBTextSnapshotBuilder.swift` | 从原文 Publication 的 readingOrder/resources/TOC、metadata、cover service 生成 Book 与 PublicationMap；兼容 HTML/CSS/图片快照、marks、nativeImages，保留插图章与空章。另定义可选原包附件和备份恢复生产线。 |
| `BookImporter.swift`、`AppModel.swift` | read 改 async；EPUB 留存副本后只经 Readium 打开和 SnapshotBuilder，移除旧 epub 结构解析函数。导入/修书的授权、staging、owner/代次与提交回滚继续沿用。其他格式分支只跨越 async API 边界，解析规则未换。 |
| `Readium/ReadiumSpeechBridge.swift`、`ReadiumReaderView.swift`、`PlayerView.swift` | 当前可见原文 Locator→句位置，播放句→Locator/显示 Decoration，播放器返回共用句目标；EPUB 面内暂停/继续、停止跟随/回到朗读。复用现有 SpeechPlayer published 事件，无需改 SpeechPlayer 或其他格式听书。 |
| `Readium/EPUBNavigatorHost.swift` | 分别 diff/apply user、tts、search 三组；新 Navigator 三组都重新应用，暂停清空 tts 不会清 user。 |
| `ReaderView.swift`、`ReadiumReaderView.swift` | 复用原搜索与 ContentsView，补 EPUB 真实命中范围、确认导航后显示两秒 search Decoration；原生单书导出补可选附件。 |
| `Models.swift`、`ICloudBackup.swift`、`LibraryViews.swift` | BackupPacket 与 ICloudArchive.Item 新增可选 epubAttachment，所有单书/整库/iCloud/本地文件出口带原包；整库恢复在隔离书库中重建快照并事务提交。许可证页列出实际锁定组件、上游和许可来源；新增 Pow 许可全文资源。 |
| `Services.swift`、`PublicationStore.swift`、`AppModel.swift` | 无附件替换清 source 和 source map；校验 revision 后复用快照映射；恢复撤销旧会话 generation；pin 名带进程随机前缀，清缓存保护所有同进程 Store 的 pin，清除上次进程孤儿。 |
| `StorageView.swift` | 原包作为不可清理的书库分项；文本/摘记与原包不重复相加，派生缓存可单独清理。通用缓存清理排除整个 Readium 目录，交共享 Store 清理。 |
| `Readium/LocatorMigration.swift` | 同进程所有 LibraryDisk 实例共用 NSLock，覆盖首次 catalog 的检查、读取、原子发布；后续书/重试不能覆盖首次备份。 |
| `ShelfView.swift`、`DesignFlowTests.swift` | 续读卡标题/章节有独立标识；四个过期 OriginalReader 改为 EPUB 断言；两项时序敏感测试保留原场景并补状态等待；新增派生 EPUB 冒烟/搜索流程。 |
| `ReadiumTextSnapshotTests.swift`、`ReadiumBackupSourceTests.swift`、`LocatorMigrationTests.swift` | 新增 6+6+1 个用例；现有导入/恢复测试只适配 async，原错误断言保留。snapshot.epub.b64 是原创文本夹具。 |
| `project.pbxproj` | 两个 app Source、两个 test Source、Pow 许可 Resource 唯一挂接。生成器已递归收集 Swift 和 Resources，不必修改或运行。 |

## 文本层与旧解析路径

新 EPUB 调用链：security-scoped URL → EPUBSourceStaging 私有副本/摘要 → ReadiumService.open → SnapshotBuilder → Imported → prepareImport/commitImport。Readium 打不开或不支持的正文类型会明确报错，不调用旧解析器兜底。标题优先 TOC（保留层级供阅读目录），其次资源标题；作者、简介、分类、语言和封面来自 Publication。缺 TOC 可用资源标题与默认章名。快照按 Readium readingOrder 逐项生成，不按旧 OPF 解析器重新裁定顺序。

正文抽取直接复用 HTMLText.chapter；分句仍用 Sentence.split，包括实体/空白、ruby、表格、emoji UTF-16 与长句拆块规则。标题换成 TOC 标题不会改正文 text。document HTML/CSS/图片是供旧端和原包缺失时派生的兼容快照，EPUB 显示继续读取原包。PublicationMap 以 `epubTextMap` 写入 Book，并随原包 revision 校验后使用。

旧 `BookImporter.epub` 已删除，**剩余调用方为零**；SafeArchive 仍由 `BookImporter.docx` 与 `ComicImporter.book` 使用。后者位于 MobiReader.swift 的漫画部分，并非 MOBI 使用 ZIP/OPF；SafeArchive 的兼容测试继续保留。XMLNode 仅供 DOCX，resolve 仍供安全资源路径解析。存量 Book 不重算 text，仍由 LegacyEPUBBuilder 按旧数据生成派生包。恢复带原包的备份才按本单元要求重建源快照。

兼容快照支持 XHTML/HTML 和 SVG 正文的文字抽取；纯插图 XHTML 与空章保留。直接以其他媒体作为 readingOrder 的包会报正文格式错误，不伪装成成功文本导入。未测竖排、SVG/fixed-layout 实际显示；存量派生仍有 UNIT1 所列不可恢复的字体/媒体/层级损失。

## 听书与搜索逐项核对

| 项目 | 单元 3 现状 | 本单元 |
| --- | --- | --- |
| 可见位置 | 已捕获首个可见字符、反解原文 Locator/章句 | 起播等待在途位置反解，ReadiumSpeechBridge 用原文 Locator 求当前句；不从章首重置。不能精确对齐的可见位置明确提示。 |
| 当前句跟读 | 只有 tts 分组名 | 播放句经同一 LocatorBridge 转原文范围，再投影简繁显示范围；精确范围才生成 tts Decoration，跟随时导航到该句。 |
| 暂停/停止 | 无 EPUB 跟读渲染 | 暂停/停止/换书清空 tts；user/search 分别管理。继续重新求当前句；阅读面有固定暂停/继续按钮。 |
| 跟随与独立进度 | 音频写 listeningProgress；阅读写 progress | 跟随导航带会话内标志，不把音频自动跳转写成阅读断点；目录/显式跳转停止跟随，拖动正文退出跟随；允许手动回到声音。无新增计时器，统计沿用 visibility。 |
| 播放器返回 | 已携带 LocatorTarget、可用 listeningProgress Locator | 改为与阅读页共用 sentence 目标，现有完整 Locator/revision 在章句匹配时仍保留；落到当前 EPUB Session 的桥。非 EPUB 分支完全保留。 |
| 选区听书 | 单元 3 已能把选区换成原文章句 | 复用该精确句目标，不重写选区捕获。 |
| 搜索算法 | Book.text 全文、同章重复命中、最多 200 条，正文无命中才查标题 | 保留算法、防抖、排序、结果；不接第二套 Readium SearchService。 |
| 搜索跳转 | ContentsView 已传 UTF-16 textRange，EPUB 已经 bridge | 复用跳转；EPUB 重新取真实命中范围，修正首尾空白及大小写匹配长度；仅标题命中不装饰不相关正文。其他格式保持原目标口径。 |
| 搜索标示 | 只有 search 分组名 | 导航确认后显示两秒 search Decoration，取消/新命中替换独立任务；不清 user/tts，不把模糊范围当命中。 |

EPUB 正文提供整句高亮；播放器原有逐字时间/字幕逻辑没有改变，本单元没有新增字级 Decoration。超预算、原文/显示边界不确定等情形，可能只导航而没有精确跟读高亮；此限制沿用单元 3，而非伪造精确范围。

## 备份附件、兼容与事务

字段均为可选，外层版本不变：单书 BackupPacket version=2，整库 ICloudArchive version=1。

```json
{
  "epubAttachment": {
    "base64": "<原 source.epub 字节>",
    "sha256": "<小写 SHA-256>"
  }
}
```

单书放在 packet 根，整库放在 Item 根（恢复同时接受 packet 内的附件）。映射随 Book.epubTextMap 保存；恢复不信任附件带来的旧映射，Readium 重新解析并生成当前快照/映射。附件无绝对路径、security bookmark 或外部资源引用。源文件经 source.json/Book 描述/实际摘要一致性检查后才导出；无有效原文件则省略附件。

恢复先校验普通 Book/进度，再解码 base64、核对摘要、尝试 Readium 打开及重建。附件缺失、坏类型、坏 base64、摘要不符或 Readium 打不开，均保留旧备份 Book 文本层并清 source 描述/源映射，走派生路径；取消不会被吞成降级。普通书籍字段/进度无效仍按旧规则拒绝，并非所有归档错误都忽略。

整库复制到隔离 staging 库，再逐书 prepareImport/commitImport；无附件覆盖会删除 staging 中同 ID 的旧 source，新附件重绑 Publications/<id>/source.epub 和 source.json，并轮换持久缓存 epoch。全部书成功后才替换根目录，失败仍保留原库。旧三层引用保持，恢复仅撤销 publicationRevision，随后现有迁移按原 Locator/TextAnchor 重定位。AppModel 在开始恢复时更新会话 generation，旧 Navigator 回调不能在恢复结束后覆写新进度。

单书详情导出、原生分享出口、iCloud 备份和本地整库导出均带附件；从文件恢复与 iCloud 使用同一恢复函数。ICloudBackupStore.removeBook 仍移除整个 Item，因此其附件一并删除；只含该书的快照删除，含其他书的快照保留其他内容。测试覆盖真实导出函数、新库往返、同 ID 附件覆盖/无附件覆盖及快照移除。

JSON 附件会使原包增加约 1/3 编码体积，恢复有解码/复制/快照的内存与临时空间开销。没有新增静默大小截断，也没有改成旧端不识别的归档大版本；大书峰值、ENOSPC、异常杀进程仍需实测。

## 许可证与空间口径

组件页逐项列出锁定的 Readium 3.11.1（BSD-3-Clause）、SwiftSoup 2.13.5（MIT）、ReadiumZIPFoundation 3.0.1 及 ZIPFoundation 上游（MIT）、SMBClient 0.3.1（MIT）、Pow 1.0.6（MIT）、CryptoSwift 1.10.0（Zlib 派生，保留附加署名条款全文）、Zip 2.1.2（MIT）、DifferenceKit 1.3.0（Apache-2.0）、ReadiumFuzi 4.0.0（MIT）及现有 Lucide 图标。还区分列出 Package.resolved 中未链接的 CSQLite/GCDWebServer/SQLCipher/SQLite/ArgumentParser/DocC/SymbolKit，避免把解析图说成 app 链接图。版本逐项核对 Package.resolved；许可核对包内既有全文及固定 tag 的上游 LICENSE，Pow 新增随包全文。

API/许可依据包括 [Readium Metadata](https://github.com/readium/swift-toolkit/blob/3.11.1/Sources/Shared/Publication/Metadata.swift)、[Streamable](https://github.com/readium/swift-toolkit/blob/3.11.1/Sources/Shared/Toolkit/Data/Streamable.swift)、[CoverService](https://github.com/readium/swift-toolkit/blob/3.11.1/Sources/Shared/Publication/Services/Cover/CoverService.swift)、[Pow 许可](https://github.com/EmergeTools/Pow/blob/1.0.6/LICENSE)、[ReadiumZIPFoundation 许可](https://github.com/readium/ZIPFoundation/blob/3.0.1/LICENSE)。未使用 main 或 4.x API 猜测。

空间整理统计书库文档目录下所有 owner，将书库拆成“书库文本与摘记”与“书库原 EPUB”，两项之和是书库占用，原包不可清理；派生包与 session 文件列为 EPUB 缓存。通用其他缓存项减去语音和整个 Readium 目录以免重复；清理入口清当前书库的派生缓存，其他书库缓存保留；经共享 Store 清理时跳过在途生成和同进程 pin，上一进程孤儿可清。原文件永不进入可清缓存项。文件分配字节按路径累计，硬链接 pin 可能使显示占用高于实际物理新增占用；本轮未做磁盘实测校准。

## UI 审计定性与逐项改写理由

所有 27 个原测试方法保留；新增 1 个，共 28 个。没有 skip、删测试、改 workflow continue-on-error，或把时序敏感场景换成 TXT 了事。

| 用例 | 依据与处理 | 未实测点 |
| --- | --- | --- |
| OriginalReaderKeepsTypographyAndContentsReachable | 旧 nativePage/notes/下一章断言对 EPUB 已过期。保留 EPUB 派生夹具，检查 WebView 实际正文、关键按钮、设置/纸色保持、Readium TOC 跳章及返回书架。 | WebKit 正文可见、设置 sheet 和 TOC 控件实际树。 |
| OriginalReaderDarkModeKeepsChapterControlsReachable | 旧原生前后章槽位不属于 Readium 面；改夜间 Readium 目录双向跳章，仍查实际正文与关键控件。 | 夜间正文对比、目录可达与跳转完成。 |
| OriginalReaderChromeDoesNotResizeOrMoveItsColumn | 原生文本布局捕获过期；改捕获 WebView 可见正文/元素 frame/视口，仍要求实际翻到不同页、四次工具显隐不移动/重排、返回首章。 | WebKit 分栏可访问性边界与几何稳定。不能用只有 Navigator 容器的存在性代替。 |
| OriginalReaderKeepsFollowingThroughRepeatedPlaybackToggles | 原生 following 标签过期；改 EPUB 面内暂停/继续及跟读范围存在状态，保留按钮 frame 稳定；暂停后跳另一阅读章，再回到声音原章，验证不 seek 音频。 | TTS Decoration 实际渲染、连续系统语音、跟随翻页。可访问性 value 表示已生产的高亮状态，不替代像素检查。 |
| RecentReadingStaysPrimaryWhileAnotherBookHasListeningProgress | **独立场景，非 EPUB 路由问题**：夹具 now-listening 为 ui-long/ui-recent，均 TXT。lastReadingBook 只比较 max(lastReadAt, progress.updatedAt)，startListening/saveListeningProgress 不改阅读时钟；静态未发现优先级实现错误。旧全局同名文本查询缺少“英雄卡已到目标状态”的条件，改卡内独立标识和条件等待，保留第二章、返回阅读及暂停迷你播放器的断言。 | 没有三轮失败行与 UI 树/时间线，不能证明旧失败唯一来自选择器/时序；此为待复跑验证的定性，若仍败须按日志继续排查，不改成 EPUB/TXT 路由豁免。 |
| ReaderKeepsActionSlotsAndChapterNavigationDoesNotSeekAudio | **时序敏感，不列为过期断言**：原本 launch(reader) 就是 TXT，未换夹具。暂停点击后立刻读 label/frame、翻章后立刻读章节有中间态风险；补暂停/继续/章节终态等待，原槽位、阅读/听书独立断言保留。EPUB 等价覆盖另由上面的 OriginalReader 跟读用例承担。 | #15 败、#16/#17 过，缺失败时间线，尚不能宣称已消除全部翻转。 |
| HomeShowsContinueAndRecentWithoutScrolling | **时序敏感，不列为过期断言**：保留 launch(shelf)，等待同一续读卡动作可点击及书名/章节就绪；不滚动，不改动续读选择实现。索引异步更新会触发书架重算，元素存在不代表该帧的可点击性/内容终态。 | #15/#16 过、#17 败；仍需模拟器复跑确认具体失败行。 |
| EPUBDerivedFixtureSmokeAndSearch（新增） | 保留 ui-original 这一存量 EPUB，经真实派生构建和 Readium 展示；查正文、目录/搜索、命中返回、设置、返回书架。原包读取/导入/恢复由单元测试覆盖，当前 UI fixture 机制未新增原包场景。 | 原包专门 UI 冒烟、重复命中像素高亮仍需设备/模拟器扩展验证。 |

原生面流程继续由现有 ui-long 的排版、分页、搜索/摘记、工具槽位测试覆盖；PDF 两个流程及播放器/书架/设置等其余 20 个 UI 方法保留。所有 28 个本轮均因环境无法运行；逐项清单见 ACCEPTANCE。上述静态时序分析不等同实测复现或“UI 已绿”。

## 首次快照竞态

原实现 fileExists→read→atomic write 可让不同书同时进入并覆盖。现在同进程所有实例共用锁，首次检查、读取、原子写入在一个临界区中完成；后一个任务只能在备份已完整发布后检查，因此不能读取已迁移 catalog 再覆盖备份。每书快照也在同一临界区写出；后续转换/提交不持该锁，不阻塞异步 Publication 工作。范围为当前单进程迁移模型，不声称跨进程事务锁。

新增 testConcurrentFirstMigrationOfTwoBooksKeepsPremigrationCatalogSnapshot，同时迁移两本不同书，要求两个新 Locator 均已提交，而首次备份字节与迁移前 catalog 完全相等、两书 Locator 均为空；再并发调用快照入口确认备份不被已迁移 catalog 覆盖。本机未运行此 XCTest。

## 实际验证与测试总账

`/tmp/readium-unit4/validate.py` 已执行：完整 OpenStep 解析工程 213 对象，检查对象引用、Sources 路径、五项新增工程成员唯一挂接；Swift 词法定界符/注释/字符串与行尾空白；异步导入/恢复调用点；两个 base64 EPUB 的 CRC、首项 stored mimetype/无 extra、XML 良构；源测试方法清单；新文件 UTF-8；构建号四处 142；workflows、锁文件 SHA-256 不变。通过。脚本不解析 Swift 类型、actor 隔离或 SDK API，不替代编译。嵌入 JavaScript 未改，无需把旧 JS 检查重复计算为本轮新测试。

| 类型 | 方法数 | 本轮实际执行 |
| --- | ---: | --- |
| NativeCoreTests | 113 | 0 |
| ReadiumPublicationTests | 10 | 0 |
| ReadiumPreferencesTests | 12 | 0 |
| ReadiumLocatorTests | 15 | 0 |
| LocatorMigrationTests | 11（新增 1） | 0 |
| ReadiumTextSnapshotTests | 6（新增） | 0 |
| ReadiumBackupSourceTests | 6（新增） | 0 |
| 单测合计 | **173**（原 160 + 13） | **0** |
| DesignFlowTests | **28**（原 27 + 1，四项改写） | **0** |

外部已提供基线为 Tests #17 单测 160/160、UI 21/27；#15 为 UI 21/27、#16 为 22/27。没有把历史通过迁移成本轮通过。未执行 SwiftPM resolve、unsigned archive、EPUBCheck、模拟器、真机或真实 iCloud；验收仍须跑完整单测、28 个 UI（尤其 7 个审计项反复运行）和 Release 资源包检查。
