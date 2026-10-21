# 听页 · 原生 iOS / Mac Catalyst

纯 Swift / SwiftUI 本地阅读与听书应用，最低 iOS 17。当前工程及最新 TestFlight 上传版本为 **1.23.0（112）· v20「刊 · Folio」+ 参照 PureLibro 补齐的功能与四种界面语言**（见[发布历史](docs/RELEASE_HISTORY.md)）。iOS/iPadOS 与 Mac Catalyst 均已收到 Apple 上传成功回执，回执为处理中；**尚未确认 TestFlight 可安装**，未提交正式 App Store 审核。

2026-10-22 完成 **v20「刊 · Folio」杂志排版重设计**（用户选定方向，主色指定为 Claude 陶土橙 `#D97757`）：象牙纸 `#FAF9F5` / 炭黑 `#141413`、报头双线与编号、宋体大标题、直角块状按钮；页签改为 `01/02/03` 编号 + 宋体「书 / 读 / 己」与陶土下划线；听书页为大号引语 + 陶土播放块 + Ⅰ–Ⅳ 工具栏。**应用图标改为报头式「听」**（双线 + 宋体「听」+ 陶土题条 + NO.20，日间 / 深色 / 着色三变体，1024px 无 alpha）。[Figma 原稿](https://www.figma.com/design/evqePR3n5p2o0ToOVKtfKX)、[设计说明](Design/v20-folio/DESIGN.md)、[日间](Design/v20-folio/runtime/light-overview.jpg) / [深色](Design/v20-folio/runtime/dark-overview.jpg)运行截图。功能、导航、数据协议与已保存的阅读偏好不变。随后按用户要求以 **1.22.0（111）** 归档并上传 iOS 与 Mac Catalyst，两端均收到 `Upload succeeded`，**尚未确认 TestFlight 可安装**，未提交正式审核（见[发布历史](docs/RELEASE_HISTORY.md)）。以下为历史记录。

2026-10-21 按用户要求应用前述推荐的 **A「纸间回声」** 并推送 TestFlight。日间图标与 OpenAI GPT Image 原图逐字节一致；深色、着色版从同一幅图做背景与色调适配，未混用 B 候选。三张图均为 1024×1024、RGB 无 alpha。与 109 相比，137 个构建 / 测试输入仅改变三个 PNG 和两个构建号配置文件；未改业务或 UI 源码。构建 110 **104 项 Debug 回归全部通过**，双端 Release 归档、签名 / 权限 / dSYM / 包内新图标检查通过；两端均返回 `Upload succeeded` / `EXPORT SUCCEEDED`，退出码 0。未改测试组、未提交正式审核、未创建 Git 提交。见 [新图标与适配说明](Design/icon-margin-gpt/README.md)、[最终三变体](Design/icon-margin-gpt/final/appearances.png)、[110 上传证据](Design/icon-margin-gpt/final/testflight-110.json)。

2026-10-21 完成 **v19「余白」Figma 设计与 SwiftUI 实现**：[可编辑 Figma 原稿](https://www.figma.com/design/xJdLrqBJ9bUkstoEIG1CKY) 包含 30 张界面稿、语义变量与本地组件、3 张图标母版。界面改为暖纸 / 石墨 / 陶橙，首页采用左右并列的续读书签卡，书架采用开放列表，阅读足迹与设置重新分层，阅读／听书工具与二级面板统一换新；该次交付的初版图标为 **「折页声窗」**（109；110 已另换为上述 GPT 图标），当时替换三种 1024px 无 alpha 资源。保留原有功能、导航、保存的字体与纸色，不覆盖起始工作区。iPhone SE 3 完整 **86 核心 + 18 UI = 104 项测试通过**，iOS Debug 与 Mac Catalyst 无签名构建通过；含日夜、小屏、最大字号、横屏与外观不重置纸色验证。详见 [设计说明](Design/v19-margin/DESIGN.md)、[实际验收记录](Design/v19-margin/VALIDATION.md)、[运行截图](Design/v19-margin/runtime/README.md)。随后按用户要求递增为 **1.21.0（109）**，重新完成 104 项 Debug 回归、双端 Release 归档和包检查，并于本机时间 **20:17:28 / 20:24:22** 分别收到 iOS / Mac 的 `Upload succeeded`。没有更改测试组或提交正式审核；[上传证据](Design/v19-margin/testflight-109.json)及[发布历史](docs/RELEASE_HISTORY.md)已记录。以下 v18 及更早内容为历史记录。

2026-10-21 完成 **v18「静蓝」重设计与本地实现**：晨雾灰白 / 蓝黑页面、深靛蓝主操作、白色内容表面与蓝雾选中态；系统字体承担界面骨架，宋体保留给书名和文学内容。续读主卡片、书架列表与网格、听书控制面板、统计卡片、三页签及迷你播放器统一换新。**应用图标改为「开放书页 + 三道声波」**，日间 / 深色 / 着色三变体均为 1024×1024 无 alpha PNG，渲染管线为 `Design/render-app-icon-v18.swift`。自包含高保真稿见 [静蓝设计稿](Design/v18-still/index.html)。原 [Figma「青听」稿](https://www.figma.com/design/2pbCXocDkORKA8Dl0Y5X5U) 在未登录浏览器中只读，仅作历史对照，未声称写回 Figma。信息架构、功能入口和读听交互契约保持不变；本次不归档、不上传、不递增版本号。iPhone 17e 模拟器 **86 项核心 + 16 项 UI 回归全部通过**，Mac Catalyst Debug 编译通过；运行截图见 [静蓝 previews](Design/v18-still/previews/)。

2026-10-21 完成 **v17「青听」重设计**：经 Figma 高保真稿（[听页 · 重设计](https://www.figma.com/design/2pbCXocDkORKA8Dl0Y5X5U)，含令牌、五屏界面与图标稿）选定方向——v16 的朱砂换为 **青松 `#2E6B4F`**（夜间 `#8CC2A5`），纸色微调 `#F7F4EC` / 夜 `#141619`，卡片圆角 16、按钮 14；阅读器跟读带同步青色。**应用图标重设计为「字」**（青松渐变底、宋体「听」立骨、字下三道声弧，日间 / 深色 / 着色三变体，渲染管线 `Design/render-app-icon-v16.swift`；候选稿见 `render-app-icon-v15-concepts.swift`）。信息架构与 v16 完全一致（书 / 读 / 己、v15 交互契约零删减），仅替换令牌与图标。iPhone 17e 模拟器 **86 项核心 + 16 项 UI 回归全部通过**；同日完成 iOS 与 Mac Catalyst Release 归档并上传 App Store Connect（14:40 / 14:43 收到 `Upload succeeded`；首次上传因图标含 alpha 被拒，改无 alpha 渲染后重传通过），回执为 Apple 正在处理，**尚未确认 TestFlight 可安装**；未提交正式审核、未更改测试组。

2026-10-21 完成 **v16「墨 · Ink」全盘重设计**（用户从 A「书房」/ B「墨」/ C「星野」三方向中选定 B）：宣纸为底、墨色为文、朱砂为印，宋体承担页标题 / 书名 / Tab 小字，四页签并为 **书 / 读 / 己**，无封面书改用线装书题签占位封；**应用图标同步重设计为「线装书题签」**（与界面同源的宣纸 / 宋体竖签 / 朱砂闲章，含日间 / 夜间 / 着色三变体），见 [图标说明](Design/icon-ink/README.md) 与 [预览](Design/icon-ink/index.html)。界面设计规范见 [墨 Ink 设计说明](Design/v16/b-ink/DESIGN.md)，运行截图见 [previews](Design/v16/b-ink/previews/)。功能与 v15 交互契约零删减；iPhone 17e 模拟器 **86 项核心 + 16 项 UI 回归全部通过**。同日完成 iOS 与 Mac Catalyst Release 归档并上传 App Store Connect（11:29 / 11:31 收到 `Upload succeeded`），回执为 Apple 正在处理，**尚未确认 TestFlight 可安装**；未提交正式审核、未更改测试组。

2026-10-20 已完成 iOS 与 Mac Catalyst Release 归档并上传 App Store Connect：iPhone 17e **102 项回归通过**，iPhone SE 3 **16 项 UI 回归通过**。两个平台均收到上传成功回执，回执状态为 Apple 正在处理，**尚未确认 TestFlight 可安装**；未提交正式 App Store 审核、未更改测试组。证据见 [验收记录](docs/ACCEPTANCE.md) 与 [发布历史](docs/RELEASE_HISTORY.md)。

功能键的布局与状态契约沿用 [交互规范](Design/v15-focus/ACTIONS.md)（v16 未改动功能键分层，仅替换视觉与页签架构）。

## 当前实现与设计基线

当前 UI 实现为 v20 **「刊 · Folio」**：杂志排版、象牙 / 炭黑 / Claude 陶土橙，图标为报头式「听」。以 [Figma](https://www.figma.com/design/evqePR3n5p2o0ToOVKtfKX)、[实现规范](Design/v20-folio/DESIGN.md) 与源码为准；v19「余白」及更早稿件为历史。v18「静蓝」、v17「青听」、v16「墨」及 v15「专注」的视觉稿保留作历史，交互契约继续沿用。

三个页签：**书 / 读 / 己**。

- **读**：编辑式标题与搜索、暖沙续读书签卡、最近在读列表、七日阅读记录、待读清单。上次阅读优先「继续阅读」，上次听书优先「继续听」，从未听过不称「继续听」。正在播放优先展示听书状态。
- **书**：文字「添加 / 整理」、书籍 / 漫画切换、独立「筛选 / 排序 / 显示方式」、文字「详情」。搜索时收起页首与类型栏，小屏键盘上方可直接操作结果。隐藏书籍入口归「更多」。新用户默认列表，已有网格 / 列表选择保持；辅助功能大字号使用列表，格式说明收在空态与导入面板。
- **己**：统计（日 / 周 / 月 / 年 / 全部、阅读目标、逐次记录、导出）+ 今日摘句 + 设置题录清单（阅读排版 / 字体 / 声音 / 外观 / 传书 / 备份 / 书摘 / 更多设置）。
- **听书**：暖沙书名标签、可展开封面、陶橙短竖线与暖色跟读高亮；常用工具固定「目录 / 语速 / 声音 / 定时」，音频输出在声音设置。显示「本章第 X / Y 句」和**估算**剩余分钟，可拖动句子进度。大字号 / 低高度窗口仅固定播放与跳句；迷你播放器只保留展开与播放，不再放直接结束。
- **阅读**：分页、连续滚动、原书图文、PDF、漫画；正文阅读工具固定「目录 / 排版 / 听书 / 更多」，日夜切换归「更多」。翻章只定位正文，不连带跳转声音；听条只管状态与播放。新安装默认系统字体，已保存的字体和独立纸色选择不被重置；默认纸色为宣纸。
- **反馈**：普通成功用可关闭的非阻断提示；导入记录逐项状态、成功数和失败原因，失败可重新选择文件。删除、还原等破坏性操作仍需确认。提示消失后可在导入面板查看最近结果。
- **无障碍**：关键标题、按钮、页签与说明跟随 Dynamic Type；封面与主题小字对比度有自动化断言；主要图标操作至少 44pt；支持系统「减少动态效果」。

## 数据与服务边界

- 没有听页账号或自有服务器。书籍、进度、书摘、统计保存在本机。
- 系统声音可离线朗读。智谱 GLM、MiniMax、Microsoft Azure、ElevenLabs 使用用户自己的密钥由设备直连，密钥存 Keychain。
- 云朗读会发送当前句及少量预取句子；试听也会联网，费用由服务商决定。不会把示例测试或本地估算声称为付费云语音实听验收。
- iCloud Drive **手动快照**备份书籍、资源、进度和书摘；恢复前校验并确认，只替换对应书籍，其余保留。
- iCloud 键值存储**自动同步阅读位置**，不自动传输书籍；两台设备需要各自持有相同书籍。上传 / 到达时间由系统决定，不保证即时同步。
- 隐藏书籍与应用锁通过系统生物识别或设备密码验证。
- 锁屏使用系统「正在播放」，**没有实时活动 / 灵动岛自定义扩展**。

## 支持能力与限制

| 能力 | 范围 |
| --- | --- |
| 导入 | TXT、EPUB、MOBI / AZW / AZW3、PDF、HTML、Markdown、DOCX、CBZ / 图片 ZIP、听页备份 JSON |
| 传书 | 系统文件、WiFi 传书、WebDAV、OPDS；SMB 通过系统文件 App 接入 |
| 阅读 | CoreText 分页、连续滚动、目录、搜索、书签、划线笔记、原书图文、字体导入、七种纸色 |
| 听书 | 变速、逐句定位、跟读、睡眠定时、锁屏控制、云语音预取、分角色音色（Beta） |
| 统计 | 日 / 周 / 月 / 年 / 全部、阅读目标、逐次记录、导出 |

限制：不支持 DRM、RAR / CBR 和扫描 PDF 的 OCR 朗读。新导入文件最大 100 MB，解压资源最大 130 MB，正文最大 400 万 UTF-16 字符 / 3000 章；PDF 最大 22 MB。复杂出版物 CSS、固定版式和跨章节锚点不保证完整复刻。

位置协议仍为「章 + 句子序号」，没有改成字符偏移。新增本机使用方式字段为可选，旧目录可解码，不改变跨端 `BackupPacket v2`。

本机书库：`Documents/TingyeNative/<owner>/Books`。`owner` 是 `guest` 或迁移保留的旧账号目录名，不是新账号系统。

## 构建与测试

打开 `Tingye.xcodeproj`，选择 `Tingye` scheme。Swift Package Manager 固定使用 ZIPFoundation 0.9.20，不需要 Node、CocoaPods 或 React Native。

```sh
# 核心测试 + UI 流程回归（设备名称按本机运行时调整）
xcodebuild -project Tingye.xcodeproj -scheme Tingye \
  -destination 'platform=iOS Simulator,name=iPhone 17e' \
  -parallel-testing-enabled NO test

# 仅核心测试
xcodebuild -project Tingye.xcodeproj -scheme Tingye \
  -destination 'platform=iOS Simulator,name=iPhone 17e' \
  -only-testing:TingyeTests test

# Mac Catalyst 编译，不签名、不上传
xcodebuild -project Tingye.xcodeproj -scheme Tingye -configuration Debug \
  -destination 'generic/platform=macOS,variant=Mac Catalyst' CODE_SIGNING_ALLOWED=NO build
```

- `TingyeTests/NativeCoreTests.swift`：导入、存储、备份恢复、进度合并、语音、文字安全、主题对比度、动作语义和导入反馈。
- `TingyeUITests/DesignFlowTests.swift`：首页首屏与搜索、书架整理 / 详情 / 独立筛选排序、播放器句子拖动与暂停、最大字号与横屏、混合导入、阅读四键 / 日夜、读听定位分离、迷你播放器与结束确认。
- UI 测试通过 `-ui-fixture` 使用临时书库、关闭同步并强制系统声音，**不改用户书库、不调用付费接口**。这些入口只编译到 Debug。
- `-uireview <场景>` 仍可用于人工走查；配合 `-ui-fixture` 检查长书名、长句；通过模拟器系统字号或启动参数 `-UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXXXL` 检查最大辅助功能字号（包括弹出的 sheet）。不加 `-ui-fixture` 时会使用模拟器现有书库。
- `-ui-fixture -ui-showcase` 可使用公版节选、示意书封和模拟阅读记录进行视觉走查；只在 Debug 的临时书库中生效，不代表用户实际阅读记录。
- v19 本轮设计与测试证据见 [余白验收记录](Design/v19-margin/VALIDATION.md)；之前的发布验收与未覆盖项目保留在 [验收清单](docs/ACCEPTANCE.md)。模拟器与离线测试不能代替真实语音、蓝牙、来电和跨设备 iCloud 验收。

`create-project.rb` 是工程重建辅助脚本，日常开发无需执行；重建后仍须审查签名、资源及 Xcode 构建配置差异。发布版本和构建号只有在准备实际归档时才递增。

## 主要文件

| 路径 | 职责 |
| --- | --- |
| `Tingye/Theme.swift` | 颜色、字体、按钮、封面、阅读纸色与动效策略 |
| `Tingye/TingyeApp.swift` | 导航、迷你播放器、反馈容器、Debug 走查入口 |
| `Tingye/NowView.swift` | 首页续读与最近在读 |
| `Tingye/ShelfView.swift` | 搜索整理、导入选择器与逐项结果 |
| `Tingye/PlayerView.swift` / `SpeechPlayer.swift` | 听书界面 / 播放与合成 |
| `Tingye/AppModel.swift` / `Models.swift` | 书库协调、行为记录、导入反馈与数据模型 |
| `Tingye/ReaderView.swift` / `OriginalBookView.swift` | 原生文字阅读 / 原书图文 |
| `Tingye/ICloudBackup.swift` | 快照、还原事务、进度同步 |

## 文档与许可

- [当前余白设计规范与 Figma](Design/v19-margin/DESIGN.md)
- [交互基线：专注版设计规范（方案 B）](Design/v15-focus/DESIGN.md)
- [上一轮可用性修订记录](Design/v14-editorial/USABILITY.md)
- [核心链路与真机验收清单](docs/ACCEPTANCE.md)
- [发布与旧设计历史](docs/RELEASE_HISTORY.md)

示例书籍为公开作品节选。思源宋体、霞鹜文楷的 OFL，以及 ZIPFoundation 的 MIT 许可随 App 资源附带。UI 与业务代码为 Swift，原书图文使用系统 WKWebView，不依赖外部网页运行时。
