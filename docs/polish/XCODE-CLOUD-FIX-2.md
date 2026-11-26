# Xcode Cloud Build 69 测试修复

Build 69 在 iOS 27.2 的四台模拟器上报告 208/217 通过。以下行号指向本轮工作区，注明「改前」的行号来自开工时的文件快照。环境缺少 Xcode，结论基于 Build 69 的失败信息和源码。模拟器运行结果待云端复测。

## 1. `testCatalystEntitlementsIncludeKeyValueStore`

- **根因已确认。** Build 69 在测试机读到编译时的 `#filePath` `/Volumes/workspace/repository/TingyeTests/NativeCoreTests.swift`，运行目录为 `/`。改前 `TingyeTests/NativeCoreTests.swift:1279–1307` 依赖其中一个路径能找到源码检出目录，分机测试环境不具备这个前提。
- **修复与改动位置。** `Tingye.xcodeproj/project.pbxproj:22–23,112–113,292–293,453–454` 中，两个磁盘文件在开工时只有签名设置引用，因此补建 `PBXFileReference` 并加入 `Tingye` 文件组。两个独立的 `PBXBuildFile` 只进入 `TingyeTests` 的 Resources 阶段。`TingyeTests/NativeCoreTests.swift:1279–1288` 从 `Bundle(for:)` 定位并读取两份资源，缺失时报告完整文件名。第 1288 行的 kvstore 断言逐字保留。

## 2. `testSystemFilePickerSingleImportFromSourcesDeliversAndShowsResult`

- **已定位的测试依赖，云端具体表现不确定。** DEBUG fixture 写入 App 容器的 `Documents/听页导入回归.txt`（`Tingye/TingyeApp.swift:55–58,103–107`）。`Tingye/Info.plist:52–53,91–92` 已开启就地打开与文件共享。改前的系统选择器创建时没有 `directoryURL`（改前 `Tingye/ShelfView.swift:1276–1281`），测试依赖系统记住的位置，找不到才尝试「浏览 → 我的 iPhone → 听页」，并在首次查询时固定了是否查询系统文件进程（改前 `TingyeUITests/DesignFlowTests.swift:1041–1067`）。日志只证实文件查询失败，无法确认云端当时的起始位置、文件提供方状态或快照所在进程。此 fixture 的目标是本地文件提供方。 [Apple `directoryURL` 文档](https://developer.apple.com/documentation/uikit/uidocumentpickerviewcontroller/directoryurl)
- **修复与改动位置。** `Tingye/TingyeApp.swift:55–58,103–107` 让 fixture 写入使用同一个 DEBUG 目录入口，`Tingye/ShelfView.swift:1278–1281` 在相同 fixture 场景中将其设置为系统 picker 的起始目录。`TingyeUITests/DesignFlowTests.swift:1067–1099` 每次查询重新发现宿主和系统文件进程，优先找起始目录中的文件，保留经本地提供方进入 App 文件夹的路径，再点按真实文件。`Tingye/ShelfView.swift:1297–1298` 的系统 delegate 继续交付 URL，`TingyeUITests/DesignFlowTests.swift:1098–1104` 继续验证文件出现、逐项结果中的文件名和「已加入书库」。

## 3. `testOriginalReaderKeepsTypographyAndContentsReachable`

- **根因。** Build 69 失败在 `TingyeUITests/DesignFlowTests.swift:32` 的通用滚动检查，对应改前第 894 行加在「系统字体」断言前的 `reveal`。该次滚动未使 Readium 排版面板的目标通过 `isHittable` 检查。
- **修复与改动位置。** `TingyeUITests/DesignFlowTests.swift:920–921` 移除这一处 `reveal`，恢复直接检查「系统字体」的 `isSelected`。本用例与开工快照对照只有该行删除。

## 4. `testShelfOrganizeAndDetailsAreExplicit`

- **根因。** Build 69 点按时的快照没有 `book.detail.ui-long`。整理模式显示选择按钮，退出后再走普通详情入口，书目列表是懒加载的（`Tingye/ShelfView.swift:779–801,988–989,1146–1153`）。失败时具体滚动偏移量不确定。
- **修复与改动位置。** `TingyeUITests/DesignFlowTests.swift:479–481` 在取消整理后、点按详情前调用 `reveal`。此后唯一一次点按是等待出现并检查过可达性的详情页「打开」按钮（第 482–490 行）。

## 5. `testShelfSeparatesFilterSortAndLayoutAndProtectsDeletion`

- **根因与不确定项。** 根书房的「更多」在 `kindSelector` 内，筛选、排序、视图和整理在下一行（`Tingye/ShelfView.swift:120–121,435–445,514–531`）。滚到「更多」只能证明分类栏的这个控件可达。SE 的内容宽约 `375 − 2 × 24 = 327pt`，默认字号三个中文菜单约各 78pt，加 44pt 的整理入口和 24pt 间距，约 302pt。布局还有把数量单独放一行的分支。底部整理栏只在 `editing` 时出现（`Tingye/Theme.swift:68–75,91,1327–1335`，`Tingye/ShelfView.swift:150,515–525,589–598`）。现有证据指向测试滚动定位，并存在报告提到的 `Button` / `PopUpButton` 查询类型差异。失败日志没有打印循环中的 ID 或各控件 frame，无法确定当时先失败的是哪个按钮，也无法定量确认类型差异对该次失败的影响。 [Apple `XCUIElement.ElementType` 文档](https://developer.apple.com/documentation/xcuiautomation/xcuielement/elementtype?source=delasign)
- **修复与改动位置。** `TingyeUITests/DesignFlowTests.swift:718–734` 按标识查询，按页面顺序分别滚动到四个控件，仍逐个验证唯一、属于 `Button` 或 `PopUpButton`、且可命中。第 740–760 行用相同查询操作三个菜单，并在点击清除筛选、排序和视图前定位，保留筛选结果、菜单名称和筛选后唯一性的验证。第 769–771 行在退出整理后先把书行滚进视口，再执行原来的保留书籍断言。书架浏览布局沿用现有实现。

## 6. `testHomeSearchOpensExistingShelfSearch`

- **根因。** 原断言已等到结果存在，随后等待命中仍超时。搜索页把搜索头、结果统计和书目都放在同一纵向滚动视图内，使用 `.scrollDismissesKeyboard(.interactively)`（`Tingye/ShelfView.swift:102–144,645–685`）。SE 有键盘时需把书行滚进剩余视口。
- **修复与改动位置。** `TingyeUITests/DesignFlowTests.swift:407–422` 增加局部的单向滚动。检查结果前只在书架滚动视图内上滑，避免通用 `reveal` 第一阶段下拉带走键盘，随后直接用原文案断言 `isHittable`。截图后按需下拉找回「取消」。

## 7. `testPlayerCanScrubSentencesAndKeepPaused`

- **根因与高度估算。** 667pt 的 SE 在旧布局触发 `<700` 分支，状态所在的卡片排在 `hero`、句子进度、四项工具和「回到原文」之后（改前 `Tingye/PlayerView.swift:33–58`，对应原有滚动分支现位于第 36–59 行）。按常规字号估算，112pt 宽的封面高约 149pt，旧竖排 hero 共约 338–364pt（含一至两行书名）。进度约 66pt、工具至少 44pt、返回 50pt，加两处间距和上下边距共约 208pt。状态之前还有卡片与外层上边距 28pt，合计在滚动内容的约 574–600pt 处。固定播放行至少占 `78 + 16 = 94pt`，即使给满 667pt，滚动视口也至多 573pt。安全区会进一步减小可用高度。计算依据为 `Tingye/Theme.swift:68–77,91,846,1410–1417` 和 `Tingye/PlayerView.swift:40–54,123–134,176–238,364–365,396,432–441,558–563`。精确 frame 待模拟器确认。
- **修复与改动位置。** `Tingye/PlayerView.swift:5,34–66,137,176–237` 中，常规字号在 580–699pt 的可用高度使用 72pt 封面并把书名、章名移到旁边，沿用中间独立滚动正文、卡片顶部固定状态的布局。紧凑 hero 约 207pt，标准控制约 286pt。在 580pt 处仍给卡片留下约 87pt。辅助功能字号或可用高度低于 580pt 时继续采用整页滚动及固定播放控制，700pt 起使用原来的竖排，800pt 起封面仍为 144pt。`TingyeUITests/DesignFlowTests.swift:495–519` 的整个用例保持原样。

## 8. `testReaderNotesAndSearchOpenWithoutStartingAudio`

- **实际路径与不确定项。** 此用例启动 `reader`，使用 DEBUG 的 TXT 长标题样本（`TingyeUITests/DesignFlowTests.swift:679–682`，`Tingye/TingyeApp.swift:75–80,397–398`），走 `Tingye/Readium/ReaderRouter.swift:6–10,18–21` 的原生 `ReaderView`。摘记传入模式 `3`，`笔记 N` 一直是 `SegmentedBar` 的一个真按钮，但它位于 `List` 内的长标题 `EditorialIntro` 之后，导航栏下还留有搜索抽屉（`Tingye/ReaderView.swift:591–599,1847–1860,1921–1924`，`Tingye/Theme.swift:1096–1129,1344–1373,1447–1450`）。在原半高首屏上，长标题占用更多空间，可能使下一行未进入可见列表或未生成快照。初始选择原先在 `onAppear` 写入，首帧先走章节分支。页签栏始终由同一组固定选项构建。现有日志无法区分列表行尚未实例化与未暴露给无障碍快照。
- **修复与改动位置。** `Tingye/ReaderView.swift:591–600,1841–1858,1925–1930,1946–1948` 将直接打开摘记设为全高弹层，并从首帧按传入的 `initialMode` 得到选择。用户点按页签或输入搜索词时仍可改变选择。`TingyeUITests/DesignFlowTests.swift:300–313,679–701` 的页签存在、选中和非播放检查均保持原样。

## 9. `testPDFReaderKeepsReadingToolsAndNotesReachable`

- **实际路径与不确定项。** `reader-pdf` 生成有 PDF 数据的样本（`Tingye/TingyeApp.swift:79,140–150`），`Tingye/Readium/ReaderRouter.swift:8,20` 同样交给原生阅读器。Build 69 已通过页签存在和选中断言。空摘记的提示由 `NotesList` 在 `EditorialIntro` 和页签之后渲染，`EditorialNotice` 的文字与内边距会进一步增加行高（`Tingye/ReaderView.swift:1847–1860,1886–1887`，`Tingye/ReaderAnnotations.swift:348–352`，`Tingye/Theme.swift:1410–1417,1430–1440`）。原半高弹层下提示位于可见范围之外是与证据一致的解释。缺少失败时的列表和提示 frame，无法确认它当时是否已经出现在无障碍树中。
- **修复与改动位置。** PDF 走第 8 条的同一修复（`Tingye/ReaderView.swift:591–600,1841–1845`）。全高呈现给页签下方的提示留出空间。`TingyeUITests/DesignFlowTests.swift:300–313,970–983` 的「长按正文」命中断言和 PDF 工具断言保持原样。

## 自查

- `python3 scripts/verify-swift-sources.py` 退出码为 `0`，输出 `PASS 57 target Swift files; Tingye=49, TingyeTests=7, TingyeUITests=1`，另有 25 个独立 Design 工具排除在 Xcode Sources 之外。
- 用脚本的项目解析器另查 Target → Resources → BuildFile → FileReference。两份 entitlements 各进入 `TingyeTests` 一次，并用 `plistlib` 确认源文件中两个 kvstore 值都等于 `$(TeamIdentifierPrefix)$(CFBundleIdentifier)`。
- 以开工时保存在 `/tmp` 的文件快照核对改动位置、播放器与摘记用例、原书排版用例的单行回退，以及 kvstore 断言。未执行 Git 操作。以上自查涵盖文件和项目配置，Xcode 编译、资源复制产物和模拟器测试结果待验证。
