# 听页 · 原生 iOS / Mac Catalyst

纯 Swift / SwiftUI 本地阅读与听书应用，最低 iOS 17。当前工程及最新 TestFlight 上传版本为 **1.18.0（105）**：应用图标换为用户选定的 **02「抱书的小王子」**，补齐 iOS 默认 / 夜间 / 着色资源，Mac 使用默认图标；应用功能源码与构建 104 保持一致。图标见 [最终预览](Design/icon-little-prince/final/index.html) 与 [生成说明](Design/icon-little-prince/README.md)。

2026-10-20 已完成 iOS 与 Mac Catalyst Release 归档并上传 App Store Connect，95 项回归测试通过。两个平台均收到上传成功回执，回执状态为 Apple 正在处理，**尚未确认 TestFlight 可安装**，未提交正式 App Store 发布。证据与历代设计见 [发布历史](docs/RELEASE_HISTORY.md)。

## 当前实现与设计基线

用户明确选定 **B「极简·专注」**：浅灰紫、系统界面字体、无框排版、轻量书目列表。**当前界面以源码与 [专注版规范](Design/v15-focus/DESIGN.md) 为准**。v14「刊」及 [上一轮可用性修订](Design/v14-editorial/USABILITY.md) 保留为历史，不能再用其中的颜色、宋体书名或粗线条指导当前实现。

四个页签：**今日 / 书架 / 足迹 / 设置**。

- **今日**：品牌与搜索、无框续读区、最近在读列表、七日阅读记录、待读清单。上次阅读优先「继续阅读」，上次听书优先「继续听」，从未听过不称「继续听」。正在播放优先展示听书状态。
- **书架**：轻量搜索、书籍 / 漫画筛选、明确的「整理」、排序下拉、文字「详情」。新用户默认列表，已有网格 / 列表选择保持；辅助功能大字号使用列表，格式说明收在空态与导入面板。
- **听书**：紧凑书名栏、可展开封面、低饱和跟读高亮；显示「本章第 X / Y 句」和**估算**剩余分钟，可直接拖动句子进度，上一句 / 下一句带文字。大字号与低高度窗口的正文、进度和工具可滚动，播放 / 跳句固定可见。
- **阅读**：分页、连续滚动、原书图文、PDF、漫画；灰紫色跟读高亮、轻量工具条，听条随内容高度给正文留空间。新安装默认系统字体，已保存的字体和独立纸色选择不被重置。
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
- `TingyeUITests/DesignFlowTests.swift`：首页首屏与搜索、书架整理 / 详情、播放器句子拖动与暂停、最大字号操作、混合导入、阅读工具与日夜布局。
- UI 测试通过 `-ui-fixture` 使用临时书库、关闭同步并强制系统声音，**不改用户书库、不调用付费接口**。这些入口只编译到 Debug。
- `-uireview <场景>` 仍可用于人工走查；配合 `-ui-fixture` 检查长书名、长句；通过模拟器系统字号或启动参数 `-UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXXXL` 检查最大辅助功能字号（包括弹出的 sheet）。不加 `-ui-fixture` 时会使用模拟器现有书库。
- `-ui-fixture -ui-showcase` 可使用公版节选、示意书封和模拟阅读记录进行视觉走查；只在 Debug 的临时书库中生效，不代表用户实际阅读记录。
- 本轮证据、待验收项目与发布门槛见 [验收清单](docs/ACCEPTANCE.md)。模拟器与离线测试不能代替真实语音、蓝牙、来电和跨设备 iCloud 验收。

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

- [当前专注版设计规范（方案 B）](Design/v15-focus/DESIGN.md)
- [上一轮可用性修订记录](Design/v14-editorial/USABILITY.md)
- [核心链路与真机验收清单](docs/ACCEPTANCE.md)
- [发布与旧设计历史](docs/RELEASE_HISTORY.md)

示例书籍为公开作品节选。思源宋体、霞鹜文楷的 OFL，以及 ZIPFoundation 的 MIT 许可随 App 资源附带。UI 与业务代码为 Swift，原书图文使用系统 WKWebView，不依赖外部网页运行时。
