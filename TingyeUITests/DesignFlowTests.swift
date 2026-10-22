import XCTest

/// 使用 DEBUG 临时书库；不依赖现有阅读记录，不调用付费语音或 iCloud。
@MainActor
final class DesignFlowTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func launch(_ scene: String, largeType: Bool = false, appearance: String = "light") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-fixture", "-ui-reset-preferences", "-uireview", scene, "-ui-reduce-motion", "-ui-appearance", appearance, "-privacy.appLock", "NO", "-reader.font", "system", "-reader.original", "NO", "-reader.scrolling", "NO", "-shelf.kind", "books", "-voice.rate", "1.0", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
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

    func testHomeShowsContinueAndRecentWithoutScrolling() {
        let app = launch("now")
        let read = app.buttons["continue.reading"]
        XCTAssertTrue(read.waitForExistence(timeout: 15))
        XCTAssertTrue(read.isHittable)
        XCTAssertTrue(app.buttons["now.listen"].isHittable)
        XCTAssertTrue(read.label.contains("继续阅读"))
        XCTAssertEqual(read.frame.height, app.buttons["now.listen"].frame.height, accuracy: 1, "默认字号的读听按钮不应挤成两行")
        XCTAssertTrue(app.staticTexts["最近在读"].firstMatch.isHittable)
        screenshot(app, "今日-首屏续读与最近在读")
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
        XCTAssertTrue(app.buttons["继续阅读"].waitForExistence(timeout: 5))
    }

    func testPlayerCanScrubSentencesAndKeepPaused() {
        let app = launch("player")
        // 句子进度是自定义刻度轨（非系统 Slider），用与真实手指相同的坐标拖动手势验证。
        let scrubber = app.descendants(matching: .any)["player.sentence-progress"]
        XCTAssertTrue(scrubber.waitForExistence(timeout: 15))
        let toggle = app.buttons["player.toggle"]
        XCTAssertTrue(toggle.label.contains("继续朗读"))
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
        for (index, label) in ["书", "读", "己"].enumerated() {
            XCTAssertEqual(app.buttons["navigation.tab.\(index)"].label, label)
        }
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

    func testReaderKeepsActionSlotsAndChapterNavigationDoesNotSeekAudio() {
        let app = launch("reader")
        XCTAssertTrue(app.buttons["reader.listen"].waitForExistence(timeout: 15))
        let ids = ["reader.contents", "reader.preferences", "reader.more"]
        let positions = ids.map { app.buttons[$0].frame.midX }
        app.buttons["reader.listen"].tap()
        XCTAssertTrue(app.buttons["player.toggle"].waitForExistence(timeout: 5))
        if app.buttons["player.toggle"].label.contains("暂停") { app.buttons["player.toggle"].tap() }
        app.buttons["player.collapse"].tap()
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
        app.buttons["player.collapse"].tap()
        app.buttons["reader.returnToSpeech"].tap()
        XCTAssertEqual(app.staticTexts["reader.currentChapter"].label, "1 / 2")
        screenshot(app, "功能键-阅读固定四键与独立播放控制")
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
        for id in ["shelf.filter", "shelf.sort", "shelf.layout", "shelf.more", "import.book"] {
            XCTAssertEqual(app.buttons.matching(identifier: id).count, 1)
            XCTAssertTrue(app.buttons[id].isHittable)
        }
        app.buttons["shelf.filter"].tap()
        app.buttons["未读"].tap()
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
        XCTAssertTrue(app.navigationBars["声音设置"].waitForExistence(timeout: 5))
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
        for id in ["reader.contents", "reader.preferences", "reader.listen", "reader.more"] {
            let button = app.buttons[id]
            for _ in 0..<5 {
                if button.isHittable { break }
                tools.swipeUp()
            }
            XCTAssertTrue(button.isHittable)
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
        XCTAssertTrue(app.staticTexts["阅读足迹"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["按日查看"].isSelected)
        screenshot(app, "余白-阅读足迹")
        let appearance = app.buttons["profile.appearance"]
        reveal(appearance, in: app)
        appearance.tap()
        XCTAssertTrue(app.navigationBars["外观"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["appearance.light"].isSelected)
        app.buttons["appearance.dark"].tap()
        XCTAssertTrue(app.buttons["appearance.dark"].isSelected)
        screenshot(app, "余白-夜间外观选择")
        app.navigationBars.firstMatch.buttons.firstMatch.tap()
        let reading = app.buttons["profile.reading"]
        // Navigation restores the same list position.
        XCTAssertTrue(reading.waitForExistence(timeout: 5))
        reading.tap()
        XCTAssertTrue(app.navigationBars["阅读排版"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["系统字体"].isSelected, "外观切换不能改变正文的独立字体偏好")
        screenshot(app, "余白-夜间阅读排版")
        let paper = app.buttons["旧书"]
        revealAboveDone(paper, in: app)
        paper.tap()
        XCTAssertTrue(paper.isSelected)
        app.buttons["完成"].tap()
        reveal(appearance, in: app)
        appearance.tap()
        app.buttons["appearance.light"].tap()
        XCTAssertTrue(app.buttons["appearance.light"].isSelected)
        app.navigationBars.firstMatch.buttons.firstMatch.tap()
        reading.tap()
        XCTAssertTrue(app.navigationBars["阅读排版"].waitForExistence(timeout: 5))
        revealAboveDone(app.buttons["旧书"], in: app)
        XCTAssertTrue(app.buttons["旧书"].isSelected, "全局外观切换不能重置独立选择的纸色")
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
