# 页签实施状态

工作基线为 `56c3b79d71378c5d792f0db56097968bbf3fba48`（构建 148），分支 `redesign/full-product-20261121`。当前 **59/59 项均已核对生产路径**，其中 **54 项应用界面已实施结构迁移**，**5 项已实施应用周边呈现，系统或路由内部为 N/A**。第二轮 macOS Actions 在 `cbbe25c` 上编译成功，单元 186 项通过，UI 33 项中 1 项失败。原生阅读器最大字号边距回归已通过，派生 EPUB 冒烟用例的新失败已定位到首个可用页面位置确认前，修订后的同源码单用例诊断已通过一次，根因及完整套件、设备验收仍待确认。完整范围见 [覆盖矩阵](COVERAGE.md)。以下第一、第二里程碑为当时的证据记录，以末尾的当前矩阵为准。

## 第一里程碑 · 共享组件与书库

| ID | 已落地 | 待验证或后续实施 |
| --- | --- | --- |
| G01 | `Tingye/TingyeApp.swift` 的 `StudyRootView` 用同一个栈承载书库、`NotesUnifiedView` 和原 `StatsView(ji:)`。顶栏新增摘记直达，沿用我的入口和 ID。冷启动条件、前后台处理与根 modal 处理比对基线字节一致。 | macOS 验证返回、滚动和焦点恢复、根导航及播放/阅读覆盖层。用真机检查上锁与前后台。 |
| S01 | `Tingye/ShelfView.swift` 调整为页首动作、紧凑续读、书种、书目、今日一句。续读沿用最近阅读和位置，保留专注、样例和添书入口。连续书目采用同一内容面，封面按可用宽度布局。 | macOS 验证首屏可达、长标题、漫画页号、听读位置独立、深色和最大字号。 |
| S02 | `ShelfView.swift` 为书种切换和筛选、排序、视图、整理提供独立样式。窄屏工具可换行，大字号沿现有规则用列表，保留 `shelf.layout` 和排序数据。 | macOS 验证窄屏菜单触点唯一、切换和筛选清除、手动排序、列表/网格状态重开保持。 |
| S03 | `ShelfView.swift` 改用有焦点边界的紧凑搜索界面，保留全分组匹配、搜索字段 ID、最近搜索及清空。空结果有专门状态，输入后结果优先于历史。 | macOS 验证小屏键盘、打开详情和取消。设备验 VoiceOver 焦点及大字换行。 |
| S04 | `ShelfView.swift` 的分组入口、书目行和封面网格采用页签样式；分组空态给出创建路径。 | 移动分组 sheet、重命名和移除确认仍用已有呈现，后续覆盖其界面。设备验嵌套分组与键盘。 |
| S05 | `ShelfView.swift` 以选中底和文字标示书目选择，底栏保留移动、隐藏、删除及示例书不可删提示。原长按、隐私解锁和删除确认仍在。 | macOS 验证全选、取消整理、删除确认与禁用，设备验隐藏书认证和辅助操作。 |
| I01 | `ShelfView.swift` 把根书库「添书」移到首屏，使用同一个现有入口 ID 和 `ImportHubView` sheet。分组沿用导航栏入口。 | 传书 hub 内部界面由后续里程碑处理。macOS 验证入口和文件 picker 呈现时序，真机验提供方交付。 |
| P01 | `Tingye/TingyeApp.swift` 的 `MiniPlayer` 采用页签色和排版，延续展开、回到朗读及播放/暂停的三个控制，强化合成和错误状态样式。 | macOS 验证暂停、展开和回到朗读，真机验大字号与后台音频。完整播放器后续实施。 |
| M01 | 书库「摘记」直达原 `NotesUnifiedView`，显式显示系统返回。我的原入口仍在。追加一个真实点击和返回的 `DesignFlowTests` 回归，现有用例保留。 | macOS 执行新增回归。摘记页面内部的索引构图及视觉属于后续实施。 |
| M02 | 书库「我的」入口使用同一导航组件，沿用已有 ID、路由和返回动作。 | 我的内部布局、统计卡和设置目录属于后续实施。macOS 验证旧入口和返回。 |

第一里程碑推进 **10 项**。S04、I01 在第二里程碑继续推进，M01、M02 仍为入口。计划中的 `launch.resume` 接线与运行中批次取消列为可选未来工作。

## 共享底座

- `Tingye/Theme.swift` 新增日夜 `IndexTheme`、对比度分支及宋体系统回退。根和书库使用 `IndexActionLabel`、`IndexActionStyle`、`IndexRule` 和共享面板。真实封面保留图像，页签调用可选用暖纸占位。下游现有 `Theme` 和独立正文 `ReaderPaper` 按原值解析，后续按界面接入新底座。
- `Tingye/Resources/Localizable.xcstrings` 为根入口、续读、分组、选择和搜索补齐简中、繁中、英文、日文资源。现有字串保持原值。

### 第一里程碑本地证据

| 命令或检查 | 结果 |
| --- | --- |
| `git diff --check`、`git diff --cached --check` | 通过。新文档另查行尾空白、引用路径和 59 个唯一条目。 |
| `python3 scripts/verify-swift-sources.py` | 56 个 Swift target 成员通过，App 48、单测 7、UI 1。 |
| `PYTHONDONTWRITEBYTECODE=1 python3 scripts/test_release_provenance.py -v` | 7 个本地来源守卫用例通过。 |
| `PYTHONDONTWRITEBYTECODE=1 python3 -` 内联检查 | 沿 PBXGroup、PBXResourcesBuildPhase、PBXBuildFile 和文件引用验证 17 个资源，检查 52 个资产清单、宋体注册与字串目录。核对新增 32 个四语键、格式占位符及原 989 个键。和 HEAD 比对现有无障碍标识及偏好声明、启动与 modal 处理、正文偏好、原 UI 测试字节。按色码计算 26 组日夜文本搭配与 6 组控件边界，最小分别为 5.77∶1 和 3.21∶1。 |
| `command -v swift; command -v swiftc; command -v swift-frontend; uname -s` | Linux 环境无可调用的 Swift 前端。本次没有 Swift 解析、SDK 类型检查、iOS 编译或模拟器结果。 |

源码复核以项目 iOS 17 部署目标为准，检查 SwiftUI 单栈值路由、可见导航栏、焦点、自动网格、样式和资源调用点。布局、无障碍焦点、菜单在最窄屏和最大辅助字号下的实际表现，以及 UIKit picker 与 SwiftUI sheet 的时序仍需 macOS/设备确认。临窗深层页面临时与已迁移书库并存，后续逐屏接入以消除跨页视觉差异。

用户曾报告选文件后无响应，仍缺对应设备、入口和提供方的复现证据，也没有根因或修复结论。后续用与实施源码相同的 SHA 留存单元和 UI Actions 结果，并按 [方案](PLAN.md) 补齐真机覆盖。当前工作保持未提交，未触发远端操作。

## 第二里程碑 · 添书、连接、详情与阅读目录

结构指界面代码已落地；部分指子表面已改，其余仍需实施。系统选择器按之前的产品语义呈现。所有行均需 macOS 实际编译、UI 回归和适用设备场景验证。

| ID | 实施口径及文件 | 待验证或继续实施 |
| --- | --- | --- |
| G03 | 部分。`Tingye/TingyeApp.swift` 的根与添书反馈显示任务、活动队列、成功和失败。沿用结果 sheet 及呈现 token。 | 其他未迁移页面沿现有反馈样式。验进度与结果切换、弹层叠放、长错误和焦点。 |
| S04 | 补齐移动分组的结构。`Tingye/ShelfView.swift` 区分新建、已有分组与不分组，保留原命名、移动和取消语义。 | 重命名与删除继续用系统确认。验多级路径、保存、取消及键盘。 |
| S06 | 结构。`Tingye/LibraryViews.swift` 以书籍概览和读听按钮起首，随后是简介、目录与管理。展示独立听书位置、本地缺失时的备份入口、目录预览加载失败和重试。 | 验详情首屏、简介 sheet、恢复分支与实际预览失败。 |
| S07 | 结构。同文件把分组、导出、修书、TXT 重新分章和删除列为可扫描的管理操作。两种删除范围的原确认保留，修书选择器仍送原修复管线。新增取消移除 UI 回归源码。 | 验实机文件选择取消、同格式修复、备份分享、删除范围和取消保留。 |
| S08 | 结构。同文件把目录检索、多选、全选范围和独立读听操作编排到列表，底栏区分选择、提交和保存中。 | 验目录筛选的选择范围、多选保存、失败恢复与暂停音频。 |
| S09 | 结构。`Tingye/LibraryViews.swift` 重做本书书签和摘记入口及目的地；`Tingye/ReaderAnnotations.swift` 保有原文定位、笔记编辑、复制、分享和删除。 | 验空态回到书籍、回原文 Locator 及确认删除。 |
| I01 | 补齐添书中心结构。`Tingye/Sources.swift` 把单选/批量、最近结果、无线传输、保存连接和新增协议分区。 | 验书库及设置两条入口、导入忙碌与旧结果。 |
| I02 | 周边结构。选择文件按钮与准备反馈已改，`LocalBookPicker` 和根所有权、单批模式、scope 协调与真实关闭门闩沿原实现。 | 系统选择器内部由 iOS 呈现。执行真实 Files 单选、批量取消、再开和结果重选用例并走查提供方。 |
| I03 | 结构。`Tingye/ShelfView.swift` 更新逐项结果，展示等待、处理、成功和失败原因；`Tingye/TingyeApp.swift` 支持从进度查看同一队列。保留部分成功和重新选择。 | 计数来自已有报告，无分阶段解析百分比。验混合结果、进行中关闭结果、长文件名和大字号操作。 |
| I04 | 结构。`Tingye/Sources.swift` 将连接与访问凭据分组，字段有可读标签和键盘次序，密码保持 SecureField。连接目录只显示协议和主机，移除仍确认。 | 验有效/无效地址、键盘、小屏、编辑回填、取消和移除。 |
| I05 | 结构。同文件整理 WebDAV 路径、文件夹和可导入行；列目录的空、搜索无匹配、正在读取、离线、登录与重试可区分。 | 验真实 WebDAV 的目录、401、离线、恢复及下载。 |
| I06 | 结构。同文件保留 OPDS 本地筛选、远程检索、分页、分类、封面和导入，区分首次空、无匹配及失败重试，错误重试仍用上次请求。 | 验真实 feed、搜索与翻页、认证、离线及导入。 |
| I07 | 结构。`Tingye/SMBBrowser.swift` 区分共享和子目录，复用文件行与状态，根搜索匹配共享名；打不开时提示地址、登录和系统本地网络权限。 | 验 SMB 真机授权、离线、重试、递归与下载。既有会话和认证实现沿用。 |
| I08 | 结构。`Tingye/Sources.swift` 分隔连通、启动、错误和收到的文件，保留地址复制、重连、返回和结束。地址仍只显示在传书页。 | 验真机本地网络拒绝、同网段上传、错误条目、重连和退出关闭服务。 |
| R06 | 结构。`Tingye/ReaderView.swift` 改目录、书签、插图和笔记容器，保留章节号、在读/朗读状态、锚点打开和书签确认。 | 验原生和 PDF 的目录、插图、书签、跟读关闭时定位。 |
| R07 | 结构。`Tingye/Readium/ReadiumReaderView.swift` 改目录层级、搜索入口、书签、摘记及未定位提示。 | 验目录层级、原始链接、书签删除和未定位数据，原书与派生样本均走查。 |
| R08 | 结构。`Tingye/ReaderView.swift` 的共用书内搜索展示等待、无匹配、计数与原文片段。保留最多 200 处提示、异步搜索及偏移定位。 | 执行真实查询、查找同章多处命中及 Readium 可见匹配，验键盘和最大字号。 |
| R10 | 部分。`Tingye/ReaderAnnotations.swift` 更新共享摘记行、空态和笔记编辑器，保留标注色、未定位提示、编辑/分享/删除。 | 原文选段调色面板仍待设计迁移。验五色、旧绿色兼容、编辑和取消。 |
| R12 | 部分。`Tingye/ComicReaderView.swift` 更新页目录、书签过滤、当前页和空态。保留原缩略图、页码跳转及深色呈现。 | 主漫画工具栏、错误及帮助待后续实施。验缩放、阅读方向与目录返回。 |

本里程碑推进 **19 项**，其中 **S04、I01** 是既有条目补齐，新增推进 **17 项**。因此累计 27 项有代码进展，**32 项尚未迁移**，分别为 G02、G04、R01–R05、R09、R11、R13–R14、P02–P08、M03–M06、T01–T10。另有 M01、M02 的页面内部及上述部分条目的剩余表面。完整播放器、统一摘记、统计、设置、备份和正文工具继续按覆盖矩阵推进。

### 第二里程碑本地证据

- `git diff --check`、`git diff --cached --check` 通过；`python3 scripts/verify-swift-sources.py` 验证 56 个 Swift target 成员；`PYTHONDONTWRITEBYTECODE=1 python3 scripts/test_release_provenance.py -v` 通过 7 项。
- `PYTHONDONTWRITEBYTECODE=1 python3 -` 内联检查验证 17 个项目资源引用、52 个资产清单和书封宋体注册。两次累计添加 142 个四语键，原 989 个键照旧；核对新增键的占位符。日夜标称色共核对 28 个文本组合与 6 个控件边界，最小分别为 5.67∶1 和 3.21∶1。
- 以 HEAD 划定源码边界并比对。原测试字节和首里程碑新增回归保留；此次追加详情两种删除范围与取消回归。原无障碍 ID、持久化偏好、冷启动、根文件选择、远程下载/协议实现、正文/导航器、定位、标注引擎、漫画解码与原始纸色比较通过。
- `command -v swift; command -v swiftc; command -v swift-frontend; uname -s` 确认 Linux 无 Swift 前端。本次没有 Swift 解析、SDK 类型检查、编译、运行或界面验收证据。

上线前重点验证极窄屏与大字号的操作栏、搜索与保存键盘、VoiceOver 聚合标签、错误重试以及嵌套 sheet 和文件选择器。用户报告「选文件后无响应」仍缺真机复现、根因和修复证据。工作区保持未提交，下一轮可继续使用同一分支。


## 第三里程碑续作 · 深层界面、状态和验收

中断前已保存播放器、阅读器、摘记、统计、设置与备份的实施代码。续作完成状态和格式文案、自然布局及源码复核。新增原版 PDF 无可用页、插图加载与失败、摘句空/失败/重试、数据导出失败的可见反馈。坏 PDF 只读取 PDFKit 已创建文档的页数，仍沿用同一个 PDFView、页变化观察器与缩放设置。恢复了 `player.endListening` 原标识。词表及项目/测试比对针对构建 148。

### 本地验证

| 命令 | 结果 |
| --- | --- |
| `git diff --check`、`git diff --cached --check` | 通过，索引为空。 |
| `python3 scripts/verify-swift-sources.py` | 56 个 Swift target 成员通过，App 48、单测 7、UI 1。 |
| `PYTHONDONTWRITEBYTECODE=1 python3 scripts/test_release_provenance.py -v` | 7 个本地来源守卫用例通过。 |
| `PYTHONDONTWRITEBYTECODE=1 python3 docs/redesign-20261121/verify-local.py` | 检查 17 个打包资源、52 个资产清单、4 个注册字体、989 个原语言键及 312 个新增四语键的占位符。对照构建 148 查验 31 个保护区段、原无障碍标识和持久化声明及共享图标引用；原 216 个测试方法保留，累计追加 3 个 UI 用例（摘记导航、取消移除、坏 PDF 返回），尚待执行。标称日夜/高对比文本 68 组、控件边界 12 组，最低分别 5.77∶1、3.21∶1。核对 59 行。 |
| `PYTHONDONTWRITEBYTECODE=1 python3 scripts/check-redesign-structure.py` | 历史脚本以 `18481af` 检查构建 143，在 `EPUBNavigatorHost.swift` 与其旧基线不一致处失败。该文件在 148 基线前已改变，与本工作区的 148 字节一致。原脚本及工作流保持原样。 |
| `command -v swift swiftc swift-frontend xcodebuild`、`uname -s` | Linux 无上述工具及 Apple SDK。没有 Swift 解析、类型检查、编译、模拟器、截图或真机通过结果。 |

只读比对协调方清单与当前工作区。20 个缺失文件均为 `Design/v21-swiss/icon/out/`（13）、`Design/v23-time/icon/out/`（4）、`Design/v31-anthropic/app-icon/out/`（3）的历史输出。HEAD 是普通 PNG。沿 PBXGroup 和打包资源反查生产引用，并核对应用/构建源码与真实 AppIcon 资产，20 个文件均不进入 App 或测试资源。排除项仅为这 20 条。本轮对它们没有恢复、覆盖、暂存或提交。生产 AppIcon 目录字节与 148 一致。

### 首轮 macOS Actions 与 R05 修订

Tests run `44929297226` 的 Unit 和 UI Checkout 日志均记录 `9df50d887093a7a66bca3fc1a27dff98971c2033`。两项均编译成功。Unit 执行 186 项、0 失败。UI 在 iPhone 17 Pro（iOS 26.4.1）模拟器执行 33 项、1 失败，日志未见跳过。摘记导航、取消移除、坏 PDF 返回三个新增 UI 用例均通过。

唯一失败为 `testLargestTypeReaderToolsCanScrollWithoutLosingBackButton`，`TingyeUITests/DesignFlowTests.swift:813`。该断言检查工具按钮可点击、整体进入滚动视口且高度至少 44 点后，要求其左侧框线距屏幕左缘至少 16 点。UI 日志在检查第一个按钮 `reader.contents` 时记录实测 12 点。原生文字/PDF 共用的 `ReaderView.chapterBar` 在页签迁移后使用 `Theme.space3`，实际为 12 点。本地将这个面板的内容内边距改用现有 `Theme.space4`（16 点），保留全宽实底、工具滚动与所有测试断言。

本次修订通过 `git diff --check`、`git diff --cached --check`、`python3 scripts/verify-swift-sources.py`（56 个成员）、`PYTHONDONTWRITEBYTECODE=1 python3 scripts/test_release_provenance.py -v`（7 项）和 `PYTHONDONTWRITEBYTECODE=1 python3 docs/redesign-20261121/verify-local.py`。新布局待在修订 SHA 上执行原 UI 用例和全套测试，确认最大字号下四个按钮的完整框线及返回按钮可达。独立的真机验收仍待开展。

### 第二轮 macOS Actions 与派生 EPUB 调查

Tests run `44931620062` 的两份实际 Checkout 日志均记录 `cbbe25c8060635199995dae7cbdea461806578da`。两项均编译成功。Unit 186 项通过。UI 在 iPhone 17 Pro、iOS 26.4.1 上执行 33 项，1 项失败，日志未见跳过。原 R05 的 `testLargestTypeReaderToolsCanScrollWithoutLosingBackButton` 已通过。

- **已证实的失败阶段**。唯一失败是 `testEPUBDerivedFixtureSmokeAndSearch`。测试以 `reader-original` 启动派生 EPUB，首个条件为 `DesignFlowTests.swift:315` 等真实目录按钮 `reader.contents`，时限 20 秒。第二轮在测试相对时间 24.59 秒开始等待，44.67 秒请求失败快照，尚未进入后续 WebView、目录或搜索断言。第一轮相应时间为 9.49 秒开始等待、15.99 秒进入 WebView 查询，随后完成目录、搜索和排版。
- **失败附件与源码**。第二轮 `TingyeUITests.xcresult` 下 `Data/data.0~s3emUDvJqnl1xILbF09zFLAxRWV…` 是 PID 14184 的文本无障碍快照。它显示 `reader.epubNavigator` 已挂载，WebView 无正文后代，`reader.epubPage` 为「未分页」，标题仍为书名，书签禁用。快照中未出现 EPUB 打开失败面板或目录按钮。源码中目录只在 `chrome && ready && session.error == nil` 时出现，`locationChanged` 先通过回调过滤、再更新分页标记和就绪状态。证据支持故障发生在首个可用位置确认前。快照无法区分 WebKit 导航/资源交付停顿、回调未送达，或回调被过滤。
- **版本对照与根因边界**。两次提交的 Readium 路径、走查样本、共享样式及测试字节一致。唯一生产差异是另一条路由的原生文字/PDF 工具面板 12→16 点。第二轮同样使用派生样本的另外四个 `testOriginalReader…` 用例均通过。该组合支持间歇性启动或加载问题，尚未证明它来自模拟器或生产 App。构建 146 的 AppSSO 诊断只能作为线索，已有 DEBUG 模拟器钩子在两个 SHA 中相同。本次未得到能够把 AppSSO 或本地 scheme 请求事件与 PID 14184 的失败窗口关联起来的时间序列，因此未改生产代码、测试或就绪条件。
- **有界后续取证**。协调方如安排复现，可在同一个 `cbbe25c`、同款 iOS 26.4.1 模拟器上，仅运行一次原样的派生 EPUB 用例，保留 xcresult 以及覆盖启动到断言结束的模拟器统一日志。以失败 PID 和同一时钟串联 `loadRequest`、AppSSO 查询及返回、本地 scheme handler 开始/完成与可用页面位置。如果该次通过，保留对照及未复现结论。如果再失败，先用日志区分 WebKit 资源阶段与 App 位置确认阶段，再决定是否缩小生产修订范围。真机原 EPUB、派生 EPUB、目录与搜索仍待验收。

本轮只更新此文档。本地重新通过 diff 空白与暂存检查、Swift target 成员检查、7 项发布来源守卫用例及 `verify-local.py`。Linux 没有 Apple SDK 或 Xcode，未新跑本机 Swift 编译或模拟器。历史守卫的旧基线结论仍见上文。

派生 EPUB 单用例诊断已接入现有 `tests.yml` 的显式手动模式，默认完整 Unit/UI job 保留。首次诊断 `44935673186` 已通过 SHA 和环境检查，随后 Xcode 26.6 在运行测试前拒绝 `-test-iterations 1`，以 64 退出，原用例启动 0 次。该次没有执行 EPUB 复现实验。脚本已移除此参数，保留默认单次执行及成功时启动次数等于 1 的检查。协调方推送修订后可执行 `gh workflow run tests.yml --ref redesign/full-product-20261121 -f diagnostic_mode=epub-derived-once`。诊断配置 SHA 与被测 `cbbe25c` 分别记录；单次诊断不构成完整测试结果。YAML、Bash、Python 及六种事件/输入分流已静态核对，两个原 job 的新增条件以外逐字一致。工作区原守卫报告本次获准的 `.github` 差异。固定 `cbbe25c` 源码的基线边界断言经 Git 对象只读比对通过。精确环境和证据口径见 [派生 EPUB 单用例取证](EPUB-DIAGNOSTIC.md)。

### 修订后的派生 EPUB 单用例结果

Run `44936246544` 实际使用配置 SHA `51df34e97321b3e11cb2275646688f3a8761b25c` 和干净的应用/测试 SHA `cbbe25c8060635199995dae7cbdea461806578da`。arm64 runner 镜像 `20261117.0516.1`，Xcode 26.6（17F113），iPhone 17 Pro、iOS 26.4.1（23E254a）。首次诊断的 64 退出和 0 个用例仍计作启动参数错误。修订后的单次诊断退出 0，原用例启动 1 次、通过 1 项、失败 0、跳过 0，耗时 107.520 秒。完整 Unit/UI 未执行，第二轮整套测试的 1 个 UI 失败仍保留。

成功路径中，PID 14682 的 WebKit 页面约 18:46:01.37 UTC 发出首个请求，WebContent 14750、14757 的首批本地资源任务于 18:46:05.56–05.89 走通，随后两个主 frame 于 18:46:13.58–13.94 加载完成。18:46:15.47 从无障碍树看到目录，18:46:15.67 的快照记录首章分页标记。测试随后通过网页正文、目录、搜索结果、排版及返回书库检查。过滤日志仅见一条 SSO 偏好读取，未检出 `tryAuthorize` 或 AppSSO 查询。整套失败没有可比的 WebKit 时间线。单跑通过支持间歇性表现，未证明根因或修复。新模拟器、禁用并行及无前序用例是本次诊断的区别。

前置服务列表和结束截图采集均超时。后置服务状态、回查日志、结果摘要和附件导出命令成功，附件 manifest 为空。详细时间线和证据限制见 [派生 EPUB 单用例取证](EPUB-DIAGNOSTIC.md)。完整套件和真机验收仍待完成。

### Apple 平台后续验收

用经审查提交的同一实施 SHA 先做 macOS 编译，再执行现有单元和 UI Actions，两类测试和来源守卫都保留。覆盖 iOS 17 和当前系统，以及小屏/横屏、深浅/高对比、最大字号、减少动态效果及透明度、VoiceOver、键盘和四语长串。导入要真机走本机、iCloud Drive 和第三方提供方的选中、取消、重新选择、作用域与结果弹层。既有「选文件后无响应」仍缺复现和根因或修复证据。

数据验收在隔离的旧库副本上进行，包含旧标注绿、旧 EPUB Locator、原生/EPUB/PDF/漫画、独立读听位置、缓存和密码保护。先验证旧备份可还原，再用两个环境验证 iCloud 的归档与进度合并、离线和冲突。保留旧结构与迁移机制，比较重启前后目录、摘记、进度及位置，验证键值未移入新的默认域。设备验证重点还包括认证回后台、音频路由/中断、保护隐藏内容和大字号下独立 sheet 的呈现顺序。

## 当前 59 项验收矩阵

| ID / 表面 | 实施及生产出处 | 本地静态 | macOS 与设备 |
| --- | --- | --- | --- |
| G01 启动、根栈与返回 | 结构已实施。根路由把书库、摘记、我的接入同一导航栈，内容与迷你播放器同层。 `Tingye/TingyeApp.swift` `StudyRootView`，首载自动开书、前后台刷新与保存、根返回。 | 已静态复核。冷启动、前后台保存区段字节核对。 | 待验证。冷启动、嵌套返回路径、滚动和焦点恢复。 |
| G02 应用锁 | 结构已实施。锁屏遮罩及辅助树隐藏，区分等待认证和失败后重试。系统生物识别和密码弹层内部 N/A。 `Tingye/Library.swift` `AppLockGate`、`PrivacyLock`，系统认证及后备设备密码。 | 已静态复核。PrivacyLock 字节一致，锁遮罩同原 scene 生命周期。 | 待验证。Face ID、Touch ID、密码后备、取消，已弹 sheet 的退后台隐私。 |
| G03 全局状态与操作失败 | 结构已实施。任务进度、结果队列链接、提示关闭及失败反馈用同一呈现。 `Tingye/TingyeApp.swift` `FeedbackOverlay`、`StudyRootView`，通知、活动、失败 alert、结果 sheet。 | 已静态复核。生产调用点及结果 token、关闭门闩核对。 | 待验证。优先级、结果进出，多个 sheet 叠放和大字。 |
| G04 系统分享与外部打开 | 周边已实施。摘句卡、逐书 Markdown、录入及数据导出按钮和失败落点已分区。系统分享及外部交付内部 N/A。 `Tingye/TingyeApp.swift` `onOpenURL`，`Tingye/ShelfView.swift` `ShareSheet`，`Tingye/DailyQuoteCard.swift` `QuoteShareLink`。 | 已静态复核。ShareSheet 和 onOpenURL 字节一致。 | 待验证。分享可用类型、取消、失败，外部打开和 Files 提供方。 |
| S01 书库根与续读 | 结构已实施。续读条、快捷入口、书种切换、连续书目和摘句。 `Tingye/ShelfView.swift` `ShelfView` 的续读条，`Tingye/AppModel.swift` `lastReadingBook` 与样例初始化。 | 已静态复核。核对最近阅读来源、读/听进度与样例调用。 | 待验证。长标题、空库、漫画页号、深色、小屏。 |
| S02 书目筛选、排序与视图菜单 | 结构已实施。书目工具集中放置，筛选、排序、布局及整理各自可达。 `Tingye/ShelfView.swift` `filterMenu/sortMenu/layoutMenu`、`ManualShelfOrder`。 | 已静态复核。排序/布局键、原按钮 ID 核对。 | 待验证。全部排序、筛选组合、手动拖动及重开。 |
| S03 书库搜索 | 结构已实施。历史、清空、查询和无匹配结果有独立位置。 `Tingye/ShelfView.swift` `startSearch/cancelSearch/rememberSearch`。 | 已静态复核。搜索语句、字段 ID 和取消路径核对。 | 待验证。键盘遮挡、打开结果、清空及返回焦点。 |
| S04 嵌套分组、移动及命名 | 结构已实施。目录页及移动分组按新建、现有、根目录分组。命名和确认内部使用系统。 `Tingye/ShelfView.swift` `ShelfView(group:)`、`GroupPickerView`、重命名 alert。 | 已静态复核。分组入口、创建移动及删除调用核对。 | 待验证。多级移动、输入校验、保留书籍确认和取消。 |
| S05 书目菜单、整理与隐藏 | 结构已实施。整理勾选、批量操作、空/禁用态及书目触点调整。 `Tingye/ShelfView.swift` `menu/finishEditing/hideSelectedBooks/removeSelectedBooks`，`Tingye/Library.swift`。 | 已静态复核。原标识和藏书、删除入口核对。 | 待验证。重排、隐藏/恢复鉴权、删除与取消。 |
| S06 书籍详情及简介 sheet | 结构已实施。读听分开显示，之后为简介、目录和管理，本地缺失提供恢复。 `Tingye/LibraryViews.swift` `BookDetailView`。 | 已静态复核。详情 ID、预览等待/错误/重试核对。 | 待验证。简介展开，加载失败、无本地书的真机恢复。 |
| S07 详情操作及修书 picker | 结构已实施。导出、分组、修书、TXT 重分章、删除分别呈现。修书 picker 内部使用系统。 `Tingye/LibraryViews.swift` `BookDetailView`，`Tingye/AppModel.swift` `repair/resplit`。 | 已静态复核。两种删除范围、取消回归源码和原 picker 回调核对。 | 待验证。原文件修复、作用域交付、两种删除范围、取消。 |
| S08 目录管理与批量已读 | 结构已实施。章节检索和多选管理区分普通、选中、保存状态。 `Tingye/LibraryViews.swift` `ChapterManagerView`。 | 已静态复核。选择范围、提交回调及原 ID 核对。 | 待验证。过滤后全选、批量已读、保存失败和暂停保持。 |
| S09 详情内书签与本书摘记 | 结构已实施。本书书签/摘记独立索引，编辑、定位、分享及删除确认。 `Tingye/LibraryViews.swift` `BookDetailView`、`Tingye/ReaderAnnotations.swift` `NotesList`。 | 已静态复核。LocatorTarget 回调、未定位提示及入口核对。 | 待验证。旧书签、未定位条目和编辑/取消。 |
| I01 添书中心 / 来源目录 sheet | 结构已实施。添加来源、文件/批量、连接和最近结果分区。 `Tingye/Sources.swift` `ImportHubView/SourcesView`；书库与 `Tingye/StatsView.swift` `SettingsDirectoryView` 发起。 | 已静态复核。书库、设置入口及 modal token 生命周期核对。 | 待验证。两条入口，任务进行中打开、关闭并再选。 |
| I02 系统文件选择 | 周边已实施。文件入口与等待/取消反馈在应用内。UIDocumentPicker、Files 和提供方 UI 内部 N/A。 `Tingye/TingyeApp.swift` `StudyRootView`、`Tingye/ShelfView.swift` `LocalBookPicker`、`Tingye/AppModel.swift` `requestFileImport`。 | 已静态复核。唯一根宿主、复制、单批、回调去重、原 scope 比对。 | 待验证。真机 Files、本机/iCloud/第三方、取消与空交付、选择后无响应复现。 |
| I03 导入进度、结果与重选 | 结构已实施。逐项等待、处理中、成功、失败和重选，已有报告计数。 `Tingye/AppModel.swift` `importFiles`、`Tingye/Models.swift` `ImportReport`、`Tingye/ShelfView.swift` `ImportResultsView`。 | 已静态复核。报告与 token 引用核对，AppModel 无改动。 | 待验证。混合结果、部分成功、失败文件重选，不使用过期 URL。 |
| I04 新增/编辑连接与移除确认 | 结构已实施。连接与登录字段分开，安全输入、焦点、校验和确认。 `Tingye/Sources.swift` `SourceEditor`、`SourcesView`、`SourceHTTPClient`。 | 已静态复核。核对协议客户端和密码类型，目录只呈现主机。 | 待验证。键盘、无效地址、编辑回填、认证失败、移除。 |
| I05 WebDAV 文件夹递归 | 结构已实施。远程目录分开列文件夹和书，空、筛选、离线及错误可重试。 `Tingye/Sources.swift` `WebDAVBrowser`。 | 已静态复核。下载和目录函数、错误分流核对。 | 待验证。带认证的 WebDAV、401、离线恢复、下载。 |
| I06 OPDS 浏览、检索与分页 | 结构已实施。区分目录、检索、分页、无命中及错误。 `Tingye/Sources.swift` `OPDSBrowser/OPDSFeed`。 | 已静态复核。查询路由、原最近请求、导入语义核对。 | 待验证。真实 feed 分页、账号权限、弱网、无结果。 |
| I07 SMB 共享、目录与下载 | 结构已实施。共享根、子目录、下载、错误提示与重试。 `Tingye/SMBBrowser.swift` `SMBBrowser/SMBConnection`。 | 已静态复核。会话、连接和下载调用核对。 | 待验证。SMB 本地网络权限拒绝/恢复及真实共享。 |
| I08 WiFi 传书与浏览器上传 | 结构已实施。连接等待/就绪、地址复制、接收结果和重连结束。 `Tingye/Sources.swift` `WiFiTransferView/WiFiTransferServer`、`Tingye/Info.plist`。 | 已静态复核。WiFiTransferServer 字节一致。 | 待验证。局域网浏览器上传、错误项、拒绝权限、退出后停服务。 |
| R01 格式路由及全屏 | 周边已实施。全屏入口周边、加载/失败和返回路径已实施。格式路由内部为 N/A。 `Tingye/TingyeApp.swift` 根 cover、`Tingye/Readium/ReaderRouter.swift`。 | 已静态复核。ReaderRouter、AppModel 和根呈现门闩比对。 | 待验证。EPUB、原生文字、PDF、漫画各从多种入口打开及保存返回。 |
| R02 原生分页、滚动及文内媒体 | 结构已实施。原生覆盖工具与插图目录的加载/失败已实施；原生正文视口、分页和媒体渲染保持。 `Tingye/ReaderView.swift` `ReaderView/NativeTypesetter/ScrollingText/ReaderMediaPage`。 | 已静态复核。原生正文、CoreText/UIKit 区段比对。 | 待验证。单/双页、连续滚动、图表文字、放大字号、位置不动。 |
| R03 原页 PDFKit | 结构已实施。PDF 共用章页工具，PDFKit 无可用页时提供退出与修复指引。 `Tingye/ReaderView.swift` `ReaderDocument/PDFReader`。 | 已静态复核。核对原 PDFKit 页变更、背景及缩放操作，新增坏 PDF 返回用例。 | 待验证。损坏文件、扫描 PDF 与可提取文字 PDF；缩放、页位和纯图片页。 |
| R04 Readium EPUB 加载与导航 | 结构已实施。Readium 的打开中、失败重试及顶部返回有专门呈现。 `Tingye/Readium/ReadiumReaderView.swift` `open/locationChanged`、`EPUBNavigatorHost.swift`、`PublicationStore.swift`（同目录）。 | 已静态复核。发布物会话、导航器回调及定位区段比对。 | 第二轮派生 EPUB 在首个可用位置确认前超时。同源码单用例之后通过一次，根因仍待确认。原书、派生书、内链和失败恢复仍需设备验收。 |
| R05 原生/PDF 工具栏、更多及自动翻页子面板 | 结构已实施。原生/PDF 顶栏、章页选择、更多及自动翻页按任务分层。 `Tingye/ReaderView.swift` `chapterBar/moreMenu/morePanelRows`。 | 已静态复核。面板内容恢复 16 点水平边距，测试及原工具 ID 保留。 | `cbbe25c` 最大字号滚动、边距及返回用例已通过。44 点触控、横屏、定时/停止及弹层切换仍需设备验收。 |
| R06 原生目录 sheet | 结构已实施。目录、书签、插图、笔记各有段落和状态。 `Tingye/ReaderView.swift` `ContentsView/ChapterScrubber`。 | 已静态复核。章页跳转、监听状态和书签删除调用核对。 | 待验证。大图加载/失败、实时朗读状态、书签移除和位置。 |
| R07 EPUB 目录、书签与摘记 sheet | 结构已实施。EPUB 各索引页分段，保留原目录深度、摘记与未定位提示。 `Tingye/Readium/ReadiumReaderView.swift` `contentsView`。 | 已静态复核。原 Locator 目标和目录回退分支核对。 | 第二轮冒烟未到目录断言，另外四个 Readium 用例通过。原书层级、关闭及书签/标注跳转待设备验收。 |
| R08 书内搜索 | 结构已实施。搜索入口、等待、无命中、片段和数量提示。 `Tingye/ReaderView.swift` `ContentsView/ReaderSearch`，`Tingye/Readium/ReadiumReaderView.swift` `showSearch/jumpTo`。 | 已静态复核。UTF-16 偏移、异步取消、200 条上限及 UI 标识核对。 | 首轮派生 EPUB 搜索通过，第二轮在启动等待失败，未执行该用例的搜索断言。同章重复命中、键盘与 Readium 可见命中待设备验收。 |
| R09 排版及更多排版子页 | 结构已实施。文字、纸色、翻页、更多排版与个人字体分组；EPUB 有适用说明。 `Tingye/ReaderView.swift` `ReadingPreferencesView/MoreTypographyView`、`Tingye/Readium/ReadiumPreferencesBridge.swift`。 | 已静态复核。ReaderPaper、UIKit 正文字形、Readium 桥接及原偏好声明比对。 | 待验证。各纸色、长文本、两引擎及固定版式、字体回退。 |
| R10 选段、标注、笔记编辑与删除 | 结构已实施。选区、扩展、颜色、样式、笔记与引用各有层级，删除保持确认。 `Tingye/ReaderAnnotations.swift` `SelectionPanel/NoteEditor/NotesList`、`Tingye/Readium/ReadiumAnnotations.swift`、`Tingye/Readium/ReadiumReaderView.swift` `selection`。 | 已静态复核。五色、历史绿色、画线和句区间比对。 | 待验证。五色三样式、旧绿、编辑、选择/删除/复制/分享。 |
| R11 阅读中辅助听书 | 结构已实施。两个文字读器的读听控制和回到朗读状态独立呈现。 `Tingye/ReaderView.swift` `listeningControls`、`Tingye/Readium/ReadiumReaderView.swift` `bottomActions/refreshSpeech`、`ReadiumSpeechBridge.swift`（同目录）。 | 已静态复核。Readium 跟读、音频引擎和双进度路由核对。 | 待验证。播放/暂停、跨章、离开跟随、位置独立、深浅纸高亮。 |
| R12 漫画全屏、页目录和帮助 | 结构已实施。漫画顶部书签与帮助、下方进度与方向工具、页目录与坏图反馈。帮助确认内部使用系统。 `Tingye/ComicReaderView.swift` `ComicReaderView/pageDirectory/ZoomableComicImage`。 | 已静态复核。解码、缩放、模式存储与进度核对。 | 待验证。左右向/竖滚、缩放后开合工具、空书签和坏图。 |
| R13 专注计时、运行及总结 | 结构已实施。预设/自定义、会话冲突、进行中和结束小结分区。 `Tingye/ReaderView.swift` 专注 sheet、`Tingye/FocusSession.swift` `FocusStartView/FocusSummaryView`。 | 已静态复核。FocusSessionStore 字节一致，按钮动作原路径。 | 待验证。后台恢复、同书/异书、停留/放弃、完成与计时无障碍。 |
| R14 读完收尾 sheet | 结构已实施。读完摘要、摘句、读完感、下一本及回书库。 `Tingye/ReaderView.swift` `finishPresented`、`Tingye/BookFinishView.swift`。 | 已静态复核。读完触发、候选和摘记保存调用核对。 | 待验证。最后页触发、无候选/本地内容、编辑键盘和跳转。 |
| P01 全局迷你播放器 | 结构已实施。紧凑迷你播放条保有展开、回朗读、播停，含合成与错误状态。 `Tingye/TingyeApp.swift` `MiniPlayer`。 | 已静态复核。原回跳、播放器 ID 及书库隐藏规则核对。 | 待验证。暂停再展开、回朗读、合成与后台中断、大字。 |
| P02 全屏播放器与句流 | 结构已实施。书目、句流、句进度及核心键分区；紧凑布局固定播停。 `Tingye/PlayerView.swift` `PlayerView/SentenceProgressControl`。 | 已静态复核。跳句、拖动提交、书签、回原文与 UI 标识核对。 | 待验证。小屏/横屏/最大字号、重复句及暂停拖动。 |
| P03 播放器从属弹层 | 结构已实施。封面放大、章节、声音、倍速及定时有独立入口；结束保留系统确认。 `Tingye/PlayerView.swift` 封面/章节/声音 sheet、倍速/定时菜单、结束确认，`Tingye/TingyeApp.swift` `AirPlayButton`。 | 已静态复核。原菜单标识、定时值及停止回调核对。 | 待验证。菜单取消、定时关闭、封面和返回原任务。 |
| P04 听书章节列表与检索 | 结构已实施。章节检索、原位/进度、结果空态集中在列表。 `Tingye/PlayerView.swift` `ChapterListView/ChapterProgressSlider`。 | 已静态复核。章滑杆/跳章仍调用原逻辑。 | 待验证。同章位置与暂停、键盘、选择后关闭。 |
| P05 声音设置、试听与保存 | 结构已实施。显示当前声音、试听和保存，含音色加载和失败信息。 `Tingye/PlayerView.swift` `VoiceSettingsView`、`Tingye/SpeechPlayer.swift` `SpeechVoiceCache`。 | 已静态复核。试听、保存与恢复实现区段比对。 | 待验证。从三入口进出、取消、保存、试听恢复与 AirPlay。 |
| P06 音色、语速、分角色子页 | 结构已实施。音色、语速与分角色子页有独立导航和当前值。 `Tingye/PlayerView.swift` `voiceDetail`、`Tingye/DialogueRoles.swift`。 | 已静态复核。预览参数、角色选项和 DialogueRoles 比对。 | 待验证。各提供方音色、自定义或缺音色、Beta 分角色。 |
| P07 云语音连接与草稿 | 结构已实施。云提供方、凭据、连接配置、音色与重试反馈。 `Tingye/PlayerView.swift` `cloudConfiguration`、`Tingye/SpeechPlayer.swift` `VoiceOptions`、`Tingye/Services.swift` `CloudSpeech`。 | 已静态复核。原提供方、模型和安全字段不变量核对。 | 待验证。六种提供方、失败/离线、返回系统音色、保存取消。 |
| P08 音频系统表面 | 周边已实施。输出设备按钮及播放器错误恢复的应用周边已实施。AirPlay、锁屏媒体和音频系统内部 N/A。 `Tingye/SpeechPlayer.swift` `SpeechAudioSession/SpeechPlayer`、`Tingye/TingyeApp.swift` `AirPlayButton/KeepAwakeModifier`。 | 已静态复核。AVRoutePicker 标识、SpeechPlayer、常亮代码核对。 | 待验证。真机耳机/AirPlay/锁屏/遥控/中断，后台音频。 |
| M01 统一摘记索引 | 结构已实施。根与我的双入口、按书/类型查询、回原文、删除及导出。 `Tingye/NotesUnifiedView.swift` `NotesUnifiedView`、`Tingye/StatsView.swift` `.notes`。 | 已静态复核。原 LocatorTarget 与授权可见数据、UI 回归源码核对。 | 待验证。授权前后、含听书书签、长查询、系统分享取消。 |
| M02 我的概览及每日摘句 | 结构已实施。我的概览含本月、藏书/时长/连读、目的地和摘句状态。 `Tingye/TingyeApp.swift` `StudyRoute.me`、`Tingye/StatsView.swift` `StatsView(ji:)`、`Tingye/DailyQuoteCard.swift`。 | 已静态复核。统计来源、摘句种子和回原文核对。 | 待验证。长数字、大字、无书、读书失败重试、返回。 |
| M03 阅读足迹 | 结构已实施。周期与区间、读听拆分、图表、逐次记录、排行、导出失败。 `Tingye/StatsView.swift` `statisticsContent`。 | 已静态复核。区间、记录及原图表口径复核。 | 待验证。分区间、大字及图表朗读、旧数据及导出。 |
| M04 每日目标与提醒 sheet | 结构已实施。目标、提醒、快捷分钟与通知拒绝分别呈现。 `Tingye/StatsView.swift` `goalEditor/ReadingReminder`、`Tingye/GeneralSettingsView.swift` `celebrateIfGoalReached`。 | 已静态复核。原目标和重排、授权接口核对。 | 待验证。拒绝/允许、已达标、取消、通知实际到达。 |
| M05 阅读日历 sheet | 结构已实施。月份导航、日期网格、选日详情与本月汇总。 `Tingye/ReadingCalendarView.swift` `ReadingCalendarView`、`Tingye/StatsView.swift`。 | 已静态复核。日期、达标计算和读时长来源核对。 | 待验证。四语日期、月切换、零记录、VoiceOver 日期网格。 |
| M06 系统通知与设置跳转 | 周边已实施。拒绝提示及系统设置跳转，应用提示由共享反馈呈现。系统通知及设置内部 N/A。 `Tingye/StatsView.swift` `ReadingReminder`、`Tingye/GeneralSettingsView.swift`，`Tingye/Library.swift`。 | 已静态复核。原 UN 通知及达标回调核对。 | 待验证。首次授权、拒绝、从设置返回、前/后台达标。 |
| T01 设置目录及路径转接 | 结构已实施。五组设置目录，保留独立路由与添书转接。 `Tingye/StatsView.swift` `SettingsDirectoryView`、`Tingye/LibraryViews.swift` `SettingsDestination/settingsDestinationView`。 | 已静态复核。原目标路由、显示标识、模态 token 查看。 | 待验证。从各子页返回、设置导入、系统语言往返。 |
| T02 App 外观 | 结构已实施。系统/日间/夜间用具名色样和选中标记。 `Tingye/LibraryViews.swift` `AppearanceView`、`Tingye/TingyeApp.swift` `WindowAppearance`。 | 已静态复核。外观键、WindowAppearance 与正文纸色区段比对。 | 待验证。外观真切换、深色浅纸独立、高对比。 |
| T03 通用设置 | 结构已实施。语言、阅读目标、漫画和交互分组。 `Tingye/GeneralSettingsView.swift` `GeneralSettingsView`。 | 已静态复核。默认键、冷启动、漫画模式和通知区段比对。 | 待验证。系统语言切换、偏好重开、常亮和系统 Home 指示条。 |
| T04 字体管理及导入 | 结构已实施。个人字体、选中、空态、导入失败/取消。字体 picker 内部使用系统。 `Tingye/Typography.swift` `MyFontsView/FontLibrary`、`Tingye/Readium/ReadiumFontProvider.swift`。 | 已静态复核。FontLibrary、四个注册字体和 Readium 字体桥比对。 | 待验证。字体安装/取消/删除/失效回退、作用域。 |
| T05 选段菜单设置 | 结构已实施。可排序的选段菜单列表具选中/默认及恢复动作。 `Tingye/MenuSettingsView.swift` `MenuSettingsView/SelectionTool`。 | 已静态复核。原排序与至少一项可见规则核对。 | 待验证。拖动/旁白重排、恢复、默认页生效。 |
| T06 TXT 分章规则 | 结构已实施。当前规则、限制、正则编辑及错误/预览分组。 `Tingye/TxtRulesView.swift` `TxtRulesView`、`Tingye/BookImporter.swift` `TxtChapterRules`。 | 已静态复核。原默认、正则编译与重分章调用核对。 | 待验证。非法正则、预设/删除、键盘安全、真实 TXT 重分章。 |
| T07 隐私与关于及子页 | 结构已实施。隐私锁/隐藏书、数据导出、许可和本地隐私政策分组。 `Tingye/LibraryViews.swift` `ProfileView/PrivacyPolicyView/FontLicenseView`。 | 已静态复核。安全调用、原导出内容及缓存确认保留。 | 待验证。隐藏书认证、分享失败和取消、许可资源与链接。 |
| T08 空间整理与清理确认 | 结构已实施。总占用、分项、缓存清理、修复索引分区。破坏性确认内部使用系统。 `Tingye/StorageView.swift` `StorageView/StorageUsage`、`Tingye/Services.swift` `LibraryDisk`。 | 已静态复核。StorageUsage 字节一致、清理/修复调用核对。 | 待验证。缓存失败、空值禁用、书籍及进度保留。 |
| T09 整库备份、还原预览及确认 | 结构已实施。保存、恢复、同步分区；真实阶段、计数、确认、取消及重试。文件 picker 和确认内部使用系统。 `Tingye/ICloudBackup.swift` `ICloudBackupView/ICloudTransferCard/ICloudBackupStore`、`Tingye/Services.swift`。 | 已静态复核。归档和原恢复逻辑区段比对，系统选择仍交原回调。 | 待验证。本机归档、取消/失败/部分文件、云盘真实签名、同标识覆盖。 |
| T10 自动同步与上传状态 | 结构已实施。同步状态、本机提交/接收和手动上传状态有独立位置。 `Tingye/ICloudBackup.swift` `ProgressSync/ICloudUploadStatus/ProgressSyncStatusRows`。 | 已静态复核。同步键和上传/合并区段字节核对。 | 待验证。同账户多设备、无权限/离线、恢复与本机位置冲突。 |
