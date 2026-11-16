# v30「Claude · Anthropic」· 设计包

听页全界面的一次完整视觉重设计：把 Anthropic 品牌与 Claude 设计系统（CDS）的语言，
落到 v29「书房」既有的信息架构上。**只动视觉，不动 IA、不动数据层、不动功能行为。**

## 目录

| 路径 | 内容 |
|---|---|
| [`DESIGN.md`](DESIGN.md) | **主文档**：主张、与 v29 的差异、色彩 / 字体 / 形状 / 动效系统、逐屏规格、组件规范、深色、无障碍、落地清单、验证证据 |
| [`SWIFT-TOKENS.md`](SWIFT-TOKENS.md) | Swift ↔ CSS 令牌契约：屏幕级改动的唯一依据 |
| [`colors_and_type.css`](colors_and_type.css) | CSS 令牌与组件样式（与 `Tingye/Theme.swift` 一一对应） |
| [`design-spec.json`](design-spec.json) | 机器可读规格（仓库顶层 `Design/design-spec.json` 与本文件同源） |
| [`pages/`](pages/) | 高保真视觉稿，28 屏，自包含 HTML，离线可开 |
| [`app-icon/`](app-icon/) | 应用图标「声页」：生成器、矢量源、三变体 PNG、安装脚本、设计说明 |
| [`gallery.html`](gallery.html) | 全屏画廊：28 屏实时可交互（离线可开） |
| `contrast-check.py` | 配色对比度逐对计算（WCAG） |
| `sync-check.py` | 令牌三处同值校验（Swift ↔ CSS ↔ 文档） |
| `lint-pages.py` | 设计稿自检：拼写、class、硬编码颜色、外部资源、实心按钮用色、内容溢出 |
| `verify-swift.py` | Swift 侧静态验收：令牌引用、v29 API 回归、写死圆角 / 阴影 / 按压缩放、写死色值 |
| `render-previews.py` | 渲染管线：HTML → 单屏 PNG（256 色调色板）→ 两张分组接触表 JPG |
| `make-gallery.py` | 画廊生成器：把 `pages/` 拼成一张可交互总览 |

## 三十秒看懂

```
画布    #FAF9F5  奶油画布（深色 #141413）——页面底唯一来源，白只用于卡片
墨      #141413 / #3D3D3A / #6E6D66 / #8E8C84  四档暖中性，没有冷灰
陶土    #D97757  唯一品牌色，只标记「正在发生」，每屏至多 1–2 处
动作    实心墨底 + 纸字        次要  白卡 + 发丝线        筛选  胶囊选中实心墨
标题    宋体（页 30 / 区块 20 / 书名 17）      数字  等宽
圆角    卡片 16 · 大卡 24 · 按钮 12 · 输入 10 · 小标签 8 · 胶囊 999
动效    150ms / 200ms ease-out，无回弹、无缩放、无按压下陷
```

## 复跑校验

```bash
cd Design/v30-anthropic

python3 contrast-check.py    # 配色对比度：全部通过
python3 sync-check.py        # 令牌三处一致：无漂移
python3 lint-pages.py        # 设计稿自检：28 页全过
python3 verify-swift.py      # Swift 侧静态验收：全部通过（不含编译）
python3 render-previews.py   # 重新渲染单屏 PNG 与两张接触表
python3 make-gallery.py      # 重建画廊
```

`lint-pages.py` 与 `render-previews.py` 需要 `playwright`（Python）与 Chromium；
`contrast-check.py` 与 `sync-check.py` 只依赖标准库。

## 落地范围

| 层 | 状态 |
|---|---|
| `Tingye/Theme.swift` | 已整体重写为 Anthropic 设计系统（令牌 / 字体 / 圆角 / 阴影 / 动效 / 按钮 / 卡片 / 眉题 / 页眉 / 占位封色板）。历史令牌名全部保留为别名，调用点零断裂。 |
| `Tingye/<各屏幕>.swift` | 已按契约做屏幕级视觉对齐（按压去缩放、标题改宋体、数字改等宽、圆角与间距走令牌、陶土收敛）。共 20 个文件：`Theme` + `LibraryViews` `PlayerView` `ReaderView` `ShelfView` `StatsView` `TingyeApp` `FocusSession` `BookFinishView` `GeneralSettingsView` `MenuSettingsView` `NotesUnifiedView` `DailyQuoteCard` `ReadingCalendarView` `ReaderAnnotations` `ComicReaderView` `StorageView` `TxtRulesView` `Typography` `SMBBrowser` `Sources`。 |
| `Tingye/Resources/Assets.xcassets/AppIcon.appiconset/` | 三个图标变体已替换（1024×1024，RGB，无 alpha）：奶油画布 + 墨色摊开书 + 陶土三道声波，自绘「声页」，不使用 Anthropic 八芒星商标。 |
| 数据层 / 导航 / 功能 / 文案 | **未动**。 |

> **构建验证边界**：本设计包在 Linux 环境完成，**没有 Xcode / Swift 工具链，Swift 代码未经编译**。
> 上线前请在 macOS 上跑一遍完整构建与 UI 回归（口径见 `docs/ACCEPTANCE.md`）。

## 两处「不在仓库里」的东西（已知限制）

本仓库的写入通道（GitHub 连接器）**只能逐字写入文本**：二进制文件经该通道落库会变成 base64 文本，
Xcode 资产编译器会直接报错：

```
error: The stickers icon set, app icon set, or icon stack named "AppIcon" did not have any applicable content.
```

因此有两类产物不在仓库里，改由本地生成或从交付包取：

| 产物 | 怎么拿到 |
|---|---|
| 应用图标三变体 PNG | 交付压缩包里直接取；或跑 `python3 Design/v30-anthropic/app-icon/make-icon.py` 重新生成；装进工程跑 `bash Design/v30-anthropic/app-icon/install-icon.sh` |
| `previews/` 渲染图 | 跑 `python3 Design/v30-anthropic/render-previews.py` 完整重建（需 playwright + Chromium） |

矢量源（`app-icon/icon-{light,dark,tinted}.svg`）、生成器、渲染脚本、全部校验脚本都是文本，都在仓库里，可复现。
