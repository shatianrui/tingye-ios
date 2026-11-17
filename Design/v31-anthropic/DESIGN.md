# 听页 v31 · Anthropic 式全界面设计（代号「暖纸」）

作者：Pax（本轮全新设计，不沿用任何既往设计包）
范围：全部界面，逐屏落地。只改视觉与构图，不改功能、导航结构、数据协议与文案语义。

## 0. 一句话主张

把整个 App 当成一张安静的书桌：**纸、墨、线、陶土**四种元素走遍每一屏。
层级靠留白与发丝线，不靠色块与阴影；标题用宋体立住编辑感，控件用系统体保持顺手；
陶土是唯一的彩色，只出现在「正在发生」的地方。

与 Anthropic / Claude 设计语言的关系：取其魂——暖象牙画布、深暖炭墨、陶土克制、
衬线大标题、几乎不可见的阴影、大量留白；但构图与组件全部按听页的阅读场景重新排定，
不是对任何现成界面的临摹。

## 1. 色彩

全梯度只许暖中性，禁止任何带蓝调的灰。白只出现在卡面与输入框，页面底永远是纸面。

| 令牌 | 日间 | 夜间 | 用途 |
|---|---|---|---|
| `bg` 纸面 | #FAF9F5 | #131211 | 每一屏的底，唯一页面底 |
| `surface` 卡面 | #FFFFFF | #1E1C1A | 卡片、输入框、浮层 |
| `surface2` 沉底 | #F1EFE7 | #292724 | 分段轨道、听条底、次级面 |
| `surfaceSunken` | #F6F4EC | #191715 | 隔行、占位、代码块底 |
| `ink` 主墨 | #191817 | #F5F3EC | 标题与正文主色 |
| `ink2` | #4A4741 | #C9C5BA | 正文副色 |
| `ink3` | #75726A | #9C988E | 说明文字 |
| `ink4` | #A3A099 | #6E6B64 | 时间戳、页脚、极次级 |
| `line` 发丝线 | #E6E3D9 | #2E2C29 | 分隔、描边（0.5–1pt） |
| `lineField` | rgba(25,24,23,.14) | rgba(245,243,236,.16) | 输入框描边 |
| `clay` 陶土面 | #D97757 | #D97757 | 进度已读段、在读点、跟读条、印章 |
| `clayDeep` 陶土字 | #AC4A26 | #F0AD88 | 链接、当前章、眉题（对纸面 ≥4.5:1） |
| `claySoft` 陶土淡底 | #F7EAE3 | #3E2A21 | 选中行、跟读带、状态签底 |
| `onClay` | #16130F | #16130F | 压在陶土面上的字 |
| `danger` | #B23A3A | #FF9FAD | 删除、错误 |
| `dangerSoft` | #F9ECEC | #382122 | 危险提示底 |
| `focus` 焦点环 | 陶土 #D97757 | 陶土 #D97757 | 本设计不用蓝：焦点 = 陶土描边 + 标签变化双通道 |

主按钮：日间墨底（`ink`）纸字（`bg`）；夜间反转——纸底墨字。
陶土按钮只允许每屏一处，且必须是该屏「正在发生」的主动作（如继续阅读、开始播放）；
其余动作一律墨按钮 / 白卡次按钮 / 文字按钮。

**陶土纪律**：每屏至多 2 处陶土面（不含淡底与陶土字）。陶土不用于：卡片底、
分段选中态、大面积按钮、装饰渐变。全 App 不出现渐变色块（封面图本身除外）。

## 2. 字体

| 角色 | 字体 | 规格 |
|---|---|---|
| 首页眉题大标题 | 宋体 `Theme.serif(34)` | Regular，行高 1.2 |
| 页标题 | 宋体 `Theme.serif(28)` | Regular |
| 区块标题 | 宋体 `Theme.serif(20)` | Regular |
| 卡片标题、书名、章名、摘句 | 宋体 `Theme.serif(17–20)` | Regular，不合成粗体 |
| 统计大数字 | 宋体 `Theme.serif(30)` 起 | 编辑数字感，不用粗黑 |
| 正文与控件 | 系统体 `Theme.sans` | 16 正文 / 15 控件 / 13 说明 |
| 眉题（kicker） | 系统体 semibold 12 | 字距 2.0，陶土字或 ink3 |
| 时间戳、页码、百分比 | `.monospacedDigit()` | 随父字号 |
| 阅读正文 | 用户偏好字体 | 不动（见 §7 阅读纸） |

层级只靠字号、留白、发丝线三件事。禁止用粗体堆层级；禁止斜体中文。

## 3. 形状、间距、深度

- 圆角：卡片 18（`radius`）；大卡与底部面板顶 28（`heroRadius`）；按钮 14（`buttonRadius`）；
  输入框 12（`radiusField`）；小标签 6（`radiusSmall`）；胶囊全圆（`radiusPill`）；
  书封 `coverRadius(w) = min(8, w×0.06)`。
- 间距刻度：4 / 8 / 12 / 16 / 24 / 32 / 48（`space1…space7`）。页面水平边距 24（紧凑 20）；
  卡内边距 20；列表行最小高 52；区块间距 32。
- 深度：先发丝线，后阴影。静息卡阴影黑 3%、模糊 24、y 6（`.softCardShadow()`）；
  浮层黑 6%、模糊 20、y 8（`.floatingPanel()`）；夜间不用阴影，靠描边提亮一档。
- 页面里禁止写死圆角/间距数字，一律走令牌；禁止自写 `.shadow()`（系统 popover 除外）。

## 4. 动效

- 只用两条：`pressSpring`（response 0.32，damping 0.86）与按压 0.2s ease-out。
- 按压反馈只有透明度 0.88，不缩放、不下陷、不回弹。
- 「减少动态效果」由既有 ReducedMotionPolicy 统一拦截，不另设开关。

## 5. 组件（本设计的组件语言，逐屏复用）

| 组件 | 规格 |
|---|---|
| `PaperBackground` | 纸面底 + 可选顶部眉题区，全屏统一入口 |
| `Masthead` | 眉题行（kicker + 右侧动作）+ 宋体大标题 + 可选副行 |
| `SectionHeader` | 宋体 20 + 右侧文字按钮（陶土字） |
| `PaperCard` | 白卡 + 发丝线 + softCardShadow，内边距 20 |
| `HairlineRow` | 行间 0.5pt 发丝线，无卡壳；左图右文或左文右值 |
| `PrimaryButton` | 墨底纸字（夜间反转），圆角 14，高 50，15pt medium |
| `ClayButton` | 陶土底 + onClay 字；每屏至多一个，见 §1 纪律 |
| `SecondaryButton` | 白卡 + 发丝线 + 墨字 |
| `TextButton` | 陶土字，无下划线 |
| `Chip` | 胶囊：选中墨底纸字，未选白卡 + 发丝线 |
| `SegmentedBar` | 轨道 surface2，滑块 surface + 发丝线，文字 13 |
| `ProgressLine` | 高 3，轨道 line，已读段陶土，圆头 |
| `SealBadge` | 陶土淡底 + 陶土字 11pt，圆角 6；状态必须带文字 |
| `SealDot` | 6pt 陶土圆点 + 文字（如「在读」），不用纯色点单独表意 |
| `CoverView` | coverRadius + 发丝线描边 + 内侧 1pt 高光线 |
| `SheetChrome` | 面板顶圆角 28、抓手条 line 色、宋体标题 20、右上关闭为无底图标按钮 |
| `EmptyState` | 宋体标题 22 + 系统体说明 14（ink3）+ 单个 PrimaryButton |
| `StatBlock` | 宋体大数字 + 眉题式标签（ink3） |
| `CircleIconButton` | 44pt 命中区，无底无描边，图标 ink2 |

图标：沿用 SF Symbols，但一律经工程既有图标映射层调用（无映射层时本轮在 Theme 建 `ThemeIcon` 枚举收口），线宽风格统一 regular。

## 6. 逐屏规格

每屏三件事必查：①构图走 §5 组件；②陶土出现点逐个点名、总数合纪律；
③与现状的可见差异——用户打开这一屏，必须一眼看出是新设计。

### 6.1 书房（ShelfView，根页）
- 构图：Masthead（眉题=日期+「书房」，大标题宋体 34「书房」）；其下「正在读」大卡：
  白卡、左封面（大圆角）、右宋体书名 + 章节行 + ProgressLine + 双动作
  （ClayButton「继续阅读」+ SecondaryButton「开始专注」）。
- 「今日一句」：不做卡片，做编辑引文——左侧 3pt 陶土竖线 + 宋体 20 引文 + ink3 出处行。
- 书架：编辑风列表/网格二选一沿用现有切换；行间发丝线、宋体书名、ink3 元数据行
  （作者 · 进度% 等宽数字）；在读书带 SealDot。
- 陶土点：继续阅读按钮、进度已读段、在读点、引文竖线（计 2 类面 + 淡底签，不超纪律）。

### 6.2 书库管理与书籍详情（LibraryViews / Library.swift）
- 详情页：Masthead 式头部（封面居左、宋体书名 28、元数据行），数据用 StatBlock 三联
  （进度 / 累计时长 / 摘记数）；操作区 PrimaryButton「打开」+ 次按钮行；
  目录预览为 HairlineRow 列表，当前章陶土字 + 左侧陶土竖点。
- 管理页：HairlineRow 列表 + 右侧文字按钮；批量操作底栏为浮层卡（floatingPanel）。

### 6.3 添书与来源（Sources / SMBBrowser / 导入流）
- 入口页：三个来源做成 PaperCard 行（图标 + 宋体标题 + ink3 说明 + 右箭头），不用色块图标底。
- SMB 浏览：HairlineRow 文件行，文件夹用 ink2 图标；连接表单为白卡 + radiusField 输入框。
- 导入进度与结果：ProgressLine + 等宽数字百分比；结果页走 EmptyState 的成功变体
  （宋体标题 + 陶土 SealBadge 计数）。

### 6.4 原生阅读器（ReaderView / ReaderAnnotations）
- 顶栏：无底，左返回 + 中宋体章名 17（两行钳制）+ 右图标组；底栏：整面白面板
  （SheetChrome 上沿）承载进度滑杆（ProgressLine 加粗变体 + 两端等宽时间/页码）、
  章节前后按钮、功能行（目录/亮度/字体/听书/更多）图标等距排布，选中态陶土字。
- 划线/书签弹层：白卡浮层，颜色点收敛为「陶土 / 墨 / 灰」三档 + 形状区分，不用彩虹色点。
- 目录抽屉：当前章陶土字 + SealDot；书签/摘记分段用 SegmentedBar。
- 跟读高亮：陶土淡底带（claySoft），当前句左侧 2pt 陶土竖线。

### 6.5 Readium 阅读器（ReadiumReaderView）
- WebView 外的全部 chrome 与 6.4 同语言：顶栏、底面板、目录、偏好面板逐项对齐；
  EPUB 偏好面板（字号/行距/纸面）用 SegmentedBar + Chip + ProgressLine 滑杆，白卡分组。
- 注入 CSS 的强调色与纸面取 §7 的值，与原生阅读器同貌。

### 6.6 漫画阅读器（ComicReaderView）
- 黑底场景保留（图片内容优先），但 chrome 走本系统：半透明墨底栏、宋体页码标题、
  ProgressLine 页进度（陶土段），面板为深色版 PaperCard（surface 夜间值）。

### 6.7 播放器（PlayerView）与语音设置
- 播放器：纸面底；封面大卡居中（heroRadius + 柔影）；宋体书名 22 + 章名 ink3；
  进度 ProgressLine + 两端等宽时间；主控行：中 ClayButton 圆形播放/暂停（本屏唯一陶土面）、
  两侧墨色快退/快进；倍速/定时/章节用 Chip 行；听条（迷你播放）为 surface2 底 + 发丝线顶边。
- 语音设置：HairlineRow + 试听按钮（TextButton 陶土字）；选中行 claySoft 底 + 左竖线。

### 6.8 摘记（NotesUnifiedView）
- Masthead（眉题「摘记」）；筛选 Chip 行；摘记卡：白卡、左侧陶土竖线（引用类）/
  发丝线（书签类）区分，宋体引文 17、ink3 出处行（书名 · 章节 · 时间等宽）；
  空态走 EmptyState。

### 6.9 我的与统计（StatsView / ReadingCalendarView）
- 头部摘要卡：StatBlock 三联（藏书 / 累计时长 / 连续天数），宋体大数字。
- 日历：月格发丝线网格，读过的日子用陶土淡底圆角块 + 墨字，今天加陶土描边环；
  热力不用绿色梯度，改陶土淡→实两档 + 无读日留空。
- 入口行（设置/存储/备份等）：HairlineRow + 右箭头 ink4。

### 6.10 专注（FocusSession）与读完收尾（BookFinishView）
- 专注：大宋体计时数字（54，等宽位宽对齐）、书名 ink3、开始/暂停 ClayButton（本屏唯一陶土面）、
  结束走 SecondaryButton；背景纸面 + 中央极淡陶土圆环进度（线宽 3，轨道 line）。
- 收尾页：宋体大标题「读完」+ 书名；StatBlock（用时/摘记/划线）；一句摘录做编辑引文（同 6.1）；
  动作：PrimaryButton「回书房」+ TextButton「写一句」。

### 6.11 设置组（GeneralSettings / MenuSettings / TxtRules / Storage / ICloudBackup）
- 统一构图：Masthead 小号（宋体 28 页标题）+ 分组 PaperCard + HairlineRow；
  开关选中态陶土（系统 Toggle 着色走 clay）；数值选择用 Chip 或 SegmentedBar；
  存储页用量条用 ProgressLine 变体（陶土=书籍、surface2=缓存、line=其他，三段带图例文字）；
  危险操作（清缓存/删备份）独立成组、danger 字 + 二次确认，不与普通行混排。
- 关于页：版本号等宽数字、陶土字链接行。

### 6.12 状态与无障碍（states / accessibility）
- 空态、加载、错误三态统一 EmptyState 语言；错误态用 dangerSoft 底签 + 文字说明（双通道）。
- 动态字号下 Masthead 标题可缩至 24，行高不裁切；所有图标按钮 ≥44pt 命中区（既有规范延续）。

## 7. 阅读纸（ReaderPaper）

七种阅读纸的结构、命名与「浅纸常亮」开关不动；纸面色值向本系统靠拢：
默认纸 = 纸面 #FAF9F5 / 夜间 #131211，与全 App 同底；其余各纸的日间值保持其性格
（米白、豆绿、羊皮等）但饱和度统一压低一档、文字色统一走 ink 梯度；
跟读高亮与划线强调统一陶土系。Readium 注入 CSS 与原生渲染共用同一组解析值（沿用既有
ReaderPaper.resolve 收口，不另起炉灶）。

## 8. App 图标

沿用现图标构图（书页/声波意象），按本系统重绘三变体（浅/深/染色）：
纸面底、墨色图形、陶土只作一个点（页角或声波首段）。资产落 AppIcon.appiconset，
制作脚本留 Design/v31-anthropic/app-icon/。

## 9. 硬规则（自检清单）

1. 页面底永远是 `bg`，不出现纯白整页底与冷灰。
2. 陶土每屏 ≤2 处面；陶土字与淡底不计面，但不得借此铺色。
3. 圆角、间距、阴影只走令牌与 §5 组件，页面不写死数值。
4. 标题宋体、控件系统体、数字等宽；中文不用斜体与合成粗体。
5. 状态一律双通道（颜色 + 文字/形状）。
6. 不改功能、导航、数据、文案语义；不改用户阅读偏好的结构与默认值之外的行为。
7. 每个既有界面都要有可见变化：一眼看不出差别的屏，视为未完成。
