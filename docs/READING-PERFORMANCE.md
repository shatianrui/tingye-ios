# 阅读内存与分页取消优化（2026-11-09）

## 改动

- **整书缓存保持有界**：旧实现淘汰最旧书时，若它正在阅读或播放，只删除其队列记录、不删除字典中的整书。切换阅读/播放对象后，这本书永远不会再次参与淘汰。现在只淘汰最旧的非当前书，受保护书一直留在队列中，解除保护后仍能正常释放。缓存目标仍为 4 本，不改变书库、进度或备份格式。
- **真正按最近使用缓存**：打开书籍、异步读取和同步读取的缓存命中都更新最近使用顺序，避免常读的书被当成最旧书重复解码。
- **取消过期分页**：字号、窗口尺寸或章节变化取消视图任务时，同步取消后台 CoreText 分页任务；每页之间检查取消并丢弃部分结果，避免旧任务继续排完整个长章。不会中断正在运行的单次 CoreText 调用，尚未改变富文本准备所在的线程。

## 回归与可执行验证

新增 `ReadingPerformanceTests` 共 4 项，覆盖：曾被保护的书解除保护后能被淘汰、缓存命中更新 LRU/当前阅读书保留、分页中途取消不返回残缺页列表、极小视口 fallback 前也响应取消。

测试通过更新磁盘中的测试书并检查下一次读取结果，验证真实 `AppModel` 缓存行为，不依赖暴露私有缓存。使用临时书库与内存同步存储，不接触实际书库或云端。分页测试通过注入取消检查，在第一页之后确定性取消，无计时竞争。

Unsigned iOS 工作流已纳入新增测试及既有的两项分页完整性回归。未触发远端运行。Mac 上可执行：

```sh
xcodebuild -project Tingye.xcodeproj -scheme Tingye \
  -destination 'platform=iOS Simulator,name=iPhone 17e' \
  -only-testing:TingyeTests/ReadingPerformanceTests \
  -only-testing:TingyeTests/NativeCoreTests/testPaginationCoversEveryCharacterWithoutGaps \
  -only-testing:TingyeTests/NativeCoreTests/testEveryPageRendersAllOfItsCharacters \
  test
```

## 本地验收事实与限制

本环境为 Linux，没有 Swift 编译器、Xcode 或 iOS SDK。修改的 3 个 Swift 文件通过 tree-sitter Swift 语法解析，`git diff --check` 通过；这些检查不能代替 Swift 类型检查、构建或 XCTest。新增/既有 XCTest 尚未运行。未测量峰值内存或耗时，不声称提升百分比。未提交、推送、发布或修改版本号。

缓存的 4 本限制是条目数而非字节数，当前阅读/播放以及索引任务也可能各自持有书对象，不等同于整个进程的内存上限。实际超大书、连续切书、快速调字号和旋转屏幕仍需在模拟器/真机验证。
