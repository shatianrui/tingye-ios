# 听页 v31 · 单元 D：其余界面与 App 图标

唯一设计依据：[DESIGN.md](../../Design/v31-anthropic/DESIGN.md) §1–§5、§6.8–§6.12、§8。只读取本规范、当前实现及 A/B/C 交付记录；没有读取旧设计包或旧设计分支，没有执行 git 命令。

交付状态：D 单元视觉实现、图标与静态核对已落地。**没有执行 iOS 编译或模拟器视觉验收；陶土严格逐处计数有两组规范冲突，下文明确列出，未标为全部通过。**

修改 14 个既有 Swift 文件；新增 Swift 文件 **0**，没有修改 Xcode 工程。新增设置构图 `SettingsPage` / `SettingsGroup` 放在原有 Sources 成员 `GeneralSettingsView.swift` 内，仅组合 A 的 Masthead、PaperCard、HairlineRow、SectionHeader，不增加令牌、色板或按钮语言。

## 逐屏改动与可见差异

| 页面 | 最终构图与肉眼可见变化 | 功能边界 |
|---|---|---|
| 摘记 `NotesUnifiedView` | 「摘记」眉题 + 宋体 28 Masthead；墨色选中 Chip 行；独立 PaperCard，引用类 3pt 陶土左线、书签类发丝线；宋体 17 引文、ink3 书名/章/日期时间出处；笔记改中性沉底；空列表与无匹配用 EmptyState | Chip 仅过滤当前列表，未持久化或迁移数据；搜索、按书分组、时间倒序、导出、跳转、滑动删除与确认继续使用原 API |
| 我的 `StatsView(ji: true)` | 报头配摘要 PaperCard，StatBlock 藏书/累计时长/连续天数三联；月度大数字改宋体；入口去块状底、改 HairlineRow 与 ink4 右箭头；无本机书籍的寄语改无卡壳编辑引文 | 统计数据来源、书摘/设置/足迹路由、返回闭包不变；复用 B 已完成的 DailyQuoteCard，未改组件 |
| 阅读足迹 `StatsView` | 28pt Masthead + 同款摘要卡；日/周/月/年/全部改墨色 Chip；时长、概览、排行数字改宋体；图表改墨色/中性两档；每日目标改白卡细线；无记录图表和逐次记录用 EmptyState | 区间、偏移、会话、排行、目标计算、JSON 导出保持原样 |
| 阅读目标面板 | Masthead + 分组 PaperCard/HairlineRow；常用分钟改 Chip；通知权限异常增加 dangerSoft 文字签 | 原 Stepper 全范围、提醒时间、通知请求、保存/取消与 detent 保留 |
| 阅读日历 | 月标题宋体；月格增加 0.5pt 网格；无读日留空、读日 claySoft + 墨字；今天陶土圆环，选中日另用墨色边框；达标下划线仍以形状标记；日明细 HairlineRow，月摘要 StatBlock 三联 | 日期可选范围、月切换、目标判定、记录与汇总计算不变；没有绿色梯度 |
| 专注开始 | 54pt 宋体等宽计时面，3pt line 轨道；书名 ink3；目标改 SegmentedBar；开始改 ClayButton | 原 25/45/自定义、10…90 分钟 Stepper、开始后关闭面板的行为保留 |
| 专注进行中 | 同款宋体计时 + 极淡陶土进度圆环；结束改 SecondaryButton，放弃保留文字动作 | 没有添加暂停状态；仍按原 15 秒 Timeline 刷新、原到时完成规则运行，不改统计写入 |
| 专注其他书/小结 | 其他书提示改 EmptyState；完成分钟改宋体 54；寄语去色卡，改陶土左线编辑引文；继续/合上书仍用主/次按钮 | 会话清理、结束另一场与继续阅读闭包原样 |
| 读完 `BookFinishView` | 34pt 宋体「读完」报头；新增 StatBlock 用时/摘记/划线三联；PrimaryButton「回书房」及 TextButton「写一句」；引文去大面积色底和分享下划线；输入框统一 radiusField/lineField | 原总时长/读完天数摘要保留；摘记列显示附笔记标注数，划线列显示全部标注数，直接由已有记录派生；读完感加载/保存/删除、换句、原文定位、分享、下一本选择不变。「写一句」只聚焦原 TextEditor；「回书房」调用既有关闭本书闭包 |
| 设置目录 | 系统分组列表改 Masthead + 五组 PaperCard；入口 HairlineRow、无底墨色图标、ink4 箭头 | 目的地、导入 sheet 和文件导入呈现门控原样 |
| 通用设置 | 28pt Masthead + 语言/首页/目标/漫画/交互白卡；Toggle 着 clay，漫画选择改 SegmentedBar；说明移到组外 ink3 | 原 AppStorage 键、默认值、系统语言设置入口、漫画模式值不变 |
| 菜单 | 28pt 报头；每个可重排项用 PaperCard + HairlineRow；编号等宽；默认状态 claySoft 文字签；恢复默认改文字按钮 | 保留 List、始终编辑模式、onMove、至少保留一项及原 save；没有用 ScrollView 破坏拖动排序 |
| TXT 分章规则 | 28pt 报头；白卡/发丝线规则行；最大字数增加常用 Chip，并保留完整 Stepper；输入框统一令牌；无效正则为 dangerSoft 文字签；章节预览用宋体与等宽编号 | 保留 List 及规则 swipeActions；编译/预览算法、规则选择、添加/删除、原上限下限和存储键不变 |
| 空间整理 | 宋体 StatBlock 总量；3pt 三段用量条 + 名称/数值/色样图例；分项改 HairlineRow；修复索引独立；清理集中到危险组、danger 字 | 单项清理按规范新增确认，全部清理保留原确认；确认后仍调原 clear，统计/扫描算法与 EPUB 缓存保护不变 |
| 备份与同步 | 28pt Masthead + 保存/恢复/自动同步 PaperCard；入口发丝线；Toggle clay；移除恢复说明大陶土底；操作阶段与上传用 EmptyState；进度为中性 ProgressLine，时间等宽；失败与同步问题有 dangerSoft 签和文字 | ICloudBackupView 之前的全部备份/还原/同步实现逐字保留；导出、查找、从文件恢复、替换确认、取消、重试、刷新和固定底部备份按钮保留 |
| 隐私与关于 | 28pt Masthead + 隐私/关于/导出白卡；应用锁 Toggle clay；版本/构建号等宽；政策与许可入口陶土字、ink4 箭头；展示紧凑原生导航栏 | 设置路由与导航层级不变；隐藏书验证/重新隐藏、数据导出闭包不变 |
| 外观 | 宋体报头、三项 PaperCard + HairlineRow；选中用墨色勾；缩略预览直接消费 v31 Theme，清除硬编码旧预览色值 | 三个模式与 app.appearance 存储、切换动作不变；缩略图局部指定明暗，仅用于预览 |
| 字体管理 | 28pt Masthead；字体示例去陶土大底，改白卡；自定义字体与导入入口发丝线；无个人字体用 EmptyState | 字体注册/导入/删除实现、文件选择与 reader.font 不变 |
| 开源许可/隐私政策 | 28pt Masthead；许可链接用陶土字、发丝线；政策正文统一 PaperCard 与令牌间距 | 授权清单、版本、资源名、网址、许可全文及政策文字原样 |
| 根壳/反馈 | WindowGroup、根栈及顶部 chrome 为纸面；导航栏背景 bg、边界 line，标准/滚动边缘/紧凑外观一致；「我的」去胶囊色底；忙态为 EmptyState loading，错误为 EmptyState error（dangerSoft 标题底签 + 警告形状 + 原错误文字） | 原 NavigationStack、阅读 fullScreenCover、播放器/导入 sheet、原生错误 alert、后台任务和文件导入门控保留；系统 alert 仍负责原先的模态关闭语义 |
| 应用锁 | 材质遮罩换实体纸面；无底墨色锁图标；宋体 EmptyState；验证时共享加载态 | 生物验证/锁定状态/前后台策略逐字不变，未触及 Library 的持久化部分 |

## 陶土逐屏清单

数字按**实际独立填色图元**说明，不把重复线条、系统开关自动折算成“一类”。淡底、文字、描边单列。

| 页面 | 实色面/线点 | 淡底、字或描边 |
|---|---|---|
| 摘记 | 每张可见引用类卡 1 条陶土线，总计 n；书签为中性线，无陶土按钮 | 报头眉题、导出/回到原文字；Chip 选中墨色 |
| 我的 | 编辑引文左线 1（实际摘句或无书寄语二选一） | 摘句动作字；其余摘要/入口/月度数字为墨色 |
| 阅读足迹 | 每日目标已读段最多 1；图表为墨色，无额外陶土柱 | 修改/日历字、进度与排行说明字 |
| 阅读目标 | 提醒 Toggle 开启时 1 | 常用 Chip 墨色；权限失败用 danger/dangerSoft |
| 阅读日历 | 实色填充 0 | 读日 claySoft；今天陶土描边 1；所选日期/达标说明陶土字，选中框墨色 |
| 专注开始 | 开始 ClayButton 1 | 报头陶土字；圆环 track 为 line，初始进度 0 |
| 专注进行中 | 实色面 0 | 进度圆环 clay × 0.18；正在专注文字；结束按钮中性 |
| 专注其他书 | 0 | 报头陶土字 |
| 专注小结 | 引文左线 1 | 完成文字/报头陶土字 |
| 读完 | 引文左线 1 | 全书读完标签、换句/分享/写一句等文字；主按钮墨色 |
| 设置目录 | 0 | 入口均墨色；不使用色块图标底 |
| 通用设置 | 已开启的系统 Toggle k 个，k ∈ 0…5；默认 4 个 | 漫画选中为中性滑块 |
| 菜单 | 已开启 Toggle k 个，k ∈ 1…3；默认 3 个 | 默认签 claySoft、编号/恢复默认陶土字 |
| TXT 规则 | 0 | 选中勾、加入/预设操作陶土字；常用 Chip 墨色；正则错误 dangerSoft |
| 空间整理 | 书籍用量段最多 1、书籍图例色样 1，合计最多 2 | 清理为 danger；缓存/其他为中性色 |
| 备份与同步 | 自动同步 Toggle 开启时 1；手动传输进度墨色 | 同步状态 claySoft、各操作陶土字；失败 dangerSoft |
| 隐私与关于 | 应用锁开启时 1 | 政策/许可/导出链接陶土字 |
| 外观 | 0 | 预览、选中图标均为中性 |
| 字体管理 | 0 | 字体选中勾/导入陶土字 |
| 开源许可 | 0 | 链接陶土字 |
| 隐私政策 | 0 | 无需彩色强调 |
| 根壳/应用锁 | 0 | 系统动作 tint 为 clayDeep；错误 dangerSoft，加载墨色 |

**规范冲突，未宣称严格两处全通过：**

1. §6.8 要求每张引用卡的陶土左线；当同屏可见 3 张或更多引用卡时，n 可超过 §1 的严格逐图元两处限制。本稿保留每张卡的类别视觉，不删记录、不改卡片分类、不通过放大卡片隐藏超限。没有将 n 条线写成“只有一处”。
2. §6.11 明确要求系统 Toggle 着 clay，而通用设置有 5 个开关、菜单默认 3 个开启。开启数量由用户决定；全部使用 clay 时不能保证整屏严格 ≤2。本稿优先保留该节具体开关规格与既有开关行为，不改默认值、不把部分开关悄悄换成其他强调色。这两屏的严格数量项仍需设计裁决；没有为此新增设置页、折叠功能或改变导航。

## 全仓视觉扫尾：已改清单

- [x] D 页面直接绘制的历史色彩别名（warm/onWarm/gold/goldSoft/accent/accentSoft 等）收敛到 bg/surface/surface2/ink 梯度/clayDeep/claySoft。
- [x] 摘记按旧标注颜色绘制竖线的路径，改为引用陶土/书签发丝线的视觉分类；存量标注颜色数据不改。
- [x] 摘记类型小标签改 SealBadge；笔记说明底改中性，不铺陶土色卡。
- [x] 我的入口白色块行改 HairlineRow，右箭头 ink4。
- [x] 我的无书寄语、专注小结、读完引文去色卡，改编辑引文。
- [x] 统计周期选中陶土胶囊改共享墨色 Chip。
- [x] 统计图不再反复填充实陶土，换中性柱，保留目标进度强调。
- [x] 统计大数字、月历摘要、专注计时和存储总量改宋体；时间、版本、百分比等数字等宽。
- [x] 日历写死 10pt 圆角改 radiusSmall；日格增加发丝线，无读日取消灰块；今天与选中日期形状分开。
- [x] 设置 Form 普通分组收拢为 PaperCard/HairlineRow；菜单重排与 TXT 左滑仍用原 List。
- [x] Toggle 与 SegmentedBar 分工明确，分段选中不使用陶土面。
- [x] 存储总量取消陶土大底；清理操作从普通分项移入独立危险组，补单项确认。
- [x] iCloud 恢复说明去大面积陶土底；失败补 dangerSoft 文字/形状；进度使用共享细线。
- [x] 外观预览全部硬编码旧色值删除，改局部明暗环境中的 Theme 令牌；选中图标去彩色面。
- [x] 关于版本与构建号改等宽；链接改 clayDeep。
- [x] 字体示例区去陶土卡底；个人字体空态改 EmptyState。
- [x] 根壳顶部「我的」取消图标/文字胶囊底，保持原命中区与路由。
- [x] 应用锁去系统材质底，改实体纸面；忙态、空态、错误均使用共享语言。
- [x] D 页面圆角、容器间距、描边与按钮高度收敛到 A 令牌；没有页面自写 shadow、装饰渐变或新颜色。手绘 SF Symbol 使用 ThemeIcon；系统 Label/导航/菜单保留其系统符号机制。

保留的尺寸仅为字体大小、已有书封/图表/示意图尺寸、字号对应行间距、日历最小宽度等排版/几何规格。专注圆环直径由 space7 × 6 组合，不另立令牌。

## 全仓扫描：受红线保护，发现但未回改

| 位置 | 残留与处理理由 |
|---|---|
| `ReaderView.swift` | 插图章与目录搜索仍有 ContentUnavailableView；媒体边框有字面量 4；目录当前章仍引用 accentSoft。属于 C，原样保留 |
| `Readium/ReadiumReaderView.swift` | 状态容器仍有字面量 padding 24、圆角 12/18。属于 C，原样保留 |
| `PlayerView.swift` | 播放空态、章节搜索仍用 ContentUnavailableView；当前章仍用 accentSoft。属于 C，原样保留 |
| `ReaderAnnotations.swift` | NoteEditor 的 warm 底、NoteRow 的字面量竖线圆角、AllNotesView 的旧空态与 gold 标签。属于 C 文件及其原有摘记呈现，本轮不回改 |
| `LibraryViews.swift` 中 `ProfileView` 之前 | 详情书签目的地仍有旧空态/章节强调字与字面量间距；B 的详情/目录管理完整前缀保持逐字一致，未趁扫尾修改 |
| `TingyeApp.swift` 的 `MiniPlayer` | 图标小圆底及部分字面量间距属于 C 的已交付区块，完整类型逐字保留 |
| `Theme.swift` | 兼容别名、旧 EditorialIntro/EditorialNotice 辅助构图及内部 shadow 由 A 管理；没有修改共享层影响 A/B/C |
| 出版物、PDF/原文页面、DEBUG 示例封面与示例插图 | 属于内容图像/原书或测试素材，不把内容自身色彩当作 App 装饰令牌替换 |

## App 图标

脚本：[make-icon.py](../../Design/v31-anthropic/app-icon/make-icon.py)。仅 Python 标准库 + 环境已有 Pillow **10.2.0**，不联网、不安装依赖；可从任意目录运行：

```sh
python3 Design/v31-anthropic/app-icon/make-icon.py
```

- 保留当前已安装资产的展开书页/三段声波意象，以两片对称墨色书页和三个纸面负形声波重绘。无文字、渐变、阴影或额外图标外框。
- 浅版：bg `#FAF9F5`、ink `#191817`；深版：bg `#131211`、ink `#F5F3EC`。二者仅左上页角一个直径 32px 陶土点 `#D97757`。
- 染色版：同构灰阶输入（纸 `#F5F5F5`、墨 `#191919`、页角点 `#929292`），把着色交给系统，保留单点亮度层级。
- 4 倍采样后用 Lanczos 缩小，输出均为 **1024×1024、RGB、无 alpha**；不预切系统图标圆角。
- 三份产物保存在 [out](../../Design/v31-anthropic/app-icon/out)，同字节复制到工程 `AppIcon.appiconset`，脚本同时写浅/深/染色三个 iOS universal 槽位的 `Contents.json`。
- 已查看大图以及 64px/32px 缩略预览；没有冒充 iOS 主屏实机截图。

## 实际验证

1. 执行 `python3 scripts/verify-swift-sources.py`，退出 **0**：`PASS 56 target Swift files; Tingye=48, TingyeTests=7, TingyeUITests=1`。没有新增 Swift，没有 pbxproj 变更，已有 Sources 成员完整。
2. 14 个改动源码的词法括号/字符串/注释配对、Theme 引用名称核对通过。**这些静态检查不等同于 Swift 类型检查。**
3. 对任务开始时保存的文件快照进行范围比对：A/B/C 整屏文件、MiniPlayer 类型、LibraryViews 的 B 区前缀均未改变；FocusSessionStore、备份/同步实现、字体底层、GeneralSettings 常量与通知实现的前缀逐字一致。
4. 核对 28 个原有派生/存取/行为区块（导出、专注、目标、TXT 添加删除、存储扫描清理、会话统计、启动走查等）与全部 AppStorage 声明，均与快照一致。设置布局所需的过滤/焦点/确认只在 UI 层。
5. 图标三槽 JSON、1024 尺寸、RGB 无 alpha、染色灰阶、安装副本与产物同字节检查通过；浅/深版以允许抗锯齿误差的颜色距离掩码检查为单一陶土连通图形。重跑脚本，资产和 JSON 哈希完全相同。
6. 任务起始文件哈希清单核对：既有改动仅限 14 个 Swift 文件和 AppIcon 的 3 个 PNG/Contents.json；新增仅图标脚本/3 份产物与本文。Theme、测试、构建号 **144**、工程文件、workflows、依赖锁定未动。

本机 Linux 无 `swift`、`xcodebuild`、iOS SDK/模拟器；**未执行构建、XCTest、UI 测试或逐屏模拟器截图**。不运行会依赖旧基线或 git 的历史结构脚本，不为可逆视觉修改添加实现镜像测试。

## 未动项、偏差与后续验收

- 原有专注状态机仅 idle/running/finished，无暂停。按“仅视觉、不改行为”红线保留，未为规范的“开始/暂停”添加持久化字段、暂停逻辑或伪按钮；仅开始使用 ClayButton，结束使用 SecondaryButton。
- 没有现成删除备份入口，故未凭空新增删除功能；既有覆盖恢复继续二次确认。原生文件选择器、分享、确认框与全局错误 alert 保留系统行为；全局 error EmptyState 提供额外视觉语境。
- 没有自然动作的 EmptyState 只显示标题/说明，不为凑 PrimaryButton 新增导航或功能；已有重试、导入等动作保留在原位置。
- 菜单与 TXT 用列表中的 PaperCard 行，保留重排/滑动交互；没有把它们强行合成导致手势失效的单个滚动卡。
- §1 陶土严格计数与引用卡/多开关的冲突见上表；其余 D 页面按列出的实际数量最多两处实面。
- A/B/C 残留仅记录，不回改。全仓扫尾不等于宣称受红线保护的所有残留已消失。
- 待 iOS 环境：日/夜模式、小屏、横屏、最大辅助字号；摘要三联换行；月历今日/所选/达标形状；专注四种状态；收尾聚焦输入与下一本；菜单拖动与 TXT 左滑；每种清理确认；备份传输/暂停上传/失败重试/还原确认；原生错误框与反馈层共存；导航转场纸面及系统主屏三图标外观。
