# 划线与高亮调色盘热修

以 `a091f60`（构建 144）为基准，恢复标注的存储键取色、新建调色盘和选段面板的颜色及样式控件。

## 与构建 144 的对应

| 项目 | 恢复结果 |
|---|---|
| `ReaderMark.palette` | 按 144 的顺序恢复琥珀 `yellow` `#D69E3A`、陶土 `clay` `#A34F36`、蓝 `blue` `#4A6FA5`、粉 `pink` `#C85A53`、紫 `purple` `#7E629E`。 |
| `ReaderMark.uiColor(_:)` | 删除三档映射。五色按存储键取色，历史 `green` 显示 `#4E8E75`，未知键按 144 的规则显示琥珀。构建 145 引入的 `ink` 和 `gray` 也走该回退，原存储键保留。 |
| `ReaderMark.newColor(_:)` | 最近选色为五色之一时沿用，其余值（含 `green` 和未设置）回退到 `clay`。编辑旧标注时直接加载已存颜色键，只改样式时沿用该键。 |
| 选段面板 | 恢复 144 的 24pt 实色圆点、颜色名、按键精确匹配的白色勾选和选中淡底。样式恢复带图标的「浅底」「直线」「波浪线」胶囊按钮，对应 `Icon.highlight`、`Icon.underlineStyle`、`Icon.wavyStyle`。原生与 Readium 共用该控件，并使用同一套 v31 面板前景色。 |
| Readium 标注 | `ReadiumAnnotations.decorations` 已传入 `Highlight.color` 原键，`style(color:kind:)` 已调用 `ReaderMark.uiColor`。浅底、直线、波浪线均由共享修复恢复原色，波浪线模板的琥珀回退也同时恢复。 |

## 全仓核对的其他路径

- 原生分页的 CoreText 绘制和滚动的 `UITextView` 标注都通过 `ReaderMark.style` 取色，按存储键恢复。
- 书籍详情、原生目录、Readium 目录等使用 `NotesList` 的摘记行，圆点和引文竖线均通过 `ReaderMark.color(note.color)` 恢复。
- Readium 搜索命中调用 `ReadiumAnnotations.style(color: "yellow", kind: "background")`，恢复 144 的琥珀浅底。
- 原生直接写笔记和 Readium 新建标注草稿均通过 `ReaderMark.newColor` 恢复 144 的最近选色规则。全仓搜索未发现第二处三档映射。

## 保留的 v31 部分

保留选段面板的卡片、圆角、间距、宋体标题、工具分段和墨底保存按钮。跟读样式的后续修复见 [跟读高亮热修](HOTFIX-speech-highlight.md)。标注位置、ID、存储格式、构建号 145 和 workflows 均保持原样。

## 验证

- 与 `git show a091f60:Tingye/ReaderAnnotations.swift` 逐段比较，`ReaderMark` 及两个控件行与 144 一致。Readium 用户标注的着色和定位路径与 144 一致。
- `ReadiumLocatorTests` 恢复五色期望，独立核对六种 144 颜色的 RGB、未知键回退和新建默认色。保留八个存储键在三种样式下的装饰数量、ID、颜色、样式、未定位结果、分组和模板断言。
- 源码成员检查通过（56 个 Swift 文件），`git diff --check` 通过。当前 Linux 环境没有 Xcode，未执行 iOS 编译、XCTest 或模拟器视觉验证。
