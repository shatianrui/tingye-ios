# 听页完整重设计 · 第一阶段方案

实施进度见 [状态记录](STATUS.md)。基线为本地 `HEAD` 和 `origin/main` 的 `56c3b79d71378c5d792f0db56097968bbf3fba48`，`redesign/full-product-20261121`，1.26.0（148）「临窗」。协调方已核验同 SHA 的 Tests `44256844448`、未过期的 `Tingye-unsigned-ipa`（run `44261764826`）及最近 verified release `unsigned-1.26.0-20261118.49`。第一阶段根据这些记录及工作区源码制定方案。逐屏范围及状态见 [覆盖矩阵](COVERAGE.md)。

## 1. 设计方向「页签」

让用户能从书目继续阅读，也能从摘记直接回原文。书库采用紧凑的续读条和连续书目，阅读器保持整张正文，工具在边缘展开。摘记成为可独立进入的索引，播放器把当前句和控制置于同一视觉中心。沿用 Anthropic 暖纸稿的安静留白与中文宋体节奏，采用暖纸、深青和单一连续内容面。当前 `Theme.swift` 的临窗冷灰/窗蓝、`StudyRootView` 的单栈和 `ShelfView` 的书库功能是实施起点。参考了 `Design/v31-anthropic/DESIGN.md` 的材质、`Design/v29-study/DESIGN.md` 的沉浸原则、`Design/v19-margin/previews/figma-now-contrast-verified.png` 的续读层级与 `Design/v20-folio/runtime/light-overview.jpg` 的列表和听读对照。正式界面采用下文的新构图。图标默认沿用当前 AppIcon 三外观和现有语义图标资产，封面优先用真实书封，缺图时用纸色、书名和作者。

### 视觉规格

| 语义 | 日间 | 夜间 | 使用 |
| --- | --- | --- | --- |
| 画布 | `#F5F1E8` | `#191D1B` | 书库、摘记、设置底色 |
| 内容面 | `#FFFCF6` | `#232925` | 表单、面板、控制条 |
| 选中面 | `#E9EDE5` | `#303B34` | 当前行、筛选、播放句底 |
| 主墨 / 次墨 | `#232823` / `#545D53` | `#F1EEE4` / `#B8C1B7` | 内容及元数据 |
| 强调 / 强调上文字 | `#2D594B` / `#FFFFFF` | `#A9D7C0` / `#172820` | 主动作、激活、链接、焦点 |
| 装饰线 / 控件边界 | `#D9D5C8` / `#777F75` | `#404A42` / `#7E897F` | 前者用于分隔，后者用于有语义的边界和进度轨 |
| 错误 / 警示 | `#9C343C` / `#775217` | `#FFACB2` / `#F3C980` | 有文字与图标的失败、权限、破坏性动作 |

- 型版以默认 Dynamic Type 的点数为基准。页面标题 30 pt、书名及当前播放句 22–24 pt、摘句 19 pt，使用已打包且可用的思源宋体 Regular，缺字体时回系统字。栏目 17 pt semibold、行文及按钮 17 pt、元数据和状态 13–15 pt，使用系统字重和相对文本样式。时间、百分比、章数用等宽数字。阅读正文仍由已保存的字体和排版控制。日期、书名、语言、音色和文件名支持换行与四种现有 App 语言。
- 间距 4/8/12/16/24/32/48 pt，外边距紧凑 16、常规 24，宽屏主列最大 720，覆盖式阅读工具最大 760。列表行基础 52、主按钮基础 48，随内容增高。书封圆角 4，控件 8，面板 16，发丝线 0.5–1。每页一个实色主要动作，行尾处理次级动作，长列表共用一张内容面。稳定布局使用实色及分隔线，媒体图保持原色。系统弹层与分享保留平台材质。减少透明度时，自定义浮层用不透明内容面。
- 触点至少 44×44 pt，主控可键盘访问。VoiceOver 顺序为返回、标题、当前对象、主动作、内容、附加动作；sheet 打开读标题，关闭后还焦点，表单首错获焦。拖动条有可调值和增减动作，图表提供读听拆分文字，选中、失败、正在播放、已读均有颜色以外的标签。普通字目标 ≥4.5∶1，重要非文本边界 ≥3∶1。上述深浅方案的次墨对选中面约 5.77/6.30，强调按钮文字约 7.95/9.68，控件边界对选中面约 3.49/3.21。高对比模式以主墨加强次字、边界和焦点，实际合成色、所有语义组合及新增控件需验收。
- 反馈按压 120 ms，面板淡入及内容更新 180–220 ms；沿用系统 push/sheet 转场，减少动态效果时取消装饰位移、自动居中滚动改为直接定位。保留已有翻页、触感及常亮偏好，暂停时句流稳定，进度和焦点变化不抢滚动。最大辅助字号自动改单列、按钮堆叠、书架列表化、读听工具可滚动；返回、关闭、播放和提交在键盘、小屏及横屏可达。
- App 外观和正文纸色各自解析。`Theme.swift` 的 `ReaderPaper` 七键、始终浅色/独立夜间语义、原生/原书和 `ReadiumPreferencesBridge` 的等价解析保持。首轮保留临窗正文纸色和正文跟读配色，再以原文画布实测；界面青色用于导航和操作。用户调色盘 `yellow/clay/blue/pink/purple`、历史 `green`、浅底/直线/波浪线装饰和默认键映射保持。跟读有独立高亮带，按实际正文纸色取对比，暂停/跳章/停止跟随清理及重复句定位沿用各引擎逻辑。见 `ReaderAnnotations.swift`、`ReaderView.swift`、`OriginalBookView.swift` 与 `Readium/ReadiumAnnotations.swift`、`ReadiumReaderView.swift`。

## 2. 导航与关键流程

单一 `NavigationStack` 以书库为根，页首提供有文字的「摘记」「我的」直达入口，另设搜索和添书。宽屏使用相同路由和更宽的书目构图。书库头部续读区是紧凑内容条，以最近阅读位置及「继续阅读」为主，保留「开始专注」；听书仍从书籍菜单、详情和迷你播放器进入；继续区下接书种、筛选/排序/显示及书目，同一屏保有整理和详情。搜寻或整理时沿用迷你播放器隐藏规则，退出恢复书库浏览入口，返回原路径与滚动焦点应在设备上核对。隐藏书籍、返回、空架导入、手动整理及既有启动模式都保留入口。

| 流程 | 实施规格及理由 |
| --- | --- |
| 打开 App → 继续阅读 | 启动沿用构建 148 的 `StudyRootView` 行为。首次有书目时只尝试开书一次，沿用当前选书与跳过漫画的判定，返回后可在书库主动续读。保留 `GeneralSettingsView` 的 `launch.resume` 偏好与显示，接入启动属于可选未来工作。 |
| 书库 → 搜索/整理/详情 | 同一书库内搜索书名、作者、分类，搜索亦匹配分组，关闭后回到发起目录。列表点书直开，详情用独立按钮或原菜单，长按和整理保留入口。详情上半部显示封面及读/听位置，下半部顺序为简介、目录、摘记与书签、书籍管理；底部读和听动作依格式显示。非本地书走既有备份恢复。 |
| 书库/设置/外部 → 添书 → 结果 | hub 首位为「选择文件」「批量导入文件」，其下为 WiFi、连接与最近结果。系统文件选择关闭后显示全局进度条及可展开的文件队列；外部打开沿用 `onOpenURL` 接入，连接与修复/恢复沿各自既有入口及处理语义。已开始的系统选取、下载、导入分别反馈对应阶段。关闭结果回到发起上下文，重试时重新选文件，已成功项保留。 |
| 书目/详情/摘记 → 原文 → 返回 | 根级全屏经 `RoutedReaderView` 打开。原生/PDF 共享返回、章/页和书签，工具顺序沿用目录、排版、摘记、更多。EPUB 保有 Readium 自己的目录/听书/设置、目录内搜索/书签/摘记及选择动作；两引擎共用视觉组件与命名。保留 Readium 内链、目录深度和真实位置；工具开合覆盖正文，前后 EPUB 列、原生分页、PDF 页内位置和缩放不变。漫画全屏保留方向、缩放、页码、目录、书签和帮助。 |
| 阅读 → 听书 → 读/听切换 | 「从此处听」在正文继续显示，跟随可开关；「回到朗读」显式定位。迷你播放器保留展开、播放/暂停和回到朗读，完整播放器保留逐句、进度、章节、封面、书签、倍速、定时、声音、音频输出和结束确认。回原文按入口保持基线语义，播放器对非 EPUB 返回已有阅读位置，对 EPUB 定位正在朗读的原文；迷你播放器的「回到朗读」明确定位当前朗读句。正文跳转、搜索/摘记返回不擅自 seek 或开始音频。 |
| 摘记 → 定位与整理 | 保留书内目录/直接摘记按钮、详情及「我的」原入口。统一摘记仍分书列出并按类别搜索，详情保留原文和上下文，书签回到创建时的原文位置，选段面板内已有的从此处听继续可用。复制/引用分享、Markdown 导出、编辑、删除标注或书签沿原控制与确认。隐藏书的索引遵从授权。 |
| 我的 → 统计/设置 → 恢复或管理 | 我的优先显示目前实际统计、每日目标、今日摘句和显式入口。足迹保留日/周/月/年/全部与日历、读听分项和旧统计，设置用阅读、声音、导入、数据、通用分组。恢复循选择来源、预览影响、确认、处理、完成，失败保留本地书库。隐私锁、通知与本地网络权限保留系统呈现。 |

### 关键页面的构图

- **书库**将搜索和添书置于首屏，紧接一条续读行。续读行用约 44×64 pt 书封、章/页与百分比，主按钮写明续读；书目先展示标题与作者，次行放进度和位置，详情用独立触点。保留可见最近划线的「今日一句」，放在书目后，出处可读。
- **阅读与漫画**在隐藏工具时只显示正文和已有状态提示。露出工具时，顶部为返回、书/章名与书签，底部先给位置后给动作；深外观上的浅纸仍用浅纸控件。图片页以原图和缩放为中心，页号及方向可独立操作。
- **听书**上方为返回和书/章信息，中部为当前句及可选前后文，底部依次是句进度、三键传输控制、章节/倍速/声音/定时等工具及返回原文。宽屏可把句流和控制并列，窄屏和大字让句流独立滚动，播放键常驻。
- **摘记**先呈搜索和类型，随后按书分段。每条以原文为首，笔记置于其下，章与日期放在末行。整组与逐项动作分开标明，正文一键可回。**我的**先显示读听摘要及目标，入口用连续清单。足迹图表旁保留读听数值，备份页按保存、恢复、同步的顺序分区。

### 本地导入的可见状态与呈现契约

1. `ShelfView`、`SettingsDirectoryView`、`SourcesView` 和 `ImportResultsView` 发同一个 `AppModel.requestFileImport` 请求。`StudyRootView` 唯一承载 `LocalBookPicker`。结果/导入中心/阅读器/播放器的 token 在实际 `onDismiss` 才释放，上一层关闭前不呈现下一个选择器。复制单选为普通入口，批量独立。UIKit delegate 当场发出一次结果，`nil` 为主动取消，非 nil 空集合显示明确错误。系统修书/字体/还原各自的 picker 保留其任务、权限和确认语义。
2. 选中后首个可见更新为「正在准备文件」，随后显示当前文件及阶段「正在读取」「正在解析并保存」。只对可计数部分显示“已处理 n/m”，等待 provider 时用不定进度。队列行显示等待、处理中、已加入、失败原因。选择器取消返回原处。完成提供「查看逐项结果」「前往书库」「重新选择失败文件」。关闭提示后从添书仍可回到本次最近结果。以 `AppModel.beginImport/importFiles`、`FeedbackOverlay`、`ImportReport`、`BookImporter.readCoordinated` 为落点。
3. 保留现有取消语义。关闭状态面板只收起进度，已开始的批次按现有流程完成。失败重选产生新请求，不复用过期 URL。新增运行中「停止剩余导入」及取消 API 属于可选未来工作。
4. security scope 覆盖异步处理全程并平衡归还；`NSFileCoordinator` accessor 内同步复制实际交付的可读 URL，解析使用独立快照。再次校验 owner/generation，保留书库恢复互斥、临时文件回收、部分成功及原 EPUB staging/digest。取不到或未下载、权限撤销、损坏/格式不支持、存储不足分别给用户能执行的下一步。历史说明用于定位可疑节点；用户曾遇到选完无响应且无报错，设备上的复现、根因和修复结论仍待取证。见 [导入历史回归](../LOCAL-IMPORT-REGRESSION.md)。

## 3. 实施工作包与默认决策

| 优先级 | 工作包与源码入口 | 完成条件 |
| --- | --- | --- |
| P0 | 底座与全局状态。`Theme.swift`、`TingyeApp.swift`、`Library.swift`、`GeneralSettingsView.swift` | 新令牌、动态布局、系统外观、反馈及解锁焦点。导航、锁、外部打开和持久化时机通过现有入口保持可达。 |
| P0 | 书库/导入/详情。`ShelfView.swift`、`Sources.swift`、`LibraryViews.swift`、`AppModel.swift`、`BookImporter.swift` | 新书目层级、续读和选中状态，搜索、详情和整理无丢项。根 picker、忙碌与逐项进度、选择器取消及失败重选可经每个入口完整运行。 |
| P0 | 阅读与定位。`ReaderView.swift`、`ComicReaderView.swift`、`OriginalBookView.swift`、`ReaderAnnotations.swift`、`Readium/ReaderRouter.swift`、`Readium/ReadiumReaderView.swift`、`Readium/EPUBNavigatorHost.swift` | 三路径独立验收。页位、附件、原始 Locator、目录、自由选段、五色和跟读均存续。先稳定视口再改外观，按实际能力显隐。 |
| P1 | 播放与摘记。`PlayerView.swift`、`TingyeApp.swift`、`SpeechPlayer.swift`、`Readium/ReadiumSpeechBridge.swift`、`NotesUnifiedView.swift`、`DailyQuoteCard.swift` | 统一听读入口，暂停/定位/音频路由依原语义。全局和书内摘记、分享与导出完成闭环。 |
| P1 | 我的、设置、连接与数据。`StatsView.swift`、`ReadingCalendarView.swift`、`MenuSettingsView.swift`、`Typography.swift`、`TxtRulesView.swift`、`SMBBrowser.swift`、`ICloudBackup.swift`、`StorageView.swift` | 设置和连接字段、统计口径、平台提示及确认语义均有对应矩阵项，深浅和大字号通过。 |
| P2 | 覆盖与签收。`TingyeTests/`、`TingyeUITests/DesignFlowTests.swift`、现有验证脚本和工作流 | 逐矩阵行记录源码、状态样例、验证出处及遗留项；结果按实施 SHA 归档。 |

单栈和共享目的地负责导航，阅读与播放保留根级呈现所有权，减少 Modal 竞争。Readium 和原生工具按引擎能力展示，文档未列的新功能需另立范围，AI 对话和新增后端均排除。视觉及路由实现先保留现有辅助功能标识和读听状态契约，后续分包接线；本地化沿用 `Tingye/Resources/Localizable.xcstrings`。数据默认零 schema 迁移。保留读/听两个位置、原始定位及版本、书籍与摘记 ID、已读标记、统计、分组/手动排序、隐藏与锁、纸色字体、来源与云语音既有配置、备份及 Keychain 边界。`Models.swift`、`Services.swift` 的 `LibraryDisk`、`Library.swift`、`ICloudBackup.swift`、`Readium/LocatorMigration.swift` 和 `PublicationStore.swift` 继续负责读写与兼容。若后续确实需要持久化新字段，默认采用可选字段、旧版本 fixture 解码、幂等且可回滚操作；先在隔离书库比对重开前后，再验证 148 → 实施版原地升级、失败中断、同 ID 修复和备份回读。清理只能删除可重建缓存，保留原 EPUB 字节和被打开的 publication。

## 4. 后续验证门槛

1. 实施后先本地审查差异、全部矩阵路由、源注册和本地化，运行 `git diff --check`、`scripts/verify-swift-sources.py` 和发布守卫单测 `scripts/test_release_provenance.py`。历史 `scripts/check-redesign-structure.py` 锁定旧 Readium 提交、构建 143 和旧套件计数，记录其适用范围，以 148 为对照逐条核查当前源成员、引擎与数据边界、单 picker 和套件保全等约束。发生差异时记录具体原因与等效证据。对照 `NativeCoreTests`、Readium 定位/偏好/原包/备份测试及 `DesignFlowTests`，保留现有 fixture 和断言意图；新增测试覆盖新导航语义、选择器取消、批次部分成功及真实 Files 的缺口。证据用到达页面、实际文本/图像、位置和进度结果，拒绝跳过、削弱断言或降低守卫。
2. 由协调方授权并选定提交后运行 `.github/workflows/tests.yml` 的完整 `TingyeTests`（macos-15/Xcode 26.3）和 `TingyeUITests`（macos-latest）。当前测试入口含 `pull_request` 与两个历史分支的 push 过滤，本分支直接 push 不会命中过滤。若 PR 事件执行合成 merge SHA，须采用经协调方授权的精确 SHA 触发路径，或以实际经验证且最终交付的同一提交为准。核对运行 `head_sha` 和两 job 的 checkout SHA 都等于实施 SHA，检查两个 job 成功、xcresult 中无跳过且原有回归齐全。保存 run、SHA、Xcode/模拟器版本、suite 计数、两份 xcresult 和失败处置。任何交付源码变化均重新跑同 SHA 全套测试。
3. 模拟器验证不能代替设备。实体 iPhone 至少覆盖本机 Files、已下载/未下载 iCloud Drive、实际第三方 provider、系统 SMB、Open In、WiFi/应用内 WebDAV/OPDS/SMB，含取消、权限拒绝/撤销、混合批次、重选和返前台。另验 iCloud 双机冲突和后台时序、Face/Touch ID 或设备密码、系统朗读资源、云语音失联、后台/锁屏和音频中断、AirPlay/通知、低存储、VoiceOver 与大字。记录设备/iOS、安装 build/同源 SHA、入口、阶段、错误状态及脱敏结果。原位升级和设备差异单独留证，逐项关闭故障。
4. SHA 守卫继续以 `scripts/verify-unsigned-source.py` 和 `.github/workflows/build-unsigned-ipa.yml` 的构建及发布双校验为准。若另行授权交付，核对 `expected_sha`、源 provenance、测试 run、IPA SHA-256、tag 指向和不可覆盖旧 release。各实施里程碑的交付权限由协调方另行确认。
