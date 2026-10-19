import XCTest

/// 使用 DEBUG 临时书库；不依赖现有阅读记录，不调用付费语音或 iCloud。
@MainActor
final class DesignFlowTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func launch(_ scene: String, largeType: Bool = false, appearance: String = "light") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-fixture", "-uireview", scene, "-ui-reduce-motion", "-app.appearance", appearance, "-privacy.appLock", "NO", "-reader.font", "system", "-reader.paper", "paper", "-reader.original", "NO", "-shelf.layout", "list"]
        if largeType { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        return app
    }
    private func screenshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<10 {
            if element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
    }

    func testHomeShowsContinueAndRecentWithoutScrolling() {
        let app = launch("now")
        let read = app.buttons["continue.reading"]
        XCTAssertTrue(read.waitForExistence(timeout: 15))
        XCTAssertTrue(read.isHittable)
        XCTAssertTrue(app.buttons["now.listen"].isHittable)
        XCTAssertTrue(read.label.contains("继续阅读"))
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
        XCTAssertTrue(app.buttons["book.detail.ui-long"].exists)
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
        app.buttons["navigation.tab.1"].tap()
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
        let slider = app.sliders["player.sentence-progress"]
        XCTAssertTrue(slider.waitForExistence(timeout: 15))
        let toggle = app.buttons["player.toggle"]
        XCTAssertTrue(toggle.label.contains("继续朗读"))
        let original = slider.value as? String
        slider.adjust(toNormalizedSliderPosition: 0.65)
        XCTAssertNotEqual(slider.value as? String, original)
        XCTAssertTrue((slider.value as? String)?.contains("句") == true)
        XCTAssertTrue(toggle.label.contains("继续朗读"), "拖动不能擅自恢复已暂停的朗读")
        let scrubbed = slider.value as? String
        app.buttons["player.nextSentence"].tap()
        XCTAssertNotEqual(slider.value as? String, scrubbed)
        toggle.tap()
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertTrue(toggle.label.contains("暂停朗读"))
        toggle.tap()
        XCTAssertTrue(toggle.label.contains("继续朗读"))
        screenshot(app, "播放器-句子拖动与暂停")
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
        for (index, label) in ["今日", "书架", "足迹", "设置"].enumerated() {
            XCTAssertEqual(app.buttons["navigation.tab.\(index)"].label, label)
        }
        app.buttons["navigation.tab.1"].tap()
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
}
