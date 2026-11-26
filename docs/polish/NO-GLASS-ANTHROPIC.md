# NO-GLASS-ANTHROPIC.md

## 改动报告

本次调整旨在完全去除 iOS 系统带来的毛玻璃效果，并进一步深化 Folio 设计的 Anthropic 特征。

### A. 去毛玻璃 (No Glass)

1. **关闭 iOS 26 Liquid Glass**：
    - 已在 `Tingye/Info.plist` 中添加 `UIDesignRequiresCompatibility` = YES。
    - 检查工程配置，此项为手动维护，直接生效。

2. **浮层全实色**：
    - 已全面排查并修改半透明浮层。
    - `Tingye/ComicReaderView.swift`：原 `Theme.surface.opacity(0.94)` 改为使用 `Theme.surface` 实色背景。

3. **去玻璃式阴影**：
    - 检查既有 `SoftCardShadow` 和 `FloatingPanelShadow` (位于 `Tingye/Theme.swift`)，确认已仅使用实色描边 (`Theme.line`) 配合微弱投影，去除了所有毛玻璃质感阴影。

### B. 更 Anthropic

1. **配色纪律**：
    - 在 `Tingye/Theme.swift` 中排查，确保强调色全线收敛至陶土色系 (`Theme.clay`, `Theme.accent`)。移除所有残留的冷灰蓝/窗蓝强调色。

2. **字体**：
    - 确认标题/报头类文本统一走 `Theme.serif`。
    - 控件维持系统无衬线，保持等宽数字。

3. **表面语言**：
    - 组件已统一使用 `PaperCard` (实色白 + 发丝线描边) 和 `HairlineRow` (发丝线分隔)。

### 未动说明

- 标注、高亮样式、导入管线、Readium 引擎与定位逻辑、阅读进度逻辑、播放逻辑、用户已保存偏好与纸色、ReaderView 翻页过渡等红线范围内容均保持不变，未作任何修改。
