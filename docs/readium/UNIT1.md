# Readium 迁移单元 1：依赖、Publication 数据层与存量重建器

实施日期：2026-11-16 UTC。依据：完整阅读 `docs/readium/PLAN.md` 后按单元 1 的依赖 → 数据层 → 服务层 → 测试 → 报告顺序落盘。本次没有执行任何 git 命令、提交或推送，没有启动 CI。

交付状态：代码、工程引用、锁文件、许可证及测试夹具已写入；**尚未通过 Swift 编译、SPM 实际解析、模拟器测试、archive 或 EPUBCheck，不能按“验收通过”提交发布**。本环境是 Linux，未安装 Swift、Xcode、Ruby 或 Java。下面将静态检查和待 Mac/CI 实测明确分开。

## 改动文件与要点

| 文件 | 要点 |
| --- | --- |
| `Tingye.xcodeproj/project.pbxproj` | 新增 Readium exact 3.11.1，只链接 Shared / Streamer / Navigator 三个 Toolkit product；ZIP 包改为 Readium fork exact 3.0.1/product ReadiumZIPFoundation；app 直接链接 SwiftSoup exact 2.13.5 作 DOM 规范化。新增 Readium Group、四个 app Sources、一个 test Source、两个许可 Resources；测试 target 直接链接 Shared / ReadiumZIPFoundation。原 Fixtures 是 folder resource，自动覆盖新子目录。 |
| `Tingye.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` | 按版本化 Package.swift 与真实 tag commit 手工锁定 16 个身份；保留 Pow / SMBClient；移除旧 upstream ZIP pin 和已失效 originHash。不是实际 resolver 的产物。 |
| `create-project.rb` | 同步以上包及 app/test product 声明，递归保留 Swift 子目录 Group，补齐生成器原先漏写的 Pow；把生成器原先的 128/1.24.0 对齐当前 **142/1.25.0**，未运行生成器覆盖现工程。 |
| `Tingye/Models.swift` | Book 增加 Optional `epubSource` 类型化访问器，仍以原 fields JSON 编解码，未知键保留；描述包含库内相对路径、SHA-256、imported/repaired 来源、mappingVersion；非法描述只视为无 source，不拒绝旧 Book。新增只读 source staging 所有者和流式 SHA-256 工具。 |
| `Tingye/BookImporter.swift` | 仅 EPUB 分支复制到私有 staging，解析该副本并随 Imported 传递；保留原文件名作为缺 title 时的 fallback，旧章节/text 抽取规则不变。SafeArchive 适配 fork 的 actor init/entries/extract，仍向旧导入器暴露同步解压接口及 Entry 数组；不改 DOCX/漫画等格式语义。 |
| `Tingye/Services.swift` | LibraryDisk 提供 Publications、source/sidecar 校验、prepareImport/commitImport 与事务性删除。后台准备新 Book/source；发布阶段以 journal、旧文件硬链接备份、原子文件/目录发布同步提交 Book/source/catalog，失败回滚；初始化重放未完成 journal。普通 read-state 写入保留匹配且通过哈希校验的 source。新增每书持久缓存代次，修书/替换时随事务更新，删除时移除。 |
| `Tingye/AppModel.swift` | importFiles 授权有效期内持有 staging 并交 add；add/repair 做 generation/owner/cancellation 检查，同书写入互斥，准备完成后再事务提交目录。repair 保留 ID/原有引用重定位逻辑，切换 source 并使旧派生代次不可复用。删除、标记已读、重新分章与同书提交互斥，避免旧快照在修书后回写。没有接 Publication 打开路由。 |
| `Tingye/Readium/ReadiumService.swift` | MainActor 封装共享 AssetRetriever / PublicationOpener(parser: EPUBParser())，仅接本地文件，检查 sniffed EPUB、Publication EPUB profile、未受限和非空 readingOrder；错误分为路径、格式、取文件、解析、受限和空正文。只有测试调用。 |
| `Tingye/Readium/PublicationMap.swift` | 章序 ↔ 唯一容器相对 href、原 document.path（保留重复映射）、资源根、映射/生成器版本和 publicationRevision；只 hash 参与生成的出版物内容，排除 nativeReadChapters 等本机状态。原包 revision 使用 source 字节哈希。 |
| `Tingye/Readium/PublicationStore.swift` | 按库 owner 隔离 source/cache；缓存键含内容哈希、生成器版本及持久代次；单实例 actor 合并并发请求，失败不缓存完成态，缓存命中校验 receipt/EPUB 哈希；invalidate、清理与 session pin/release 接口。pin 使用独立硬链接/副本，修书、删除或缓存清理不会销毁已 pin 的会话文件；原包 pin 再次校验 revision。 |
| `Tingye/Readium/LegacyEPUBBuilder.swift` | SwiftSoup DOM 规范化 + XMLParser 校验，失败退 text；唯一章路径、资源解包/去重、CSS/内部链接重写、平铺 nav、OPF/spine/cover、mimetype 首项 stored/无 extra 校验；同卷 staging 完整生成后发布 EPUB 与 receipt。 |
| `TingyeTests/NativeCoreTests.swift` | 只将 ZIP import 改为 ReadiumZIPFoundation，以及原漫画测试中 Archive 创建/addEntry 适配 async fork；未更动其他测试逻辑、PR #13 测试线或 workflow。 |
| `TingyeTests/ReadiumPublicationTests.swift` | 新增原包 Readium readingOrder/TOC/cover、重建章序/nav/manifest/cover/图片/规范化与损失、SafeArchive、缓存合并/再生/损坏/保活/代次、source 提交/修书/替换/删除、catalog 失败回滚/重启恢复、AppModel 导入修书、坏包/坏路径/缺资源/取消/写入失败测试。**均未执行。** |
| `TingyeTests/Fixtures/readium/original.epub` | 原创最小 EPUB 3：两章、nav、PNG cover，mimetype 第一项无压缩。 |
| `TingyeTests/Fixtures/readium/legacy-book.json` | 原创三章存量 JSON：HTML/CSS、body 残壳、中文及重复 path、缺 HTML、nativeImages、图片 data URI 去重、封面、内部 fragment、缺资源。 |
| `TingyeTests/Fixtures/readium/README.md` | 夹具来源、覆盖范围和临时输出说明。 |
| `Tingye/Resources/Readium-LICENSE.txt` | 从 3.11.1 LICENSE 原样保存 BSD 3-Clause 全文。 |
| `Tingye/Resources/Readium-Dependencies-LICENSE.txt` | 所链接的 CryptoSwift、Zip、DifferenceKit、ReadiumFuzi、SwiftSoup 版本化许可全文及来源；组件 UI 展示留单元 4。 |
| `Tingye/Resources/ZIPFoundation-LICENSE.txt` | 对齐 fork 3.0.1 MIT 原文（版权年份 2017–2024）；沿用原 Resources 引用。 |
| `docs/readium/UNIT1.md` | 本报告。 |

构建号保持 142，现工程营销版本保持 1.25.0。未修改任何现有 UI、ReaderView/TingyeApp 路由、其他格式解析规则、备份协议、`.github/workflows` 或 `tests.yml`。当前 EPUB 仍使用旧引擎阅读。LibraryDisk 的提交保障也覆盖 add/repair 的公共写入边界，但只有 EPUB 留存原包；其他格式没有新增 source 附件或渲染路径。

## 依赖核验与手工锁文件依据

核验使用 GitHub 连接器读取固定 tag 的 `Package.swift`、公开 API 源文件和 tag 对应 commit；不是根据 main 猜版本。Readium 的 [3.11.1 Package.swift](https://github.com/readium/swift-toolkit/blob/3.11.1/Package.swift) 声明全部一层约束；[ZIP fork 3.0.1 Package.swift](https://github.com/readium/ZIPFoundation/blob/3.0.1/Package.swift) 确认模块/product 改名，Archive 为 async actor：init、entries()、extract()、addEntry() 均须 await。SafeArchive 以真实 [Archive.swift](https://github.com/readium/ZIPFoundation/blob/3.0.1/Sources/ZIPFoundation/Archive.swift)、[Reading](https://github.com/readium/ZIPFoundation/blob/3.0.1/Sources/ZIPFoundation/Archive%2BReading.swift)、[Writing](https://github.com/readium/ZIPFoundation/blob/3.0.1/Sources/ZIPFoundation/Archive%2BWriting.swift) 适配。

Readium 打开链核对了固定版本的 [AssetRetriever](https://github.com/readium/swift-toolkit/blob/3.11.1/Sources/Shared/Toolkit/Data/Asset/AssetRetriever.swift)、[PublicationOpener](https://github.com/readium/swift-toolkit/blob/3.11.1/Sources/Streamer/PublicationOpener.swift)、[EPUBParser](https://github.com/readium/swift-toolkit/blob/3.11.1/Sources/Streamer/Parser/EPUB/EPUBParser.swift) 与 FileURL(url:) 实现。没有使用 Streamer().open、HTTP 服务器或 GCDWebServer adapter。

所有新增传递版本选择相应 Package.swift 下界的已发布正式 tag，未声称是各包最新版本。原 Pow/SMBClient pin 保留，并重新核对其 manifest 和 tag commit。Pow 的 enablePreviews=false，目标不依赖包级声明的 SnapshotPreviews-iOS exact 0.10.21；沿用基线锁文件未纳入这个禁用预览依赖的状态，CI 须确认 product pruning 仍将其排除。SMBClient 没有外部包依赖。每一行的 revision 都核对了 tag 对应 commit（不是 Package.swift blob SHA）：

| identity | version | tag commit | 版本化依据 |
| --- | --- | --- | --- |
| cryptoswift | 1.10.0 | `f2a627b84c1ff96f21ac2fcb623ab36142dd5512` | [Package.swift](https://github.com/krzyzanowskim/CryptoSwift/blob/1.10.0/Package.swift) |
| csqlite | 3.50.4 | `bdb5580e54cdf49251b365ea34e2651199473240` | [Package.swift](https://github.com/stephencelis/CSQLite/blob/3.50.4/Package.swift) |
| differencekit | 1.3.0 | `073b9671ce2b9b5b96398611427a1f929927e428` | [Package.swift](https://github.com/ra1028/DifferenceKit/blob/1.3.0/Package.swift) |
| fuzi | 4.0.0 | `347aab158ff8894966ff80469b384bb5337928cd` | [Package.swift](https://github.com/readium/Fuzi/blob/4.0.0/Package.swift) |
| gcdwebserver | 4.0.0 | `c51ffcde677392fef6241a783ffebcad11a5911c` | [Package.swift](https://github.com/readium/GCDWebServer/blob/4.0.0/Package.swift) |
| pow | 1.0.6 | `1b4b1dda28c50b95f0872927ee2226fe8b58950e` | [Package.swift](https://github.com/EmergeTools/Pow/blob/1.0.6/Package.swift) |
| smbclient | 0.3.1 | `e636c2b2458930770932a36d311ec9d478575b90` | [Package.swift](https://github.com/kishikawakatsumi/SMBClient/blob/0.3.1/Package.swift) |
| sqlcipher.swift | 4.11.0 | `247b042574b4838c7eefdb95d6a250a843dcf1ad` | [Package.swift](https://github.com/sqlcipher/SQLCipher.swift/blob/4.11.0/Package.swift) |
| sqlite.swift | 0.16.0 | `964c300fb0736699ce945c9edb56ecd62eba27a3` | [Package.swift](https://github.com/stephencelis/SQLite.swift/blob/0.16.0/Package.swift) |
| swift-argument-parser | 1.0.1 | `d2930e8fcf9c33162b9fcc1d522bc975e2d4179b` | [Package.swift](https://github.com/apple/swift-argument-parser/blob/1.0.1/Package.swift) |
| swift-docc-plugin | 1.5.0 | `647c708be89f834fa6a6d4945442793a77ddf5b6` | [Package.swift](https://github.com/swiftlang/swift-docc-plugin/blob/1.5.0/Package.swift) |
| swift-docc-symbolkit | 1.0.0 | `b45d1f2ed151d057b54504d653e0da5552844e34` | [Package.swift](https://github.com/swiftlang/swift-docc-symbolkit/blob/1.0.0/Package.swift) |
| swift-toolkit | 3.11.1 | `9a8c094b72245fd27043c9d298005e5c78b32a01` | [Package.swift](https://github.com/readium/swift-toolkit/blob/3.11.1/Package.swift) |
| swiftsoup | 2.13.5 | `49dcadd93161f4a44b4994d3a3e8de9f085aface` | [Package.swift](https://github.com/scinfu/SwiftSoup/blob/2.13.5/Package.swift) |
| zip | 2.1.2 | `67fa55813b9e7b3b9acee9c0ae501def28746d76` | [Package.swift](https://github.com/marmelroy/Zip/blob/2.1.2/Package.swift) |
| zipfoundation | 3.0.1 | `e2faaa7ae1640094fe52ae00f00814ba507635e7` | [Package.swift](https://github.com/readium/ZIPFoundation/blob/3.0.1/Package.swift) |

进一步追溯了 SQLite.swift 0.16.0 的 CSQLite ≥3.50.4、SQLCipher.swift ≥4.11.0，以及 DocC plugin 1.5.0 的 SymbolKit ≥1.0.0；后者在实际工具链会选择的 [Package@swift-5.5.swift](https://github.com/swiftlang/swift-docc-symbolkit/blob/1.0.0/Package@swift-5.5.swift) 还依赖 ArgumentParser 1.0.x，故补 1.0.1。Zip 2.1.2 的 Package@swift-5.0.swift 和 DifferenceKit 1.3.0 的版本化 manifest 也核对了，无新增外部包。其余新增包的根目录未发现更高工具链版本 manifest。

**仍须 resolver 核查：** version 3 锁文件未保留旧 originHash（根依赖图已变，无法在 Linux 无 SwiftPM 的环境计算 Xcode 的新 hash）。CI 可能重写 hash、裁剪未使用 product 的包、因 trait/product pruning 改变二级 pin，或按上游 `from` 约束更新兼容版本。GCDWebServer、SQLite/SQLCipher、DocC 出现在包级解析图/锁文件中，不表示 app 链接了它们。SwiftSoup manifest tools 6.0、SQLite/CSQLite manifest tools 6.1 需要 CI 所指定的新工具链；不能只看 Readium 的 tools 5.10。app 额外直接声明 SwiftSoup 是为了可维护的 HTML DOM 修复，使用的是 Readium 本已依赖的同一包，并非第四个 Toolkit product。未运行任何依赖解析或 Ruby 工程重建。

## 存储事务与缓存合同

EPUB staging 只存文件 URL/摘要，Book JSON 不含原包 base64、绝对路径或 security bookmark。LibraryDisk 提交后是 `Publications/<id>/source.epub` 和 `source.json`；JSON 中 `epubSource` 与 sidecar、实际字节 SHA-256 必须匹配才可选原包。缺失/损坏时 Store 回退现有 JSON 重建。导入 JSON 即使带本机 source 描述，没有本次导入的原包附件也会去掉描述、隔离旧 source；原包备份附件属于单元 4。

`.PublicationTransactions/<uuid>` 保存新文件、旧文件硬链接备份、journal 和 committed 标记；失败/重启以旧快照回滚，标记完成后再清理。原包目录用完整 staging 发布；Book 文件原子替换；catalog 按已有保护级别原子写入。删除也把 Book/source/缓存代次/catalog 纳入同一可回滚 journal；全部完成后 AppModel 才移除内存条目，避免删文件中断时留下悬空目录或孤立原包。

`.PublicationCacheEpochs/<id>` 是库内派生缓存代次，随导入/修书事务更新、删除时清理，普通 read-state 写入不改变。物理缓存位于 `Caches/TingyeReadium/<owner>/<id>/<contentHash>-v<generator>-<epoch>/`。同内容替换也选新代次，旧文件只等待安全清理，不误当作新 publication。逻辑 publicationRevision 仍表示实际源字节或生成器+内容，不把随机代次当正文变化。

单个 PublicationStore 内合并同键请求；一个调用方取消不会取消其他等待方的共享生成，取消方不接受结果；显式 invalidate 取消该书在途生成。prepare 完成时再次核对持久代次，拦截中途替换。单元 2 应为同一书库共享一个 Store，并使用 pin 返回的独立会话 URL；未设计跨进程/多个独立 Store 的全局锁。保活接口现在可测试，尚未挂阅读会话或 StorageView。

## 重建及损失记录口径

每个完成产物包含 `publication.epub` 和 `publication.json` receipt。receipt 持久保存 EPUB 哈希、PublicationMap 与 Report；只有 ZIP/XML/引用检查和全部写入完成后才发布整个目录，失败不留完成态。缓存命中还校验实际 EPUB 字节哈希。

章节使用固定序号 `EPUB/text/ch-000001.xhtml`，严格按原 chapters 排序。原 path 不作唯一主键，中文/重复 path 有明确映射。重复 path 的内部链接优先当前章，其他情况选首个章序并记损失。fragment 不存在时退到目标章首并记日志。

HTML 复用 OriginalDocument 清理经验，再由 SwiftSoup 解析和 XML 序列化；保留单个 body 的 class/id、可用文本/表格/ruby/锚点。正文 style 提取到章级 CSS，原 document.css 同时保留。残留 head/脚本/事件/活动元素清理会记录；SVG/MathML/音视频等不完整外来内容保守移除。XHTML XML 校验失败或 HTML 缺失时，按原 text 转义为段落，补可用 nativeImages 到章末并记录位置损失，不改原 text、marks、章节序或听书进度。

图片只接受经过 MIME/字节类型校验的 PNG/JPEG/GIF/WebP base64 data URI，使用字节 SHA 文件名和去重，不把 JSON 资源键或外部路径当输出文件路径。GIF/WebP 转 PNG 核心媒体，动画保留静态帧并记损失；坏资源/不支持类型/单个编码超过 128 MiB 会被丢弃并记损失。封面只使用已有 cover，标记 manifest cover-image，不猜首图。未保留原语言时按正文识别，低置信度用 und，记录推断。

src/href/style/CSS url 可可靠匹配资源键或 data URI 才改成文件引用；章间 href 按 path 表改写。srcset 当前保守删除并记属性损失，以可解析 src 为主。无法追溯原目录的 @import/@font-face 删除；不可解析/远程 url 改 none，活动/含转义而无法可靠检查的样式整段移除。缺图保留 alt，不猜测 foo.jpg 对应哪个 rN；外部显式 http(s)/mailto 超链接保留。没有导入旧分页多栏骨架。

Report 的每条 Loss 含可选的 **0 起章节索引**、稳定 `code` 和最多 240 字 detail；不内嵌大段 base64/整书文本。当前 code 包括 publication-metadata、language-inferred、html-sanitized、html-missing、html-fallback、resource-invalid、resource-mime-mismatch、image-converted、image-missing、native-image-missing、image-appended、cover-missing、element-removed、element-normalized、attribute-removed、id-removed、css-dependency-removed、css-url-removed、css-unsafe-removed、link-removed、duplicate-path-link、fragment-missing。报告表示可读内容的重建损失，不声称无损恢复原出版物。

## 本机检查及需总控核查事项

已执行 Python 静态检查（工具脚本位于本次环境 `/tmp/readium-unit1/validate.py`，不作为仓库交付）：

- 解析完整 OpenStep pbxproj，检查对象、target、Group/phase/product 引用存在；四个新 app Sources 和新 test Source 唯一挂接，两个新许可在 Resources，测试 Fixtures folder 已挂接。
- 核对 app/test product 与 Frameworks 对应，版本号仍为 142；锁文件 JSON、16 个唯一身份、40 位 commit 格式、ZIP fork URL、Readium 版本固定。
- 用 Python zipfile/lxml/Pillow 检查原夹具的 CRC、mimetype 首项 stored/无 extra、XML 可解析、两项 spine/manifest 文件存在、PNG 可解码；检查旧 JSON 三章、重复 path 和图片数据完整。
- 检查本次编辑源码无行尾空白。没有运行 git diff/check 或任何 git 命令。

这些检查不替代 Swift typecheck。总控优先核查：

1. 实际 SPM resolve 与新锁文件：上述包级非选用依赖/traits 是否被裁剪；originHash 回写；保持单一 ZIPFoundation identity，不能退回 upstream/fork 混用。
2. 新 Swift 源码在真实 SDK 的编译及 actor 隔离诊断；SafeArchive 为保留旧同步导入合同使用短任务/信号量桥接，不应在大量占满 Swift cooperative pool 的并发同步调用中使用。当前 AppModel 逐文件导入，未来并发批量导入需改为真正 async 管线。必须跑既有 DOCX/漫画 ZIP 回归。
3. iOS 文件系统上 FileManager 的目录/文件 replaceItemAt、硬链接与故障回滚，以及真实空间不足/进程被杀。已写入“catalog 写入失败 + 重启 journal 恢复”和“父路径不可写”的测试；**没有模拟真实 ENOSPC、断电或多进程竞争**。
4. XMLParser 只证明 XML 良构，完整 EPUB 规范、CSS 合法性和资源 bundle 必须用 EPUBCheck/Release archive/Readium 实测。当前 srcset/外来词汇/字体/媒体的保守降级，以及 GIF/WebP 转 PNG 的动画损失应在真实旧库样本上确认。
5. 尚未测真实大书的峰值内存、临时空间（原包 staging + 事务备份 + JSON/缓存）、哈希/重建耗时。后台准备降低主线程编码压力，但这里没有性能实测数据。
6. 单元 2 必须持有 Store 与 pin 会话；单元 4 补 source 备份附件、存储分类、组件许可 UI。当前仅路径字段的旧备份恢复将重建 JSON，不得声称原包备份完整。

## 对照 PLAN 单元 1 验收

| PLAN 验收条目 | 本单元状态 | 依据 / 未做原因 |
| --- | --- | --- |
| 新包 exact / ZIP identity 归一 / 工程与生成器同步 | **已做静态配置，未实测解析** | 已核对固定 tag API/依赖图；本机无 xcodebuild。 |
| `xcodebuild -resolvePackageDependencies` 与锁文件检查 | **未做实际 resolve** | 锁文件是有依据的手工候选，需 Mac/CI 解析确认。 |
| Release unsigned archive，Readium CSS/JS/字体 bundle | **未做** | 本机无 Xcode；只链接官方 product，不手工复制包资源。 |
| 原始 EPUB 被 Readium 解析，readingOrder/TOC/cover | **已写测试，未执行** | 两章 original.epub + 原包打开/TOC/cover 测试。原夹具 ZIP/XML/PNG 静态检查已通过。 |
| JSON 重建 EPUB 被 Readium 解析、正确 spine/nav/images/cover | **已实现、已写测试，未执行** | 三章代表夹具及源 JSON 不变断言；本机没有 Swift/iOS Runtime。 |
| 重建夹具 EPUBCheck | **未做** | 无 Swift 可生成运行产物、无 Java/EPUBCheck；XMLParser 不是 EPUBCheck。 |
| body 残壳、无 HTML、中文/重复 path、data URI、缺资源、封面、图片章、坏包 | **已实现相应处理/测试，未执行** | fixture 与动态派生样本覆盖；GIF/WebP 转换未新增独立动画夹具，待真实样本。 |
| 取消、空间不足 | **部分已做，未实测** | 有取消/写入失败不发布测试；真实 ENOSPC/中途系统终止故障注入未做。 |
| 缓存删除后再生、并发合并、当前文件保活 | **已实现/已写测试，未执行** | Store 清理/损坏后再生/共享结果/pin 用例；UI 会话接入留单元 2。 |
| 同 ID 替换/修书不误用旧 source 或派生包 | **已实现/已写测试，未执行** | sidecar+digest、无附件描述失效、持久代次、AppModel 生命周期及事务恢复用例。 |
| 现有 EPUB/DOCX/漫画/备份回归 | **未执行** | 旧导入器保留；只适配 ZIP 模块/actor。须由 Mac/CI 跑现有 TingyeTests。 |
| 不切路由、不改 UI/其他格式语义、Optional 兼容、构建 142、无 workflow/git 操作 | **已做静态自查** | 新 Service 仅测试调用，Book 仍原 fields 编解码，旧字段不改；未触碰路由、UI 或 workflow。 |

建议在 Mac 上先 resolve，再跑 `TingyeTests/ReadiumPublicationTests` 与全部 `TingyeTests`，随后运行既有 unsigned archive 脚本、检查资源 bundle，并对测试实际生成的派生 EPUB 执行 EPUBCheck。所有失败都应先修复再标记单元 1 验收通过；本报告没有预先把这些门槛记成完成。
