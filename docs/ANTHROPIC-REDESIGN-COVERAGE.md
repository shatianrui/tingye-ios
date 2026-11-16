# Anthropic-inspired 全界面重设计覆盖清单

Phase 2 本地实施；更新日期：2026-11-17 Asia/Shanghai。**145 项 implemented-static-only，2 项按明确范围保留；全部 iOS 视觉/运行验收 pending。** 本阶段未编译、未构建、未发布。

基线：`readium-engine@18481af8008b27266af661b03bf16cf5b10e07a0`；新分支 `redesign/anthropic-readium-20261117`。

这里的“实际界面”指从当前 Swift 源码、导航、sheet、popover、菜单与状态分支核实的表面，不是旧 Design HTML 原型。Linux 没有 Xcode/模拟器，尚未实际运行、截图或完成视觉验收。系统拥有的选择器/分享/权限弹窗只调整应用自有入口、呈现与反馈，不承诺替换系统 UI。原始源文件定位按基线符号检索，后续行号会变。

## 导航事实与范围

- 唯一应用根：`StudyRootView` → `ShelfView()`；书房首页内容在书库根内。`StudyRoute.me` → `StatsView(ji: true)`；我的 → 独立统计、统一摘记、设置目录。
- `SettingsDestination` 有 13 个实际 enum 目标：reading、fonts、voice、appearance、backup、notes、privacy、licenses、profile、txtRules、general、storage、menu。许可与隐私经隐私与关于深入访问。
- 阅读器 fullScreenCover → `RoutedReaderView`，3 个实际路由分支：comic → `ComicReaderView`；可解码 PDF → `ReaderView`；EPUB → `ReadiumReaderView`；其他文本格式 → `ReaderView`。判断顺序不能改。
- 两个本机导入主宿主：ShelfView 与 SettingsDirectoryView；ImportHub 关闭后消费请求。结果页另有 push/sheet 的重选入口。书籍详情另有修书选择器，备份另有恢复选择器，字体另有字体选择器。
- 来源浏览：ImportHub → SourcesView → WiFi、WebDAV、OPDS、SMB；递归远程文件夹和 OPDS 分页属于实际深层流程。不存在独立“发现 tab”。
- Readium 目前只有其真实的目录/书签/摘记/搜索/排版/听书与选区路径；原生 reader 的专注、读完收尾、更多与自动翻页不是 EPUB 已有能力。此差异明确保留，不将画出的页面冒称为已连通功能。

## 新设计语言及内容保护

全新独立设计，Anthropic-inspired，非官方关联。暖象牙纸面、炭黑文字、克制陶土强调，以中文可读性、原生导航、细层级和舒适留白组织信息。UI 候选日间基底 `#F7F4ED`、主文 `#292724`、次文 `#69635B`、强调 `#A54D35`、线 `#DAD3C8`；夜间候选基底 `#201F1C`、主文 `#F1EADF`、强调 `#E9A18A`。这些只是待验证的应用 UI 候选，不替换 ReaderPaper/Readium 内容配色与偏好映射，也不宣称对比已通过。

书名/引文可用当前已授权宋体，操作和正文说明用可缩放系统中文；标题靠字号、字重、段落和留白建立层级。新界面应重组页首、书目、工具组、表单、状态和底部动作，不以全局换色代替各屏设计。当前主题已有部分暖色，仍需要下表逐项结构调整。沿用并适配现有向量图标系统，不移植/重命名 v30 规范、页面、图标或资源。

阅读正文保护：原书 EPUB CSS、布局、Navigator 视口、固定版式、图片、字体供应、spine/link、Locator、文字快照、简繁显示映射、进度、迁移、备份源包、依赖与测试全部保留。UI 重做限自有 chrome/工具/设置容器；不得通过共享 Theme 意外改变正文参数、默认值或测试期待。PDF 原页与漫画原图同样保留。所有现有入口、测试与辅助功能标识保留；发现无法满足的冲突应单独记录，不能删功能或放宽测试消除。

## 覆盖计数

共 **147 个覆盖单元**；48 个应用 Swift 源文件，17 个位于 `Tingye/Readium/`。静态检索得 95 个 View/UIViewRepresentable/UIViewControllerRepresentable/ViewModifier 结构声明，包含共享组件和 modifier，不能当成 95 个独立路由。

- 入口、全局与书房：10 项（A001–A010）。
- 书库、整理与详情：23 项（A011–A033）。
- 导入、发现、远程与 WiFi：24 项（A034–A057）。
- 阅读器：真实格式路由与控制：32 项（A058–A089）。
- 听书、声音与输出：16 项（A090–A105）。
- 统计、摘句、专注与读完：15 项（A106–A120）。
- 设置、数据与深层流程：20 项（A121–A140）。
- 兼容表面、系统界面与全局适配：7 项（A141–A147）。

每行是一个可审查的页面、子流程、模式或状态覆盖单元，不把弹窗和状态冒计为独立整屏。跨文件共享组件可服务多行。implemented-static-only 只表示源码接入与静态自审；iOS 视觉/运行仍未验收。preserved-by-scope 表示明确要求保持的资产/遗留表面，不冒充重新实现。


## 入口、全局与书房

| ID | 实际表面 | 源文件 | 现有路径/状态证据 | 计划的实质重设计 | 状态 |
| --- | --- | --- | --- | --- | --- |
| A001 | StudyRootView 根导航与启动续读 | `Tingye/TingyeApp.swift` | 书库根、我的 push、上次非漫画书自动 fullScreenCover；无旧 tab 首页 | 重排页首、返回层级与阅读入口，使用留白和编辑式标题，保留自动打开与阅读优先级。 | implemented-static-only：新页首、PaperPanel、书目/详情EditorialRow及原生整理/分组容器已集成；所有原生确认入口保留，iOS待验收 |
| A002 | 根层阅读器与听书呈现 | `Tingye/TingyeApp.swift` | selectedBook 全屏、showingPlayer sheet、restore 禁用 | 统一页眉、关闭动作、安全区和模态容器；保持 RoutedReaderView 与恢复事务边界。 | implemented-static-only：新页首、PaperPanel、书目/详情EditorialRow及原生整理/分组容器已集成；所有原生确认入口保留，iOS待验收 |
| A003 | 全局忙碌、提示与失败警告 | `Tingye/TingyeApp.swift` | FeedbackOverlay busy/activity、notice、逐项结果按钮、操作未完成 alert | 将进度、结果摘要和恢复动作组织为明确状态条，长错误可读，避免无反馈。 | implemented-static-only：新页首、PaperPanel、书目/详情EditorialRow及原生整理/分组容器已集成；所有原生确认入口保留，iOS待验收 |
| A004 | 应用锁与身份验证失败后重试 | `Tingye/Library.swift` | AppLockGate、后台重锁、系统生物识别 | 设计安静的纸面锁屏、身份说明和大解锁按钮，保持系统身份验证。 | implemented-static-only：新页首、PaperPanel、书目/详情EditorialRow及原生整理/分组容器已集成；所有原生确认入口保留，iOS待验收 |
| A005 | 书房正在读卡与开始专注入口 | `Tingye/ShelfView.swift` | heroCard、最近阅读、开始专注记录 bookID | 重新组织封面、书名、进度和继续读主动作，听书与专注为清楚的次动作。 | implemented-static-only：新页首、PaperPanel、书目/详情EditorialRow及原生整理/分组容器已集成；所有原生确认入口保留，iOS待验收 |
| A006 | 书房摘句与藏书概览 | `Tingye/ShelfView.swift` | todayQuote、今日日期/时长、latestHighlight | 采用引用正文、出处、阅读信息的独立层级，减少装饰性卡片堆叠。 | implemented-static-only：新页首、PaperPanel、书目/详情EditorialRow及原生整理/分组容器已集成；所有原生确认入口保留，iOS待验收 |
| A007 | 书房无书/无正在读状态 | `Tingye/ShelfView.swift` | emptyState、heroEntry 缺失、首次导入 | 以短说明和添书主动作建立首用路径，区分无书与筛选后无结果。 | implemented-static-only：新页首、PaperPanel、书目/详情EditorialRow及原生整理/分组容器已集成；所有原生确认入口保留，iOS待验收 |
| A008 | 发现/书源现有入口 | `Tingye/ShelfView.swift` | 页首加号、添书按钮、sources review route | 让导入入口可发现；基线没有独立发现 tab，不虚构旧原型页面。 | implemented-static-only：新页首、PaperPanel、书目/详情EditorialRow及原生整理/分组容器已集成；所有原生确认入口保留，iOS待验收 |
| A009 | 系统分享、文件选择与音频输出 | `Tingye/ShelfView.swift`；`Tingye/TingyeApp.swift` | ShareSheet、系统文件宿主、AirPlayButton | 统一自有调用按钮与模态前后反馈，系统控制保留原生可用性与 iPad 锚点。 | implemented-static-only：新页首、PaperPanel、书目/详情EditorialRow及原生整理/分组容器已集成；所有原生确认入口保留，iOS待验收 |
| A010 | 应用图标/启动及资源语言 | `Tingye/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json`；`Tingye/Info.plist`；`Tingye/Resources/Localizable.xcstrings` | 既有日间/深色/tinted 图标、UILaunchScreen、四语本地化 | 独立审视新主题的图标与启动背景一致性；更新自有 UI 文案本地化，不使用 v30 资产。 | preserved-by-scope：按本阶段明确指令不生成营销资产，保留现有图标/启动资产；本地化核对待自审 |

## 书库、整理与详情

| ID | 实际表面 | 源文件 | 现有路径/状态证据 | 计划的实质重设计 | 状态 |
| --- | --- | --- | --- | --- | --- |
| A011 | 书目列表 | `Tingye/ShelfView.swift` | bookList、书籍/漫画 kind、最近阅读信息 | 重做书目行的封面比例、中文长标题和进度层级，以细分隔和稳定对齐形成书目节奏。 | implemented-static-only：新页首、PaperPanel、书目/详情EditorialRow及原生整理/分组容器已集成；所有原生确认入口保留，iOS待验收 |
| A012 | 封面网格 | `Tingye/ShelfView.swift` | bookGrid、真实封面、占位封面 | 重新规划封面间距、书名和状态区域，真实封面不重新着色。 | implemented-static-only：新页首、PaperPanel、书目/详情EditorialRow及原生整理/分组容器已集成；所有原生确认入口保留，iOS待验收 |
| A013 | 分组列表/网格与递归分组 | `Tingye/ShelfView.swift` | folders、ShelfView(group:)、showingGroups | 明确当前分组和返回路径，文件夹与书籍采用不同信息层级。 | implemented-static-only：新页首、PaperPanel、书目/详情EditorialRow及原生整理/分组容器已集成；所有原生确认入口保留，iOS待验收 |
| A014 | 筛选菜单与清除筛选 | `Tingye/ShelfView.swift` | 阅读状态全部/在读/待读/读完，分类 | 重做触发器、当前条件摘要和重置动作，选择不只靠颜色。 | implemented-static-only：新页首、PaperPanel、书目/详情EditorialRow及原生整理/分组容器已集成；所有原生确认入口保留，iOS待验收 |
| A015 | 排序与手动排序 | `Tingye/ShelfView.swift` | 最近阅读/书名/作者/添加时间/手动 | 展示当前排序并保持与筛选分离；整理拖动及可访问替代动作保留。 | implemented-static-only：新页首、PaperPanel、书目/详情EditorialRow及原生整理/分组容器已集成；所有原生确认入口保留，iOS待验收 |
| A016 | 列表/网格切换与辅助字号回退 | `Tingye/ShelfView.swift` | layoutMenu、useList | 清晰标识当前视图；大字号自动列表且不改用户偏好。 | implemented-static-only：新页首、PaperPanel、书目/详情EditorialRow及原生整理/分组容器已集成；所有原生确认入口保留，iOS待验收 |
| A017 | 书库搜索、取消与历史记录 | `Tingye/ShelfView.swift` | shelfSearchBar、recentSearches、跨组搜索 | 重排搜索字段、键盘关闭、历史清空和结果摘要，长中文输入不挤压取消按钮。 | implemented-static-only：新页首、PaperPanel、书目/详情EditorialRow及原生整理/分组容器已集成；所有原生确认入口保留，iOS待验收 |
| A018 | 搜索空结果、筛选空结果与漫画空态 | `Tingye/ShelfView.swift` | emptyState 的不同分支 | 分别提供改关键词、清除条件、导入漫画等针对性恢复动作。 | implemented-static-only：新页首、PaperPanel、书目/详情EditorialRow及原生整理/分组容器已集成；所有原生确认入口保留，iOS待验收 |
| A019 | 多选整理与选择范围 | `Tingye/ShelfView.swift` | editing、selection、scopeNotice、editBar | 建立明确整理模式和选择数量；移动、隐藏、删除的主次与风险分离。 | implemented-static-only：新页首、PaperPanel、书目/详情EditorialRow及原生整理/分组容器已集成；所有原生确认入口保留，iOS待验收 |
| A020 | 书籍上下文菜单/独立详情入口 | `Tingye/ShelfView.swift` | menu(entry)、contextMenu、detailButton | 统一继续读、听书、详情、隐藏和管理的动作分组，保留独立详情触点。 | implemented-static-only：新页首、PaperPanel、书目/详情EditorialRow及原生整理/分组容器已集成；所有原生确认入口保留，iOS待验收 |
| A021 | 移动/新建分组 sheet | `Tingye/ShelfView.swift` | GroupPickerView、parentGroup、未分组 | 重做路径、目标、名称输入和确认区域；键盘与大字号下动作可达。 | implemented-static-only：新页首、PaperPanel、书目/详情EditorialRow及原生整理/分组容器已集成；所有原生确认入口保留，iOS待验收 |
| A022 | 分组重命名与解散确认 | `Tingye/ShelfView.swift` | rename alert、group removal confirmation | 使用清晰命名输入与保留书籍说明，提供原生取消和破坏性动作。 | implemented-static-only：新页首、PaperPanel、书目/详情EditorialRow及原生整理/分组容器已集成；所有原生确认入口保留，iOS待验收 |
| A023 | 书库批量删除确认 | `Tingye/ShelfView.swift` | removalSelection、sample 不可删除 | 突出真实数量与仅本机范围；选择状态返回后稳定保留。 | implemented-static-only：新页首、PaperPanel、书目/详情EditorialRow及原生整理/分组容器已集成；所有原生确认入口保留，iOS待验收 |
| A024 | 隐藏书籍展开/重新隐藏 | `Tingye/ShelfView.swift`；`Tingye/LibraryViews.swift` | libraryOptions、unlockHidden、ProfileView | 统一隐私状态提示与验证入口，维持后台重新隐藏。 | implemented-static-only：新页首、PaperPanel、书目/详情EditorialRow及原生整理/分组容器已集成；所有原生确认入口保留，iOS待验收 |
| A025 | 书籍详情主页面与缺失书籍 | `Tingye/LibraryViews.swift` | BookDetailView、hero、entry nil | 重做封面与书名排版、元数据与阅读进度区；缺失书籍提供明确返回。 | implemented-static-only：新页首、PaperPanel、书目/详情EditorialRow及原生整理/分组容器已集成；所有原生确认入口保留，iOS待验收 |
| A026 | 详情本机阅读/听书与云端恢复 | `Tingye/LibraryViews.swift` | actionButtons、local false → ICloudBackupView | 本机继续读突出为主动作，云端项说明需先恢复，听书保留次级入口。 | implemented-static-only：新页首、PaperPanel、书目/详情EditorialRow及原生整理/分组容器已集成；所有原生确认入口保留，iOS待验收 |
| A027 | 简介摘要与全文 sheet | `Tingye/LibraryViews.swift` | briefSection、showingIntro、无简介 | 重做摘要段落、阅读全文入口与出处，全文页具有舒适阅读宽度和关闭动作。 | implemented-static-only：修书保留原选择器与格式/ID/原包事务，AppModel改用协调快照读取；详情操作接入EditorialRow；iOS待验收 |
| A028 | 详情目录预览与加载 | `Tingye/LibraryViews.swift` | loadReadingDetails、chapterTitles、loadingPreview | 重新组织读到这里、附近章节与全部目录，显示真实加载而非空白。 | implemented-static-only：新页首、PaperPanel、书目/详情EditorialRow及原生整理/分组容器已集成；所有原生确认入口保留，iOS待验收 |
| A029 | 章节管理、搜索和多选已读标记 | `Tingye/LibraryViews.swift` | ChapterManagerView、marking、已读/未读、听此章 | 以章节序号、标题、状态构建目录行，选择模式底部操作清晰；保留阅读/声音分离。 | implemented-static-only：新页首、PaperPanel、书目/详情EditorialRow及原生整理/分组容器已集成；所有原生确认入口保留，iOS待验收 |
| A030 | 详情书摘与阅读书签子页 | `Tingye/LibraryViews.swift` | NotesList push、阅读书签 List、空书签 | 重做分区标题和引文行、当前定位摘要、空态指引；跳转仍走 LocatorTarget。 | implemented-static-only：新页首、PaperPanel、书目/详情EditorialRow及原生整理/分组容器已集成；所有原生确认入口保留，iOS待验收 |
| A031 | 详情更多、导出、TXT 重分章 | `Tingye/LibraryViews.swift` | manageSection、exportBook、resplit | 清晰区分阅读资料、文件操作与删除；导出包含 Readium 原包附件。 | implemented-static-only：新页首、PaperPanel、书目/详情EditorialRow及原生整理/分组容器已集成；所有原生确认入口保留，iOS待验收 |
| A032 | 修复原书选择与结果 | `Tingye/LibraryViews.swift`；`Tingye/AppModel.swift` | repair fileImporter、格式校验、source 替换 | 在选前解释修复用途，选后显示阶段与失败恢复；保留 ID、摘记和原包事务。 | implemented-static-only：新页首、PaperPanel、书目/详情EditorialRow及原生整理/分组容器已集成；所有原生确认入口保留，iOS待验收 |
| A033 | 详情移除本机/本机与 iCloud 确认 | `Tingye/LibraryViews.swift` | removal confirmation | 明确两个删除范围、不可恢复说明和取消，保持实际删除语义。 | implemented-static-only：新页首、PaperPanel、书目/详情EditorialRow及原生整理/分组容器已集成；所有原生确认入口保留，iOS待验收 |

## 导入、发现、远程与 WiFi

| ID | 实际表面 | 源文件 | 现有路径/状态证据 | 计划的实质重设计 | 状态 |
| --- | --- | --- | --- | --- | --- |
| A034 | ImportHub 根 sheet | `Tingye/Sources.swift` | ImportHubView NavigationStack → SourcesView | 以导入方式而非重复大卡组织入口，突出本机选择与远程/电脑传书的差别。 | implemented-static-only：ImportHub保留NavigationStack与来源入口；新EditorialIntro与单/批分流，根请求控制modal关闭；iOS待验收 |
| A035 | 本机文件选择与根宿主交接 | `Tingye/ShelfView.swift`；`Tingye/StatsView.swift`；`Tingye/AppModel.swift` | bookImporter、request/consume、两个 onDismiss | 重做选择前说明和即时状态反馈；实施时评估复制单选与独立批量，保留单一根宿主交接。 | implemented-static-only：LocalBookPicker复制单选/显式批量；request-consume保留并由StudyRootView唯一宿主和onDismiss门槛接管；iOS待验收 |
| A036 | Open In/分享至听页入口 | `Tingye/TingyeApp.swift`；`Tingye/AppModel.swift` | onOpenURL → beginImport | 打开文件后提供可见接收/解析/保存反馈，不能只靠最终弹窗。 | implemented-static-only：onOpenURL保留beginImport；开始时清旧notice，既有根busy与逐项结果可见；iOS待验收 |
| A037 | 逐项导入结果页面 | `Tingye/ShelfView.swift` | ImportResultsView，waiting/importing/imported/failed | 重做总览计数、文件名、阶段、失败原因和明确完成主动作，允许混合成功。 | implemented-static-only：ImportResultsView改用Intro/Notice/PaperPanel，逐项等待/解析/成功/失败与计数完整保留；iOS待验收 |
| A038 | 结果页空态、重选与继续导入 | `Tingye/ShelfView.swift`；`Tingye/TingyeApp.swift` | 结果 sheet、结果 push、FeedbackOverlay 结果 sheet | 统一根层重新选文件链路，重选不复用失效 URL，避免 sheet 内选择器重现吞回调。 | implemented-static-only：删除结果页picker；重选只request+dismiss，所有hub/结果/reader/player关闭token后打开根picker；iOS待验收 |
| A039 | 导入忙碌、取消、空选择与解析错误 | `Tingye/AppModel.swift`；`Tingye/ShelfView.swift`；`Tingye/BookImporter.swift` | busy、empty URLs、失败项、权限/格式/损坏错误 | 显示开始即响应、真实取消与空成功的区别、逐项恢复；错误保留可读全文。 | implemented-static-only：delegate单次交付，nil取消与空成功分开，beginImport即时busy；协调复制/解析错误进入原逐项报告；iOS待验收 |
| A040 | 书源连接目录与无连接状态 | `Tingye/Sources.swift` | SourcesView、WebDAV/OPDS/SMB、最近结果 | 重新布局本地/电脑/服务器方式、连接名称与地址副标题；有无连接状态分别处理。 | implemented-static-only：书源自适应行、连接说明/错误面板、列表层级和WiFi网页步骤/队列新布局；iOS/provider待验收 |
| A041 | WebDAV 新建/编辑 sheet | `Tingye/Sources.swift` | SourceEditor kind webdav | 重做名称、URL、认证和保存验证顺序，长地址和应用密码说明可读。 | implemented-static-only：书源自适应行、连接说明/错误面板、列表层级和WiFi网页步骤/队列新布局；iOS/provider待验收 |
| A042 | OPDS 新建/编辑 sheet | `Tingye/Sources.swift` | SourceEditor kind opds | 书目地址和可选认证分区清晰；保存错误与取消行为明确。 | implemented-static-only：书源自适应行、连接说明/错误面板、列表层级和WiFi网页步骤/队列新布局；iOS/provider待验收 |
| A043 | SMB 新建/编辑 sheet | `Tingye/Sources.swift` | SourceEditor kind smb、访客说明 | 把 NAS 地址、访客/账号说明和共享目录选择分阶段表达。 | implemented-static-only：书源自适应行、连接说明/错误面板、列表层级和WiFi网页步骤/队列新布局；iOS/provider待验收 |
| A044 | 连接管理菜单与移除确认 | `Tingye/Sources.swift` | Menu/contextMenu、removing | 明确仅删除本机连接，保持服务器和已导入书籍，形成一致管理行。 | implemented-static-only：书源自适应行、连接说明/错误面板、列表层级和WiFi网页步骤/队列新布局；iOS/provider待验收 |
| A045 | WebDAV 文件夹递归与搜索 | `Tingye/Sources.swift` | WebDAVBrowser、当前路径、refreshable | 重做文件夹/文件行、大小、可导入状态和路径层级；保留下载管线。 | implemented-static-only：书源自适应行、连接说明/错误面板、列表层级和WiFi网页步骤/队列新布局；iOS/provider待验收 |
| A046 | WebDAV 加载、空目录、无匹配与错误 | `Tingye/Sources.swift` | loading、error、重新加载 | 统一连接阶段、带上下文重试与搜索重置，禁用文件依然可辨。 | implemented-static-only：书源自适应行、连接说明/错误面板、列表层级和WiFi网页步骤/队列新布局；iOS/provider待验收 |
| A047 | OPDS 分类、书目与分页 | `Tingye/Sources.swift` | OPDSBrowser navigation/acquisition/next | 封面、作者、格式与获取动作重新分层，分类导航与下载动作可区分。 | implemented-static-only：书源自适应行、连接说明/错误面板、列表层级和WiFi网页步骤/队列新布局；iOS/provider待验收 |
| A048 | OPDS 本地筛选/远程搜索及返回 | `Tingye/Sources.swift` | remoteSearchTemplate、showingSearchResults | 显示搜索范围和返回全部入口，维持请求目标与分页语义。 | implemented-static-only：书源自适应行、连接说明/错误面板、列表层级和WiFi网页步骤/队列新布局；iOS/provider待验收 |
| A049 | OPDS 加载、空内容、无匹配与重试 | `Tingye/Sources.swift` | lastAttemptURL/error、feed empty | 设计请求状态与失败原因；补齐本地过滤后无匹配的可视反馈属于实施项。 | implemented-static-only：书源自适应行、连接说明/错误面板、列表层级和WiFi网页步骤/队列新布局；iOS/provider待验收 |
| A050 | SMB 共享目录列表 | `Tingye/SMBBrowser.swift` | share == nil、shares、无共享 | 采用连接名、共享数和文件夹入口的清楚层级；无共享说明可恢复。 | implemented-static-only：书源自适应行、连接说明/错误面板、列表层级和WiFi网页步骤/队列新布局；iOS/provider待验收 |
| A051 | SMB 递归文件夹/搜索/下载 | `Tingye/SMBBrowser.swift` | 共享 SMBConnection、shownFiles、download | 重做路径、文件大小与导入动作，保持递归会话复用和 unsupported 禁用。 | implemented-static-only：书源自适应行、连接说明/错误面板、列表层级和WiFi网页步骤/队列新布局；iOS/provider待验收 |
| A052 | SMB 加载、认证/网络失败、空目录 | `Tingye/SMBBrowser.swift` | loading、error、重新加载、refreshable | 显示目标与失败恢复动作，保持错误不被空态覆盖。 | implemented-static-only：书源自适应行、连接说明/错误面板、列表层级和WiFi网页步骤/队列新布局；iOS/provider待验收 |
| A053 | WiFi 传书手机页面 | `Tingye/Sources.swift` | WiFiTransferView、启动/地址/复制 | 重做连接步骤、地址阅读与复制确认；令牌不拆分显示，不改变传输权限。 | implemented-static-only：书源自适应行、连接说明/错误面板、列表层级和WiFi网页步骤/队列新布局；iOS/provider待验收 |
| A054 | WiFi 接收列表与结束流程 | `Tingye/Sources.swift` | received、成功/失败、返回书库/结束传书 | 接收数量和逐项结果按时间组织，服务关闭动作与导航动作清楚。 | implemented-static-only：书源自适应行、连接说明/错误面板、列表层级和WiFi网页步骤/队列新布局；iOS/provider待验收 |
| A055 | WiFi 启动失败/权限/无网络/未接收 | `Tingye/Sources.swift` | server.error/address nil、空 received | 为服务启动和可恢复错误提供清晰步骤与重连，保留离页停服。 | implemented-static-only：书源自适应行、连接说明/错误面板、列表层级和WiFi网页步骤/队列新布局；iOS/provider待验收 |
| A056 | WiFi 浏览器上传页面及拖放 | `Tingye/Sources.swift` | WiFiTransferServer.page 内嵌实际 HTML | 重新组织标题、说明、拖放区与发送按钮，使用同一新主题；保留手机窄屏与键盘操作。 | implemented-static-only：书源自适应行、连接说明/错误面板、列表层级和WiFi网页步骤/队列新布局；iOS/provider待验收 |
| A057 | WiFi 浏览器队列/重试/超时/断连 | `Tingye/Sources.swift` | page 中 queue、progress、retry、clear | 区分上传与加入书架阶段，长文件名、进度和失败恢复可读，保留 aria-live。 | implemented-static-only：书源自适应行、连接说明/错误面板、列表层级和WiFi网页步骤/队列新布局；iOS/provider待验收 |

## 阅读器：真实格式路由与控制

| ID | 实际表面 | 源文件 | 现有路径/状态证据 | 计划的实质重设计 | 状态 |
| --- | --- | --- | --- | --- | --- |
| A058 | Readium EPUB 原包/存量派生阅读 | `Tingye/Readium/ReaderRouter.swift`；`Tingye/Readium/ReadiumReaderView.swift`；`Tingye/Readium/EPUBNavigatorHost.swift` | comic 优先、PDF native、EPUB epub；原包或 LegacyEPUBBuilder | 重做自有 chrome 和工具层；保留 Navigator 视口、原书 CSS、布局、spine、字体与全部偏好映射。 | implemented-static-only：阅读自有工具层、目录/搜索等待/摘记/笔记/排版和漫画目录/缺图态已重做；内容渲染与定位保持，iOS待验收 |
| A059 | EPUB 重排、固定版式、翻页/滚动/双栏 | `Tingye/Readium/ReadiumPreferencesBridge.swift`；`Tingye/Readium/ReadiumReaderView.swift` | 固定版式受限偏好；可重排分页/滚动、宽屏双栏 | 为各模式检查控件适配与清晰状态，保留固定版式和纸色/排版参数原语义，不改内容排版。 | implemented-static-only：阅读自有工具层、目录/搜索等待/摘记/笔记/排版和漫画目录/缺图态已重做；内容渲染与定位保持，iOS待验收 |
| A060 | EPUB 加载、打开失败与重试 | `Tingye/Readium/ReadiumReaderView.swift` | session.loading/error、retry、修书指引 | 建立轻量打开进度和错误恢复面板，确保返回始终可达、阅读位置保存。 | implemented-static-only：阅读自有工具层、目录/搜索等待/摘记/笔记/排版和漫画目录/缺图态已重做；内容渲染与定位保持，iOS待验收 |
| A061 | EPUB 顶栏、沉浸与书签 | `Tingye/Readium/ReadiumReaderView.swift` | topBar、chrome、mappedChapter 禁用 | 重做标题和导航按钮的密度与触点；隐藏 chrome 不引起正文移动或页码变化。 | implemented-static-only：阅读自有工具层、目录/搜索等待/摘记/笔记/排版和漫画目录/缺图态已重做；内容渲染与定位保持，iOS待验收 |
| A062 | EPUB 底栏与辅助听书 | `Tingye/Readium/ReadiumReaderView.swift` | 目录、听书、暂停/继续、跟随/回到朗读、设置 | 重做动作分组与播放状态表达，保持 mappedChapter 限制、阅读/声音定位相互独立。 | implemented-static-only：阅读自有工具层、目录/搜索等待/摘记/笔记/排版和漫画目录/缺图态已重做；内容渲染与定位保持，iOS待验收 |
| A063 | EPUB 多层目录与无 TOC 回退 | `Tingye/Readium/ReadiumReaderView.swift` | contentsView、flatten depth、book.chapters fallback | 重做章节层级、缩进与行距；保持 href 和 Link 导航，不按序号猜资源。 | implemented-static-only：阅读自有工具层、目录/搜索等待/摘记/笔记/排版和漫画目录/缺图态已重做；内容渲染与定位保持，iOS待验收 |
| A064 | EPUB 书签/摘记与未定位标注 | `Tingye/Readium/ReadiumReaderView.swift`；`Tingye/ReaderAnnotations.swift` | contents Section、swipe delete、unresolvedAnnotations | 清晰分段呈现与未定位说明，保留所有原文数据和重定位语义。 | implemented-static-only：阅读自有工具层、目录/搜索等待/摘记/笔记/排版和漫画目录/缺图态已重做；内容渲染与定位保持，iOS待验收 |
| A065 | EPUB 书内全文搜索 sheet | `Tingye/Readium/ReadiumReaderView.swift`；`Tingye/ReaderView.swift` | Sheet.search → ContentsView startsSearching、search decorations | 重做搜索入口、匹配摘要与跳转反馈，保留原文范围/Locator 与搜索高亮映射。 | implemented-static-only：阅读自有工具层、目录/搜索等待/摘记/笔记/排版和漫画目录/缺图态已重做；内容渲染与定位保持，iOS待验收 |
| A066 | EPUB 系统选区菜单/标注 sheet/笔记 | `Tingye/Readium/EPUBNavigatorHost.swift`；`Tingye/Readium/ReadiumReaderView.swift`；`Tingye/ReaderAnnotations.swift` | onSelection、onDecoration、Sheet.annotation/note | 统一选区到标注的工具层和编辑布局，不能更改 DOM 选区到原文定位转换。 | implemented-static-only：阅读自有工具层、目录/搜索等待/摘记/笔记/排版和漫画目录/缺图态已重做；内容渲染与定位保持，iOS待验收 |
| A067 | EPUB 排版与字体 sheet | `Tingye/Readium/ReadiumReaderView.swift`；`Tingye/ReaderView.swift` | showsPreview false、标准翻页说明 | 重做偏好分组与模式说明；保留 EPUB 实际采用的偏好及固定版式限制，不改变 ReaderPaper。 | implemented-static-only：阅读自有工具层、目录/搜索等待/摘记/笔记/排版和漫画目录/缺图态已重做；内容渲染与定位保持，iOS待验收 |
| A068 | TXT 与其他原生文字阅读 | `Tingye/ReaderView.swift`；`Tingye/Readium/ReaderRouter.swift` | TXT/HTML/Markdown/DOCX/MOBI/AZW 等 native | 重做章节外栏、控制与状态信息；保留文字分页、滚动、双页、句级定位和既有字体设置。 | implemented-static-only：阅读自有工具层、目录/搜索等待/摘记/笔记/排版和漫画目录/缺图态已重做；内容渲染与定位保持，iOS待验收 |
| A069 | 原生图文、表格与插图页 | `Tingye/ReaderView.swift` | ReaderMediaPage、NativeTextPage、ScrollingText、chapter blocks | 只调整自有边界/控制风格；图文来源、表格图像、分页尺寸与原文数据保持。 | implemented-static-only：阅读自有工具层、目录/搜索等待/摘记/笔记/排版和漫画目录/缺图态已重做；内容渲染与定位保持，iOS待验收 |
| A070 | PDF 原页阅读与缩放 | `Tingye/ReaderView.swift` | document.isPDF、PDFReader/PDFKit | 重做页码和工具层，保留 PDF 页面本色、缩放、视口与页级进度；支持无可朗读文字状态。 | implemented-static-only：阅读自有工具层、目录/搜索等待/摘记/笔记/排版和漫画目录/缺图态已重做；内容渲染与定位保持，iOS待验收 |
| A071 | 原生顶栏/章页状态/沉浸 | `Tingye/ReaderView.swift` | topBar、ReaderStatusLine、bookmark、chrome | 重做状态条与控制栏层级，时钟/电量不抢正文，隐藏与显示不重排内容。 | implemented-static-only：阅读自有工具层、目录/搜索等待/摘记/笔记/排版和漫画目录/缺图态已重做；内容渲染与定位保持，iOS待验收 |
| A072 | 原生章进度滑杆/前后章/双页 | `Tingye/ReaderView.swift` | ChapterScrubber、chapterBar、pageLabel | 重做章标题、百分比和前后章触点；拖动松手提交和 VoiceOver 即时调整保留。 | implemented-static-only：阅读自有工具层、目录/搜索等待/摘记/笔记/排版和漫画目录/缺图态已重做；内容渲染与定位保持，iOS待验收 |
| A073 | 原生更多 popover | `Tingye/ReaderView.swift` | morePanelRows、pendingMoreAction | 编辑式动作分组，支持滚动和最大字号；保持 popover 消失后再打开 sheet，避免抢呈现。 | implemented-static-only：阅读自有工具层、目录/搜索等待/摘记/笔记/排版和漫画目录/缺图态已重做；内容渲染与定位保持，iOS待验收 |
| A074 | 原生自动翻页子面板 | `Tingye/ReaderView.swift` | autoTurnPanelRows、停止浮排、PDF/scroll 排除 | 重做当前间隔、关闭和返回菜单，保留只在适用模式出现。 | implemented-static-only：阅读自有工具层、目录/搜索等待/摘记/笔记/排版和漫画目录/缺图态已重做；内容渲染与定位保持，iOS待验收 |
| A075 | 原生日夜切换与导出备份 | `Tingye/ReaderView.swift` | toggleNightMode、shareBook、ShareSheet | 统一工具按钮与反馈，不覆盖用户纸色或 Readium 包附件。 | implemented-static-only：阅读自有工具层、目录/搜索等待/摘记/笔记/排版和漫画目录/缺图态已重做；内容渲染与定位保持，iOS待验收 |
| A076 | 原生跟读条、返回朗读与结束确认 | `Tingye/ReaderView.swift` | listeningStrip、returnPill、endingListening | 重做跟随/暂停状态与小屏控制布局，保持阅读跳章不 seek 声音。 | implemented-static-only：阅读自有工具层、目录/搜索等待/摘记/笔记/排版和漫画目录/缺图态已重做；内容渲染与定位保持，iOS待验收 |
| A077 | 原生目录章节/书签/笔记/插图模式 | `Tingye/ReaderView.swift` | ContentsView mode 0/1/3/2、IllustrationRow | 重新规划模式导航、章节列表、插图占位和空态，保留不同数据来源与跳转。 | implemented-static-only：阅读自有工具层、目录/搜索等待/摘记/笔记/排版和漫画目录/缺图态已重做；内容渲染与定位保持，iOS待验收 |
| A078 | 共享全文搜索与异步/无结果状态 | `Tingye/ReaderView.swift` | 150ms debounce、hits nil、200 处上限、ReaderSearch | 重做查询、等待、结果计数与片段；补充现有等待空白的视觉反馈，不改 offset 到句/Locator 映射。 | implemented-static-only：阅读自有工具层、目录/搜索等待/摘记/笔记/排版和漫画目录/缺图态已重做；内容渲染与定位保持，iOS待验收 |
| A079 | 共享书签菜单与删除确认 | `Tingye/ReaderView.swift` | bookmarkToRemove、回到此处 | 明确引用、位置与删除按钮，取消保留正文/进度。 | implemented-static-only：阅读自有工具层、目录/搜索等待/摘记/笔记/排版和漫画目录/缺图态已重做；内容渲染与定位保持，iOS待验收 |
| A080 | 原生选段与扩选菜单 | `Tingye/ReaderAnnotations.swift`；`Tingye/ReaderView.swift` | SelectionPanel、扩大选区、标注/笔记/引用 | 重做工具切换与摘要；大字号工具可滚动，EPUB 不支持的扩选仍保持禁用。 | implemented-static-only：阅读自有工具层、目录/搜索等待/摘记/笔记/排版和漫画目录/缺图态已重做；内容渲染与定位保持，iOS待验收 |
| A081 | 标注颜色/背景/下划线/波浪线 | `Tingye/ReaderAnnotations.swift` | markTools、ReaderMark、已有标注编辑/删除 | 颜色名、样式示例和选中符号同时呈现；五色、旧绿兼容和持久化值不变。 | implemented-static-only：阅读自有工具层、目录/搜索等待/摘记/笔记/排版和漫画目录/缺图态已重做；内容渲染与定位保持，iOS待验收 |
| A082 | 笔记编辑器/键盘/保存取消 | `Tingye/ReaderAnnotations.swift` | NoteEditor、TextEditor、focus | 重做引用预览、编辑正文和底部动作，键盘不遮保存，保留原文和笔记分离。 | implemented-static-only：阅读自有工具层、目录/搜索等待/摘记/笔记/排版和漫画目录/缺图态已重做；内容渲染与定位保持，iOS待验收 |
| A083 | 引用复制/分享/从此处听 | `Tingye/ReaderAnnotations.swift` | SelectionPanel quote、ShareLink | 清晰区分复制、系统分享与声音定位；维持原文引用与阅读位置不变。 | implemented-static-only：阅读自有工具层、目录/搜索等待/摘记/笔记/排版和漫画目录/缺图态已重做；内容渲染与定位保持，iOS待验收 |
| A084 | 本书笔记列表、编辑/分享/删除 | `Tingye/ReaderAnnotations.swift` | NotesList、NoteRow、editing sheet、contextMenu | 重做引文、笔记、时间和章名层级；删除确认与未定位原文保留。 | implemented-static-only：阅读自有工具层、目录/搜索等待/摘记/笔记/排版和漫画目录/缺图态已重做；内容渲染与定位保持，iOS待验收 |
| A085 | 漫画左到右/右到左/条漫 | `Tingye/ComicReaderView.swift` | mode ltr/rtl/vertical、TabView/ScrollView | 重做外部工具与阅读模式入口；保留图像、手势、RTL、每书偏好和页码语义。 | implemented-static-only：阅读自有工具层、目录/搜索等待/摘记/笔记/排版和漫画目录/缺图态已重做；内容渲染与定位保持，iOS待验收 |
| A086 | 漫画缩放、图片加载/失败 | `Tingye/ComicReaderView.swift` | ComicPage、ZoomableComicImage、loading image nil | 统一加载占位与缺图状态，保留降采样、双指/双击缩放和全图阅读空间。 | implemented-static-only：阅读自有工具层、目录/搜索等待/摘记/笔记/排版和漫画目录/缺图态已重做；内容渲染与定位保持，iOS待验收 |
| A087 | 漫画顶底工具、页码滑杆与书签 | `Tingye/ComicReaderView.swift` | chrome、pageStep、scrubbing、bookmark | 重新组织书名、进度、前后页和模式选择；确保安全区与边界禁用状态。 | implemented-static-only：阅读自有工具层、目录/搜索等待/摘记/笔记/排版和漫画目录/缺图态已重做；内容渲染与定位保持，iOS待验收 |
| A088 | 漫画页面目录/仅书签/空书签 | `Tingye/ComicReaderView.swift` | pageDirectory sheet、thumbnail rows、onlyBookmarks | 重做缩略图、当前页和书签摘要层级，所有模式仍能跳页。 | implemented-static-only：阅读自有工具层、目录/搜索等待/摘记/笔记/排版和漫画目录/缺图态已重做；内容渲染与定位保持，iOS待验收 |
| A089 | 漫画更多菜单/方向选择/操作说明 | `Tingye/ComicReaderView.swift` | Menu、Picker、showingHelp alert | 让模式、帮助和书签动作分组清晰，保留 VoiceOver 显示阅读工具动作。 | implemented-static-only：阅读自有工具层、目录/搜索等待/摘记/笔记/排版和漫画目录/缺图态已重做；内容渲染与定位保持，iOS待验收 |

## 听书、声音与输出

| ID | 实际表面 | 源文件 | 现有路径/状态证据 | 计划的实质重设计 | 状态 |
| --- | --- | --- | --- | --- | --- |
| A090 | 迷你播放器 | `Tingye/TingyeApp.swift` | MiniPlayer、展开、回到朗读、暂停/继续 | 重做紧凑书名/状态/控制排布，错误与缓冲可辨，大字号垂直布局。 | implemented-static-only：播放器/迷你条、工具格、目录和声音子页新层级及错误面板已集成；播放/音频输出待iOS验收 |
| A091 | 完整听书页面与空态 | `Tingye/PlayerView.swift` | PlayerView book nil、fromReader | 以书名与当前句为中心重做顶部信息和播放区，空态有明确关闭/回书库路径。 | implemented-static-only：播放器/迷你条、工具格、目录和声音子页新层级及错误面板已集成；播放/音频输出待iOS验收 |
| A092 | 跟读文本、前后文与进度 | `Tingye/PlayerView.swift` | SentenceFollow、SentenceProgressControl、上下文 toggle | 重做当前句与前后句的视觉层级，保持自动跟随、长句滚动、句序号和暂停状态。 | implemented-static-only：播放器/迷你条、工具格、目录和声音子页新层级及错误面板已集成；播放/音频输出待iOS验收 |
| A093 | 播放/跳句/跳章/返回原文 | `Tingye/PlayerView.swift` | transportRow、returnToReader、chapter slider | 重新规划核心按钮和进度工具分区，大字号与横屏核心播放常可见。 | implemented-static-only：播放器/迷你条、工具格、目录和声音子页新层级及错误面板已集成；播放/音频输出待iOS验收 |
| A094 | 缓冲、朗读失败与恢复 | `Tingye/PlayerView.swift` | player.buffering/error、重试、检查声音设置 | 把缓冲与失败信息贴近播放动作，错误原因完整可读、恢复动作可达。 | implemented-static-only：播放器/迷你条、工具格、目录和声音子页新层级及错误面板已集成；播放/音频输出待iOS验收 |
| A095 | 听书更多、听到处书签与结束确认 | `Tingye/PlayerView.swift` | player.more、bookmarkListening、endingListening | 统一菜单分组与删除性停止确认，保留阅读位置不受声音书签影响。 | implemented-static-only：播放器/迷你条、工具格、目录和声音子页新层级及错误面板已集成；播放/音频输出待iOS验收 |
| A096 | 封面查看 sheet | `Tingye/PlayerView.swift` | showingCover | 重做封面展示、书名作者和关闭布局，真实书封保持原图。 | implemented-static-only：播放器/迷你条、工具格、目录和声音子页新层级及错误面板已集成；播放/音频输出待iOS验收 |
| A097 | 听书目录 sheet/搜索/章进度 | `Tingye/PlayerView.swift` | ChapterListView、current chapter、empty filtered | 重做目录编号、正在听状态与章跳转，保留 seek 和暂停语义。 | implemented-static-only：播放器/迷你条、工具格、目录和声音子页新层级及错误面板已集成；播放/音频输出待iOS验收 |
| A098 | 语速/睡眠定时菜单与输出路由 | `Tingye/PlayerView.swift`；`Tingye/TingyeApp.swift` | rate menu、sleepUntil、AirPlayButton | 统一菜单触发器与当前值表达，保留后台播放、定时与系统音频输出。 | implemented-static-only：播放器/迷你条、工具格、目录和声音子页新层级及错误面板已集成；播放/音频输出待iOS验收 |
| A099 | 声音与朗读设置主页 | `Tingye/PlayerView.swift` | VoiceSettingsView、试听、保存并应用/取消 | 重新组织当前服务、声音摘要与保存状态；不让未保存草稿混入播放。 | implemented-static-only：播放器/迷你条、工具格、目录和声音子页新层级及错误面板已集成；播放/音频输出待iOS验收 |
| A100 | 系统/云音色选择与加载 | `Tingye/PlayerView.swift` | voiceDetail 选择音色、voicePicker、voicesLoaded | 重做音色行、当前选中与试听控制；保留异步枚举、默认音色和自定义 ID。 | implemented-static-only：播放器/迷你条、工具格、目录和声音子页新层级及错误面板已集成；播放/音频输出待iOS验收 |
| A101 | 朗读节奏子页 | `Tingye/PlayerView.swift` | voiceDetail 朗读节奏、rateSection | 用明确数值、滑杆和试听关系建立简洁布局，保留倍率范围和存储。 | implemented-static-only：播放器/迷你条、工具格、目录和声音子页新层级及错误面板已集成；播放/音频输出待iOS验收 |
| A102 | 分角色配音子页 | `Tingye/PlayerView.swift` | roleSection、Beta、旁白/男声/女声 | 重做启用、角色与声音对应关系，关闭/展开状态和 Beta 说明清晰。 | implemented-static-only：播放器/迷你条、工具格、目录和声音子页新层级及错误面板已集成；播放/音频输出待iOS验收 |
| A103 | 连接云语音子页及六服务选择 | `Tingye/PlayerView.swift` | system/GLM/MiniMax/Azure/ElevenLabs/custom | 重做提供方、连接、模型和音色分组；保持各服务草稿隔离与真实配置字段。 | implemented-static-only：播放器/迷你条、工具格、目录和声音子页新层级及错误面板已集成；播放/音频输出待iOS验收 |
| A104 | 云语音深层字段/模型/音色刷新 | `Tingye/PlayerView.swift` | SecureField、region/groupID/customURL、自定义模型/复刻音色 | 输入、说明、验证与刷新状态组织清晰，保留钥匙串及保存逻辑，审计不读取真实密钥。 | implemented-static-only：播放器/迷你条、工具格、目录和声音子页新层级及错误面板已集成；播放/音频输出待iOS验收 |
| A105 | 声音试听、停止、错误与应用反馈 | `Tingye/PlayerView.swift` | previewing/previewTask/notice/error、暂停原书 | 明确试听正在播放和错误恢复，取消预览恢复策略不变。 | implemented-static-only：播放器/迷你条、工具格、目录和声音子页新层级及错误面板已集成；播放/音频输出待iOS验收 |

## 统计、摘句、专注与读完

| ID | 实际表面 | 源文件 | 现有路径/状态证据 | 计划的实质重设计 | 状态 |
| --- | --- | --- | --- | --- | --- |
| A106 | 我的概览 | `Tingye/StatsView.swift` | ji true、月度摘要、书摘/设置入口 | 重做累积数字、阅读节奏和导航层级，保留来自 sessions/readingSeconds 的真实统计。 | implemented-static-only：统计/月度概览、可滚动日历、自适应汇总、摘句分享视图、专注/读完新页首与笔记布局；iOS待验收 |
| A107 | 独立阅读统计日/周/月/年/全部 | `Tingye/StatsView.swift` | Period、offset、interval、Charts | 重做时间切换、读听分项、图表注释和空记录态，保持计时口径与历史未分类说明。 | implemented-static-only：统计/月度概览、可滚动日历、自适应汇总、摘句分享视图、专注/读完新页首与笔记布局；iOS待验收 |
| A108 | 目标卡与目标/提醒编辑 sheet | `Tingye/StatsView.swift` | goalEditor、5..600、提醒时间、通知拒绝 | 重做数字、预设、提醒开关和权限失败恢复；保持本机通知和达标后不提醒。 | implemented-static-only：统计/月度概览、可滚动日历、自适应汇总、摘句分享视图、专注/读完新页首与笔记布局；iOS待验收 |
| A109 | 逐次记录/阅读时段/按书排行/导出 | `Tingye/StatsView.swift` | sessionsCard、ranking、overview、exportStats | 重做时间线、书名/读听时长与 CSV 导出动作，空历史说明不伪造数据。 | implemented-static-only：统计/月度概览、可滚动日历、自适应汇总、摘句分享视图、专注/读完新页首与笔记布局；iOS待验收 |
| A110 | 阅读日历月选择与日期格 | `Tingye/ReadingCalendarView.swift` | month、grid、未来日期禁用 | 重新规划月份导航、阅读量与达标的非颜色标识，窄屏日期仍易触。 | implemented-static-only：统计/月度概览、可滚动日历、自适应汇总、摘句分享视图、专注/读完新页首与笔记布局；iOS待验收 |
| A111 | 日历选中日明细与月统计 | `Tingye/ReadingCalendarView.swift` | dayDetail、monthSummary | 重做天/分钟/书目层级，无阅读日明确说明，大字号不挤成三列。 | implemented-static-only：统计/月度概览、可滚动日历、自适应汇总、摘句分享视图、专注/读完新页首与笔记布局；iOS待验收 |
| A112 | 今日摘句加载/空候选/我的紧凑卡 | `Tingye/DailyQuoteCard.swift`；`Tingye/StatsView.swift` | DailyQuoteCard(compact:true)、寄语回退、redacted | 以中文引文和出处建立版面；区分真实书摘与阅读寄语，加载可辨。 | implemented-static-only：统计/月度概览、可滚动日历、自适应汇总、摘句分享视图、专注/读完新页首与笔记布局；iOS待验收 |
| A113 | 摘句分享图与系统分享 | `Tingye/DailyQuoteCard.swift`；`Tingye/ReaderAnnotations.swift` | QuoteShareCard/QuoteShareLink，笔记列表可达 | 全新暖纸、炭字、陶土点缀的分享排版与署名，保留图像渲染失败时文字分享。 | implemented-static-only：统计/月度概览、可滚动日历、自适应汇总、摘句分享视图、专注/读完新页首与笔记布局；iOS待验收 |
| A114 | 统一书摘/笔记/书签与搜索 | `Tingye/NotesUnifiedView.swift` | NotesUnifiedView、books groups、query | 重做按书引文、类型、时间和全文片段；增加搜索无结果呈现，保留原模型。 | implemented-static-only：统计/月度概览、可滚动日历、自适应汇总、摘句分享视图、专注/读完新页首与笔记布局；iOS待验收 |
| A115 | 统一摘记跳转/导出/删除确认 | `Tingye/NotesUnifiedView.swift` | markdown、LocatorTarget、两种删除确认 | 分离回原文与更多操作，导出保持章节日期，确认只删除指定数据。 | implemented-static-only：统计/月度概览、可滚动日历、自适应汇总、摘句分享视图、专注/读完新页首与笔记布局；iOS待验收 |
| A116 | 专注开始/自定义时长 | `Tingye/FocusSession.swift`；`Tingye/ReaderView.swift` | FocusStartView idle、25/45/自定义、native reader | 重做书名、时间选择和启动动作，保留唯一 session 与不重复计时。 | implemented-static-only：统计/月度概览、可滚动日历、自适应汇总、摘句分享视图、专注/读完新页首与笔记布局；iOS待验收 |
| A117 | 专注进行/另一本会话/放弃 | `Tingye/FocusSession.swift` | runningSection/otherBookSection、finish/abandon | 明确剩余时间、结束和放弃的后果；已有另一书会话信息完整。 | implemented-static-only：统计/月度概览、可滚动日历、自适应汇总、摘句分享视图、专注/读完新页首与笔记布局；iOS待验收 |
| A118 | 专注完成小结 | `Tingye/FocusSession.swift` | FocusSummaryView、继续读/合上书 | 重做用时、读至章节、新增摘记和引文的层级，保留数据来源及关闭行为。 | implemented-static-only：统计/月度概览、可滚动日历、自适应汇总、摘句分享视图、专注/读完新页首与笔记布局；iOS待验收 |
| A119 | 读完收尾页/读完感编辑 | `Tingye/BookFinishView.swift`；`Tingye/ReaderView.swift` | BookFinishView、quote 换句、saveFinishNote | 重做完成信息、书中引文与可编辑感想，保存状态明确，不改变挂靠 Highlight 的存取。 | implemented-static-only：统计/月度概览、可滚动日历、自适应汇总、摘句分享视图、专注/读完新页首与笔记布局；iOS待验收 |
| A120 | 读完下一本/无下一本/回原文分享 | `Tingye/BookFinishView.swift` | nextSection、nextEntry、QuoteShareLink | 下一本书与回书库为清楚选择，保留先关闭旧 reader 再开新书的时序。 | implemented-static-only：统计/月度概览、可滚动日历、自适应汇总、摘句分享视图、专注/读完新页首与笔记布局；iOS待验收 |

## 设置、数据与深层流程

| ID | 实际表面 | 源文件 | 现有路径/状态证据 | 计划的实质重设计 | 状态 |
| --- | --- | --- | --- | --- | --- |
| A121 | 设置目录 | `Tingye/StatsView.swift` | SettingsDirectoryView，阅读/声音/导入/数据/通用 | 重新规划分组、行标题和当前值摘要，确保全部子页有实际入口。 | implemented-static-only：各设置页EditorialIntro/editorialList、动态字号/自适应行、备份阶段/同步与空间整理新容器已接入；iOS待验收 |
| A122 | 阅读排版设置与预览 | `Tingye/ReaderView.swift` | ReadingPreferencesView、字号/字体/纸色/浅纸常亮/翻页 | 重做分组、实时预览和控制密度；设置值、ReaderPaper 和内容偏好映射保持。 | implemented-static-only：各设置页EditorialIntro/editorialList、动态字号/自适应行、备份阶段/同步与空间整理新容器已接入；iOS待验收 |
| A123 | 全部纸色菜单与翻页动画 | `Tingye/ReaderView.swift` | mainPapers、ReaderPaper.allCases、slide/fade/blur/none | 重做选中标志、模式提示和易触控件，不删除已有纸色或改变存储键。 | implemented-static-only：各设置页EditorialIntro/editorialList、动态字号/自适应行、备份阶段/同步与空间整理新容器已接入；iOS待验收 |
| A124 | 更多排版子页 | `Tingye/ReaderView.swift` | MoreTypographyView、字/行/段/页边距、缩进/对齐/双页/简繁/恢复 | 重做数值层级、分组和重置反馈；保留全部内容 CSS/布局参数默认值与范围。 | implemented-static-only：各设置页EditorialIntro/editorialList、动态字号/自适应行、备份阶段/同步与空间整理新容器已接入；iOS待验收 |
| A125 | 字体管理/导入/删除 | `Tingye/Typography.swift` | MyFontsView、TTF/OTF/TTC、空列表、逐项错误 | 重做字体示例、当前字体、导入结果与删除状态；保留注册、授权与字体回退。 | implemented-static-only：各设置页EditorialIntro/editorialList、动态字号/自适应行、备份阶段/同步与空间整理新容器已接入；iOS待验收 |
| A126 | 选字菜单顺序/隐藏与恢复默认 | `Tingye/MenuSettingsView.swift` | SelectionTool order/hidden、编辑列表、至少保留一项 | 重做拖动、显隐开关和默认说明，保留所有工具及至少一个可见工具约束。 | implemented-static-only：各设置页EditorialIntro/editorialList、动态字号/自适应行、备份阶段/同步与空间整理新容器已接入；iOS待验收 |
| A127 | TXT 分章规则与预览 | `Tingye/TxtRulesView.swift` | maxLength、内置/自定义、预设菜单、无效 regex | 重做规则选择、编辑验证与章节预览，保留仅未来导入/显式重新分章生效。 | implemented-static-only：各设置页EditorialIntro/editorialList、动态字号/自适应行、备份阶段/同步与空间整理新容器已接入；iOS待验收 |
| A128 | 通用设置各项 | `Tingye/GeneralSettingsView.swift` | 语言→系统设置、续读、达标、漫画默认、震动、Home 条、常亮 | 按启动/阅读/交互分组，说明每项影响；保留所有行为和默认值。 | implemented-static-only：各设置页EditorialIntro/editorialList、动态字号/自适应行、备份阶段/同步与空间整理新容器已接入；iOS待验收 |
| A129 | 外观系统/日间/夜间预览 | `Tingye/LibraryViews.swift` | AppearanceView、三个选项、硬编码预览色 | 重做真实暖纸/炭黑外观缩略与选择行，修正文案与实际色彩不符。 | implemented-static-only：各设置页EditorialIntro/editorialList、动态字号/自适应行、备份阶段/同步与空间整理新容器已接入；iOS待验收 |
| A130 | 隐私与关于主页面 | `Tingye/LibraryViews.swift` | ProfileView、应用锁/隐藏/版本/数据导出 | 重做隐私状态与版本信息分层，不遗漏版本、隐藏书籍和导出入口。 | implemented-static-only：各设置页EditorialIntro/editorialList、动态字号/自适应行、备份阶段/同步与空间整理新容器已接入；iOS待验收 |
| A131 | 隐私政策长文 | `Tingye/LibraryViews.swift` | PrivacyPolicyView | 重做长文标题、段落宽度、分隔与可选择文本，保持事实和系统返回。 | implemented-static-only：各设置页EditorialIntro/editorialList、动态字号/自适应行、备份阶段/同步与空间整理新容器已接入；iOS待验收 |
| A132 | 开源组件与字体许可 | `Tingye/LibraryViews.swift`；`Tingye/Resources/Readium-LICENSE.txt` | FontLicenseView、Readium/依赖/字体许可文本 | 重做许可目录和长文本层级；保留全部归属与完整授权内容。 | implemented-static-only：各设置页EditorialIntro/editorialList、动态字号/自适应行、备份阶段/同步与空间整理新容器已接入；iOS待验收 |
| A133 | 空间整理总量/分项/扫描 | `Tingye/StorageView.swift` | StorageUsage：library/originals/derived/speech/covers/temporary | 重做用量、分项解释和扫描反馈；原 EPUB 与派生缓存明确区分。 | implemented-static-only：各设置页EditorialIntro/editorialList、动态字号/自适应行、备份阶段/同步与空间整理新容器已接入；iOS待验收 |
| A134 | 缓存清理/索引修复与确认 | `Tingye/StorageView.swift` | clearAll confirmation、clear、索引修复、error | 以可清理项和安全范围组织动作，保护源包、使用中的 pin 与其他书库。 | implemented-static-only：各设置页EditorialIntro/editorialList、动态字号/自适应行、备份阶段/同步与空间整理新容器已接入；iOS待验收 |
| A135 | 备份与同步主页面 | `Tingye/ICloudBackup.swift` | ICloudBackupView、可备份数量、导出/立即备份 | 重做当前状态、保存和恢复分区；保留原包随归档与本机数量约束。 | implemented-static-only：各设置页EditorialIntro/editorialList、动态字号/自适应行、备份阶段/同步与空间整理新容器已接入；iOS待验收 |
| A136 | 备份/还原阶段进度卡 | `Tingye/ICloudBackup.swift` | ICloudTransferCard running/done/failed/cancelled/confirming | 真实阶段和计数分层，无法估算时不伪装百分比，取消/重试/收起可达。 | implemented-static-only：各设置页EditorialIntro/editorialList、动态字号/自适应行、备份阶段/同步与空间整理新容器已接入；iOS待验收 |
| A137 | iCloud 上传状态 | `Tingye/ICloudBackup.swift` | checking/waiting/uploading/uploaded/notUbiquitous/failed、paused | 清楚区分本地写入与系统上传，显示查询时间和刷新入口。 | implemented-static-only：各设置页EditorialIntro/editorialList、动态字号/自适应行、备份阶段/同步与空间整理新容器已接入；iOS待验收 |
| A138 | 查找最新备份/本地文件恢复/替换确认 | `Tingye/ICloudBackup.swift` | readLatest、prepareRestoreFromFile、pendingRestore | 重做来源、日期、书籍数量、替换范围和取消，保持恢复事务与原包校验。 | implemented-static-only：各设置页EditorialIntro/editorialList、动态字号/自适应行、备份阶段/同步与空间整理新容器已接入；iOS待验收 |
| A139 | 自动进度同步与展开详情 | `Tingye/ICloudBackup.swift` | ProgressSyncStatusRows、账号状态、最近提交/接收 | 重做状态摘要与明细、开关和立即检查；不承诺系统未确认的上传/跨机到达。 | implemented-static-only：各设置页EditorialIntro/editorialList、动态字号/自适应行、备份阶段/同步与空间整理新容器已接入；iOS待验收 |
| A140 | 恢复期间禁用/云不可用/无书/备份错误 | `Tingye/ICloudBackup.swift`；`Tingye/AppModel.swift`；`Tingye/TingyeApp.swift` | busy/restoringLibrary、signed/unsigned 能力差异 | 把不能操作的原因和下一步展示在原位置，保持数据事务和用户书库。 | implemented-static-only：各设置页EditorialIntro/editorialList、动态字号/自适应行、备份阶段/同步与空间整理新容器已接入；iOS待验收 |

## 兼容表面、系统界面与全局适配

| ID | 实际表面 | 源文件 | 现有路径/状态证据 | 计划的实质重设计 | 状态 |
| --- | --- | --- | --- | --- | --- |
| A141 | 遗留 OriginalBookView 与 AllNotesView | `Tingye/OriginalBookView.swift`；`Tingye/ReaderAnnotations.swift` | 定义保留，检索无生产调用；非实际主阅读入口 | 保留源码和测试兼容，不复活旧 WebView 路由；若后续确认新入口再登记并适配自有 chrome。 | preserved-by-scope：保留遗留定义，生产路由仍使用Readium；不复活旧WebView |
| A142 | 调试走查场景与 fixture 导航 | `Tingye/TingyeApp.swift`；`TingyeUITests/DesignFlowTests.swift` | -uireview、-ui-fixture、-ui-showcase | 保留场景与可访问标识；补新状态场景时继续使用隔离书库，不能绕过测试断言。 | implemented-static-only：既有全部走查/fixture与测试字节保留，新增真实Documents导入fixture及8单元/2UI回归源码；iOS待验收 |
| A143 | 系统文件/恢复/字体/修书选择器 | `Tingye/ShelfView.swift`；`Tingye/ICloudBackup.swift`；`Tingye/Typography.swift`；`Tingye/LibraryViews.swift` | 四类 fileImporter 宿主、取消/返回 | 自有入口和结果统一；保留 iOS 系统 provider 体验、文件访问权限与原生取消。 | implemented-static-only：书籍选择器集中根宿主；修书/字体/备份仍保持各自系统流程和新表单入口，不混同归档恢复；iOS待验收 |
| A144 | 系统通知/本地网络/生物识别/系统设置 | `Tingye/StatsView.swift`；`Tingye/Sources.swift`；`Tingye/Library.swift`；`Tingye/GeneralSettingsView.swift` | 权限弹窗与返回 App 的各状态 | 统一自有权限说明与被拒恢复路径，系统授权 UI 维持原生。 | implemented-static-only：锁屏说明/验证进度、来源连接恢复和提醒权限说明接入新界面；系统授权弹窗保持原生；iOS待验收 |
| A145 | 深色与高对比全局状态 | `Tingye/Theme.swift`；`Tingye/LibraryViews.swift`；`Tingye/Sources.swift` | 动态颜色、AppearancePreview、WiFi CSS、reader 独立纸色 | 为自有 UI 建立日/夜/提高对比配色及边界；正文现有纸色与映射原样保留，单独验证对比。 | implemented-static-only：日夜UI tokens、高对比边界与WiFi网页contrast规则；正文七种纸色与偏好字节保持；iOS待验收 |
| A146 | Dynamic Type/小屏/横屏/iPad/键盘 | `Tingye/Theme.swift`；`Tingye/ShelfView.swift`；`Tingye/ReaderView.swift`；`Tingye/PlayerView.swift` | 固定 Theme.sans/display、AnyLayout、ScrollView、safeArea | 界面文字改用可缩放角色、长文本可换行；保留正文阅读偏好与现有可达性策略。 | implemented-static-only：UI字号角色/ScaledMetric、自适应行、漫画/EPUB大字工具滚动、日历日期最小宽度；布局待iOS验收；iOS待验收 |
| A147 | VoiceOver/触点/减弱动态效果 | `Tingye/Theme.swift`；`Tingye/TingyeApp.swift`；`Tingye/ReaderView.swift`；`Tingye/ComicReaderView.swift` | accessibility 标识/动作、respectReducedMotion、44pt 控制 | 审查标题语义、焦点返回、状态朗读、非颜色信号及最小44×44pt目标；动画响应系统设置。 | implemented-static-only：标题/状态语义、44pt控制、应用锁下层VoiceOver隐藏和既有减弱动态效果保留；真实VO焦点/触点待验收；iOS待验收 |

## 所有行共同的状态与验收矩阵（均 pending）

| 维度 | 需要验证的实际情况 | 验收要求 | 状态 |
| --- | --- | --- | --- |
| 内容 | 首次空库、无简介/封面/书签/摘记、无搜索匹配、无远程目录、无下一本、无可朗读文字 | 原位置解释原因并提供适合该状态的动作；不生成虚构用户数据 | pending |
| 异步 | 导入选择后、读盘/解析/保存、EPUB 打开、音色枚举/试听、远程下载、存储扫描、备份/还原/上传 | 开始可见、阶段真实，允许的取消/重试可达；完成和失败都有反馈 | pending |
| 错误 | 拒绝权限、文件失效/不存在/损坏/不支持、认证或网络失败、云不可用、未定位摘记 | 原因不被截断；保留成功项与原文/进度；恢复动作明确 | pending |
| 模态 | sheet、fullScreenCover、popover、confirmationDialog、alert、系统选择器/分享、键盘、iPad | 单一稳定宿主；先关闭再呈现；取消不误执行；关闭后焦点回到触发器 | pending |
| 日夜/高对比 | 跟随系统/固定日夜、提高对比、浅纸常亮、自有与系统材质、WiFi HTML | 普通文本目标至少4.5:1，大字与必要图形至少3:1；重要状态不只靠颜色；测量后才标通过 | pending |
| 字号与尺寸 | 默认、最大普通、最大辅助字号；小 iPhone、横屏、iPad 分屏；中文长标题/长路径 | 自有文字缩放/换行；底部动作可达；触点至少44×44pt；无截断核心动作 | pending |
| VoiceOver | 标题、次序、按钮名称、选择状态、滑杆值、忙碌/结果反馈、菜单/模态焦点返回 | 有意义的标签/值/动作，不重复朗读装饰；搜索/定位不破坏焦点 | pending |
| 动效 | Reduce Motion、播放器跟读、书签动画、页面/modal 转换 | 尊重减弱动态效果；正文视口不因 chrome/状态转换改变；不以动画承担唯一反馈 | pending |
| 数据安全与兼容 | 新旧 EPUB、固定版式、TXT 图文、PDF、漫画、repair/restore/删除/清缓存 | 所有既有数据/Locator/迁移/源包事务和内容布局测试保留，原阅读与听书进度分离 | pending |

## 后续完成标记规则

每项至少记录实际修改文件、到达路径和验证证据后才能从 pending 更新。实现不等于验收；静态校验不等于 Xcode 编译、iOS 运行或真机文件 provider 验证。系统界面保持系统所有权，记录宿主流程验收。不能以“全局 Theme 已改”批量勾选所有行。

本阶段已按这些路由接入新组件和导入宿主。组件与实际修改说明见 [ANTHROPIC-INTERFACE.md](ANTHROPIC-INTERFACE.md)，导入链路与待设备验收矩阵见 [LOCAL-IMPORT-REGRESSION.md](LOCAL-IMPORT-REGRESSION.md)。源码实施与设备验收分别记录，不把静态结果标成运行通过。

## UI 声明源索引（基线行号）

以下是 Phase 1 基线的声明索引与行号，保留用于对照；具体实施状态以上方A项为准，全部iOS验收仍pending，不能把声明数当独立屏幕数。新增组件见设计系统说明。

| 源文件 | 声明:行号 | 状态 |
| --- | --- | --- |
| `Tingye/BookFinishView.swift` | `BookFinishView:10` | pending |
| `Tingye/ComicReaderView.swift` | `ComicReaderView:7`、`ComicPage:248`、`ZoomableComicImage:303` | pending |
| `Tingye/DailyQuoteCard.swift` | `DailyQuoteCard:6`、`QuoteShareCard:129`、`QuoteShareLink:179` | pending |
| `Tingye/FocusSession.swift` | `FocusStartView:155`、`FocusSummaryView:280` | pending |
| `Tingye/GeneralSettingsView.swift` | `GeneralSettingsView:33` | pending |
| `Tingye/ICloudBackup.swift` | `ICloudBackupView:862`、`ICloudTransferCard:989`、`ICloudUploadRow:1060`、`ProgressSyncStatusRows:1080` | pending |
| `Tingye/Library.swift` | `AppLockGate:206` | pending |
| `Tingye/LibraryViews.swift` | `BookDetailView:8`、`ChapterManagerView:339`、`ProfileView:504`、`AppearanceView:680`、`FontLicenseView:778`、`PrivacyPolicyView:860` | pending |
| `Tingye/MenuSettingsView.swift` | `MenuSettingsView:25` | pending |
| `Tingye/NotesUnifiedView.swift` | `NotesUnifiedView:8` | pending |
| `Tingye/OriginalBookView.swift` | `OriginalBookView:290` | pending |
| `Tingye/PlayerView.swift` | `PlayerView:6`、`TransportButton:482`、`SentenceProgressControl:505`、`ChapterProgressSlider:570`、`ChapterListView:601`、`VoiceSettingsView:703` | pending |
| `Tingye/ReaderAnnotations.swift` | `SelectionPanel:98`、`NoteEditor:288`、`NotesList:342`、`NoteRow:421`、`AllNotesView:458` | pending |
| `Tingye/ReaderView.swift` | `ReaderView:289`、`NativeTextPage:1403`、`ReaderMediaPage:1415`、`ScrollingText:1469`、`ReaderStatusLine:1583`、`PDFReader:1652`、`ContentsView:1736`、`ChapterScrubber:1923`、`IllustrationRow:2030`、`ReadingPreferencesView:2053`、`MoreTypographyView:2248` | pending |
| `Tingye/ReadingCalendarView.swift` | `ReadingCalendarView:4` | pending |
| `Tingye/Readium/EPUBNavigatorHost.swift` | `EPUBNavigatorHost:7` | pending |
| `Tingye/Readium/ReaderRouter.swift` | `RoutedReaderView:14` | pending |
| `Tingye/Readium/ReadiumReaderView.swift` | `ReadiumReaderView:113` | pending |
| `Tingye/SMBBrowser.swift` | `SMBBrowser:75` | pending |
| `Tingye/ShelfView.swift` | `ShelfView:5`、`GroupPickerView:1210`、`BookImportModifier:1273`、`ImportResultsView:1295`、`ShareSheet:1370` | pending |
| `Tingye/Sources.swift` | `SourcesView:93`、`ImportHubView:223`、`SourceActionRow:242`、`SourceEditor:264`、`WebDAVBrowser:357`、`OPDSBrowser:517`、`WiFiTransferView:712` | pending |
| `Tingye/StatsView.swift` | `StatsView:7`、`SettingsDirectoryView:617` | pending |
| `Tingye/StorageView.swift` | `StorageView:4` | pending |
| `Tingye/Theme.swift` | `ScaledSystemFont:201`、`ReducedMotionPolicy:211`、`SoftCardShadow:422`、`SealBadge:431`、`GlassSkin:494`、`CircleIconButton:516`、`ListenLabel:535`、`Card:573`、`SettingsIcon:585`、`SettingsRow:597`、`RowDivider:621`、`InkRule:629`、`SectionTitle:636`、`PageMasthead:659`、`ProgressBar:695`、`BookCoverView:718`、`FlexibleCover:795`、`CoverBackdrop:809`、`NoticeView:828`、`ThemeIcon:938` | pending |
| `Tingye/TingyeApp.swift` | `StudyRootView:188`、`UIReviewAppearance:365`、`WindowAppearance:376`、`MiniPlayer:403`、`FeedbackOverlay:494`、`KeepAwakeModifier:542`、`AirPlayButton:564` | pending |
| `Tingye/TxtRulesView.swift` | `TxtRulesView:5` | pending |
| `Tingye/Typography.swift` | `MyFontsView:100` | pending |
