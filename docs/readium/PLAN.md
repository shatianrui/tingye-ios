# 听页 Readium 全量迁移：单元 0 摸底与施工方案

调查日期：2026-11-15（UTC）。代码基线：`readium-engine` / `a97cdec4595fedbeab6ba722f07c33b105b15faf`，本地 `main` 同一提交；工程版本 1.25.0（142）。本单元仅新增本文件，不修改代码、工程、依赖锁或构建号，不 push。下文的“现状”来自该基线的静态源码；没有访问用户设备里的实际书库，不能据此保证历代客户端导入的每一本 JSON 都有完整字段。后续新文件、新字段和算法均是施工设计，尚未实现、编译或通过真机验证。

## 总体决策

推荐组合路线：新 EPUB 在导入授权有效期间复制原文件到书库的持久目录，由 Readium 解析并交给 EPUB Navigator 渲染；已有 EPUB 没有原文件时，按现有 Book JSON 生成一份确定性的兼容 EPUB，按需缓存。修书重新提供原文件后，切换到原文件。重建追求内容可读和定位可迁移，无法恢复已经丢弃的出版物信息。

保留 Book JSON 作为原生文本层，保留已有章节顺序、`text` 和分句口径；听书、书内搜索、摘记、书架百分比继续使用它。新导入的 EPUB 结构解析最终以 Readium 为唯一权威，从其 readingOrder/resources 提取文本并写入同一 JSON 模型，复用 `HTMLText.chapter` 的文本规范化规则，不再独立运行旧的 ZIP→container→OPF→spine EPUB 结构解析。EPUB 停用 CoreText/TextKit 渲染与分页；其他格式保留现有引擎。

全库四类引用（阅读进度、听书进度、书签、划线）逐步增加 Readium Locator 持久化，Locator 成为新版本的主定位；旧章句坐标和 142 TextAnchor 同时保留，供文本层、旧备份和其他格式的原生引擎使用。不能把 Readium `locations.position` 当成句序号。依赖固定 Readium **3.11.1**，引入 **ReadiumShared、ReadiumStreamer、ReadiumNavigator**；该版 EPUB Navigator 使用内部 WebViewServer，**不需要 ReadiumAdapterGCDWebServer**，详见第 8 问。

## 1. EPUB 存量数据：落盘内容、章节与目录

### 1.1 导入和持久化路径

`BookImporter.read` 按扩展名 `epub` 调用 `epub(url)`，返回 `Imported(book, progress)`（`Tingye/BookImporter.swift:7–13`）。`epub` 用 `SafeArchive` 打开源 ZIP，读取 `META-INF/container.xml` 和其指向的 OPF，再遍历 manifest/spine（`Tingye/BookImporter.swift:120–149`）。`AppModel.importFiles` 在 security-scoped URL 授权期间后台解析，然后 `add`（`Tingye/AppModel.swift:485–500`）；`add` 调 `disk.write(book)` 后生成 ShelfEntry、保存 catalog（`Tingye/AppModel.swift:338–364`）。

书库根目录是 Documents 下 `TingyeNative/<owner>/`，书本文件为 `Books/<id>.json`，目录为 `catalog.json`（`Tingye/Services.swift:588–613`）。`Book.fields` 本身直接编码为 JSON 根对象，**落盘没有额外的 `fields` 外壳**；Chapter 同理（`Tingye/Models.swift:39–52,55–60,82–92`）。封面/分类另有可重建的 `Index/<id>.json`、`Index/<id>.jpg` 缓存，不是原 EPUB（`Tingye/Services.swift:616–632`）。

### 1.2 当前原生 EPUB 导入器写入的完整键清单

| 层级 / 键 | 类型与实际内容 | 证据 |
| --- | --- | --- |
| 根 `id` | String，默认 UUID 小写；不采用 OPF identifier | `Tingye/Models.swift:82–85` |
| 根 `title` / `author` | String，OPF 首个 title / creator；title 无节点时用文件名，author 无节点时为“佚名” | `Tingye/BookImporter.swift:125–126` |
| 根 `format` | String，确切值 `"EPUB"` | `Tingye/BookImporter.swift:171` |
| 根 `chapters` | `[Object]`，如下表；生成顺序为保留下来的 spine 项顺序 | `Tingye/BookImporter.swift:145–167`、`Tingye/Models.swift:85` |
| 根 `resources` | `[String: String]`，只存 manifest 声明的 PNG/JPEG/GIF/WebP；键 `r0`、`r1`…；值如 `data:image/jpeg;base64,<原图片字节的base64>`，不是原路径 | `Tingye/BookImporter.swift:130–140,169` |
| 根 `description` / `category` | String，首个 OPF description，缺省 `""`；首个 subject，缺省“其他” | `Tingye/BookImporter.swift:169` |
| 根 `cover`（可选） | String，例如 `tingye-resource:r0`；由 manifest `properties` 包含 cover-image 或 EPUB 2 cover meta 的 id 指定 | `Tingye/BookImporter.swift:132,139,170` |
| 章 `title` | String，首次识别到的 h1/h2/h3 内容，最多 200 字；无标题默认“第 N 章”，不是来自 nav/NCX | `Tingye/BookImporter.swift:150,228,236–248` |
| 章 `text` | String，由标签流生成纯文本：块级标签换行、空白折叠、实体解码；不是原 XHTML | `Tingye/BookImporter.swift:223–248,265–272` |
| 章 `marks` | `[Object]`，每项 `{start: Number, end: Number, bold: Bool, italic: Bool}`；start/end 为 text 的 UTF-16 半开区间，来自 b/strong/i/em；**不是用户划线** | `Tingye/BookImporter.swift:228,240–248` |
| 章 `nativeImages` | `[String]`，识别出的 img src 在源文档里的顺序，例如 `["tingye-resource:r2"]`；仅限能解析到已保存图片的引用，可为空、可重复 | `Tingye/BookImporter.swift:151–155` |
| 章 `document.html` | String，img src 已替换成 `tingye-resource:rN` 的清洗文档；具体清洗见下节 | `Tingye/BookImporter.swift:156–165` |
| 章 `document.css` | String，按本章 link 标签顺序拼接能找到的 CSS，每份加换行；不保留 CSS 文件路径；并未改写 CSS 内的 url() / @import | `Tingye/BookImporter.swift:141–144,160–165` |
| 章 `document.path` | String，ZIP 根相对的原 spine 文档规范化路径，如 `OEBPS/Text/c1.xhtml`；不带锚点和 query | `Tingye/BookImporter.swift:111–118,148,165` |

这是该导入器生成的封闭清单。`color` / `sample` 是 Book 访问器的默认值，不是 EPUB 导入器额外写的键（`Tingye/Models.swift:65–67`）；后续业务还可能写 `nativeReadChapters` 等字段（`Tingye/AppModel.swift:548–558`）。模型保留未知 JSON 键，因此旧客户端/外部备份可能包含额外字段，迁移不得丢弃（`Tingye/Models.swift:9–11,82–92`）。

### 1.3 原文件、清洗损失和章节关系

**当前 EPUB 路径不保存原 EPUB 文件，也不把它放入 epubData/raw/base64 字段。** 正证是 `epub` 的完整返回构造只有上述 extras，`Imported` 只持有 Book 和进度，LibraryDisk 只写整本 JSON（`Tingye/BookImporter.swift:7,120–172`；`Tingye/Services.swift:602–613`）。对照 PDF 明确把整个源 Data 编为根 `pdf` base64，再由 `Book.pdf` 解码（`Tingye/BookImporter.swift:15–19`；`Tingye/Models.swift:68–69`）。全仓检索 `epubData|rawEPUB|epubBase64|originalEPUB|rawData|base64EncodedString` 未找到 EPUB 原包存储；找到的是图片、PDF、鉴权和其他格式资源。不能把用户在 Files 里可能仍有的导入源、旧客户端的未知键或临时下载文件视为应用可依赖的原包备份。

远程导入把文件放在临时目录并在操作结束时删除（`Tingye/Sources.swift:338–351`）；SMB 同样使用临时目录（`Tingye/SMBBrowser.swift:185–187`），WiFi 收件在回调完成后删目录（`Tingye/Sources.swift:1011–1015`）。已有 iCloud/本地整库备份只装 Book + 引用数据，没有原 EPUB 附件（`Tingye/ICloudBackup.swift:10–24,400–445`）。旧书迁入也只搬 JSON（`Tingye/AppModel.swift:143–149`）。

每个**保留下来的 chapter 对应一个 spine itemref 的文档**，不按标题再分章，也不再按 TXT 长度拆分；不是原 spine 的完整一一映射：`linear="no"` 被跳过，manifest 缺失的 itemref 被跳过，text 为空且没有可识别图片的文档也被丢弃（`Tingye/BookImporter.swift:145–167`）。一个原文档含多个标题仍只生成一个 chapter；同路径重复 itemref 也可能生成多个 chapter，重建时必须有唯一输出路径，不能用 path 作唯一主键。

纯文本抽取会先删 restored-source-link 回链、script/style/head/nav/noscript 及注释，再处理标签与实体（`Tingye/BookImporter.swift:223–248`）。`document.html` 则来自另一条清洗路径：删回链、script/head/iframe/object/form/noscript 整块和注释、声明/doctype、html 外壳标签、meta/link/base/embed/input/button，以及 on* 事件属性；**body 外壳及其 class/id、正文样式属性、正文里的 style/nav、SVG 等不保证被删**（`Tingye/OriginalBookView.swift:7–12`）。因此它既不是完整 XHTML，也不能直接假设是纯 body 内片段。head 内嵌 style 随 head 丢失；body 内 style 可能仍在；外链 CSS 保存在独立 css 字符串。只替换 `<img src>`，不覆盖 SVG image href、srcset、CSS 背景图、字体 url 等（`Tingye/BookImporter.swift:253–263`）。

没有结构化保存 nav/NCX 树、navPoint 层级、锚点目录、page-list、landmarks、原 OPF manifest/spine/meta（语言、排版方向、固定版式、字体混淆信息等）。只留下平铺 chapter 标题和 path；即使某些 nav 标签偶然保留在正文 HTML 中，也不等于保存了可用的 TOC 数据结构。证据是导入完整处理仅查 title/creator/manifest/itemref/description/subject/cover，未读取 NCX/nav，目录 UI 遍历 chapters（`Tingye/BookImporter.swift:120–172`；`Tingye/ReaderView.swift:1721–1730,1753–1780`）。

## 2. 存量 EPUB 重建：可行范围与全部步骤

结论是**可生成结构合法、供 Readium 读取的派生 EPUB；不能无损还原原书**。已有 text、清洗 HTML、CSS、部分图片足以构造一个新的 reflowable EPUB；缺 HTML/资源时还能由 text 生成有明确损失说明的正文。这里是可行性设计，尚未用 Readium 对真实旧库验证。OCF、包文档、XHTML 和 nav 的格式约束依据 [W3C EPUB 3.3](https://www.w3.org/TR/epub-33/) 的对应章节。

### 2.1 确定性的拼装算法

1. **快照与输出映射。** 校验 Book.id、章节数、JSON 类型；不改原 JSON。生成 `chapterIndex → EPUB/text/ch-000001.xhtml` 和 `document.path → [输出 href]` 映射，保存生成器版本及输入 SHA-256；固定序号保证重复 path、空 path、中文路径不冲突。输出书籍标识使用 `urn:tingye:<book.id>`，不能谎称恢复了原 OPF identifier。映射需记录源文档路径和资源根，供 Locator 迁移使用。路径校验沿用并加强 `BookImporter.resolve`（`Tingye/BookImporter.swift:111–118`）。
2. **搭建容器。** 工作目录写 `mimetype`（内容恰为 `application/epub+zip`）、`META-INF/container.xml`（指向 `EPUB/package.opf`）、`EPUB/text/`、`EPUB/styles/`、`EPUB/images/` 和 `EPUB/nav.xhtml`。打 ZIP 时 mimetype 必须第一项、无压缩、无额外字段；其余可 deflate；使用后台任务与临时 staging，校验成功才原子发布。
3. **解出资源。** 对 resources 的每个 data URI，拆 MIME/base64、校验长度与实际解码，按 `rN → images/rN.<ext>` 表映射，不接受任意路径写入。当前已知只存 PNG/JPEG/GIF/WebP；不能调用只接受 `data:image/` 的 `Book.resourceData` 去解任意新媒体（`Tingye/Models.swift:76–80`）。HTML 若内嵌 data:image 也提取并按哈希去重；封面若直接是 data URI，同样提取。WebP/GIF 等视 EPUB 核心媒体与工具链支持补 PNG/JPEG fallback，保持 manifest MIME 与字节一致。
4. **规范化章节。** 用 HTML DOM 解析器读取 document.html；有 body 时提取其内容并保留适当属性，没有时作为片段解析；清理残留 html/body/声明，规范空元素、实体和 namespace，序列化为 XML 兼容 XHTML。统一补 `html xmlns`、head/title/meta、CSS link 和单个 body，不要用字符串直接套壳制造嵌套 body，也不要仅靠 `closingSelfClosedTags` 当 XML 修复器。若 HTML 无效或缺失，由 `OriginalDocument.fromText` 等价规则转义 text 后生成段落（`Tingye/OriginalBookView.swift:14–28`），并补 nativeImages 中未能落位的可用图；保留可用的 id/链接锚点。回退会损失版式，必须记入重建报告。
5. **重写引用。** img 的 `tingye-resource:rN` 改成 `../images/rN.ext`；遍历 src/href/srcset/style 和 CSS url()/@import。能直接对应资源键/data URI 的改写为文件路径；章间链接依据原 document.path 和 fragment 映射到新文件；重复 path 的链接用确定规则消歧并记日志。**原图片路径到 rN 的 imagePaths 表没有落盘**，不能从 `foo.jpg` 猜出它必为 r3；CSS 原文件所在目录也丢了。无法可靠解析的字体、背景图、媒体和 @import 去掉相应声明/元素或保留可读替代，禁止留下必然 404 或越界写入。外部网络引用按本地阅读策略拦截；外部超链接交用户显式打开。原 img 尚未被替换的相对路径不代表资源存在。
6. **处理样式。** 每章 css 写为独立 `styles/ch-N.css`，保留可用的正文 style；统一重写后再引用。去掉依赖缺失字体/媒体、远程加载、已丢失布局元数据的规则；不注入旧 `OriginalDocument.html` 的强制多栏骨架，让 Navigator/Readium CSS 排版（旧骨架见 `Tingye/OriginalBookView.swift:55–59`）。默认使用新的纸面偏好，不把旧 CSS 当分页引擎。
7. **写 OPF。** package/version/unique-identifier、metadata（identifier/title/language/modified，author/description/subject 若有）、manifest（每章 XHTML、nav、CSS、图片及 fallback）、spine（严格按现有 chapter 顺序）。语言无原值时识别文本语言，失败用 `und` 并记录推断，不能假设所有书是中文。派生书声明 reflowable，不伪造原书固定版式。封面资源加 `properties="cover-image"`，可同时生成封面页及 EPUB 2 cover meta 以利兼容；没有 cover 时不随意把首图当封面。
8. **写目录。** `nav.xhtml` 用 chapters.title 创建平铺 toc，每项指向对应生成 XHTML；不能凭标题猜原 nav/NCX 层级。EPUB 3 nav 足够，NCX 是可选兼容产物，不是这条管线必须恢复的原文件。若额外生成 NCX，须同步 manifest/spine toc 标识。
9. **验证、缓存、生命周期。** 检查 XML、manifest 引用、spine 顺序、资源存在、fragment、编码和路径，测试样本跑 EPUBCheck 与 Readium `AssetRetriever → PublicationOpener(EPUBParser) → Navigator` 实际打开。缓存键含出版物内容哈希及生成器版本；哈希只覆盖参与重建的内容，排除 nativeReadChapters 等本机状态，避免标记已读就重建。原包 revision 用 source 字节哈希，文本映射另带 text/schema 版本。失败不写完成标志，不修改旧进度；同书并发请求合并。修书、同 ID 替换、还原使缓存和 Locator 解析缓存失效。缓存被清理后可重建；当前阅读会话使用的文件须保活，不能被空间清理删掉。

### 2.2 明确的缺口与推荐组合

| 缺口 | 可采取的办法 | 不能承诺的结果 |
| --- | --- | --- |
| html/head/命名空间被删，body 可能仍在 | DOM 规范化、补单层外壳；失败退 text | 原始 head 样式、语义元数据还原 |
| 仅四种 manifest 图片，原资源路径映射丢失 | 以 rN 文件化；只改有证据的引用 | 字体、SVG 文件、音视频、背景图全部恢复 |
| CSS 是合并字符串，原目录丢失 | 章级 CSS、去无解 url/@import | 原书全部 CSS 依赖可追溯 |
| 非线性/空文档、TOC 层级未保存 | 按现有 chapters 重建 spine/平铺 nav | 原 spine 数量、脚注/附录与目录树一致 |
| 旧书可能缺 document / path / resources | text 和 nativeImages 降级重建 | 恢复原版式和精确 DOM 坐标 |
| 封面/语言/固定版式信息不全 | 使用已有 cover；语言推断；reflowable | 无依据恢复出版物布局 |

以上缺口直接来自第 1 问的白名单和清洗逻辑（`Tingye/BookImporter.swift:130–171`；`Tingye/OriginalBookView.swift:7–12`）。**新导入继续全部重建会永久重复这些损失；只留原文件又无法打开存量。故采用“新书原包、旧书派生包”的组合。** 已有书可通过原有修书入口补原文件并保留 book.id（`Tingye/AppModel.swift:560–606`）。

建议持久路径为 `TingyeNative/<owner>/Publications/<id>/source.epub`，附相对路径、SHA-256、来源类型、结构映射版本的 sidecar 元数据；Book 根增加可选 `epubSource` 描述，不存绝对 URL 或安全书签，也不在 Book 中再塞一份源包 base64。派生缓存放独立 Readium 缓存目录，缓存可删除、source 不可被缓存清理。文件、JSON、catalog 用可回滚 staging 提交；同 ID 被无原包 JSON 替换时必须移除/隔离旧 source，不能误开旧书。

备份/导出必须覆盖 source：单元 4 在现有 ICloudArchive.Item 上增加可选原包附件（base64 + digest）和映射元数据，解包后写回 source 路径；保留现有 v1/v2 解码，旧软件可忽略新可选项。独立单书 BackupPacket 导出也要加可选附件，并在 `BookImporter.read(json)` 的 packet 分支提取它；不能只在“整库备份”里保留原包。这是兼容优先方案，大文件内存风险见风险表；若以后改 ZIP 分文件备份，应另起协议版本，不能本次悄悄让旧 JSON 读不了。没有附件的旧备份恢复后仍走派生包，不依赖原设备路径。

## 3. 打开路由与完整调用链

实际分流分两层，漫画判断**不在 ReaderView 内**：

1. 书架网格/列表调用 `readingButton`，按钮触发 `model.open(entry)`（`Tingye/ShelfView.swift:812–820`）；上下文菜单也用它（`Tingye/ShelfView.swift:1073–1076`）。详情开始阅读同样调用（`Tingye/LibraryViews.swift:128`）。
2. `AppModel.open` 清理一次性 readerJump 后进 `openBook`；指定章句的重载先设置 readerJump（`Tingye/AppModel.swift:199–207`）。
3. `openBook` 命中缓存直接设置 selectedBook，否则 `loadBook → Task.detached { disk.read(id) } → Book JSON decode/validated → remember`，成功设置 selectedBook（`Tingye/AppModel.swift:208–245`；`Tingye/Services.swift:613`）。
4. `TingyeApp` 的 fullScreenCover 观察 selectedBook：`book.fields["comic"]?.bool == true` → ComicReaderView；否则 ReaderView（`Tingye/TingyeApp.swift:278–285`）。ShelfEntry.isComic 另按 `format.uppercased() == "CBZ"` 分类，不能混为同一个判据（`Tingye/Models.swift:183–184`）。
5. ReaderView 初始化 ReaderDocument，缓存 `isPDF = book.isPDF`；Book.isPDF 判的是 **fields["pdf"] 是否存在**，不是 format。document.pdf 成功解码为 Data 时进入 PDFReader，否则进入 textContent（`Tingye/Models.swift:68–69`；`Tingye/ReaderView.swift:263–275,357–359,423–429`）。非 PDF/漫画的 EPUB、MOBI、TXT 等目前全部走原生文字+块渲染；scrolling 选 TextKit，分页选 CoreText（`Tingye/ReaderView.swift:646–684,1137–1164`）。
6. onAppear 恢复 `entry.progress`，按 TextAnchor 校验句号，再消费显式 readerJump，并 persist（`Tingye/ReaderView.swift:522–540`）。

**新增路由判据：`book.format.uppercased() == "EPUB"`，底层就是 `book.fields["format"]?.string`。** 当前导入确实写 `"EPUB"`；没有单独的 EPUB 导入来源字段（`Tingye/Models.swift:65`；`Tingye/BookImporter.swift:169–171`）。不能用 document 存在与否判断，HTML/Markdown/MOBI 也可能有它；不能用“有资源”判断（`Tingye/BookImporter.swift:30–32,100–108`；`Tingye/MobiReader.swift:295`）。缺 format 的 Book 默认 TXT，保持原语义；不以 HTML 猜格式并擅自迁为 EPUB。

施工时在 `TingyeApp.swift:278` 的同一根入口新增集中 ReaderRouter：保留漫画优先、PDF 存在优先，再判断 EPUB，其余原 ReaderView；EPUB 进入新的 ReadiumReaderView，不在旧 textContent 里外挂第三套分页。PDF 无效数据的处理另给明确错误，避免伪装 EPUB。AppModel 继续加载 Book 文本层；异步 Publication 准备放 EPUB session，支持取消、恢复、错误重试。详情、书架、全局摘记、今日一句和听书页的“从这里读”必须最终经过这个入口，并传完整 Locator/引用 ID，不能只传章句丢掉新定位。

## 4. 阅读偏好与七种纸面完整清单

### 4.1 ReaderPreferences 的全部存储字段

结构确切名称为 `ReaderPreferences`，不是 ReadingPreferences（后者是 UI 名称）。定义与默认值在 `Tingye/Theme.swift:875–888`，ReaderView 由 AppStorage 组装（`Tingye/ReaderView.swift:340–361`）。它是 Equatable 的内存值，不是独立 Codable 存档。

| 字段 | 类型 / 默认值 | AppStorage 键 | 写入 UI 与证据 | EPUBPreferences 迁移方向 |
| --- | --- | --- | --- | --- |
| fontSize | Double / 19 | reader.fontSize | ReadingPreferencesView 字号按钮/滑杆 14…34：`Tingye/ReaderView.swift:2064–2073`；MoreTypographyView 恢复默认：2279–2282 | fontSize 是倍率，按 Readium 基准字号校准，不能写 19 |
| lineSpacing | Double / 11 | reader.lineSpacing | MoreTypographyView 行距 2…28：`Tingye/ReaderView.swift:2254`；恢复默认：2280 | 转 lineHeight 比例，需与当前字体行高实测 |
| font | String / "system" | reader.font | ReadingPreferencesView fontChip：`Tingye/ReaderView.swift:2200–2222`；MyFontsView 选用/删除/导入：`Tingye/Typography.swift:119–134,154`；恢复默认：`Tingye/ReaderView.swift:2281` | fontFamily + fontFamilyDeclarations，系统/4 个内置/自定义字体 |
| paper | String / "paper" | reader.paper | 纸色 Picker/按钮：`Tingye/ReaderView.swift:2099–2134`；日夜切换：1327–1335；恢复默认：2281 | backgroundColor/textColor/theme，动态色先解析成当前日/夜的实际色值 |
| scrolling | Bool / false | reader.scrolling | ReadingPreferencesView 翻页方式：`Tingye/ReaderView.swift:2149–2153`；恢复默认：2281 | scroll |
| paragraphSpacing | Double / 15 | reader.paragraphSpacing | MoreTypographyView 段距 0…36：`Tingye/ReaderView.swift:2255`；恢复默认：2280 | paragraphSpacing，转换单位 |
| margin | Double / 24 | reader.margin | MoreTypographyView 页边距 16…52：`Tingye/ReaderView.swift:2256`；恢复默认：2280 | pageMargins 是倍率，结合视口校准 |
| indent | Bool / true | reader.indent | MoreTypographyView 首行两字：`Tingye/ReaderView.swift:2257`；恢复默认：2280 | paragraphIndent = 2em 或 0，检查 CJK 生效情况 |
| justified | Bool / true | reader.justified | MoreTypographyView 两端对齐：`Tingye/ReaderView.swift:2258`；恢复默认：2280 | textAlign = justify / start |
| letterSpacing | Double / 0（pt） | reader.letterSpacing | MoreTypographyView 滑杆 -1…6、步长 .5：`Tingye/ReaderView.swift:2245–2252`；恢复默认：2282 | letterSpacing，按字号换单位并验证支持范围 |
| convert | String / "none"（none/s2t/t2s） | reader.convert | MoreTypographyView 简繁：`Tingye/ReaderView.swift:2271–2282` | 没有直接对应项，见下文 |

ReaderPreferences 的**其余计算成员**是 kind、background、foreground、secondary、highlightBand、highlight、uiFont；静态 bundledFonts 为 serif→NotoSerifCJKsc-Regular、kai→LXGWWenKaiLite-Regular、hansans→NotoSansCJKsc-Regular、xixihei→LXGWNeoXiHei（`Tingye/Theme.swift:889–933`）。MyFontsView 的 AppStorage 声明默认却是 `"serif"`，与结构/ReaderView 的 `"system"` 不同，迁移时尊重已保存值、统一未设置时的默认（`Tingye/Typography.swift:101`）。

还需搬迁以下**结构外**状态，不能声称它们已在 ReaderPreferences 中：

| 状态 | 类型 / 默认 | 写入位置 / 当前行为 | 迁移处理 |
| --- | --- | --- | --- |
| reader.pageTurn | String / slide；slide/fade/blur/none | `Tingye/ReaderView.swift:345,399–409,2155–2162` | Navigator 没有四种同名偏好；保留配置，支持的使用导航动画，fade/blur 是否退化见待拍板 |
| reader.doublePage | Bool / true | MoreTypographyView：`Tingye/ReaderView.swift:2240,2260–2267` | reflowable 用 columnCount，fixed-layout 用 spread；保留窄屏、滚动、eink 限制（1137–1144） |
| study.paperAlwaysLight | Bool / false | 纸色页 Toggle：`Tingye/ReaderView.swift:2043,2139–2146`；动态解析：`Tingye/Theme.swift:864–869` | 同时解析文字和背景；外观变更重新 submitPreferences |
| app.appearance | String / system | ReaderView 读取：`Tingye/ReaderView.swift:353,496`；设置目录入口：`Tingye/StatsView.swift:654`；实际 AppearanceView 写入：`Tingye/LibraryViews.swift:680–681,715–718` | 和 SwiftUI colorScheme/纸色共同决定当前实际颜色 |
| autoTurn | Int / 0，临时会话秒数 | `Tingye/ReaderView.swift:354–355,502–510,862–866` | 调 Navigator goForward，暂停/结束条件仍由 app 管理，不持久化 |

Readium 偏好依据 [EPUBPreferences.swift](https://github.com/readium/swift-toolkit/blob/3.11.1/Sources/Navigator/EPUB/Preferences/EPUBPreferences.swift#L10) 和 [EPUBPreferencesEditor.swift](https://github.com/readium/swift-toolkit/blob/3.11.1/Sources/Navigator/EPUB/Preferences/EPUBPreferencesEditor.swift#L90)：fontSize 基准倍率 1.0、pageMargins 默认倍率 1.0；多种排版项仅在 publisherStyles=false 时有效，不能照搬原数值。默认 reflowable 采用听页排版偏好并设 publisherStyles=false；fixed-layout 保持原布局，只应用支持的偏好。旧 WebKit 行高公式 `(fontSize + lineSpacing * 1.35) / fontSize` 只能作为视觉校准起点，原生正文实际用 UIFont+NSMutableParagraphStyle，不能当成跨引擎的精确换算（`Tingye/OriginalBookView.swift:49–54`；`Tingye/ReaderView.swift:7–15`）。

字体必须通过 Readium 的 CSSFontFamilyDeclaration/CSSFontFace 供应实际文件，UIFont 注册不能自动让 WKWebView 使用字体；内置字体和 FontLibrary 自定义文件均要处理，瘦身 IPA 缺字体时回退系统。参考 [EPUB Fonts](https://github.com/readium/swift-toolkit/blob/3.11.1/docs/Guides/Navigator/EPUB%20Fonts.md#L55)。

convert 当前只转换显示，长度变化则整章保留原文（`Tingye/Typography.swift:7–18`）。建议给 Readium 的 Publication resource 加按需 XHTML 文本节点转换层，保留原字符与显示字符的映射，选区/进度存原文 Locator，重新转换渲染而不改 source.epub/Book.text；不要直接改 innerHTML 或只设 language 当转换。Readium 支持资源包装 [TransformingContainer.swift](https://github.com/readium/swift-toolkit/blob/3.11.1/Sources/Shared/Toolkit/Data/Container/TransformingContainer.swift#L9)，但 DOM 转换与 Locator 往返必须在单元 2/3 验证；未通过前不能把“简繁已支持”写进验收。

### 4.2 七种纸面：实际颜色值

值为 `#RRGGBB`。背景来自 `Tingye/Theme.swift:846–871`，正文来自 892–901，次字来自 903–911；paper 的正文/次字另引用 Theme.ink/ink3（`Tingye/Theme.swift:11,17`）。虽然旧注释说“其他纸色保持原样”，实际 `.mist/.ancient/.eink/.white` 也走动态色函数，以下以可执行代码为准。

| key / 名称 | 背景 日 / 夜 | 正文 日 / 夜 | 次字 日 / 夜 |
| --- | --- | --- | --- |
| paper / 默认（宣纸） | #FAF9F5 / #141413 | #1C1B18 / #EFEDE6 | #6E6A5A / #99968A |
| mist / 雾灰 | #E6EBF1 / #1D2733 | #14181F / #D8E2EC | #666666 / #93A3B5 |
| ancient / 旧书 | #F3E7D6 / #2A2118 | #2C2418 / #EAD9BE | #6E5F4B / #B39B78 |
| eink / 浅灰 | #F0F0F0 / #1E1E1E | #242424 / #E8E8E8 | #666666 / #A8A8A8 |
| white / 纯白 | #FFFFFF / #000000 | #14181F / #EFEFEA | #666666 / #A9A9A2 |
| blue / 深蓝 | #1A2C3A / #1A2C3A | #D5E4F0 / #D5E4F0 | #8AA0B4 / #8AA0B4 |
| night / 夜读 | #101012 / #101012 | #EFEDE6 / #EFEDE6 | #A5A296 / #A5A296 |

`paperAlwaysLight` 为 true 时所有调用 paperColor 的颜色取日间值；但 paper.foreground/secondary 走 Theme 动态色，现有实现存在与“常亮”不完全一致的边界，移植时应让纸面背景和文字使用同一明暗决策，防止低对比（`Tingye/Theme.swift:864–872,892–911`）。`ReaderPaper.dark` 只识别 blue/night，ReaderView.isDarkPaper 又只额外识别默认纸的 dark 外观，不能照抄此布尔值来给所有纸面选 Readium.theme（`Tingye/Theme.swift:863`；`Tingye/ReaderView.swift:363`）。

陶土强调色日 #A84A28 / 夜 #F0AD88，跟读标记 #D97757（`Tingye/Theme.swift:23,27,915–919`）；原生整句跟读背景 alpha：深纸或默认纸夜间 .26，其余 .14；分页跟读另用夜 .18/日 .16（`Tingye/ReaderView.swift:1129`）。新实现分别映射偏好色、selection/CSS 和 Decoration；普通链接/选区/跟读不是同一个 EPUBPreferences 字段。UI 面板深 #1F1E1D / 浅白，阅读强调另由 readerAccent 决定（`Tingye/ReaderView.swift:367–370`）。用户新建划线调色盘为 yellow=#D69E3A、clay=#A34F36、blue=#4A6FA5、pink=#C85A53、purple=#7E629E，旧 green=#4E8E75 仍须兼容（`Tingye/ReaderAnnotations.swift:23–34`）；不能照 Models 的旧五色注释漏掉 clay 或重写旧 green。

## 5. 全库定位数据：存储、读写点与双向转换设计

### 5.1 现状数据形态

这些引用都在 `catalog.json` 的 ShelfEntry 中，**不在 Books/<id>.json 内**（`Tingye/Models.swift:137–164`；`Tingye/Services.swift:606–613`）。

| ShelfEntry 字段 | 对应结构的全部定位/业务字段 | 证据 |
| --- | --- | --- |
| progress（必需） | ReadingProgress：chapter:Int=0、position:Int=0（句序号）、updatedAt:Double=0（毫秒）、anchor:TextAnchor?=nil | `Tingye/Models.swift:119–127,148` |
| listeningProgress（可选） | 同 ReadingProgress；首次没有它时沿用 progress | `Tingye/Models.swift:149–151`；`Tingye/AppModel.swift:513–518` |
| bookmarks（必需数组） | Bookmark：id:UUID、chapter:Int、position:Int、excerpt:String、anchor:TextAnchor?、date:Date | `Tingye/Models.swift:128–135,157` |
| highlights（可选数组） | Highlight：id:UUID、chapter:Int、start:Int、end:Int（句号，含尾）、text:String、anchor:TextAnchor?（只锚起始句）、color:String=yellow、style:String=background、note:String?、date:Date | `Tingye/Models.swift:231–246,163–164` |
| 四类引用的 anchor | TextAnchor：quote:String（最多 120 个 Swift Character），before/after:String?（各最多 40）；邻接至多两句拼接，before 取尾/after 取首；不是 UTF-16 字节上限 | `Tingye/Models.swift:106–117,306–320` |

Sentence.range 是章 text 的 UTF-16 NSRange，句序号从 0 起；260 UTF-16 以上长句再分块（`Tingye/Models.swift:273–298`）。现有 `enum Locator` 是听页自有重定位工具，**不是 ReadiumShared.Locator**。坐标校验、quote 前缀互含、上下文消歧、最后坐标钳制全在 `Tingye/Models.swift:301–395`；书签在 398–407，划线以起点+旧跨度并用全文校验终点在 410–436。它只在本章找，不会全书跨章搜索；不能声称 142 已解决 spine 变化重定位。

### 5.2 读写和消费位置

| 动作 | 当前代码入口与行为 |
| --- | --- |
| 保存阅读 | ReaderView.persist → AppModel.saveProgress：页翻/跳转保存、退出/后台保存（`Tingye/ReaderView.swift:551–553,1192–1193,1299–1322`）；滚动回调只换算并更新内存 sentencePosition，随后由 persist 的生命周期调用落盘，没有看到每次滚动的独立保存调用（`Tingye/ReaderView.swift:651–654`）。AppModel 经 sync.update 生成时间戳、补 anchor、写 entries、推 KVS、1200ms 防抖 catalog（`Tingye/AppModel.swift:366–411`） |
| 恢复阅读 | ReaderView.onAppear 读 entry.progress、Locator.resolve、消费 readerJump（`Tingye/ReaderView.swift:522–540`）；ReaderDocument.sentences 按章缓存（263–275） |
| 书签新增/删除 | 顶栏调用 model.bookmark（`Tingye/ReaderView.swift:724–739`），听书页同样调用，取 player.currentText（`Tingye/PlayerView.swift:350–356`）；AppModel 按章句切换、excerpt 截 80 字、补 anchor，立即 saveCatalog（`Tingye/AppModel.swift:426–434`） |
| 书签跳转 | ContentsView.resolvedTarget 先解析 anchor，按钮调用 jump；ReaderView.jump 更新章句并 persist（`Tingye/ReaderView.swift:1785–1803,1889–1894,1299–1303`）。但详情书签页直接传旧章句，不做此解析（`Tingye/LibraryViews.swift:251–252`），是要统一的消费缺口 |
| 划线创建/编辑/删除 | ReaderView.selectionPanel 把完整句范围、text、anchor 交 model（`Tingye/ReaderView.swift:1250–1275`）；Library.addHighlight 补 anchor、合并无笔记重叠项、排序，update/remove 修改数组（`Tingye/Library.swift:97–122`）；updateEntries 负责目录写回（`Tingye/Library.swift:11–23`） |
| 划线渲染 | ReaderView.chapterMarks 逐章筛选、内存 Locator.resolve 后由 ReaderMark.range 转 UTF-16（`Tingye/ReaderView.swift:1223–1233`）；ReaderMark.apply 绘制、滚动另有增强串坐标映射（`Tingye/ReaderAnnotations.swift:43–81`；`Tingye/ReaderView.swift:111–130`） |
| 摘记跳转 | ContentsView.notes、详情 NotesList 直接把 note.chapter/start 交跳转（`Tingye/ReaderView.swift:1781–1782`；`Tingye/LibraryViews.swift:232`）；全局入口同样传章句（`Tingye/NotesUnifiedView.swift:127,168`），应随 Locator 统一 |
| 保存听书 | AppModel 初始化 player.onProgress → saveListeningProgress（`Tingye/AppModel.swift:112,414–424`）；SpeechPlayer.playSentence/系统 utterance 开始回调，seek 也回调（`Tingye/SpeechPlayer.swift:433,500,726–735`）；不推阅读 KVS，不改阅读位置 |
| 恢复听书 | startListening 使用显式传入值，否则 listeningProgress，否则 progress；自有 Locator.resolve 后 player.start（`Tingye/AppModel.swift:509–519`）；从当前句听、seek 与阅读跟随另见 `Tingye/ReaderView.swift:1185–1219` |
| 修书 / 同 ID 替换 | 四类引用按 TextAnchor 重定位，旧无锚点书签/划线保留（`Tingye/AppModel.swift:346–359,584–603`；`Tingye/Models.swift:439–463`） |

整库 ICloudArchive.Item 带书签、划线、listeningProgress，导出和还原均有明确赋值（`Tingye/ICloudBackup.swift:16–24,225–235,414,435`）。单书 BackupPacket v2 当前只有 Book + progress，不含其他三类引用（`Tingye/Models.swift:260–270`）。KVS 当前只写 `c/p/t`，**不传 TextAnchor**，接收时新建 ReadingProgress 因而 anchor=nil（`Tingye/ICloudBackup.swift:702–708,755–759`）；读取更新判断也只比章句（736–739），新 Locator 即使在同一句不同 DOM 范围也要能更新，不能沿用此去重条件。

### 5.3 要实现的 Locator 双向转换合同

在四个引用结构增加可选 `locator`（Readium Locator JSON 对象）、`locatorVersion` 和 `publicationRevision`；新增字段全部 Optional 解码。存储采用 JSON 对象包装，桥接处用 `ReadiumShared.Locator` 的 JSON API，不假设它是 Swift Codable。代码中显式限定 `ReadiumShared.Locator` / `ReadiumShared.JSONValue`，与听页同名类型隔离；如需重命名本地工具，单独原子修改全部调用点。

Readium Locator 的 `href/type/title/locations/text` 结构、position>=1、progression/totalProgression 为 0…1、text.before/highlight/after 的正式依据见 [Locator.swift](https://github.com/readium/swift-toolkit/blob/3.11.1/Sources/Shared/Publication/Locator.swift#L11)。原生 position 是 0 起句号，两者决不能直接赋值。

转换优先级和失败策略：

1. **旧引用 → 资源。** EPUB 有原包时，用旧 chapter.document.path 匹配 Readium readingOrder href（统一解码、去片段、消除 dot segment），不能按数组下标硬对齐；旧库重建用明确 chapter→派生 href 表。原 path 缺失/资源删失时，用标题+文本候选查找全书，重复文本结合上下文、原相邻章节和顺序消歧。仅在本章找不到时扩大范围，并限制成本、记录置信度。
2. **旧引用 → 文本/DOM 范围。** 原生 Locator.resolve 先在原文本层确定句子；TextAnchor.quote→locator.text.highlight、before/after→同名上下文作为候选。142 上下文是去掉分隔空白的相邻句拼接，不能不经规范化就当成 DOM 的严格邻接上下文。建立 HTML 文本节点与原生 text 的对齐索引，保留原始 UTF-16、规范化字符和 DOM range 的映射（处理标题、实体、空白、表格、ruby、脚注、简繁）。在选定 DOM 范围生成 selector/范围扩展及实际上下文，再得到 Readium 可消费 Locator。
3. **划线范围。** anchor 只代表起始句；必须使用 Highlight.text 全文和 start…end 对应的文本范围恢复终点，不能只高亮前 120 字。单个 chapter/spine 资源内存一个范围 Locator；未来支持跨资源选择时存分段 Locator 数组并共用用户标注 ID。不能仅用 progression 装饰范围。新建选区保存 Navigator 原始选区 Locator，并同时换算文本层 start/end。
4. **新 Locator → 旧坐标。** href 经映射找文本章，text/DOM 对齐找 UTF-16 范围，再 Sentence.index 得句号/跨度，生成新的 TextAnchor；听书回调反向生成该句范围 Locator。DOM 页位置可精于句号，主定位保留完整 Locator，兼容坐标允许同一句内精度损失。
5. **恢复和保存。** 有同 revision 的有效 Locator 优先；无效/变版走 TextAnchor 重定位；再尝试 href+资源内 progression；最终回退已钳制的章句对应资源开头。不覆盖失败条目的旧文本与锚点，不把模糊匹配假装成精确划线；无法确定范围则保留标注、显示未定位状态。迁移状态区分精确、文本重定位、近似、未解析，可重试。不能让初始化默认页回调抢先覆盖恢复位置。
6. **全格式范围。** 非 EPUB 也写相同 Locator JSON：TXT/Markdown/MOBI/DOCX/HTML 以稳定逻辑 href `tingye://book/<id>/chapter/<n>`、type=text/plain 加文本范围扩展；PDF 用稳定页 href/fragment 和页内信息；漫画用页 href/type 与资源引用。它们不生成 EPUB，不进入 Navigator；其原生视图通过桥接继续用章句/页号。逻辑 href 是应用内部合同，不能误送 EPUB Navigator。以后给这些格式新增真实出版物 URL 时另做版本映射。
7. **迁移事务。** 先备份 catalog，再按书后台、可取消、可重复地转换，打开书时优先补齐，空闲时覆盖剩余全库；每书原子提交。不可只迁 progress 漏掉 listeningProgress、书签、划线。旧引用保留，便于恢复、旧设备和问题诊断。新建/修改/跳转/渲染都走同一 bridge，避免详情页、全局笔记、结束页摘句各有一套。
8. **同步与备份。** 阅读 KVS 在原有 c/p/t 兼容项旁加有大小限制的 Locator/anchor/revision 字段，新版优先，旧版忽略；仍用原有单调时钟和“正在阅读保护”，不向 KVS 塞整段划线或原包。听书保持独立且不推阅读位置。整库/单书备份按现有各自范围带新增字段，解码非法 Locator 时仅忽略该 Locator，不拒绝整个可读旧书；显示全文与笔记原样保留。

## 6. 听书、搜索与统计：为何保留原生文本层

SpeechPlayer.start 直接缓存 `book.chapters`，对指定章的 `.text` 执行 `Sentence.split`，选 position，playSentence 用 currentText 创建系统 utterance 或云语音请求（`Tingye/SpeechPlayer.swift:378–387,488–505`）。下一章分句缓存仍读 `.text`（681–686）；不是从 WebView DOM 或 EPUB 原文件即时取句。句号、UTF-16 范围还用于跟读和预取。

书内检索是 `ReaderSearch.matches(in:[Chapter])`：逐章对 chapter.text 的 NSString 做大小写不敏感查找，同章多次命中分别保留，最多 200 项，正文无命中才匹配标题；结果携带 UTF-16 offset 和上下文（`Tingye/ReaderView.swift:1684–1717`）。ContentsView 防抖 150ms 后后台调用，点击用 Sentence.index 把 offset 变句号（1820–1829、1885–1887）。它不搜索 CSS、DOM、资源或 Readium SearchService。迁移后结果通过 Locator bridge 跳 Navigator，保留这个搜索口径即可。

统计分两类：

- **时长/会话不依赖正文文本。** TingyeApp 每 5 秒调用 `recordUsageTick`；前台正文可见优先计阅读，否则播放中且不 buffering 计听书；同一 tick 不重复计（`Tingye/TingyeApp.swift:263–267`；`Tingye/AppModel.swift:656–675`）。ReaderView 进出和听书面板控制正文可见性（`Tingye/ReaderView.swift:523,551,555`）。ReadingSession 在 180 秒内同书同模式、同一天合并，最多 3000 项，readingSeconds/sessions 存 UserDefaults（`Tingye/Library.swift:131–171`；`Tingye/AppModel.swift:156–157`）。Navigator wrapper 必须接同一可见性生命周期，不能新增另一个定时器。
- **书架完成百分比/句子数依赖文本。** ShelfEntry 初始化按章分句生成 sentenceCounts，readFraction 按句数权重计算，无缓存时退章比例（`Tingye/Models.swift:172–175`；`Tingye/AppModel.swift:4–16`）；笔记数量也由 entries.highlights 统计（`Tingye/Library.swift:126–127`）。保留这套兼容统计；Readium totalProgression 可作定位/诊断，不直接替换既有书架百分比造成突然跳变。

因此本次**必须保留原生 Book JSON 文本层，理由是现有功能合同和引用兼容，而不是声称时长只能依赖 JSON**。以后改成 Readium 内容迭代/TTS/搜索是另一个独立项目，不在这次替换 EPUB 渲染时同时换口径。

| EPUB 管线部分 | 最终保留/停止 |
| --- | --- |
| 原文件复制与校验、Readium 解析 EPUB 结构、取得 readingOrder/TOC/资源 | 新增并执行，Readium 是结构权威 |
| HTMLText.chapter 的文本抽取/空白实体规范化、Sentence.split、标题与文本章映射 | 保留，从 Readium 资源读数据；已有 Book.text 不重算覆盖 |
| Book ID/format/元数据、封面/分类索引、听书/检索需要的 chapters.text 与路径映射 | 保留；新书补原包 readingOrder/TOC 元数据 |
| 旧 epub(url) 的 SafeArchive→container→OPF→manifest/spine 结构读取 | 单元 1 可暂留保兼容；单元 4 切换到 Readium 后停止用于新 EPUB，不能长期双解析裁定结构 |
| document HTML/CSS、nativeImages/resources/marks | 存量全部保留作重建/兼容；本轮新书也保留派生兼容快照以便旧备份恢复/旧版读取；日后可专门瘦身。它们由 Readium 资源派生，不再决定 EPUB 视觉渲染 |
| CoreText 分页/NativeTypesetter、ChapterBlockParser/ScrollAugmenter、旧 OriginalDocument WebKit 分页 | EPUB 路由停用；其他格式/现有测试依赖的部分不删除 |
| PDF/MOBI/TXT/Markdown/漫画导入与渲染 | 保持原流程；ZIP 库归一只改解压依赖适配，不改变格式语义 |

## 7. 工程和构建摸底

### 7.1 工程结构与已有依赖

`project.pbxproj` 是传统显式 fileRef/PBXBuildFile/Group/BuildPhase 工程（objectVersion=54），不是自动同步文件夹；新增 Swift 文件要挂 app/test Sources，新增字体/许可证/测试夹具挂相应 Resources（`Tingye.xcodeproj/project.pbxproj:6,9–62,75–127,129–156,260–311`）。Targets 是 Tingye（application）、TingyeTests（unit-test bundle）、TingyeUITests（ui-testing bundle），测试都依赖应用（260–311）。共享 scheme 已存在于 `Tingye.xcodeproj/xcshareddata/xcschemes/Tingye.xcscheme`。

已经有 3 个 SPM 包，**不是无 SPM 工程**：

| 包 URL | 工程约束 / 当前锁定 | product |
| --- | --- | --- |
| https://github.com/weichsel/ZIPFoundation.git | exact 0.9.20 / 0.9.20 | ZIPFoundation |
| https://github.com/kishikawakatsumi/SMBClient.git | exact 0.3.1 / 0.3.1 | SMBClient |
| https://github.com/EmergeTools/Pow.git | upToNextMajor 1.0.6 / 1.0.6 | Pow |

证据：`Tingye.xcodeproj/project.pbxproj:303–307,333–337,725–767`；锁文件 `Tingye.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved:4–30`。

最低 iOS 均 17.0、Swift language mode 为 5.0（如 `Tingye.xcodeproj/project.pbxproj:447,451,544,551,570,580,652,658,677,687`）。版本号/构建号是各 target Debug/Release 的 CURRENT_PROJECT_VERSION=142、MARKETING_VERSION=1.25.0（479/484、564/575、592/597、671/682）；本单元不 bump。Readium 3.11.1 需 iOS 15.0，**没有最低 iOS 冲突**；Package tools-version=5.10，需要相应新工具链，不能把工程 Swift language mode=5.0 当编译器过旧的证据。[Package.swift](https://github.com/readium/swift-toolkit/blob/3.11.1/Package.swift#L1)。单测 CI 已指定 Xcode 26.3，unsigned 使用 macos-latest 默认 Xcode（`.github/workflows/tests.yml:43–57`；`.github/workflows/build-unsigned-ipa.yml:52–61`）。

### 7.2 unsigned 构建命令原文及 SPM 行为

workflow 并非直接 archive：先显示 Xcode/Swift 版本，再从 pbxproj 提取版本，在 Build 步执行下列原文（`.github/workflows/build-unsigned-ipa.yml:73–83`）：

```bash
chmod +x scripts/build-unsigned-ipa.sh
ARGS=""
if [ "${{ inputs.slim_fonts }}" = "false" ]; then ARGS="$ARGS --full-fonts"; fi
if [ "${{ inputs.osize }}" = "true" ]; then ARGS="$ARGS --osize"; fi
# tag 触发时没有 workflow_dispatch 输入，inputs.* 为空，上面两个
# 判断都不成立，默认就是瘦身 + -O，和脚本默认值一致。
# shellcheck disable=SC2086
./scripts/build-unsigned-ipa.sh $ARGS
ls -lh build/Tingye-unsigned.ipa
```

脚本 archive 的 xcodebuild **原文**如下（`scripts/build-unsigned-ipa.sh:77–98`；ARCHIVE/DERIVED/SWIFT_OPT 定义在 66–74）：

```bash
xcodebuild -project Tingye.xcodeproj -scheme Tingye \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  -derivedDataPath "$DERIVED" \
  archive \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_ENTITLEMENTS="Tingye/Tingye-unsigned.entitlements" \
  DEVELOPMENT_TEAM="" \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=NO \
  SWIFT_OPTIMIZATION_LEVEL="$SWIFT_OPT" \
  SWIFT_COMPILATION_MODE=wholemodule \
  DEBUG_INFORMATION_FORMAT=dwarf \
  STRIP_INSTALLED_PRODUCT=YES \
  STRIP_SWIFT_SYMBOLS=YES \
  DEAD_CODE_STRIPPING=YES \
  COPY_PHASE_STRIP=YES \
  DEPLOYMENT_POSTPROCESSING=YES
```

脚本默认 Release/arm64、`SWIFT_OPT=-O`，只有 --osize 改 -Osize；ARCHIVE=`build/Tingye-unsigned.xcarchive`、DERIVED=`build/DerivedData-unsigned`。没有显式 `-resolvePackageDependencies`，也没有 `-disableAutomaticPackageResolution`，因此正常 Xcode archive 会解析项目 SPM 依赖；这是根据命令参数的构建预期，**本 Linux 环境未运行 Xcode 验证新增依赖**。单元 1 增加显式 resolve 作为前置验收，检查日志与更新锁文件；后续 archive 无需人工先在 Xcode GUI 安装包。Readium 资源 bundle 必须进入 app，不能只看 Swift 链接成功。

unsigned 脚本打包阶段删除两个 LXGW 字体及 plist 项（`scripts/build-unsigned-ipa.sh:118–145`），新 Navigator 字体配置必须检查实际文件存在。workflow 还会发 Release（`.github/workflows/build-unsigned-ipa.yml:131–143`），**本单元及后续仅验证时不要无意触发发布**；可在 CI 测试 job 或本地 Mac 直接跑构建脚本。

### 7.3 必须优先解决 ZIPFoundation 包身份

Readium 3.11.1 的依赖包含 `readium/ZIPFoundation` from 3.0.1，且使用 product/module **ReadiumZIPFoundation**；现工程是 `weichsel/ZIPFoundation` exact 0.9.20，两个 URL 的默认包 identity 都会是 zipfoundation。模块改名不等于包 identity 已隔离，不能假设这两条不同仓库/不相容版本会直接共存。证据：[Readium Package.swift:31,44](https://github.com/readium/swift-toolkit/blob/3.11.1/Package.swift#L31)、[fork 的 Package.swift](https://github.com/readium/ZIPFoundation/blob/3.0.1/Package.swift) 和本工程 pbxproj:726–732；目前是依赖图风险判断，尚未实际执行解析来断言具体报错。

推荐单元 1 统一使用 Readium fork（与工具包范围一致并在 Package.resolved 锁实际版本），将 app 的 direct ZIPFoundation 引用换为 ReadiumZIPFoundation，适配 `Tingye/BookImporter.swift:4,186–193` 的 SafeArchive 和 `TingyeTests/NativeCoreTests.swift:1463,1545–1548` 的导入/写 ZIP API。DOCX、漫画等仍通过原 SafeArchive 工作，必须回归，不把换压缩库扩大为换其他格式解析器。若解析器证明可用明确 identity 方式隔离两包，也可评估，但不要先采用维护私有 fork/改 URL 的复杂方案。

`create-project.rb` 会重建整个工程，仍写旧 ZIPFoundation 及旧 128/1.24.0（`create-project.rb:5,22–28,41–47`），不能运行它覆盖现工程。单元 1 同步依赖声明/版本来源，后续若采用 Tingye/Readium 子目录还须更新其仅扫描顶层 Swift 的 glob（12 行），防止未来再生成漏文件。

## 8. Readium 稳定版本、products、依赖和许可证

### 8.1 联网核验记录

2026-11-15 通过 GitHub 连接器实际读取 [releases API](https://api.github.com/repos/readium/swift-toolkit/releases?per_page=100)，筛选非 draft、非 prerelease 的 `3.x.y` 并按语义版本比较。结果最新为 **3.11.1**，发布于 **2026-10-16 13:29:04 UTC**；4.0.0-alpha.1/alpha.2 是预发布，不选。证据：[3.11.1 release](https://github.com/readium/swift-toolkit/releases/tag/3.11.1)。读取的是 tag **3.11.1 的 Package.swift**，不是 main，也不是 4.0 alpha。[版本化 Package.swift](https://github.com/readium/swift-toolkit/blob/3.11.1/Package.swift)，文件 blob SHA=`2fd938005190e0ac966cf49c426a320dca4d97f3`（GitHub fetch_file 返回）。另核验 annotated tag 指向 commit `9a8c094b72245fd27043c9d298005e5c78b32a01`（[tag 对象](https://api.github.com/repos/readium/swift-toolkit/git/tags/dbe93a839d429c5d1672f9c7536f931d9591440a)），便于后续锁文件审计。

包名 Readium，swift-tools-version 5.10、platform `.iOS("15.0")`；许可 **BSD 3-Clause**，需随源码和二进制分发保留相应版权/条款（[LICENSE](https://github.com/readium/swift-toolkit/blob/3.11.1/LICENSE)）。第三方依赖各有许可证，单元 1/4 汇总到许可展示：现有 FontLicenseView 只展示字体，需要扩展为含组件的许可页（`Tingye/LibraryViews.swift:495,607,777–811`；已有许可资源见 `Tingye.xcodeproj/project.pbxproj:21–24,54,61`）。release 明确允许 minor 版出现小型破坏性变更，因此用 exact 3.11.1 和提交锁文件，避免浮动到未来 3.x。

### 8.2 products 全清单及每个 product 的直接依赖

以下都是独立 `.library` product，各自导出同名 target；列的是它们 target 的直接依赖，引用其他 Readium product 时其依赖再传递展开，不能把内部 target 和 product 混淆。[Package.swift products:14–24 / targets:36–185](https://github.com/readium/swift-toolkit/blob/3.11.1/Package.swift#L14)。

| 独立 product | target 直接依赖 | 听页是否直接引入 / 用途 |
| --- | --- | --- |
| ReadiumShared | ReadiumInternal（内部 target）、SwiftSoup、Zip、ReadiumFuzi（Fuzi 包）、ReadiumZIPFoundation（ZIPFoundation 包） | **是**；Publication/Locator/URL/AssetRetriever、资源读取、共享类型 |
| ReadiumStreamer | CryptoSwift、ReadiumShared、ReadiumFuzi | **是**；PublicationOpener、EPUBParser，解析源包或派生包 |
| ReadiumNavigator | ReadiumInternal、ReadiumShared、DifferenceKit、SwiftSoup | **是**；EPUBNavigatorViewController、EPUBPreferences、选区/Decoration、WebView 与 Readium CSS 资源 |
| ReadiumOPDS | ReadiumShared、ReadiumFuzi | 否；现有 Sources.swift 的 OPDS 保留 |
| ReadiumLCP | CryptoSwift、ReadiumInternal、ReadiumShared、ReadiumZIPFoundation | 否；本轮不新增 DRM/LCP 支持 |
| ReadiumAdapterGCDWebServer | ReadiumGCDWebServer（GCDWebServer 包）、ReadiumShared | **否**；它是独立 HTTPServer 适配 product，但当前 EPUB Navigator 不需要 |
| ReadiumAdapterLCPSQLite | SQLite（SQLite.swift 包）、ReadiumLCP | 否；用于 LCP 存储适配 |

`ReadiumInternal` 和 `TestPublications` 都不是独立导出 product，不往 Xcode 的 product 列表里加。Shared 链接 CoreServices/UIKit 并处理 Resources；Streamer 拷贝 Assets；Navigator 拷贝 EPUB/Assets 并处理 Resources（[Package.swift:36–104](https://github.com/readium/swift-toolkit/blob/3.11.1/Package.swift#L36)）。它们的资源 bundle 是运行时必需项。

包级外部依赖约束（`from` 表示最低兼容版本，实际版本由解析器/锁决定）：CryptoSwift ≥1.10.0、marmelroy/Zip ≥2.1.2、DifferenceKit ≥1.3.0、readium/Fuzi ≥4.0.0、readium/GCDWebServer ≥4.0.0、readium/ZIPFoundation ≥3.0.1、SwiftSoup ≥2.13.5、SQLite.swift ≥0.16.0、swift-docc-plugin ≥1.5.0（[Package.swift:25–35](https://github.com/readium/swift-toolkit/blob/3.11.1/Package.swift#L25)）。不选择某个 product 不代表它所在包级依赖一定不会被 SPM 获取/解析，但不应给 app 链接不需要的 LCP/OPDS/HTTP product。

### 8.3 当前版本的真实打开与渲染 API

不要照旧教程写 `Streamer().open` 或强制运行本地 HTTP 服务器。当前流程为 `AssetRetriever.retrieve(FileURL)` → `PublicationOpener(parser: EPUBParser()).open(asset:allowUserInteraction:)` → 检查 Publication 未受限/格式为 EPUB → `EPUBNavigatorViewController(publication:initialLocation:config:)`。Shared 负责取文件，Streamer 负责结构解析，Navigator 负责显示；只配置 EPUBParser 即可，不需要为了默认 parser 的 PDF factory 把听页 PDF 路由迁走。依据：[Open Publication 指南](https://github.com/readium/swift-toolkit/blob/3.11.1/docs/Guides/Open%20Publication.md#L1)、[EPUBParser.swift:31–35](https://github.com/readium/swift-toolkit/blob/3.11.1/Sources/Streamer/Parser/EPUB/EPUBParser.swift#L31)、[PublicationOpener.swift](https://github.com/readium/swift-toolkit/blob/3.11.1/Sources/Streamer/PublicationOpener.swift#L18)。

**HTTP 适配器的取舍有源码依据：** [EPUBNavigatorViewController.swift:278–324](https://github.com/readium/swift-toolkit/blob/3.11.1/Sources/Navigator/EPUB/EPUBNavigatorViewController.swift#L278) 的新初始化没有 httpServer；旧带 httpServer 重载标记 deprecated，说明 HTTP server 不再需要。内部 [EPUBNavigatorViewModel.swift:46–78](https://github.com/readium/swift-toolkit/blob/3.11.1/Sources/Navigator/EPUB/EPUBNavigatorViewModel.swift#L46) 创建 `WebViewServer(scheme:"readium")`，分别供应静态资源和 publication 资源。故 EPUB 的 localhost 端口、ATS 例外、本地网络权限不应因照搬旧接法而新增；现有 WiFi 传书服务器继续独立工作。

划线和跟读用 [Decoration API](https://github.com/readium/swift-toolkit/blob/3.11.1/docs/Guides/Navigator/Decorations.md)：内置 highlight/underline，wavy 注册自定义 HTMLDecorationTemplate；用不同 group 分隔用户标注、TTS、搜索命中，不能每次跟读清掉用户划线。偏好通过 Configurable/submitPreferences 更新，字体与样式走版本化官方 API，不移植旧多栏脚本覆盖 Navigator。

## 后续单元 1–4：文件级施工清单与验收

以下是按顺序可交付的四个单元。每个单元在独立提交中更新实际验收记录，失败不得宣称完成。本单元没有执行这些修改。

### 单元 1：依赖、Publication 数据层与存量重建

**改文件：** `Tingye.xcodeproj/project.pbxproj`、`Tingye.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`、`create-project.rb`、`Tingye/BookImporter.swift`（Imported 携 source staging 信息）、`Tingye/Models.swift`（可选 source 描述/映射）、`Tingye/Services.swift`（LibraryDisk publication 路径、事务读写/删除）、`Tingye/AppModel.swift`（import/add/repair 生命周期、同 ID 替换与 generation 检查）、`TingyeTests/NativeCoreTests.swift`（ZIP 模块适配）。原生 EPUB 导入器可暂用于生成兼容快照，最终切换在单元 4。

**新增文件：** `Tingye/Readium/ReadiumService.swift`（共享 AssetRetriever/PublicationOpener，仅 EPUBParser）、`PublicationStore.swift`（source/cache/staging）、`LegacyEPUBBuilder.swift`（第 2 问算法）、`PublicationMap.swift`（原章→href、revision/hash）；`TingyeTests/ReadiumPublicationTests.swift`，`TingyeTests/Fixtures/readium/` 重建夹具；`Tingye/Resources/Readium-LICENSE.txt` 及所选依赖许可。

**pbxproj：** 增 exact 3.11.1 XCRemoteSwiftPackageReference；增 Shared/Streamer/Navigator 的 XCSwiftPackageProductDependency、app packageProductDependencies 和 Frameworks 的 PBXBuildFile；归一原 ZIPFoundation 为 Readium fork/product；新增 Readium Group、每个文件 FileReference/BuildFile/Sources；测试源码入 TingyeTests，夹具/许可入 Resources；测试直接 import 的包按需补测试 target product。不加 GCDWebServer adapter、OPDS、LCP。生成器同步依赖与递归源码引用，避免重建时丢文件。

**验收：** Mac/CI 执行 `xcodebuild -resolvePackageDependencies -project Tingye.xcodeproj -scheme Tingye`，检查 package identity 和锁文件；Release unsigned archive 成功，检查 Readium CSS/JS/字体资源 bundle；原始 EPUB 和旧 JSON 重建 EPUB 均能被 Readium 解析并得到正确 readingOrder/TOC/cover；重建夹具跑 EPUBCheck；覆盖 body 残壳、无 HTML、中文/重复 path、data URI、缺资源、封面、图片章、坏包、取消和空间不足；缓存删除后可再生；同 ID 替换/修书不误用旧原包；现有 EPUB/DOCX/漫画/备份测试通过。当前已有 fixture 回归位置 `TingyeTests/NativeCoreTests.swift:788–797,855–860,1540–1548`。

### 单元 2：EPUB Navigator 路由、纸面偏好与阅读 UI

**改文件：** `Tingye/TingyeApp.swift`（统一 Router）、`Tingye/ReaderView.swift`（把公用目录/偏好/控件的必要接口抽出，保留其他格式）、`Tingye/Theme.swift`（纸色实际解析共用函数，修正常亮配色口径）、`Tingye/Typography.swift`（字体文件供应/回退）；`Tingye/Resources/Localizable.xcstrings`（新增状态文案）。

**新增文件：** `Tingye/Readium/ReaderRouter.swift`、`ReadiumReaderView.swift`（SwiftUI 容器、工具栏与生命周期）、`EPUBNavigatorHost.swift`（UIViewControllerRepresentable/协调器）、`ReadiumPreferencesBridge.swift`、`ReadiumFontProvider.swift`、`EPUBDisplayTransform.swift`（简繁显示层，附原文映射合同）；`TingyeTests/ReadiumPreferencesTests.swift`。如拆公共 UI，新增 `Tingye/ReaderControls.swift`，避免复制整份 2300 行 ReaderView。

**pbxproj：** 上述 app/test 文件显式加 Group/Sources；如增加 app 自有 CSS 资源，加 Resources；Readium 的 SPM 资源由包自身管理，不复制到 app 源树；不新增网络权限或监听服务。

**验收：** 所有 format=EPUB 从书架/详情/自动续读进入 Navigator，PDF/comic/TXT/MOBI/Markdown 等仍进原引擎；新原包和旧派生包可读、翻章/内部链接/平铺或原层级 TOC 正常；七纸面×日夜、paperAlwaysLight、字号/行距/段距/页边距/缩进/对齐/字距、4 内置字体/自定义字体、缺失字体回退、滚动/分页/横竖屏/宽屏双栏均检查；fixed-layout 与竖排有专门样本；偏好变化保留当前位置。简繁先验证资源转换不改变源文件和文本层，原文 Locator 与显示选区的完整往返与单元 3 TextDOMIndex 联合验收；未通过前阻断最终切换发布，不能靠关闭已保存偏好蒙混。阅读统计接同一 visibility 生命周期、无重复计时；本单元允许先用资源级近似恢复，精确引用由单元 3 完成。

### 单元 3：全库 Locator 迁移、范围标注与所有跳转

**改文件：** `Tingye/Models.swift`（四类引用 Optional Locator/版本/revision、保留旧坐标/锚点）、`Tingye/AppModel.swift`（saveProgress/saveListeningProgress/bookmark、readerJump 改成可带 Locator 的目标、迁移调度；markChapters 只写本机状态，不能误使 publication revision 变化）、`Tingye/Library.swift`（划线 CRUD/合并）、`Tingye/ReaderView.swift` / `ReaderAnnotations.swift`（非 EPUB bridge、公共跳转合同）、`Tingye/LibraryViews.swift`、`NotesUnifiedView.swift`、`DailyQuoteCard.swift`、`BookFinishView.swift`、`PlayerView.swift`（各引用创建/消费）、`Tingye/ICloudBackup.swift`（Optional 字段解码、KVS 双写/合并/去重，恢复失效逻辑）。

**新增文件：** `Tingye/Readium/LocatorBridge.swift`、`TextDOMIndex.swift`（原文/DOM/显示映射）、`LocatorMigration.swift`（按书可恢复事务）、`ReadiumAnnotations.swift`（选区与三组 decorations，自定义 wavy）；`TingyeTests/ReadiumLocatorTests.swift`、`LocatorMigrationTests.swift`，增加旧 141/142 catalog/backup 夹具。

**pbxproj：** app 和 test 新文件分别加入 Sources，夹具加入测试 Resources；桥接只使用 Shared 已有 product，需要直接 import 时补测试 target 引用，不额外增加 Toolkit product。

**验收：** 第 5.3 节逐项合同通过：旧无 anchor/有 anchor 四类引用全覆盖；重复 quote、>120 字、多句划线、emoji/UTF-16、实体/空白、简繁、表格、插图章、脚注/非线性章、spine 增删/重排、同 path 重复、修书/同 ID 替换；恢复原位置、书签/搜索/摘记/今日一句/听书跳阅读都用同一个 bridge；五色和 background/underline/wavy 范围正确，笔记/ID/date 不丢；阅读与听书位置互不覆盖；迁移被打断可再跑，无匹配标注保留并可见；Locator JSON 往返和无效字段隔离；TXT/MOBI/PDF/漫画等写入/恢复 Locator 仍保持原生行为；同一句细粒度更新不被旧 c/p 去重吞掉；旧设备 KVS/备份读取兼容，失败不破坏原 catalog。

### 单元 4：文本层切换、听书/搜索联动、备份与全量回归

**改文件：** `Tingye/BookImporter.swift`（EPUB 结构解析完全交 Readium，保留其他分支）、`Tingye/AppModel.swift`（导入/修书改 async Readium 文本层生产）、`Tingye/SpeechPlayer.swift`（只适配桥接事件/来源，继续 chapter.text+Sentence.split）、`Tingye/ReaderView.swift`（公用 ReaderSearch/Contents 接口及 1337–1340 行单书导出）、`Tingye/LibraryViews.swift`（326–335 行详情单书导出补原包附件；495/607/778 行附近许可入口及 FontLicenseView 扩展为组件+字体许可页）、`Tingye/ICloudBackup.swift`（source 附件、映射/Locator、导入/还原/删除快照一致性）、`Tingye/Models.swift`（BackupPacket 可选 source 附件）、`Tingye/Services.swift`（source 文件/JSON/catalog 一致提交/删除）、`Tingye/StorageView.swift`（source 算书库、派生包算缓存、活跃文件保活）、`scripts/build-unsigned-ipa.sh`（仅在资源保留/字体回退检查确有必要时调整）、`.github/workflows/tests.yml`（需要的定向用例）、`TingyeUITests/DesignFlowTests.swift`（EPUB 标识与交互）。

**新增文件：** `Tingye/Readium/EPUBTextSnapshotBuilder.swift`（从 Readium readingOrder 生成兼容 Book 快照和映射）、`ReadiumSpeechBridge.swift`（句/字跟读定位与显式跟随，分组 Decoration）、`TingyeTests/ReadiumIntegrationTests.swift`、`docs/readium/ACCEPTANCE.md`（实际设备/样本/构建与损失记录）。如把公共 Search/Contents 拆文件，工程同步加入。

**pbxproj：** 新文件 Sources 与测试 Resources；更新许可证资源，依赖锁保持单元 1 选定范围；不删其他引擎所需源码/字体。版本/构建号在实际发布单元统一决定，本方案不预占 143。

**验收：** 新 EPUB 导入只由 Readium 解释结构，文本快照和原包均可恢复；存量无原包可打开并保持听书/检索结果及旧进度；听书从当前页/选区开始、章句 seek、后台播放、跟读开关、停止/恢复、系统/云语音、逐字显示均可用，不反向覆盖阅读位置；搜索重复命中点击正确，统计前台/后台互斥且书架百分比不突变；整库和单书导出→删除本机→新库导入均保留 source 和精确 Locator，旧 JSON 无 source 仍可用；同 ID 旧备份覆盖新原包时不能沿用旧文件；iCloud 快照移除书籍能删除 source 附件；清理缓存后 source 未丢，活跃阅读不黑屏；大书内存/首开/二次打开时间有记录；离线、重启、低存储/异常退出能恢复。执行现有 TingyeTests + 新测试、EPUB 定向 UI、unsigned Release archive；现有过期 UI 用例仍需单独辨认，不能把 continue-on-error 当通过（`.github/workflows/tests.yml:13–18`）。最后检查所有 EPUB 路由已脱离旧原生排版，其余格式原生回归通过，再允许发布。

## 风险清单（按严重度）

| 严重度 | 风险与证据/原因 | 缓解与完成门槛 |
| --- | --- | --- |
| P0 | 旧数据或迁移失败被新默认位置覆盖；原包/JSON/catalog 三份不一致 | 按书快照、staging/原子发布、revision 校验、初始化恢复屏障；失败不回写；替换/还原/删除和取消故障注入 |
| P0 | 章句不等于 Readium position；新旧 spine/DOM 不同，短 quote 重复，长划线终点易丢 | href 映射+原文/DOM 索引+全文范围；4 类引用双存；分级解析状态，未解析标注保留；全局跨章消歧，不能只依赖现有本章 Locator.resolve |
| P0 | 只保留本机 source 路径，备份恢复丢原包或错误沿用旧同 ID 原包 | source 附件与 digest 纳入整库/单书备份，恢复重新绑定并使旧 source/cache 失效；新库往返验收 |
| P1 | zipfoundation 包 identity/版本冲突，或归一解压库破坏 DOCX/漫画 | 单元 1 先解析、归一 Readium fork、适配 SafeArchive/测试，跑现有 ZIP 格式回归；锁文件实测 |
| P1 | 存量 HTML/CSS/图片不完整，重建 EPUB 不合法或出现损失 | DOM→XML 规范化、资源白名单与失效依赖处理、text 降级、EPUBCheck+Readium 打开；无法恢复的字体/TOC/媒体如实记录 |
| P1 | 原包 HTML 与旧抽取 text 口径不同（标题、ruby、空白、脚注），听书/搜索跳转漂移 | 保留旧 text 快照，建立双向规范化映射及 DOM range；旧包不因升级而重算 text；有差异的样本加入基准 |
| P1 | 宣纸/常亮/夜间强制原书 CSS、字体和简繁导致显示/Locator 不一致 | 实际日夜色值解析、publisherStyles 策略、字体声明、显示资源转换与原文映射；7×2 视觉和定位回归，fixed/竖排单独测 |
| P1 | 原 JSON base64 图片+原包双存，以及备份附件让大书内存/磁盘增长 | 后台逐资源处理、图片按需解码、source 不重复写 Book base64、附件逐书处理并测峰值；如超预算再设计分文件备份格式，不能默默丢附件 |
| P1 | WebView 出版物内容与 Toolkit 必需脚本混淆、远程资源意外访问 | 保留 Toolkit 脚本，审计版本化 Navigator 内容加载/资源策略；在 app 可控资源转换/导航层禁出版物脚本与隐式网络加载，测脚本/外链/远程 CSS 图片/路径穿越样本；不照搬旧 CSP 禁掉 Readium 自有 JS |
| P2 | 生命周期切换双计时、后台音频拉走正文、保活缓存被清理 | 沿用同一个 recordUsageTick，阅读/听书位置独立；显式跟随才跳转，原会话保活文件；复用现有 usage/listening 测试 |
| P2 | fade/blur 动画无直接对应、eink/双页/fixed 行为不同 | 用 Navigator 支持能力分支；保留用户值；退化方案需拍板并记录，不承诺四种动画原样迁移 |
| P2 | CI 冷解析慢/网络失败、资源 bundle 漏入 IPA、slim 字体被删 | exact 3.11.1+锁文件、显式 resolve、资源/缺字体断言；独立测试 unsigned archive，不用发布 workflow 代替测试 |
| P2 | KVS 新 Locator 更新被 c/p 去重忽略，旧端回传丢精度或 payload 过大 | revision+Locator 感知去重，大小限制、单调时钟、c/p/t 兼容项；用旧端模拟数据测试；保留旧坐标和锚点 |

## 尚需验证与需要人拍板的边界

**不阻塞本方案落地、交给实施验收的未知项：** 真实旧库缺字段比例、各类清洗 HTML 的可修复率、旧 text↔原包 DOM 对齐成功率、readium/ZIPFoundation 的实际解析结果与 API 差异、大书首开和备份峰值、TTC 字体在 WebView 的可用性、fixed-layout/竖排上排版偏好的有效集合。本环境是 Linux，未执行 xcodebuild、SPM resolve、Readium 渲染或 EPUBCheck；没有把静态推断当实测通过。

**需要产品拍板的唯一体验差异：** 已保存 fade/blur 翻页动画若 Navigator 无对应能力，是否允许 EPUB 使用 Navigator 标准翻页（保留旧配置供其他格式），还是必须追加自定义转场。建议允许标准翻页；无论哪种都不改动原用户偏好值。该决策不影响单元 1 和定位/备份设计，可在单元 2 视觉验收时确认。

存量缺失资源只能降级、想恢复原版需用户重新提供原包，这是数据事实，不是尚未选择的技术路线。默认接受有记录的派生书恢复；不能为每本旧书要求重新导入才能继续阅读。字体/简繁、四类引用和备份完整性均已列为后续验收要求，不能以“待拍板”为由省略。

## 本单元自检

- 八问均已按现状/设计区分，提供仓库文件:行号或版本化官方来源；Readium 版本经过联网 releases 与 tag Package.swift 核实。
- 未改任何 Swift、工程、workflow、锁文件、构建号；唯一新增交付为 `docs/readium/PLAN.md`。
- 提交前检查 Markdown、引用行号可达、diff --check 与 git diff 文件清单；只提交本文件，不 push，不触发发布。
