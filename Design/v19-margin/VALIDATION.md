# v19「余白」实现与验收

日期：2026-10-21。下文设计交付验收保留 **1.20.0（108）** 当时的证据；其后完成 **1.21.0（109）** UI 版和 **1.21.0（110）** GPT 图标版的双端 TestFlight 上传，新增记录见文末。上传不等于已可安装或正式上架。

## 交付

- [可编辑 Figma 文件](https://www.figma.com/design/xJdLrqBJ9bUkstoEIG1CKY)：30 张界面画板、语义变量、文字样式与本地组件，另有 3 张 1024px 图标母版。
- [设计规范](DESIGN.md) 与 [运行截图索引](runtime/README.md)。Figma 预览位于 `previews/`，原生运行截图位于 `runtime/`，不能混称。
- 原生实现使用系统 UI 字体 / Dynamic Type，文学内容与书名使用已包含的宋体。没有为匹配 Figma 的渲染替代字体而安装 Noto Sans。
- 图标「折页声窗」已从 Figma 导出并替换 Assets 中的日间、深色、着色版本；均验证为 **1024×1024、8-bit RGB、无 alpha**。`prepare-icons.swift` 只做不透明转换，不重画几何。

## 实现边界

| 文件 | 本轮内容 |
| --- | --- |
| `Theme.swift` / 颜色资源 | 暖纸、石墨、陶橙；按钮、胶囊、轻边界、占位书封与跟读标记；复用现有 TY 矢量图标，未映射状态继续使用 SF Symbols |
| `TingyeApp.swift` / `NowView.swift` | 横排图标＋中文页签、迷你播放器；编辑式首页、左右并列续读卡、主次动作、最近在读与七日点阵 |
| `ShelfView.swift` | 标题和真实在读数量、独立筛选 / 排序 / 显示、开放列表、52pt 封面；搜索收起额外头部与底栏，保留键盘上方操作空间 |
| `LibraryViews.swift` / `StatsView.swift` / `DailyQuoteCard.swift` | 暖沙详情区、外观预览、阅读足迹大数字、轻图表、前移设置清单、衬线摘句 |
| `Sources.swift` / `ICloudBackup.swift` | 导入与备份界面样式和层级；未改传输、快照、还原或进度同步算法 |
| `PlayerView.swift` / `ReaderView.swift` / `ComicReaderView.swift` | 暖沙书名标签、宋体跟读、石墨播放键、轻边界工具面板；保留四键顺序、句子进度、定位、暂停和紧凑布局 |
| 原书、书摘、分角色、字体管理 | 通过共享 Theme / 原有组件继承新外观；没有为换肤重写这些模块的内容、服务或数据逻辑 |

浅色 `ink2` 从初稿 `#686C63` 调整为 `#62665D`，`accent` 从 `#A64B2D` 调整为 `#A44A2C`。原因是暖沙 / 次级表面上的小字对比度。已更新 Figma 对应变量，并把 hero、marker 上的文字组合加入原有 4.5:1 自动化断言。无文字图标保留原始品牌导出色。

## 已完成验证

| 项目 | 结果与证据 |
| --- | --- |
| iOS Simulator Debug | 构建通过；`build/v19-margin/ios-build.log`，后续完整测试也重新构建了修改后的 App |
| 完整自动化验收 | **104 / 104 Passed，0 failed，0 skipped**；86 核心 + 18 UI；`build/v19-margin/verified-se.xcresult` / `verified-se.log` |
| 设备 | iPhone SE (3rd generation)，375×667pt，iOS 27.0；模拟器名 `Tingye Action Layout SE` |
| 小屏、最大辅助功能字号 | 首页续读与最近在读、搜索结果在键盘上方、书架整理、播放器固定播放与跳句、阅读四键和返回；见 `runtime/se-*.png` |
| 外观与偏好 | 新增测试覆盖外观选择、夜间阅读／听书，以及切换全局外观后仍保留独立「旧书」纸色 |
| 横屏 | 播放与前后跳句位于可见区域；补充断言实际宽度大于高度；单项复核也 Passed，见 `build/v19-margin/landscape-capture.xcresult` |
| 390×844pt 日夜视觉 | iPhone 17e 实际运行截图；检查 6 主页面 × 日夜，以及 6 二级面板；见 `runtime/` |
| Mac Catalyst Debug | 无签名构建通过；`build/v19-margin/catalyst-build.log` |
| 资源与工作区 | 三个 icon RGB 无 alpha；`git diff --check` 通过；设计交付时工程文件与起始备份逐字节相同，随后上传阶段仅递增版本配置 |

可机器读取的验收摘要：[validation-summary.json](validation-summary.json)。详细 bundle 和日志保留在 `build/v19-margin/`，没有把更早版本的 86+16 历史成绩算作本次结果。

### 测试配置修正记录

- 初轮无签名核心测试无法访问模拟器钥匙串（-34018）。改用模拟器本地 ad-hoc 签名后，钥匙串测试通过；未修改生产签名配置。
- 外观交互测试不能使用 `-app.appearance` 启动参数来锁定 `@AppStorage`。新增 DEBUG 临时书库专用 `-ui-appearance` 初值，让测试可真实切换外观。正常运行不会重置用户设置。
- SE 上 XCUITest 会把被固定「完成」栏遮住的纸色按钮误报为 hittable。测试现在先确认目标完整滚入完成栏上方再点击，没有降低测试断言。
- iPhone 17e 的完整运行日志记录了 86+18 测试全部通过，但 Xcode 随后的诊断采集阶段超时，结果包未封口。它不作为最终完整 bundle；上表采用 `-collect-test-diagnostics never` 后正常退出的 SE 结果。
- Xcode 27 的横屏 `app.screenshot()` 出现按竖屏边界裁切的问题。横屏改用 `XCUIScreen.main.screenshot()`，并重新运行该测试；截图拼图脚本保留图像方向。

## 复现命令

在仓库根目录执行；设备 ID 按本机模拟器调整。新一次运行要使用新的 result bundle 路径。

```sh
xcodebuild -project Tingye.xcodeproj -scheme Tingye -configuration Debug \
  -destination 'platform=iOS Simulator,id=DBD3F316-5B81-41E3-8EFA-80A52190D0DD' \
  -derivedDataPath build/MarginV19DerivedData \
  -resultBundlePath build/v19-margin/new-check.xcresult \
  -parallel-testing-enabled NO -collect-test-diagnostics never \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- test

xcodebuild -project Tingye.xcodeproj -scheme Tingye -configuration Debug \
  -destination 'generic/platform=macOS,variant=Mac Catalyst' \
  -derivedDataPath build/MarginV19CatalystDerivedData \
  CODE_SIGNING_ALLOWED=NO build

# 启动 DEBUG 临时演示书库，生成实际像素截图；不会上传或替换用户书库。
bash Design/v19-margin/capture-runtime.sh
```

## 未声称覆盖的项目 / 现有告警

- 模拟器与离线测试不代替真机云语音实听、耳机 / 蓝牙 / 来电中断、跨设备 iCloud、Face ID 与 App Store 安装验证。
- Mac Catalyst 本轮验证为编译，不是整套桌面交互回归。
- 原书、漫画等保留原有渲染算法及核心测试，本轮没有逐种真实出版物重新做视觉比对。
- 编译仍有原有 `Sources.swift` 的 `maxBytes` actor 隔离告警，以及未使用 AppIntents 的元数据提示。测试记录有 AVAudioSession 主线程同步激活告警。本轮没有借换肤改写这些服务，也不声称构建无告警。

## 保存原有工作

起始工作区已有未提交的 v18 修改，副本在 `build/before-margin-v19/`。设计交付基于该副本增量修改，未 reset / revert、未提交。当时 `Tingye.xcodeproj/project.pbxproj` 与该副本一致，版本为 **1.20.0（108）**，设计交付阶段没有归档或上传。

## 后续 TestFlight 上传 · 1.21.0（109）

用户追加要求「推送 TestFlight」后，递增工程版本和 `create-project.rb`，未再修改业务或 UI 源码。发布前副本在 `build/before-margin-testflight-109/`，137 个构建 / 测试输入的 SHA-256 冻结清单为 `build/release-109-source-manifest.json`。

- **重新验证**：iPhone SE 3 / iOS 27.0，Debug 配置 **86 核心 + 18 UI = 104 项通过，0 失败、0 跳过**；`build/Release109Tests.xcresult`，日志 `build/release-109-tests.log`。
- **Release 归档**：iOS arm64、Mac Catalyst arm64 + x86_64 均成功。版本、归档签名、iCloud / Keychain 权限、dSYM、隐私清单、包内不透明三变体图标与 DEBUG 入口隔离检查通过；`build/release-109-{ios,mac}-checks.json`。
- **实际上传**：iOS 于本机时间 **20:17:28**、Mac 于 **20:24:22** 收到 `Upload succeeded`；两端均为 `EXPORT SUCCEEDED` / 退出码 0。
- **状态边界**：Apple 最后回执为 `Uploaded package is processing`，**尚未确认 TestFlight 可安装**；没有正式上架审核、测试组变更或 Git 提交。
- **证据**：[testflight-109.json](testflight-109.json)、`build/upload-109.log`、`build/upload-109-mac.log`；完整记录见 [发布历史](../../docs/RELEASE_HISTORY.md)。

前述 `validation-summary.json` 与 `runtime/` 保留设计初次交付时的 108 测试 / 截图含义；不将其改称 109 或 110 的截图。模拟器和包检查仍不替代真机、付费语音、跨设备 iCloud 或完整桌面交互验收。

## 后续 GPT 图标替换 · 1.21.0（110）

用户要求应用图标并推送 TestFlight 后，按前述推荐采用 A「纸间回声」。只修改三个图标 PNG 和构建号配置；137 个输入与 109 的冻结清单比对通过，UI 与业务代码未变。

- 日间图标与 GPT 原图逐字节一致；深色 / 着色为同一图形的颜色与位图边缘适配。均为 1024px RGB 无 alpha，着色为中性灰阶。
- **110 独立验证：104 / 104 Debug 测试通过，0 失败、0 跳过**；`build/Release110Tests.xcresult`。
- 双端 Release 归档、签名 / 权限 / dSYM / 隐私 / 测试入口隔离检查通过；包内图标摘要全部不同于 109，排除旧资源缓存。
- iOS/iPadOS 与 Mac Catalyst 均收到 `Upload succeeded` / `EXPORT SUCCEEDED`，退出码 0；最后回执为处理中，未确认可安装。没有正式审核、测试组变更或 Git 提交。
- [图标及适配说明](../icon-margin-gpt/README.md)、[110 回执摘要](../icon-margin-gpt/final/testflight-110.json)，原始日志在 `build/upload-110{,-mac}.log`。
