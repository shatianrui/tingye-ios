# Readium 迁移单元 2：Navigator 路由、偏好与阅读 UI

实施日期：2026-11-16 UTC。本轮为中断续跑，保留上一轮实现，先完整重读原任务书、PLAN 和 UNIT1，再补齐接线与边界。未执行 git 操作，未改构建号、workflow 或 PR #13 测试线。

交付状态：实现、工程挂接、12 项测试源码及本报告已落盘，静态检查通过；**本轮未经 Swift 编译、XCTest、CI 或设备验证，不标记为验收通过。**

## 中断恢复盘点

下表记录恢复时的落盘状态与本轮发现的缺口；最终处理与验证记录见后文。

| 文件 | 恢复时核对结果 / 缺口 |
| --- | --- |
| `Tingye/TingyeApp.swift` | selectedBook 根入口已改为 RoutedReaderView；既有 5 秒 recordUsageTick 保留，无新计时器。 |
| `Tingye/Readium/ReaderRouter.swift` | 判据为 comic 布尔值 → pdf 可解码 → format.uppercased() == EPUB → native；不猜 document/resources。实现完整，但未挂工程、无判据测试。 |
| `Tingye/ReaderView.swift` | 原生仅接共用纸面解析、偏好面板可关闭示例预览；默认仍显示预览。其他格式继续使用既有 ReaderView。 |
| `Tingye/Theme.swift` | 七纸面背景/正文/次字日夜值逐项与 PLAN 4.2 相符；resolve 同时决定背景与文字，alwaysLight 不再只锁背景。无半截函数。 |
| `Tingye/Typography.swift` | MyFontsView 未设置时的默认字体已与 ReaderPreferences 统一为 system；FontLibrary 的存储/导入流程保留。 |
| `Tingye/AppModel.swift` | 每书库共享 PublicationStore，换库清空；saveProgress 仍走 sync.update、TextAnchor、KVS 和 1200ms catalog 防抖，仅赋值 progress；听书/书签/划线未被此路径覆盖。 |
| `Tingye/Readium/PublicationMap.swift` | 原包按规范化 document.path 优先、唯一标题其次；不按 spine 下标猜章。缺测试；需要在失败保留跳转的基础上检查加载中新增跳转。 |
| `Tingye/Readium/ReadiumReaderView.swift` | prepare/pin/open、目录回退、错误重试、设置与听书入口均已写完；仅确认目标资源后消费 readerJump。退出及失败释放 pin。缺口：取消后可见会话无重试提示、open 无同书幂等保护、准备期间新跳转可能错过、未映射资源仍可能沿用旧章保存/听书。 |
| `Tingye/Readium/EPUBNavigatorHost.swift` | 3.11.1 初始化、delegate、内部/外部链接均已接；偏好差异 submitPreferences，字体清单变化时用 currentLocation 重建。需核对旧导航任务/重建回调隔离，目录使用 Link 保留 fragment 的路径，以及 same-resource 跳转确认。 |
| `Tingye/Readium/ReadiumPreferencesBridge.swift` | 纯函数换算和 fixed-layout 子集完整；需加纸面/字号/行高/滚动/双栏等测试，并记录负字距在 Toolkit 被钳制为 0 的限制。 |
| `Tingye/Readium/ReadiumFontProvider.swift` | 同套字体键；文件可读才声明，缺文件 family 与 metrics 回退系统；TTC/WebView 效果待实测。未挂工程。 |
| `Tingye/Readium/EPUBDisplayTransform.swift` | 只有协议与原文映射合同，无转换实现，符合本单元范围；不宣称 EPUB 简繁支持。未挂工程。 |
| `Tingye.xcodeproj/project.pbxproj` | 六个新 app 文件均缺 FileReference/Group/BuildFile/Sources；构建号现值 142。 |
| `TingyeTests/ReadiumPreferencesTests.swift` | 尚不存在；需新增并挂测试 target，按直接 import 补 Navigator product。 |
| `Tingye/Resources/Localizable.xcstrings` | 新状态文案尚未登记，需要补齐。 |

新增 Swift 实现未发现 TODO/FIXME、空实现或被截断函数；EPUBDisplayTransform 是任务明确要求保留的未来接口。

## 本轮补齐与最终改动清单

| 文件 | 最终行为 / 本轮工作 |
| --- | --- |
| `Tingye/TingyeApp.swift`、`ReaderRouter.swift` | selectedBook 唯一根入口集中分流：漫画 → 可解码 PDF → EPUB → 原生。PDF 的条件沿用 Book.pdf 的 base64 解码口径，不额外检查 PDF 文件签名；缺失/非法 pdf 且格式为 EPUB 时进入 EPUB。 |
| `Tingye/Readium/ReadiumReaderView.swift` | StateObject 持有会话、Publication、Store 与 pin；原包/派生包共用 prepare→pin→open。新增同书打开幂等、取消后的明确错误/重试、加载期间最新 readerJump 接力、非法章拒绝及失败回调屏障。未映射的原包额外资源可显示，但不保存旧章坐标，听书按钮暂不可用。目录保留层级，无 TOC 则回退文本章；听书从已映射当前章第 0 句开始，使用原 PlayerView/SpeechPlayer。 |
| `Tingye/Readium/EPUBNavigatorHost.swift` | 包装 3.11.1 Navigator；新增初始化完成后的请求排队、跳转 UUID 确认、取消旧导航任务与旧 Navigator 回调隔离。目录改用 go(to: Link)，交 Publication.locate 保留 fragment；资源错误反馈容器。内部链接仍交 Navigator，外链交系统。 |
| `Tingye/Readium/ReadiumPreferencesBridge.swift` | 映射同套 ReaderPreferences；reflowable 关闭 publisherStyles，fixed-layout 仅传画布背景与 spread。补记 Toolkit 负字距限制。 |
| `Tingye/Readium/ReadiumFontProvider.swift` | system、四个内置、自定义字体均复用原键；可读文件才声明 CSSFontFamilyDeclaration/CSSFontFace，缺失回退 system。修复 TTC fragment 被 Readium 本地字体 URL 改写丢弃的问题：在 servingFile 返回 WebView 地址后附加 face。字体切换时刷新清单，导入/删除退出面板时再刷新。 |
| `Tingye/Readium/PublicationMap.swift` | 保留上一轮原包规范路径优先/唯一标题后备；新增独立测试覆盖额外 spine 项、中文编码路径和重复标题拒绝。 |
| `Tingye/Readium/EPUBDisplayTransform.swift` | 仅保留显示资源转换协议、不可改原文合同和映射接口；未执行简繁转换。 |
| `Tingye/Theme.swift` | 原生和 EPUB 共用 ReaderPaper.resolve；七纸面各自背景/正文/次字一起决定日夜，宣纸 xuan 背景也从同一解析器取得。常亮修正只统一明暗决策，未改 PLAN 颜色值。blue/night 在常亮时仍为原本的深纸。 |
| `Tingye/ReaderView.swift` | 保留上一轮共用解析和 ReadingPreferencesView.showsPreview 参数（默认 true）；EPUB 复用原设置面板并关闭示例文字，MoreTypographyView 写入的原 AppStorage 键即时应用。 |
| `Tingye/Typography.swift` | 保留上一轮 MyFontsView 默认 system；未新建字体偏好键。 |
| `Tingye/AppModel.swift` | 保留上一轮每库共享 Store 和 loadLibrary 重置；阅读位置使用原 saveProgress，无第二套持久化。 |
| `Tingye.xcodeproj/project.pbxproj` | 六个新 app 文件分别有唯一 FileReference/BuildFile，入 Readium Group 与 app Sources；新测试入 TingyeTests Group/Sources。测试直接 import Navigator，补其 product/Frameworks；未改包版本或锁文件。 |
| `create-project.rb` | 原已递归扫描 app Swift 和测试文件，只补测试 Navigator 链接，防止以后重新生成工程丢失该声明；未运行生成器。 |
| `TingyeTests/ReadiumPreferencesTests.swift` | 12 个用例：七纸面完整日夜/常亮矩阵、字号/行框、段距/边距/缩进/对齐/字距、滚动/宽窄/双栏/eink、fixed 子集、路由优先级及不猜格式、原包映射、进度比例钳制、缺字体、TTC URL 改写、取消→重试→重复打开复用 Publication/单 pin。未新增二进制夹具。 |
| `Tingye/Resources/Localizable.xcstrings` | 增加 7 条 EPUB 打开/失败/取消/重试提示及能力说明，覆盖简中/繁中/英文/日文；既有目录条目保持原值。 |

## 换算依据与支持范围

按固定 **Readium 3.11.1** 源码核对了 [EPUBPreferences](https://github.com/readium/swift-toolkit/blob/3.11.1/Sources/Navigator/EPUB/Preferences/EPUBPreferences.swift)、[ReadiumCSS](https://github.com/readium/swift-toolkit/blob/3.11.1/Sources/Navigator/EPUB/CSS/ReadiumCSS.swift)、[CSSProperties](https://github.com/readium/swift-toolkit/blob/3.11.1/Sources/Navigator/EPUB/CSS/CSSProperties.swift) 与 [字体声明接口](https://github.com/readium/swift-toolkit/blob/3.11.1/Sources/Navigator/EPUB/CSS/HTMLFontFamilyDeclaration.swift)，没有按 4.x API 实现。

| 输入 | EPUB 映射与依据 |
| --- | --- |
| paper / 外观 / alwaysLight | resolve 先产生实际 UInt32 RGB，再传 backgroundColor/textColor/theme。七纸面 14 组 RGB 与 PLAN 表一致。常亮同时锁背景和文字；固定深纸仍用 dark theme。 |
| fontSize（pt） | `fontSize / 16` 倍率；Readium 转为 CSS 百分比，按 WebKit 默认 16 CSS px 基准取 19 → 1.1875（118.75%），目标接近原生 19pt。是逻辑尺寸校准起点，尚未用真机验证视觉等效，不宣称已完成视觉校准。 |
| lineSpacing（pt） | `(选用 UIFont.lineHeight + lineSpacing) / fontSize`，下限 1；系统/内置/自定义以实际可用 UIFont metrics 为准，缺文件按系统 metrics。原生正文是 UIFont + paragraph.lineSpacing，不采用旧 WebKit 的 1.35 系数。测试注入 metrics，不依赖设备字体数值。 |
| paragraphSpacing（pt） | `paragraphSpacing / fontSize`；Readium 写 paraSpacing 为 rem，以当前根字号估算原 pt 间距。19pt 默认段距为 15/19 rem。 |
| margin（pt） | 固定 RS pageGutter 基线 24 CSS px，pageMargins = margin/24；默认 24 → 1，48 → 2。Readium CSS 决定最终分栏/安全区边距，宽屏视觉仍待校准，不承诺所有视口都与原生像素相同。 |
| indent | 开启传 2，关闭传 0；Toolkit 将 paraIndent 写为 rem，在强制根字号的普通正文约等于两字/2em，嵌套异字号段落仍需视觉检查。 |
| justified | true → justify，false → start。 |
| letterSpacing（pt） | `2 * max(0, value) / fontSize`；3.11.1 ReadiumCSS 再除以 2 写 rem，例如 20pt 的 2pt 字距传 0.2，最后为 0.1rem。Toolkit EPUBPreferences 不支持负字距（初始化钳制至 0），EPUB 对 -1…0 取 0，保留原设置值供原生格式使用。 |
| scrolling / doublePage | scroll 使用原值；只有分页、doublePage=true、宽度 >650、非 eink 才 columnCount=two，其他情况 one；旋转/窗口宽度变化重新计算。fixed-layout 使用相同双页条件决定 spread，未传重排字体/页内文字色/行距等。 |
| font / convert / pageTurn | 字体保留 system/serif/kai/hansans/xixihei/custom:PostScript 键；缺文件静默回退系统。convert 仅存原值，EPUB 明示未支持；fade/blur 等值保留，使用 Navigator 标准翻页，不创建新设置。 |

偏好由原 AppStorage 改变触发 SwiftUI 更新，Coordinator 仅在 EPUBPreferences 有差异时 submitPreferences，不重放 initialLocation。3.11.1 [Navigator](https://github.com/readium/swift-toolkit/blob/3.11.1/Sources/Navigator/EPUB/EPUBNavigatorViewController.swift) 的重新分栏/重载路径从 currentLocation 恢复；字体文件清单变化才重建 child，并把旧 currentLocation 作为新 initialLocation，且隔离旧实例回调。仅核对了代码路径，真实字号重排、分页边界和旋转仍待设备验证。

阅读位置使用 `sentenceIndex / max(1, sentenceCount)` 估算资源内 progression，逆向 floor(progression * sentenceCount) 并钳制到最后一句。旧进度先用 142 TextAnchor 在文本章解析，再按路径/唯一标题选资源；派生包按其确定映射选资源。不把 Readium locations.position 当句号。显式跳转仍只有资源内比例精度；成功改变章句后由 saveProgress 刷新兼容 TextAnchor；章句相同时沿用 sync.update 的去重，保留原进度/anchor，不制造新时间戳。精确 DOM/Locator 属于单元 3。

## 边界自查与依据

| 边界 | 最终代码处理路径 |
| --- | --- |
| 打开取消 / 失败重试不黑屏 | Session.open 用局部 acquired 持有未发布 pin；任何错误先 release。仍有效的可见尝试被取消时设置明确错误和重试；已 close 的尝试 generation 不符则不发布结果。View 有 loading、错误卡、重试、始终可见的返回；重试重新 open，清除旧请求屏障。 |
| 偏好变化后位置不跳 | Host.update 的普通偏好分支只 submitPreferences；字体重建传 currentLocation，取消旧 go 并屏蔽旧 delegate，已处理的请求 UUID 不重复执行。 |
| 退出释放 pin | onDisappear 先清 readingSurface、保存最终稳定位置、readerClosed 刷盘，再 session.close。close 换 generation 并清 Publication/map/initialLocation，对已接收 pin 异步 release；尚在打开的局部 acquired 由 catch release。deinit 也有兜底。 |
| 同书重复打开不重复会话 | @StateObject 保留 Session，task 只随 retry ID 重开；Session.open 对同 book.id 且 loading 或已持有 Publication、无错误的情况直接返回。AppModel 共享 Store 合并重建，Session 重复 open 也不再 pin。 |
| readerJump 消费和失败保留 | open 先取显式目标，非法章/路径和非唯一标题映射失败显示错误，保留 model.readerJump。准备期间收到新目标，完成后发最新请求；已有 Navigator 等首次位置回调后执行 go。期待资源与请求 UUID 两层屏障防止默认页、旧同资源请求覆盖；go 成功并确认目标章才消费，出错后的 location 回调不消费、不回写。 |
| 进度独立 / 旧引用不改 | persist 仅在 ready、已映射、无错误、无未完成目标时调用 AppModel.saveProgress；该函数走 sync.update、locatorAnchor、KVS、1200ms scheduleCatalogSave，只赋值 entries[i].progress。退出调用 readerClosed/flushPendingSaves；未改 listeningProgress/bookmarks/highlights，也未创建 Decoration 或重写 Book 文本。 |
| 正文统计口径 | updateVisibility 仅在页面出现、ready、无错误且未展开 PlayerView 时标 visible；设置和目录沿用原生仍算阅读的口径。退出清 visible。沿用 TingyeApp 同一个 5 秒 tick 和 AppModel 前台正文优先/后台非 buffering 音频的互斥判断，没有新增定时器。 |
| 资源不对应旧文本章 | 保留书内浏览与资源标题，mappedChapter=false 阻止 persist 并禁用错误的听书起章；不会把上一章句坐标写到额外资源。 |
| 字体文件缺失 / TTC | files 过滤不存在/不可读文件，family 与 lineHeight 均回退 system；CSS 声明有 system/sans-serif 后备。TTC face 在 WebView URL 改写后附 fragment。测试只检查声明生成，实际 WebKit/TTC face 选择仍待验证。 |

上述各项为静态源码核对；取消/重复打开额外有异步 XCTest，**本机未执行**。pin 的 actor release、缓存清理保活与原生阅读/听书互斥还应结合单元 1 的 Store 测试和现有 NativeCoreTests 在 Mac 回归，不能把代码路径存在当作设备验收通过。

## 实际验证记录

本环境为 Linux；`command -v swift`、`command -v xcodebuild` 均无可执行文件。本轮没有 Swift 编译、SPM resolve、XCTest 运行、模拟器/真机运行、archive、EPUBCheck，也未启动或观察 CI。

已执行并通过的检查：

- `/tmp/readium-unit2/validate_project.py`：完整 OpenStep tokenizer/parser 解析 pbxproj，共 189 个对象；全部对象引用存在、Group 引用/各 target 的 phase 与 product/Frameworks 一致；六个新 app 文件和测试各唯一挂接，Sources 文件实际存在。四处显式 CURRENT_PROJECT_VERSION 均为 142；对比修改前工程，各配置原值保留。与单元 1 同为结构解析检查，不是仅搜索文件名。
- `/tmp/readium-unit2/validate_sources.py`：16 个相关 Swift 文件定界符、注释/字符串闭合及行尾空白检查；Readium 和新增测试无 TODO/FIXME/fatalError；Router 判据顺序检查；12 个 XCTest 方法存在。此脚本不解析 Swift 类型或 actor 隔离，不等同编译。
- 语言目录 JSON 可解析，7 个新增状态含四种语言；新增前已存在的条目值逐项相等。
- `.github/workflows/*` 与 Package.resolved 的本轮前后 SHA-256 相同；未改构建号，未运行工程生成器，无任何 git 命令。

建议 Mac/CI 下一步执行新增 ReadiumPreferencesTests、ReadiumPublicationTests 和全量 TingyeTests，再做定向 EPUB UI 与 unsigned archive；本轮未改 workflow，也未宣称这些检查已通过。

## 未做项与 PLAN 单元 2 逐条验收

| PLAN 单元 2 验收 | 状态与剩余验证 |
| --- | --- |
| 所有 EPUB 经书架/详情/自动续读进入 Navigator；其他格式原引擎 | **已实现、路由测试已写，未执行。** selectedBook 根入口统一；各已有入口保留，章句跳转在 EPUB 消费。其他格式未改导入/渲染分支；原生纸面只做任务授权的共用解析及常亮修正。需全入口 UI 回归。 |
| 新原包、旧派生包可读，翻章/内部链接/TOC 层级 | **代码已接，未 UI 实测。** 原包 readingOrder/TOC，派生包确定映射/平铺 TOC，无 TOC 回退文本章；目录走 Link，外链交系统；原包/派生包解析沿用单元 1 测试。 |
| 七纸面×日夜、alwaysLight | **纯函数测试已写，未运行/视觉验收。** 显式 RGB 期望表覆盖全组合，颜色未改值。 |
| 字号/行距/段距/边距/缩进/对齐/字距 | **已映射、测试已写，未运行/真机校准。** 换算依据如上；负字距受 Toolkit 下限限制。 |
| 四内置/自定义字体、缺文件回退 | **已接、回退与 TTC 声明测试已写，未 WebView 实测。** 完整/瘦身 IPA、TTF/OTF/TTC 均待设备验证。 |
| 滚动/分页/横竖屏/宽屏双栏 | **判定已实现、边界测试已写，未 UI 实测。** 650 阈值、滚动/eink/开关限制均覆盖；真实旋转与分页位置仍需检查。 |
| fixed-layout 与竖排专门样本 | **fixed 偏好子集测试已写；专门样本未做、未实测。** 不强行覆盖出版物方向/页内样式，仍需原包样本验证。 |
| 偏好变化保留当前位置 | **已有明确处理路径，未设备验证。** submitPreferences 保留当前 Navigator；字体列表变动以 currentLocation 重建。 |
| 简繁资源转换及原文 Locator/显示选区往返 | **按任务书仅留接口，未实现/未验收。** 不修改源包、Book.text 或用户 convert 值；单元 3/4 与 TextDOMIndex 联验，最终切换发布仍受此门槛限制。 |
| 阅读统计同一 visibility，无重复计时 | **已接同一入口，未运行回归。** 设置/目录仍计阅读，PlayerView 暂停正文统计，后台由既有 tick 决定听书；现有 NativeCoreTests 的独立进度/usage 用例未更改。 |
| 资源级近似恢复，精确引用留单元 3 | **已实现、比例/原包映射测试已写，未运行。** 显式跳转失败保留请求，不静默回第一章；完整 Locator 持久化、四类引用迁移、划线/书签 Decoration 与选区创建均未做。 |

未移植原生自动翻页、书内搜索/跟读等超出本任务书基础 chrome 的能力；听书当前仅按章起播，精确句级联动留单元 4。未做新性能、低存储、异常杀进程实测，也未审计完原包脚本/隐式网络资源策略；这些仍在 PLAN 后续全量验收范围。没有新增二进制夹具，没有删除或重写既有划线/书签数据。
