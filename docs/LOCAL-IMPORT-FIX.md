# 本地文件导入修复

用户报告：系统文件列表中可以选到书籍，但点击书籍后没有后续反应。

原入口默认允许多选，单击只选择文件，需要再确认；并通过原位安全作用域 URL 异步读取。普通入口现改为 `UIDocumentPickerViewController(forOpeningContentTypes:asCopy:)` 的复制导入和单选，点选文件后即关闭选择器。批量选择保留在独立按钮，界面说明需要选择后确认。

系统选择器关闭后再启动导入，取消选择不产生任务；委托完成回调只交付一次。导入和原书修复使用后台协调读取，继续保留成功/失败的逐项结果。复制导入 API 参考：[Apple 文档](https://developer.apple.com/documentation/uikit/uidocumentpickerviewcontroller/init(foropeningcontenttypes:ascopy:))。

新增 4 项本地导入单元回归（选择器配置、委托/取消、文件持久化、读取失败）及 1 项实际系统文件选择器 UI 回归；同时重跑原有混合导入结果回归。该 UI 回归仅在 DEBUG 隔离书库启动时生成专用测试文件，不向正常用户书库注入内容。

本机 Linux 已通过 Swift 语法解析；实际编译与测试结果以此修复标签的 GitHub Actions 记录为准。模拟器验证不能替代用户实际文件提供方和重签真机环境。
