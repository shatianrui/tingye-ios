# 听页 · v30「Claude · Anthropic」Swift 令牌契约

> 本文件是 `Tingye/Theme.swift` 与 `Design/v30-anthropic/colors_and_type.css` 的映射表。
> 改任何一���，另一处同提交更新。

## 1. 颜色

| CSS 变量 | Swift 令牌 | 日间 | 深色 | 用途 |
|---|---|---|---|---|
| `--ty-canvas` | `Theme.bg` | `#FAF9F5` | `#141413` | 页面底（**永远是奶油画布，不是纯白**） |
| `--ty-surface` | `Theme.surface` | `#FFFFFF` | `#1F1E1D` | 卡面、输入框、次按钮底 |
| `--ty-surface-subtle` | `Theme.surface2` | `#F0EFE6` | `#2A2926` | 分段轨道、听条底、沉底 |
| `--ty-surface-sunken` | `Theme.surfaceSunken` | `#F7F6F0` | `#232220` | 隔行、占位块 |
| `--ty-ink` | `Theme.ink` | `#141413` | `#FAF9F5` | 标题墨 |
| `--ty-ink-strong` | — | `#1F1E1D` | `#EFEDE6` | （并入 `ink2` 之上层） |
| `--ty-ink-2` | `Theme.ink2` | `#3D3D3A` | `#C2C0B6` | 正文副色 |
| `--ty-ink-3` | `Theme.ink3` | `#6E6D66` | `#98968E` | 说明文字 |
| `--ty-ink-4` | `Theme.ink4` | `#8E8C84` | `#73726C` | 时间戳、页脚 |
| `--ty-line` | `Theme.line` | `#E7E6E1` | `#2C2C33` | 发丝线（0.5–1pt） |
| `--ty-line-field` | `Theme.lineField` | rgba(31,30,29,.15) | rgba(250,249,245,.18) | 输入框描边 |
| `--ty-clay` | `Theme.clay` | `#D97757` | `#D97757` | 陶土**面**（进度段、印章点、图标） |
| `--ty-clay-emph` | `Theme.clayEmph` | `#C6613F` | `#E08C6E` | 陶土按下态 |
| `--ty-clay-text` | `Theme.accent` | `#A34E2B` | `#F0AD88` | 陶土**文字**（链接、当前章、眉题编号） |
| `--ty-clay-soft` | `Theme.accentSoft` / `Theme.claySoft` | `#F5E7DF` | `#472E25` | 陶土淡底（跟读带、选中行） |
| `--ty-on-clay` | `Theme.onClay` | `#141413` | `#141413` | 压在陶土面上的字 |
| `--ty-danger` | `Theme.danger` | `#B53333` | `#FF9FAD` | 删除、错误 |
| `--ty-focus` | `Theme.focus` | `#2D7FD8` | `#5AA9F0` | 唯一的冷色，仅焦点环 |

**陶土纪律**：每屏至多 1–2 处陶土。陶土只标记「正在发生」——当前章、在读印章点、进度已读段、跟读竖条、眉题编号。**不用于**：大面积按钮底、分段选中态、卡片底色。

## 2. 字体

| 角色 | Swift | 规格 |
|---|---|---|
| 界面（按钮、列表、设置） | `.system` / `Theme.sans` | 15pt，medium |
| 页标题、书名、章节题、摘句 | `Theme.serif(n)` | 思源宋体 Regular，**不合成粗体** |
| 区块标题 | `Theme.serif(20)` | 宋体 |
| 统计大数字 | `Theme.display(n)` | 等宽数字 semibold |
| 页码 / 时间戳 / 序号 | `Theme.mono(n)` 或 `.monospacedDigit()` | 等宽 |
| 眉题 | `Theme.masthead` + `.tracking(Theme.kickerTracking)` | 12pt medium + 字距 1.6 |
| 正文 | 用户偏好字体 | 不动 |

**层级只靠字号 + 留白 + 发丝线**，不用粗体堆叠。

## 3. 圆角 / 间距 / 阴影

| 用途 | Swift | 值 |
|---|---|---|
| 卡片 | `Theme.radius` | 16 |
| 大卡、升起面板、播放器头 | `Theme.heroRadius` | 24 |
| 小标签、书封 | `Theme.radiusSmall` | 8 |
| 输入框 | `Theme.radiusField` | 10 |
| 按钮 | `Theme.buttonRadius` | 12 |
| 胶囊 | `Theme.radiusPill` | 9999 |
| 书封圆角 | `Theme.coverRadius(width)` | `min(10, width × 0.09)` |
| 间距刻度 | `Theme.space1` `space2` `space3` `space4` `space5` `space6` `space7` `space8` | 4 / 8 / 12 / 16 / 20 / 24 / 32 / 48 |
| 页面水平边距 | `Theme.inset` / `Theme.insetCompact` | 24 / 20 |
| 内容最大宽 | `Theme.pageWidth` | 720 |
| 静息卡面阴影 | `.softCardShadow()` | 黑 4%，半径 20，y 4 |
| 浮层 | `.floatingPanel()` | 黑 8%，半径 16，y 4 |

**禁止**：在页面里写死圆角数字（`RoundedRectangle(cornerRadius: 10)` 之类）；自己写 `.shadow()`（除系统 popover）。

## 4. 组件

| 组件 | Swift | Anthropic 语汇 |
|---|---|---|
| 主按钮 | `PrimaryButtonStyle` | 实心墨底 + 纸字，圆角 12，文字 15pt medium |
| 次按钮 | `SecondaryButtonStyle` | 白卡 + 发丝线 + 墨字 |
| 文字按钮 | 自定义 | `Theme.accent` 字，无下划线 |
| 筛选 / 分段 | `ChipPillStyle` | 胶囊；选中实心墨，未选中沉底 + 发丝线 |
| 卡片 | `Card { }` / `.glassCard()` | 白卡 + 发丝线 + `.softCardShadow()` |
| 列表行 | `RowDivider` | 行间 0.5pt 发丝线，**无卡壳** |
| 图标按钮 | `CircleIconButton` | 44pt 命中区，无底无描边 |
| 按压反馈 | `PressButtonStyle()` | 只变透明度 0.85；**不传 scale** |
| 区块标题 | `SectionTitle` | 宋体 20pt |
| 页眉 | `PageMasthead` | 眉题行 + 宋体 30pt 大标题 |
| 状态标签 | `SealBadge` | 陶土淡底 + 陶土字 |
| 进度 | `ProgressBar` | 轨道发丝线，已读段陶土 |

## 5. 动效

- 只用 `Theme.pressSpring`（150ms ease-out）与 `Theme.smoothSpring`（200ms ease-out）。
- **不回弹、不缩放、不按压下陷**。按压只有透明度 0.85。
- 「减少动态效果」照旧由 `ReducedMotionPolicy` 统一拦截。

## 6. 硬规则清单（自检用）

1. 页面底永远是 `Theme.bg` / `.paperBackground()`，不出现纯白底。
2. 不出现冷灰（带蓝调的灰）；墨色梯度只有暖中性四档。
3. 卡片是白面 + 发丝线，不要「灰底 + 深色卡」。
4. 陶土不铺大面积。
5. 圆角、间距一律走令牌。
6. 标题用宋体，正文用系统体，数字用等宽。
7. 图标走 `Icon` 枚举 / `ThemeIcon`，不直接写 SF Symbol 名。
8. 状态一律双通道：颜色 + 文字或形状（不只靠颜色）。
9. 不改任何功能行为、数据协议、导航结构、文案语义。
