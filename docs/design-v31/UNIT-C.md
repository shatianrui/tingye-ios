# 听页 v31 · 单元 C：阅读线续跑审计与补完

依据：`Design/v31-anthropic/DESIGN.md` §6.4–§6.7、§7，沿用 §1 陶土纪律、§5 组件。

本轮从被重启打断的工作区继续，没有重做已完成的构图。进入时只读通读了全部 9 个文件的 diff（+539/−405），并检查了对应调用、ReaderPaper.resolve、ReadiumPreferencesBridge 和受影响的测试。没有提交、切分支、暂存或恢复文件；构建号保持 **144**。

## 1. 接手时审计与本轮完成情况

| 原始要求 | 接手时状态 | 本轮处理与最终状态 |
|---|---|---|
| 原生无底顶栏、宋体章名 17、两行 | 已完成构图 | 保留；修复无底顶栏在 App 外观与阅读纸明暗不同时的前景色，正文墨/副墨/陶土字随纸面解析。专注快捷字也随纸面解析。 |
| 原生整面底板、SheetChrome、章进度与前后章 | 已完成 | 保留 SheetChrome 上沿、整面 surface、ProgressLine 加粗变体、墨色滑块与两端等宽页/章数。拖动提交与辅助功能调整逻辑不变。 |
| 原生功能行选中陶土字 | 已完成 | 保留目录、排版、摘记、听书、更多五列和大字号两列；不新增亮度入口或改既有导航。 |
| 原生划线白卡、陶土/墨/灰与形状区分 | 已完成 | 保留浮层白卡、圆/圆角方/空心胶囊、选中勾、文字名称与 SegmentedBar；旧键仅映射显示，无存量数据迁移。 |
| 原生目录当前章陶土字 + SealDot、分段 | 已完成 | 保留当前章宋体陶土字、在读点及文字；章节/书签/笔记/插图用 SegmentedBar。 |
| 原生跟读 claySoft + 左 2pt 陶土线 | 半成品 | 上轮已加入分页/滚动竖线及动态 claySoft，但分页入口仍传旧的陶土透明色。本轮改为 prefs.highlight；分页竖线移至本行所有背景画完后绘制，避免后续 run 背景覆盖竖线；重设滚动正文时清理新增的竖线绘制范围。切句、跟随和定位逻辑不动。 |
| Readium 顶栏、底板、目录对齐 | 已完成构图 | 保留；无底顶栏前景与书签强调字改随 palette，实体面板仍走 Theme。 |
| Readium 偏好 SegmentedBar + Chip + 白卡滑杆 | 已完成 | 沿用共享 ReadingPreferencesView（Readium 不显示原生预览）；字号/行距/字体/纸色等分组、墨色 Chip、翻页 SegmentedBar、ProgressLine 滑杆均保留。 |
| Readium CSS 与跟读强调 | 已完成 | 保留 palette 输入、链接/选区 CSS 注入及跟读 decoration 的 claySoft/2px 陶土边；原有 Readium 偏好桥已调用 resolve，无须改桥或路由。 |
| 漫画黑底与深色 chrome | 已完成 | 保留黑画布、强制深色外观、半透明夜间 surface 栏、发丝线、宋体等宽页码、陶土进度和夜间 PaperCard 缩略图；当前页数字明确使用 clayDeep 字令牌。 |
| 播放器纸面、封面大卡、宋体 22、圆形 ClayButton、Chip 行 | 已完成 | 保留；把已有句序/估算剩余时间放在进度线两端，数字等宽。主屏进度为墨色 ProgressLine，保证播放/暂停圆钮是唯一陶土面。 |
| 迷你听条 surface2 + 顶发丝线 | 已完成 | 保留；副行用 ink2，加强 surface2 上的文字层级。原生阅读内听条也保留同一语言，修复其实体浅面板误用深纸亮字的问题；自动翻页浮签改取面板副墨。 |
| 语音设置 HairlineRow、试听文字按钮、选中行 | 已完成 | 保留 HairlineRow、TextButtonStyle、当前音色 claySoft + 左侧陶土竖线与勾；选择器、服务配置、试听和保存语义不动。 |
| ReaderPaper §7 改值 | 色表已完成，消费端未收齐 | 七纸色表原样保留；补齐分页跟读和无底顶栏的纸面解析消费端。详见下表。 |
| 旧测试期望 | 未动 | 本轮更新三处受影响测试，逐项见 §4；不删断言、不降低对比度阈值。 |
| 源码成员核对、单元 C 报告 | 未完成 | 本轮执行 verify-swift-sources.py，退出 0；产出本文。 |

## 2. 逐屏可见变化与陶土点

“面”按正在发生的语义部件计数：一条进度线、一个 SealDot、同一当前句跨行的竖线分别算一处；陶土字和 claySoft 不计实色面。用户已有的书封/插图、存量标注内容不是新增装饰色块。以下列明所有主动加入的 chrome 强调点；没有新增渐变或陶土卡底。

| 屏/层 | 可见构图变化 | 陶土实色面 | 陶土字、淡底及双通道 |
|---|---|---|---|
| 原生阅读主屏（chrome 开启） | 顶栏去底去框，章名两行；底部整面 SheetChrome，五项无底功能行 | 章进度 1；朗读时当前句左竖线 1，合计 ≤2 | 已标书签形状；当前功能/专注文字；跟读 claySoft 带。隐藏 chrome 时只剩跟读竖线。 |
| 原生目录 | 原彩色胶囊改中性 SegmentedBar；宋体章节行 | 当前章 SealDot 1 | 当前章标题/序号陶土字、claySoft 当前行；“在读”文字和正在朗读图标。 |
| 原生/Readium 选段浮层 | 白卡、宋体选段、工具与线型分段、墨底保存动作 | 陶土圆形色样 1 | 墨色为方、灰色为空心胶囊；名称、勾与选中淡底共同表意。其他两个色样不计陶土面。 |
| 原生/Readium 排版面板 | 白卡分组、墨色字体 Chip、中性分段、纸面样本 | 浅纸常亮 Toggle 开启时 1 | 纸样墨色边框与勾；其余滑杆为墨色，未叠加陶土滑块。 |
| 原生更多工具/自动翻页面板 | surface 实体浮层，宋体区块标题、墨色工具 | 0 | 开启项勾为陶土字；自动翻页浮签使用实体面板墨色。 |
| Readium 主屏 | 无底宋体顶栏、整面 SheetChrome 底板、墨色滑块 | 章进度 1；朗读 decoration 左边 1，合计 ≤2 | 书签/功能选中字；链接强调；选区与当前句 claySoft。固定版式不注入重排正文 CSS。 |
| Readium 目录/书签/摘记抽屉 | 原连续分区改 SegmentedBar；宋体目录 | 当前章 SealDot 1 | 当前章陶土字 + claySoft；书签/摘记沿用原数据、删除与定位处理。 |
| 漫画主屏 | 黑画布、半透明暖墨栏、宋体等宽页码、中性操作面 | 页进度 1 | 书签和操作选中为陶土字/图标 + 形状；选中操作用 claySoft。 |
| 漫画缩略图/书签 | 夜间 PaperCard、SegmentedBar、宋体页码 | 当前页 SealDot 1 | 当前页数字、书签图标陶土字；在读文字。 |
| 播放器主屏（含小屏/大字号分支） | 封面由左侧小图改居中 heroRadius 大卡、宋体书名 22、跟读白卡、工具胶囊 | 圆形播放/暂停 ClayButton 1 | 朗读状态陶土字；工具选中为墨底纸字；主屏进度刻意用 ink2，符合 §6.7“本屏唯一陶土面”。 |
| 播放器目录 | 宋体当前章、进度操作与在听点 | 章节滑杆 1、当前章 SealDot 1，合计 2 | 当前章陶土字、当前行 claySoft、“正在听”文字。 |
| 迷你听条 | surface2 整面沉底、顶发丝线、宋体书名；底细进度为墨色 | 0 | 控制与副行用墨梯度，不追加陶土播放底。 |
| 语音设置首页/云配置 | 白面分组、HairlineRow、试听 TextButton | 0 | 服务状态和试听陶土字，保存为墨按钮。 |
| 语音音色详情 | 当前音色改淡底横行 + 左线，取消色块图标底 | 选中行左竖线 1 | claySoft 当前行、勾、当前音色名称；系统/云端选择器保留。 |
| 语速详情 | 白面组、等宽倍速、墨色偏好滑杆 | 0 | 倍速读数陶土字；不新增陶土滑块。 |

Readium 搜索结果的强调沿用既有陶土字色/高亮 decoration，没有新增陶土按钮或卡底。共享 NotesList/NoteEditor 的内容卡、编辑、删除与搜索行为没有为本单元另做重设计。

## 3. ReaderPaper 改值表（接手时已落入，本轮保留并核对）

每格顺序为 **背景 / 主字 / 副字**，均为十六进制 RGB。旧值取本单元开始前的仓库版本；新值为本次最终 resolve。

| 纸键/名称 | 日间旧值 | 日间新值 | 夜间旧值 | 夜间新值 |
|---|---|---|---|---|
| paper 默认 | FAF9F5 / 1C1B18 / 6E6A5A | FAF9F5 / 191817 / 6B6960 | 141413 / EFEDE6 / 99968A | 131211 / F5F3EC / 9C988E |
| mist 雾灰 | E6EBF1 / 14181F / 666666 | ECEDE8 / 191817 / 4A4741 | 1D2733 / D8E2EC / 93A3B5 | 242522 / F5F3EC / 9C988E |
| ancient 旧书 | F3E7D6 / 2C2418 / 6E5F4B | F2ECE0 / 191817 / 4A4741 | 2A2118 / EAD9BE / B39B78 | 29231D / F5F3EC / 9C988E |
| eink 浅灰 | F0F0F0 / 242424 / 666666 | F1F0EB / 191817 / 4A4741 | 1E1E1E / E8E8E8 / A8A8A8 | 1E1C1A / F5F3EC / 9C988E |
| white 纯白 | FFFFFF / 14181F / 666666 | FFFFFF / 191817 / 6B6960 | 000000 / EFEFEA / A9A9A2 | 131211 / F5F3EC / 9C988E |
| blue 深蓝 | 1A2C3A / D5E4F0 / 8AA0B4 | 242A2C / F5F3EC / C9C5BA | 同旧日间 | 同新日间 |
| night 夜读 | 101012 / EFEDE6 / A5A296 | 131211 / F5F3EC / 9C988E | 同旧日间 | 同新日间 |

默认纸精确为 **#FAF9F5 / #131211**。雾灰去冷蓝，旧书减黄，深蓝降低蓝饱和度；原本无彩的浅灰改为极低饱和暖灰。纯白保留命名对应的白纸，夜读收归暖炭墨；不为零饱和纸凭空加浓色。七个 rawValue、名称、顺序、深纸判定、用户存储键和“浅纸常亮”决策不变；没有新增纸或重置用户选择。

文字全部取规范 ink 梯度：日间主字 ink，副字 ink2/ink3；夜间主字 ink，副字 ink3，深蓝副字 ink2。强调按最终纸面明暗解析：

| 语义 | 浅纸 | 深纸 | 消费端 |
|---|---|---|---|
| 跟读底/选区底（Palette.highlight） | F7EAE3 | 3E2A21 | 原生分页/滚动 prefs.highlight、Readium speech decoration、注入 ::selection |
| 强调字（Palette.accent） | AC4A26 | F0AD88 | 原生无底顶栏状态、Readium 顶栏/链接 CSS |
| 当前句竖线 | D97757 | D97757 | CoreText/UITextView、Readium speech 模板 2px 边 |

原生通过 ReaderPaper.color → resolve；ReadiumPreferencesBridge 和 ReadiumReaderView 同样使用 resolve，EPUBNavigatorHost 接收该 palette。没有另起纸色表。固定版式仍仅设置画布/跨页，保留出版物内部色彩。

## 4. 旧值测试期望逐条更新

1. `ReadiumPreferencesTests.testEveryPaperResolvesExactDayNightAndAlwaysLightColors`：上表七行、日夜共 42 个背景/主字/副字字段更新到 v31；保留七纸 × 日夜 × alwaysLight 的 28 组决策及 bridge 背景/文字/theme 一致性检查。增加 claySoft 与 clayDeep 的精确 hex 期望；期望表独立书写，没有调用生产 resolve 来生成期望。
2. `NativeCoreTests.testReaderHighlightUsesPaperAppearanceInsteadOfAppAppearance`：保留竖线 #D97757 的精确断言；旧半透明带 alpha 0.14/0.26 更新为精确、不透明 claySoft #F7EAE3/#3E2A21（alpha 1）。按全部浅纸的实际日夜解析与 alwaysLight 检查，不再误把“仅默认纸跟随外观”当规则；测试恢复原 UserDefaults 值。增加跟读底上主字 **≥4.5:1**，不是取消可读性约束。
3. `ReadiumLocatorTests.testFiveColorsLegacyGreenAndThreeDecorationStyles` 改名为 `testThreeTonesLegacyColorsAndThreeDecorationStyles`：旧的五色加绿色固定数量 6 已不适用。独立断言新调色盘恰为 clay/ink/gray；显式覆盖新三键和 yellow/blue/pink/purple/green 五个历史键，共 8 个，各跑 background/underline/wavy 三种样式。校验历史键的外观映射、每条 ID/tint/style、未定位列表和分组隔离，数量从 6 更新为 8，不丢弃旧色兼容覆盖。

`testFocusTextContrastInBothAppearances`、`testFocusReadingPapersHaveReadableTextInBothAppearances` 的配对和 **≥4.5** 阈值均未修改；没有跳过、删除或 expectedFailure。字体、路由、定位、跟读及原书测试输入不做批量替色。

## 5. 实际验证与边界

执行 `python3 scripts/verify-swift-sources.py`，退出码 **0**：

```text
PASS 56 target Swift files; Tingye=48, TingyeTests=7, TingyeUITests=1
INFO 25 standalone Design tools excluded from app/test Sources
```

没有新增 Swift 文件，所有变更源码和测试均已有正确 Sources 成员；无需修改 pbxproj。该检查沿 target → Sources → BuildFile → FileReference → 磁盘文件核对，同时检查漏项、重复及错误 target。`git diff --check` 通过。

另外用 Python 标准库静态读取生产色表与独立测试表，比对全部 42 个字段，并按项目 UIColor.relativeLuminance 相同的 sRGB 线性化公式遍历 28 种纸面/外观/alwaysLight 组合：

| 配对 | 最低对比度 | 阈值 |
|---|---:|---:|
| 纸面上主字/副字 | 5.2255:1 | ≥4.5 |
| claySoft 跟读底上主字 | 12.1401:1 | ≥4.5 |
| 纸面上 clayDeep 强调字 | 4.7441:1 | ≥4.5 |
| 迷你条 ink2 / surface2（日间） | 8.0398:1 | ≥4.5 |

历史 `UNIT-A.md` 写的日间 ink3/surface2 4.1727 与当前 hex 的复算不符：当前 #6B6960 / #F1EFE7 算得 **4.7817:1**。本轮未改旧报告、全局色令牌或其测试断言，也不把历史文档里的静态数值当 XCTest 结果。迷你条改用 ink2 是本屏副行的层级选择。

环境为 Linux，无 swift、xcodebuild 或 iOS 模拟器；没有安装工具包、没有发起外网安装。**未执行 Swift 编译、XCTest、UI 测试或模拟器截图**。以上通过项是源码成员、文本静态核对与颜色数学检查；尚不能声称 iOS 构建/逐屏视觉验收通过。后续 iOS 验收需覆盖深纸配浅色 App、浅纸常亮、横屏/最大字号、小屏工具滚动、CoreText/UITextView 跨行竖线、Readium 换资源后的 CSS/跟读呈现和漫画 RTL 进度。

## 6. 未动项与理由

- `ReaderRouter.swift`：既有分流已满足漫画/PDF/EPUB/原生的边界，本单元只改视觉；原路由测试保留。
- `ReadiumPreferencesBridge.swift`：已经通过 resolve 共享纸色，固定版式保护仍在；色表变化自动生效，无须重复修改。
- 播放器不新增伪造的累计播放时钟：SpeechPlayer 对外给出的真实展示是句序和按句首估算的剩余时间。保留这些文案及估算语义，只将其等宽排在进度两端；未为满足“时间两端”扩展数据或播放逻辑。
- 原生功能行保留既有目录/排版/摘记/听书/更多；亮度等工具保留在“更多”。没有因规格概括性列举而替换现有功能或改名、改导航。
- 语音原生 Picker 继续负责实际系统/云端音色选择；当前音色摘要行采用选中视觉，没有把选音色改为新流程。
- 书库线、摘记独立页、统计、全局设置和其他屏没有修改；ReaderAnnotations 中共享 NotesList/NoteEditor 的既有界面不扩展为单元 D 工作。
- `SpeechPlayer`、数据/导入/存储/同步、Readium Locator/导航请求/桥接、分页与手势判定、跟读切句与定位逻辑、用户偏好结构/默认值均不改。新增的 speechRange 只用于绘制竖线，不参与阅读位置。
- App 图标、构建号 144、工程成员、workflows、依赖锁定与构建脚本均不动。
- 未运行历史 `check-redesign-structure.py`：该脚本固定旧 143 基线，并要求 ReaderPaper/阅读绘制字节不变，与本次明确授权的 §7 色值及跟读外观修改不相容；没有放宽或改写此脚本。构建成员使用任务指定的 verify-swift-sources.py 核对。

最终交付为原有 9 个 Swift 文件的续改、3 个受影响测试文件与本文；没有新增依赖或生产源码文件。
