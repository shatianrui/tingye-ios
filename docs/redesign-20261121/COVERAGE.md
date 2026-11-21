# 听页完整重设计 · 功能与逐屏覆盖矩阵

基线为构建 148「临窗」，功能及入口以当前 `Tingye/` 调用关系为准，实施规格与进度见 [方案](PLAN.md) 和 [状态记录](STATUS.md)。共 **59 项**，含 3 个目的地（书库、摘记、我的），其余为子页、全屏、浮层、任务状态与系统表面。同一条目可以覆盖同一任务内的多个弹层。路径以仓库根为起点，代码锚点用于下一阶段核对真实入口。表中的设计动作属于待实施范围，当前行为有差异时已标明。

状态列按 **空 / 载入或处理中 / 失败 / 权限 / 取消或放弃 / 离线** 顺序列出。`✓` 表示后续要覆盖的任务状态，`—` 表示 N/A。离线列的 `✓` 同时涵盖本地能力应继续可用以及网络能力应显示可恢复状态两类。所有条目均验日间、夜间及最大辅助字号（系统界面遵从平台）；正文另验浅纸置于深色 App。选中、停用、确认和返回也按行验证。各表描述基线入口与拟议验收，尚无本阶段运行结果。

## 全局与书库（13 项）

| ID / 表面 | 生产入口及已有能力 | 重设计验收 | 空 / 载 / 错 / 权 / 取 / 离 |
| --- | --- | --- | --- |
| G01 启动、根栈与返回 | `Tingye/TingyeApp.swift` `StudyRootView`，首载自动开书、前后台刷新与保存、根返回 | 沿用现有冷启动判定，书库直达摘记与我的；返回原路径和焦点，隐藏书不泄露 | ✓/✓/✓/—/—/✓ |
| G02 应用锁 | `Tingye/Library.swift` `AppLockGate`、`PrivacyLock`，系统认证及后备设备密码 | 遮住正文/书名与辅助树，验证中互斥、失败或取消仍可解锁，设备无密码沿现策略 | —/✓/✓/✓/✓/✓ |
| G03 全局状态与操作失败 | `Tingye/TingyeApp.swift` `FeedbackOverlay`、`StudyRootView`，通知、活动、失败 alert、结果 sheet | 明确优先级，任务进度压过旧提示，关闭、结果及非阻断成功可达 | —/✓/✓/—/✓/— |
| G04 系统分享与外部打开 | `Tingye/TingyeApp.swift` `onOpenURL`，`Tingye/ShelfView.swift` `ShareSheet`，`Tingye/DailyQuoteCard.swift` `QuoteShareLink` | 书籍/书库备份、阅读数据、文本与摘句卡分享照原入口，系统取消返回原页；外部文件进入现有导入 | —/✓/✓/✓/✓/✓ |
| S01 书库根与续读 | `Tingye/ShelfView.swift` `ShelfView` 的续读条，`Tingye/AppModel.swift` `lastReadingBook` 与样例初始化 | 续读条、书籍/漫画切换、真实章/页/阅读进度，点书开启；空架保留添书，样例及最近可见划线保留 | ✓/✓/✓/—/—/✓ |
| S02 书目筛选、排序与视图菜单 | `Tingye/ShelfView.swift` `filterMenu/sortMenu/layoutMenu`、`ManualShelfOrder` | 阅读状态及分类、最近阅读/标题/作者/添加/手动，列表/网格独立，已存偏好保持，大字回列表 | ✓/—/—/—/✓/✓ |
| S03 书库搜索 | `Tingye/ShelfView.swift` `startSearch/cancelSearch/rememberSearch` | 书名、作者、分类、分组、历史和清空，空词与无结果有不同提示，键盘上方结果可选 | ✓/—/—/—/✓/✓ |
| S04 嵌套分组、移动及命名 | `Tingye/ShelfView.swift` `ShelfView(group:)`、`GroupPickerView`、重命名 alert | 原目录嵌套，创建/移动/根目录，命名校验；删分组确认保留所含书籍 | ✓/—/✓/—/✓/✓ |
| S05 书目菜单、整理与隐藏 | `Tingye/ShelfView.swift` `menu/finishEditing/hideSelectedBooks/removeSelectedBooks`，`Tingye/Library.swift` | 阅读、听书、详情、隐藏/恢复、解锁、批量选择移动、重排、删除本机确认，退出整理恢复书目 | ✓/✓/✓/✓/✓/✓ |
| S06 书籍详情及简介 sheet | `Tingye/LibraryViews.swift` `BookDetailView` | 阅读、听书、简介全文、目录预览、摘记/书签；未缓存或无本地副本可去备份恢复 | ✓/✓/✓/—/✓/✓ |
| S07 详情操作及修书 picker | `Tingye/LibraryViews.swift` `BookDetailView`，`Tingye/AppModel.swift` `repair/resplit` | 同格式修书、符合条件的 TXT 重分章、单书备份导出、仅本机及本机+iCloud 删除说明及确认 | —/✓/✓/✓/✓/✓ |
| S08 目录管理与批量已读 | `Tingye/LibraryViews.swift` `ChapterManagerView` | 定位当前章、选章、多选与批量已读/未读；阅读/听此章各走正确进度 | ✓/—/✓/—/✓/✓ |
| S09 详情内书签与本书摘记 | `Tingye/LibraryViews.swift` `BookDetailView`、`Tingye/ReaderAnnotations.swift` `NotesList` | 书签和摘记到原文；编辑/分享/删除沿各自已有动作，空态回到阅读 | ✓/—/✓/—/✓/✓ |

## 导入与连接（8 项）

| ID / 表面 | 生产入口及已有能力 | 重设计验收 | 空 / 载 / 错 / 权 / 取 / 离 |
| --- | --- | --- | --- |
| I01 添书中心 / 来源目录 sheet | `Tingye/Sources.swift` `ImportHubView/SourcesView`；书库与 `Tingye/StatsView.swift` `SettingsDirectoryView` 发起 | 单/批、WiFi、WebDAV、OPDS、SMB、连接管理与最近结果仍可到达；格式说明简明 | ✓/—/—/—/✓/✓ |
| I02 系统文件选择 | `Tingye/TingyeApp.swift` `StudyRootView`、`Tingye/ShelfView.swift` `LocalBookPicker`、`Tingye/AppModel.swift` `requestFileImport` | 单一宿主，实际 dismiss 后呈现，复制单选/独立批量，回调即出可见状态；取消与空交付区分 | ✓/✓/✓/✓/✓/✓ |
| I03 导入进度、结果与重选 | `Tingye/AppModel.swift` `importFiles`、`Tingye/Models.swift` `ImportReport`、`Tingye/ShelfView.swift` `ImportResultsView` | 准备、读取、解析保存、逐项成功/失败，展示现有取消结果；保留已保存项，重新选择失败文件。中止运行中批次属可选未来工作 | ✓/✓/✓/✓/✓/✓ |
| I04 新增/编辑连接与移除确认 | `Tingye/Sources.swift` `SourceEditor`、`SourcesView`、`SourceHTTPClient` | 类型、地址、连接表单、保存/取消和删除本机连接；字段校验与原授权/来源边界保留 | ✓/—/✓/✓/✓/— |
| I05 WebDAV 文件夹递归 | `Tingye/Sources.swift` `WebDAVBrowser` | 文件夹导航、刷新、过滤支持文件、下载导入和错误重试，拒绝与离线可辨认 | ✓/✓/✓/✓/—/✓ |
| I06 OPDS 浏览、检索与分页 | `Tingye/Sources.swift` `OPDSBrowser/OPDSFeed` | 目录项、书目行与获取动作、查询与下一页；空目录/无命中、取消等待或离开、下载失败 | ✓/✓/✓/✓/✓/✓ |
| I07 SMB 共享、目录与下载 | `Tingye/SMBBrowser.swift` `SMBBrowser/SMBConnection` | 共享根、递归浏览、连接及下载反馈，保留刷新及回退；本地网络/服务拒绝状态可读 | ✓/✓/✓/✓/—/✓ |
| I08 WiFi 传书与浏览器上传 | `Tingye/Sources.swift` `WiFiTransferView/WiFiTransferServer`、`Tingye/Info.plist` | 地址就绪/等待、复制完整链接、接收与失败逐项、断线重连和结束/离开关闭服务，配对限制沿用 | ✓/✓/✓/✓/✓/✓ |

格式核对以 `Tingye/BookImporter.swift` 的 `read/readCoordinated` 与 `Tingye/Sources.swift` 的 `ImportableFile` 为准，后者独立按文件名过滤，各入口保持目前接纳范围。解析支持 EPUB、TXT（含 `text`/无扩展文本）、MOBI/AZW/AZW3/PRC、PDF、HTML/HTM/XHTML、Markdown、DOCX、CBZ/图片 ZIP、听页备份 JSON 及可解码的 `Book` JSON。DRM、RAR/CBR、扫描 PDF 的 OCR 为 N/A。PDF 图片页仍可查看，听书仅用可提取文字。整库归档恢复走 T09。

## 阅读与书内工具（14 项）

| ID / 表面 | 生产入口及已有能力 | 重设计验收 | 空 / 载 / 错 / 权 / 取 / 离 |
| --- | --- | --- | --- |
| R01 格式路由及全屏 | `Tingye/TingyeApp.swift` 根 cover、`Tingye/Readium/ReaderRouter.swift` | 先模型漫画标记，再存在可从 Base64 解出的 PDF 数据，再 EPUB，其余原生。读取时可反馈；关闭时保存、返回发起上下文 | —/✓/✓/—/✓/✓ |
| R02 原生分页、滚动及文内媒体 | `Tingye/ReaderView.swift` `ReaderView/NativeTypesetter/ScrollingText/ReaderMediaPage` | 原位置、单/自动双页、分页/滚动及插图表格。正文独立排版；工具开合不改变页位 | ✓/✓/✓/—/—/✓ |
| R03 原页 PDFKit | `Tingye/ReaderView.swift` `ReaderDocument/PDFReader` | PDF 原页与放大、图像原色，覆盖工具开合保持页内位置与缩放；EPUB 原书图文归 R04 | ✓/✓/✓/—/—/✓ |
| R04 Readium EPUB 加载与导航 | `Tingye/Readium/ReadiumReaderView.swift` `open/locationChanged`、`EPUBNavigatorHost.swift`、`PublicationStore.swift`（同目录） | 原 EPUB 或旧数据派生、内链和分页、开合不改真实 Navigator 视口，打开重试或返回修书，定位不足时显式提示 | ✓/✓/✓/—/✓/✓ |
| R05 原生/PDF 工具栏、更多及自动翻页子面板 | `Tingye/ReaderView.swift` `chapterBar/moreMenu/morePanelRows` | 章/页滑杆、书签、目录、排版、摘记、搜索、日夜、适用时自动翻页、辅助听书、专注/收尾、备份；popover 可关闭 | —/—/—/—/✓/✓ |
| R06 原生目录 sheet | `Tingye/ReaderView.swift` `ContentsView/ChapterScrubber` | 目录、书签、插图、笔记分段，读/听当前章可辨，书签移除确认和跳转可达 | ✓/✓/✓/—/✓/✓ |
| R07 EPUB 目录、书签与摘记 sheet | `Tingye/Readium/ReadiumReaderView.swift` `contentsView` | 出版物原目录深度、回退章列表、书签删除、摘记未定位提示，退出及搜索可达 | ✓/✓/✓/—/✓/✓ |
| R08 书内搜索 | `Tingye/ReaderView.swift` `ContentsView/ReaderSearch`，`Tingye/Readium/ReadiumReaderView.swift` `showSearch/jumpTo` | 等待、无匹配和前 200 处提示，同章多命中、定位到原文及匹配装饰，取消中止旧查询 | ✓/✓/✓/—/✓/✓ |
| R09 排版及更多排版子页 | `Tingye/ReaderView.swift` `ReadingPreferencesView/MoreTypographyView`、`Tingye/Readium/ReadiumPreferencesBridge.swift` | 字体/导入、字号行段距、边距、缩进、对齐、翻页、纸色、简繁、预览与默认值。Readium 仅作用于支持设置，固定版式按现桥接单独校验 | —/✓/✓/—/✓/✓ |
| R10 选段、标注、笔记编辑与删除 | `Tingye/ReaderAnnotations.swift` `SelectionPanel/NoteEditor/NotesList`、`Tingye/Readium/ReadiumAnnotations.swift`、`Tingye/Readium/ReadiumReaderView.swift` `selection` | 五色三样式、旧绿、选段菜单配置、编辑/复制/分享、删除确认；原文定位与未定位数据保留 | ✓/✓/✓/—/✓/✓ |
| R11 阅读中辅助听书 | `Tingye/ReaderView.swift` `listeningControls`、`Tingye/Readium/ReadiumReaderView.swift` `bottomActions/refreshSpeech`、`ReadiumSpeechBridge.swift`（同目录） | 从当前处开始、暂停/继续、回到朗读、停止跟随、已有播放器入口及结束确认，浅深纸跟读带与跨页对齐 | ✓/✓/✓/—/✓/✓ |
| R12 漫画全屏、页目录和帮助 | `Tingye/ComicReaderView.swift` `ComicReaderView/pageDirectory/ZoomableComicImage` | 左右翻/反向/竖滚、缩放手势、页码跳转、书签筛选、阅读说明 alert、坏图反馈；TTS 为 N/A | ✓/✓/✓/—/✓/✓ |
| R13 专注计时、运行及总结 | `Tingye/ReaderView.swift` 专注 sheet、`Tingye/FocusSession.swift` `FocusStartView/FocusSummaryView` | 25/45 分或自定义、继续/结束/放弃、已有其他书会话与完成小结，恢复保留章及会话 | ✓/—/—/—/✓/✓ |
| R14 读完收尾 sheet | `Tingye/ReaderView.swift` `finishPresented`、`Tingye/BookFinishView.swift` | 读完状态、摘句回原文/分享、读完感编辑、下一本与回书库；无候选和加载降级 | ✓/✓/✓/—/✓/✓ |

## 听书（8 项）

| ID / 表面 | 生产入口及已有能力 | 重设计验收 | 空 / 载 / 错 / 权 / 取 / 离 |
| --- | --- | --- | --- |
| P01 全局迷你播放器 | `Tingye/TingyeApp.swift` `MiniPlayer` | 播/停、合成中、错误提示、展开、回到朗读三触点；无会话隐藏，整理/搜索时收起 | ✓/✓/✓/—/—/✓ |
| P02 全屏播放器与句流 | `Tingye/PlayerView.swift` `PlayerView/SentenceProgressControl` | 播停、上一/下一句、拖句/定位、当前句和可选前后文、书签、按格式返回原文，暂停拖动保持暂停 | ✓/✓/✓/—/✓/✓ |
| P03 播放器从属弹层 | `Tingye/PlayerView.swift` 封面/章节/声音 sheet、倍速/定时菜单、结束确认，`Tingye/TingyeApp.swift` `AirPlayButton` | 放大封面、入口可达、定时关闭、加速、输出设备、结束须确认；保留播放位置 | ✓/✓/✓/—/✓/✓ |
| P04 听书章节列表与检索 | `Tingye/PlayerView.swift` `ChapterListView/ChapterProgressSlider` | 搜索及无匹配、当前章、章滑杆、跳章后保持原暂停/播放状态 | ✓/—/—/—/✓/✓ |
| P05 声音设置、试听与保存 | `Tingye/PlayerView.swift` `VoiceSettingsView`、`Tingye/SpeechPlayer.swift` `SpeechVoiceCache` | 从播放器/阅读或设置到达；加载系统音色、试听/停止、保存或取消，试听结束恢复应恢复的会话 | ✓/✓/✓/—/✓/✓ |
| P06 音色、语速、分角色子页 | `Tingye/PlayerView.swift` `voiceDetail`、`Tingye/DialogueRoles.swift` | 音色及自定义能力按提供方、语速调整、Beta 分角色及所选音色，草稿与参数可读 | ✓/✓/✓/—/✓/✓ |
| P07 云语音连接与草稿 | `Tingye/PlayerView.swift` `cloudConfiguration`、`Tingye/SpeechPlayer.swift` `VoiceOptions`、`Tingye/Services.swift` `CloudSpeech` | 系统、GLM、MiniMax、Azure、ElevenLabs、自定义的现有字段、列表、模型、自定义音色、试听和保存；失联可回系统音色 | ✓/✓/✓/✓/✓/✓ |
| P08 音频系统表面 | `Tingye/SpeechPlayer.swift` `SpeechAudioSession/SpeechPlayer`、`Tingye/TingyeApp.swift` `AirPlayButton/KeepAwakeModifier` | 后台/锁屏媒体、遥控、音频输出切换与中断恢复，系统/云语音错误可恢复，常亮按偏好 | ✓/✓/✓/—/✓/✓ |

## 摘记、我的与足迹（6 项）

| ID / 表面 | 生产入口及已有能力 | 重设计验收 | 空 / 载 / 错 / 权 / 取 / 离 |
| --- | --- | --- | --- |
| M01 统一摘记索引 | `Tingye/NotesUnifiedView.swift` `NotesUnifiedView`、`Tingye/StatsView.swift` `.notes` | 新增书库头部直达且保留我的入口，按书/类型/查询，回到原文（含听书书签）、确认移除/删除、逐书 Markdown 导出；隐藏条目遵从授权 | ✓/—/✓/✓/✓/✓ |
| M02 我的概览及每日摘句 | `Tingye/TingyeApp.swift` `StudyRoute.me`、`Tingye/StatsView.swift` `StatsView(ji:)`、`Tingye/DailyQuoteCard.swift` | 摘句、原文/分享可用时显示，目标与统计摘要，进入统计、摘记和设置，返回书库 | ✓/✓/✓/—/✓/✓ |
| M03 阅读足迹 | `Tingye/StatsView.swift` `statisticsContent` | 周期、前后区间、读听拆分/旧记录、图表、阅读节奏与逐次记录；空区间可切换，可导出 | ✓/—/✓/—/✓/✓ |
| M04 每日目标与提醒 sheet | `Tingye/StatsView.swift` `goalEditor/ReadingReminder`、`Tingye/GeneralSettingsView.swift` `celebrateIfGoalReached` | 目标分数与时间、保存/取消、权限被拒可解释、后台提醒及达标提示保持 | —/✓/✓/✓/✓/✓ |
| M05 阅读日历 sheet | `Tingye/ReadingCalendarView.swift` `ReadingCalendarView`、`Tingye/StatsView.swift` | 月切换、日选择、记录为空、当日时长及已读书目；按原开启/关闭路径 | ✓/—/—/—/✓/✓ |
| M06 系统通知与设置跳转 | `Tingye/StatsView.swift` `ReadingReminder`、`Tingye/GeneralSettingsView.swift`，`Tingye/Library.swift` | 仅在已有功能需要时出现系统授权/设置联动，拒绝、关闭、返回时更新可见状态 | —/—/✓/✓/✓/✓ |

## 设置、空间与备份（10 项）

| ID / 表面 | 生产入口及已有能力 | 重设计验收 | 空 / 载 / 错 / 权 / 取 / 离 |
| --- | --- | --- | --- |
| T01 设置目录及路径转接 | `Tingye/StatsView.swift` `SettingsDirectoryView`、`Tingye/LibraryViews.swift` `SettingsDestination/settingsDestinationView` | 五组齐全，保留通向 R09、P05、I01 和其余设置子页；目标/摘记从我的可达 | —/—/—/—/—/✓ |
| T02 App 外观 | `Tingye/LibraryViews.swift` `AppearanceView`、`Tingye/TingyeApp.swift` `WindowAppearance` | 跟随系统/日间/夜间，色板预览和选中可读，纸色仍单独设置 | —/—/—/—/—/✓ |
| T03 通用设置 | `Tingye/GeneralSettingsView.swift` `GeneralSettingsView` | 语言（进系统设置）、保留启动续读设置及现有启动行为、达标、漫画默认方向、触感、Home 指示条及常亮 | —/—/—/—/✓/✓ |
| T04 字体管理及导入 | `Tingye/Typography.swift` `MyFontsView/FontLibrary`、`Tingye/Readium/ReadiumFontProvider.swift` | 已带字体及用户字体、导入选择及撤销、删除用户字体、缺失回退和系统字体；不改已保存字体键 | ✓/✓/✓/✓/✓/✓ |
| T05 选段菜单设置 | `Tingye/MenuSettingsView.swift` `MenuSettingsView/SelectionTool` | 调整次序和显隐，默认首个可见，至少一个可用；拖动有辅助路径 | —/—/—/—/—/✓ |
| T06 TXT 分章规则 | `Tingye/TxtRulesView.swift` `TxtRulesView`、`Tingye/BookImporter.swift` `TxtChapterRules` | 自定义规则、最大字数、内置规则、删除与预览，非法正则提示；书籍重分章走详情 | ✓/—/✓/—/✓/✓ |
| T07 隐私与关于及子页 | `Tingye/LibraryViews.swift` `ProfileView/PrivacyPolicyView/FontLicenseView` | 应用锁、隐藏书、版本、隐私、许可、阅读数据导出；保留原有清缓存确认和隐私入口 | ✓/✓/✓/✓/✓/✓ |
| T08 空间整理与清理确认 | `Tingye/StorageView.swift` `StorageView/StorageUsage`、`Tingye/Services.swift` `LibraryDisk` | 分项计数、索引修复、清指定或全部缓存确认；原 EPUB、当前使用缓存和元数据受保护 | ✓/✓/✓/—/✓/✓ |
| T09 整库备份、还原预览及确认 | `Tingye/ICloudBackup.swift` `ICloudBackupView/ICloudTransferCard/ICloudBackupStore`、`Tingye/Services.swift` | 本地导出/系统文件选择、iCloud 保存与查找，元信息预览、逐阶段进度、取消或重试、确认替换对应书；其他书保留 | ✓/✓/✓/✓/✓/✓ |
| T10 自动同步与上传状态 | `Tingye/ICloudBackup.swift` `ProgressSync/ICloudUploadStatus/ProgressSyncStatusRows` | 同步独立开关、立即检查、上次事实和账号不可用提示；离线存本地，已开启等待与错误明确区分 | ✓/✓/✓/✓/—/✓ |

## 覆盖核对口径

- `Tingye/ReaderAnnotations.swift` 中旧 `AllNotesView` 的声明仅作历史核对，活动全局路线使用 `NotesUnifiedView`。历史 `Design/feature-parity.csv` 的 React Native 路径及旧设计态不计入当前目的地。`Tingye/TingyeApp.swift` 的 `UIReview` 是 DEBUG 检查入口，后续保留测试目的地与真实生产可达性。
- EPUB 与原生/PDF 的底部工具及目录结构当前不同，按各自代码覆盖。保持 Readium 源包、定位、图文、目录内链接及听书桥接。`OriginalBookView` 的视图定义和相关单元回归仍在项目内，当前生产路由使用 Readium 或原生/PDF；同文件的 `OriginalDocument` 清理/拼装 helper 仍用于导入和 Readium 派生。
- 下阶段每行补充有证据的完成标记（实现 SHA、测试/走查标识及设备缺口）。P0 必须先保护导入单宿主、正文视口、数据可逆、读听进度和辅助功能。设备与 CI 的关闭条件见 [方案](PLAN.md)。
