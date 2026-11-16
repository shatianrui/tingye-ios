# 本地文件导入：历史补丁移植草稿

**已实现、尚未经 iOS/CI/真机验证，不得当作已解决。补丁在本地分支 integrate/ios-import-v30-search，相关用户故障尚未关闭。**

## 历史与证据

- PR #10（c965f13 / 4dfff84）处理 ImportHub sheet 内选择器呈现/回调被吞，已在当前 HEAD。保留 request/consume 与宿主根层呈现。
- 8e38777（2026-11-09）提供单选复制、独立批量入口、协调读取和回归；81acce1 改为从委托直接启动导入。两项未合入 main/HEAD，漏带已证实。
- 用户于 2026-11-17 确认本次症状为「选中文件后无反应，也没有任何报错」。这与 8e38777 所记点选后没有后续、PR #10 所记打开后无导入无报错相似，支持当前历史补丁移植；症状相似仍不足以证明具体根因相同，也不代表真机验证完成或用户故障已关闭。终审据此继续完成，不以等待报错原文或失败书籍为前提。

## 当前移植内容（待验证）

普通入口用 UIDocumentPicker asCopy 单选，点书即导入；批量入口单独显示确认说明。两者均只登记请求并关闭 ImportHub，书库/设置宿主消费请求后再呈现选择器。委托直接 beginImport，不在 picker onDismiss 暂存 URL，完成只交付一次。取消不生成任务；空成功选择保留 PR10 的明确错误。

importFiles 与原书 repair 的后台读取改为 readCoordinated；在 NSFileCoordinator 回调内用 readableURL 完整解析，协调/解析错误继续走原反馈。现有安全作用域 start/stop 继续包住 await。复制选择器不能代替 Open In 的权限边界；不能由 Task 后 startAccessing 推断权限失效。

## 入口、格式与权限边界

书库、设置、结果页 bookImporter 使用复制选择器。onOpenURL 保留入口并经协调读取；原书修复只移植协调读取，其选择器不在此次呈现改动范围。格式仍按 BookImporter 原规则：EPUB、MOBI/AZW/AZW3/PRC、TXT、PDF、HTML、Markdown、DOCX、CBZ/ZIP、备份 JSON。没有增加 DRM 支持或放宽格式校验。离线或不可读的文件提供方仍可能报错，不能宣称已覆盖所有提供方。

## 复现与回归

1. 书库添书 → 选择文件：确认 ImportHub 先关闭；点 TXT/EPUB 一次，不再确认，核对报告与正文。
2. 设置传书与导入重复；覆盖本机、iCloud 已下载/未下载文件与实际使用的第三方提供方。
3. 批量入口勾选多个文件并确认，核对逐项结果；取消后再开普通入口仍为单选，取消不生成任务。
4. 从其他 App Open In 导入、结果页重新选文件、同格式原文件修复；检查失败原因、进度与资源保留。
5. 删除源文件后打开已导入书，确认目录和正文持久化。

已补回 LocalFileImportTests 四项历史单测（尚未执行）：复制/单选配置、委托单次交付与取消、删除源文件后的持久化、缺失文件的失败反馈。仅取消用 nil 区别空成功；保留原断言语义并增加取消后迟到选择的单次交付断言。
已补回 testSingleTapLocalFileImportsThroughSystemPicker（尚未执行），经当前 sources → ImportHub 关闭 → 根层选择器的真实导航，仅 DEBUG 隔离书库生成测试文件。现有混合导入单元/UI 回归及 DesignFlowTests 的搜索 isHittable 原断言保持不变。另需验收设置宿主、独立批量入口及真实提供方。

## 2026-11-17 聚焦终审（静态检查）

- 单选交付：Coordinator 在调用 completion 前设置 completed，重复选择/取消回调不再交付；选中的 URL 直接传给 beginImport，不依赖 picker onDismiss 中暂存的值。取消为 nil，成功但空数组保留明确错误。
- 呈现与批量：Sources 只登记请求并 dismiss；书库/设置宿主在 ImportHub onDismiss 消费一次请求后开启根层 picker。consume 仅清除请求位，批量模式仍可读取，且在置 importing 为 true 前保存到宿主状态；下一次普通请求把模式设回 false。静态调用链没有同时开启第二个 picker 的操作，也没有把选择器挂回 hub。
- 线程与读取：UIKit 的 [UIDocumentPickerDelegate](https://developer.apple.com/documentation/uikit/uidocumentpickerdelegate.md) 为 MainActor，当前委托同步调用 completion，随后进入 MainActor AppModel.beginImport。读取通过 Task.detached 在后台协调，start/stop 安全作用域仍包住 await，Open In 与 repair 保留相同访问边界；未将 Task 后才 startAccessing 写成根因。
- 反馈：beginImport → run 显示 busy/activity；importWithFeedback 把逐项结果汇总为非模态通知，根层 FeedbackOverlay 提供“查看逐项结果”。选中后无需自动弹出第二个 sheet；逐项错误保留在结果报告，外围错误走 message，busy 时也有明确通知。
- 编译目标：NativeCoreTests.swift 已在 TingyeTests 的 Sources，DesignFlowTests.swift 已在 TingyeUITests 的 Sources；没有新增 Swift 文件，无需修改 pbxproj。ShelfView.swift 显式 import UIKit；测试辅助使用的类型、ProgressSync 初始化参数及 XCTest 查询 API 未发现明显不匹配。未做实际编译。
- API 边界：工程部署目标为 iOS 17.0；Apple 标明 [asCopy 初始化器](https://developer.apple.com/documentation/uikit/uidocumentpickerviewcontroller/init(foropeningcontenttypes:ascopy:).md) 自 iOS 14 可用，[searchable 的 isPresented/placement 重载](https://developer.apple.com/documentation/swiftui/view/searchable(text:ispresented:placement:prompt:)-5hhxx.md) 自 iOS 17 可用，[navigationBarDrawer](https://developer.apple.com/documentation/swiftui/searchfieldplacement/navigationbardrawer(displaymode:).md) 与 [always](https://developer.apple.com/documentation/swiftui/searchfieldplacement/navigationbardrawerdisplaymode/always.md) 自 iOS 15 可用。现有搜索补丁保持原样。
- README 链接指向本文件，git diff --check 通过。此轮没有发现必须修改产品代码或既有测试断言的问题，只更新症状证据与终审文档；运行时结论仍待验证。

## 验证前状态

2026-11-17 已将核对过的补丁应用到工作树，并完成上述聚焦静态终审。Linux 无 Xcode，未编译、未运行 iOS 单元/UI 测试、未做真机验证、未触发 CI、未构建 IPA。仍须保持“已实现、尚未经 iOS/CI/真机验证”，记录具体代码版本、设备、提供方与真实结果后再决定是否关闭问题。
