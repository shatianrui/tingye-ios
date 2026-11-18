# 构建 146 的 EPUB 冒烟回归

## 根因

失败发生在 Readium 的首批 EPUB 章节请求进入 WebKit 之后、交给本地资源处理器之前。iOS 26.4 模拟器的 WebKit 对已有本地 `WKURLSchemeHandler` 的导航仍发起 AppSSO 查询。第二次失败运行中，WebKit 等了约 19 秒才收到查询结果，随后才开始章节加载。SwiftUI 阅读器已挂载，但首个位置尚未确认，`ready` 仍为 `false`，底栏因此没有创建 `reader.contents`。WebKit 上游记录过同一机制导致 Apple Books 的本地 EPUB 加载卡住，修复方式是在导航策略阶段跳过本地 scheme 的拦截。 [WebKit 313882 修复](https://github.com/WebKit/WebKit/commit/111ec8a8a585f7d2764b373a0ef28fa8772cc5a9)

## 从启动到目录按钮

1. `launch("reader-original", original: true)` 传入 `-ui-fixture`、`-uireview reader-original` 和 `-reader.original YES`。两版 App 都读取前两项，`reader.original` 在这两个版本都没有读取方。 [UI 启动参数](../../TingyeUITests/DesignFlowTests.swift#L8) · [场景参数解析](../../Tingye/TingyeApp.swift#L178)
2. DEBUG 下，`TingyeApp` 调用 `UIReview.makeFixture()`。它在临时书库生成 `ui-original`，存入两章正文、章内 HTML/CSS 和内嵌 PNG，并用该书库初始化 `AppModel`。`AppModel` 同步读入目录。根视图的走查任务调用 `driveUIReview()`，选择该 EPUB 并调用 `model.open`。`openBook` 读出图书并写入 `selectedBook`，根视图随即呈现 `RoutedReaderView`。 [Fixture 播种](../../Tingye/TingyeApp.swift#L53) · [样本内容](../../Tingye/TingyeApp.swift#L121) · [书库初始化](../../Tingye/AppModel.swift#L125) · [走查任务](../../Tingye/TingyeApp.swift#L284) · [选择 EPUB](../../Tingye/TingyeApp.swift#L375) · [打开图书](../../Tingye/AppModel.swift#L222) · [阅读器呈现](../../Tingye/TingyeApp.swift#L311)
3. 两版 `ReaderRouter` 都按 `Book.format == "EPUB"` 进入 `ReadiumReaderView`。这个样本没有随书原文件，`PublicationStore.prepare` 通过 `LegacyEPUBBuilder` 将正文和资源生成派生 EPUB。会话 pin 文件、打开 Publication 并解析初始 Locator，然后挂载 `EPUBNavigatorHost`。测试查询到的 WebView 属于 Readium。 [路由](../../Tingye/Readium/ReaderRouter.swift#L4) · [派生 EPUB](../../Tingye/Readium/PublicationStore.swift#L24) · [会话打开](../../Tingye/Readium/ReadiumReaderView.swift#L46) · [挂载 Navigator](../../Tingye/Readium/ReadiumReaderView.swift#L192)
4. `chrome` 初值为 `true`，底栏还要求 `ready && session.error == nil`。Readium 的 `locationDidChange` 经 Host 的 `reportLocation` 送到 `ReadiumReaderView.locationChanged`，视图收到位置并处理反向映射后才置 `ready = true`。目录按钮的标识符在两版中均为 `reader.contents`，按钮开启目录面板，面板的 `reader.search` 再打开全文搜索。 [就绪状态](../../Tingye/Readium/ReadiumReaderView.swift#L125) · [底栏门槛](../../Tingye/Readium/ReadiumReaderView.swift#L257) · [定位回调](../../Tingye/Readium/EPUBNavigatorHost.swift#L207) · [设置 ready](../../Tingye/Readium/ReadiumReaderView.swift#L569) · [目录按钮](../../Tingye/Readium/ReadiumReaderView.swift#L394) · [搜索入口](../../Tingye/Readium/ReadiumReaderView.swift#L436)

## 运行证据与版本对照

- 构建 146 的两次运行都在 `DesignFlowTests.swift:315` 的 20 秒断言失败，Unit 通过。构建 145 的对照组同样使用 iOS 26.4，测试在 `t = 9.50s` 开始等待，到 `t = 27.34s` 已进入下一条 WebView 断言，相隔约 17.84 秒，最终正文、目录和搜索都通过。 [146 首次运行](https://github.com/shatianrui/tingye-ios/actions/runs/44226327945) · [146 第二次运行](https://github.com/shatianrui/tingye-ios/actions/runs/44228756852) · [145 对照运行](https://github.com/shatianrui/tingye-ios/actions/runs/44232725958)
- 第二次运行的 `TingyeUITests.xcresult` 在 PID `12097` 的失败快照中记录了 `reader.epubNavigator`、无正文后代的 `WebView` 和其加载指示器。顶栏的 `reader.back` 可见，`reader.currentTitle` 仍是书名，书签禁用，`reader.epubPage` 为「未分页」。快照没有打开失败面板，也没有底栏。这把故障定位到首个页面位置送达之前。原始快照数据对象以 `data.0~BLfznjNm` 开头。

第二次失败运行，PID `12097` 的模拟器统一日志，时间为 UTC。

| 时间 | 日志事件 |
| --- | --- |
| `03:22:06.158`、`03:22:06.249` | 两个 WebView 发出 `WebPageProxy::loadRequest`。 |
| `03:22:08.280`、`03:22:08.507` | WebKit 调用 `SOAuthorizationCoordinator::tryAuthorize`。AuthKit 查询可接管的 URL，AppSSO 发起配置查询。 |
| `03:22:26` 左右 | 20 秒断言耗尽，XCTest 请求无障碍快照，正文仍未分页。 |
| `03:22:27.447`、`03:22:27.449` | AppSSO 配置返回，WebKit 确认两个 URL 都未注册 AppSSO，才向 WebContent 放行。 |
| `03:22:27.455` 起 | 首个 provisional load 开始，随后 `WebURLSchemeTaskProxy` 请求本地 handler、收到数据并完成。 |

本地 handler 在放行后返回了数据。Readium 的页面装饰模板由 `spreadViewDidLoad` 注册，执行时点在正文加载之后。现有日志已定位 AppSSO 查询阻塞，也给出了该次失败里资源真正开始加载的时点。未取得足够的对照组 AppSSO 日志来解释两版运行为什么恰好落在 20 秒门槛两侧。 [Readium 3.11.1 的章节请求](https://github.com/readium/swift-toolkit/blob/3.11.1/Sources/Navigator/EPUB/EPUBReflowableSpreadView.swift#L74) · [页面加载与装饰注册顺序](https://github.com/readium/swift-toolkit/blob/3.11.1/Sources/Navigator/EPUB/EPUBSpreadView.swift#L362) · [模板注入](https://github.com/readium/swift-toolkit/blob/3.11.1/Sources/Navigator/EPUB/EPUBNavigatorViewController.swift#L961)

对 `189fc00` 与 `14cbd24` 的源码逐段比较显示，测试启动参数、fixture 播种、`AppModel`、格式路由、派生资源生成、Navigator 就绪回调和目录标识符相同。六处 App 增量的影响如下。

| 文件 | 增量及其执行时点 |
| --- | --- |
| `OriginalBookView.swift` | 更换独立 UIViewRepresentable 的跟读 `mark` 填充和取色。两个提交的 EPUB 路由都没有实例化这个视图。 |
| `ReaderAnnotations.swift` | 恢复标注取色和控件。fixture 初始摘记为空，冒烟失败发生在首次全文搜索前。 |
| `ReaderView.swift` | 原生路径的选段面板和跟读绘制变更。原生 `reader.contents` 的标识符也没有变化。 |
| `Theme.swift` | 移除原生跟读竖线使用的 `highlightBand`，Readium 启动所用的纸色解析保持原样。 |
| `ReadiumAnnotations.swift` | 删除 `tingye.speech` 专用模板。模板配置是在启动时惟一相关的增量，但 WebKit 卡在导航策略阶段，此时页面尚未加载，模板 JS 还未执行。 |
| `ReadiumReaderView.swift` | 跟读装饰改为直接透传。启动时跟读数组为空，`refreshSpeech` 在未朗读时也清空数组。目录挂载条件及标识符一致。 |

因此，现有证据把故障归因于已知的 WebKit 本地导航问题，没有把它归因到某一处高亮增量。145 对照组证明原等待口径可以走通，两个 146 失败提供了调查入口。

## 修复与保留的热修

在 `EPUBNavigatorHost` 构造 Navigator 前，给 iOS 26.4 的 DEBUG 模拟器隔离 fixture 安装一次配置钩子。Readium 注册本地 scheme handler 时，钩子先调用 WebKit 原注册方法，再用 WebKit 的 SPI 为这份配置关闭 Extensible SSO。配置在 Readium 创建 WebView 之前生效。原 EPUB 请求仍经 Readium 的 scheme handler，原来的 DOM、分页、定位和全文搜索照常执行。设备和 Release 目标不会编译这个钩子。 [修复入口](../../Tingye/Readium/EPUBNavigatorHost.swift#L37) · [fixture 配置钩子](../../Tingye/Readium/EPUBNavigatorHost.swift#L293) · [WebKit SPI 声明](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/API/Cocoa/WKPreferencesPrivate.h) · [Readium 注册顺序](https://github.com/readium/swift-toolkit/blob/3.11.1/Sources/Navigator/EPUB/EPUBSpreadView.swift#L67)

- 五色标注调色盘、旧颜色键和选择面板继续使用 146 的实现。 [标注热修](HOTFIX-highlight-palette.md)
- Readium 继续通过默认 `.highlight` 模板绘制跟读浅底，原生 CoreText/TextKit 继续铺跟读背景，竖线保持删除。独立 `OriginalBookView` 的 145 渐变在文字底部横向铺色，本身也属于填充带。该视图未参与这条路径，这次保留 146 的整段背景填充。 [跟读热修](HOTFIX-speech-highlight.md) · [跟读装饰生成](../../Tingye/Readium/ReadiumSpeechBridge.swift#L22)

## 验证状态

已核对两版源码、三次 CI 的 UI 日志及第二次失败的无障碍快照和模拟器日志。源码成员检查通过。测试文件、20 秒等待、构建号 146 和 workflows 保持原样。当前 Linux 工作区没有 Xcode，补丁尚待在 iOS 26.4 模拟器上跑原用例并复跑 EPUB 目录、排版和跟读用例。设备端仍依赖系统 WebKit 的实现。
