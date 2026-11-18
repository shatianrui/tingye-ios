# 跟读高亮热修

v31 单元 C 为 Readium 增加了带 2px 陶土左边框的跟读模板。`ReadiumReaderView` 在把当前句装饰交给 Navigator 前统一换成该模板的专用样式，覆盖了 `ReadiumSpeechBridge` 原有的 `.highlight`。同一轮改动也在原生 CoreText 和 TextKit 的跟读浅底上额外绘制了左侧竖线。

## 与构建 144（`a091f60`）逐项对应

| 路径 | 恢复与核查结果 |
|---|---|
| `ReadiumAnnotations.swift` | 删除跟读专用样式 ID 和模板。整个文件与 144 一致，默认模板透明度为 `0.28`，波浪线模板仍用于用户划线。 |
| `ReadiumReaderView.swift` | 恢复 144 的 `speechDecorations: speechDecorations` 透传。桥接层生成的当前句 `.highlight` 由默认模板填充，Navigator 继续通过独立的跟读分组应用装饰。`palette` 继续用于正文链接和选区颜色。 |
| `ReaderView.swift` 分页 | 删除 CoreText 每行左侧的附加竖条，按当前句各字形段的宽度与高度铺 `prefs.highlight`。144 的跟读底部还有一道 2pt 横线，本次呈现仅使用填充带。用户划线「浅底」仍由 144 的 `ReaderMark.draw` 填充字形框。 |
| `ReaderView.swift` 连续滚动 | 删除 `ReaderScrollTextView` 的竖条绘制及其专用范围状态。恢复 144 的 TextKit 路径，由 `.backgroundColor` 分别铺满用户划线「浅底」和当前句。跟读继续使用 `prefs.highlight`。 |
| `OriginalBookView.swift` | 现有实现为横向分页的 WebKit 原书视图。144 用内联 `<mark>` 包住当前句各段文字，并以渐变填充文字底部。本次沿用选段范围，将渐变改为覆盖整个文字范围的浅底，颜色取 `preferences.highlight`。当前路由由 `ReaderView` 渲染原生标注，由 Readium 渲染 EPUB 标注，原书视图本身只处理跟读。 |

原生跟读浅底继续按 `ReaderPaper` 解析为浅纸 `#F7EAE3` 或深纸 `#3E2A21`。用户划线使用上一热修恢复的五色调色盘和历史颜色键。 [划线与高亮调色盘热修](HOTFIX-highlight-palette.md)

## 验证

- 对照 `a091f60` 核查 Readium 模板、跟读装饰传参及桥接层的样式创建。全仓搜索中，剩余左边框用于引文和设计稿等其他内容。原书 HTML 中的跟读数据属性沿用 144，用于定位、清除和跟随当前句的 `<mark>`。
- 移除固定跟读竖线颜色的测试断言，保留明暗纸色、浅纸常亮、浅底透明度和最低文字对比度断言。原书跟读测试增加跨标签浅底填充断言，并保留原有的范围、清除和跟随检查。
- 源码成员检查和源码静态核查通过。原书注入脚本通过语法检查，并在模拟 DOM 中验证跨节点的纯色背景与清除行为。当前 Linux 环境缺少 Xcode，iOS 编译、XCTest 和模拟器视觉验证待运行。
