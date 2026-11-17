# v31 单元 A：令牌与共享组件层

唯一设计依据：[`Design/v31-anthropic/DESIGN.md`](../../Design/v31-anthropic/DESIGN.md) §1–§5、§6.12 的共享无障碍要求。
未读取或移植旧设计分支。未执行任何 git 命令。

交付范围：现有 `Tingye/Theme.swift`、现有 `TingyeTests/NativeCoreTests.swift`、只读核对脚本 `scripts/verify-swift-sources.py` 与本文。没有新增 Swift 文件，没有修改 pbxproj。

状态：共享层实现已落地，Sources 与范围静态核对通过。**指定色值与原有 4.5:1 测试存在一项冲突，保留原断言，未将该项标为通过。** 本机为 Linux，没有 Swift、Xcode 或 iOS SDK，未执行 iOS 编译、XCTest 或截图验收。

## 1. 颜色令牌对照

值按「日间 / 夜间」排列。旧值仅来自本次任务开始时的工作区文件，用于记录修改，不作为新设计依据。

| 令牌 | 旧值 | v31 值 |
|---|---|---|
| bg | #F7F4ED / #201F1C | #FAF9F5 / #131211 |
| surface | #FFFDF8 / #292723 | #FFFFFF / #1E1C1A |
| surface2 | #EEE9DF / #34312C | #F1EFE7 / #292724 |
| surfaceSunken | 无 | #F6F4EC / #191715 |
| ink | #292724 / #F1EADF | #191817 / #F5F3EC |
| ink2 | #625B52 / #C2B9AB | #4A4741 / #C9C5BA |
| ink3 | #696158 / #BEB5A7 | #75726A / #9C988E |
| ink4 | 无 | #A3A099 / #6E6B64 |
| line | #D4CCC0 / #5A544C | #E6E3D9 / #2E2C29 |
| lineField | 无 | rgba(25,24,23,0.14) / rgba(245,243,236,0.16) |
| clay | #D97757 / #D97757 | 不变 |
| accent | #98432E / #E9A18A | #AC4A26 / #F0AD88 |
| clayDeep | 无 | accent 别名 |
| accentSoft | #F0E4DA / #3B2B25 | #F7EAE3 / #3E2A21 |
| claySoft | 无 | accentSoft 别名 |
| onClay | #141413 / #141413 | #16130F / #16130F |
| danger | #AE3D4E / #FF9FAD | #B23A3A / #FF9FAD |
| dangerSoft | 无 | #F9ECEC / #382122 |
| focus | 无 | clay（#D97757，双模同值） |

原 line 另有提高对比度覆盖值 #80776B / #A3998B；本轮 line 统一为规范指定值。新 XCTest 同时覆盖普通与提高对比度外观，防止回到未列入 v31 的色板。

### 兼容别名与封面

Theme 原有 **67 个静态符号名全部保留**，含函数的旧签名。以下是色彩兼容关系：

| 旧符号 | 旧关系或值 | v31 关系 |
|---|---|---|
| onInk、onAccent | #FFFDF8 / #201F1C | bg |
| rulePaint、cardEdge | line | line |
| link、forest、jade、indigo、plum | accent | accent |
| onForest | onAccent | onAccent（bg） |
| marker、amberOnDark | clay | clay |
| onMarker | onClay | onClay |
| readingHighlight、hero、indigoSoft | accentSoft | accentSoft |
| heroInk、heroButtonInk | ink | ink |
| wash | clay × 0.08 | accentSoft |
| warm | #EEE7DB / #322E27 | surface2 |
| onWarm、gold、ochre | #514A3F / #E0D5C4 | ink2 |
| goldSoft | warm | warm（surface2） |
| jadeSoft | #EAF6EF / #1E3327 | accentSoft |
| auroraGradient、accentGradient | 两端同为 accent | 保持签名，两端同为新 accent |
| heroGradient | 两端同为 hero | 保持签名，两端同为新 hero |
| coverColor / coverUIColor | 按字符串映射五种彩色浅纸，占位封不随夜间切换 | surfaceSunken，保留字符串参数与函数签名 |
| coverForeground | #17233A | ink |
| coverGradient 两种重载 | 相同颜色的两端 | 保留纯色语义；不生成装饰渐变 |

实际导入的封面图片仍沿用原显示路径，色板字符串与书籍数据均不修改。

## 2. 形状、间距、字体与动效

| 令牌或样式 | 旧值 | v31 值 |
|---|---|---|
| radius | 14 | 18 |
| heroRadius | 16 | 28 |
| buttonRadius | 10 | 14 |
| radiusField | 无 | 12 |
| radiusSmall | 8 | 6 |
| buttonRadiusSmall | 8 | radiusSmall（6），兼容保留 |
| radiusPill | 无 | 9999；组件使用 Capsule |
| coverRadius(width) | 封面内部 min(10, width × 0.09) | min(8, width × 0.06) |
| space1…space7 | 无集中刻度 | 4 / 8 / 12 / 16 / 24 / 32 / 48 |
| inset / insetCompact | 24 / 无 | 24 / 20 |
| cardInset / rowMinHeight / sectionSpacing | 卡 16、PaperPanel 18 / 行 52 / 无集中值 | 20 / 52 / space6（32） |
| pageWidth | 720 | 720 |
| buttonHeight / iconButtonSize | 50 / 44 | 50 / 44 |
| hairline / progressHeight / sealDotSize | 行内字面量 / 3 / 无 | 0.5 / 3 / 6 |
| rule / ruleMedium / ruleHeavy | 1 / 2 / 3 | 不变，兼容保留 |
| softCardShadow | 黑 6%，半径 12，y2；夜间黑 3% | 日间黑 3%，半径 24，y6；夜间不添加 shadow |
| floatingPanel | 黑 8%，半径 16，y4；日夜相同 | 日间黑 6%，半径 20，y8；夜间不添加 shadow |
| pressSpring | response 0.28 / damping 0.72 | response 0.32 / damping 0.86 |
| smoothSpring | response 0.42 / damping 0.86 | pressSpring 别名 |
| pressAnimation | 无统一值 | 0.2 秒 ease-out |
| 按压样式 | 0.85 透明度、缩放、Pow 下陷；Chip 0.6 | 仅 0.88 透明度；保留 scale 参数但不执行缩放 |
| disabledOpacity | 散落的 0.4 | 集中为 0.4 |
| serif / serifSemibold / serifBold | 思源宋体 Regular，后两者已为兼容别名 | 保持 Regular，不合成粗体 |
| sans | 已有系统体函数 | 保留系统体语义；控件 15 medium，说明按组件使用 13/14 |
| masthead / kicker | 12 medium，无统一 tracking | 12 semibold；mastheadTracking = 2.0 |
| display | 系统体 semibold | serif；StatBlock 使用 monospacedDigit |
| headline | serifBold 兼容入口 | 保留，实际为 serif Regular |

`Font` 不携带 tracking；完整眉题由 `.mastheadStyle(color:)` 同时应用 `Theme.masthead` 与 2.0 字距。Masthead、StatBlock、共享眉题使用此入口。
两种阴影分别通过 `@Environment(\.colorScheme)` 判断；夜间分支直接返回内容，卡面和浮层保留 line 描边。
按钮反馈与封面透明度过渡经既有 ReducedMotionPolicy 拦截。共享 ListenLabel 移除循环变色，保留其状态符号与全部文字。

## 3. 组件清单与落点

以下组件均在 **`Tingye/Theme.swift`**，无需新增 Sources 条目。旧组件 API 继续有效。

| 组件 | 实现 / 兼容入口 | 外观与状态 |
|---|---|---|
| PaperBackground | 新增泛型容器；支持无 header 的初始化 | bg 全屏纸底，可选顶部内容；不接管导航/滚动 |
| Masthead | PageMasthead 的别名，原实现同步对齐 | 12pt 眉题及可选右侧文字动作、宋体 34（支持传 28）、可选副行；可换行，支持缩至 24 |
| SectionHeader | 新增；SectionTitle 也改为宋体 20 | 宋体 20 + 右侧 TextButton |
| PaperCard | Card 的别名；PaperPanel 同步对齐 | surface + line + softCardShadow，默认内边距 20、圆角 18 |
| HairlineRow | 新增泛型行；提供 EditorialRow 文本便利初始化 | 最小行高 52、可选 0.5 分隔，无卡壳；内容支持左右组合 |
| PrimaryButton | 新增文字入口，复用 PrimaryButtonStyle | ink 底 bg 字，日夜自动反转，15 medium、高 50、圆角 14；禁用/按压态 |
| ClayButton | 新增，复用 PrimaryButtonStyle 的颜色参数 | clay 底 onClay 字；每屏限额由调用方遵守 |
| SecondaryButton | 新增文字入口，SecondaryButtonStyle 同步对齐 | surface + line + ink，禁用/按压态；保留 emphasized 旧参数 |
| TextButton | 新增，配套 TextButtonStyle | accent 字、无下划线，最小高度 44，禁用/按压态 |
| Chip | 新增文字入口，ChipPillStyle 同步对齐 | Capsule；选中 ink/bg + 勾号及 selected trait；未选 surface/line |
| SegmentedBar | 新增泛型受控组件 | surface2 轨道、surface/line 滑块、13pt 字；勾号/selected trait；大辅助字号纵排 |
| ProgressLine | ProgressBar 的别名 | 3pt line 轨道/clay 已读段，Capsule 圆头；既有进度无障碍描述保留 |
| SealBadge | 既有组件对齐 | 11pt accent、accentSoft、圆角 6；文字必传；filled 参数保留但统一淡底 |
| SealDot | 新增 | 6pt clay 圆点 + 必传状态文字，圆点本身不单独朗读 |
| CoverView | BookCoverView 的别名，FlexibleCover 复用其实现 | coverRadius、line 发丝线、内侧 1pt 高光；真实封面完整显示 |
| SheetChrome | 新增泛型容器 | 仅顶部圆角 28、line 抓手、宋体 20、右上无底 CircleIconButton；关闭回调由调用方提供 |
| EmptyState | 新增 | 宋体 22、系统说明 14/ink3、可选单个 PrimaryButton；空/加载/错误/成功状态，错误 dangerSoft 与形状、文字 |
| StatBlock | 新增 | 宋体数字默认 30、等宽数字、ink3 眉题式标签 |
| CircleIconButton | 既有组件对齐 | 44pt 最小命中区，无底无描边，ink2 regular 图标；原 action/label/size 签名保留 |

所有动作闭包均由调用方传入；不增加业务分支、导航、存储或默认选择逻辑。没有迁移逐屏调用点。

### 图标收口

工程原本已有 `enum Icon`（SF Symbol 字符串及状态函数）和 `struct ThemeIcon: View`，因此沿用现有映射层，不创建同名枚举。
Icon 的名称与符号映射保持原样。ThemeIcon 统一使用 `Image(systemName:)` 和 regular 字重，停止从旧 TY 矢量资产替换部分符号；保留 symbol/size/weight 调用签名，weight 为兼容参数。未删除任何图标资源，未批量修改页面图标调用。

## 4. 测试同步与已知冲突

全仓搜索测试文件、Python/脚本中的 `Theme.*`、hex 色值、contrast/对比度断言；影响本单元的已有颜色约束集中在 NativeCoreTests。

| 测试 | 本轮改动及理由 |
|---|---|
| 新增 testV31PaletteResolvesToSpecifiedColors | 新增规范精确值期望；覆盖 19 个不透明令牌/别名与 lineField，共 20 项 × 日夜 × normal/high。按 RGBA 分量验证 UIKit 动态解析与输入框 0.14/0.16 透明度，防止别名、高对比度或日夜解析偏离规范。 |
| testFocusTextContrastInBothAppearances | **配对及 ≥4.5 阈值全部保持**；仅补充解析颜色与外观的失败诊断。指定 ink3/surface2 的日间对比度只有 4.1727:1，不能在保留精确色值时声称通过。 |
| 其余 NativeCoreTests 颜色断言 | 不改。ReaderPaper/正文对比度、封面前景对比度、Theme.wash 动态颜色比较均保留原断言；封面使用新中性色与 ink，仍满足 ≥4.5。 |
| ReadiumPreferencesTests、正文 DOM/OriginalDocument 的 hex 与跟读色断言 | 不改。属于 ReaderPaper/出版物样式或测试输入，非本单元 UI 色板快照。不得把测试输入颜色或出版物自带色误替换。 |
| TingyeUITests 与其余测试 | 没有本单元需替换的旧 Theme hex 快照，不改。 |

冲突处理：不改设计指定 hex、不降低阈值、不删除或跳过原配对，也不添加 expectedFailure 来遮蔽它。已提出可选方案：surface2 上正文改用 ink2；这需要明确调整该配对语义并在后续逐屏单元核对实际调用，**本交付尚未执行此改动**。

WCAG 2.x 相对亮度按 sRGB 线性化计算，源值静态复算如下；不是 UIKit XCTest 执行结果。30 组日夜配对中，29 组 ≥4.5，1 组冲突。

| 配对 | 日间 | 夜间 | ≥4.5 |
|---|---:|---:|---|
| `ink / bg` | 16.8307 | 16.8528 | PASS |
| `ink2 / bg` | 8.7860 | 10.8518 | PASS |
| `ink3 / bg` | 4.5600 | 6.5004 | PASS |
| `accent / bg` | 5.2992 | 9.8351 | PASS |
| `onClay / clay` | 5.9310 | 5.9310 | PASS |
| `ink / readingHighlight` | 15.0572 | 12.1401 | PASS |
| `ink3 / surface2` | 4.1727 | 5.1742 | FAIL |
| `accent / accentSoft` | 4.7408 | 7.0848 | PASS |
| `onInk / ink` | 16.8307 | 16.8528 | PASS |
| `ink2 / surface` | 9.2560 | 9.8518 | PASS |
| `ink3 / surface` | 4.8039 | 5.9014 | PASS |
| `heroInk / hero` | 15.0572 | 12.1401 | PASS |
| `ink2 / hero` | 7.8602 | 7.8172 | PASS |
| `accent / hero` | 4.7408 | 7.0848 | PASS |
| `onMarker / marker` | 5.9310 | 5.9310 | PASS |

如采用 ink2/surface2，正文仍须保持 ≥4.5；不得把 ink3 在此背景上重新定义成允许低对比度的正文。ink4 仅为规范指定的极次级语义，未加入正文达标承诺。

## 5. Sources 构建成员核对

执行：`python3 scripts/verify-swift-sources.py`，退出码 **0**。
脚本解析 OpenStep pbxproj，解析 PBXGroup 的实际路径，逐条沿 **target → PBXSourcesBuildPhase → PBXBuildFile → PBXFileReference → 磁盘文件** 验证。
同时检查缺失/重复构建成员、错误 target、只创建 buildFile 却未加入 Sources，以及磁盘文件与构建成员集合是否一致。

结果：**56 / 56 target Swift 文件通过**，Tingye 48、TingyeTests 7、TingyeUITests 1。
另有 **25 个 Design 独立 Swift 工具脚本**，没有所属 Xcode target，逐个确认不在 App/测试 Sources 中；只枚举路径，不作为设计实现来源。它们不应加入 App target。
本轮新增 Swift 文件数 **0**；修改的 Theme.swift 与 NativeCoreTests.swift 均已经在正确 Sources 阶段。完整逐文件输出：

```text
PASS Tingye: Tingye/AppModel.swift
PASS Tingye: Tingye/BookFinishView.swift
PASS Tingye: Tingye/BookImporter.swift
PASS Tingye: Tingye/ComicReaderView.swift
PASS Tingye: Tingye/DailyQuoteCard.swift
PASS Tingye: Tingye/DialogueRoles.swift
PASS Tingye: Tingye/FocusSession.swift
PASS Tingye: Tingye/GeneralSettingsView.swift
PASS Tingye: Tingye/ICloudBackup.swift
PASS Tingye: Tingye/Library.swift
PASS Tingye: Tingye/LibraryViews.swift
PASS Tingye: Tingye/MenuSettingsView.swift
PASS Tingye: Tingye/MobiReader.swift
PASS Tingye: Tingye/Models.swift
PASS Tingye: Tingye/NotesUnifiedView.swift
PASS Tingye: Tingye/OriginalBookView.swift
PASS Tingye: Tingye/PlayerView.swift
PASS Tingye: Tingye/ReaderAnnotations.swift
PASS Tingye: Tingye/ReaderView.swift
PASS Tingye: Tingye/ReadingCalendarView.swift
PASS Tingye: Tingye/Readium/EPUBDisplayTransform.swift
PASS Tingye: Tingye/Readium/EPUBNavigatorHost.swift
PASS Tingye: Tingye/Readium/EPUBTextSnapshotBuilder.swift
PASS Tingye: Tingye/Readium/LegacyEPUBBuilder.swift
PASS Tingye: Tingye/Readium/LocatorBridge.swift
PASS Tingye: Tingye/Readium/LocatorMigration.swift
PASS Tingye: Tingye/Readium/PublicationMap.swift
PASS Tingye: Tingye/Readium/PublicationStore.swift
PASS Tingye: Tingye/Readium/ReaderRouter.swift
PASS Tingye: Tingye/Readium/ReadiumAnnotations.swift
PASS Tingye: Tingye/Readium/ReadiumFontProvider.swift
PASS Tingye: Tingye/Readium/ReadiumPreferencesBridge.swift
PASS Tingye: Tingye/Readium/ReadiumReaderView.swift
PASS Tingye: Tingye/Readium/ReadiumService.swift
PASS Tingye: Tingye/Readium/ReadiumSpeechBridge.swift
PASS Tingye: Tingye/Readium/StoredLocator.swift
PASS Tingye: Tingye/Readium/TextDOMIndex.swift
PASS Tingye: Tingye/SMBBrowser.swift
PASS Tingye: Tingye/Services.swift
PASS Tingye: Tingye/ShelfView.swift
PASS Tingye: Tingye/Sources.swift
PASS Tingye: Tingye/SpeechPlayer.swift
PASS Tingye: Tingye/StatsView.swift
PASS Tingye: Tingye/StorageView.swift
PASS Tingye: Tingye/Theme.swift
PASS Tingye: Tingye/TingyeApp.swift
PASS Tingye: Tingye/TxtRulesView.swift
PASS Tingye: Tingye/Typography.swift
PASS TingyeTests: TingyeTests/LocatorMigrationTests.swift
PASS TingyeTests: TingyeTests/NativeCoreTests.swift
PASS TingyeTests: TingyeTests/ReadiumBackupSourceTests.swift
PASS TingyeTests: TingyeTests/ReadiumLocatorTests.swift
PASS TingyeTests: TingyeTests/ReadiumPreferencesTests.swift
PASS TingyeTests: TingyeTests/ReadiumPublicationTests.swift
PASS TingyeTests: TingyeTests/ReadiumTextSnapshotTests.swift
PASS TingyeUITests: TingyeUITests/DesignFlowTests.swift
PASS 56 target Swift files; Tingye=48, TingyeTests=7, TingyeUITests=1
TOOL (no Xcode target): Design/icon-little-prince/validate-icons.swift
TOOL (no Xcode target): Design/icon-margin-gpt/make-preview.swift
TOOL (no Xcode target): Design/icon-margin-gpt/prepare-variants.swift
TOOL (no Xcode target): Design/render-app-icon-v10.swift
TOOL (no Xcode target): Design/render-app-icon-v11.swift
TOOL (no Xcode target): Design/render-app-icon-v12.swift
TOOL (no Xcode target): Design/render-app-icon-v13.swift
TOOL (no Xcode target): Design/render-app-icon-v14.swift
TOOL (no Xcode target): Design/render-app-icon-v15-concepts.swift
TOOL (no Xcode target): Design/render-app-icon-v16.swift
TOOL (no Xcode target): Design/render-app-icon-v18.swift
TOOL (no Xcode target): Design/render-app-icon-v2.swift
TOOL (no Xcode target): Design/render-app-icon-v3.swift
TOOL (no Xcode target): Design/render-app-icon-v4.swift
TOOL (no Xcode target): Design/render-app-icon-v5.swift
TOOL (no Xcode target): Design/render-app-icon-v7.swift
TOOL (no Xcode target): Design/render-app-icon-v8.swift
TOOL (no Xcode target): Design/render-app-icon-v9.swift
TOOL (no Xcode target): Design/render-app-icon.swift
TOOL (no Xcode target): Design/v19-margin/contact-sheet.swift
TOOL (no Xcode target): Design/v19-margin/prepare-icons.swift
TOOL (no Xcode target): Design/v21-swiss/icon/render-app-icon-v21.swift
TOOL (no Xcode target): Design/v23-time/icon/render-app-icon-v23.swift
TOOL (no Xcode target): Design/v25-moqing/render-app-icon-v25.swift
TOOL (no Xcode target): Design/v26-wereader/render-app-icon-v26.swift
INFO 25 standalone Design tools excluded from app/test Sources
```

## 6. 验证结果与未动项

- Sources 核对通过；只读脚本 Python 语法检查通过。
- 静态核对 18 个不透明颜色令牌/别名的日夜精确值，通过。lineField 的 RGBA 动态行为由新增 XCTest 承载，尚未在 iOS 执行。
- 与任务进入时的临时快照比对：原 Theme 的 67 个静态符号均保留；ReaderPaper 与 ReaderPreferences 区块字节一致。
- 任务进入时的工作区 SHA-256 清单复核：已有文件仅 Theme.swift、NativeCoreTests.swift 发生修改。pbxproj、构建号 **144**、workflows、依赖锁定、逐屏 Swift 文件、数据与引擎文件均未变化。
- 本机没有 Swift/Xcode/iOS SDK：编译、UIKit 动态色 XCTest、交互和视觉验收均未执行。**不声明测试全绿**；原有对比度测试预期会暴露上文的一项日间冲突。
- 未运行既有 `check-redesign-structure.py`：该脚本内部执行 git 且绑定旧基线/旧构建号，与本任务禁止 git 操作不符；本轮使用独立只读 Sources 脚本及进入时文件清单进行核对。
- 未改 ReaderPaper §7、阅读偏好及出版物 DOM/CSS，未逐屏排版、迁移图标调用或核算每屏陶土面数量，未改 App 图标资产（§8）。这些仍属于后续单元。
- 未改功能、导航结构、数据协议、现有文案及交互闭包。旧别名会把新令牌与共享外观传递到既有使用处；各页面内部未迁移的局部样式仍需后续单元对齐。
