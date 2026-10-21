# 听页 · 界面、图标与核心链路验收

最新上传版本为 **1.18.0（106）**：功能键分层重设计，已按用户追加要求完成 iOS 与 Mac Catalyst TestFlight 上传；回执为 Apple 正在处理，尚未确认可安装。TestFlight 用于继续真机验证，不代表正式 App Store 发布或全部验收完成。测试结果与环境必须分开记录：**模拟器 / 注入存储 / 本地缓存音频通过，不等于真实付费接口、蓝牙或跨设备 iCloud 通过。**

## 功能键分层重设计（1.18.0 · 106，2026-10-20）

- 阅读固定四键，顶栏只保留返回 / 书签；阅读翻章与声音定位分开，展开已暂停的播放器不自动恢复。
- 听书固定「目录 / 语速 / 声音 / 定时」，输出设备归声音设置；迷你播放器只保留展开与播放，结束会话仍确认。
- 书架独立筛选、排序与显示；隐藏入口归「更多」。小屏搜索时精简页首，键盘上方可以直接点击结果。
- 小屏走查修正了最大辅助功能字号下翻章文字撑宽浮层的问题；新增水平边距断言。系统菜单 / popover 测试按实际可访问名称操作，并等待取消完成；纸色 / 显示方式采用可修改测试初值，不再被启动参数域锁住。
- 最终测试发生在构建号递增至 106 后，使用冻结的同一份代码。核心 86 项未新增，UI 从 9 增至 16 项。测试不调用付费语音、不改用户书库。

| 环境 / 范围 | 最终结果 | 证据 |
| --- | --- | --- |
| iPhone 17e / iOS 27，核心 + UI | **102 / 102 通过** | `build/action-layout-release-tests.log`、`build/ActionLayoutRelease.xcresult` |
| iPhone SE 3 / iOS 27，375 × 667pt | **16 / 16 UI 通过** | `build/action-layout-release-small.log`、`build/ActionLayoutReleaseSmall.xcresult` |
| 日夜、最大字号、横屏 / 低高度 | 自动化与截图抽样通过 | 上述结果包附件；[实际界面截图](../Design/v15-focus/action-previews/index.html) |
| Mac Catalyst Debug | **编译通过** | `build/action-layout-mac.log`；未做 Mac 交互实测 |
| iOS / Mac Catalyst Release | **两端归档与包检查通过** | `build/archive-106.log`、`build/archive-106-mac.log`；`build/release-106-ios-checks.json`、`build/release-106-mac-checks.json` |
| 真机 VoiceOver、蓝牙 / AirPlay、来电、云语音、双设备 iCloud | **仍待实测** | 本轮只验证设备选择入口，不声称真实路由或付费接口通过 |

发布检查：iOS 为 arm64，Mac 为 arm64 / x86_64；版本、签名、iCloud / Keychain 权限、dSYM UUID、隐私清单、三种 iOS 图标资源保持正确。Release 二进制不含 `UIReview`、`-ui-reset-preferences` 等测试入口，也未打包 XCTest bundle。136 个构建输入的 SHA-256 见 `build/release-106-source-manifest.json`，检查脚本为 `build/verify-release-106.py`。

上传：iOS **17:56:47**、Mac **17:58:27**（本机时间）分别收到 `Upload succeeded` 与 `EXPORT SUCCEEDED`，进程退出码均为 0。日志为 `build/upload-106.log`、`build/upload-106-mac.log`，汇总为 `build/release-106-upload-summary.json`。Apple 回执为 `Uploaded package is processing`，**尚未确认 TestFlight 可安装**。没有提交正式 App Store 审核、没有修改测试组或邀请测试者。

以下保留历史版本证据，不能替代本轮记录。

## 历史：专注版初始自动化与界面证据

- 核心套件：86 项；包含此前 7 项设计回归，以及本轮新增的七种阅读纸色对比度、默认字体与明确用户偏好保留检查。
- UI 套件：9 项；使用临时书库、长书名、100 字以上长句、系统声音、关闭 iCloud，不操作用户原书库。本轮新增首页搜索衔接、阅读工具 / 排版与夜间布局。
- 首轮 UI 回归发现底栏 VoiceOver 名称被根容器覆盖，已移除根容器的统一标签，并逐个验证四个页签名称。
- 方案 B 最终验证于 2026-10-19 完成：iPhone 17e 共 **95 项（86 核心 + 9 UI）通过**，iPhone SE 3 重跑同一组 **9 项 UI 全部通过**，Mac Catalyst Debug 编译通过。此前 90 项验证属于旧视觉，不替代本轮结果。
- 截图走查另外修正了无图书封装饰撑宽内容的问题，以及阅读工具打开时页脚从面板下露出碎片的问题；下表均为这两项修正后的最终结果。
- 最大字号测试使用 UIKit 实际字号启动参数，涵盖弹出的播放器；并断言播放键固定可见且居中，避免仅修改主页面环境却误报 sheet 已适配。

| 环境 / 范围 | 状态 | 证据 |
| --- | --- | --- |
| iPhone 17e / iOS 27 核心 + UI | **95 / 95 通过** | `build/focus-b-final.log`、`build/FocusBFinal.xcresult` |
| iPhone SE 3 / iOS 27（375 × 667pt） | **9 / 9 UI 通过** | `build/focus-b-small-final.log`、`build/FocusBSmallFinal.xcresult`；使用本轮临时设备 |
| 日间 / 夜间 / 最大辅助功能字号 | **完成抽样复核** | 首页、网格 / 列表书架、详情、播放器、阅读工具、设置、足迹；夜间小屏首页 / 播放器 / 阅读；最大字号首页 / 书架 / 播放器。截图在 `.xcresult` 附件及 `build/focus-b-previews/` |
| Mac Catalyst Debug | **编译通过** | `build/focus-b-mac-final.log`；未签名、未归档、未做 Mac 交互实测 |
| 真机 VoiceOver / 减少动态效果 | 未实测 | 仅有代码适配和 UI 自动化检查 |
| 实际云语音 / 蓝牙 / 来电 | 未实测 | 需要设备与服务商账号 |
| 真实 iCloud 双设备 | 未实测 | 需要同一 Apple 账号的两台设备 |

复跑：

```sh
xcodebuild -project Tingye.xcodeproj -scheme Tingye \
  -destination 'platform=iOS Simulator,name=iPhone 17e' \
  -parallel-testing-enabled NO -collect-test-diagnostics never test
```

## 图标更新与 TestFlight（1.18.0 · 105，2026-10-20）

- 采用用户选定的 02「抱书的小王子」。默认 PNG 与选型预览的 SHA-256 完全一致；夜间与灰阶着色版保留同一构图。生成与安装脚本见 `Design/icon-little-prince/render-icons.py`。
- 三张源图均为 1024 × 1024、不带 alpha 的方形 PNG。原生 ImageIO / CoreGraphics 逐像素检查全部不透明，着色图的 RGB 最大通道差为 0；日志 `build/little-prince-icon/pixel-validation.log`。
- iPhone 17e / iOS 27 重新执行 **95 / 95（86 核心 + 9 UI）通过**；日志 `build/icon-105-tests.log`、结果包 `build/Icon105Tests.xcresult`。此次没有重跑 SE 小屏测试，前述 SE 结果仍属于 2026-10-19 的界面回归。
- iOS 与 Mac Catalyst Release 均成功归档：`build/Tingye-105.xcarchive`、`build/Tingye-105-mac.xcarchive`；Mac 包含 arm64 / x86_64。签名、iCloud / Keychain 权限、dSYM UUID 与 DEBUG 入口隔离检查通过。
- 使用 `assetutil` 确认 iPhone / iPad 归档各自包含默认、`UIAppearanceDark`、`ISAppearanceTintable` 三种不透明图标。Mac 归档包含默认图标及生成的 `AppIcon.icns`；对包内导出的 iOS / Mac 图标进行了抽样查看。实际系统自定义着色、透明样式与真机桌面仍需设备验收。
- 本次生产构建输入相对 104 只改变三个 AppIcon PNG 与工程 / 重建脚本中的构建号。源文件哈希见 `build/release-105-source-manifest.json`，归档检查见 `build/release-105-ios-checks.json`、`build/release-105-mac-checks.json`。
- 两个平台均返回 `Upload succeeded` 与 `EXPORT SUCCEEDED`，上传进程退出码为 0；日志 `build/upload-105.log`、`build/upload-105-mac.log`。回执为 `Uploaded package is processing`，尚未确认 TestFlight 可安装。
- 没有改动业务 Swift 源码、测试组或邀请测试者，也没有提交正式 App Store 审核。下列真机 / 真实服务门槛仍保持待验收。

## TestFlight 归档与上传（1.18.0 · 104，2026-10-19）

- 版本：1.18.0（104）；同步更新工程与 `create-project.rb`。上述模拟器回归完成后，仅递增版本 / 构建配置，功能源码没有再改动。
- iOS Release：`build/Tingye-104.xcarchive`；日志 `build/archive-104.log`、`build/upload-104.log`。
- Mac Catalyst Release：`build/Tingye-104-mac.xcarchive`；日志 `build/archive-104-mac.log`、`build/upload-104-mac.log`；包含 Apple Silicon 与 Intel。
- 两端归档的版本、签名、iCloud / Keychain 权限及 dSYM UUID 检查通过；Release 二进制未包含 `UIReview` / `-ui-fixture` / `-ui-showcase` 等测试入口，也未打包 XCTest bundle。检查结果见 `build/release-104-ios-checks.json`、`build/release-104-mac-checks.json`；源文件哈希见 `build/release-104-source-manifest.json`。
- 两端均收到 `Upload succeeded` 与 `EXPORT SUCCEEDED`，对应上传进程退出码为 0。上传回执状态为 `Uploaded package is processing`，不能据此宣称已可安装。
- 没有提交正式 App Store 审核，没有变更测试组或邀请测试者。下列真实服务 / 设备验收仍待完成。

## 正式发布前的真机门槛

下列项目尚未完成。不要在商店说明或发布记录中写「全部验收通过」。真实凭据只在设备设置页输入，不写进源码、截图或测试日志。

### 1. 首次导入 → 第一次开听

- [ ] 全新安装：无权限时，文件选择 / 本地网络权限解释明确，取消不报成功。
- [ ] 从文件选择器导入自己的长篇 EPUB / TXT，首屏续读入口可用。
- [ ] 一批有效 EPUB + 损坏 JSON：只有坏文件显示失败，成功书可读；重试不需要重导成功项。
- [ ] 从 WiFi / WebDAV / OPDS 下载；断网时有明确失败，恢复后重试可成功。
- [ ] 默认系统声音无需 API Key；用户明确配置后才使用云服务，未隐式切换付费提供方。

### 2. 播放连续性与中断

对系统声音及每个实际启用的云提供方分别检查：

- [ ] 开始、暂停、继续、上一句 / 下一句、跨章、0.5× / 1× / 2×；不截尾、不重复跳句。
- [ ] 句子进度拖到中段；已暂停仍保持暂停；滑动过程中自然跨章不误应用旧目标。
- [ ] 180 字长句、连续标点、空章节、最后一章最后一句，音频与显示一致。
- [ ] 锁屏 / 后台连续听至少 30 分钟；系统播放控件能暂停、继续、跳句和拖动进度。
- [ ] 蓝牙耳机断连暂停；重新连接不会未经用户同意突然播放；AirPlay 可切路由。
- [ ] 来电 / Siri / 闹钟中断：遵循系统恢复许可；未许可不自动播放；进度保留。
- [ ] 15 分钟定时实际等到停止；重新打开不会意外恢复上次已结束的定时。

### 3. 云服务异常与费用边界

- [ ] 飞行模式、弱网、请求超时：错误能看到，重试可恢复，暂停后不继续无限预取。
- [ ] 无效密钥 / 错误区域 / 不存在的音色：提示具体原因，可直接检查声音设置。
- [ ] 余额不足 / 配额耗尽 / 限流：不是无限自动重试，也不自动切换另一家付费服务。
- [ ] MiniMax MP3 真实接口实听：句尾完整，句间停顿合理；AAC / WAV 离线样本不能代替此项。
- [ ] 提供方账单与预取行为符合预期；设置页说明当前句、预取句和试听均可能发往服务商。

### 4. iCloud 同步与恢复

准备 A / B 两台登录同一 Apple 账号的设备，开启 iCloud Drive，各自导入同一书籍。

- [ ] A 阅读推进，退出阅读页；B 在系统同步到达后合并位置；未到达前不显示虚假完成。
- [ ] A / B 同时阅读不互相跳页；停止后依时间戳规则合并，重启后位置一致。
- [ ] A 保存快照，检查系统上传状态；B 下载并查看日期 / 数量后确认还原。
- [ ] 还原取消、断网、损坏快照、空间不足时保留原本机书库；未还原的书仍存在。
- [ ] 旧账号目录的新快照不会被 guest 下旧快照遮盖。
- [ ] 隐藏书在未解锁时不出现在书目统计、排行或导出明细。

### 5. 无障碍与布局

- [ ] VoiceOver 从首页开始按顺序读到继续阅读、听书、最近在读和四个页签；页签名称各不相同。
- [ ] 普通与最大辅助功能字号，小屏竖屏 / 横屏：播放、定时、章节、返回和重试均可触达。
- [ ] 长书名 / 长章节名 / 长作者名：主要内容可读，不用过度缩小文字掩盖溢出。
- [ ] VoiceOver 能调整句子滑杆；暂停状态不改变；成功提示留到用户关闭且只播报一次。
- [ ] 开启「减少动态效果」：无按压缩放、循环波形和自动滚动动画；仍能定位当前句。
- [ ] 真机日间 / 夜间 / 提高对比度，检查灰紫辅助文字、浅底按钮、无图封面与导入的真实书封；模拟器已覆盖普通日夜配色。
- [ ] iPad 分屏与 Mac 窄窗口：播放器整页可滚动，主要控制不被挤出窗口。

## 发布纪律

1. 用户已明确选定 B「极简·专注」，以 `Design/v15-focus/DESIGN.md` 为准；后续在该方向内收敛，正式公开发布前先完成上述关键链路。
2. 关键失败必须记录设备、系统、提供方、复现步骤和脱敏日志；修复后回归相同场景。
3. 只有真实完成的项目打勾。无法验证的服务商应保留明确边界，不能用「构建通过」替代。
4. 准备发布时再递增构建号、检查签名 / entitlements、归档与上传；上传成功也不等于 TestFlight 已可安装。
