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
        // 目标既可能在视口下方，也可能在上方：从设置目录底部（外观）返回后，
        // 顶部的「阅读排版」就在视口上方，单向 swipeUp 永远滑不到它。
        // 先向上方（swipeDown）找：目标已存在且不在上方时提前转入向下查找。
        for _ in 0..<6 {
            if element.isHittable { return }
            if element.exists, !element.frame.isEmpty, element.frame.minY >= app.frame.minY { break }
            app.swipeDown()
        }
        for _ in 0..<10 {
            if element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
    }

    private func revealInScrollView(_ element: XCUIElement, in scrollView: XCUIElement, _ message: String,
                                    file: StaticString = #filePath, line: UInt = #line) {
        var swipes = 0
        waitForReadingCondition({
            if element.exists && element.isHittable { return true }
            if swipes < 6, scrollView.exists, scrollView.isHittable {
                swipes += 1
                scrollView.swipeUp()
            }
            return false
        }, message, file: file, line: line)
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

    /// 系统路由按钮的标签随语言变化。优先认我们打上的标识，再认常见标签。
    /// 只在按钮完整落在屏幕内、且不被底部保存栏挡住时返回，避免对屏外元素问 isHittable。
    private func audioOutput(in app: XCUIApplication, above save: XCUIElement) -> XCUIElement? {
        let candidates = [
            app.buttons["voice.audioOutput"],
            app.buttons["AirPlay"],
            app.buttons["隔空播放"],
            app.buttons["选择音频输出设备"],
        ]
        for candidate in candidates {
            guard candidate.exists else { continue }
            let frame = candidate.frame
            guard frame.width > 10, frame.height > 10 else { continue }
            guard app.frame.insetBy(dx: 0, dy: 4).contains(frame) else { continue }
            if save.exists, frame.maxY > save.frame.minY { continue }
            return candidate
        }
        return nil
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

        /// Readium 网页的无障碍坐标会在 1 点内来回跳动。工具显隐真正挪动正文栏时位移远大于这个容差。
        func nearlyEquals(_ other: ReaderLayoutCapture, tolerance: CGFloat = 2) -> Bool {
            text == other.text && pdf == other.pdf
                && Self.framesMatch(viewport, other.viewport, tolerance: tolerance)
                && frames.count == other.frames.count
                && zip(frames, other.frames).allSatisfy { Self.framesMatch($0, $1, tolerance: tolerance) }
        }

        private static func framesMatch(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat) -> Bool {
            abs(lhs.minX - rhs.minX) <= tolerance && abs(lhs.minY - rhs.minY) <= tolerance
                && abs(lhs.width - rhs.width) <= tolerance && abs(lhs.height - rhs.height) <= tolerance
        }
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
        var captured: ReaderLayoutCapture?
        waitForReadingCondition({
            guard let next = capture(), next.viewport.width > 40, next.viewport.height > 80 else { return false }
            captured = next
            return true
        }, "应取得有效的正文布局", file: file, line: line)
        return try XCTUnwrap(captured, file: file, line: line)
    }

    /// 原书样本是块级分页：插图 / 表格整块独占一页，这类页面没有 reader.nativePage 正文，
    /// 布局捕获恒为 nil。向前翻页时跳过这类无正文的块页，直到落在一个与基准页文字不同的
    /// 正文页，并返回实际翻页次数，供返回时对称翻回。超时或超过上限返回 nil。
    private func advanceToTextPage(in app: XCUIApplication, capture: () -> ReaderLayoutCapture?,
                                   differentFrom baseline: ReaderLayoutCapture) -> Int? {
        var turns = 0
        // CI 模拟器上翻页落地偏慢，给足时间与次数：首屏是块级分页（插图/表格独占页），
        // 要连着跳过若干无正文页才能落到正文页，翻不动就误判成「没有正文页」。
        let deadline = Date().addingTimeInterval(40)
        while Date() < deadline {
            if let next = capture(), next.text != baseline.text { return turns }
            guard turns < 6 else { return nil }
            let before = capture()
            // Readium 分页靠左右滑，点右缘会落到工具栏切换区，页码不会变。
            app.webViews.firstMatch.swipeLeft()
            turns += 1
            // 等这一翻落地（捕获变化或落到无正文的块页）后再继续判断，避免对着过渡帧连点。
            let settle = Date().addingTimeInterval(4)
            while Date() < settle {
                let next = capture()
                let unchanged = (next == nil && before == nil) || (next.map { current in before?.nearlyEquals(current) ?? false } ?? false)
                if !unchanged { break }
                Thread.sleep(forTimeInterval: 0.2)
            }
        }
        return nil
    }

    private func tapReadingCenter(in app: XCUIApplication, frame: CGRect) {
        // 双页时第一张纸页的中央属于上一页区；使用整个窗口的中央 x。
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: app.frame.width / 2, dy: frame.midY - app.frame.minY)).tap()
    }

    private func exposedReadingFrame(in app: XCUIApplication, frame: CGRect,
                                     file: StaticString = #filePath, line: UInt = #line) -> CGRect? {
        // 正文视口延伸在 chrome 覆盖层下方；底栏/听条可能覆过整页中线，
        // 只在顶栏与底栏之间实际露出的正文区域内点按，不能穿透面板控件。
        let viewport = frame.intersection(app.frame)
        let back = app.buttons["reader.back"]
        let tools = app.scrollViews["reader.tools"]
        let top = back.exists ? max(viewport.minY, back.frame.maxY) : viewport.minY
        let bottom = tools.exists ? min(viewport.maxY, tools.frame.minY) : viewport.maxY
        guard !viewport.isNull, viewport.width > 1, bottom - top > 1 else {
            XCTFail("阅读工具覆盖层之间应有可点按的正文区域", file: file, line: line)
            return nil
        }
        return CGRect(x: viewport.minX, y: top, width: viewport.width, height: bottom - top)
    }

    private func tapReadingEdge(next: Bool, in app: XCUIApplication, frame: CGRect,
                                file: StaticString = #filePath, line: UInt = #line) {
        guard let exposed = exposedReadingFrame(in: app, frame: frame, file: file, line: line) else { return }
        // 翻页热区为正文宽度的最左/最右 28%；落点取露出正文边缘内侧并相对窗口原点换算。
        let inset = min(12, exposed.width * 0.14)
        let x = next ? exposed.maxX - inset : exposed.minX + inset
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: x - app.frame.minX, dy: exposed.midY - app.frame.minY)).tap()
    }

    private func setReadingTools(_ visible: Bool, in app: XCUIApplication, frame: CGRect,
                                 file: StaticString = #filePath, line: UInt = #line) {
        let more = app.buttons["reader.more"]
        if more.exists != visible {
            guard let exposed = exposedReadingFrame(in: app, frame: frame, file: file, line: line) else { return }
            tapReadingCenter(in: app, frame: exposed)
        }
        // 与 openReaderMorePanel / waitForReadingCondition 使用同一 15 秒口径。
        // 显示必须同时存在且可点；隐藏仍要求从可访问性树移除，不能只验不可点。
        if visible {
            waitForReadingCondition({ more.exists && more.isHittable }, "阅读工具应显示且可点按", file: file, line: line)
        } else {
            XCTAssertTrue(more.waitForNonExistence(timeout: 15), "阅读工具应已隐藏", file: file, line: line)
        }
    }

    /// 打开阅读页「更多」工具面板（原生底部 sheet）并定位到面板内的指定条目。
    private func openReaderMorePanel(_ app: XCUIApplication, expect row: String,
                                     file: StaticString = #filePath, line: UInt = #line) {
        let sheet = app.scrollViews["reader.moreSheet"]
        if !sheet.exists {
            let more = app.buttons["reader.more"]
            XCTAssertTrue(more.waitForExistence(timeout: 15), "更多按钮应存在", file: file, line: line)
            more.tap()
            XCTAssertTrue(sheet.waitForExistence(timeout: 10), "阅读工具面板应已打开", file: file, line: line)
        }
        let target = sheet.buttons[row]
        revealInScrollView(target, in: sheet, "阅读工具面板未出现「\(row)」", file: file, line: line)
    }

    private func assertReaderChromePreservesLayout(in app: XCUIApplication, baseline: ReaderLayoutCapture,
                                                  capture: @escaping () -> ReaderLayoutCapture?, name: String,
                                                  file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertTrue(app.buttons["reader.more"].isHittable, file: file, line: line)
        for (index, visible) in [false, true, false, true].enumerated() {
            setReadingTools(visible, in: app, frame: baseline.viewport)
            let current = try captureReaderLayout(capture, file: file, line: line)
            XCTAssertEqual(current.text, baseline.text, "实际页文字应保持，不能仅让章节编号不变", file: file, line: line)
            XCTAssertEqual(current.pdf, baseline.pdf, "工具显隐不能改变 PDF 页码、缩放或页内位置", file: file, line: line)
            XCTAssertTrue(current.nearlyEquals(baseline), "工具显隐不能移动或收缩实际正文视口，也不能重排正文元素", file: file, line: line)
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
        XCTAssertTrue(notesTab.waitForExistence(timeout: 10))
        XCTAssertTrue(notesTab.isSelected, "摘记入口应直接打开笔记，而非让读者再切换章节页签")
        // 切到笔记页后内容还需一拍完成布局：等提示文字真正可达，不采样一次下结论。
        let noteHint = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "长按正文")).firstMatch
        waitForReadingCondition({ noteHint.isHittable }, "笔记页应显示可达的「长按正文」提示")
        XCTAssertFalse(app.buttons["player.toggle"].exists)
        app.buttons["完成"].tap()
        XCTAssertTrue(app.buttons["reader.more"].waitForExistence(timeout: 5))
    }

    private func epubWeb(in app: XCUIApplication) -> XCUIElement {
        XCTAssertTrue(app.buttons["reader.contents"].waitForExistence(timeout: 20))
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.waitForExistence(timeout: 15))
        return web
    }
    private func openEPUBChapter(_ title: String, in app: XCUIApplication) {
        app.buttons["reader.contents"].tap()
        XCTAssertTrue(app.navigationBars["目录"].waitForExistence(timeout: 5))
        let chapter = app.buttons[title]
        XCTAssertTrue(chapter.waitForExistence(timeout: 5))
        chapter.tap()
        XCTAssertTrue(app.navigationBars["目录"].waitForNonExistence(timeout: 5))
        waitForReadingCondition({ app.staticTexts["reader.currentTitle"].label == title }, "EPUB 跳章应已确认")
    }
    private func setEPUBTools(_ visible: Bool, in app: XCUIApplication, web: XCUIElement) {
        if app.buttons["reader.contents"].exists != visible { tapReadingCenter(in: app, frame: web.frame) }
        waitForReadingCondition({ app.buttons["reader.contents"].exists == visible }, "EPUB 工具显隐应完成")
    }
    private func epubLayout(in app: XCUIApplication) -> ReaderLayoutCapture? {
        let web = app.webViews.firstMatch
        let page = app.descendants(matching: .any)["reader.epubPage"]
        guard web.exists, page.exists, web.frame.width > 40, web.frame.height > 80 else { return nil }
        let token = page.label
        guard token.hasPrefix("page|") else { return nil }
        func q(_ value: CGFloat) -> CGFloat { value.rounded() }
        let frame = web.frame
        return .init(viewport: CGRect(x: q(frame.minX), y: q(frame.minY), width: q(frame.width), height: q(frame.height)),
                     text: [token])
    }
    func testEPUBDerivedFixtureSmokeAndSearch() {
        let app = launch("reader-original", original: true)
        let web = epubWeb(in: app)
        waitForOriginalChapter("第一章 · 纸上的风景", in: web, app: app)
        // 验证目录与直达书内搜索均可一键打开，不再依赖嵌套 sheet 切换。
        app.buttons["reader.contents"].tap()
        let contentsNav = app.navigationBars["目录"]
        XCTAssertTrue(contentsNav.waitForExistence(timeout: 5))
        app.buttons["完成"].tap()
        XCTAssertTrue(contentsNav.waitForNonExistence(timeout: 5), "关闭目录后目录导航栏应消失")
        let searchButton = app.buttons["reader.search"]
        waitForReadingCondition({ searchButton.exists && searchButton.isHittable }, "关闭目录后顶栏书内搜索按钮应可点按")
        searchButton.tap()
        let search = app.searchFields["搜索章节与全文"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap(); search.typeText("把日子放慢一点")
        let hit = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "把日子放慢一点")).firstMatch
        XCTAssertTrue(hit.waitForExistence(timeout: 10))
        waitForReadingCondition({ hit.isHittable }, "EPUB 书内搜索结果应在键盘上方直接可点")
        hit.tap()
        XCTAssertTrue(app.navigationBars["目录与摘记"].waitForNonExistence(timeout: 5), "选中搜索结果后搜索面板应关闭")
        let preferencesButton = app.buttons["reader.preferences"]
        waitForReadingCondition({ preferencesButton.exists && preferencesButton.isHittable }, "选中搜索结果后排版入口应可点按")
        preferencesButton.tap()
        let prefsNav = app.navigationBars["阅读排版"]
        XCTAssertTrue(prefsNav.waitForExistence(timeout: 5))
        app.buttons["完成"].tap()
        XCTAssertTrue(prefsNav.waitForNonExistence(timeout: 5), "关闭排版面板后导航栏应消失")
        let backButton = app.buttons["reader.back"]
        waitForReadingCondition({ backButton.exists && backButton.isHittable }, "关闭排版面板后返回按钮应可点按")
        backButton.tap()
        XCTAssertTrue(app.buttons["study.heroContinue"].waitForExistence(timeout: 10))
    }

    func testHomeShowsContinueAndRecentWithoutScrolling() {
        // 131 起没有独立「今日」页：书库即根页面（书房），续读由正在读大卡承担，
        // 原 continue.reading / now.listen 标识已随 Now 页删除。
        let app = launch("shelf")
        let read = app.buttons["study.heroContinue"]
        XCTAssertTrue(read.waitForExistence(timeout: 15))
        waitForReadingCondition({ read.isHittable && app.buttons["study.heroFocus"].isHittable }, "续读卡两项动作应完成布局")
        XCTAssertTrue(read.label.contains("继续阅读"))
        XCTAssertGreaterThanOrEqual(read.frame.height, 44)
        XCTAssertTrue(app.buttons["study.heroFocus"].isHittable, "专注是大卡上的第二动作；听书已收拢为辅助入口，不再与续读并列")
        waitForReadingCondition({ app.staticTexts["study.heroTitle"].label == "一本用来检查长标题和阅读体验的书" }, "大卡应是最近在读的书")
        waitForReadingCondition({ app.staticTexts["study.heroChapter"].label == "第 1 / 2 章" }, "大卡应显示阅读进度")
        screenshot(app, "书房-首屏续读大卡")
    }

    func testRecentReadingStaysPrimaryWhileAnotherBookHasListeningProgress() {
        // 同 E1：续读看书房大卡（study.heroContinue），进度看大卡上的章节文本，
        // 原 continue.reading / now.readingProgress / now.listen 均已删除。
        let app = launch("now-listening")
        let reading = app.buttons["study.heroContinue"]
        XCTAssertTrue(reading.waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["miniPlayer.toggle"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["miniPlayer.toggle"].label.contains("继续"))
        waitForReadingCondition({ app.staticTexts["study.heroTitle"].label == "一本用来检查长标题和阅读体验的书" }, "续读大卡应属于最近阅读的书")
        waitForReadingCondition({ app.staticTexts["study.heroChapter"].label == "第 2 / 2 章" }, "大卡进度属于最近阅读（第 2 章），不属于刚听过的另一本书")
        screenshot(app, "阅读优先-最近阅读与独立听书条")
        reading.tap()
        XCTAssertTrue(app.buttons["reader.contents"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["reader.currentChapter"].label, "2 / 2")
        XCTAssertFalse(app.buttons["player.toggle"].exists, "继续阅读不能把用户送入播放器")
    }

    func testHomeSearchOpensExistingShelfSearch() {
        // 搜索入口就在书房根页面（shelf.search），原 now.search 已删除。
        let app = launch("shelf")
        let search = app.buttons["shelf.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 15))
        search.tap()
        let field = app.textFields["shelf.search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("长标题")
        field.typeText("\n")
        let result = app.buttons["book.detail.ui-long"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        waitForReadingCondition({ result.isHittable }, "小屏键盘上方应能直接操作搜索结果")
        screenshot(app, "书房-从根页面搜索书架")
        result.tap()
        XCTAssertTrue(app.buttons["detail.reading"].waitForExistence(timeout: 5))
    }

    func testReaderToolsAndTypographyRemainAvailable() {
        let app = launch("reader")
        let preferences = app.buttons["reader.preferences"]
        XCTAssertTrue(preferences.waitForExistence(timeout: 15))
        screenshot(app, "专注-阅读工具栏")
        preferences.tap()
        XCTAssertTrue(app.navigationBars["阅读排版"].waitForExistence(timeout: 5))
        let font = app.buttons["系统字体"]
        let panel = app.scrollViews.containing(.staticText, identifier: "让这一页更舒服").firstMatch
        revealInScrollView(font, in: panel, "阅读排版面板中的系统字体应可点按")
        XCTAssertTrue(font.isSelected)
        app.buttons["完成"].tap()
        XCTAssertTrue(app.buttons["reader.contents"].waitForExistence(timeout: 5))
        app.buttons["reader.contents"].tap()
        XCTAssertTrue(app.navigationBars["目录与摘记"].waitForExistence(timeout: 5))
    }

    func testPagedReaderChromeDoesNotReflowOrMoveReadingPosition() throws {
        let app = launch("reader")
        let more = app.buttons["reader.more"]
        XCTAssertTrue(more.waitForExistence(timeout: 15))
        waitForReadingCondition({ more.isHittable }, "阅读工具应显示且可点按")
        let capture = { self.nativeLayout(in: app) }
        let first = try captureReaderLayout(capture)
        tapReadingEdge(next: true, in: app, frame: first.viewport)
        waitForReadingCondition({ capture().map { $0.text != first.text } == true }, "必须实际翻到另一页正文")
        let reading = try captureReaderLayout(capture)
        XCTAssertEqual(app.staticTexts["reader.currentChapter"].label, "1 / 2", "应在章内非首页验证分页稳定")
        try assertReaderChromePreservesLayout(in: app, baseline: reading, capture: capture, name: "固定正文-分页")
        tapReadingEdge(next: false, in: app, frame: reading.viewport)
        waitForReadingCondition({ capture()?.text == first.text }, "工具开关后上一页应回到原来那一页文字")
    }

    func testDarkHomeAndShelfKeepPrimaryActionsReachable() {
        // 根页面即书架：夜间断言直接在书房做，不再经 navigation.tab.0 切页签。
        let app = launch("shelf", appearance: "dark")
        XCTAssertTrue(app.buttons["study.heroContinue"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["study.heroFocus"].isHittable)
        screenshot(app, "书房-夜间首页")
        XCTAssertTrue(app.buttons["shelf.organize"].waitForExistence(timeout: 5))
        reveal(app.buttons["book.detail.ui-long"], in: app)
        screenshot(app, "书房-夜间书架")
    }

    func testShelfOrganizeAndDetailsAreExplicit() {
        let app = launch("shelf")
        let organize = app.buttons["shelf.organize"]
        XCTAssertTrue(organize.waitForExistence(timeout: 15))
        // 小屏上首本书位于页首与英雄卡下方、初始不在可视区，先滚动到位再断言。
        reveal(app.buttons["book.detail.ui-long"], in: app)
        XCTAssertTrue(app.buttons["book.detail.ui-long"].isHittable)
        screenshot(app, "书架-文字整理与详情入口")
        organize.tap()
        XCTAssertTrue(app.buttons["取消整理"].waitForExistence(timeout: 5))
        app.buttons["取消整理"].tap()
        reveal(app.buttons["book.detail.ui-long"], in: app)
        app.buttons["book.detail.ui-long"].tap()
        let reading = app.buttons["detail.reading"]
        XCTAssertTrue(reading.waitForExistence(timeout: 5))
        XCTAssertEqual(reading.label, "打开", "v31 详情主动作应明确打开书籍")
        XCTAssertEqual(app.staticTexts["detail.readingProgress"].label, "读至第 1 章", "已读书籍仍须明确显示续读位置")
        XCTAssertTrue(reading.isHittable)
        XCTAssertTrue(app.buttons["detail.listen"].isHittable)
        XCTAssertLessThan(reading.frame.minY, app.buttons["detail.listen"].frame.minY)
        XCTAssertGreaterThanOrEqual(reading.frame.height, 44)
        reading.tap()
        XCTAssertTrue(app.buttons["reader.contents"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["reader.currentChapter"].label, "1 / 2", "打开应恢复本书阅读进度")
    }

    func testPlayerCanScrubSentencesAndKeepPaused() {
        let app = launch("player")
        // 句子进度是自定义刻度轨（非系统 Slider），用与真实手指相同的坐标拖动手势验证。
        let scrubber = app.descendants(matching: .any)["player.sentence-progress"]
        XCTAssertTrue(scrubber.waitForExistence(timeout: 15))
        let toggle = app.buttons["player.toggle"]
        XCTAssertTrue(toggle.label.contains("继续朗读"))
        waitForReadingCondition({ app.staticTexts["player.readingStatus"].isHittable }, "跟读状态应固定在卡片顶部，不随长句滚出视口")
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
        waitForReadingCondition({ app.staticTexts["player.readingStatus"].isHittable }, "跟读状态应固定在卡片顶部，不随长句滚出视口")
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
        let tools = app.scrollViews["player.tools"]
        XCTAssertTrue(tools.waitForExistence(timeout: 5))
        XCTAssertEqual(tools.value as? String, "辅助功能字号", "必须实际进入辅助功能字号布局，紧凑高度分支不能代替")
        screenshot(app, "播放器-最大字号长书名")
        XCTAssertTrue(toggle.isHittable, "最大字号下播放控制也应固定可见")
        XCTAssertEqual(toggle.frame.midX, app.frame.midX, accuracy: 2, "跳句文字放大后不能把播放键挤偏")
        screenshot(app, "播放器-最大字号播放控制")
        // Scroll within the content area: swiping the sheet itself can dismiss the player.
        XCTAssertTrue(tools.exists)
        let contents = app.buttons["player.contents"]
        for _ in 0..<10 {
            if contents.isHittable { break }
            tools.swipeUp()
        }
        XCTAssertTrue(contents.isHittable, "最大字号下目录必须能从播放器内容区滚动到达")
        contents.tap()
        XCTAssertTrue(app.navigationBars["听书目录"].waitForExistence(timeout: 5))
    }

    func testLargestTypeHomeAndShelfActionsRemainReachable() {
        let app = launch("shelf", largeType: true)
        let read = app.buttons["study.heroContinue"]
        XCTAssertTrue(read.waitForExistence(timeout: 15))
        reveal(read, in: app)
        screenshot(app, "书房-最大字号")
        // 旧三页签已删除：「我的」是根页面右上角的单一入口（study.openProfile），书库就是根页面本身。
        let profile = app.buttons["study.openProfile"]
        XCTAssertEqual(profile.label, "我的")
        XCTAssertTrue(profile.isHittable)
        let organize = app.buttons["shelf.organize"]
        reveal(organize, in: app)
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
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label == %@", "从当前阅读位置听")).count, 0,
                       "辅助听书只应收在更多面板，不能在底面板重复暴露")
        openReaderMorePanel(app, expect: "从当前阅读位置听")
        let start = app.buttons["从当前阅读位置听"]
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label == %@", "从当前阅读位置听")).count, 1,
                       "打开更多后全界面也只能有一个同名动作")
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
            if toggle.label.contains("暂停") { toggle.tap(); waitForReadingCondition({ toggle.label.contains("继续") }, "暂停应已生效") }
            XCTAssertTrue(toggle.waitForExistence(timeout: 2), "暂停后快捷条必须保持，后续点击不能穿透正文")
            XCTAssertEqual(toggle.frame, toggleFrame, "暂停与继续不能移动快捷条")
            toggle.tap()
            waitForReadingCondition({ toggle.label.contains("暂停") }, "继续播放应已生效")
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
        waitForReadingCondition({ app.staticTexts["reader.currentChapter"].label == "2 / 2" }, "章节导航应已完成")
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
        waitForReadingCondition({ app.buttons["reader.toggle"].label.contains("暂停") }, "继续声音应已生效")
        XCTAssertEqual(app.staticTexts["reader.currentChapter"].label, "2 / 2", "继续声音也不能擅自开启跟随")
        app.buttons["reader.toggle"].tap()
        app.buttons["reader.back"].tap()
        // 退出阅读器回到书房根页，重开走正在读大卡（原 continue.reading 已随 Now 页删除）。
        XCTAssertTrue(app.buttons["study.heroContinue"].waitForExistence(timeout: 5))
        app.buttons["study.heroContinue"].tap()
        XCTAssertTrue(app.buttons["reader.contents"].waitForExistence(timeout: 5))
        waitForReadingCondition({ app.staticTexts["reader.currentChapter"].label == "2 / 2" }, "退出重开应恢复独立阅读断点")
        app.buttons["reader.returnToSpeech"].tap()
        XCTAssertEqual(app.staticTexts["reader.currentChapter"].label, "1 / 2")
        screenshot(app, "阅读优先-固定阅读工具与独立听书进度")
    }

    func testOriginalReaderKeepsFollowingThroughRepeatedPlaybackToggles() throws {
        let app = launch("reader-original", original: true)
        let web = epubWeb(in: app)
        waitForOriginalChapter("第一章 · 纸上的风景", in: web, app: app)
        app.buttons["reader.listen"].tap()
        XCTAssertTrue(app.buttons["player.collapse"].waitForExistence(timeout: 10))
        app.buttons["player.collapse"].tap()
        let toggle = app.buttons["reader.toggle"], follow = app.buttons["reader.returnToSpeech"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        let frame = toggle.frame
        for _ in 0..<3 {
            waitForReadingCondition({ follow.value as? String == "跟读高亮" }, "EPUB 正文应有句级跟读高亮")
            if toggle.label.contains("暂停") { toggle.tap() }
            waitForReadingCondition({ toggle.label.contains("继续") && follow.value as? String == "无跟读高亮" }, "暂停应清除 TTS 高亮")
            XCTAssertEqual(toggle.frame, frame)
            toggle.tap()
            waitForReadingCondition({ toggle.label.contains("暂停") && follow.value as? String == "跟读高亮" }, "继续应恢复 TTS 高亮")
            XCTAssertEqual(toggle.frame, frame)
        }
        toggle.tap()
        waitForReadingCondition({ toggle.label.contains("继续") && follow.value as? String == "无跟读高亮" }, "暂停应完成")
        openEPUBChapter("第二章 · 安静的回声", in: app)
        waitForOriginalChapter("第二章 · 安静的回声", in: web, app: app)
        app.buttons["reader.returnToSpeech"].tap()
        waitForReadingCondition({ app.staticTexts["reader.currentTitle"].label == "第一章 · 纸上的风景" }, "阅读跳章不应 seek 声音，回到朗读仍应在第一章")
        XCTAssertFalse(app.buttons["player.toggle"].exists)
    }

    func testReaderNotesAndSearchOpenWithoutStartingAudio() {
        let app = launch("reader")
        XCTAssertTrue(app.buttons["reader.notes"].waitForExistence(timeout: 15))
        openReaderNotesAndReturn(in: app)
        XCTAssertFalse(app.buttons["reader.toggle"].exists)
        // 顶栏直达书内搜索，不经过二级弹层，也不触发音频。
        let searchButton = app.buttons["reader.search"]
        XCTAssertTrue(searchButton.waitForExistence(timeout: 5))
        XCTAssertTrue(searchButton.isHittable)
        searchButton.tap()
        let field = app.searchFields["搜索章节与全文"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertTrue(field.isHittable, "激活搜索后应直接显示可输入的搜索框")
        XCTAssertTrue(app.buttons["章节"].isSelected, "书内搜索应打开章节与全文结果")
        field.tap()
        field.typeText("第二章")
        XCTAssertTrue(app.staticTexts["reader.searchResultCount"].waitForExistence(timeout: 5))
        // 搜索态收起页首介绍与分栏，首条结果直接落在键盘上方；避免对被键盘覆盖的列表做 swipeUp 误触键盘。
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
        openReaderMorePanel(app, expect: "切换夜间纸色")
        let sheet = app.scrollViews["reader.moreSheet"]
        sheet.buttons["切换夜间纸色"].tap()
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 5))
        openReaderMorePanel(app, expect: "切换日间纸色")
        screenshot(app, "功能键-更多阅读操作与夜间切换")
    }

    func testShelfSeparatesFilterSortAndLayoutAndProtectsDeletion() {
        let app = launch("shelf")
        // SwiftUI Menu 可出现在快照的 Button 或 PopUpButton 下。
        func tools(_ id: String) -> XCUIElementQuery {
            app.descendants(matching: .any).matching(identifier: id)
        }
        let filter = tools("shelf.filter").firstMatch
        let sort = tools("shelf.sort").firstMatch
        let layout = tools("shelf.layout").firstMatch
        XCTAssertTrue(filter.waitForExistence(timeout: 15))
        // 「更多」在分类栏，筛选、排序和视图在下一行。分别滚动到每个目标再检查。
        for id in ["shelf.more", "shelf.filter", "shelf.sort", "shelf.layout"] {
            let query = tools(id)
            let control = query.firstMatch
            reveal(control, in: app)
            XCTAssertEqual(query.count, 1, id)
            XCTAssertTrue(control.elementType == .button || control.elementType == .popUpButton, id)
            XCTAssertTrue(control.isHittable, id)
        }
        // 新版添加入口位于书目末尾，浏览工具仍固定在列表前。
        XCTAssertEqual(app.buttons.matching(identifier: "import.book").count, 1)
        let add = app.buttons["import.book"]
        reveal(add, in: app)
        XCTAssertTrue(add.isHittable)
        for _ in 0..<10 {
            if filter.isHittable { break }
            app.swipeDown()
        }
        XCTAssertTrue(filter.isHittable)
        filter.tap()
        app.buttons["待读"].tap()
        XCTAssertTrue(app.buttons["shelf.clearFilters"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["book.detail.ui-long"].exists)
        XCTAssertEqual(tools("shelf.sort").count, 1, "筛选后不能复制一份浏览工具")
        let clear = app.buttons["shelf.clearFilters"]
        reveal(clear, in: app)
        clear.tap()
        reveal(sort, in: app)
        sort.tap()
        app.buttons["书名"].tap()
        XCTAssertTrue(sort.label.contains("书名"))
        reveal(layout, in: app)
        layout.tap()
        app.buttons["封面网格"].tap()
        XCTAssertTrue(layout.label.contains("网格"))
        screenshot(app, "功能键-书架筛选排序与显示分层")
        app.buttons["shelf.organize"].tap()
        XCTAssertFalse(app.buttons["shelf.delete"].isEnabled)
        app.buttons["shelf.selectAll"].tap()
        XCTAssertTrue(app.buttons["shelf.move"].isEnabled)
        app.buttons["shelf.delete"].tap()
        XCTAssertTrue(app.buttons["删除本机副本"].waitForExistence(timeout: 5))
        cancelConfirmation(in: app)
        app.buttons["shelf.finishOrganizing"].tap()
        reveal(app.buttons["book.detail.ui-long"], in: app)
        XCTAssertTrue(app.buttons["book.detail.ui-long"].waitForExistence(timeout: 5), "取消删除应保留书籍")
    }

    func testPlayerToolsAreDirectAndPreservePausedState() throws {
        let app = launch("player")
        XCTAssertTrue(app.buttons["player.voice"].waitForExistence(timeout: 15))
        let ids = ["player.contents", "player.rate", "player.voice", "player.sleep"]
        let positions = ids.map { app.buttons[$0].frame.midX }
        XCTAssertEqual(positions, positions.sorted())
        for id in ids { XCTAssertTrue(app.buttons[id].isHittable) }
        app.buttons["player.voice"].tap()
        XCTAssertTrue(app.navigationBars["声音与朗读"].waitForExistence(timeout: 5))
        let save = app.buttons["voice.save"]
        let lists = app.collectionViews.allElementsBoundByIndex.filter { $0.frame.height > 200 }
        let list = lists.max { $0.frame.height < $1.frame.height } ?? app
        // 最后一行是懒加载的，系统按钮标签又会是 AirPlay 或「隔空播放」。先滚到底再按固定标识找。
        var route = audioOutput(in: app, above: save)
        for _ in 0..<12 {
            if let route { break }
            list.swipeUp()
            route = audioOutput(in: app, above: save)
        }
        let found = try XCTUnwrap(route, "音频输出应露在保存栏上方")
        XCTAssertTrue(found.isHittable, "音频输出应露在保存栏上方")
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
        XCTAssertTrue(app.buttons["shelf.organize"].waitForExistence(timeout: 5), "结束听书后应回到书库根页面（旧页签已删除）")
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
            // 边距口径以代码为准：构建 136 起底部工具面板贴边全宽，chapterBar 工具格的水平内边距就是 16
            // （ReaderView.chapterBar 的 .padding(.horizontal, 16)）；云端实测 minX 恰为 16.0，
            // 原阈值 20 是旧浮层面板时期的口径，已过期。此处仍要求按钮完整落在 16 边距内、不被撑出屏幕。
            XCTAssertGreaterThanOrEqual(button.frame.minX, 16)
            XCTAssertLessThanOrEqual(button.frame.maxX, app.frame.maxX - 16, "大字号不能把工具面板撑出水平边距")
        }
        XCTAssertLessThanOrEqual(app.buttons["reader.bookmark"].frame.maxX, app.frame.maxX - 12)
        screenshot(app, "功能键-最大字号阅读工具")
        openReaderMorePanel(app, expect: "切换夜间纸色")
    }

    func testMarginProfileAndReadingStatsRemainAvailable() {
        let app = launch("stats")
        let settings = app.buttons["profile.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 15))
        // 「我的」在新结构里不用系统导航栏：StatsView(ji) 自绘页眉（构建 135 起 ji 版隐藏系统导航栏、
        // 无系统返回箭头），目的地标志是页眉的「我的」标题与它专属的返回按钮 study.profileBack，
        // app.navigationBars["我的"] 在此结构下不存在，原断言落点错误。
        XCTAssertTrue(app.staticTexts["我的"].exists, "当前目的地应是「我的」（旧页签已删除）")
        XCTAssertTrue(app.buttons["study.profileBack"].exists, "「我的」页眉应带返回书库的按钮")
        let statistics = app.buttons["profile.stats"]
        XCTAssertTrue(statistics.isHittable)
        statistics.tap()
        XCTAssertTrue(app.navigationBars["阅读足迹"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["按日查看"].isSelected)
        screenshot(app, "听页-阅读足迹")
        app.navigationBars["阅读足迹"].buttons.firstMatch.tap()
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
    }

    func testMarginAppearanceKeepsReadingTypographyIndependent() {
        let app = launch("stats")
        let settings = app.buttons["profile.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 15))
        settings.tap()
        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 5))
        let appearance = app.buttons["profile.appearance"]
        reveal(appearance, in: app)
        appearance.tap()
        XCTAssertTrue(app.navigationBars["外观"].waitForExistence(timeout: 5))
        waitForReadingCondition({ app.buttons["appearance.light"].isSelected }, "浅色外观选择应在界面更新后生效")
        app.buttons["appearance.dark"].tap()
        waitForReadingCondition({ app.buttons["appearance.dark"].isSelected }, "深色外观选择应在界面更新后生效")
        screenshot(app, "听页-夜间外观选择")
        app.navigationBars["外观"].buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 5))
        let reading = app.buttons["profile.reading"]
        reveal(reading, in: app)
        reading.tap()
        XCTAssertTrue(app.navigationBars["阅读排版"].waitForExistence(timeout: 5))
        reveal(app.buttons["系统字体"], in: app)
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
        waitForReadingCondition({ app.buttons["appearance.light"].isSelected }, "浅色外观选择应在界面更新后生效")
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
        let web = epubWeb(in: app)
        waitForOriginalChapter("第一章 · 纸上的风景", in: web, app: app)
        for id in ["reader.back", "reader.bookmark", "reader.contents", "reader.listen", "reader.preferences"] {
            XCTAssertTrue(app.buttons[id].isHittable)
        }
        app.buttons["reader.preferences"].tap()
        XCTAssertTrue(app.navigationBars["阅读排版"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["系统字体"].isSelected)
        revealAboveDone(app.buttons["旧书"], in: app)
        app.buttons["旧书"].tap()
        XCTAssertTrue(app.buttons["旧书"].isSelected)
        app.buttons["完成"].tap()
        waitForOriginalChapter("第一章 · 纸上的风景", in: web, app: app)
        openEPUBChapter("第二章 · 安静的回声", in: app)
        waitForOriginalChapter("第二章 · 安静的回声", in: web, app: app)
        app.buttons["reader.preferences"].tap()
        XCTAssertTrue(app.navigationBars["阅读排版"].waitForExistence(timeout: 5))
        revealAboveDone(app.buttons["旧书"], in: app)
        XCTAssertTrue(app.buttons["旧书"].isSelected)
        app.buttons["完成"].tap()
        app.buttons["reader.back"].tap()
        XCTAssertTrue(app.buttons["study.heroContinue"].waitForExistence(timeout: 10))
    }

    func testOriginalReaderDarkModeKeepsChapterControlsReachable() {
        let app = launch("reader-original", appearance: "dark", original: true)
        let web = epubWeb(in: app)
        waitForOriginalChapter("第一章 · 纸上的风景", in: web, app: app)
        for id in ["reader.back", "reader.bookmark", "reader.contents", "reader.preferences"] { XCTAssertTrue(app.buttons[id].isHittable) }
        openEPUBChapter("第二章 · 安静的回声", in: app)
        waitForOriginalChapter("第二章 · 安静的回声", in: web, app: app)
        openEPUBChapter("第一章 · 纸上的风景", in: app)
        waitForOriginalChapter("第一章 · 纸上的风景", in: web, app: app)
        screenshot(app, "EPUB-夜间目录导航")
    }

    func testOriginalReaderChromeDoesNotResizeOrMoveItsColumn() throws {
        let app = launch("reader-original", original: true)
        let web = epubWeb(in: app)
        waitForOriginalChapter("第一章 · 纸上的风景", in: web, app: app)
        let capture = { self.epubLayout(in: app) }
        let first = try captureReaderLayout(capture)
        let turns = try XCTUnwrap(advanceToTextPage(in: app, capture: capture, differentFrom: first),
                                  "未能翻到与首屏不同的正文页（首屏页码标记：\(first.text.joined(separator: ","))）")
        let reading = try captureReaderLayout(capture)
        XCTAssertNotEqual(reading.text, first.text)
        for visible in [false, true, false, true] {
            setEPUBTools(visible, in: app, web: web)
            let current = try captureReaderLayout(capture)
            XCTAssertEqual(current.text, reading.text, "工具显隐不能换掉当前页文字")
            XCTAssertTrue(current.nearlyEquals(reading), "工具显隐不能移动或收缩 EPUB 正文栏")
        }
        for _ in 0..<turns { web.swipeRight() }
        waitForOriginalChapter("第一章 · 纸上的风景", in: web, app: app)
        XCTAssertFalse(app.buttons["player.toggle"].exists)
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
        waitForReadingCondition({
            guard let page = capture()?.pdf["page"] as? NSNumber else { return false }
            return page != first.pdf["page"] as? NSNumber
        }, "PDFKit 必须实际进入另一页")
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
    private func cancelSystemBookPicker(_ app: XCUIApplication) {
        let files = XCUIApplication(bundleIdentifier: "com.apple.DocumentsApp")
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let surfaces = [app, files, springboard]
        let predicate = NSPredicate(format: "label == '取消' OR label == 'Cancel'")
        let deadline = Date().addingTimeInterval(15)
        var cancel: XCUIElement?
        while cancel == nil, Date() < deadline {
            for surface in surfaces {
                let button = surface.buttons.matching(predicate).firstMatch
                if button.exists {
                    cancel = button
                    break
                }
            }
            if cancel == nil { RunLoop.current.run(until: Date().addingTimeInterval(0.4)) }
        }
        guard let button = cancel else {
            XCTFail("系统文件选择器应已打开，并能取消")
            return
        }
        let frame = button.frame
        if frame.width > 1, frame.height > 1 {
            button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        } else {
            button.tap()
        }
    }

    func testSystemFilePickerPresentsFromSources() throws {
        let app = launch("sources-file-import")
        let single = app.buttons["sources.importFile"]
        XCTAssertTrue(single.waitForExistence(timeout: 15))
        XCTAssertTrue(single.isHittable)
        single.tap()
        // 选择器可能在宿主里，也可能在打开后才出现的系统文件进程里。
        let files = XCUIApplication(bundleIdentifier: "com.apple.DocumentsApp")
        func pickerElement() -> XCUIElement? {
            let predicate = NSPredicate(format: "label == '取消' OR label == 'Cancel'")
            let deadline = Date().addingTimeInterval(12)
            while Date() < deadline {
                let surfaces = [app] + (files.state == .notRunning ? [] : [files])
                for surface in surfaces {
                    let match = surface.buttons.matching(predicate).firstMatch
                    guard match.exists else { continue }
                    let frame = match.frame
                    if frame.width > 1, frame.height > 1 { return match }
                }
                RunLoop.current.run(until: Date().addingTimeInterval(0.25))
            }
            return nil
        }
        let cancel = try XCTUnwrap(pickerElement(), "系统文件选择器应已打开")
        screenshot(app, "系统单选导入-文件选择器", wholeScreen: true)
        cancel.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        // 根选择器会先关闭添书面板。取消后从书库重新打开添书，验证入口可再次使用。
        let profile = app.buttons["study.openProfile"]
        waitForReadingCondition({ profile.exists && profile.isHittable }, "取消文件选择后应回到书库")
        let add = app.buttons["import.book"]
        revealInScrollView(add, in: app.scrollViews.firstMatch, "取消后仍可打开添书面板")
        add.tap()
        waitForReadingCondition({ single.exists && single.isHittable }, "取消后选择文件入口仍可点按")
    }

    func testBatchCancelThenSingleAndResultsRetryUseOneRootPicker() {
        let app = launch("sources-file-import")
        let batch = app.buttons["sources.importBatch"]
        XCTAssertTrue(batch.waitForExistence(timeout: 15))
        reveal(batch, in: app); batch.tap()
        cancelSystemBookPicker(app)
        let add = app.buttons["import.book"]
        XCTAssertTrue(add.waitForExistence(timeout: 10)); reveal(add, in: app); add.tap()
        let single = app.buttons["sources.importFile"]
        XCTAssertTrue(single.waitForExistence(timeout: 10)); single.tap()
        cancelSystemBookPicker(app)
        XCTAssertTrue(app.buttons["study.openProfile"].waitForExistence(timeout: 10))
        app.terminate()
        let resultApp = launch("import-results")
        let results = resultApp.buttons["import.results"]
        XCTAssertTrue(results.waitForExistence(timeout: 20)); results.tap()
        let retry = resultApp.buttons["import.retrySelection"]
        XCTAssertTrue(retry.waitForExistence(timeout: 10)); reveal(retry, in: resultApp); retry.tap()
        cancelSystemBookPicker(resultApp)
        XCTAssertTrue(resultApp.buttons["study.openProfile"].waitForExistence(timeout: 10), "结果 sheet 应先关闭，再由根选择器接管")
        screenshot(resultApp, "结果重选-取消回书库")
    }
}
