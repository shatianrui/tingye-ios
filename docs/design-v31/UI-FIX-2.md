# v31 UI-FIX-2：阅读工具辅助函数诊断与修复

范围：`anthropic-ui-v31`，构建号 **145**。核对 [Tests run 44032590099](https://github.com/shatianrui/tingye-ios/actions/runs/44032590099)，通过 GitHub 连接器读取 jobs 和 [UI job 133867813102 日志](https://github.com/shatianrui/tingye-ios/actions/runs/44032590099/job/133867813102)。Unit job 成功，UI 为 30 例、1 例失败。

本地日志为 `/tmp/v31-ui3.log`。将其中目标用例的第 **9026–9107 行**与连接器日志逐行比较，去掉日志时间戳和本地 job/step 前缀后，**82 行事件完全一致**。下文行号均指这份本地日志；它是修复前证据。

## 1. 先纠正失败位置与时间判断

| 日志位置 | 实际事件 |
| --- | --- |
| `v31-ui3.log:8496,8681` | 分页正文 chrome 稳定性用例从 06:48:01 开始，06:48:32 通过，耗时 30.782 秒。 |
| `v31-ui3.log:9026` | 本例在 **06:49:42.387** 开始。 |
| `v31-ui3.log:9058–9067` | 已检查同名动作数量，成功点击「从当前阅读位置听」，随后找到 `reader.toggle`；已越过上一轮的重复动作失败点。 |
| `v31-ui3.log:9068–9077` | 获取 `reader.nativePage` 的 frame，检查 `reader.more` 存在，然后在 **t=12.12s** 点按 **(201.0, 482.8)**。 |
| `v31-ui3.log:9086–9102` | 等待的是 **`reader.more` 不存在**，连续检查到 t=17.71s 仍未满足。 |
| `v31-ui3.log:9105–9107` | **06:50:00.582** 报原 `DesignFlowTests.swift:214` 失败，即 `waitForNonExistence(timeout: 5)`；本例耗时 **18.448 秒**。 |
| `v31-ui3.log:9644` | 整组 30 例耗时 699.211 秒，只有本例失败。 |

因此，本轮不是后段重新显示工具时的 `waitForExistence` / `isHittable` 失败，而是第一次 `setReadingTools(false, ...)` 没有隐藏成功。约十分钟是整组运行到该处的时间，不能作为本例已执行十分钟或后续章节断言已通过的证据。上一轮 `/tmp/v31-ui2.log:8853` 则明确是原 `:544` 的同名按钮多匹配，耗时 12.257 秒（`:8887`）。

## 2. 根因分类与源码核对

**分类：测试辅助函数对可点正文区域的假设过时，另有 5 秒与既有 15 秒等待口径不一致。不是已证实的纯等待超时，也没有证据表明 chrome 开关整体失效。**

- `Tingye/ReaderView.swift:322,456–467,775–805,818–823`：`chrome` 控制底面板的条件挂载；`reader.more` 在 `reader.tools` 的四槽动作网格中。这里不是用 opacity 隐藏常驻按钮，因此原 `more.exists != visible` 的状态分支仍成立，不能把“不可点击”直接当成“已经隐藏”。
- `ReaderView.swift:681–691,1218`：正文中央 28%–72% 区域调用 `toggleChrome()`，左右两侧翻页；切换采用 `.snappy(duration: 0.24)`，外层另有 `.snappy(duration: 0.25)`（`:497`）。`Theme.pressSpring` 经 `smoothSpring` 用于 `active` 等状态（`Theme.swift:98–100`、`ReaderView.swift:498–500`），不能凭动画名称认定这次是五秒动画未完成。
- `ReaderView.swift:417–430,453–467,481–485`：正文固定尺寸，顶栏和底面板以 overlay 覆盖；仅保证面板之外有最小阅读高度（`:418–419`），并不保证**整个正文视口的几何中心**始终露出。
- `ReaderView.swift:793–805,1038–1064`：辅助听书启动后，四槽下方增加听书控制，底面板随测量结果增高；正文另外为听条留底部空间（`:429`）。普通分页 chrome 用例没有这项听书状态，不能用它通过来证明本例点按坐标也有效。
- `TingyeUITests/DesignFlowTests.swift:141–145,204–207`：`nativeLayout` 使用原生正文 frame，旧点按函数直接取其 `midY`，没有扣除覆盖层。日志明确显示它随后进行了坐标点按，却始终未等到 `more` 移除。这与点按落在增高后的底面板覆盖区相符。
- 根壳的阅读器通过既有 `fullScreenCover` 呈现（`Tingye/TingyeApp.swift:311–319`）；本例启动、更多面板与听书动作均已成功，没有证据支持为这次失败修改根壳。
- 既有 `openReaderMorePanel` 对更多按钮使用 **15 秒**，并说明大字号 popover 可能较慢（修改前 `DesignFlowTests.swift:217–229`，修改后 `:237–249`）；共享 `waitForReadingCondition` 同样为 **15 秒**（`:157–161`）。原 `setReadingTools` 的显隐等待都是 5 秒，显示时还在存在后立即检查 `isHittable`。

**证据边界：** 日志没有记录点按当时的 `reader.tools.frame`，所以“该坐标实际命中面板”是结合上述布局与事件链的源码推断，不能冒充截图或模拟器实测。也不能声称多等十秒就必然消失。确定的问题是辅助函数从未验证点按坐标是否落在露出的正文内。

本次修正辅助函数的输入定位与等待机制。底面板覆盖范围内本就包含章节滑杆和听书控件，不能让这些区域的触摸穿透正文来迁就旧坐标；实际露出的正文仍保留中央点按路径。因此没有修改 App 的布局、手势或按钮可访问性语义。

## 3. 改动清单

仅修改 `TingyeUITests/DesignFlowTests.swift:210–235` 的 `setReadingTools`：

1. 保留 `more.exists != visible`，每次调用最多点按一次。用调用方正文 frame 与窗口相交，再以现有 `reader.back` 底缘及 `reader.tools` 顶缘限定露出的正文区域，点其中部；横坐标仍使用整个窗口中心，避免双页时误翻页。没有可点区域就明确失败。
2. 显示时使用既有 `waitForReadingCondition`，在同一 **15 秒**期限内同时要求 `more.exists && more.isHittable`；隐藏时仍严格要求 `waitForNonExistence`，期限对齐为 **15 秒**。
3. 增加调用位置透传及显隐诊断消息。没有新增动作重试、固定 sleep、跳过，亦未复制 `openReaderMorePanel` 的重按逻辑。

新增本文 `docs/design-v31/UI-FIX-2.md`。

目标用例整个函数逐字保持不变（修改后 `DesignFlowTests.swift:562–630`），包括动作唯一性、四槽位置、暂停/继续不移动快捷条、展开入口唯一、翻章不 seek 音频、暂停状态保持、音频回写不覆盖阅读位置、退出重开恢复独立断点等所有断言。其余测试、布局比较函数、容差和更多面板辅助函数也均未修改。

## 4. 验证与限制

- `python3 scripts/verify-swift-sources.py` 退出码 **0**：56 个 target Swift 文件（App 48、Unit 7、UI 1），25 个 Design 工具不进入 target。该检查不等于 Swift 编译。
- 用任务开始时保存的源文件做精确比较：移除 `setReadingTools` 后，新旧 UI 文件完全一致；目标测试整个函数 SHA-256 均为 `06056aad27b828b852f13699b0c84ca03eafc60fa87b773dc81463bf9784e6b5`。
- 用任务开始时的工作区文件哈希核对改动范围：只改上述 UI 文件并新增本文。工程各处 `CURRENT_PROJECT_VERSION` 仍为 **145**；没有修改 workflows，没有执行 git 操作。
- 当前 Linux 环境没有 `swift`、`xcodebuild`、`xcrun` 或 iOS 模拟器，**未执行修复后编译、Unit 或 UI 测试，不能宣称该例已转绿**。已读取 UI artifact 元数据，但网络限制使本地无法下载结果包，未以其截图作为证据。
- Xcode 环境需执行目标用例，确认点按落在实际露出的正文、工具能隐藏并重新显示，再完成本例后续全部功能断言；同一辅助函数还用于 native/PDF chrome 稳定性测试，需一并复核其正文坐标与文字保持。这里没有触发 CI 或重复运行失败用例。
