import XCTest

/// 使用 DEBUG 临时书库；不依赖现有阅读记录，不调用付费语音或 iCloud。
@MainActor
final class DesignFlowTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func launch(_ scene: String, largeType: Bool = false, appearance: String = "light", original: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-fixture", "-ui-reset-preferences", "-uireview", scene, "-ui-reduce-motion", "-ui-appearance", appearance, "-privacy.appLock", "NO", "-reader.font", "system", "-reader.original", original ? "YES" : "NO", "-reader.scrolling", "NO", "-shelf.kind", "books", "-voice.rate", "1.0", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        if largeType { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        return app
    }
    private func screenshot(_ app: XCUIApplication, _ name: String, wholeScreen: Bool = false) {
        let attachment = XCTAttachment(screenshot: wholeScreen ? XCUIScreen.main.screenshot() : app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<10 {
            if element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
    }

    private func revealAboveDone(_ element: XCUIElement, in app: XCUIApplication) {
        let done = app.buttons["完成"]
        // XCUITest can report a control underneath a safe-area inset as hittable.
        // Scroll the whole target above the fixed footer before tapping it.
        for _ in 0..<8 {
            if element.exists && element.isHittable && element.frame.maxY < done.frame.minY { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
        XCTAssertLessThan(element.frame.maxY, done.frame.minY)
    }

    private func originalText(_ text: String, in web: XCUIElement) -> XCUIElement {
        web.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func originalElementIsVisible(_ element: XCUIElement, in web: XCUIElement, app: XCUIApplication) -> Bool {
        guard element.exists, element.isHittable else { return false }
        let visible = element.frame.intersection(web.frame).intersection(app.frame)
        return !visible.isNull && visible.width > 1 && visible.height > 1
    }

    private func waitForOriginalElement(_ element: XCUIElement, in web: XCUIElement, app: XCUIApplication,
                                        message: String, minimumSize: CGFloat = 1,
                                        file: StaticString = #filePath, line: UInt = #line) {
        let rendered = NSPredicate { _, _ in
            self.originalElementIsVisible(element, in: web, app: app)
                && element.frame.width > minimumSize && element.frame.height > minimumSize
        }
        let expectation = XCTNSPredicateExpectation(predicate: rendered, object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 15), .completed, message, file: file, line: line)
    }

    private func waitForOriginalChapter(_ title: String, in web: XCUIElement, app: XCUIApplication,
                                        file: StaticString = #filePath, line: UInt = #line) {
        // 只查询网页后代，不能让原生顶栏同名标题或空的 WebView 使验收通过。
        waitForOriginalElement(originalText(title, in: web), in: web, app: app,
                               message: "原书网页章节标题应已完成布局并可见：\(title)", file: file, line: line)
        waitForOriginalElement(originalText("把日子放慢一点", in: web), in: web, app: app,
                               message: "原书网页应显示实际正文，不能只出现空白渲染器", file: file, line: line)
    }

    private func verifyOriginalIllustration(in web: XCUIElement, app: XCUIApplication,
                                            file: StaticString = #filePath, line: UInt = #line) {
        let caption = originalText("午后，山色与树影。", in: web)
        XCTAssertTrue(caption.waitForExistence(timeout: 15), "图注必须来自首章的原书 HTML", file: file, line: line)
        // 小屏可能将整张插图排到下一栏；验证它可达后回到首屏继续排版与目录测试。
        var pageTurns = 0
        for _ in 0..<3 {
            if originalElementIsVisible(caption, in: web, app: app) { break }
            web.swipeLeft()
            pageTurns += 1
        }
        waitForOriginalElement(caption, in: web, app: app, message: "原书插图的图注应可见", file: file, line: line)
        let illustration = web.images.firstMatch
        if illustration.waitForExistence(timeout: 2) {
            waitForOriginalElement(illustration, in: web, app: app, message: "可访问性树中的原书插图应已加载并可见",
                                   minimumSize: 40, file: file, line: line)
        }
        if pageTurns > 0 {
            screenshot(app, "原书图文-插图与图注")
            for _ in 0..<pageTurns { web.swipeRight() }
            waitForOriginalChapter("第一章 · 纸上的风景", in: web, app: app, file: file, line: line)
        }
    }

    private struct ReaderLayoutCapture: Equatable {
        let viewport: CGRect
        var text: [String] = []
        var frames: [CGRect] = []
        var pdf: NSDictionary = [:]
    }

    private func nativeLayout(in app: XCUIApplication) -> ReaderLayoutCapture? {
        let pages = app.staticTexts.matching(identifier: "reader.nativePage").allElementsBoundByIndex
        guard !pages.isEmpty, pages.allSatisfy({ !$0.label.isEmpty && $0.frame.height > 80 }) else { return nil }
        return .init(viewport: pages.reduce(CGRect.null) { $0.union($1.frame) },
                     text: pages.map(\.label), frames: pages.map(\.frame))
    }

    private func pdfLayout(in app: XCUIApplication) -> ReaderLayoutCapture? {
        let pdf = app.descendants(matching: .any).matching(identifier: "reader.pdf").firstMatch
        guard pdf.exists, let value = pdf.value as? String, let data = value.data(using: .utf8),
              let state = try? JSONSerialization.jsonObject(with: data) as? NSDictionary,
              ["page", "scale", "pageX", "pageY", "pageWidth", "pageHeight"].allSatisfy({ state[$0] != nil }),
              (state["scale"] as? NSNumber)?.doubleValue ?? 0 > 0 else { return nil }
        return .init(viewport: pdf.frame, pdf: state)
    }

    private func waitForReadingCondition(_ condition: @escaping () -> Bool, _ message: String,
                                         file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate { _, _ in condition() }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)], timeout: 15),
                       .completed, message, file: file, line: line)
    }

    private func captureReaderLayout(_ capture: @escaping () -> ReaderLayoutCapture?,
                                     file: StaticString = #filePath, line: UInt = #line) throws -> ReaderLayoutCapture {
        var last: ReaderLayoutCapture?
        var stableSince = Date()
        waitForReadingCondition({
            guard let next = capture(), next.viewport.width > 40, next.viewport.height > 80 else { return false }
            if next == last { return Date().timeIntervalSince(stableSince) >= 0.5 }
            last = next; stableSince = Date(); return false
        }, "真实正文布局应连续稳定", file: file, line: line)
        return try XCTUnwrap(last, file: file, line: line)
    }

    private func tapReadingCenter(in app: XCUIApplication, frame: CGRect) {
        // 双页时第一张纸页的中央属于上一页区；使用整个窗口的中央 x。
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: app.frame.width / 2, dy: frame.midY - app.frame.minY)).tap()
    }

    private func setReadingTools(_ visible: Bool, in app: XCUIApplication, frame: CGRect) {
        let more = app.buttons["reader.more"]
        if more.exists != visible { tapReadingCenter(in: app, frame: frame) }
        if visible { XCTAssertTrue(more.waitForExistence(timeout: 5)); XCTAssertTrue(more.isHittable) }
        else { XCTAssertTrue(more.waitForNonExistence(timeout: 5)) }
    }

    private func assertReaderChromePreservesLayout(in app: XCUIApplication, baseline: ReaderLayoutCapture,
                                                  capture: @escaping () -> ReaderLayoutCapture?, name: String,
                                                  file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertTrue(app.buttons["reader.more"].isHittable, file: file, line: line)
        for (index, visible) in [false, true, false, true].enumerated() {
            setReadingTools(visible, in: app, frame: baseline.viewport)
            let current = try captureReaderLayout(capture, file: file, line: line)
            XCTAssertEqual(current.viewport, baseline.viewport, "工具显隐不能移动或收缩实际正文视口", file: file, line: line)
            XCTAssertEqual(current.text, baseline.text, "实际页文字应保持，不能仅让章节编号不变", file: file, line: line)
            XCTAssertEqual(current.frames, baseline.frames, "实际正文元素不能重排或平移", file: file, line: line)
            XCTAssertEqual(current.pdf, baseline.pdf, "工具显隐不能改变 PDF 页码、缩放或页内位置", file: file, line: line)
            if index == 0 || index == 3 { screenshot(app, "\(name)-\(visible ? "显示工具" : "隐藏工具")") }
        }
        XCTAssertFalse(app.buttons["reader.toggle"].exists, "工具显隐不应启动辅助听书", file: file, line: line)
    }

    private func cancelConfirmation(in app: XCUIApplication) {
        // iOS / iPadOS 的 popover 形式会省略取消按钮，轻点外部即取消。
        if app.buttons["取消"].exists { app.buttons["取消"].tap() }
        else {
            let outside = app.otherElements["PopoverDismissRegion"]
            XCTAssertTrue(outside.exists)
            // 不点状态栏：状态栏触摸不会关闭 popover。
            outside.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.25)).tap()
            XCTAssertTrue(outside.waitForNonExistence(timeout: 5))
        }
    }

    private func openReaderNotesAndReturn(in app: XCUIApplication) {
        let notes = app.buttons["reader.notes"]
        XCTAssertTrue(notes.waitForExistence(timeout: 5))
        notes.tap()
        XCTAssertTrue(app.navigationBars["目录与摘记"].waitForExistence(timeout: 5))
        let notesTab = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "笔记 ")).firstMatch
        XCTAssertTrue(notesTab.waitForExistence(timeout: 5))
        XCTAssertTrue(notesTab.isSelected, "摘记入口应直接打开笔记，而非让读者再切换章节页签")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "长按正文")).firstMatch.isHittable)
        XCTAssertFalse(app.buttons["player.toggle"].exists)
        app.buttons["完成"].tap()
        XCTAssertTrue(app.buttons["reader.more"].waitForExistence(timeout: 5))
    }

    func testHomeShowsContinueAndRecentWithoutScrolling() {
        let app = launch("now")
        let read = app.buttons["continue.reading"]
        XCTAssertTrue(read.waitForExistence(timeout: 15))
        XCTAssertTrue(read.isHittable)
        let listen = app.buttons["now.listen"]
        XCTAssertTrue(listen.isHittable)
        XCTAssertTrue(read.label.contains("继续阅读"))
        XCTAssertGreaterThan(read.frame.width, listen.frame.width, "继续阅读应为明确的主操作，听书保留为辅助入口")
        XCTAssertLessThan(read.frame.maxY, listen.frame.maxY)
        XCTAssertGreaterThanOrEqual(read.frame.height, 44)
        XCTAssertGreaterThanOrEqual(listen.frame.height, 44)
        XCTAssertTrue(app.staticTexts["最近在读"].firstMatch.isHittable)
        screenshot(app, "今日-首屏续读与最近在读")
    }

    func testRecentReadingStaysPrimaryWhileAnotherBookHasListeningProgress() {
        let app = launch("now-listening")
        let reading = app.buttons["continue.reading"]
        XCTAssertTrue(reading.waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["miniPlayer.toggle"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["miniPlayer.toggle"].label.contains("继续"))
        XCTAssertTrue(reading.label.contains("一本用来检查长标题和阅读体验的书"))
        XCTAssertTrue(app.staticTexts["now.readingProgress"].label.contains("第 2"), "首页进度属于最近阅读，不属于刚听过的另一本书")
        XCTAssertGreaterThan(reading.frame.width, app.buttons["now.listen"].frame.width)
        screenshot(app, "阅读优先-最近阅读与独立听书条")
        reading.tap()
        XCTAssertTrue(app.buttons["reader.contents"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["reader.currentChapter"].label, "2 / 2")
        XCTAssertFalse(app.buttons["player.toggle"].exists, "继续阅读不能把用户送入播放器")
    }

    func testHomeSearchOpensExistingShelfSearch() {
        let app = launch("now")
        let search = app.buttons["now.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 15))
        search.tap()
        let field = app.textFields["shelf.search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap(); field.typeText("长标题")
        XCTAssertTrue(app.buttons["book.detail.ui-long"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["book.detail.ui-long"].isHittable, "小屏键盘上方应能直接操作搜索结果")
        screenshot(app, "专注-从首页搜索书架")
        app.buttons["取消"].tap()
        XCTAssertTrue(app.buttons["shelf.search"].isHittable)
    }

    func testReaderToolsAndTypographyRemainAvailable() {
        let app = launch("reader")
        let preferences = app.buttons["reader.preferences"]
        XCTAssertTrue(preferences.waitForExistence(timeout: 15))
        screenshot(app, "专注-阅读工具栏")
        preferences.tap()
        XCTAssertTrue(app.navigationBars["阅读排版"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["系统字体"].isSelected)
        app.buttons["完成"].tap()
        XCTAssertTrue(app.buttons["reader.contents"].waitForExistence(timeout: 5))
        app.buttons["reader.contents"].tap()
        XCTAssertTrue(app.navigationBars["目录与摘记"].waitForExistence(timeout: 5))
    }

    func testPagedReaderChromeDoesNotReflowOrMoveReadingPosition() throws {
        let app = launch("reader")
        XCTAssertTrue(app.buttons["reader.more"].waitForExistence(timeout: 15))
        let capture = { self.nativeLayout(in: app) }
        let first = try captureReaderLayout(capture)
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: first.viewport.maxX - 12, dy: first.viewport.midY)).tap()
        waitForReadingCondition({ capture()?.text != first.text }, "必须实际翻到另一页正文")
        let reading = try captureReaderLayout(capture)
        XCTAssertEqual(app.staticTexts["reader.currentChapter"].label, "1 / 2", "应在章内非首页验证分页稳定")
        try assertReaderChromePreservesLayout(in: app, baseline: reading, capture: capture, name: "固定正文-分页")
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: reading.viewport.minX + 12, dy: reading.viewport.midY)).tap()
        waitForReadingCondition({ capture()?.text == first.text }, "工具开关后上一页应回到原来那一页文字")
    }

    func testDarkHomeAndShelfKeepPrimaryActionsReachable() {
        let app = launch("now", appearance: "dark")
        XCTAssertTrue(app.buttons["continue.reading"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["now.listen"].isHittable)
        screenshot(app, "专注-夜间首页")
        app.buttons["navigation.tab.0"].tap()
        XCTAssertTrue(app.buttons["shelf.organize"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["book.detail.ui-long"].isHittable)
        screenshot(app, "专注-夜间书架")
    }

    func testShelfOrganizeAndDetailsAreExplicit() {
        let app = launch("shelf")
        let organize = app.buttons["shelf.organize"]
        XCTAssertTrue(organize.waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["book.detail.ui-long"].isHittable)
        screenshot(app, "书架-文字整理与详情入口")
        organize.tap()
        XCTAssertTrue(app.buttons["取消整理"].waitForExistence(timeout: 5))
        app.buttons["取消整理"].tap()
        app.buttons["book.detail.ui-long"].tap()
        let reading = app.buttons["detail.reading"]
        XCTAssertTrue(reading.waitForExistence(timeout: 5))
        XCTAssertTrue(reading.label.contains("继续阅读"))
        XCTAssertTrue(app.buttons["detail.listen"].isHittable)
        XCTAssertLessThan(reading.frame.minY, app.buttons["detail.listen"].frame.minY)
        XCTAssertGreaterThanOrEqual(reading.frame.height, 44)
    }

    func testPlayerCanScrubSentencesAndKeepPaused() {
        let app = launch("player")
        // 句子进度是自定义刻度轨（非系统 Slider），用与真实手指相同的坐标拖动手势验证。
        let scrubber = app.descendants(matching: .any)["player.sentence-progress"]
        XCTAssertTrue(scrubber.waitForExistence(timeout: 15))
        let toggle = app.buttons["player.toggle"]
        XCTAssertTrue(toggle.label.contains("继续朗读"))
        XCTAssertTrue(app.staticTexts["player.readingStatus"].isHittable, "跟读状态应固定在卡片顶部，不随长句滚出视口")
        let original = scrubber.value as? String
        scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5))
            .press(forDuration: 0.2, thenDragTo: scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.5)))
        XCTAssertTrue(waitForValueChange(of: scrubber, from: original), "拖动后句子标签应离开 \(original ?? "nil")")
        let scrubbed = scrubber.value as? String
        XCTAssertTrue(scrubbed?.contains("句") == true)
        XCTAssertTrue(toggle.label.contains("继续朗读"), "拖动不能擅自恢复已暂停的朗读")
        app.buttons["player.nextSentence"].tap()
        XCTAssertTrue(waitForValueChange(of: scrubber, from: scrubbed))
        toggle.tap()
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertTrue(toggle.label.contains("暂停朗读"))
        toggle.tap()
        XCTAssertTrue(toggle.label.contains("继续朗读"))
        XCTAssertTrue(app.staticTexts["player.readingStatus"].isHittable)
        screenshot(app, "播放器-句子拖动与暂停")
    }

    /// 等无障碍值真正刷新，避免手势完成后立刻读取到旧快照。
    private func waitForValueChange(of element: XCUIElement, from old: String?, timeout: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if (element.value as? String) != old { return true }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return (element.value as? String) != old
    }

    func testLargestTypePlayerControlsRemainReachable() {
        let app = launch("player", largeType: true)
        let toggle = app.buttons["player.toggle"]
        XCTAssertTrue(app.buttons["player.more"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["player.cover"].exists, "必须实际进入辅助功能字号布局，而不是仅传了测试参数")
        screenshot(app, "播放器-最大字号长书名")
        XCTAssertTrue(toggle.isHittable, "最大字号下播放控制也应固定可见")
        XCTAssertEqual(toggle.frame.midX, app.frame.midX, accuracy: 2, "跳句文字放大后不能把播放键挤偏")
        screenshot(app, "播放器-最大字号播放控制")
        reveal(app.buttons["player.contents"], in: app)
        app.buttons["player.contents"].tap()
        XCTAssertTrue(app.navigationBars["听书目录"].waitForExistence(timeout: 5))
    }

    func testLargestTypeHomeAndShelfActionsRemainReachable() {
        let app = launch("now", largeType: true)
        let read = app.buttons["continue.reading"]
        XCTAssertTrue(read.waitForExistence(timeout: 15))
        reveal(read, in: app)
        screenshot(app, "今日-最大字号")
        let tabs = [(1, "此刻"), (0, "书库"), (2, "我的")]
        for (tag, label) in tabs {
            let tab = app.buttons["navigation.tab.\(tag)"]
            XCTAssertEqual(tab.label, label)
            XCTAssertTrue(tab.isHittable)
        }
        let tabPositions = tabs.map { app.buttons["navigation.tab.\($0.0)"].frame.midX }
        XCTAssertEqual(tabPositions, tabPositions.sorted(), "导航顺序应为此刻、书库、我的")
        app.buttons["navigation.tab.0"].tap()
        let organize = app.buttons["shelf.organize"]
        XCTAssertTrue(organize.waitForExistence(timeout: 10))
        XCTAssertTrue(organize.isHittable)
        screenshot(app, "书架-最大字号列表")
    }

    func testMixedImportUsesResultsInsteadOfSuccessAlert() {
        let app = launch("import-results")
        let results = app.buttons["import.results"]
        XCTAssertTrue(results.waitForExistence(timeout: 15))
        XCTAssertFalse(app.alerts.firstMatch.exists)
        results.tap()
        XCTAssertTrue(app.staticTexts["成功示例.txt"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["失败示例.json"].exists)
        XCTAssertTrue(app.buttons["重新选择失败文件"].isHittable)
        screenshot(app, "导入-逐项结果与重试")
    }

    func testReaderKeepsActionSlotsAndChapterNavigationDoesNotSeekAudio() throws {
        let app = launch("reader")
        XCTAssertTrue(app.buttons["reader.notes"].waitForExistence(timeout: 15))
        let ids = ["reader.contents", "reader.preferences", "reader.notes", "reader.more"]
        let positions = ids.map { app.buttons[$0].frame.midX }
        XCTAssertFalse(app.buttons["reader.listen"].exists, "常驻工具应优先目录、排版与摘记")
        app.buttons["reader.more"].tap()
        let start = app.buttons["从当前阅读位置听"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()
        XCTAssertTrue(app.buttons["reader.toggle"].waitForExistence(timeout: 5))
        setReadingTools(false, in: app, frame: nativeLayout(in: app)?.viewport ?? app.frame)
        waitForReadingCondition({
            guard let layout = self.nativeLayout(in: app) else { return false }
            return layout.viewport.maxY <= app.buttons["reader.toggle"].frame.minY
        }, "朗读快捷条出现时正文视口必须完整位于快捷条上方")
        let toggle = app.buttons["reader.toggle"]
        let toggleFrame = toggle.frame
        for _ in 0..<3 {
            if toggle.label.contains("暂停") { toggle.tap() }
            XCTAssertTrue(toggle.waitForExistence(timeout: 2), "暂停后快捷条必须保持，后续点击不能穿透正文")
            XCTAssertEqual(toggle.frame, toggleFrame, "暂停与继续不能移动快捷条")
            toggle.tap()
            XCTAssertTrue(app.staticTexts["跟随朗读"].waitForExistence(timeout: 5),
                          "连续暂停与继续后仍应保持跟随朗读及原文高亮")
            XCTAssertEqual(toggle.frame, toggleFrame)
        }
        setReadingTools(true, in: app, frame: nativeLayout(in: app)?.viewport ?? app.frame)
        XCTAssertTrue(app.buttons["reader.back"].isHittable)
        XCTAssertFalse(app.buttons["player.toggle"].exists, "辅助听书启动后应留在正文")
        if app.buttons["reader.toggle"].label.contains("暂停") { app.buttons["reader.toggle"].tap() }
        XCTAssertTrue(app.buttons["reader.expandPlayer"].waitForExistence(timeout: 5))
        for (index, id) in ids.enumerated() {
            XCTAssertEqual(app.buttons[id].frame.midX, positions[index], accuracy: 1, "播放状态不能改变功能键的位置")
        }
        XCTAssertEqual(app.buttons.matching(identifier: "reader.expandPlayer").count, 1)
        XCTAssertTrue(app.buttons["reader.toggle"].label.contains("继续"))
        app.buttons["reader.nextChapter"].tap()
        XCTAssertEqual(app.staticTexts["reader.currentChapter"].label, "2 / 2")
        XCTAssertFalse(app.buttons["reader.nextChapter"].isEnabled)
        app.buttons["reader.expandPlayer"].tap()
        XCTAssertTrue(app.buttons["player.toggle"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["player.currentChapter"].label, "第 1 / 2 章", "阅读翻章不能改变听书章节")
        XCTAssertTrue(app.buttons["player.toggle"].label.contains("继续"), "展开听书页不能擅自恢复播放")
        let listeningProgress = app.descendants(matching: .any)["player.sentence-progress"]
        let oldListeningPosition = listeningProgress.value as? String
        app.buttons["player.nextSentence"].tap()
        XCTAssertTrue(waitForValueChange(of: listeningProgress, from: oldListeningPosition), "应实际触发一次音频进度回写")
        XCTAssertTrue(app.buttons["player.toggle"].label.contains("继续"))
        app.buttons["player.collapse"].tap()
        XCTAssertEqual(app.staticTexts["reader.currentChapter"].label, "2 / 2", "音频进度回调不能覆盖眼前的阅读位置")
        app.buttons["reader.toggle"].tap()
        XCTAssertTrue(app.buttons["reader.toggle"].label.contains("暂停"))
        XCTAssertEqual(app.staticTexts["reader.currentChapter"].label, "2 / 2", "继续声音也不能擅自开启跟随")
        app.buttons["reader.toggle"].tap()
        app.buttons["reader.back"].tap()
        XCTAssertTrue(app.buttons["continue.reading"].waitForExistence(timeout: 5))
        app.buttons["continue.reading"].tap()
        XCTAssertTrue(app.buttons["reader.contents"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["reader.currentChapter"].label, "2 / 2", "退出重开应恢复独立阅读断点")
        app.buttons["reader.returnToSpeech"].tap()
        XCTAssertEqual(app.staticTexts["reader.currentChapter"].label, "1 / 2")
        screenshot(app, "阅读优先-固定阅读工具与独立听书进度")
    }

    func testOriginalReaderKeepsFollowingThroughRepeatedPlaybackToggles() throws {
        let app = launch("reader-original", original: true)
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.waitForExistence(timeout: 15))
        waitForOriginalChapter("第一章 · 纸上的风景", in: web, app: app)
        app.buttons["reader.more"].tap()
        app.buttons["从当前阅读位置听"].tap()
        XCTAssertTrue(app.buttons["reader.toggle"].waitForExistence(timeout: 5))
        setReadingTools(false, in: app, frame: web.frame)
        let toggle = app.buttons["reader.toggle"]
        if toggle.label.contains("暂停") { toggle.tap() }
        waitForReadingCondition({ toggle.label.contains("继续") }, "暂停后快捷条应保持可用")
        let anchor = originalText("把日子放慢一点", in: web)
        waitForOriginalElement(anchor, in: web, app: app, message: "用于检查布局的原文字符节点必须可见")
        let capture: () -> ReaderLayoutCapture? = {
            guard web.exists, anchor.exists, anchor.frame.width > 1 else { return nil }
            return .init(viewport: web.frame, text: [anchor.label], frames: [anchor.frame])
        }
        let baseline = try captureReaderLayout(capture)
        for visible in [true, false] {
            setReadingTools(visible, in: app, frame: baseline.viewport)
            let current = try captureReaderLayout(capture)
            XCTAssertEqual(current.viewport, baseline.viewport, "朗读中开合阅读菜单不能改变原书视口")
            XCTAssertEqual(current.frames, baseline.frames, "朗读中开合阅读菜单不能改变原文字符布局")
        }
        let toggleFrame = toggle.frame
        for _ in 0..<3 {
            if toggle.label.contains("暂停") { toggle.tap() }
            XCTAssertTrue(toggle.waitForExistence(timeout: 2), "原书图文暂停后也不能让点击穿透到网页正文")
            XCTAssertEqual(toggle.frame, toggleFrame)
            XCTAssertEqual(web.frame, baseline.viewport, "暂停不能改变原书视口")
            toggle.tap()
            XCTAssertTrue(app.staticTexts["跟随朗读"].waitForExistence(timeout: 5),
                          "原书图文连续暂停与继续后应保留朗读高亮")
            XCTAssertEqual(toggle.frame, toggleFrame)
            XCTAssertEqual(web.frame, baseline.viewport, "继续朗读不能改变原书视口")
        }
        screenshot(app, "原书图文-连续播放保持跟随")
    }

    func testReaderNotesAndSearchOpenWithoutStartingAudio() {
        let app = launch("reader")
        XCTAssertTrue(app.buttons["reader.notes"].waitForExistence(timeout: 15))
        openReaderNotesAndReturn(in: app)
        XCTAssertFalse(app.buttons["reader.toggle"].exists)
        app.buttons["reader.more"].tap()
        app.buttons["书内搜索"].tap()
        let field = app.searchFields["搜索章节与全文"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertTrue(field.isHittable, "激活搜索后应直接显示可输入的搜索框")
        XCTAssertTrue(app.buttons["章节"].isSelected, "书内搜索应打开章节与全文结果")
        field.tap()
        field.typeText("第二章")
        XCTAssertTrue(app.staticTexts["reader.searchResultCount"].waitForExistence(timeout: 5))
        // 搜索异步替换行；存在并不代表插入动画已结束，且不能命中键盘候选文字。
        let chapter = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "02、第二章")).firstMatch
        XCTAssertTrue(chapter.waitForExistence(timeout: 5))
        waitForReadingCondition({ chapter.isHittable }, "搜索结果完成布局后应能直接点击")
        screenshot(app, "阅读优先-书内搜索结果")
        chapter.tap()
        XCTAssertTrue(app.buttons["reader.notes"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["reader.currentChapter"].label, "2 / 2")
        XCTAssertFalse(app.buttons["reader.toggle"].exists, "阅读搜索与摘记不应开启声音")
        screenshot(app, "阅读优先-摘记直达与书内搜索")
    }

    func testReaderMoreGroupsDayNightAndKeepsBookmarkSeparate() {
        let app = launch("reader")
        XCTAssertTrue(app.buttons["reader.more"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["reader.bookmark"].isHittable)
        app.buttons["reader.more"].tap()
        // UIKit 系统菜单的 Section 子项不一定保留 SwiftUI identifier，按可见名称操作。
        XCTAssertTrue(app.buttons["切换夜间纸色"].waitForExistence(timeout: 5))
        app.buttons["切换夜间纸色"].tap()
        app.buttons["reader.more"].tap()
        XCTAssertTrue(app.buttons["切换日间纸色"].waitForExistence(timeout: 5))
        screenshot(app, "功能键-更多阅读操作与夜间切换")
    }

    func testShelfSeparatesFilterSortAndLayoutAndProtectsDeletion() {
        let app = launch("shelf")
        XCTAssertTrue(app.buttons["shelf.filter"].waitForExistence(timeout: 15))
        for id in ["shelf.filter", "shelf.sort", "shelf.layout", "shelf.more"] {
            XCTAssertEqual(app.buttons.matching(identifier: id).count, 1)
            XCTAssertTrue(app.buttons[id].isHittable)
        }
        // 新版添加入口位于书目末尾，浏览工具仍固定在列表前。
        XCTAssertEqual(app.buttons.matching(identifier: "import.book").count, 1)
        let add = app.buttons["import.book"]
        reveal(add, in: app)
        XCTAssertTrue(add.isHittable)
        for _ in 0..<10 {
            if app.buttons["shelf.filter"].isHittable { break }
            app.swipeDown()
        }
        XCTAssertTrue(app.buttons["shelf.filter"].isHittable)
        app.buttons["shelf.filter"].tap()
        app.buttons["待读"].tap()
        XCTAssertTrue(app.buttons["shelf.clearFilters"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["book.detail.ui-long"].exists)
        XCTAssertEqual(app.buttons.matching(identifier: "shelf.sort").count, 1, "筛选后不能复制一份浏览工具")
        app.buttons["shelf.clearFilters"].tap()
        app.buttons["shelf.sort"].tap()
        app.buttons["书名"].tap()
        XCTAssertTrue(app.buttons["shelf.sort"].label.contains("书名"))
        app.buttons["shelf.layout"].tap()
        app.buttons["封面网格"].tap()
        XCTAssertTrue(app.buttons["shelf.layout"].label.contains("网格"))
        screenshot(app, "功能键-书架筛选排序与显示分层")
        app.buttons["shelf.organize"].tap()
        XCTAssertFalse(app.buttons["shelf.delete"].isEnabled)
        app.buttons["shelf.selectAll"].tap()
        XCTAssertTrue(app.buttons["shelf.move"].isEnabled)
        app.buttons["shelf.delete"].tap()
        XCTAssertTrue(app.buttons["删除本机副本"].waitForExistence(timeout: 5))
        cancelConfirmation(in: app)
        app.buttons["shelf.finishOrganizing"].tap()
        XCTAssertTrue(app.buttons["book.detail.ui-long"].waitForExistence(timeout: 5), "取消删除应保留书籍")
    }

    func testPlayerToolsAreDirectAndPreservePausedState() {
        let app = launch("player")
        XCTAssertTrue(app.buttons["player.voice"].waitForExistence(timeout: 15))
        let ids = ["player.contents", "player.rate", "player.voice", "player.sleep"]
        let positions = ids.map { app.buttons[$0].frame.midX }
        XCTAssertEqual(positions, positions.sorted())
        for id in ids { XCTAssertTrue(app.buttons[id].isHittable) }
        app.buttons["player.voice"].tap()
        XCTAssertTrue(app.navigationBars["声音与朗读"].waitForExistence(timeout: 5))
        reveal(app.buttons["AirPlay"], in: app)
        XCTAssertTrue(app.buttons["AirPlay"].isHittable)
        screenshot(app, "功能键-声音与播放设备")
        app.buttons["取消声音设置，不保存修改"].tap()
        XCTAssertTrue(app.buttons["player.toggle"].label.contains("继续"))
        app.buttons["player.sleep"].tap()
        app.buttons["15 分钟后停止"].tap()
        XCTAssertTrue((app.buttons["player.sleep"].value as? String)?.contains("15") == true)
        app.buttons["player.sleep"].tap()
        app.buttons["关闭定时"].tap()
        XCTAssertEqual(app.buttons["player.sleep"].value as? String, "未开启")
        XCTAssertTrue(app.buttons["player.toggle"].label.contains("继续"))
        screenshot(app, "功能键-听书四项常用工具")
    }

    func testMiniPlayerOnlyExpandsAndTogglesAndEndNeedsConfirmation() {
        let app = launch("player")
        XCTAssertTrue(app.buttons["player.collapse"].waitForExistence(timeout: 15))
        app.buttons["player.collapse"].tap()
        XCTAssertTrue(app.buttons["miniPlayer.open"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["miniPlayer.toggle"].label.contains("继续"))
        XCTAssertFalse(app.buttons["下一句"].exists)
        screenshot(app, "功能键-精简迷你播放器")
        app.buttons["miniPlayer.open"].tap()
        XCTAssertTrue(app.buttons["player.toggle"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["player.toggle"].label.contains("继续"))
        app.buttons["player.more"].tap()
        app.buttons["player.endListening"].tap()
        XCTAssertTrue(app.buttons["结束听书"].waitForExistence(timeout: 5))
        cancelConfirmation(in: app)
        XCTAssertTrue(app.buttons["player.toggle"].isHittable)
        app.buttons["player.more"].tap()
        app.buttons["player.endListening"].tap()
        app.buttons["结束听书"].tap()
        XCTAssertTrue(app.buttons["navigation.tab.0"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["miniPlayer.open"].exists)
    }

    func testLargestTypeReaderToolsCanScrollWithoutLosingBackButton() {
        let app = launch("reader", largeType: true)
        XCTAssertTrue(app.buttons["reader.back"].waitForExistence(timeout: 15))
        let tools = app.scrollViews["reader.tools"]
        for id in ["reader.contents", "reader.preferences", "reader.notes", "reader.more"] {
            let button = app.buttons[id]
            for _ in 0..<5 {
                let visible = tools.frame.intersection(app.frame)
                if button.isHittable && visible.contains(button.frame) { break }
                tools.swipeUp()
            }
            XCTAssertTrue(button.isHittable)
            XCTAssertTrue(tools.frame.intersection(app.frame).contains(button.frame), "滚动后工具按钮必须完整露出，不能只露出图标就算可点击")
            XCTAssertTrue(app.buttons["reader.back"].isHittable)
            XCTAssertGreaterThanOrEqual(button.frame.height, 44)
            XCTAssertGreaterThanOrEqual(button.frame.minX, 20)
            XCTAssertLessThanOrEqual(button.frame.maxX, app.frame.maxX - 20, "大字号不能把工具面板撑出水平边距")
        }
        XCTAssertLessThanOrEqual(app.buttons["reader.bookmark"].frame.maxX, app.frame.maxX - 12)
        screenshot(app, "功能键-最大字号阅读工具")
        app.buttons["reader.more"].tap()
        XCTAssertTrue(app.buttons["切换夜间纸色"].waitForExistence(timeout: 5))
    }

    func testMarginProfileAndAppearanceRoutesRemainAvailable() {
        let app = launch("stats")
        let settings = app.buttons["profile.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 15))
        XCTAssertEqual(app.buttons["navigation.tab.2"].label, "我的")
        let statistics = app.buttons["profile.stats"]
        XCTAssertTrue(statistics.isHittable)
        statistics.tap()
        XCTAssertTrue(app.navigationBars["阅读足迹"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["按日查看"].isSelected)
        screenshot(app, "听页-阅读足迹")
        app.navigationBars["阅读足迹"].buttons.firstMatch.tap()
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 5))
        let appearance = app.buttons["profile.appearance"]
        reveal(appearance, in: app)
        appearance.tap()
        XCTAssertTrue(app.navigationBars["外观"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["appearance.light"].isSelected)
        app.buttons["appearance.dark"].tap()
        XCTAssertTrue(app.buttons["appearance.dark"].isSelected)
        screenshot(app, "听页-夜间外观选择")
        app.navigationBars["外观"].buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 5))
        let reading = app.buttons["profile.reading"]
        reveal(reading, in: app)
        reading.tap()
        XCTAssertTrue(app.navigationBars["阅读排版"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["系统字体"].isSelected, "外观切换不能改变正文的独立字体偏好")
        screenshot(app, "听页-夜间阅读排版")
        let paper = app.buttons["旧书"]
        revealAboveDone(paper, in: app)
        paper.tap()
        XCTAssertTrue(paper.isSelected)
        app.buttons["完成"].tap()
        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 5))
        reveal(appearance, in: app)
        appearance.tap()
        app.buttons["appearance.light"].tap()
        XCTAssertTrue(app.buttons["appearance.light"].isSelected)
        app.navigationBars["外观"].buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 5))
        reveal(reading, in: app)
        reading.tap()
        XCTAssertTrue(app.navigationBars["阅读排版"].waitForExistence(timeout: 5))
        revealAboveDone(app.buttons["旧书"], in: app)
        XCTAssertTrue(app.buttons["旧书"].isSelected, "全局外观切换不能重置独立选择的纸色")
    }

    func testOriginalReaderKeepsTypographyAndContentsReachable() {
        let app = launch("reader-original", original: true)
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.waitForExistence(timeout: 15), "原书模式必须实际使用含图文的 WebView，不能回退纯文字")
        waitForOriginalChapter("第一章 · 纸上的风景", in: web, app: app)
        verifyOriginalIllustration(in: web, app: app)
        for id in ["reader.back", "reader.contents", "reader.preferences", "reader.notes", "reader.more"] {
            XCTAssertTrue(app.buttons[id].isHittable, "原书图文应保留工具：\(id)")
        }
        XCTAssertEqual(app.staticTexts["reader.currentChapter"].label, "1 / 2")
        screenshot(app, "原书图文-正文与阅读工具")
        openReaderNotesAndReturn(in: app)
        waitForOriginalChapter("第一章 · 纸上的风景", in: web, app: app)
        app.buttons["reader.preferences"].tap()
        XCTAssertTrue(app.navigationBars["阅读排版"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["系统字体"].isSelected)
        let paper = app.buttons["旧书"]
        revealAboveDone(paper, in: app)
        paper.tap()
        XCTAssertTrue(paper.isSelected)
        app.buttons["完成"].tap()
        XCTAssertTrue(web.waitForExistence(timeout: 5), "更换纸色应保留原书图文渲染器")
        waitForOriginalChapter("第一章 · 纸上的风景", in: web, app: app)
        XCTAssertTrue(app.buttons["reader.contents"].isHittable)
        app.buttons["reader.contents"].tap()
        XCTAssertTrue(app.navigationBars["目录与摘记"].waitForExistence(timeout: 5))
        let first = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "第一章 · 纸上的风景")).firstMatch
        let second = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "第二章 · 安静的回声")).firstMatch
        XCTAssertTrue(first.exists)
        XCTAssertTrue(second.isHittable)
        second.tap()
        XCTAssertTrue(app.buttons["reader.preferences"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["reader.currentChapter"].label, "2 / 2")
        XCTAssertFalse(app.buttons["reader.nextChapter"].isEnabled)
        XCTAssertTrue(web.exists, "目录跳章后仍应显示第二章的原书 HTML")
        waitForOriginalChapter("第二章 · 安静的回声", in: web, app: app)
        app.buttons["reader.preferences"].tap()
        XCTAssertTrue(app.navigationBars["阅读排版"].waitForExistence(timeout: 5))
        revealAboveDone(app.buttons["旧书"], in: app)
        XCTAssertTrue(app.buttons["旧书"].isSelected, "原书翻章不应重置排版偏好")
        app.buttons["完成"].tap()
        waitForOriginalChapter("第二章 · 安静的回声", in: web, app: app)
        screenshot(app, "原书图文-目录跳章与排版保持")
    }

    func testOriginalReaderDarkModeKeepsChapterControlsReachable() {
        let app = launch("reader-original", appearance: "dark", original: true)
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.waitForExistence(timeout: 15))
        waitForOriginalChapter("第一章 · 纸上的风景", in: web, app: app)
        verifyOriginalIllustration(in: web, app: app)
        for id in ["reader.back", "reader.contents", "reader.preferences", "reader.notes", "reader.previousChapter", "reader.nextChapter"] {
            XCTAssertTrue(app.buttons[id].isHittable, "夜间原书模式应保留工具：\(id)")
        }
        app.buttons["reader.nextChapter"].tap()
        XCTAssertEqual(app.staticTexts["reader.currentChapter"].label, "2 / 2")
        XCTAssertFalse(app.buttons["reader.nextChapter"].isEnabled)
        waitForOriginalChapter("第二章 · 安静的回声", in: web, app: app)
        app.buttons["reader.previousChapter"].tap()
        XCTAssertEqual(app.staticTexts["reader.currentChapter"].label, "1 / 2")
        XCTAssertTrue(app.webViews.firstMatch.exists)
        waitForOriginalChapter("第一章 · 纸上的风景", in: web, app: app)
        verifyOriginalIllustration(in: web, app: app)
        screenshot(app, "原书图文-夜间独立章节导航")
    }

    func testOriginalReaderChromeDoesNotResizeOrMoveItsColumn() throws {
        let app = launch("reader-original", original: true)
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.waitForExistence(timeout: 15))
        setReadingTools(false, in: app, frame: web.frame)
        waitForOriginalChapter("第一章 · 纸上的风景", in: web, app: app)
        verifyOriginalIllustration(in: web, app: app)
        web.swipeLeft()
        var anchor: XCUIElement?
        waitForReadingCondition({
            guard !self.originalElementIsVisible(self.originalText("第一章 · 纸上的风景", in: web), in: web, app: app) else { return false }
            anchor = web.staticTexts.allElementsBoundByIndex.first { !$0.label.isEmpty && self.originalElementIsVisible($0, in: web, app: app) }
            return anchor != nil
        }, "原文必须实际翻到非首页并显示文字")
        let text = try XCTUnwrap(anchor)
        setReadingTools(true, in: app, frame: web.frame)
        let capture: () -> ReaderLayoutCapture? = {
            guard web.exists, text.exists, text.frame.width > 1 else { return nil }
            return .init(viewport: web.frame, text: [text.label], frames: [text.frame])
        }
        let reading = try captureReaderLayout(capture)
        try assertReaderChromePreservesLayout(in: app, baseline: reading, capture: capture, name: "固定正文-原书图文")
        setReadingTools(false, in: app, frame: web.frame)
        web.swipeRight()
        waitForOriginalChapter("第一章 · 纸上的风景", in: web, app: app)
    }

    func testPDFReaderKeepsReadingToolsAndNotesReachable() {
        let app = launch("reader-pdf")
        XCTAssertTrue(app.buttons["reader.notes"].waitForExistence(timeout: 15))
        for id in ["reader.contents", "reader.preferences", "reader.notes", "reader.more"] {
            XCTAssertTrue(app.buttons[id].isHittable)
        }
        XCTAssertEqual(app.staticTexts["reader.currentChapter"].label, "1 / 2")
        openReaderNotesAndReturn(in: app)
        app.buttons["reader.nextChapter"].tap()
        XCTAssertEqual(app.staticTexts["reader.currentChapter"].label, "2 / 2")
        XCTAssertFalse(app.buttons["reader.nextChapter"].isEnabled)
        XCTAssertFalse(app.buttons["player.toggle"].exists)
        screenshot(app, "阅读优先-PDF工具与摘记")
    }

    func testPDFReaderChromeDoesNotResizeScaleOrMoveItsPage() throws {
        let app = launch("reader-pdf")
        XCTAssertTrue(app.buttons["reader.nextChapter"].waitForExistence(timeout: 15))
        let capture = { self.pdfLayout(in: app) }
        let first = try captureReaderLayout(capture)
        app.buttons["reader.nextChapter"].tap()
        waitForReadingCondition({ capture()?.pdf["page"] as? NSNumber != first.pdf["page"] as? NSNumber },
                                "PDFKit 必须实际进入另一页")
        XCTAssertEqual(app.staticTexts["reader.currentChapter"].label, "2 / 2")
        let reading = try captureReaderLayout(capture)
        try assertReaderChromePreservesLayout(in: app, baseline: reading, capture: capture, name: "固定正文-PDF")
        app.buttons["reader.previousChapter"].tap()
        waitForReadingCondition({ capture()?.pdf["page"] as? NSNumber == first.pdf["page"] as? NSNumber },
                                "工具开关后 PDF 应能返回原页")
        XCTAssertEqual(app.staticTexts["reader.currentChapter"].label, "1 / 2")
    }

    func testMarginDarkPlayerAndReaderKeepControlsReachable() {
        let app = launch("player", appearance: "dark")
        XCTAssertTrue(app.buttons["player.toggle"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["player.toggle"].isHittable)
        screenshot(app, "余白-夜间听书")
        app.terminate()
        let reader = launch("reader", appearance: "dark")
        XCTAssertTrue(reader.buttons["reader.preferences"].waitForExistence(timeout: 15))
        XCTAssertTrue(reader.buttons["reader.back"].isHittable)
        XCTAssertTrue(reader.buttons["reader.contents"].isHittable)
        screenshot(reader, "余白-夜间正文")
    }

    func testLandscapePlayerKeepsPlaybackVisible() {
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = launch("player")
        XCTAssertTrue(app.buttons["player.toggle"].waitForExistence(timeout: 15))
        for id in ["player.previousSentence", "player.toggle", "player.nextSentence"] {
            XCTAssertTrue(app.buttons[id].isHittable)
            XCTAssertTrue(app.frame.contains(app.buttons[id].frame))
        }
        XCTAssertGreaterThan(app.frame.width, app.frame.height, "必须实际进入横屏布局")
        // Xcode 27's application-cropped capture can use portrait bounds after rotation.
        screenshot(app, "功能键-横屏固定播放控制", wholeScreen: true)
    }
}

extension DesignFlowTests {
    func testSingleTapLocalFileImportsThroughSystemPicker() {
        let app = launch("sources-file-import")
        let choose = app.buttons["sources.importFile"]
        XCTAssertTrue(choose.waitForExistence(timeout: 15))
        choose.tap()
        let file = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "点击导入")).firstMatch
        XCTAssertTrue(file.waitForExistence(timeout: 20), app.debugDescription)
        screenshot(app, "系统选择器-选择本地书籍")
        let fileCell = app.cells.containing(.staticText, identifier: file.label).firstMatch
        XCTAssertTrue(fileCell.exists)
        fileCell.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)).tap()
        let results = app.buttons.matching(identifier: "import.results").firstMatch
        XCTAssertTrue(results.waitForExistence(timeout: 20), "Single file tap should dismiss the picker and start import: " + app.debugDescription)
        results.tap()
        XCTAssertTrue(app.staticTexts["1 本书导入成功"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["点击导入.txt"].exists)
        screenshot(app, "本地文件-单击导入成功")
    }
}
