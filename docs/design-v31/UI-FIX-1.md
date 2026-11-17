# v31 UI-FIX-1：DesignFlowTests 五例修复

范围：`anthropic-ui-v31`，构建号 **145**。依据 `Design/v31-anthropic/DESIGN.md`，特别是 §6.2、§6.4、§6.7、§6.12 及不改变功能的约束。

核对了本地保留的 CI 文本日志 `/tmp/v31-ui2.log`：其中 DesignFlowTests 为 30 例、5 例失败，失败名称、行号和错误与任务给出的 Tests run **44028713338** 一致。本文引用的是这份已有日志，没有重新触发 CI，也没有将它当作修复后结果。

## 分类

| 用例 | 分类 | 修复位置 |
|---|---|---|
| `testPagedReaderChromeDoesNotReflowOrMoveReadingPosition` | 真回归：实际正文回跳；不能修改期望文字迁就 | `ReaderView.swift` |
| `testReaderKeepsActionSlotsAndChapterNavigationDoesNotSeekAudio` | 真回归：底面板与更多弹层重复暴露同一动作 | `ReaderView.swift`，测试补充全界面唯一性断言 |
| `testLargestTypePlayerControlsRemainReachable` | 旧断言失效：大字号分支仍在，封面已不再是分支标志 | `PlayerView.swift` 提供真实布局状态；同步测试 |
| `testShelfOrganizeAndDetailsAreExplicit` | 旧断言失效：详情主按钮按新规范改为「打开」 | 仅同步测试，补验续读说明和实际打开 |
| `testShelfSeparatesFilterSortAndLayoutAndProtectsDeletion` | 真回归：菜单选项有数据，但系统菜单标题/可访问性呈现损坏 | `ShelfView.swift`；原测试不变 |

没有将任何一例归类为 flake。

## 1. 分页正文回跳（原 :416）

**证据与根因：** 06:22:34 的失败日志显示，基准页以「书，安静读书…」开始，隐藏工具后却以「第1句…」开始。按 `UIReview.makeFixture` 的原始正文逐字定位，基准页覆盖 `[297, 595)`，失败时覆盖 `[0, 297)`；这是真实回到前一页，不只是章编号或标题变化。第 3 个长句从字符 240 开始，跨过页边界 297。

源码中的问题链是：正文 `GeometryReader` 内用透明 `Group` 承接 `.task(id: RebuildKey(...))`，分页子视图又带 `.id(chapter-pageIndex)`。[Apple 的 Group 文档](https://developer.apple.com/documentation/swiftui/group)说明修饰符会作用到组内视图，生命周期回调会随条件内容变化再次执行。据此结合源码判断，页身份变化可重新挂载分页任务。旧 `rebuild` 无条件重新分页，并用 `currentOffset`（当前句的句首）执行 `locate`；翻到字符 297 后，`turn` 保存的是包含它的长句序号，句首 240 仍在上一页，重复定位就退回 `[0, 297)`。日志中的精确偏移与这条路径吻合。仅根据这份日志不能断言新底面板改变了多少点 inset；不能把这种推测当实测结果。

**改动：**

- 正文的分页任务改挂在稳定的 `ZStack` 容器上，不随页视图身份重新挂载；以已完成的 `RebuildKey` 跳过相同章节、尺寸和偏好的重复分页。
- 正文先固定为外层 GeometryReader 给出的尺寸，再把选区/听条、底面板、状态行与顶栏分别挂成 `overlay`。chrome 测量结果仅决定覆盖层高度，不参与正文布局；系统覆盖物策略也不再随 chrome 切换。
- 用户真正改变字号或窗口尺寸时，以当前页首字符定位新页，避免再次把跨页长句的句首误当作眼前位置。首次打开、跨章跳转、滚动模式和显式跟随朗读仍走各自的原定位来源。
- 辅助听书已经开启时仍为快捷条保留原有底部空间，确保正文在听条上方；没有用 chrome 高度作为正文 inset。

**断言意图：** 此用例和共享 `assertReaderChromePreservesLayout` 均逐字保持不变：仍比较实际页文字、每个正文元素坐标、正文视口，连续开合四次后还必须能回到原上一页。没有放宽坐标容差、等待条件或改为只验章号。

## 2. 辅助听书动作重复（原 :544）

**证据与根因：** 06:24:42 的失败树同时列出 popover 中的 `reader.startListening` 与 `reader.tools` 中一个无 identifier 的按钮，标签均为「从当前阅读位置听」。新底面板确实新增了同一动作；原先只查 `reader.listen` 不存在不能抓住无 identifier 的重复入口。

**改动：** 移除底面板上重复的直接听书动作，保留「更多 → 辅助听书 → 从当前阅读位置听」原入口、标识与执行闭包。常驻工具回到目录、排版、摘记、更多四个槽位；大字号仍为两列。这四个槽位不随是否播放变化。

**断言意图：** 在原用例中增加全 App 按精确标签计数：打开更多前为 0，打开后为 1。仍用原来的全局按钮查询点击，没有用 `.firstMatch` 或缩小到 popover 查询。暂停/继续不移位、展开入口唯一、阅读翻章不 seek 音频、退出重开保留独立阅读断点等后续断言全部保留。

## 3. 最大字号播放器（原 :491）

**证据与根因：** `PlayerView` 仍按 `typeSize.isAccessibilitySize || geometry.size.height < 700` 选择整页滚动加固定 transportRow 的布局，footer 也仍按真实字号切换两列。v31 将同一个 `hero(book, coverWidth:)` 用于这个分支，hero 包含 `player.cover`；因此「封面不存在」在正确进入辅助字号时也会失败。不是自适应布局分支丢失。

**改动：** 给实际滚动容器 `player.tools` 增加由环境 `dynamicTypeSize` 决定的 accessibilityValue：辅助字号为「辅助功能字号」，仅因高度进入该分支则为「紧凑高度」。测试改为等待这个真实容器，并精确断言它的值为「辅助功能字号」。该值不读取测试启动参数，也不在普通高度布局中伪造。

**等价性：** 原断言意图是确保测试真的进入辅助字号布局；现在直接检查当前布局与实际环境字号，且能排除“小屏紧凑布局冒充辅助字号”的假通过。原有播放控制固定可达、横向居中误差 2pt、从内容滚动区到达目录并实际打开听书目录的断言全部保留。

## 4. 整理与详情入口（原 :445）

**证据与根因：** 日志显示整理、取消整理、打开 `book.detail.ui-long` 和等待 `detail.reading` 均成功，具体失败是 `reading.label.contains("继续阅读")`。`LibraryViews.actionButtons` 已按规范 §6.2 使用 `PrimaryButton("打开")`，仍调用 `model.open(entry)`；阅读位置另由 `detail.readingProgress` 显式显示。不是整理入口或详情主动作丢失。

**改动与等价性：** 精确断言新按钮标签「打开」，同时断言本例已读样本的「读至第 1 章」说明、阅读按钮实际可点击；再点击按钮进入阅读器并检查恢复第 1 / 2 章。保留整理/取消整理、详情入口可达、阅读动作位于听书动作上方、听书可达、阅读按钮高度至少 44pt。App 详情代码无需修改。

## 5. 排序菜单与删除保护（原 :691）

**证据与根因：** `ShelfView.sorted` 中 `title` 排序分支、`sortMenu` 中 `.tag("title")` 与「书名」文本均存在。06:26:33 的失败快照却找不到「书名」按钮，并列出了无标签 Button。排序 Picker 及布局 Picker 的选项都由带自定义 `ThemeIcon` 的通用 `Label` 构成；筛选 Picker 使用普通 `Text`，同一次运行中「待读」已成功点击。结合这两点，定位为自定义选项标签在原生菜单桥接时丢失标题的呈现/可访问性回归；具体系统桥接行为仍需修复后模拟器验证，不能通过改找无名按钮规避。

**改动：** 两个相关 Picker 的选项改用原生支持的 `Text`，保留所有标题、tag、selection 绑定和系统选中标记。外部筛选、排序、视图三个独立 Menu 的标识、图标、状态说明不变。没有删除书名排序、合并工具或改动排序算法；布局选项采用相同修正，以便该例下一步仍可实际选择「封面网格」。

**断言意图：** 整个原测试逐字不变，继续真实点击「书名」「封面网格」，检查当前排序/布局标签；继续验三项工具各自唯一、可达，筛选生效、清除后恢复，以及未选中时禁止删除、删除二次确认、取消删除保留书籍。没有为通过测试而绕开菜单、放宽名称或去掉删除保护。

## 验证与限制

- `python3 scripts/verify-swift-sources.py` 退出码 0：56 个 target Swift 文件（App 48、Unit 7、UI 1），25 个 Design 独立工具未加入 target。
- 修改的四个 Swift 文件通过忽略字符串、插值与注释后的词法括号配对检查。此项不是 Swift 编译或类型检查。
- 与任务开始时的文件快照比对，分页稳定用例、共享正文比较函数、筛选/排序/布局/删除保护用例均逐字不变。
- 用日志中的两段实际正文与 fixture 原文核对了字符偏移 0/297 和跨页句首 240，确认旧句首定位确实会选中上一页；这是日志与源码分析，不冒充模拟器复现。
- 本环境是 Linux，没有 `swift`、`xcodebuild`、`xcrun` 或 iOS 模拟器，**未执行修复后的编译、单元测试或 UI 测试，不能声称五例已经转绿**。在 Xcode 环境需复跑这五例；尤其确认系统菜单文本桥接、播放器布局状态值和实际视口坐标。

最终仅修改 `Tingye/ReaderView.swift`、`Tingye/PlayerView.swift`、`Tingye/ShelfView.swift`、`TingyeUITests/DesignFlowTests.swift`，新增本文。构建号仍为 **145**；未改工程、workflows 或其他文件，未执行 git 操作。
