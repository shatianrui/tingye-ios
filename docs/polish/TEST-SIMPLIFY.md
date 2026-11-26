# 听页 UI 测试简化与 TTS 初始化加固交付报告

## 简化前后

| `TingyeUITests/DesignFlowTests.swift` | 基线 `a0925b3` | 当前工作树 | 净变化 |
| --- | ---: | ---: | ---: |
| 行数 | 1130 | 1131 | +1 |
| UI 测试方法 | 30 | 31 | +1 |

`testMarginProfileAndAppearanceRoutesRemainAvailable` 拆成 `testMarginProfileAndReadingStatsRemainAvailable` 和 `testMarginAppearanceKeepsReadingTypographyIndependent`，净增一条。文件选择器测试由 `testSystemFilePickerSingleImportFromSourcesDeliversAndShowsResult` 改名为 `testSystemFilePickerPresentsFromSources`，计数不变。新增的导入管线集成测试属于 `TingyeTests`。

预计整轮明显缩短，运行时间波动也会减小。省去的主要开销是文件 App 跨进程导航找文件、每次捕获布局时要求连续稳定 0.5 秒的轮询，以及书房搜索中为处理键盘遮挡反复上下滑动的循环。Margin 拆分增加一次独立启动，净耗时和抖动幅度待 Xcode Cloud 第四轮实测。本机无 Xcode，未本地运行任何测试。

## 逐条处置与覆盖去向

下表的 UI 测试行号均取自当前工作树的 `TingyeUITests/DesignFlowTests.swift`。

| 原工单 | 测试或调用点 | 处置与覆盖去向 |
| --- | --- | --- |
| 1 · 书房搜索 | `testHomeSearchOpensExistingShelfSearch`（410） | **简化。** 输入「长标题」后回车提交，`ShelfView.swift:659` 的 `onSubmit` 记录搜索并清除焦点以收起键盘。等待 `book.detail.ui-long` 出现且可点，保留原可点断言文案和截图，再点结果并等 `detail.reading` 出现。详情入口运用 `NavigationLink` 打开 `BookDetailView`，而 `detail.reading` 是本地书籍详情里的「打开」主操作，因此可确认确实进入详情（`Tingye/ShelfView.swift:823`、`Tingye/LibraryViews.swift:145`、`Tingye/LibraryViews.swift:152`）。**有意放弃**原「取消」后 `shelf.search` 再次可点的收尾断言，未找到专门接手的测试。本轮保留搜索到详情的核心流程，省去小屏上滚回取消按钮及重复验证入口的编排。 |
| 2 · 摘记与书内搜索 | `testReaderNotesAndSearchOpenWithoutStartingAudio`（683） | **保留摘记，简化搜索。** 原摘记打开、返回及未启动音频断言保留。输入「第二章」并看到结果计数后，通过 `revealInScrollView` 在 `waitForReadingCondition` 内只向结果列表 `app.collectionViews.firstMatch` 发元素级 `swipeUp`。目录的「完成」会关闭阅读器弹层（`Tingye/ReaderView.swift:1849`、`Tingye/ReaderView.swift:1936`），因此采用结果列表内滚动。点击后仍验证 `reader.notes` 出现、`reader.currentChapter == "2 / 2"`、`reader.toggle` 不存在，两处截图保留。 |
| 3 · 系统文件选择器 | `testSystemFilePickerPresentsFromSources`（1073），`testBatchCancelThenSingleAndResultsRetryUseOneRootPicker`（1109） | **改名、简化、下沉。** 单选 UI 只测 `sources.importFile` 能呈现选择器、能在宿主或已运行的文件进程找到并点「取消」、回到书库后重新打开添书面板时单选入口仍可点。截图改为选择器全屏截图。真实 TXT 的投递及落盘由下文的 `ImportPipelineTests` 接手。**保留**批量、单选和结果重选测试，它只通过 `cancelSystemBookPicker`（1044）完成呈现和取消循环，跨进程查询限于查找取消按钮，原来就无需在文件 App 内导航找文件。批量和重试的实际投递缺口见下文。 |
| 4 · 排版面板 | `testReaderToolsAndTypographyRemainAvailable`（429） | **简化。** 用含「让这一页更舒服」的排版面板滚动视图定位「系统字体」。新增的 `revealInScrollView`（35）在元素存在且可点时结束，只对传入的 scroll view 发最多 6 次元素级 `swipeUp`，全程无 `swipeDown` 或 app 级滑动。系统字体已选中和「完成」后 `reader.contents` 可达的断言保留。通用 `reveal()` 本体和其他测试对它的调用均保留原样。 |
| 5 · TTS 初始化 | `testMarginDarkPlayerAndReaderKeepControlsReachable`（1014） | **保留测试，延后 TTS 初始化。** 深色播放器和阅读器的可达性断言及截图保留。隔离的 DEBUG 暂停态改为直接准备状态。启动、标签、语音设置和实际发声的调用点见下文。 |
| 6 · 阅读布局捕获 | `captureReaderLayout`（177）；分页正文（446）、原书 EPUB（959）、PDF（995）的布局回归 | **简化捕获，保留行为断言。** 保留 `waitForReadingCondition` 的有界等待，捕获对象存在且视口宽大于 40、高大于 80 即采用。**有意放弃**每次捕获须连续稳定 0.5 秒的判定，翻页落地和工具显隐后的布局对比仍各自验证，详见下文。 |
| 7 · 多场景用例 | 原 `testMarginProfileAndAppearanceRoutesRemainAvailable` | **拆分。** `testMarginProfileAndReadingStatsRemainAvailable`（860）验证「我的」、阅读足迹和返回。独立启动的 `testMarginAppearanceKeepsReadingTypographyIndependent`（879）验证全局浅深外观切换、系统字体及独立纸色偏好。原有截图随对应流程保留。其余多段流程的处置见下文。 |

### 导入覆盖和缺口

- 新增的 `TingyeTests/ImportPipelineTests.swift:6` 已加入 `TingyeTests` 的 Sources。测试用临时 `LibraryDisk`、独立的 UserDefaults suite、内存存储和离线 `ProgressSync` 构造 `AppModel`，写出与 DEBUG fixture 内容相同的真实 UTF-8 TXT「听页导入回归.txt」。确认模型消费的是单选请求后，将原始 URL 传入 `completeFileImportSelection([url])`。模型管理安全作用域与协调副本（`Tingye/AppModel.swift:539`、`Tingye/AppModel.swift:574`、`Tingye/BookImporter.swift:10`）。测试最多轮询 10 秒等导入完成，验证有结果入口、报告已完成且文件名一致、条目状态为 `.imported`，再检查书目目录、书籍文件和从磁盘读回的正文内容。
- 原单选 UI 中的结果页文本断言由模型报告断言承接。结果入口、成功和失败文件名及可点的重试动作仍有 `testMixedImportUsesResultsInsteadOfSuccessAlert`（573）用混合导入 fixture 覆盖。系统文件提供方是否显示 fixture、真实单选后从系统进程回调并在结果页呈现该文件名和状态，有意放弃端到端断言，以移除依赖模拟器文件 App 路径和提供方状态的导航。
- **批量实际投递缺口。** 新集成测试只提交一个 URL。现有 `testFileImportWaitsForAllModalDismissalsAndConsumesOneMode` 验证批量请求排队、取消后恢复单选；`testDelegateBeginsVisibleImportAndCoordinatedMissingFileKeepsSuccess` 直接从 coordinator 投递两个 URL，验证一个成功、一个缺失以及成功正文落盘；`testPartialImportsHavePerFileResultsAndDoNotShowSuccessAlerts` 直接调用模型导入，验证好文件和坏文件的逐项报告（`TingyeTests/NativeCoreTests.swift:2670`、`TingyeTests/NativeCoreTests.swift:2724`、`TingyeTests/NativeCoreTests.swift:603`）。有意放弃「实际批量选择器选中多个文件后交付给根层，再生成逐项报告」的端到端验证。原批量 UI 用例也只走取消，现有下层断言已验证多 URL 处理，继续驱动真实选件会引回文件 App 导航的波动。
- **重试实际投递缺口。** UI 验证结果页的重选动作能打开根选择器并取消，现有 `testPartialImportsHavePerFileResultsAndDoNotShowSuccessAlerts` 验证随后再次直接调用导入可生成新的成功报告。新集成测试没有从一次失败报告触发重选并再次提交 URL，也未验证真实选择器回调、替换报告和修正文件最终落盘的连续路径。本轮有意保留重选入口的呈现/取消与下层再次导入覆盖，省去跨进程选件和对同一导入管线的重复验证。

### 仍保留的布局时序断言

- `testPagedReaderChromeDoesNotReflowOrMoveReadingPosition`（446）保留 `waitForReadingCondition`，向前时须取得有效捕获且正文不同，返回时须与起始页文字相同。向前的判断排除了空捕获误判为已翻页。
- `testPDFReaderChromeDoesNotResizeScaleOrMoveItsPage`（995）保留 `waitForReadingCondition`，向前时须读到不同的有效 PDF 页码，向后须读回起始页码，同时保留章节标签断言。
- `testOriginalReaderChromeDoesNotResizeOrMoveItsColumn`（959）保留 `advanceToTextPage`（191）对每次翻页落地和无正文块页的有界等待，以及返回首章的等待。三个布局用例仍在相应工具栏可见性达到预期后，比较当前捕获和基准。分页正文和 PDF 由 `assertReaderChromePreservesLayout`（285）检查文字、PDF 页码/缩放/页内位置及视口，EPUB 直接比较文字与正文栏几何。

### 其余三段及以上流程

按进入不同页面、弹层或执行独立功能段计，重复翻页、重复切换同一控件以及同一页面上的可达性检查合并计为同一段。以下保留原流程。

| 测试 | 涉及流程及保留理由 |
| --- | --- |
| `testEPUBDerivedFixtureSmokeAndSearch`（358） | EPUB 正文、目录/搜索、排版、返回书房。保留派生原书样本的端到端冒烟。 |
| `testShelfOrganizeAndDetailsAreExplicit`（473） | 书架整理、书籍详情、打开正文。保留从整理退出后进入详情和从详情续读的链路。 |
| `testReaderToolsAndTypographyRemainAvailable`（429）、`testReaderNotesAndSearchOpenWithoutStartingAudio`（683） | 分别串接正文工具、排版与目录，以及正文、摘记与书内搜索。第 4 项和第 2 项已缩短各自的定位步骤，保留同次会话的终局断言。 |
| `testReaderKeepsActionSlotsAndChapterNavigationDoesNotSeekAudio`（585） | 正文及辅助听书、展开播放器、回书房再续读。保留阅读与听书进度互不覆盖的同会话验证。 |
| `testShelfSeparatesFilterSortAndLayoutAndProtectsDeletion`（719） | 筛选、排序、视图切换、整理与取消删除。保留书架上各功能的独立入口及交互后的书目状态。 |
| `testPlayerToolsAreDirectAndPreservePausedState`（777）、`testMiniPlayerOnlyExpandsAndTogglesAndEndNeedsConfirmation`（811） | 前者串接播放器、声音与音频输出、定时，保留暂停态跨工具验证。后者串接完整播放器、迷你播放器、结束确认和回书库，保留取消与确认的状态差异。 |
| `testOriginalReaderKeepsTypographyAndContentsReachable`（921） | 正文、排版、目录跳章、返回书房。保留排版偏好跨章生效的验证。 |
| `testBatchCancelThenSingleAndResultsRetryUseOneRootPicker`（1109） | 批量、单选、结果重选三次呈现/取消。第 3 项保留单一根选择器及模态交接验证。 |

## TTS 调用点排查

| 当前工作树位置 | 延后情况 |
| --- | --- |
| `Tingye/AppModel.swift:76`、`Tingye/SpeechPlayer.swift:355`、`Tingye/SpeechPlayer.swift:423` | **已延后合成器创建。** 模型仍构造 `SpeechPlayer`；`synth` 初始为空，初始化函数注册媒体命令和音频通知，未创建合成器或设 delegate。 |
| `Tingye/SpeechPlayer.swift:591`、`Tingye/SpeechPlayer.swift:608`、`Tingye/SpeechPlayer.swift:613`、`Tingye/SpeechPlayer.swift:845`、`Tingye/SpeechPlayer.swift:853`、`Tingye/SpeechPlayer.swift:861` | **延后至首次实际系统朗读。** `playSentence()` 的系统分支才经 `systemSynthesizer()` 创建并保留合成器、设置 delegate。实际生成 utterance 时仍构造 `AVSpeechSynthesisVoice`；后续预排复用已存在的合成器。 |
| `Tingye/SpeechPlayer.swift:478`、`Tingye/SpeechPlayer.swift:485`、`Tingye/SpeechPlayer.swift:515`、`Tingye/SpeechPlayer.swift:525`、`Tingye/SpeechPlayer.swift:544`、`Tingye/PlayerView.swift:1256` | **未新增提前初始化路径。** 暂停、停止、跳转和刷新设置仅操作已有合成器。继续朗读可走发声路径；应用设置时仅在原来已播放的情况下重开该路径。 |
| `Tingye/PlayerView.swift:208`、`Tingye/PlayerView.swift:414`、`Tingye/StatsView.swift:635`、`Tingye/SpeechPlayer.swift:393` | **已移除标签渲染时的同步音色构造。** 播放器显示、无障碍标签和个人设置项经 `voiceLabel` 查名称。 |
| `Tingye/PlayerView.swift:738`、`Tingye/PlayerView.swift:940`、`Tingye/PlayerView.swift:1010`、`Tingye/PlayerView.swift:1114`、`Tingye/SpeechPlayer.swift:970` | **已移除设置标签的同步音色构造。** `currentVoiceName` 和 `voiceLabel` 均优先查内存缓存，再查 `UserDefaults` 的 `voice.label.system.<identifier>`。暂无已知名称时显示「系统声音」，未选择音色时显示「默认中文声音」。 |
| `Tingye/PlayerView.swift:103`、`Tingye/ReaderView.swift:589`、`Tingye/LibraryViews.swift:523`、`Tingye/PlayerView.swift:696`、`Tingye/PlayerView.swift:699`、`Tingye/PlayerView.swift:801` | **已延后枚举并消除跨隔离构造风险。** `VoiceSettingsView` 保持普通 `View` 隔离（不额外加显式 `@MainActor`），`@State` 属性初始为空，不再在属性初始化期读取 `@MainActor` 的 `SpeechVoiceCache.cached`，改为 `.onAppear` 同步已有缓存；原根视图枚举 `.task` 已移除。从播放器、阅读器或 `settingsDestinationView` 进入时不触发语音枚举。 |
| `Tingye/PlayerView.swift:737`、`Tingye/PlayerView.swift:750`、`Tingye/PlayerView.swift:858`、`Tingye/PlayerView.swift:1200` | **已延后至详情出现。** 「选择音色」「分角色配音」详情页分别用 `.task` 调用加载，云语音页用 `.task(id: provider)`，只在当前提供方为 `system` 时实际请求系统音色；缓存已命中时直接复用，不闪烁加载态。 |
| `Tingye/SpeechPlayer.swift:959`、`Tingye/SpeechPlayer.swift:967`、`Tingye/SpeechPlayer.swift:968`、`Tingye/SpeechPlayer.swift:981`、`Tingye/SpeechPlayer.swift:986` | **唯一的系统音色枚举已改为异步单飞。** `@MainActor` 维护缓存和共享的 `inFlight` Task，`Task.detached` 在后台调用 `speechVoices()`，过滤中英文并排序，只回传含标识、名称和语言的 `Sendable` 值。空列表不写缓存并清除在途任务，可在下次进入详情时重试。 |
| `Tingye/SpeechPlayer.swift:610`、`Tingye/PlayerView.swift:1214`、`Tingye/PlayerView.swift:1246` | **名称写入发生在已有数据时。** 实际系统朗读取得匹配语音、详情加载找到已选语音，或保存时能匹配选择的语音，分别使用已有名称写入 `UserDefaults`。 |
| `Tingye/PlayerView.swift:717`、`Tingye/PlayerView.swift:1158`、`Tingye/PlayerView.swift:1163`、`Tingye/PlayerView.swift:1179`、`Tingye/PlayerView.swift:1181` | **已延后至首次系统试听。** `VoiceSettingsView.systemPreview` 初始为空，`testVoice()` 的系统语音分支才构造音色和合成器。停止试听及离开页面只停止已有实例。云试听使用自己的音频播放器。 |
| `Tingye/TingyeApp.swift:344`、`Tingye/TingyeApp.swift:358`、`Tingye/TingyeApp.swift:400`、`Tingye/TingyeApp.swift:408`、`Tingye/SpeechPlayer.swift:460` | **隔离 DEBUG 暂停态已改走专用路径。** `now-listening` 和隔离的 `player*` 经 `preparePausedReviewPlayer` 调用 `preparePausedForUIReview`，准备书籍、位置、进度和 Now Playing 状态，跳过旧的 `startListening()` 后立刻 `pause()` 的朗读路径。该分支在 `#if DEBUG` 内，发布版本的场景行为沿用原流程。 |
| `Tingye/TingyeApp.swift:389`、`Tingye/TingyeApp.swift:398`、`Tingye/TingyeApp.swift:403`、`Tingye/AppModel.swift:589` | **未延后主动开播场景。** DEBUG 的朗读阅读器、`miniplayer` 和非隔离的播放器场景仍调用 `startListening`，普通用户主动开播也仍走该入口；这些路径会开始实际朗读。 |
| `TingyeTests/NativeCoreTests.swift:1605`、`TingyeTests/ImportPipelineTests.swift:14` | **测试复用。** `MemoryKeyValueStore` 从 `private` 调整为测试 target 内的默认 `internal`，供集成测试注入离线 `ProgressSync`。 |

## Swift 源文件注册检查

在仓库根目录重新运行 `python3 scripts/verify-swift-sources.py`，命令退出码为 0。完整原始输出如下。

```text
PASS Tingye: Tingye/AppModel.swift
PASS Tingye: Tingye/BookFinishView.swift
PASS Tingye: Tingye/BookImporter.swift
PASS Tingye: Tingye/ComicArchive.swift
PASS Tingye: Tingye/ComicReaderView.swift
PASS Tingye: Tingye/DailyQuoteCard.swift
PASS Tingye: Tingye/DialogueRoles.swift
PASS Tingye: Tingye/FocusSession.swift
PASS Tingye: Tingye/GeneralSettingsView.swift
PASS Tingye: Tingye/ICloudBackup.swift
PASS Tingye: Tingye/Library.swift
PASS Tingye: Tingye/LibraryViews.swift
PASS Tingye: Tingye/MenuSettingsView.swift
PASS Tingye: Tingye/MobiReader.swift
PASS Tingye: Tingye/Models.swift
PASS Tingye: Tingye/NotesUnifiedView.swift
PASS Tingye: Tingye/OriginalBookView.swift
PASS Tingye: Tingye/PlayerView.swift
PASS Tingye: Tingye/ReaderAnnotations.swift
PASS Tingye: Tingye/ReaderView.swift
PASS Tingye: Tingye/ReadingCalendarView.swift
PASS Tingye: Tingye/Readium/EPUBDisplayTransform.swift
PASS Tingye: Tingye/Readium/EPUBNavigatorHost.swift
PASS Tingye: Tingye/Readium/EPUBTextSnapshotBuilder.swift
PASS Tingye: Tingye/Readium/LegacyEPUBBuilder.swift
PASS Tingye: Tingye/Readium/LocatorBridge.swift
PASS Tingye: Tingye/Readium/LocatorMigration.swift
PASS Tingye: Tingye/Readium/PublicationMap.swift
PASS Tingye: Tingye/Readium/PublicationStore.swift
PASS Tingye: Tingye/Readium/ReaderRouter.swift
PASS Tingye: Tingye/Readium/ReadiumAnnotations.swift
PASS Tingye: Tingye/Readium/ReadiumFontProvider.swift
PASS Tingye: Tingye/Readium/ReadiumPreferencesBridge.swift
PASS Tingye: Tingye/Readium/ReadiumReaderView.swift
PASS Tingye: Tingye/Readium/ReadiumService.swift
PASS Tingye: Tingye/Readium/ReadiumSpeechBridge.swift
PASS Tingye: Tingye/Readium/StoredLocator.swift
PASS Tingye: Tingye/Readium/TextDOMIndex.swift
PASS Tingye: Tingye/SMBBrowser.swift
PASS Tingye: Tingye/Services.swift
PASS Tingye: Tingye/ShelfView.swift
PASS Tingye: Tingye/Sources.swift
PASS Tingye: Tingye/SpeechPlayer.swift
PASS Tingye: Tingye/StatsView.swift
PASS Tingye: Tingye/StorageView.swift
PASS Tingye: Tingye/Theme.swift
PASS Tingye: Tingye/TingyeApp.swift
PASS Tingye: Tingye/TxtRulesView.swift
PASS Tingye: Tingye/Typography.swift
PASS TingyeTests: TingyeTests/ImportPipelineTests.swift
PASS TingyeTests: TingyeTests/LocatorMigrationTests.swift
PASS TingyeTests: TingyeTests/NativeCoreTests.swift
PASS TingyeTests: TingyeTests/ReadiumBackupSourceTests.swift
PASS TingyeTests: TingyeTests/ReadiumLocatorTests.swift
PASS TingyeTests: TingyeTests/ReadiumPreferencesTests.swift
PASS TingyeTests: TingyeTests/ReadiumPublicationTests.swift
PASS TingyeTests: TingyeTests/ReadiumTextSnapshotTests.swift
PASS TingyeUITests: TingyeUITests/DesignFlowTests.swift
PASS 58 target Swift files; Tingye=49, TingyeTests=8, TingyeUITests=1
TOOL (no Xcode target): Design/icon-little-prince/validate-icons.swift
TOOL (no Xcode target): Design/icon-margin-gpt/make-preview.swift
TOOL (no Xcode target): Design/icon-margin-gpt/prepare-variants.swift
TOOL (no Xcode target): Design/render-app-icon-v10.swift
TOOL (no Xcode target): Design/render-app-icon-v11.swift
TOOL (no Xcode target): Design/render-app-icon-v12.swift
TOOL (no Xcode target): Design/render-app-icon-v13.swift
TOOL (no Xcode target): Design/render-app-icon-v14.swift
TOOL (no Xcode target): Design/render-app-icon-v15-concepts.swift
TOOL (no Xcode target): Design/render-app-icon-v16.swift
TOOL (no Xcode target): Design/render-app-icon-v18.swift
TOOL (no Xcode target): Design/render-app-icon-v2.swift
TOOL (no Xcode target): Design/render-app-icon-v3.swift
TOOL (no Xcode target): Design/render-app-icon-v4.swift
TOOL (no Xcode target): Design/render-app-icon-v5.swift
TOOL (no Xcode target): Design/render-app-icon-v7.swift
TOOL (no Xcode target): Design/render-app-icon-v8.swift
TOOL (no Xcode target): Design/render-app-icon-v9.swift
TOOL (no Xcode target): Design/render-app-icon.swift
TOOL (no Xcode target): Design/v19-margin/contact-sheet.swift
TOOL (no Xcode target): Design/v19-margin/prepare-icons.swift
TOOL (no Xcode target): Design/v21-swiss/icon/render-app-icon-v21.swift
TOOL (no Xcode target): Design/v23-time/icon/render-app-icon-v23.swift
TOOL (no Xcode target): Design/v25-moqing/render-app-icon-v25.swift
TOOL (no Xcode target): Design/v26-wereader/render-app-icon-v26.swift
INFO 25 standalone Design tools excluded from app/test Sources
```

## 未决问题与不确定项

- **未本地运行，待 Xcode Cloud 验证。** 本机为 Linux，无 Xcode，未本地编译 App 或执行任何测试。UI 和集成测试、首次系统朗读/试听、Apple TextToSpeech 崩溃是否复现，以及耗时变化，全部待 Xcode Cloud 第四轮验证。系统返回空音色列表时可重试，但 Apple 框架内部的进程级断言能否复现仍需实机或模拟器结果。
- **已修正的编译风险（仍待云端编译实证）。** 此前版本为 `VoiceSettingsView` 显式添加 `@MainActor` 并在 `@State` 默认值中读取主 actor 隔离的 `SpeechVoiceCache.cached`，与非隔离自由函数 `settingsDestinationView`（`Tingye/LibraryViews.swift:518`、`Tingye/LibraryViews.swift:523`）存在跨隔离初始化编译风险。收尾复核已移除 `VoiceSettingsView` 的显式 `@MainActor`、改为 `@State` 空初值并在 `.onAppear` / `loadSystemVoices()` 中同步缓存，使其恢复与其他设置子页一致的 `View` 隔离口径；最终编译结果待 Xcode Cloud 确认。
- 小屏仍需验证书内搜索结果列表确实是 `app.collectionViews.firstMatch`，以及取消单选后书架滚动能在 6 次内露出添书入口。布局测试现取工具可见性达到预期后的首个有效快照，过渡帧是否影响比较也待云端确认。
- 集成测试源码已通过现成的 `AppModel(disk:progressSync:)` 构造真实模型，测试目标已有相同注入方式（`TingyeTests/ImportPipelineTests.swift:9`、`TingyeTests/ImportPipelineTests.swift:15`、`TingyeTests/NativeCoreTests.swift:623`），静态复核未发现构造障碍。当前注册脚本只检查工程挂载，构造和导入的实际运行结果待云端确认。
- 上一轮会话在 2026-11-27 01:07 CST 虚拟机重启时中断；收尾复核已基于当前工作树全量 `git diff` 逐项核对、修正上述 `VoiceSettingsView` 隔离风险并同步更新本报告。
