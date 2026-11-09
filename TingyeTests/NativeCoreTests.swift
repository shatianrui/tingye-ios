import XCTest
import SwiftUI
import AVFoundation
import CoreText
@testable import Tingye

final class NativeCoreTests: XCTestCase {
    #if TINGYE_UNSIGNED
    @MainActor func testUnsignedBuildNeverOpensCloudStorageOrChecksAppleAccount() {
        let sync = ProgressSync(account: {
            XCTFail("Unsigned builds must not request the Apple account")
            return true
        })
        XCTAssertFalse(sync.enabled)
        XCTAssertFalse(sync.accountAvailable)
        sync.start { XCTFail("Unsigned builds must not install cloud observers") }
        XCTAssertTrue(sync.synchronize()) // disabled sync is a successful no-op
        XCTAssertFalse(sync.accountAvailable)
        XCTAssertThrowsError(try ICloudBackupStore.connected()) { error in
            XCTAssertEqual(error.localizedDescription, BuildCapabilities.cloudUnavailable)
        }
    }
    #endif

    @MainActor func testFocusTextContrastInBothAppearances() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let traits = UITraitCollection(userInterfaceStyle: style)
            let pairs: [(Color, Color)] = [(Theme.ink, Theme.bg), (Theme.ink2, Theme.bg), (Theme.ink3, Theme.bg),
                (Theme.accent, Theme.bg), (Theme.onClay, Theme.clay), (Theme.ink, Theme.readingHighlight), (Theme.ink3, Theme.surface2),
                (Theme.accent, Theme.accentSoft), (Theme.onInk, Theme.ink), (Theme.ink2, Theme.surface), (Theme.ink3, Theme.surface),
                (Theme.heroInk, Theme.hero), (Theme.ink2, Theme.hero), (Theme.accent, Theme.hero), (Theme.onMarker, Theme.marker)]
            for (text, background) in pairs {
                XCTAssertGreaterThanOrEqual(UIColor(text).resolvedColor(with: traits).contrastRatio(with: UIColor(background).resolvedColor(with: traits)), 4.5)
            }
        }
    }

    func testSMBAddressParsing() {
        XCTAssertEqual(SMBAccess.target("smb://192.168.1.10"), .init(host: "192.168.1.10", port: 445))
        XCTAssertEqual(SMBAccess.target("nas.local:1445"), .init(host: "nas.local", port: 1445))
        XCTAssertEqual(SMBAccess.target(" smb://NAS/Books "), .init(host: "NAS", port: 445))
        XCTAssertNil(SMBAccess.target("https://nas.local"))
        XCTAssertNil(SMBAccess.target("smb://"))
    }

    func testWiFiTransferRequiresToken() {
        let token = WiFiTransferServer.makeToken()
        XCTAssertEqual(token.count, 6)
        XCTAssertFalse(token.contains { "0o1il".contains($0) })
        XCTAssertEqual(TransferRoute.resolve("/\(token)", token: token), .page)
        XCTAssertEqual(TransferRoute.resolve("/\(token)/?from=qr", token: token), .page)
        XCTAssertEqual(TransferRoute.resolve("/\(token)/upload", token: token), .upload)
        XCTAssertEqual(TransferRoute.resolve("/", token: token), .forbidden)
        XCTAssertEqual(TransferRoute.resolve("/upload", token: token), .forbidden)
        XCTAssertEqual(TransferRoute.resolve("/wrong1/upload", token: token), .forbidden)
        XCTAssertEqual(TransferRoute.resolve("/", token: ""), .forbidden)
    }

    func testManualShelfOrderPutsNewBooksFirstAndMovesWithinVisible() {
        func entry(_ id: String, added: Double) -> ShelfEntry {
            var e = ShelfEntry(book: Book(id: id, title: id, format: "TXT", chapters: [Chapter(title: "一", text: "文")]))
            e.addedAt = added; return e
        }
        let rows = [entry("a", added: 1), entry("b", added: 2), entry("c", added: 3), entry("new", added: 9)]
        XCTAssertEqual(ManualShelfOrder.sorted(rows, kind: "books", order: ["c", "a", "b"]).map(\.id), ["new", "c", "a", "b"])
    }

    func testSelectionToolOrderAndVisibility() {
        XCTAssertEqual(SelectionTool.ordered(nil), [.mark, .note, .quote])
        XCTAssertEqual(SelectionTool.ordered(["引用", "未知", "标注"]), [.quote, .mark, .note], "未知项忽略，缺失项补在末尾")
        XCTAssertEqual(SelectionTool.visible(order: [.quote, .mark, .note], hidden: ["标注"]), [.quote, .note])
        XCTAssertEqual(SelectionTool.visible(order: [.mark, .note, .quote], hidden: ["标注", "笔记", "引用"]), [.mark, .note, .quote], "全部隐藏时退回全部显示")
    }

    func testStorageSizeCountsNestedFiles() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("storage-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("a/b"), withIntermediateDirectories: true)
        try Data(count: 10_000).write(to: folder.appendingPathComponent("a/b/x.bin"))
        try Data(count: 5_000).write(to: folder.appendingPathComponent("y.bin"))
        defer { try? FileManager.default.removeItem(at: folder) }
        XCTAssertGreaterThanOrEqual(StorageUsage.size(of: folder), 15_000)
        XCTAssertEqual(StorageUsage.size(of: folder.appendingPathComponent("missing")), 0)
        XCTAssertFalse(StorageUsage.Kind.library.clearable, "书库不能在空间整理里一键清掉")
    }

    func testCustomTTSEndpointAcceptsHttpsAndLocalHttpOnly() {
        XCTAssertEqual(CloudSpeech.customSpeechEndpoint("https://api.example.com/v1/")?.absoluteString, "https://api.example.com/v1/audio/speech")
        XCTAssertEqual(CloudSpeech.customSpeechEndpoint("https://api.example.com/v1/audio/speech")?.absoluteString, "https://api.example.com/v1/audio/speech")
        XCTAssertNotNil(CloudSpeech.customSpeechEndpoint("http://192.168.1.20:8000/v1"))
        XCTAssertNotNil(CloudSpeech.customSpeechEndpoint("http://localhost:8880/v1"))
        XCTAssertNotNil(CloudSpeech.customSpeechEndpoint("http://172.20.0.5/v1"))
        XCTAssertNil(CloudSpeech.customSpeechEndpoint("http://api.example.com/v1"), "公网明文 http 会泄露密钥")
        XCTAssertNil(CloudSpeech.customSpeechEndpoint("http://172.40.0.5/v1"))
        XCTAssertNil(CloudSpeech.customSpeechEndpoint("ftp://x/v1"))
        XCTAssertNil(CloudSpeech.customSpeechEndpoint("  "))
        let options = VoiceOptions.sanitized(provider: "custom", model: "", voice: "")
        XCTAssertEqual(options.model, "tts-1"); XCTAssertEqual(options.voice, "alloy")
        XCTAssertEqual(VoiceOptions.sanitized(provider: "custom", model: "kokoro", voice: "zf_xiaobei").voice, "zf_xiaobei")
    }

    @MainActor func testReadingCalendarPadsMonthToMonday() {
        var calendar = Calendar(identifier: .gregorian); calendar.firstWeekday = 2
        // 2026-10-01 是周四：前面补 3 个空位，共 31 天。
        let october = calendar.date(from: DateComponents(year: 2026, month: 10, day: 15))!
        let days = ReadingCalendarView.monthDays(october, calendar: calendar)
        XCTAssertEqual(days.prefix(3).filter { $0 == nil }.count, 3)
        XCTAssertNotNil(days[3])
        XCTAssertEqual(days.compactMap { $0 }.count, 31)
        XCTAssertEqual(ReadingCalendarView.intensity(minutes: 0, goal: 30), 0.25)
        XCTAssertEqual(ReadingCalendarView.intensity(minutes: 90, goal: 30), 1)
    }

    func testTxtCustomRuleAndMaxLengthSplitting() throws {
        let text = "【楔子】\n开篇。\n【其一】\n春。\n【其二】\n" + String(repeating: "很长的一段话。\n", count: 400)
        // 内置规则不认识【】标题：整本一章，但超长部分被切开。
        let builtIn = BookImporter.splitText(text, title: "书", maxLength: 1000)
        XCTAssertGreaterThan(builtIn.count, 1)
        XCTAssertTrue(builtIn.allSatisfy { $0.text.count <= 1000 })
        // 自定义规则按【】分章，最后一章超长再切。
        let rule = try XCTUnwrap(TxtChapterRules.compile(#"^\s*【.{1,40}】\s*$"#))
        let custom = BookImporter.splitText(text, title: "书", rule: rule, maxLength: 1000)
        XCTAssertEqual(Array(custom.prefix(3).map(\.title)), ["【楔子】", "【其一】", "【其二】（1）"])
        XCTAssertEqual(custom.filter { $0.title.hasPrefix("【其二】") }.map(\.text).joined(separator: "\n").count,
                       String(repeating: "很长的一段话。\n", count: 400).trimmingCharacters(in: .whitespacesAndNewlines).count)
        XCTAssertNil(TxtChapterRules.compile("第(章"), "非法正则不应编译通过")
        XCTAssertNil(TxtChapterRules.compile("   "))
    }

    func testReadingReminderSkipsTodayWhenGoalMetOrTimePassed() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let morning = calendar.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 9))!
        let night = calendar.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 22))!
        let at21 = 21 * 60
        // 早上、未达标：从今天 21:00 起排 7 天。
        var dates = ReadingReminder.plannedDates(now: morning, minutes: at21, todayMet: false, calendar: calendar)
        XCTAssertEqual(dates.count, 7)
        XCTAssertEqual(calendar.component(.day, from: dates[0]), 22)
        XCTAssertEqual(calendar.component(.hour, from: dates[0]), 21)
        // 今天已读够：今天不提醒，仍排满 7 天。
        dates = ReadingReminder.plannedDates(now: morning, minutes: at21, todayMet: true, calendar: calendar)
        XCTAssertEqual(dates.count, 7)
        XCTAssertEqual(calendar.component(.day, from: dates[0]), 23)
        // 今天时刻已过：从明天开始。
        dates = ReadingReminder.plannedDates(now: night, minutes: at21, todayMet: false, calendar: calendar)
        XCTAssertEqual(calendar.component(.day, from: dates[0]), 23)
        XCTAssertEqual(calendar.component(.day, from: dates[6]), 29)
    }

    @MainActor func testQuoteShareCardRendersFixedWidthImage() throws {
        let card = QuoteShareCard(text: "真正重要的东西，用眼睛是看不见的。", title: "小王子", author: "圣埃克苏佩里", chapter: "第二十一章")
        let image = try XCTUnwrap(card.render())
        XCTAssertEqual(image.size.width, 900, accuracy: 1)
        XCTAssertGreaterThanOrEqual(image.size.height, 1125)
        XCTAssertEqual(image.scale, 2)
        // 超长摘句向下延展，不截断。
        let long = try XCTUnwrap(QuoteShareCard(text: String(repeating: "很长的一句话，", count: 40), title: "长").render())
        XCTAssertGreaterThan(long.size.height, image.size.height)
        if let dir = ProcessInfo.processInfo.environment["SIMULATOR_HOST_HOME"] {
            try? image.pngData()?.write(to: URL(fileURLWithPath: dir).appendingPathComponent("Desktop/tingye-ios/build/quote-card-sample.png"))
        }
    }

    @MainActor func testReadingStreakCountsConsecutiveDaysAndKeepsTodayOpen() {
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 9))!
        func key(_ offset: Int) -> String { AppModel.dayKey(calendar.date(byAdding: .day, value: offset, to: today)!) }
        // 昨天、前天连续；今天未读：当前连续 2 天，不归零。
        var seconds = [key(-1): 600.0, key(-2): 120, key(-4): 900, key(-5): 900, key(-6): 900, key(-7): 30]
        var streak = AppModel.readingStreak(seconds, today: today, calendar: calendar)
        XCTAssertEqual(streak.current, 2)
        XCTAssertEqual(streak.longest, 3, "不足一分钟的那天不计入")
        // 今天读满一分钟后连续变 3 天。
        seconds[key(0)] = 60
        streak = AppModel.readingStreak(seconds, today: today, calendar: calendar)
        XCTAssertEqual(streak.current, 3)
        XCTAssertEqual(streak.longest, 3)
        // 断档两天：当前为 0，最长保留。
        streak = AppModel.readingStreak([key(-3): 300, key(-4): 300], today: today, calendar: calendar)
        XCTAssertEqual(streak.current, 0)
        XCTAssertEqual(streak.longest, 2)
        XCTAssertEqual(AppModel.readingStreak([:], today: today, calendar: calendar).longest, 0)
    }

    @MainActor func testFocusReadingPapersHaveReadableTextInBothAppearances() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let traits = UITraitCollection(userInterfaceStyle: style)
            for paper in ReaderPaper.allCases {
                let prefs = ReaderPreferences(paper: paper.rawValue)
                let background = UIColor(prefs.background).resolvedColor(with: traits)
                for text in [prefs.foreground, prefs.secondary] {
                    XCTAssertGreaterThanOrEqual(UIColor(text).resolvedColor(with: traits).contrastRatio(with: background), 4.5, paper.rawValue)
                }
            }
        }
    }

    func testFocusDefaultFontDoesNotReplaceExplicitReaderChoices() {
        XCTAssertEqual(ReaderPreferences().font, "system")
        let saved = ReaderPreferences(font: "serif", paper: "ancient")
        XCTAssertEqual(saved.font, "serif")
        XCTAssertEqual(saved.kind, .ancient)
        XCTAssertEqual(ReaderPreferences(font: "custom:MyFont").font, "custom:MyFont")
    }

    /// 内置阅读字体必须随包注册：字体文件缺失或 PostScript 名写错都会在这里暴露。
    func testBundledReaderFontsAreRegistered() {
        for (key, name) in ReaderPreferences.bundledFonts {
            XCTAssertNotNil(UIFont(name: name, size: 17), "\(key) 的内置字体不可用：\(name)")
            XCTAssertNotNil(ReaderPreferences(font: key).uiFont)
        }
    }

    @MainActor func testEveryCoverAndImageBackdropHasReadableSmallText() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let traits = UITraitCollection(userInterfaceStyle: style)
            for name in ["green", "red", "vermilion", "purple", "blue", "ink", "gold", "cream", "unknown"] {
                let foreground = UIColor(Theme.coverForeground(name)).resolvedColor(with: traits)
                XCTAssertGreaterThanOrEqual(foreground.contrastRatio(with: Theme.coverUIColor(name).resolvedColor(with: traits)), 4.5, name)
            }
        }
        for color in [UIColor.white, .yellow, .green, .red, .black, UIColor(hex: 0xFAF0E8)] {
            XCTAssertGreaterThanOrEqual(color.backgroundForWhiteText.contrastRatio(with: .white), 4.5)
        }
    }

    func testResumeActionTitlesAndPriorityFollowActualUse() {
        let fresh = ResumeActions(started: false, lastActivity: .reading, hasListened: false, playing: false)
        XCTAssertEqual(fresh.readingTitle, "开始阅读"); XCTAssertEqual(fresh.listeningTitle, "开始听书")
        XCTAssertFalse(fresh.prefersListening)
        let read = ResumeActions(started: true, lastActivity: .reading, hasListened: false, playing: false)
        XCTAssertEqual(read.readingTitle, "继续阅读"); XCTAssertEqual(read.listeningTitle, "听这本书")
        let heard = ResumeActions(started: true, lastActivity: .listening, hasListened: true, playing: false)
        XCTAssertFalse(heard.prefersListening); XCTAssertEqual(heard.listeningTitle, "继续听")
        XCTAssertEqual(heard.readingTitle, "继续阅读")
        let playing = ResumeActions(started: true, lastActivity: .reading, hasListened: true, playing: true)
        XCTAssertFalse(playing.prefersListening); XCTAssertEqual(playing.listeningTitle, "暂停朗读")
        let onlyHeard = ResumeActions(started: false, lastActivity: .listening, hasListened: true, playing: true)
        XCTAssertEqual(onlyHeard.readingTitle, "开始阅读", "听过不代表已打开正文")
        XCTAssertFalse(onlyHeard.prefersListening, "正在听也不能替换阅读主操作")
    }

    func testOldCatalogDefaultsToReadingAndKeepsOptionalActivity() throws {
        let book = Book(id: "activity-test", title: "行为", format: "TXT", chapters: [.init(title: "正文", text: "一。二。")])
        var row = ShelfEntry(book: book)
        let old = try JSONDecoder().decode(ShelfEntry.self, from: Integrity.encoder().encode(row))
        XCTAssertNil(old.lastActivity); XCTAssertNil(old.hasListened)
        XCTAssertNil(old.listeningProgress); XCTAssertNil(old.lastReadAt)
        row.lastActivity = .listening; row.hasListened = true
        row.listeningProgress = .init(chapter: 0, position: 1, updatedAt: 200)
        row.lastReadAt = 100
        let restored = try JSONDecoder().decode(ShelfEntry.self, from: Integrity.encoder().encode(row))
        XCTAssertEqual(restored.lastActivity, .listening); XCTAssertEqual(restored.hasListened, true)
        XCTAssertEqual(restored.listeningProgress, row.listeningProgress)
        XCTAssertEqual(restored.lastReadAt, row.lastReadAt)
    }

    func testRemainingListeningTimeIsExplicitlyEstimatedAndRateAware() {
        XCTAssertEqual(SpeechEstimate.remainingLabel(characters: 270, rate: 1), "本章约剩 1 分钟")
        XCTAssertEqual(SpeechEstimate.remainingLabel(characters: 540, rate: 1), "本章约剩 2 分钟")
        XCTAssertEqual(SpeechEstimate.remainingLabel(characters: 540, rate: 2), "本章约剩 1 分钟")
        XCTAssertEqual(SpeechEstimate.remainingLabel(characters: 1, rate: 1), "本章约剩不到 1 分钟")
        XCTAssertEqual(SpeechEstimate.remainingLabel(characters: 0, rate: 1), "本章暂无剩余文字")
        XCTAssertEqual(SpeechEstimate.remainingLabel(characters: 270, rate: .nan), "本章约剩 1 分钟")
    }

    @MainActor func testLastActivityPersistsWithoutChangingReadingPosition() async throws {
        try await withDesignModel { model, disk, _ in
            let book = Book(id: "mode", title: "方式", format: "TXT", chapters: [.init(title: "正文", text: "一。二。")])
            try await model.add(book)
            let original = try XCTUnwrap(model.entries.first).progress
            model.recordActivity(.listening, for: book.id)
            XCTAssertFalse(model.resumeActions(for: model.entries[0]).prefersListening)
            XCTAssertEqual(model.resumeActions(for: model.entries[0]).readingTitle, "开始阅读")
            XCTAssertNil(model.entries[0].lastReadAt)
            model.open(model.entries[0])
            XCTAssertFalse(model.resumeActions(for: model.entries[0]).prefersListening)
            XCTAssertEqual(model.resumeActions(for: model.entries[0]).listeningTitle, "继续听")
            model.flushPendingSaves()
            let saved = try XCTUnwrap(disk.catalog().first)
            XCTAssertEqual(saved.lastActivity, .reading); XCTAssertEqual(saved.hasListened, true)
            XCTAssertNotNil(saved.lastReadAt)
            XCTAssertEqual(saved.progress, original)
        }
    }

    @MainActor func testListeningCallbacksDoNotOverwriteReadingProgressOrICloud() async throws {
        let store = MemoryKeyValueStore()
        try await withDesignModel(syncStore: store) { model, disk, _ in
            let book = self.readingFirstBook("separate-sync")
            try await model.add(book)
            model.recordActivity(.reading, for: book.id)
            model.saveProgress(book.id, chapter: 1, position: 2)
            let before = try XCTUnwrap(model.entries.first)
            let synced = try JSONSerialization.data(withJSONObject: store.values, options: .sortedKeys)
            model.player.onProgress?(book.id, 0, 1)
            let after = try XCTUnwrap(model.entries.first)
            XCTAssertEqual(after.progress, before.progress, "声音回调不能覆盖正在阅读的位置或时间戳")
            XCTAssertEqual(after.lastReadAt, before.lastReadAt)
            XCTAssertEqual(after.listeningProgress?.chapter, 0)
            XCTAssertEqual(after.listeningProgress?.position, 1)
            XCTAssertEqual(model.readingRecency(for: after), model.readingRecency(for: before))
            XCTAssertEqual(try JSONSerialization.data(withJSONObject: store.values, options: .sortedKeys), synced,
                           "听书进度不能写入跨设备阅读位置")
            model.flushPendingSaves()
            let persisted = try XCTUnwrap(disk.catalog().first)
            XCTAssertEqual(persisted.progress, before.progress)
            XCTAssertEqual(persisted.listeningProgress, after.listeningProgress)
        }
    }

    @MainActor func testIndependentReadingAndListeningPositionsSurviveReload() async throws {
        try await withSystemVoice {
            try await self.withDesignModel { model, disk, _ in
                let book = self.readingFirstBook("separate-reload")
                try await model.add(book)
                model.recordActivity(.reading, for: book.id)
                model.saveProgress(book.id, chapter: 1, position: 2)
                model.saveListeningProgress(book.id, chapter: 0, position: 1)
                model.flushPendingSaves()
                let saved = try XCTUnwrap(disk.catalog().first)
                let suite = "tests.reading-reload." + UUID().uuidString
                let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
                defaults.set(false, forKey: ProgressSync.enabledKey)
                defer { defaults.removePersistentDomain(forName: suite) }
                let reopened = AppModel(disk: disk, progressSync: ProgressSync(store: MemoryKeyValueStore(), defaults: defaults, account: { false }))
                defer { reopened.player.stop(); reopened.flushPendingSaves() }
                let loaded = try await reopened.loadBook(book.id)
                reopened.startListening(loaded, openReader: false)
                reopened.player.pause()
                XCTAssertEqual(reopened.player.chapter, 0)
                XCTAssertEqual(reopened.player.position, 1, "重新启动听书应恢复独立的听书位置")
                reopened.open(try XCTUnwrap(reopened.entries.first))
                XCTAssertEqual(reopened.selectedBook?.id, book.id)
                XCTAssertEqual(reopened.entries.first?.progress, saved.progress,
                               "重新打开正文必须仍能恢复第2章的阅读位置")
                XCTAssertEqual(reopened.player.chapter, 0, "打开正文不能拖动声音位置")
                XCTAssertEqual(reopened.player.position, 1)
                XCTAssertNil(reopened.listeningReaderID)
            }
        }
    }

    @MainActor func testLegacyListeningFallsBackOnceThenKeepsItsOwnPosition() async throws {
        try await withSystemVoice {
            try await self.withDesignModel { model, _, _ in
                let book = self.readingFirstBook("legacy-listening")
                try await model.add(book, progress: .init(chapter: 1, position: 1, updatedAt: 100))
                XCTAssertNil(model.entries.first?.listeningProgress)
                model.startListening(book, openReader: false)
                model.player.pause()
                XCTAssertEqual(model.player.chapter, 1)
                XCTAssertEqual(model.player.position, 1, "旧书库没有听书字段时从原有阅读位置开始")
                XCTAssertEqual(model.entries.first?.listeningProgress?.position, 1)
                model.saveProgress(book.id, chapter: 0, position: 2)
                let reading = try XCTUnwrap(model.entries.first).progress
                model.player.stop()
                model.startListening(book, openReader: false)
                model.player.pause()
                XCTAssertEqual(model.player.chapter, 1)
                XCTAssertEqual(model.player.position, 1, "有独立听书进度后，阅读推进不能改变续听位置")
                XCTAssertEqual(model.entries.first?.progress, reading)
            }
        }
    }

    @MainActor func testExplicitListeningChapterLeavesReadingResumeUntouched() async throws {
        try await withSystemVoice {
            try await self.withDesignModel { model, _, _ in
                let book = self.readingFirstBook("explicit-listening")
                try await model.add(book, progress: .init(chapter: 1, position: 2, updatedAt: 100))
                model.startListening(book, openReader: false)
                model.player.pause()
                let reading = try XCTUnwrap(model.entries.first).progress
                model.listen(book.id, chapter: 0, position: 1, openReader: false)
                model.player.pause()
                XCTAssertEqual(model.player.chapter, 0)
                XCTAssertEqual(model.player.position, 1)
                XCTAssertEqual(model.entries.first?.progress, reading,
                               "听此章/从这句听只能定位声音，不能改写阅读断点")
                XCTAssertEqual(model.entries.first?.listeningProgress?.chapter, 0)
                XCTAssertEqual(model.entries.first?.listeningProgress?.position, 1)
                XCTAssertNil(model.listeningReaderID, "行内启动不应请求新的页面")
            }
        }
    }

    @MainActor func testListeningOnlyBookDoesNotReplaceRecentReading() async throws {
        try await withDesignModel { model, _, _ in
            let readingBook = self.readingFirstBook("reading-recent")
            let listeningBook = self.readingFirstBook("listening-only")
            try await model.add(readingBook)
            try await model.add(listeningBook)
            model.open(try XCTUnwrap(model.entries.first { $0.id == readingBook.id }))
            model.saveProgress(readingBook.id, chapter: 1, position: 1)
            model.recordActivity(.listening, for: listeningBook.id)
            model.saveListeningProgress(listeningBook.id, chapter: 1, position: 2)
            let heard = try XCTUnwrap(model.entries.first { $0.id == listeningBook.id })
            XCTAssertFalse(heard.started, "只听过的书不能标成已读")
            XCTAssertNil(heard.lastReadAt)
            XCTAssertEqual(model.readingRecency(for: heard), 0)
            XCTAssertEqual(model.resumeActions(for: heard).readingTitle, "开始阅读")
            XCTAssertEqual(model.resumeActions(for: heard).listeningTitle, "继续听")
            XCTAssertEqual(model.lastReadingBook?.id, readingBook.id,
                           "最近阅读与启动续读不能被新的听书回调抢走")
        }
    }

    @MainActor func testRemoteReadingMergePreservesIndependentListeningPosition() throws {
        let store = MemoryKeyValueStore()
        let suite = "tests.reading-merge." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: ProgressSync.enabledKey)
        let sync = ProgressSync(store: store, defaults: defaults, account: { true })
        let book = readingFirstBook("separate-merge")
        var local = ShelfEntry(book: book, progress: .init(chapter: 0, position: 1, updatedAt: 100))
        local.listeningProgress = .init(chapter: 1, position: 2, updatedAt: 300)
        local.lastReadAt = 150
        store.values[ProgressSync.key(local)] = ["c": 1, "p": 0, "t": 200.0]
        let merged = sync.merge([local], protected: [])
        XCTAssertEqual(merged.applied, [book.id])
        let result = try XCTUnwrap(merged.entries.first)
        XCTAssertEqual(result.progress, ReadingProgress(chapter: 1, position: 0, updatedAt: 200))
        XCTAssertEqual(result.listeningProgress, local.listeningProgress)
        XCTAssertEqual(result.lastReadAt, local.lastReadAt)
    }

    @MainActor func testRemoteReadingUpdatesDoNotStopPausedOrPlayingAudio() async throws {
        try await withSystemVoice {
            let store = MemoryKeyValueStore()
            try await self.withDesignModel(syncStore: store) { model, _, _ in
                let book = self.readingFirstBook("audio-survives-reading-sync")
                try await model.add(book, progress: .init(chapter: 1, position: 2, updatedAt: 100))
                model.startListening(book, openReader: false, from: .init(chapter: 0, position: 1))
                model.player.pause()
                let row = try XCTUnwrap(model.entries.first)
                let savedListening = row.listeningProgress
                store.values[ProgressSync.key(row)] = ["c": 0, "p": 2, "t": 200.0]
                model.pullProgress()
                XCTAssertEqual(model.entries.first?.progress, ReadingProgress(chapter: 0, position: 2, updatedAt: 200))
                XCTAssertEqual(model.entries.first?.listeningProgress, savedListening)
                XCTAssertEqual(model.player.book?.id, book.id, "同步阅读不能结束已暂停的独立听书会话")
                XCTAssertFalse(model.player.playing)
                XCTAssertEqual(model.player.chapter, 0)
                XCTAssertEqual(model.player.position, 1)
                model.player.resume()
                XCTAssertTrue(model.player.playing)
                store.values[ProgressSync.key(row)] = ["c": 1, "p": 0, "t": 300.0]
                model.pullProgress()
                XCTAssertEqual(model.entries.first?.progress, ReadingProgress(chapter: 1, position: 0, updatedAt: 300),
                               "只在听书时，远端阅读更新仍应合并")
                XCTAssertTrue(model.player.playing, "阅读同步不能中断正在播放的辅助声音")
                XCTAssertEqual(model.player.chapter, 0)
                XCTAssertEqual(model.player.position, 1)
                model.player.pause()
            }
        }
    }

    @MainActor func testUsageTickPrioritizesForegroundReadingAndCountsBackgroundAudioOnce() async throws {
        try await withSystemVoice {
            try await self.withDesignModel { model, _, _ in
                let audioBook = self.readingFirstBook("usage-audio-a")
                let readingBook = self.readingFirstBook("usage-reading-b")
                try await model.add(audioBook)
                try await model.add(readingBook)
                model.startListening(audioBook, openReader: false)
                XCTAssertTrue(model.player.playing)
                XCTAssertFalse(model.player.buffering)
                model.setReadingSurface(readingBook.id, visible: true)

                model.recordUsageTick(seconds: 5, appActive: true)
                XCTAssertEqual(model.readingSeconds.values.reduce(0, +), 5, accuracy: 0.001,
                               "听 A 同时读 B 的一个 tick 只能计一次时长")
                XCTAssertEqual(model.sessions.count, 1)
                XCTAssertEqual(model.sessions.first?.bookID, readingBook.id)
                XCTAssertEqual(model.sessions.first?.listening, false)
                XCTAssertEqual(model.sessions.first?.seconds, 5)

                model.recordUsageTick(seconds: 5, appActive: false)
                XCTAssertEqual(model.readingSeconds.values.reduce(0, +), 10, accuracy: 0.001)
                XCTAssertEqual(model.sessions.count, 2)
                XCTAssertEqual(model.sessions.last?.bookID, audioBook.id,
                               "进入后台后应记录仍在播放的 A，不再累计不可见的正文 B")
                XCTAssertEqual(model.sessions.last?.listening, true)
                XCTAssertEqual(model.sessions.last?.seconds, 5)
                XCTAssertEqual(model.sessions.map(\.seconds).reduce(0, +), 10, accuracy: 0.001)

                model.player.pause()
                let before = model.sessions
                model.recordUsageTick(seconds: 5, appActive: false)
                XCTAssertEqual(model.readingSeconds.values.reduce(0, +), 10, accuracy: 0.001)
                XCTAssertEqual(model.sessions, before, "后台暂停后不能继续计听书或残留阅读时长")
            }
        }
    }

    @MainActor func testUsageTickCountsPureReadingOnlyWhileItsSurfaceIsVisible() async throws {
        try await withDesignModel { model, _, _ in
            let book = self.readingFirstBook("usage-reading-only")
            try await model.add(book)
            XCTAssertNil(model.player.book)
            model.setReadingSurface(book.id, visible: true)
            model.recordUsageTick(seconds: 5, appActive: true)
            XCTAssertEqual(model.readingSeconds.values.reduce(0, +), 5, accuracy: 0.001)
            XCTAssertEqual(model.sessions.count, 1)
            XCTAssertEqual(model.sessions.first?.bookID, book.id)
            XCTAssertEqual(model.sessions.first?.listening, false)
            XCTAssertEqual(model.sessions.first?.seconds, 5)

            let before = model.sessions
            model.recordUsageTick(seconds: 5, appActive: false)
            XCTAssertEqual(model.sessions, before, "没有声音时进入后台不能计阅读")
            model.setReadingSurface(book.id, visible: false)
            XCTAssertNil(model.visibleReadingBookID)
            model.recordUsageTick(seconds: 5, appActive: true)
            XCTAssertEqual(model.readingSeconds.values.reduce(0, +), 5, accuracy: 0.001)
            XCTAssertEqual(model.sessions, before, "离开正文后首页或播放器停留不能计为阅读")
        }
    }

    func testReaderSearchReturnsRepeatedMatchesWithDistinctLocations() {
        let chapters = [Chapter(title: "第一章", text: "晨光。晨光。"), Chapter(title: "第二章", text: "晨光。")]
        let matches = ReaderSearch.matches(in: chapters, query: "晨光")
        XCTAssertEqual(matches.map(\.index), [0, 0, 1], "同章重复文字应各有一个可跳转的结果")
        XCTAssertEqual(matches.map(\.offset), [0, 3, 0])
        XCTAssertEqual(Set(matches.map(\.id)).count, 3)
        XCTAssertTrue(matches.allSatisfy { $0.snippet.contains("晨光") })
    }

    func testReaderSearchUsesUTF16OffsetsAfterEmoji() {
        let text = "📖 夜风。📖 夜风。"
        let matches = ReaderSearch.matches(in: [Chapter(title: "夜读", text: text)], query: "夜风")
        XCTAssertEqual(matches.map(\.offset), [3, 9], "正文定位使用 UTF-16，不能按 Swift Character 数定位")
        for match in matches {
            XCTAssertEqual((text as NSString).substring(with: NSRange(location: match.offset, length: 2)), "夜风")
            XCTAssertTrue(match.snippet.contains("📖"), "摘要截取不能破坏组合字符")
        }
    }

    func testReaderSearchHandlesTitleOnlyWhitespaceAndResultLimits() {
        let chapters = [Chapter(title: "A Quiet Chapter", text: "只有正文。"), Chapter(title: "另一章", text: String(repeating: "阅读。", count: 240))]
        let title = ReaderSearch.matches(in: chapters, query: " quiet ")
        XCTAssertEqual(title.count, 1)
        XCTAssertEqual(title.first?.index, 0)
        XCTAssertEqual(title.first?.offset, 0, "仅章名命中时跳到该章开头")
        XCTAssertEqual(title.first?.snippet, "只有正文。")
        XCTAssertTrue(ReaderSearch.matches(in: chapters, query: " \n\t ").isEmpty)
        XCTAssertTrue(ReaderSearch.matches(in: chapters, query: "不存在的文字").isEmpty)
        XCTAssertTrue(ReaderSearch.matches(in: chapters, query: "阅读", limit: 0).isEmpty)
        XCTAssertEqual(ReaderSearch.matches(in: chapters, query: "阅读", limit: 2).map(\.offset), [0, 3])
        XCTAssertEqual(ReaderSearch.matches(in: chapters, query: "阅读").count, 200,
                       "长书中大量命中应限制结果量，不阻塞阅读界面")
    }

    private func readingFirstBook(_ id: String) -> Book {
        let text = (1...4).map { "第\($0)句，" + String(repeating: "安静地阅读，", count: 20) + "这一段结束。" }.joined()
        return Book(id: id, title: id, format: "TXT", chapters: [.init(title: "第一章", text: text), .init(title: "第二章", text: text)])
    }

    @MainActor private func withSystemVoice(_ action: () async throws -> Void) async throws {
        let defaults = UserDefaults.standard
        let keys = ["voice.provider", "voice.rate", "voice.roles"]
        let saved = keys.map { defaults.object(forKey: $0) }
        defaults.set("system", forKey: "voice.provider")
        defaults.set(1.0, forKey: "voice.rate")
        defaults.set(false, forKey: "voice.roles")
        defer { for (key, value) in zip(keys, saved) { defaults.set(value, forKey: key) } }
        try await action()
    }

    @MainActor func testPartialImportsHavePerFileResultsAndDoNotShowSuccessAlerts() async throws {
        try await withDesignModel { model, _, base in
            let good = base.appendingPathComponent("好书.txt"), bad = base.appendingPathComponent("损坏.json")
            try Data("可以读这本书。下一句。".utf8).write(to: good)
            try Data("broken".utf8).write(to: bad)
            try await model.importWithFeedback([good, bad])
            let report = try XCTUnwrap(model.importReport)
            XCTAssertTrue(report.finished); XCTAssertEqual(report.successes, 1); XCTAssertEqual(report.failures, 1)
            XCTAssertEqual(report.completed, 2); XCTAssertEqual(report.items.map(\.name), ["好书.txt", "损坏.json"])
            if case .failed(let reason) = report.items[1].state { XCTAssertTrue(reason.contains("损坏")) }
            else { XCTFail("失败文件必须保留可读的原因") }
            XCTAssertEqual(model.entries.count, 1); XCTAssertNil(model.message)
            XCTAssertEqual(model.notice?.importResults, true)
            XCTAssertTrue(model.notice?.text.contains("1 个失败") == true)
            try await model.importWithFeedback([good])
            XCTAssertEqual(model.importReport?.successes, 1); XCTAssertEqual(model.importReport?.failures, 0)
            XCTAssertNil(model.message)
        }
    }

    @MainActor private func withDesignModel(syncStore: MemoryKeyValueStore? = nil, _ action: (AppModel, LibraryDisk, URL) async throws -> Void) async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "tests.design." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { try? FileManager.default.removeItem(at: base); defaults.removePersistentDomain(forName: suite) }
        defaults.set(syncStore != nil, forKey: ProgressSync.enabledKey)
        let disk = try LibraryDisk(owner: "design-test", base: base)
        let model = AppModel(disk: disk, progressSync: ProgressSync(store: syncStore ?? MemoryKeyValueStore(), defaults: defaults, account: { syncStore != nil }))
        do { try await action(model, disk, base) }
        catch { _ = try? await model.beginLibraryRestore(); throw error }
        _ = try await model.beginLibraryRestore()
    }

    func testSpokenAudioSessionActivatesAndReactivatesAfterDeactivation() throws {
        let session = AVAudioSession.sharedInstance()
        defer { try? session.setActive(false, options: .notifyOthersOnDeactivation) }
        try SpeechAudioSession.activate()
        XCTAssertEqual(session.category, .playback)
        XCTAssertEqual(session.mode, .spokenAudio)
        try session.setActive(false, options: .notifyOthersOnDeactivation)
        try session.setCategory(.ambient, mode: .default)
        try SpeechAudioSession.activate()
        XCTAssertEqual(session.category, .playback)
        XCTAssertEqual(session.mode, .spokenAudio)
    }

    func testSentenceIndicesRemainCompatibleWithExistingClient() {
        let text = "我回来了。\n风，轻轻地吹！“还好吗？”\nHello world.\n最后一句"
        let parts = Sentence.split(text)
        XCTAssertEqual(parts.map(\.text), ["我回来了。", "风，轻轻地吹！", "“还好吗？”", "Hello world.", "最后一句"])
        for part in parts { XCTAssertEqual((text as NSString).substring(with: part.range), part.text) }
        XCTAssertEqual(Sentence.index(at: parts[3].range.location, in: parts), 3)
        let long = Sentence.split(String(repeating: "你", count: 401) + "。")
        XCTAssertTrue(long.allSatisfy { $0.text.count <= 181 })
        XCTAssertEqual(long.map(\.text).joined(), String(repeating: "你", count: 401) + "。")
    }
    func testGLMWithoutTimestampsGetsEstimatedPerCharacterTimingInsideSpeech() {
        // 0.5 s 静音 + 2 s 发声 + 1 s 尾部静音，16 kHz 单声道 16 位 PCM。
        let rate = 16000
        var samples = [Int16](repeating: 0, count: rate / 2)
        samples += (0..<rate * 2).map { Int16(8000 * sin(Double($0) * 0.2)) }
        samples += [Int16](repeating: 0, count: rate)
        var wav = Data("RIFF".utf8)
        func put(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { wav.append(contentsOf: $0) } }
        func put16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { wav.append(contentsOf: $0) } }
        put(UInt32(36 + samples.count * 2)); wav.append(contentsOf: Array("WAVEfmt ".utf8))
        put(16); put16(1); put16(1); put(UInt32(rate)); put(UInt32(rate * 2)); put16(2); put16(16)
        wav.append(contentsOf: Array("data".utf8)); put(UInt32(samples.count * 2))
        for sample in samples { put16(UInt16(bitPattern: sample)) }
        let span = try! XCTUnwrap(CloudSpeech.speechSpan(wav: wav))
        XCTAssertEqual(span.start, 0.5, accuracy: 0.02)
        XCTAssertEqual(span.end, 2.5, accuracy: 0.02)

        let words = CloudSpeech.estimatedWords("你好，世界。", from: span.start, to: span.end)
        XCTAssertEqual(words.map(\.text), ["你", "好", "，", "世", "界", "。"])
        XCTAssertEqual(words.first!.start, span.start, accuracy: 0.001)
        XCTAssertEqual(words.last!.end, span.end, accuracy: 0.001)
        for (a, b) in zip(words, words.dropFirst()) { XCTAssertEqual(a.end, b.start, accuracy: 0.0001); XCTAssertLessThan(a.start, a.end) }
        XCTAssertTrue(CloudSpeech.estimatedWords("  \n", from: 0, to: 1).isEmpty)
        XCTAssertTrue(CloudSpeech.estimatedWords("好", from: 1, to: 1).isEmpty)
        XCTAssertNil(CloudSpeech.speechSpan(wav: Data(repeating: 0, count: 64)))
        XCTAssertEqual(CloudSpeech.speechSpan(audio: wav)!.start, 0.5, accuracy: 0.02)
    }

    func testCompressedCloudAudioSpanTrimsLeadingAndTrailingSilence() throws {
        // 0.4 s 静音 + 1.5 s 发声 + 0.8 s 静音，编码为压缩音频后仍能找回发声区间。
        let rate = 32000.0
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
        let frames = AVAudioFrameCount(rate * 2.7)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for i in 0..<Int(frames) {
            let t = Double(i) / rate
            buffer.floatChannelData![0][i] = (0.4..<1.9).contains(t) ? Float(0.3 * sin(2 * .pi * 440 * t)) : 0
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("span-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            let file = try AVAudioFile(forWriting: url, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: rate, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 96000])
            try file.write(from: buffer)
        }
        let span = try XCTUnwrap(CloudSpeech.speechSpan(audio: try Data(contentsOf: url)))
        XCTAssertEqual(span.start, 0.4, accuracy: 0.06)
        XCTAssertEqual(span.end, 1.9, accuracy: 0.06)
        XCTAssertNil(CloudSpeech.speechSpan(audio: Data("not audio".utf8)))
    }

    func testTrailingPauseFollowsPunctuation() {
        XCTAssertEqual(CloudSpeech.trailingPause(after: "他走了。"), 0.28)
        XCTAssertEqual(CloudSpeech.trailingPause(after: "“你来了？”"), 0.28)
        XCTAssertEqual(CloudSpeech.trailingPause(after: "然而，"), 0.14)
        XCTAssertGreaterThan(CloudSpeech.trailingPause(after: "第一章 开端"), 0.28)
    }

    func testMiniMaxTokenPlanAndHexDecoding() {
        XCTAssertEqual(CloudSpeech.minimaxOrigins.first?.absoluteString, "https://api.minimax.cn")
        let hex = "48656c6c6f"
        XCTAssertEqual(CloudSpeech.decodeHex(hex), Data("Hello".utf8))
        XCTAssertNil(CloudSpeech.decodeHex("invalid_hex!"))
        let upperHex = "414243"
        XCTAssertEqual(CloudSpeech.decodeHex(upperHex), Data("ABC".utf8))
        XCTAssertEqual(CloudSpeech.decodeHex(""), Data())

        let s1 = VoiceOptions.sanitized(provider: "minimax", model: "speech-2.8-turbo", voice: "female-shaonv")
        XCTAssertEqual(s1.model, "speech-2.8-turbo")
        XCTAssertEqual(s1.voice, "female-shaonv")

        let s2 = VoiceOptions.sanitized(provider: "minimax", model: "glm-4", voice: "tongtong")
        XCTAssertEqual(s2.model, "speech-2.8-hd")
        XCTAssertEqual(s2.voice, "male-qn-qingse")
    }

    func testEmojiAndUTF16Ranges() {
        let text = "山⛰️与书📖。春风又绿江南岸。"
        for line in Sentence.split(text) { XCTAssertEqual((text as NSString).substring(with: line.range), line.text) }
    }
    func testHTMLStripsActiveContentAndPreservesMarks() {
        let chapter = HTMLText.chapter("<head><title>hidden</title></head><h1>山水</h1><p>春<b>风</b>&amp;&#x4E66;。</p><script>steal()</script>", title: "fallback")
        XCTAssertEqual(chapter.title, "山水")
        XCTAssertTrue(chapter.text.contains("春风&书。"))
        XCTAssertFalse(chapter.text.contains("steal"))
        XCTAssertFalse(chapter.text.contains("hidden"))
        let mark = chapter.fields["marks"]?.array?.first?.object
        XCTAssertEqual(mark?["bold"]?.bool, true)
        XCTAssertEqual((chapter.text as NSString).substring(with: NSRange(location: mark!["start"]!.int!, length: mark!["end"]!.int! - mark!["start"]!.int!)), "风")
    }
    func testChapterSplittingAndEncodedText() throws {
        let parts = BookImporter.splitText("序言\n第一章 山水\n春风。\n第二章 归人\n归来。", title: "书")
        XCTAssertEqual(parts.map(\.title), ["卷首", "第一章 山水", "第二章 归人"])
        XCTAssertEqual(parts[1].text, "春风。")
        XCTAssertEqual(try BookImporter.decode(Data([0xEF,0xBB,0xBF] + Array("听页\r\n书斋".utf8))), "听页\n书斋")
        XCTAssertEqual(try BookImporter.decode(Data([0xCC,0xFD,0xD2,0xB3])), "听页")
        XCTAssertEqual(BookImporter.markdown("---\ntitle: 古书\naliases: [书]\n---\n# 正文\n春风。"), "# 正文\n春风。")
    }
    func testLegacyCatalogKeepsProgressAndCloudRevision() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let rows: [[String: JSONValue]] = [["id": .string("old-book"), "chapter": .number(1), "position": .number(5), "updatedAt": .number(10000), "snapshotRevision": .string("revision-v2")]]
        let manifest = ["tingye.vercel.catalog.reader": String(data: try Integrity.encoder().encode(rows), encoding: .utf8)!]
        try Integrity.encoder().encode(manifest).write(to: base.appendingPathComponent("manifest.json"))
        let found = try LegacyCatalog.entries(owner: "reader", directories: [base])
        let book = Book(id: "old-book", title: "旧书", format: "TXT", chapters: [Chapter(title: "一", text: "一。"), Chapter(title: "二", text: "二。")])
        let row = LegacyCatalog.row(book: book, metadata: found["old-book"])
        XCTAssertEqual(row.progress.chapter, 1); XCTAssertEqual(row.progress.position, 5)
        XCTAssertEqual(row.snapshotRevision, "revision-v2")
        XCTAssertTrue(try LegacyCatalog.entries(owner: "another-user", directories: [base]).isEmpty)
    }
    func testEPUBPathsCannotEscapeOrLoadRemoteContent() throws {
        XCTAssertEqual(try BookImporter.resolve(base: "OEBPS/Text/a.xhtml", href: "../Images/a%20b.png"), "OEBPS/Images/a b.png")
        XCTAssertThrowsError(try BookImporter.resolve(base: "a.opf", href: "../outside"))
        XCTAssertThrowsError(try BookImporter.resolve(base: "a.opf", href: "https://example.com/a"))
        XCTAssertThrowsError(try BookImporter.resolve(base: "a.opf", href: "%2E%2E/outside"))
    }
    func testBackupRoundTripPreservesOtherClientFields() throws {
        let chapter = Chapter(title: "章", text: "一。二。", extras: ["document": .object(["html": .string("<p>一。二。</p>"), "css": .string("p{color:red}")])])
        let book = Book(id: "book-1", title: "书", format: "EPUB", chapters: [chapter], extras: ["resources": .object(["r0": .string("data:image/png;base64,AAAA")])])
        let packet = BackupPacket(book: book, progress: .init(chapter: 0, position: 1, updatedAt: 1000))
        let data = try Integrity.encoder().encode(packet)
        let result = try JSONDecoder().decode(BackupPacket.self, from: data).validated(id: "book-1")
        XCTAssertEqual(result.book, book); XCTAssertEqual(result.progress.position, 1)
        XCTAssertEqual(Integrity.sha256(Data("abc".utf8)), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        var wrong = packet; wrong.progress.chapter = 8
        XCTAssertThrowsError(try wrong.validated(id: "book-1"))
        XCTAssertThrowsError(try packet.validated(id: "another-book"))
    }
    func testCatalogReservedNameAndAccountIsolation() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let first = try LibraryDisk(owner: "user-a", base: base), second = try LibraryDisk(owner: "user-b", base: base)
        let book = Book(id: "catalog", title: "不冲突", format: "TXT", chapters: [Chapter(title: "正文", text: "一个句子。")])
        try first.write(book); try first.saveCatalog([ShelfEntry(book: book)])
        XCTAssertEqual(try first.read("catalog"), book)
        XCTAssertEqual(try first.catalog().count, 1)
        XCTAssertThrowsError(try second.read("catalog"))
        XCTAssertThrowsError(try first.file("../../secret"))
        XCTAssertThrowsError(try LibraryDisk(owner: "../outside", base: base))
    }
    func testSignedKeychainRoundTrip() throws {
        let key = "test-" + UUID().uuidString
        defer { try? Keychain.remove(key) }
        try Keychain.save(Data("original".utf8), key: key)
        try Keychain.save(Data("updated".utf8), key: key)
        XCTAssertEqual(try Keychain.data(key), Data("updated".utf8))
        try Keychain.remove(key); XCTAssertNil(try Keychain.data(key))
    }
    @MainActor func testPaginationCoversEveryCharacterWithoutGaps() {
        let chapter = Chapter(title: "长章", text: String(repeating: "我冒了严寒，回到相隔二千余里，别了二十余年的故乡去。📖\n", count: 100))
        let text = NativeTypesetter.attributed(chapter, preferences: .init())
        let pages = NativeTypesetter.pages(text, size: CGSize(width: 345, height: 510))
        XCTAssertGreaterThan(pages.count, 1)
        XCTAssertEqual(pages.first?.location, 0)
        XCTAssertEqual(pages.reduce(0) { $0 + $1.length }, text.length)
        for i in 1..<pages.count { XCTAssertEqual(NSMaxRange(pages[i-1]), pages[i].location) }
        XCTAssertEqual(pages.map { text.attributedSubstring(from: $0).string }.joined(), chapter.text)
    }
    /// 每页单独排版时也要完整显示：页首在段落中间不能再加首行缩进，否则页尾的字被挤掉。
    @MainActor func testEveryPageRendersAllOfItsCharacters() {
        let paragraph = String(repeating: "春眠不觉晓，处处闻啼鸟。夜来风雨声，花落知多少。", count: 40)
        let chapter = Chapter(title: "长段", text: paragraph + "\n" + paragraph)
        let size = CGSize(width: 346, height: 620)
        let text = NativeTypesetter.attributed(chapter, preferences: .init())
        let pages = NativeTypesetter.pages(text, size: size)
        XCTAssertGreaterThan(pages.count, 2)
        let path = CGPath(rect: CGRect(origin: .zero, size: size), transform: nil)
        for (index, range) in pages.enumerated() {
            let page = NativeTypesetter.page(text, range: range)
            XCTAssertEqual(page.string, (text.string as NSString).substring(with: range))
            let frame = CTFramesetterCreateFrame(CTFramesetterCreateWithAttributedString(page), CFRange(location: 0, length: 0), path, nil)
            XCTAssertEqual(CTFrameGetVisibleStringRange(frame).length, range.length, "第 \(index + 1) 页有字被挤出")
        }
    }
    func testEPUBAndDOCXImportFixtures() throws {
        let base = try XCTUnwrap(Bundle(for: Self.self).resourceURL?.appendingPathComponent("Fixtures"))
        let epub = try BookImporter.read(base.appendingPathComponent("book.epub")).book
        XCTAssertEqual(epub.title, "山水书")
        XCTAssertEqual(epub.chapters.count, 2)
        XCTAssertTrue(epub.chapters[0].text.contains("春风"))
        XCTAssertTrue(epub.chapters[1].text.contains("归人"))
        let docx = try BookImporter.read(base.appendingPathComponent("book.docx")).book
        XCTAssertTrue(docx.chapters[0].text.contains("听页原生阅读"))
    }
    @MainActor func testBundledFontAndSamples() {
        XCTAssertNotNil(UIFont(name: Theme.serifName, size: 20))
        XCTAssertEqual(Samples.books.count, 3)
        XCTAssertTrue(Samples.books.allSatisfy(\.sample))
    }
    @MainActor func testSpeechHighlightUsesUTF16AndKeepsSourceUnchanged() {
        let chapter = Chapter(title: "正文", text: "山📖。清风徐来，水波不兴。")
        let source = NativeTypesetter.attributed(chapter, preferences: .init())
        let sentences = Sentence.split(chapter.text)
        let word = (chapter.text as NSString).range(of: "水波")
        let result = SpeechHighlight.apply(to: source, sentence: sentences[1].range)
        XCTAssertEqual(result.string, source.string)
        XCTAssertNil(source.attribute(.backgroundColor, at: word.location, effectiveRange: nil))
        XCTAssertEqual(result.attribute(.backgroundColor, at: word.location, effectiveRange: nil) as? UIColor, UIColor(Theme.wash))
        for offset in sentences[1].range.location..<NSMaxRange(sentences[1].range) {
            XCTAssertEqual(result.attribute(.backgroundColor, at: offset, effectiveRange: nil) as? UIColor, UIColor(Theme.wash))
            XCTAssertEqual(result.attribute(.foregroundColor, at: offset, effectiveRange: nil) as? UIColor, source.attribute(.foregroundColor, at: offset, effectiveRange: nil) as? UIColor)
        }
        XCTAssertNil(result.attribute(.backgroundColor, at: 0, effectiveRange: nil))
        let invalid = SpeechHighlight.apply(to: source, sentence: NSRange(location: 9999, length: 30))
        XCTAssertEqual(invalid.string, source.string)
    }
    /// GLM 与 MiniMax 的模型、音色互不串用；已串用的旧值回到各自默认值。
    func testVoiceOptionsKeepProvidersSeparate() {
        XCTAssertEqual(VoiceOptions.sanitized(provider: "minimax", model: "glm-tts", voice: "tongtong").model, "speech-2.8-hd")
        XCTAssertEqual(VoiceOptions.sanitized(provider: "minimax", model: "glm-tts", voice: "tongtong").voice, "male-qn-qingse")
        XCTAssertEqual(VoiceOptions.sanitized(provider: "glm", model: "speech-2.8-hd", voice: "female-shaonv").model, "glm-tts")
        XCTAssertEqual(VoiceOptions.sanitized(provider: "glm", model: "speech-2.8-hd", voice: "female-shaonv").voice, "tongtong")
        XCTAssertEqual(VoiceOptions.sanitized(provider: "minimax", model: "speech-02-turbo", voice: "audiobook_female_1").model, "speech-02-turbo")
        XCTAssertEqual(VoiceOptions.sanitized(provider: "glm", model: "glm-tts", voice: "xiaochen").voice, "xiaochen")
        XCTAssertEqual(VoiceOptions.sanitized(provider: "system", model: "glm-tts", voice: "tongtong").voice, "")
    }
    /// 旧版不分服务商的设置按内容迁到各自的键，不覆盖已有的分服务商设置。
    func testLegacyVoiceSettingsMigrateToOwningProvider() throws {
        let suite = "voice-migration-\(UUID().uuidString)"
        let d = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { d.removePersistentDomain(forName: suite) }
        d.set("speech-02-hd", forKey: "voice.model"); d.set("tongtong", forKey: "voice.id")
        d.set("speech-2.6-turbo", forKey: "voice.model.minimax")
        VoiceOptions.migrateLegacy(defaults: d, moveSecret: false)
        XCTAssertEqual(d.string(forKey: "voice.model.minimax"), "speech-2.6-turbo", "已有的 MiniMax 模型不被旧值覆盖")
        XCTAssertEqual(d.string(forKey: "voice.name.glm"), "tongtong", "GLM 预设音色迁到 GLM")
        XCTAssertNil(d.string(forKey: "voice.model")); XCTAssertNil(d.string(forKey: "voice.id"))
    }
    func testOriginalDocumentRetainsTablesResourcesAndBlocksActiveContent() {
        let raw = "<table><tr><td>正文</td></tr></table><img src='tingye-resource:r0' onerror='bad()'><script>bad()</script>"
        let html = OriginalDocument.html(raw, css: "table {color:red}")
        XCTAssertTrue(html.contains("<table>"))
        // 图片保留引用，由 ResourceSchemeHandler 按需提供，不再内嵌 base64。
        XCTAssertTrue(html.contains("src='tingye-resource:r0'"))
        XCTAssertTrue(html.contains("img-src data: tingye-resource:"))
        XCTAssertEqual(ResourceSchemeHandler.decode("data:image/png;base64,AAAA")?.1, "image/png")
        XCTAssertEqual(OriginalDocument.closingSelfClosedTags(#"<p>a<span class="x"/>b<br/><img src="i"/><a id='k' /></p>"#), #"<p>a<span class="x"></span>b<br/><img src="i"/><a id='k'></a></p>"#)
        XCTAssertTrue(html.contains("table {color:red}"))
        XCTAssertFalse(html.contains("onerror="))
        XCTAssertFalse(html.contains("<script>"))
        XCTAssertTrue(html.contains("script-src 'none'"))
    }
    func testEPUBRetainsOriginalHTMLAndStylesForRepair() throws {
        let base = try XCTUnwrap(Bundle(for: Self.self).resourceURL?.appendingPathComponent("Fixtures"))
        let book = try BookImporter.read(base.appendingPathComponent("book.epub")).book
        XCTAssertTrue(book.chapters.allSatisfy { $0.fields["document"]?.object?["html"]?.string != nil })
        let data = try Integrity.encoder().encode(book)
        XCTAssertEqual(try JSONDecoder().decode(Book.self, from: data), book)
    }
    @MainActor func testKaiFontIsBundled() { XCTAssertNotNil(UIFont(name: "LXGWWenKaiLite-Regular", size: 21)) }

}

import WebKit

final class ProgressAndBackupTests: XCTestCase {
    func testSingleChapterProgressAndOldCatalogCompatibility() throws {
        let book = Book(id: "progress", title: "四百句", format: "TXT", chapters: [Chapter(title: "正文", text: String(repeating: "一句。", count: 400))])
        var row = ShelfEntry(book: book)
        XCTAssertEqual(row.percentText, "未开卷")
        row.progress = .init(chapter: 0, position: 197, updatedAt: 1)
        XCTAssertEqual(row.readFraction, 198.0 / 400.0, accuracy: 0.00001)
        XCTAssertEqual(row.percentText, "50%")
        row.progress.position = 0
        XCTAssertLessThan(row.readFraction, 0.01)
        row.progress.position = 399
        XCTAssertEqual(row.readFraction, 1)
        var old = try XCTUnwrap(JSONSerialization.jsonObject(with: Integrity.encoder().encode(row)) as? [String: Any])
        old.removeValue(forKey: "sentenceCounts")
        let decoded = try JSONDecoder().decode(ShelfEntry.self, from: JSONSerialization.data(withJSONObject: old))
        XCTAssertNil(decoded.sentenceCounts)
        XCTAssertLessThan(decoded.readFraction, 1)
        let packet = try Integrity.encoder().encode(BackupPacket(book: book, progress: row.progress))
        XCTAssertFalse(String(decoding: packet, as: UTF8.self).contains("sentenceCounts"))
    }
    func testInterruptedRestoreRecoversPreviousLibrary() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let disk = try LibraryDisk(owner: "guest", base: base)
        let book = Book(id: "safe", title: "保留", format: "TXT", chapters: [Chapter(title: "正文", text: "原书。")])
        try disk.write(book); try disk.saveCatalog([ShelfEntry(book: book)])
        try FileManager.default.moveItem(at: disk.root, to: disk.root.appendingPathExtension("restore-backup"))
        let recovered = try LibraryDisk(owner: "guest", base: base)
        XCTAssertEqual(try recovered.read(book.id), book)
        XCTAssertEqual(try recovered.catalog().count, 1)
    }
    func testWeightedChaptersEmptyTextAndOutOfRangeProgress() {
        let book = Book(title: "混合", format: "TXT", chapters: [Chapter(title: "一", text: "一。二。"), Chapter(title: "二", text: "三。四。五。六。"), Chapter(title: "插图", text: "")])
        var row = ShelfEntry(book: book, progress: .init(chapter: 1, position: 1, updatedAt: 1))
        XCTAssertEqual(row.readFraction, 4.0 / 7.0, accuracy: 0.00001)
        row.progress = .init(chapter: 999, position: 999, updatedAt: 1)
        XCTAssertEqual(row.readFraction, 1)
        row.progress = .init(chapter: -1, position: -1, updatedAt: 1)
        XCTAssertGreaterThanOrEqual(row.readFraction, 0)
    }
    func testICloudSnapshotsRestoreResourcesProgressBookmarksAndKeepOtherBooks() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let store = ICloudBackupStore(root: base.appendingPathComponent("cloud"))
        let disk = try LibraryDisk(owner: "guest", base: base)
        let chapter = HTMLText.chapter("<p>春<b>风</b>。归来。</p>", title: "正文")
        let book = Book(id: "restore", title: "书", format: "EPUB", chapters: [chapter], extras: ["resources": .object(["r0": .string("data:image/png;base64,AAAA")])])
        let other = Book(id: "other", title: "保留", format: "TXT", chapters: [Chapter(title: "正文", text: "另一书。")])
        try disk.write(other); try disk.saveCatalog([ShelfEntry(book: other)])
        let mark = Bookmark(chapter: 0, position: 1, excerpt: "归来。")
        let listening = ReadingProgress(chapter: 0, position: 0, updatedAt: 456)
        let archive = ICloudArchive(owner: "guest", books: [.init(packet: .init(book: book, progress: .init(chapter: 0, position: 1, updatedAt: 123)), bookmarks: [mark], listeningProgress: listening, lastReadAt: 234)])
        let first = try store.save(archive), second = try store.save(archive)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(try store.snapshots(owner: "guest").count, 2)
        XCTAssertTrue(try store.snapshots(owner: "other-account").isEmpty)
        let recovered = try store.read(first, owner: "guest")
        let rows = try disk.restore(recovered, owner: "guest", entries: disk.catalog())
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(try disk.read(book.id), book)
        XCTAssertEqual(try disk.read(other.id), other)
        let row = try XCTUnwrap(rows.first { $0.id == book.id })
        XCTAssertEqual(row.progress.position, 1)
        XCTAssertEqual(row.listeningProgress, listening, "快照还原应分别保留阅读位置与听书位置")
        XCTAssertEqual(row.lastReadAt, 234)
        XCTAssertEqual(row.hasListened, true)
        XCTAssertEqual(row.bookmarks.first?.id, mark.id)
        XCTAssertEqual(row.sentenceCounts, [2])
        XCTAssertEqual(try disk.catalog().count, 2)
        XCTAssertThrowsError(try store.read(first, owner: "other-account"))
        let before = try Data(contentsOf: disk.root.appendingPathComponent("catalog.json"))
        var invalid = recovered; invalid.books[0].packet.progress.chapter = 999
        XCTAssertThrowsError(try disk.restore(invalid, owner: "guest", entries: rows))
        XCTAssertEqual(try Data(contentsOf: disk.root.appendingPathComponent("catalog.json")), before)
        var invalidListening = recovered
        invalidListening.books[0].listeningProgress?.chapter = 999
        XCTAssertThrowsError(try disk.restore(invalidListening, owner: "guest", entries: rows))
        XCTAssertEqual(try Data(contentsOf: disk.root.appendingPathComponent("catalog.json")), before,
                       "听书位置无效的快照也必须在写入前拒绝，保留原书库")
        let legacy = ICloudArchive(owner: "guest", books: [.init(packet: .init(book: book, progress: row.progress), bookmarks: [mark])])
        let decodedLegacy = try JSONDecoder().decode(ICloudArchive.self, from: Integrity.encoder().encode(legacy))
        XCTAssertEqual(decodedLegacy.version, 1)
        XCTAssertNil(decodedLegacy.books.first?.listeningProgress)
        XCTAssertNil(decodedLegacy.books.first?.lastReadAt)
        XCTAssertEqual(try decodedLegacy.validated(owner: "guest").books.first?.packet.progress, row.progress)
        try Data("broken".utf8).write(to: second)
        XCTAssertThrowsError(try store.read(second, owner: "guest"))
        XCTAssertEqual(try disk.read(book.id), book)
    }

    /// 新设备以 guest 运行时，旧账号目录下的快照仍可被发现并还原进当前书库。
    func testICloudRestoreFallsBackToSnapshotsUnderOtherOwners() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let store = ICloudBackupStore(root: base.appendingPathComponent("cloud"))
        let disk = try LibraryDisk(owner: "guest", base: base)
        let book = Book(id: "legacy", title: "旧书", format: "TXT", chapters: [Chapter(title: "正文", text: "旧账号的书。")])
        let archive = ICloudArchive(owner: "legacy-account", books: [.init(packet: .init(book: book, progress: .init(chapter: 0, position: 0, updatedAt: 123)), bookmarks: [])])
        let saved = try store.save(archive)
        XCTAssertTrue(try store.snapshots(owner: "guest").isEmpty)
        XCTAssertEqual(try store.snapshotOwners(), ["legacy-account"])
        let found = try XCTUnwrap(store.latestSnapshotAcrossOwners())
        XCTAssertEqual(found.owner, "legacy-account")
        XCTAssertEqual(found.url, saved)
        let recovered = try store.read(found.url, owner: found.owner)
        let rows = try disk.restore(recovered, owner: "guest", entries: disk.catalog())
        XCTAssertEqual(rows.map(\.id), [book.id])
        XCTAssertEqual(try disk.read(book.id), book)
        // 目录账号与存档记录不一致时仍拒绝。
        XCTAssertThrowsError(try store.read(found.url, owner: "guest"))
    }

    /// 当前账号（guest）目录里的旧快照不能遮住其他账号目录中更新的备份。
    func testICloudLatestSnapshotPrefersNewestAcrossOwners() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let store = ICloudBackupStore(root: base.appendingPathComponent("cloud"))
        let book = Book(id: "b", title: "书", format: "TXT", chapters: [Chapter(title: "正文", text: "内容。")])
        let item = ICloudArchive.Item(packet: .init(book: book, progress: .init(chapter: 0, position: 0, updatedAt: 1)), bookmarks: [])
        _ = try store.save(ICloudArchive(owner: "guest", createdAt: Date(timeIntervalSince1970: 1_000), books: [item]))
        let newer = try store.save(ICloudArchive(owner: "account", createdAt: Date(timeIntervalSince1970: 2_000), books: [item]))
        let found = try XCTUnwrap(store.latestSnapshotAcrossOwners())
        XCTAssertEqual(found.owner, "account")
        XCTAssertEqual(found.url, newer)
    }

    /// 删除书籍时从快照中移除该书：含其他书的快照被改写，只含该书的快照被删除。
    func testICloudRemoveBookRewritesSnapshotsAndDeletesEmptyOnes() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let store = ICloudBackupStore(root: base.appendingPathComponent("cloud"))
        let target = Book(id: "target", title: "待删", format: "TXT", chapters: [Chapter(title: "正文", text: "要删除的书。")])
        let kept = Book(id: "kept", title: "保留", format: "TXT", chapters: [Chapter(title: "正文", text: "保留的书。")])
        let both = ICloudArchive(owner: "guest", books: [target, kept].map { .init(packet: .init(book: $0, progress: .init()), bookmarks: []) })
        let onlyTarget = ICloudArchive(owner: "legacy-account", books: [.init(packet: .init(book: target, progress: .init()), bookmarks: [])])
        let bothURL = try store.save(both), onlyURL = try store.save(onlyTarget)
        let result = try await store.removeBook("target")
        XCTAssertEqual(result.rewritten, 1)
        XCTAssertEqual(result.deleted, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: onlyURL.path))
        let remaining = try store.read(bothURL, owner: "guest")
        XCTAssertEqual(remaining.books.map { $0.packet.book.id }, ["kept"])
        XCTAssertEqual(try store.snapshots(owner: "legacy-account").count, 0)
    }

    func testICloudTransferShowsRealCountsOnlyForCountableStages() {
        var transfer = ICloudTransfer(kind: .restore, stage: .connecting)
        XCTAssertNil(transfer.fraction); XCTAssertTrue(transfer.running); XCTAssertTrue(transfer.cancellable)
        transfer.advance(.downloading, completed: 3, total: 10)
        XCTAssertNil(transfer.fraction, "下载进度不可测，不能显示百分比")
        XCTAssertEqual(transfer.activity, "等待 iCloud 下载")
        transfer.advance(.validating, completed: 2, total: 5)
        XCTAssertEqual(try XCTUnwrap(transfer.fraction), 0.4, accuracy: 0.0001)
        XCTAssertEqual(transfer.countText, "2/5 本")
        XCTAssertEqual(transfer.steps, [.connecting, .finding, .downloading, .reading, .validating])
        transfer.advance(.confirming)
        XCTAssertFalse(transfer.running); XCTAssertFalse(transfer.finished); XCTAssertFalse(transfer.cancellable)
        var apply = ICloudTransfer(kind: .restore, stage: .restoring)
        apply.advance(.restoring, completed: 0, total: 0)
        XCTAssertNil(apply.fraction)
        apply.advance(.replacing)
        XCTAssertFalse(apply.cancellable)
        apply.advance(.failed, detail: "磁盘已满")
        XCTAssertEqual(apply.lastActive, .replacing)
        XCTAssertEqual(apply.steps, [.restoring, .replacing, .reloading])
        XCTAssertTrue(apply.finished); XCTAssertEqual(apply.title, "还原失败")
        var backup = ICloudTransfer(kind: .backup, stage: .writing)
        XCTAssertNil(backup.fraction)
        backup.advance(.done)
        XCTAssertEqual(backup.title, "备份已写入")
        XCTAssertFalse(ICloudUploadStatus(url: URL(fileURLWithPath: "/a"), state: .waiting).settled)
        XCTAssertFalse(ICloudUploadStatus(url: URL(fileURLWithPath: "/a"), state: .waiting).text.contains("已确认"))
        XCTAssertTrue(ICloudUploadStatus(url: URL(fileURLWithPath: "/a"), state: .uploaded).settled)
    }

    func testICloudReadAndRestoreReportPerBookProgressAndRejectEmptyOrBrokenBackups() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let store = ICloudBackupStore(root: base.appendingPathComponent("cloud"))
        let disk = try LibraryDisk(owner: "guest", base: base)
        let books = (0..<3).map { Book(id: "b\($0)", title: "书\($0)", format: "TXT", chapters: [Chapter(title: "一", text: "第\($0)句。")]) }
        let archive = ICloudArchive(owner: "guest", books: books.map { .init(packet: .init(book: $0, progress: .init()), bookmarks: []) })
        let url = try store.save(archive)
        XCTAssertEqual(try store.downloadState(url, owner: "guest", request: false), .ready)
        XCTAssertEqual(try store.uploadState(url), .notUbiquitous)
        let calls = ProgressCalls()
        let read = try store.read(url, owner: "guest") { calls.add($0, $1) }
        XCTAssertEqual(calls.values, [[0, 3], [1, 3], [2, 3], [3, 3]])
        let restored = ProgressCalls()
        let rows = try disk.restore(read, owner: "guest", entries: [], progress: { restored.add($0, $1) }, willReplace: { restored.add(-1, -1) })
        XCTAssertEqual(restored.values, [[0, 3], [1, 3], [2, 3], [3, 3], [-1, -1]])
        XCTAssertEqual(rows.count, 3)

        XCTAssertThrowsError(try ICloudArchive(owner: "guest", books: []).validated(owner: "guest")) {
            XCTAssertTrue($0.localizedDescription.contains("不包含书籍"))
        }
        let before = try Data(contentsOf: disk.root.appendingPathComponent("catalog.json"))
        XCTAssertThrowsError(try disk.restore(ICloudArchive(owner: "guest", books: []), owner: "guest", entries: rows))
        XCTAssertEqual(try Data(contentsOf: disk.root.appendingPathComponent("catalog.json")), before)
        try Data("{\"format\":1}".utf8).write(to: url)
        XCTAssertThrowsError(try store.read(url, owner: "guest")) { XCTAssertTrue($0.localizedDescription.contains("无法解析")) }
    }

    func testICloudSnapshotsListUndownloadedPlaceholdersAndReportDownloadState() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let store = ICloudBackupStore(root: base)
        let directory = try store.directory(owner: "guest")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data().write(to: directory.appendingPathComponent(".2000-b.json.icloud"))
        try Data().write(to: directory.appendingPathComponent("1000-a.json"))
        try Data().write(to: directory.appendingPathComponent("notes.txt"))
        let list = try store.snapshots(owner: "guest")
        XCTAssertEqual(list.map(\.lastPathComponent), ["2000-b.json", "1000-a.json"])
        XCTAssertEqual(try store.downloadState(list[0], owner: "guest", request: false), .downloading)
        XCTAssertThrowsError(try store.decode(list[0], owner: "guest")) { XCTAssertTrue($0.localizedDescription.contains("尚未从 iCloud 下载完成")) }
        XCTAssertThrowsError(try store.downloadState(directory.appendingPathComponent("3000-c.json"), owner: "guest", request: false)) {
            XCTAssertTrue($0.localizedDescription.contains("已被移除"))
        }
        XCTAssertThrowsError(try store.downloadState(base.appendingPathComponent("x.json"), owner: "guest", request: false))
        XCTAssertTrue(try ICloudBackupStore(root: base.appendingPathComponent("none")).snapshots(owner: "guest").isEmpty)
    }

    @MainActor func testProgressSyncStatusReportsOnlyLocalFacts() throws {
        let suite = "tests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = MemoryKeyValueStore()
        var signedIn = false
        let sync = ProgressSync(store: store, defaults: defaults, account: { signedIn })
        XCTAssertEqual(sync.summary(enabled: true).title, "等待 iCloud")
        signedIn = true; sync.refreshAccount()
        XCTAssertEqual(sync.summary(enabled: true).title, "已开启 · 等待 iCloud")
        XCTAssertTrue(sync.synchronize())

        let book = Book(id: "sync", title: "同步", format: "TXT", chapters: [Chapter(title: "一", text: "一。二。"), Chapter(title: "二", text: "三。")])
        var entry = ShelfEntry(book: book, progress: .init(chapter: 1, position: 0, updatedAt: 100))
        XCTAssertTrue(sync.push(entry))
        XCTAssertFalse(sync.push(entry), "远端已有同样新的进度时不重复提交")
        sync.recordCommit(1)
        XCTAssertEqual(sync.lastCommitCount, 1)
        let summary = sync.summary(enabled: true)
        XCTAssertEqual(summary.title, "已开启")
        for text in [summary.detail, ICloudUploadStatus(url: URL(fileURLWithPath: "/a"), state: .uploading).text] {
            XCTAssertFalse(text.contains("已上传") || text.contains("已送达") || text.contains("秒内"))
        }

        store.values[ProgressSync.key(entry)] = ["c": 0, "p": 1, "t": 200.0]
        XCTAssertTrue(sync.receive(reason: NSUbiquitousKeyValueStoreServerChange, keys: [ProgressSync.key(entry), "other"]))
        XCTAssertEqual(sync.lastReceivedCount, 1)
        XCTAssertEqual(sync.newer(than: entry), ReadingProgress(chapter: 0, position: 1, updatedAt: 200))
        sync.recordMerge(applied: 0, kept: 1)
        XCTAssertEqual(sync.lastKept, 1)
        XCTAssertFalse(sync.receive(reason: NSUbiquitousKeyValueStoreServerChange, keys: ["unrelated"]))
        entry.progress.updatedAt = 300
        XCTAssertNil(sync.newer(than: entry))

        sync.recordFailure("合并其他设备的阅读进度失败：磁盘已满")
        XCTAssertEqual(sync.summary(enabled: true).title, "同步出错")
        sync.recordMerge(applied: 0, kept: 0)
        XCTAssertNil(sync.lastError)
        XCTAssertFalse(sync.receive(reason: NSUbiquitousKeyValueStoreQuotaViolationChange, keys: []))
        XCTAssertTrue(sync.summary(enabled: true).problem)
        store.available = false
        XCTAssertFalse(sync.synchronize())
        XCTAssertEqual(sync.lastError, ProgressSync.unavailableMessage)
        store.available = true
        XCTAssertTrue(sync.synchronize())
        XCTAssertNil(sync.lastError)

        defaults.set(false, forKey: ProgressSync.enabledKey)
        XCTAssertFalse(sync.push(entry))
        XCTAssertNil(sync.newer(than: ShelfEntry(book: book)))
        XCTAssertEqual(sync.summary(enabled: false).title, "已关闭")
    }

    @MainActor private func makeSync(_ store: MemoryKeyValueStore) throws -> (ProgressSync, UserDefaults, String) {
        let suite = "tests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        return (ProgressSync(store: store, defaults: defaults, account: { true }), defaults, suite)
    }
    private func syncBook(_ title: String = "红楼梦", author: String = "曹雪芹", chapters: Int = 3) -> Book {
        Book(id: UUID().uuidString, title: title, author: author, format: "TXT", chapters: (0..<chapters).map { Chapter(title: "\($0)", text: "一。二。三。") })
    }

    @MainActor func testClosingReaderDoesNotOverwriteNewerRemoteProgressAndAppliesItAfterwards() throws {
        let store = MemoryKeyValueStore()
        let (sync, defaults, suite) = try makeSync(store); defer { defaults.removePersistentDomain(forName: suite) }
        let book = syncBook()
        let local = ShelfEntry(book: book, progress: .init(chapter: 1, position: 0, updatedAt: 100))
        store.values[ProgressSync.key(local)] = ["c": 2, "p": 1, "t": 200.0]
        // 阅读中：远端进度被搁置。
        let reading = sync.merge([local], protected: [book.id])
        XCTAssertEqual(reading.kept, 1); XCTAssertTrue(reading.applied.isEmpty)
        XCTAssertEqual(reading.entries[0].progress, local.progress)
        // 关闭阅读页：位置未变，不产生新时间戳，也不推送。
        XCTAssertNil(sync.update(local, chapter: 1, position: 0, now: 999_999))
        XCTAssertFalse(sync.push(local))
        XCTAssertEqual((store.values[ProgressSync.key(local)] as? [String: Any])?["t"] as? Double, 200)
        // 关闭后重新合并：应用远端。
        let closed = sync.merge(reading.entries, protected: [])
        XCTAssertEqual(closed.applied, [book.id])
        XCTAssertEqual(closed.entries[0].progress, ReadingProgress(chapter: 2, position: 1, updatedAt: 200))
        // 真正移动了位置才写入。
        XCTAssertNotNil(sync.update(closed.entries[0], chapter: 2, position: 2))
        XCTAssertNotNil(sync.update(ShelfEntry(book: book), chapter: 0, position: 0), "未开卷的书首次打开需要记录")
    }

    @MainActor func testLocalWritesAfterSeeingRemoteAreNewerDespiteClockSkew() throws {
        let store = MemoryKeyValueStore()
        let (sync, defaults, suite) = try makeSync(store); defer { defaults.removePersistentDomain(forName: suite) }
        let book = syncBook()
        let local = ShelfEntry(book: book, progress: .init(chapter: 0, position: 0, updatedAt: 1_000))
        let fast = 5_000_000.0  // 另一台设备时钟快了很多
        store.values[ProgressSync.key(local)] = ["c": 1, "p": 0, "t": fast]
        let merged = sync.merge([local], protected: [])
        XCTAssertEqual(merged.entries[0].progress.updatedAt, fast)
        XCTAssertEqual(sync.clock, fast)
        let mine = try XCTUnwrap(sync.update(merged.entries[0], chapter: 1, position: 2, now: 2_000))
        XCTAssertEqual(mine.updatedAt, fast + 1)
        var moved = merged.entries[0]; moved.progress = mine
        XCTAssertTrue(sync.push(moved), "看过远端之后的本机操作必须被视为更新")
        XCTAssertEqual((store.values[ProgressSync.key(local)] as? [String: Any])?["p"] as? Int, 2)
        XCTAssertGreaterThan(sync.stamp(now: 0), mine.updatedAt, "时间戳单调递增")
        XCTAssertEqual(sync.stamp(now: 9e9), 9e9, "本机时钟更晚时直接用本机时间")
        let reloaded = ProgressSync(store: store, defaults: defaults, account: { true })
        XCTAssertGreaterThanOrEqual(reloaded.clock, 9e9, "时钟持久保存")
    }

    @MainActor func testFingerprintIgnoresChapterCountAndWhitespaceAndKeepsLegacyKeys() throws {
        let store = MemoryKeyValueStore()
        let (sync, defaults, suite) = try makeSync(store); defer { defaults.removePersistentDomain(forName: suite) }
        let a = ShelfEntry(book: syncBook("Red  Chamber", author: "Cao Xueqin", chapters: 3))
        let b = ShelfEntry(book: syncBook("red chamber", author: " CAO XUEQIN ", chapters: 5))
        let c = ShelfEntry(book: syncBook("Ｒｅｄ Chamber", author: "Cao Xueqin", chapters: 2))
        XCTAssertEqual(ProgressSync.key(a), ProgressSync.key(b))
        XCTAssertEqual(ProgressSync.key(a), ProgressSync.key(c), "全角半角视为同一书名")
        XCTAssertNotEqual(ProgressSync.key(a), ProgressSync.key(ShelfEntry(book: syncBook("Red Chamber 2", author: "Cao Xueqin"))))
        XCTAssertNotEqual(ProgressSync.key(a), ProgressSync.key(ShelfEntry(book: syncBook("Red Chamber", author: "Other"))))
        XCTAssertNotEqual(ProgressSync.key(a), ProgressSync.legacyKey(a))
        XCTAssertTrue(ProgressSync.key(a).hasPrefix("progress."))
        // 删并章节后仍匹配；越界章节不应用。
        store.values[ProgressSync.key(b)] = ["c": 4, "p": 0, "t": 50.0]
        XCTAssertNil(sync.newer(than: a), "远端章节超出本机章数时忽略")
        store.values[ProgressSync.key(b)] = ["c": 2, "p": 1, "t": 50.0]
        XCTAssertEqual(sync.newer(than: a)?.chapter, 2)
        // 旧版本写入的旧键仍可读取，并迁移到新键；推送时新旧键同时写入。
        store.values = [:]
        let old = ShelfEntry(book: syncBook(chapters: 3))
        store.values[ProgressSync.legacyKey(old)] = ["c": 1, "p": 2, "t": 80.0]
        let migrated = sync.merge([old], protected: [])
        XCTAssertEqual(migrated.entries[0].progress, ReadingProgress(chapter: 1, position: 2, updatedAt: 80))
        var mine = migrated.entries[0]
        mine.progress = try XCTUnwrap(sync.update(mine, chapter: 2, position: 0, now: 10))
        XCTAssertTrue(sync.push(mine))
        for key in [ProgressSync.key(old), ProgressSync.legacyKey(old)] {
            XCTAssertEqual((store.values[key] as? [String: Any])?["c"] as? Int, 2)
        }
        // 新键较旧、旧键较新时取较新的一条。
        store.values[ProgressSync.legacyKey(old)] = ["c": 0, "p": 0, "t": 1e12]
        XCTAssertEqual(sync.newer(than: mine)?.updatedAt, 1e12)
    }

    func testCatalystEntitlementsIncludeKeyValueStore() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        for name in ["Tingye-macOS.entitlements", "Tingye.entitlements"] {
            let data = try Data(contentsOf: root.appendingPathComponent("Tingye/" + name))
            let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
            XCTAssertEqual(plist["com.apple.developer.ubiquity-kvstore-identifier"] as? String, "$(TeamIdentifierPrefix)$(CFBundleIdentifier)", name)
        }
    }

    @MainActor func testOriginalWebViewHighlightsAcrossTagsRepeatedSentencesAndClears() async throws {
        let loaded = expectation(description: "WebKit loaded")
        let delegate = LoadDelegate { loaded.fulfill() }
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        config.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 600), configuration: config)
        web.navigationDelegate = delegate
        let html = "<p>春<b>风</b>📖。归来。</p><p>归来。</p><script>window.unsafe = true;</script>"
        let chapter = HTMLText.chapter(html, title: "正文")
        web.loadHTMLString(OriginalDocument.html(html, css: ""), baseURL: nil)
        await fulfillment(of: [loaded], timeout: 40)
        let sentences = Sentence.split(chapter.text)
        XCTAssertEqual(sentences.count, 3)
        let first = try await web.evaluateJavaScript(OriginalSpeechHighlight.script(text: chapter.text, range: sentences[0].range, follow: true, color: "#dce8e1"), in: nil, contentWorld: .defaultClient)
        XCTAssertEqual(first as? Int, 3)
        let highlighted = try await web.evaluateJavaScript("Array.from(document.querySelectorAll('mark[data-ty-speech]')).map(m=>m.textContent).join('')", in: nil, contentWorld: .defaultClient)
        XCTAssertEqual(highlighted as? String, "春风📖。")
        _ = try await web.evaluateJavaScript(OriginalSpeechHighlight.script(text: chapter.text, range: sentences[2].range, follow: false, color: "#35504a"), in: nil, contentWorld: .defaultClient)
        let repeated = try await web.evaluateJavaScript("document.querySelectorAll('p')[1].querySelector('mark').textContent", in: nil, contentWorld: .defaultClient)
        XCTAssertEqual(repeated as? String, "归来。")
        _ = try await web.evaluateJavaScript(OriginalSpeechHighlight.script(text: chapter.text, range: nil, follow: false, color: "#35504a"), in: nil, contentWorld: .defaultClient)
        let remaining = try await web.evaluateJavaScript("document.querySelectorAll('mark').length", in: nil, contentWorld: .defaultClient)
        XCTAssertEqual(remaining as? Int, 0)
        let bold = try await web.evaluateJavaScript("document.querySelector('b').textContent", in: nil, contentWorld: .defaultClient)
        XCTAssertEqual(bold as? String, "风")
        let publicationScriptRan = try await web.evaluateJavaScript("window.unsafe === true", in: nil, contentWorld: .page)
        XCTAssertEqual(publicationScriptRan as? Bool, false)
        withExtendedLifetime(delegate) {}
    }

    /// 原书图文为横向分页：长文产生多页；跟读定位到后面页的句子时自动翻到该页。
    @MainActor func testOriginalWebViewPagingAndAutoPageTurn() async throws {
        let loaded = expectation(description: "WebKit loaded")
        let delegate = LoadDelegate { loaded.fulfill() }
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        config.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 600), configuration: config)
        web.navigationDelegate = delegate
        let text = (1...300).map { "这是第\($0)句用来铺满多页的话。" }.joined()
        web.loadHTMLString(OriginalDocument.html("<p>\(text)</p>", css: ""), baseURL: nil)
        await fulfillment(of: [loaded], timeout: 40)
        // 等排版与字体应用完成后再量宽度。
        try await Task.sleep(for: .milliseconds(300))
        let pageWidth = try await web.evaluateJavaScript("innerWidth", in: nil, contentWorld: .page) as? Int
        let pages = try await web.evaluateJavaScript("Math.ceil(document.documentElement.scrollWidth / innerWidth)", in: nil, contentWorld: .page) as? Int
        XCTAssertEqual(pageWidth, 390)
        XCTAssertGreaterThan(pages ?? 0, 1, "长文应排成多个横页")
        let sentences = Sentence.split(text)
        let marked = try await web.evaluateJavaScript(OriginalSpeechHighlight.script(text: text, range: sentences.last?.range, follow: true, color: "#dce8e1"), in: nil, contentWorld: .defaultClient)
        XCTAssertGreaterThan(marked as? Int ?? 0, 0, "末句应被高亮")
        let offsetX = try await web.evaluateJavaScript("Math.round(scrollX / innerWidth)", in: nil, contentWorld: .page) as? Int
        XCTAssertGreaterThan(offsetX ?? 0, 0, "跟读末句应自动翻到后面页")
        withExtendedLifetime(delegate) {}
    }

    /// 与纯文本模式一致按字跟随：同一长句跨多页时，读到哪个字就翻到那个字所在页；不跟随时只报告页码不翻页。
    @MainActor func testOriginalWebViewFollowsSpokenCharacterWithinLongSentence() async throws {
        let loaded = expectation(description: "WebKit loaded")
        let delegate = LoadDelegate { loaded.fulfill() }
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        config.websiteDataStore = .nonPersistent()
        // 句子最长 180 字（Sentence.split 会切开更长的）：用矮视图让一个 170 字的单句横跨好几页。
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 200), configuration: config)
        web.navigationDelegate = delegate
        let text = String(repeating: "长", count: 170) + "。"
        web.loadHTMLString(OriginalDocument.html("<p>\(text)</p>", css: ""), baseURL: nil)
        await fulfillment(of: [loaded], timeout: 40)
        try await Task.sleep(for: .milliseconds(300))
        let sentences = Sentence.split(text)
        XCTAssertEqual(sentences.count, 1, "整段应是一个长句")
        let sentence = try XCTUnwrap(sentences.first?.range)
        _ = try await web.evaluateJavaScript(OriginalSpeechHighlight.script(text: text, range: sentence, follow: true, color: "#dce8e1", spoken: 0), in: nil, contentWorld: .defaultClient)
        let start = try await web.evaluateJavaScript("Math.round(scrollX / innerWidth)", in: nil, contentWorld: .page) as? Int
        XCTAssertEqual(start, 0, "刚开始读，停在第一页")
        let late = OriginalSpeechHighlight.spokenIndex(text: text, sentence: sentence, offset: NSMaxRange(sentence) - 3)
        let quiet = try await web.evaluateJavaScript(OriginalSpeechHighlight.followScript(spoken: late, follow: false), in: nil, contentWorld: .defaultClient) as? Int ?? -1
        XCTAssertGreaterThan(quiet, 0, "读到句尾的字在后面的页")
        let unmoved = try await web.evaluateJavaScript("Math.round(scrollX / innerWidth)", in: nil, contentWorld: .page) as? Int
        XCTAssertEqual(unmoved, 0, "不跟随时不翻页")
        let page = try await web.evaluateJavaScript(OriginalSpeechHighlight.followScript(spoken: late, follow: true), in: nil, contentWorld: .defaultClient) as? Int ?? -1
        let moved = try await web.evaluateJavaScript("Math.round(scrollX / innerWidth)", in: nil, contentWorld: .page) as? Int
        XCTAssertEqual(moved, page, "跟随时翻到读到的字所在页")
        XCTAssertEqual(page, quiet)
        withExtendedLifetime(delegate) {}
    }

    /// 夜间纸色下，书籍样式写死的深色正文要改成阅读页正文色；浅色底的提示框里保留深色字。
    @MainActor func testOriginalWebViewFixesLowContrastBookColorsAtNight() async throws {
        let loaded = expectation(description: "WebKit loaded")
        let delegate = LoadDelegate { loaded.fulfill() }
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        config.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 600), configuration: config)
        web.navigationDelegate = delegate
        let html = #"<p class="normal">正文写死成深灰。</p><div class="note"><p>提示框里的字。</p></div>"#
        let css = ".normal{color:#333} .note{background:#fff8dc} .note p{color:#999}"
        web.loadHTMLString(OriginalDocument.html(html, css: css, color: "#e8e6e3", background: "transparent", paper: "#1c1b19"), baseURL: nil)
        await fulfillment(of: [loaded], timeout: 40)
        _ = try await web.evaluateJavaScript(OriginalSpeechHighlight.script(text: "正文写死成深灰。\n提示框里的字。", range: nil, follow: false, color: "#4a3226"), in: nil, contentWorld: .defaultClient)
        let body = try await web.evaluateJavaScript("getComputedStyle(document.querySelector('.normal')).color", in: nil, contentWorld: .page) as? String
        let note = try await web.evaluateJavaScript("getComputedStyle(document.querySelector('.note p')).color", in: nil, contentWorld: .page) as? String
        XCTAssertEqual(body, "rgb(232, 230, 227)", "深色底上的正文改用阅读页正文色")
        XCTAssertEqual(note, "rgb(20, 17, 15)", "浅色提示框里改用深色字（v2 现代书店墨色 #14110F）")
        withExtendedLifetime(delegate) {}
    }

    /// 每栏起点必须恰好落在整页边界上：书籍 CSS 改 body 边距时，翻到后面的页也不能错位。
    @MainActor func testOriginalWebViewColumnsAlignToPagesDespiteBookCSS() async throws {
        let loaded = expectation(description: "WebKit loaded")
        let delegate = LoadDelegate { loaded.fulfill() }
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        config.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 600), configuration: config)
        web.navigationDelegate = delegate
        let text = (1...400).map { "这是第\($0)句用来铺满多页的话。" }.joined()
        let css = "body.calibre{margin:0 5%;padding:0 12px;max-width:30em} body{margin:3em}"
        web.loadHTMLString(OriginalDocument.html("<body class=\"calibre\"><p>\(text)</p></body>", css: css), baseURL: nil)
        await fulfillment(of: [loaded], timeout: 40)
        try await Task.sleep(for: .milliseconds(300))
        _ = try await web.evaluateJavaScript(OriginalSpeechHighlight.script(text: text, range: nil, follow: false, color: "#dce8e1"), in: nil, contentWorld: .defaultClient)
        let lefts = try await web.evaluateJavaScript("Array.from(document.querySelector('p').getClientRects()).map(r => Math.round(r.left + scrollX))", in: nil, contentWorld: .page) as? [Int] ?? []
        XCTAssertGreaterThan(lefts.count, 3, "长文应排成多个横页")
        XCTAssertEqual(lefts, lefts.indices.map { $0 * 390 }, "每页起点应为整页宽的倍数")
        let width = try await web.evaluateJavaScript("document.documentElement.scrollWidth", in: nil, contentWorld: .page) as? Int ?? 0
        XCTAssertEqual(width % 390, 0, "总宽应为整页宽的倍数")
        withExtendedLifetime(delegate) {}
    }
}

@MainActor private final class LoadDelegate: NSObject, WKNavigationDelegate {
    let complete: () -> Void
    init(complete: @escaping () -> Void) { self.complete = complete }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { complete() }
}

final class ExtendedReadingTests: XCTestCase {
    @MainActor func testLongScrollingDocumentRestoresPositionAfterLayoutAndResize() {
        let chapter = Chapter(title: "Long", text: (1...400).map { "第\($0)句测试。" + String(repeating: "长段落与自动换行，", count: 12) + "结束。\n" }.joined())
        let source = NativeTypesetter.attributed(chapter, preferences: .init())
        let offset = (chapter.text as NSString).range(of: "第199句测试").location
        let view = ReaderScrollTextView(usingTextLayoutManager: false)
        view.textContainer.lineFragmentPadding = 0
        view.attributedText = source
        view.requestPosition(offset)
        // Request comes before SwiftUI supplies a nonzero frame.
        view.layoutIfNeeded()
        for width in [340.0, 290.0, 650.0] {
            view.frame = CGRect(x: 0, y: 0, width: width, height: 500)
            view.setNeedsLayout(); view.layoutIfNeeded()
            let glyph = view.layoutManager.glyphRange(forCharacterRange: NSRange(location: offset, length: 1), actualCharacterRange: nil)
            let rect = view.layoutManager.boundingRect(forGlyphRange: glyph, in: view.textContainer).offsetBy(dx: view.textContainerInset.left, dy: view.textContainerInset.top)
            XCTAssertTrue(view.bounds.intersects(rect), "Saved sentence must be visible after layout at width \(width)")
            XCTAssertGreaterThan(view.contentOffset.y, 1000)
        }
        let later = (chapter.text as NSString).range(of: "第300句测试").location
        view.requestPosition(later); view.layoutIfNeeded()
        let glyph = view.layoutManager.glyphRange(forCharacterRange: NSRange(location: later, length: 1), actualCharacterRange: nil)
        let rect = view.layoutManager.boundingRect(forGlyphRange: glyph, in: view.textContainer).offsetBy(dx: 0, dy: view.textContainerInset.top)
        XCTAssertTrue(view.bounds.intersects(rect))
    }
    @MainActor func testPDFImportRetainsPagesAndReadableText() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 400, height: 600))
        let data = renderer.pdfData { context in
            for index in 1...2 {
                context.beginPage()
                ("Page \(index). Read this text." as NSString).draw(at: CGPoint(x: 30, y: 30), withAttributes: [.font: UIFont.systemFont(ofSize: 20)])
            }
        }
        try data.write(to: url)
        let imported = try BookImporter.read(url).book
        XCTAssertEqual(imported.chapters.count, 2)
        XCTAssertTrue(imported.chapters[1].text.contains("Page 2"))
        XCTAssertEqual(imported.pdf, data)
    }
    func testMarkdownAndBackupFileImportAndInvalidJSON() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let markdown = base.appendingPathComponent("sample.md")
        try Data("# 第一章\n**正文**与[链接](https://example.com)。".utf8).write(to: markdown)
        let book = try BookImporter.read(markdown).book
        XCTAssertTrue(book.chapters[0].text.contains("正文与链接。"))
        // Markdown 的原书图文与正文同源：两种模式的高亮与进度一致。
        let document = book.chapters[0].fields["document"]?.object
        XCTAssertTrue(document?["html"]?.string?.contains("正文与链接。") == true)
        XCTAssertEqual(OriginalDocument.fromText("一 & <二>\n\n三"), "<p>一 &amp; &lt;二&gt;</p><p>三</p>")
        let backup = base.appendingPathComponent("backup.json")
        let progress = ReadingProgress(chapter: 0, position: 0, updatedAt: 999)
        try Integrity.encoder().encode(BackupPacket(book: book, progress: progress)).write(to: backup)
        let imported = try BookImporter.read(backup)
        XCTAssertEqual(imported.book, book); XCTAssertEqual(imported.progress, progress)
        try Data("{broken".utf8).write(to: backup)
        XCTAssertThrowsError(try BookImporter.read(backup))
    }
}

private final class ProgressCalls: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [[Int]] = []
    func add(_ done: Int, _ total: Int) { lock.lock(); stored.append([done, total]); lock.unlock() }
    var values: [[Int]] { lock.lock(); defer { lock.unlock() }; return stored }
}

private final class MemoryKeyValueStore: ProgressKeyValueStore {
    var values: [String: Any] = [:]
    var available = true
    func dictionary(forKey key: String) -> [String: Any]? { values[key] as? [String: Any] }
    func set(_ value: Any?, forKey key: String) { values[key] = value }
    func removeObject(forKey key: String) { values[key] = nil }
    var dictionaryRepresentation: [String: Any] { values }
    func synchronize() -> Bool { available }
}


// MARK: - 1.14 书库、书源、阅读与听书增强

import ZIPFoundation

extension NativeCoreTests {
    func testPalmDOCDecompressionHandlesLiteralsSpacesAndBackReferences() {
        // "abc" + 回溯 3 字节取 3 字节 + 「空格 + A」
        XCTAssertEqual(MobiReader.palmDOC([0x61, 0x62, 0x63, 0x80, 0x18, 0xC1]), Array("abcabc A".utf8))
        // 1…8 为原样字节段（多字节 UTF-8 走这里）
        let han = Array("书".utf8)
        XCTAssertEqual(MobiReader.palmDOC([UInt8(han.count)] + han), han)
    }

    func testMobiTrailingEntriesAreStripped() {
        // 多字节重叠 1 字节（低两位 0 → 1 字节）+ 一条 3 字节 TBS 记录（末字节 0x83）
        let record: [UInt8] = [0x41, 0x42, 0x00, 0xAA, 0xBB, 0x83]
        XCTAssertEqual(MobiReader.trailingSize(record, flags: 0b11), 4)
        XCTAssertEqual(MobiReader.trailingSize(record, flags: 0), 0)
    }

    func testMobiImportReadsTitleAuthorAndSplitsOnPageBreaks() throws {
        func be16(_ v: Int) -> [UInt8] { [UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)] }
        func be32(_ v: Int) -> [UInt8] { [UInt8(v >> 24 & 0xFF), UInt8(v >> 16 & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)] }
        let html = Array("<p>第一章正文。</p><mbp:pagebreak/><h1>第二回</h1><p>hello hello</p>".utf8)
        // PalmDOC 压缩：全部用 8 字节原样段编码
        var compressed: [UInt8] = []
        var i = 0
        while i < html.count { let n = min(8, html.count - i); compressed.append(UInt8(n)); compressed += html[i..<i + n]; i += n }
        let textRecord = compressed + [0x00, 0xAA, 0xBB, 0x83]
        let title = Array("测试书名".utf8), author = Array("鲁迅".utf8)
        let headerLength = 0xE8
        var r0 = [UInt8](repeating: 0, count: 16 + headerLength)
        r0.replaceSubrange(0..<2, with: be16(2))                 // PalmDOC 压缩
        r0.replaceSubrange(4..<8, with: be32(html.count))
        r0.replaceSubrange(8..<10, with: be16(1))                // 1 条正文记录
        r0.replaceSubrange(10..<12, with: be16(4096))
        r0.replaceSubrange(16..<20, with: Array("MOBI".utf8))
        r0.replaceSubrange(20..<24, with: be32(headerLength))
        r0.replaceSubrange(28..<32, with: be32(65001))           // UTF-8
        r0.replaceSubrange(0x6C..<0x70, with: be32(0xFFFF_FFFF))  // 没有图片
        r0.replaceSubrange(0x80..<0x84, with: be32(0x40))         // 有 EXTH
        r0.replaceSubrange(0xF2..<0xF4, with: be16(0b11))         // 尾部附加数据
        let exth = Array("EXTH".utf8) + be32(12 + 8 + author.count) + be32(1) + be32(100) + be32(8 + author.count) + author
        let nameOffset = r0.count + exth.count
        r0.replaceSubrange(0x54..<0x58, with: be32(nameOffset))
        r0.replaceSubrange(0x58..<0x5C, with: be32(title.count))
        r0 += exth + title + [0, 0]
        var file = [UInt8](repeating: 0, count: 78)
        file.replaceSubrange(60..<68, with: Array("BOOKMOBI".utf8))
        file.replaceSubrange(76..<78, with: be16(2))
        let first = 78 + 16 + 2
        file += be32(first) + be32(0) + be32(first + r0.count) + be32(1) + [0, 0]
        file += r0 + textRecord
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tingye-test.mobi")
        try Data(file).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let book = try BookImporter.read(url).book
        XCTAssertEqual(book.title, "测试书名")
        XCTAssertEqual(book.author, "鲁迅")
        XCTAssertEqual(book.format, "MOBI")
        XCTAssertEqual(book.chapters.count, 2)
        XCTAssertEqual(book.chapters[0].text.trimmingCharacters(in: .whitespacesAndNewlines), "第一章正文。")
        XCTAssertEqual(book.chapters[1].title, "第二回")
        XCTAssertTrue(book.chapters[1].text.contains("hello hello"))
    }

    func testMobiWithDRMIsRejected() throws {
        var file = [UInt8](repeating: 0, count: 78)
        file.replaceSubrange(60..<68, with: Array("BOOKMOBI".utf8))
        file[77] = 2
        file += [0, 0, 0, 96, 0, 0, 0, 0, 0, 0, 0, 112, 0, 0, 0, 1, 0, 0]
        var r0 = [UInt8](repeating: 0, count: 16); r0[1] = 2; r0[9] = 1; r0[13] = 2   // encryption = 2
        file += r0 + [0x41]
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tingye-drm.azw")
        try Data(file).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertThrowsError(try BookImporter.read(url)) { XCTAssertTrue($0.localizedDescription.contains("DRM")) }
    }

    func testComicZipImportsImagesInNaturalOrderAsPages() throws {
        let png = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 6)).pngData { context in UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 4, height: 6)) }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tingye-comic.cbz")
        try? FileManager.default.removeItem(at: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let archive = try Archive(url: url, accessMode: .create)
        for name in ["10.png", "2.png", "1.png", "__MACOSX/._1.png", "readme.txt"] {
            let data = name.hasSuffix(".txt") ? Data("hi".utf8) : png
            try archive.addEntry(with: name, type: .file, uncompressedSize: Int64(data.count)) { position, size in data.subdata(in: Int(position)..<Int(position) + size) }
        }
        let book = try BookImporter.read(url).book
        XCTAssertEqual(book.format, "CBZ")
        XCTAssertEqual(book.fields["comic"]?.bool, true)
        XCTAssertEqual(book.chapters.map(\.title), ["第 1 页", "第 2 页", "第 3 页"])
        XCTAssertNotNil(book.coverData)
        let entry = ShelfEntry(book: book)
        XCTAssertTrue(entry.isComic)
        XCTAssertEqual(entry.chapterCount, 3)
    }

    func testChineseConversionKeepsLengthSoSentenceCoordinatesStay() {
        let simplified = "简体中文，这里是书库与阅读进度。"
        let traditional = ChineseConvert.apply(simplified, "s2t")
        XCTAssertNotEqual(traditional, simplified)
        XCTAssertEqual(traditional.utf16.count, simplified.utf16.count)
        XCTAssertTrue(traditional.contains("簡體"))
        XCTAssertEqual(ChineseConvert.apply(traditional, "t2s"), simplified)
        XCTAssertEqual(ChineseConvert.apply(simplified, "none"), simplified)
    }

    func testDialogueRolesUseAttributionAroundQuotes() {
        let sentences = Sentence.split("天色已晚。\n他笑道：“你来了。”\n“快走！”\n她喊了一声。\n“谁在那里？”")
        XCTAssertEqual(sentences.map(\.text), ["天色已晚。", "他笑道：“你来了。”", "“快走！”", "她喊了一声。", "“谁在那里？”"])
        XCTAssertEqual(DialogueRoles.role(0, in: sentences), .narrator)
        XCTAssertEqual(DialogueRoles.role(1, in: sentences), .male)
        XCTAssertEqual(DialogueRoles.role(2, in: sentences), .female, "纯引语看后一句的说话提示")
        XCTAssertEqual(DialogueRoles.role(4, in: sentences), .narrator, "判断不出来时用旁白")
        XCTAssertEqual(DialogueRoles.attribution("他对她说"), .male, "最先出现的称谓是说话人")
        var options = VoiceOptions(provider: "system", model: "", voice: "narrator", rate: 1, key: "", groupID: "")
        XCTAssertEqual(options.forRole(.female).voice, "narrator", "未开启分角色时始终用旁白")
        options.roles = true; options.femaleVoice = "female"
        XCTAssertEqual(options.forRole(.female).voice, "female")
        XCTAssertEqual(options.forRole(.male).voice, "narrator", "没选男声时沿用旁白")
    }

    func testOPDSFeedParsesNavigationAcquisitionPagingAndSearch() {
        let xml = """
        <feed xmlns="http://www.w3.org/2005/Atom">
          <link rel="next" href="/opds/new?page=2" type="application/atom+xml;profile=opds-catalog"/>
          <link rel="search" href="/opds/search?q={searchTerms}" type="application/atom+xml"/>
          <entry><title>最新书籍</title><link rel="subsection" href="/opds/new" type="application/atom+xml;profile=opds-catalog;kind=acquisition"/></entry>
          <entry><title>故乡</title><author><name>鲁迅</name></author><summary>&lt;p&gt;小说&lt;/p&gt;</summary>
            <link rel="http://opds-spec.org/acquisition" href="/get/pdf/1" type="application/pdf"/>
            <link rel="http://opds-spec.org/acquisition" href="/get/epub/1" type="application/epub+zip"/>
            <link rel="http://opds-spec.org/image/thumbnail" href="/cover/1"/></entry>
        </feed>
        """
        let feed = OPDSFeed.parse(Data(xml.utf8), base: URL(string: "http://nas.local:8083/opds")!)
        XCTAssertEqual(feed.next?.absoluteString, "http://nas.local:8083/opds/new?page=2")
        XCTAssertEqual(feed.searchTemplate, "/opds/search?q={searchTerms}")
        XCTAssertEqual(feed.entries.count, 2)
        XCTAssertNil(feed.entries[0].acquisition)
        XCTAssertEqual(feed.entries[0].navigation?.absoluteString, "http://nas.local:8083/opds/new")
        XCTAssertEqual(feed.entries[1].author, "鲁迅")
        XCTAssertEqual(feed.entries[1].summary, "小说")
        XCTAssertEqual(feed.entries[1].acquisition?.fileExtension, "epub", "多个格式时优先 EPUB")
        XCTAssertEqual(feed.entries[1].thumbnail?.absoluteString, "http://nas.local:8083/cover/1")
        XCTAssertTrue(ImportableFile.accepts("书.AZW3"))
        XCTAssertFalse(ImportableFile.accepts("封面.jpg"))
    }

    func testGroupPathsAreNormalizedAndOldCatalogsStillDecode() throws {
        XCTAssertEqual(AppModel.normalizedGroup(" 科幻 / 阿西莫夫 /"), "科幻/阿西莫夫")
        XCTAssertEqual(AppModel.normalizedGroup("//"), "")
        // 1.13 及更早的书库目录没有分组、隐藏、划线、添加时间字段
        let book = Book(title: "春", format: "TXT", chapters: [Chapter(title: "一", text: "盼望着。东风来了。")])
        var entry = ShelfEntry(book: book)
        entry.group = "散文"; entry.hidden = true
        entry.highlights = [Highlight(chapter: 0, start: 0, end: 1, text: "盼望着。东风来了。", color: "green", style: "wavy", note: "好")]
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(entry)) as! [String: Any]
        let restored = try JSONDecoder().decode(ShelfEntry.self, from: JSONEncoder().encode(entry))
        XCTAssertEqual(restored.notes.first?.style, "wavy")
        XCTAssertTrue(restored.isHidden)
        for key in ["group", "hidden", "highlights", "addedAt"] { object[key] = nil }
        let old = try JSONDecoder().decode(ShelfEntry.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(old.group); XCTAssertFalse(old.isHidden); XCTAssertTrue(old.notes.isEmpty)
        // 跨端备份协议不含整理字段
        let packet = try JSONSerialization.jsonObject(with: JSONEncoder().encode(BackupPacket(book: book, progress: .init()))) as! [String: Any]
        XCTAssertNil(packet["highlights"]); XCTAssertNil(packet["group"])
    }

    func testHighlightMarksMapSentencesToCharacterRangesOnEachPage() {
        let text = "第一句。第二句。第三句。"
        let sentences = Sentence.split(text)
        let range = ReaderMark.range(start: 1, end: 2, in: sentences)
        XCTAssertEqual(range.map { (text as NSString).substring(with: $0) }, "第二句。第三句。")
        XCTAssertNil(ReaderMark.range(start: 2, end: 5, in: sentences))
        // 只给落在本页的部分加标记，坐标换成页内坐标
        let page = NSAttributedString(string: (text as NSString).substring(with: NSRange(location: 4, length: 4)))
        let marked = ReaderMark.apply([ReaderMark(range: range!, color: "yellow", kind: "underline")], to: page, pageRange: NSRange(location: 4, length: 4))
        var effective = NSRange()
        XCTAssertNotNil(marked.attribute(.tyMark, at: 0, effectiveRange: &effective))
        XCTAssertEqual(effective, NSRange(location: 0, length: 4))
        XCTAssertTrue(Highlight(chapter: 0, start: 1, end: 2, text: "").contains(chapter: 0, sentence: 2))
    }

    func testGLMWavNormalizationCustomVoiceAndSpeakableText() throws {
        // 1. 纯符号/分割线不具备可朗读字符，含中英文或数字才算可朗读
        XCTAssertFalse(CloudSpeech.hasSpeakableText(""))
        XCTAssertFalse(CloudSpeech.hasSpeakableText("   \n\t "))
        XCTAssertFalse(CloudSpeech.hasSpeakableText("***"))
        XCTAssertFalse(CloudSpeech.hasSpeakableText("———"))
        XCTAssertFalse(CloudSpeech.hasSpeakableText("……"))
        XCTAssertFalse(CloudSpeech.hasSpeakableText("”"))
        XCTAssertTrue(CloudSpeech.hasSpeakableText("第一章"))
        XCTAssertTrue(CloudSpeech.hasSpeakableText("123"))
        XCTAssertTrue(CloudSpeech.hasSpeakableText("Hello!"))

        // 2. GLM 支持自定义/复刻音色，同时拦截其他服务商遗留音色；分角色音色同样按服务商校验
        XCTAssertEqual(VoiceOptions.sanitized(provider: "glm", model: "glm-tts", voice: "my_cloned_voice_01").voice, "my_cloned_voice_01")
        XCTAssertEqual(VoiceOptions.sanitized(provider: "glm", model: "glm-tts", voice: "female-shaonv").voice, "tongtong")
        XCTAssertEqual(VoiceOptions.sanitized(provider: "glm", model: "glm-tts", voice: "com.apple.voice.compact.zh-CN.Tingting").voice, "tongtong")
        XCTAssertEqual(VoiceOptions.sanitized(provider: "glm", model: "glm-tts", voice: "zh-CN-XiaoxiaoNeural").voice, "tongtong")
        XCTAssertEqual(VoiceOptions.sanitized(provider: "glm", model: "glm-tts", voice: "21m00Tcm4TlvDq8ikWAM").voice, "tongtong")
        XCTAssertEqual(VoiceOptions.sanitizedRoleVoice(provider: "glm", voice: ""), "")
        XCTAssertEqual(VoiceOptions.sanitizedRoleVoice(provider: "glm", voice: "female-shaonv"), "")
        XCTAssertEqual(VoiceOptions.sanitizedRoleVoice(provider: "glm", voice: "xiaochen"), "xiaochen")
        XCTAssertEqual(VoiceOptions.sanitizedRoleVoice(provider: "glm", voice: "my_cloned_voice_01"), "my_cloned_voice_01")
        XCTAssertEqual(VoiceOptions.sanitizedRoleVoice(provider: "azure", voice: "tongtong"), "")
        XCTAssertEqual(VoiceOptions.sanitizedRoleVoice(provider: "azure", voice: "zh-CN-YunxiNeural"), "zh-CN-YunxiNeural")

        // 3. WAV 校验与修复：支持 RIFF 长度少 4、流式 0xFFFFFFFF 占位长度、末尾奇数块未补齐，同时拒绝真正截断的音频
        let rate = 16000
        var samples = [Int16](repeating: 0, count: rate / 4)
        samples += (0..<rate / 2).map { Int16(8000 * sin(Double($0) * 0.2)) }
        func makeWav(riffSize: UInt32, dataSize: UInt32, trailingExtra: [UInt8] = []) -> Data {
            var wav = Data("RIFF".utf8)
            func put(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { wav.append(contentsOf: $0) } }
            func put16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { wav.append(contentsOf: $0) } }
            put(riffSize); wav.append(contentsOf: Array("WAVEfmt ".utf8))
            put(16); put16(1); put16(1); put(UInt32(rate)); put(UInt32(rate * 2)); put16(2); put16(16)
            wav.append(contentsOf: Array("data".utf8)); put(dataSize)
            for sample in samples { put16(UInt16(bitPattern: sample)) }
            wav.append(contentsOf: trailingExtra)
            return wav
        }
        let pcmBytes = UInt32(samples.count * 2)
        // (a) GLM 常见 RIFF 长度少算 4 字节
        let shortRiff = makeWav(riffSize: 32 + pcmBytes, dataSize: pcmBytes)
        let fixedShort = try CloudSpeech.normalizedWav(shortRiff)
        XCTAssertEqual(fixedShort.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 4, as: UInt32.self).littleEndian }, 36 + pcmBytes)
        // (b) 流式 WAV 头（RIFF 与 data 长度均为 0xFFFFFFFF）
        let streamingWav = makeWav(riffSize: 0xFFFF_FFFF, dataSize: 0xFFFF_FFFF)
        let fixedStreaming = try CloudSpeech.normalizedWav(streamingWav)
        XCTAssertEqual(fixedStreaming.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 4, as: UInt32.self).littleEndian }, 36 + pcmBytes)
        XCTAssertEqual(fixedStreaming.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 40, as: UInt32.self).littleEndian }, pcmBytes)
        XCTAssertNotNil(CloudSpeech.speechSpan(wav: streamingWav))
        // (c) 末尾附带奇数长度扩展块且未补齐 pad byte
        let oddTail: [UInt8] = Array("LIST".utf8) + [3, 0, 0, 0, 1, 2, 3]
        let oddChunkWav = makeWav(riffSize: 36 + pcmBytes + UInt32(oddTail.count), dataSize: pcmBytes, trailingExtra: oddTail)
        XCTAssertNoThrow(try CloudSpeech.normalizedWav(oddChunkWav))
        // (d) 真正截断的 WAV 仍被拒绝
        let truncatedWav = makeWav(riffSize: 36 + pcmBytes, dataSize: pcmBytes + 100)
        XCTAssertThrowsError(try CloudSpeech.normalizedWav(truncatedWav))
    }

    func testGLMBalanceErrorIsNotRetriedAsRateLimit() {
        let balance = Data(#"{"error":{"code":"1113","message":"余额不足或无可用资源包,请充值。"}}"#.utf8)
        let error = CloudSpeech.glmFailure(429, data: balance)
        XCTAssertFalse(error is APIError, "1113 不应按限流重试")
        XCTAssertTrue(error.localizedDescription.contains("glm-tts"))
        let rate = Data(#"{"error":{"code":1302,"message":"并发数过高"}}"#.utf8)
        XCTAssertEqual((CloudSpeech.glmFailure(429, data: rate) as? APIError)?.status, 429)
    }
}

extension NativeCoreTests {
    @MainActor func testHiddenReadingSessionsRequireUnlockAndReturnAfterUnhiding() {
        var hidden = ShelfEntry(book: Book(id: "hidden-book", title: "私密书", format: "TXT", chapters: [Chapter(title: "一", text: "正文。")]))
        hidden.hidden = true
        let visible = ShelfEntry(book: Book(id: "visible-book", title: "公开书", format: "TXT", chapters: [Chapter(title: "一", text: "正文。")]))
        let sessions = [hidden, visible].map { entry in
            ReadingSession(bookID: entry.id, title: entry.title, start: Date(), end: Date(), seconds: 30, listening: false)
        }
        XCTAssertEqual(AppModel.visibleSessions(sessions, entries: [hidden, visible], hiddenUnlocked: false).map(\.bookID), [visible.id])
        XCTAssertEqual(AppModel.visibleSessions(sessions, entries: [hidden, visible], hiddenUnlocked: true), sessions)
        hidden.hidden = nil
        XCTAssertEqual(AppModel.visibleSessions(sessions, entries: [hidden, visible], hiddenUnlocked: false), sessions)
    }

    @MainActor func testOriginalReaderRestoresSavesAndJumpsWithoutSpeech() async throws {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        config.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 480), configuration: config)
        let coordinator = OriginalBookView.Coordinator()
        coordinator.view = web
        coordinator.key = "chapter-0"
        coordinator.follow = false
        let text = (1...300).map { "这是第\($0)句用于验证原书阅读位置的正文。" }.joined()
        coordinator.readingScript = OriginalReadingPosition.script(text: text)
        coordinator.script = OriginalSpeechHighlight.script(text: text, range: nil, follow: false, color: "#ffff00")
        coordinator.requestPosition(80, revision: 0)
        web.navigationDelegate = coordinator
        web.loadHTMLString(OriginalDocument.html("<p>\(text)</p>", css: ""), baseURL: nil)
        for _ in 0..<200 {
            if coordinator.loaded { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertTrue(coordinator.loaded)
        try await Task.sleep(for: .milliseconds(700))
        let initialPage = try await web.evaluateJavaScript("Math.round(scrollX / innerWidth)", in: nil, contentWorld: .page) as? Int ?? 0
        XCTAssertGreaterThan(initialPage, 0, "没有播放声音时也应恢复到章内保存的位置")
        let marks = try await web.evaluateJavaScript("document.querySelectorAll('mark[data-ty-speech]').length", in: nil, contentWorld: .page) as? Int
        XCTAssertEqual(marks, 0, "恢复阅读位置不应制造朗读高亮")

        // 窗口缩小等真实视口变化仍需重排，并让同一句完整落在可见页内。
        web.frame.size.height = 300
        web.layoutIfNeeded()
        coordinator.viewportDidChange(web)
        try await Task.sleep(for: .milliseconds(500))
        let offset = Sentence.split(text)[80].range.location
        let resizedJSON = try await web.evaluateJavaScript("""
            (() => {
              const node = document.querySelector('p').firstChild, range = document.createRange();
              range.setStart(node, \(offset)); range.setEnd(node, \(offset + 1));
              const rect = range.getBoundingClientRect();
              return JSON.stringify({left:rect.left, right:rect.right, top:rect.top, bottom:rect.bottom, width:innerWidth, height:innerHeight, scroll:scrollX});
            })()
            """, in: nil, contentWorld: .page) as! String
        let resized = try JSONSerialization.jsonObject(with: Data(resizedJSON.utf8)) as! [String: Double]
        XCTAssertEqual(resized["height"]!, 300, accuracy: 1)
        XCTAssertGreaterThanOrEqual(resized["left"]!, -1, "缩小视口后仍应显示原阅读句的首字")
        XCTAssertLessThanOrEqual(resized["right"]!, resized["width"]! + 1)
        XCTAssertGreaterThanOrEqual(resized["top"]!, -1)
        XCTAssertLessThanOrEqual(resized["bottom"]!, resized["height"]! + 1, "正文不可藏在阅读工具下")
        let resizedPage = resized["scroll"]! / resized["width"]!
        XCTAssertEqual(resizedPage, resizedPage.rounded(), accuracy: 0.01, "重排后应停在整页边界")
        XCTAssertEqual(coordinator.readingPosition, 80)
        web.frame.size.height = 480
        web.layoutIfNeeded()
        coordinator.viewportDidChange(web)
        try await Task.sleep(for: .milliseconds(500))
        let expandedPage = try await web.evaluateJavaScript("Math.round(scrollX / innerWidth)", in: nil, contentWorld: .page) as? Int
        XCTAssertEqual(expandedPage, initialPage, "收起工具后仍应回到相同阅读句所在页")

        let saved = expectation(description: "Manual page saved")
        var savedPosition = -1
        coordinator.onPositionChange = { position in savedPosition = position; saved.fulfill() }
        XCTAssertTrue(coordinator.accessibilityNextPage())
        await fulfillment(of: [saved], timeout: 5)
        XCTAssertGreaterThan(savedPosition, 80)
        try await Task.sleep(for: .milliseconds(400))
        let manualPage = try await web.evaluateJavaScript("Math.round(scrollX / innerWidth)", in: nil, contentWorld: .page) as? Int
        XCTAssertEqual(manualPage, initialPage + 1)

        // 翻页回写不能反过来跳到句首；书签/搜索的显式 revision 必须触发定位。
        coordinator.requestPosition(savedPosition, revision: 0)
        XCTAssertNil(coordinator.pendingPosition)
        coordinator.requestPosition(240, revision: 1)
        coordinator.restorePosition(web)
        let jumped = try await web.evaluateJavaScript("Math.round(scrollX / innerWidth)", in: nil, contentWorld: .page) as? Int ?? 0
        XCTAssertGreaterThan(jumped, initialPage + 1)
        coordinator.requestPosition(savedPosition, revision: 2)
        coordinator.restorePosition(web)
        let restored = try await web.evaluateJavaScript("Math.round(scrollX / innerWidth)", in: nil, contentWorld: .page) as? Int
        // 跨端进度精确到句子；页首句横跨两页时，应从该句起点恢复，避免漏读。
        XCTAssertGreaterThan(restored ?? 0, 0)
        XCTAssertTrue((0...1).contains((manualPage ?? 0) - (restored ?? 0)))
        coordinator.onPositionChange = { _ in XCTFail("旧翻页回调不能覆盖新的同章书签跳转") }
        _ = coordinator.accessibilityNextPage()
        coordinator.requestPosition(260, revision: 3)
        coordinator.restorePosition(web)
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(coordinator.readingPosition, 260)
        withExtendedLifetime(coordinator) {}
    }

    @MainActor func testOriginalReadingPositionSurvivesRepeatedTextAndSpeechMarkup() async throws {
        let loaded = expectation(description: "Reading positions loaded")
        let delegate = LoadDelegate { loaded.fulfill() }
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        config.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 400), configuration: config)
        web.navigationDelegate = delegate
        let text = String(repeating: "重复的📖句子。\n", count: 160)
        let html = String(repeating: "<p>重复的<b>📖句子</b>。</p>", count: 160)
        web.loadHTMLString(OriginalDocument.html(html, css: ""), baseURL: nil)
        await fulfillment(of: [loaded], timeout: 40)
        _ = try await web.evaluateJavaScript(OriginalReadingPosition.script(text: text), in: nil, contentWorld: .defaultClient)
        let late = try await web.evaluateJavaScript(OriginalReadingPosition.restore(120), in: nil, contentWorld: .defaultClient) as? Int ?? -1
        XCTAssertGreaterThan(late, 0)
        let before = try await web.evaluateJavaScript(OriginalReadingPosition.read(page: late), in: nil, contentWorld: .defaultClient) as? Int
        let sentences = Sentence.split(text)
        _ = try await web.evaluateJavaScript(OriginalSpeechHighlight.script(text: text, range: sentences[120].range, follow: false, color: "#ffff00"), in: nil, contentWorld: .defaultClient)
        let after = try await web.evaluateJavaScript(OriginalReadingPosition.read(page: late), in: nil, contentWorld: .defaultClient) as? Int
        XCTAssertEqual(before, after)
        XCTAssertGreaterThan(after ?? 0, 100)
        let first = try await web.evaluateJavaScript(OriginalReadingPosition.restore(0), in: nil, contentWorld: .defaultClient) as? Int
        XCTAssertEqual(first, 0)
        withExtendedLifetime(delegate) {}
    }
}
import MediaPlayer

extension NativeCoreTests {
    @MainActor func testSwitchingBooksRecalculatesLockScreenDuration() throws {
        let defaults = UserDefaults.standard
        let savedProvider = defaults.object(forKey: "voice.provider")
        let savedRate = defaults.object(forKey: "voice.rate")
        defaults.set("system", forKey: "voice.provider")
        defaults.set(1.0, forKey: "voice.rate")
        defer {
            defaults.set(savedProvider, forKey: "voice.provider")
            defaults.set(savedRate, forKey: "voice.rate")
        }
        let player = SpeechPlayer()
        defer { player.stop() }
        let first = Book(id: "audio-cache-first", title: "短章", format: "TXT", chapters: [Chapter(title: "一", text: "甲。乙。")])
        let text = String(repeating: "甲", count: 99) + "。" + String(repeating: "乙", count: 99) + "。"
        let second = Book(id: "audio-cache-second", title: "长章", format: "TXT", chapters: [Chapter(title: "一", text: text)])
        player.start(book: first, chapter: 0, position: 0)
        player.pause()
        let firstDuration = try XCTUnwrap(MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyPlaybackDuration] as? Double)
        player.start(book: second, chapter: 0, position: 0)
        player.pause()
        let secondDuration = try XCTUnwrap(MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyPlaybackDuration] as? Double)
        XCTAssertEqual(player.count, 2)
        XCTAssertEqual(firstDuration, 4.0 / 4.5, accuracy: 0.001)
        XCTAssertEqual(secondDuration, 200.0 / 4.5, accuracy: 0.001)
    }

    @MainActor func testCloudRequestsShareRetainedPrefetch() async throws {
        let pool = SpeechRequestPool<String>()
        let gate = AudioRequestTestGate()
        let started = expectation(description: "prefetch started")
        var calls = 0
        let first = Task { try await pool.value(for: "next sentence") {
            calls += 1; started.fulfill()
            await gate.wait()
            return "audio"
        } }
        await fulfillment(of: [started], timeout: 2)
        let second = Task { try await pool.value(for: "next sentence") { calls += 1; return "duplicate" } }
        pool.retainOnly(["next sentence"])
        try await Task.sleep(for: .milliseconds(30))
        gate.open()
        let firstResult = try await first.value, secondResult = try await second.value
        XCTAssertEqual(firstResult, "audio")
        XCTAssertEqual(secondResult, "audio")
        XCTAssertEqual(calls, 1, "Moving to a prefetched sentence must reuse the same request")
    }

    @MainActor func testCloudRequestsCancelObsoleteWorkAndBoundActualConcurrency() async throws {
        let pool = SpeechRequestPool<String>()
        let cleanup = AudioRequestTestGate()
        let started = expectation(description: "two requests started"); started.expectedFulfillmentCount = 2
        let cancelled = expectation(description: "obsolete requests cancelled"); cancelled.expectedFulfillmentCount = 2
        var active = 0, peak = 0
        var invoked: [String] = []
        func operation(_ key: String, old: Bool) async throws -> String {
            invoked.append(key); active += 1; peak = max(peak, active)
            defer { active -= 1 }
            if old {
                started.fulfill()
                do { try await Task.sleep(for: .seconds(30)) }
                catch {
                    cancelled.fulfill()
                    // The provider may take time to finish cancellation. Its slot must stay occupied.
                    await cleanup.wait()
                    throw error
                }
            }
            return key
        }
        let a = Task { try await pool.value(for: "a") { try await operation("a", old: true) } }
        let b = Task { try await pool.value(for: "b") { try await operation("b", old: true) } }
        await fulfillment(of: [started], timeout: 2)
        pool.retainOnly(["c", "d"])
        await fulfillment(of: [cancelled], timeout: 2)
        let c = Task { try await pool.value(for: "c") { try await operation("c", old: false) } }
        let d = Task { try await pool.value(for: "d") { try await operation("d", old: false) } }
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(Set(invoked), ["a", "b"], "New requests must wait until cancellation has finished")
        pool.retainOnly(["d"])
        try await Task.sleep(for: .milliseconds(30))
        cleanup.open()
        for task in [a, b, c] {
            do { _ = try await task.value; XCTFail("Obsolete work should be cancelled") }
            catch { XCTAssertTrue(error is CancellationError) }
        }
        let result = try await d.value
        XCTAssertEqual(result, "d")
        XCTAssertFalse(invoked.contains("c"), "Cancelled queued work must never call the provider")
        XCTAssertLessThanOrEqual(peak, 2)
        XCTAssertEqual(active, 0)
    }

    @MainActor func testCancelledRequestCannotRemoveItsSameKeyReplacement() async throws {
        let pool = SpeechRequestPool<String>()
        let oldGate = AudioRequestTestGate(), newGate = AudioRequestTestGate()
        let oldStarted = expectation(description: "old request started")
        let newStarted = expectation(description: "replacement request started")
        let old = Task { try await pool.value(for: "sentence") {
            oldStarted.fulfill(); await oldGate.wait(); return "old"
        } }
        await fulfillment(of: [oldStarted], timeout: 2)
        pool.retainOnly()
        let replacement = Task { try await pool.value(for: "sentence") {
            newStarted.fulfill(); await newGate.wait(); return "replacement"
        } }
        await fulfillment(of: [newStarted], timeout: 2)
        oldGate.open()
        do { _ = try await old.value; XCTFail("The old result must be discarded") }
        catch { XCTAssertTrue(error is CancellationError) }
        var duplicates = 0
        let joined = Task { try await pool.value(for: "sentence") { duplicates += 1; return "duplicate" } }
        try await Task.sleep(for: .milliseconds(30))
        newGate.open()
        let replacementResult = try await replacement.value, joinedResult = try await joined.value
        XCTAssertEqual(replacementResult, "replacement")
        XCTAssertEqual(joinedResult, "replacement")
        XCTAssertEqual(duplicates, 0)
    }
}

@MainActor private final class AudioRequestTestGate {
    private var opened = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        guard !opened else { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func open() {
        opened = true
        let pending = waiters; waiters = []
        for waiter in pending { waiter.resume() }
    }
}
extension NativeCoreTests {
    @MainActor func testICloudRestoreAdoptsNewCatalogDespitePendingSave() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "tests.restore." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { try? FileManager.default.removeItem(at: base); defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: ProgressSync.enabledKey)
        let disk = try LibraryDisk(owner: "restore-test", base: base)
        let original = Book(id: "existing", title: "原书", format: "TXT", chapters: [Chapter(title: "一", text: "一。二。三。")])
        let added = Book(id: "added", title: "备份里的书", format: "TXT", chapters: [Chapter(title: "一", text: "新书。")])
        try disk.write(original); try disk.saveCatalog([ShelfEntry(book: original)])
        let model = AppModel(disk: disk, progressSync: ProgressSync(store: MemoryKeyValueStore(), defaults: defaults, account: { false }))
        model.saveProgress(original.id, chapter: 0, position: 1)
        var restored = original; restored.fields["title"] = .string("恢复后的书")
        let bookmark = Bookmark(chapter: 0, position: 2, excerpt: "三。")
        let archive = ICloudArchive(owner: "restore-test", books: [
            .init(packet: .init(book: restored, progress: .init(chapter: 0, position: 2, updatedAt: 20)), bookmarks: [bookmark]),
            .init(packet: .init(book: added, progress: .init()), bookmarks: [])
        ])
        model.restoreICloud(archive)
        await model.icloudTask?.value
        model.flushPendingSaves()
        XCTAssertEqual(model.icloud?.stage, .done)
        XCTAssertEqual(Set(model.entries.map(\.id)), ["existing", "added"])
        XCTAssertEqual(Set(try disk.catalog().map(\.id)), ["existing", "added"])
        XCTAssertEqual(model.entries.first { $0.id == original.id }?.progress.position, 2)
        XCTAssertEqual(try disk.catalog().first { $0.id == original.id }?.bookmarks.first?.id, bookmark.id)
        XCTAssertEqual(try disk.read(original.id).title, "恢复后的书")
        // 等待取消后的旧索引任务已经全部退出，再清理测试目录。
        _ = try await model.beginLibraryRestore()
    }

    @MainActor func testLibraryRestoreBlocksEditsAndPreservesOriginalOnFailure() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "tests.restore." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { try? FileManager.default.removeItem(at: base); defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: ProgressSync.enabledKey)
        let disk = try LibraryDisk(owner: "restore-test", base: base)
        let book = Book(id: "original", title: "原书", format: "TXT", chapters: [Chapter(title: "一", text: "一。二。")])
        try disk.write(book); try disk.saveCatalog([ShelfEntry(book: book)])
        let model = AppModel(disk: disk, progressSync: ProgressSync(store: MemoryKeyValueStore(), defaults: defaults, account: { false }))
        model.saveProgress(book.id, chapter: 0, position: 1)
        let rows = try await model.beginLibraryRestore()
        let expected = try Integrity.encoder().encode(rows)
        model.saveProgress(book.id, chapter: 0, position: 0)
        model.bookmark(book.id, chapter: 0, position: 0, excerpt: "一。")
        model.move([book.id], toGroup: "不应写入")
        model.flushPendingSaves()
        XCTAssertThrowsError(try model.removeLocal(book.id))
        do { try await model.add(book); XCTFail("还原期间不得导入") } catch {}
        do {
            try await model.importFiles([base.appendingPathComponent("not-opened.txt")])
            XCTFail("还原期间不得开始解析导入文件")
        } catch { XCTAssertTrue(error.localizedDescription.contains("正在还原书库")) }
        XCTAssertEqual(try Integrity.encoder().encode(model.entries), expected)
        XCTAssertEqual(try Data(contentsOf: disk.root.appendingPathComponent("catalog.json")), expected)
        model.endLibraryRestore(nil)
        let invalid = ICloudArchive(owner: "restore-test", books: [
            .init(packet: .init(book: book, progress: .init(chapter: 99, position: 0, updatedAt: 1)), bookmarks: [])
        ])
        model.restoreICloud(invalid)
        await model.icloudTask?.value
        XCTAssertEqual(model.icloud?.stage, .failed)
        XCTAssertFalse(model.restoringLibrary)
        XCTAssertEqual(try disk.read(book.id), book)
        XCTAssertEqual(try Integrity.encoder().encode(model.entries), expected)
        XCTAssertEqual(try Data(contentsOf: disk.root.appendingPathComponent("catalog.json")), expected)
        _ = try await model.beginLibraryRestore()
    }

    func testRestoreInvalidatesOnlyRestoredBookIndexes() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let disk = try LibraryDisk(owner: "guest", base: base)
        let original = Book(id: "existing", title: "原书", format: "TXT", chapters: [Chapter(title: "一", text: "原文。")])
        let kept = Book(id: "kept", title: "保留", format: "TXT", chapters: [Chapter(title: "一", text: "保留。")])
        for book in [original, kept] { try disk.write(book); disk.saveIndex(book.id, category: "旧分类", cover: Data([1, 2, 3])) }
        try disk.saveCatalog([original, kept].map { ShelfEntry(book: $0) })
        var replacement = original; replacement.fields["category"] = .string("新分类")
        let archive = ICloudArchive(owner: "guest", books: [.init(packet: .init(book: replacement, progress: .init()), bookmarks: [])])
        _ = try disk.restore(archive, owner: "guest", entries: disk.catalog())
        XCTAssertNil(disk.cachedIndex(original.id))
        XCTAssertFalse(FileManager.default.fileExists(atPath: disk.root.appendingPathComponent("Index/existing.jpg").path))
        XCTAssertEqual(disk.cachedIndex(kept.id)?.0.category, "旧分类")
        XCTAssertEqual(disk.cachedIndex(kept.id)?.1, Data([1, 2, 3]))
        XCTAssertEqual(try disk.read(original.id).fields["category"]?.string, "新分类")
    }
}
extension NativeCoreTests {
    func testHUFFRejectsInvalidCodesWithoutTrappingAndBoundsExpansion() throws {
        let records = importFixHuffRecords()
        XCTAssertEqual(try HuffCDIC(records).unpack([0], limit: 8), Array(repeating: UInt8(65), count: 8))
        XCTAssertThrowsError(try HuffCDIC(records).unpack([0], limit: 7))
        XCTAssertEqual(try HuffCDIC(records).unpack([], limit: 0), [])

        var badHuff = Array(records[0])
        importFixPut32(31, into: &badHuff, at: 16)
        importFixPut32(1, into: &badHuff, at: 1040 + 30 * 8)
        let bad = try HuffCDIC([badHuff[...], records[1]])
        XCTAssertThrowsError(try bad.unpack([0, 0, 0, 1]))
    }

    func testHUFFRejectsOversizedOrTruncatedDictionaryMetadata() throws {
        let records = importFixHuffRecords()
        var badBits = Array(records[1])
        importFixPut32(63, into: &badBits, at: 12)
        var badCount = Array(records[1])
        importFixPut32(UInt32.max, into: &badCount, at: 8)
        importFixPut32(31, into: &badCount, at: 12)
        var badOffset = Array(records[1])
        importFixPut16(1, into: &badOffset, at: 16)
        var badLength = Array(records[1])
        importFixPut16(0x8002, into: &badLength, at: 18)
        for bad in [badBits, badCount, badOffset, badLength] {
            XCTAssertThrowsError(try HuffCDIC([records[0], bad[...]]))
        }
        XCTAssertThrowsError(try HuffCDIC([records[0]]))
        XCTAssertEqual(MobiReader.u32([UInt8](repeating: 0, count: 4), -1), 0)
        XCTAssertEqual(MobiReader.u16([UInt8](), 0), 0)
    }

    func testMobiRejectsOutOfRangeHUFFRecordCountBeforeAllocation() throws {
        var header = [UInt8](repeating: 0, count: 132)
        importFixPut16(17480, into: &header, at: 0)
        importFixPut16(1, into: &header, at: 8)
        header.replaceSubrange(16..<20, with: Array("MOBI".utf8))
        importFixPut32(116, into: &header, at: 20)
        importFixPut32(2, into: &header, at: 0x70)
        importFixPut32(UInt32.max, into: &header, at: 0x74)
        let url = try importFixMobiFile(records: [header, [0], Array(importFixHuffRecords()[0])])
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertThrowsError(try BookImporter.read(url))
    }

    func testMobiChapterCountDoesNotDropEnding() throws {
        var header = [UInt8](repeating: 0, count: 16)
        importFixPut16(1, into: &header, at: 0)
        importFixPut16(1, into: &header, at: 8)
        for count in [3000, 3001] {
            let parts = Array(repeating: "body", count: count - 1) + ["UNIQUE_ENDING"]
            let body = Array(parts.joined(separator: "<mbp:pagebreak/>").utf8)
            let url = try importFixMobiFile(records: [header, body])
            defer { try? FileManager.default.removeItem(at: url) }
            let imported = try BookImporter.read(url)
            XCTAssertEqual(imported.book.chapters.count, count)
            XCTAssertTrue(imported.book.chapters.last?.text.contains("UNIQUE_ENDING") == true)
        }
    }

    func testImportAcceptsBooksBeyondFormerSizeAndChapterLimits() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }

        let text = String(repeating: "字", count: 4_000_001)
        let textURL = base.appendingPathComponent("large.txt")
        try Data(text.utf8).write(to: textURL)
        let largeText = try BookImporter.read(textURL).book
        XCTAssertEqual(largeText.chapters.reduce(0) { $0 + $1.text.utf16.count }, 4_000_001)

        let manyChapters = Book(title: "章节很多的书", format: "TXT", chapters: (0..<3001).map { Chapter(title: "第 \($0 + 1) 章", text: "正文") })
        XCTAssertNoThrow(try manyChapters.validated())
        XCTAssertEqual(manyChapters.chapters.count, 3001)

        let oversized = base.appendingPathComponent("oversized.epub")
        XCTAssertTrue(FileManager.default.createFile(atPath: oversized.path, contents: nil))
        let handle = try FileHandle(forWritingTo: oversized)
        try handle.truncate(atOffset: 100 * 1024 * 1024 + 1)
        try handle.close()
        XCTAssertThrowsError(try BookImporter.read(oversized)) { error in
            XCTAssertFalse(error.localizedDescription.contains("100 MB"), "损坏文件可以报错，但不能再触发旧的文件大小上限")
        }

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 400, height: 600))
        var pdf = renderer.pdfData { context in
            context.beginPage()
            ("Large PDF remains readable" as NSString).draw(at: CGPoint(x: 30, y: 30), withAttributes: [.font: UIFont.systemFont(ofSize: 20)])
        }
        pdf.append(Data("\n%".utf8))
        pdf.append(Data(repeating: 0x20, count: 22 * 1024 * 1024))
        let pdfURL = base.appendingPathComponent("large.pdf")
        try pdf.write(to: pdfURL)
        let largePDF = try BookImporter.read(pdfURL).book
        XCTAssertEqual(largePDF.chapters.count, 1)
        XCTAssertTrue(largePDF.chapters[0].text.contains("Large PDF remains readable"))
        XCTAssertEqual(largePDF.pdf, pdf)
    }

    func testSourceCredentialsAreLimitedToTheConfiguredOrigin() throws {
        let client = SourceHTTPClient(baseURL: URL(string: "https://library.example/opds")!, authorization: "Basic test-only")
        for address in ["https://library.example/book.epub", "https://LIBRARY.example:443/search.xml"] {
            let request = client.authorized(URLRequest(url: URL(string: address)!))
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Basic test-only")
        }
        for address in ["https://other.example/book.epub", "http://library.example/search.xml", "https://library.example:8443/opds", "file:///tmp/book.epub"] {
            var request = URLRequest(url: URL(string: address)!)
            request.setValue("Basic inherited-secret", forHTTPHeaderField: "Authorization")
            XCTAssertNil(client.authorized(request).value(forHTTPHeaderField: "Authorization"))
        }

        let xml = "<feed xmlns='http://www.w3.org/2005/Atom'><link rel='search' type='application/opensearchdescription+xml' href='https://other.example/search.xml'/></feed>"
        let feed = OPDSFeed.parse(Data(xml.utf8), base: URL(string: "https://library.example/opds")!)
        let description = try XCTUnwrap(feed.searchDescription)
        XCTAssertNil(client.authorized(URLRequest(url: description)).value(forHTTPHeaderField: "Authorization"))
    }

    func testSourceRedirectsRecheckCredentialsWithoutAnyNetworkRequest() throws {
        let origin = URL(string: "https://library.example/opds")!
        let client = SourceHTTPClient(baseURL: origin, authorization: "Basic test-only")
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let task = session.dataTask(with: origin) // Never resumed: no request or credentials leave this process.
        let response = try XCTUnwrap(HTTPURLResponse(url: origin, statusCode: 302, httpVersion: "HTTP/1.1", headerFields: nil))
        for (address, expected) in [("https://other.example/book", false), ("http://library.example/book", false), ("https://library.example:8443/book", false), ("https://library.example:443/book", true)] {
            var redirected = URLRequest(url: URL(string: address)!)
            redirected.setValue("Basic inherited-secret", forHTTPHeaderField: "Authorization")
            client.urlSession(session, task: task, willPerformHTTPRedirection: response, newRequest: redirected) { request in
                XCTAssertEqual(request?.value(forHTTPHeaderField: "Authorization"), expected ? "Basic test-only" : nil)
            }
        }
    }

    private func importFixHuffRecords() -> [ArraySlice<UInt8>] {
        var huff = [UInt8](repeating: 0, count: 1296)
        huff.replaceSubrange(0..<4, with: Array("HUFF".utf8))
        importFixPut32(16, into: &huff, at: 8)
        importFixPut32(1040, into: &huff, at: 12)
        for index in 0..<256 { importFixPut32(index < 128 ? 0x81 : 0x181, into: &huff, at: 16 + index * 4) }
        var cdic = [UInt8](repeating: 0, count: 21)
        cdic.replaceSubrange(0..<4, with: Array("CDIC".utf8))
        importFixPut32(1, into: &cdic, at: 8)
        importFixPut16(2, into: &cdic, at: 16)
        importFixPut16(0x8001, into: &cdic, at: 18)
        cdic[20] = 65
        return [huff[...], cdic[...]]
    }

    private func importFixMobiFile(records: [[UInt8]]) throws -> URL {
        var data = [UInt8](repeating: 0, count: 78 + records.count * 8)
        data.replaceSubrange(60..<68, with: Array("BOOKMOBI".utf8))
        importFixPut16(UInt16(records.count), into: &data, at: 76)
        var offset = data.count
        for (index, record) in records.enumerated() {
            importFixPut32(UInt32(offset), into: &data, at: 78 + index * 8)
            offset += record.count
        }
        for record in records { data += record }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("import-fix-" + UUID().uuidString + ".mobi")
        try Data(data).write(to: url)
        return url
    }

    private func importFixPut16(_ value: UInt16, into bytes: inout [UInt8], at offset: Int) {
        bytes[offset] = UInt8(truncatingIfNeeded: value >> 8)
        bytes[offset + 1] = UInt8(truncatingIfNeeded: value)
    }

    private func importFixPut32(_ value: UInt32, into bytes: inout [UInt8], at offset: Int) {
        for index in 0..<4 { bytes[offset + index] = UInt8(truncatingIfNeeded: value >> ((3 - index) * 8)) }
    }
}

extension NativeCoreTests {
    @MainActor func testMiniMaxFinishesAudioWhenSubtitleEndsEarly() async throws {
        try await assertMiniMaxFinishesAudio(rate: 1, unmatchedEnding: false)
    }

    @MainActor func testMiniMaxFinishesUnmatchedLastWordAtDoubleRate() async throws {
        try await assertMiniMaxFinishesAudio(rate: 2, unmatchedEnding: true)
    }

    @MainActor private func assertMiniMaxFinishesAudio(rate: Double, unmatchedEnding: Bool) async throws {
        let defaults = UserDefaults.standard
        let settingKeys = ["voice.provider", "voice.rate", "voice.roles"]
        let savedSettings = settingKeys.map { defaults.object(forKey: $0) }
        defaults.set("minimax", forKey: "voice.provider")
        defaults.set(rate, forKey: "voice.rate")
        defaults.set(false, forKey: "voice.roles")
        defer {
            for (key, value) in zip(settingKeys, savedSettings) {
                if let value { defaults.set(value, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
        }

        let config = VoiceOptions.load()
        let unique = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let firstText = "开头\(unique)的最后数字是2026。"
        let nextText = "下一句\(unique)已经提前缓存。"
        let sentences = Sentence.split(firstText + nextText)
        XCTAssertEqual(sentences.map(\.text), [firstText, nextText])
        let firstRange = try XCTUnwrap(sentences.first?.range)
        let wav = miniMaxTailTestWav(seconds: 2.4)
        XCTAssertEqual(try AVAudioPlayer(data: wav).duration, 2.4, accuracy: 0.01)

        func cacheKey(_ text: String) throws -> String {
            let body: [String: JSONValue] = [
                "provider": .string(config.provider), "model": .string(config.model),
                "voice": .string(config.voice), "key": .string(config.key),
                "groupId": .string(config.groupID), "input": .string(text)
            ]
            return Integrity.sha256(try Integrity.encoder().encode(body))
        }
        let firstKey = try cacheKey(firstText), nextKey = try cacheKey(nextText)
        let cacheFolder = try XCTUnwrap(FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first)
            .appendingPathComponent("TTSAudio", isDirectory: true)
        let cacheFiles = [firstKey, nextKey].map { cacheFolder.appendingPathComponent($0 + ".json") }
        defer { for url in cacheFiles { try? FileManager.default.removeItem(at: url) } }

        let firstWords: [CloudSpeech.Word] = unmatchedEnding
            ? [.init(text: "开头", start: 0, end: 0.12),
               .init(text: "二零二六", start: 0.12, end: 2.3)]
            : [.init(text: firstText, start: 0, end: 0.12)]
        CloudSpeech.storeCachedResult(.init(audio: wav, words: firstWords), forKey: firstKey)
        CloudSpeech.storeCachedResult(.init(audio: wav, words: [.init(text: nextText, start: 0, end: 2.3)]), forKey: nextKey)
        // Both unique sentences must be on disk before playback; this fixture needs no API call.
        _ = try XCTUnwrap(CloudSpeech.cachedResult(forKey: firstKey))
        _ = try XCTUnwrap(CloudSpeech.cachedResult(forKey: nextKey))

        let player = SpeechPlayer()
        defer { player.stop() }
        let book = Book(id: "tail-\(unique)", title: "句尾回归", format: "TXT",
                        chapters: [Chapter(title: "正文", text: firstText + nextText)])
        player.start(book: book, chapter: 0, position: 0)
        let started = try await miniMaxTailWait(timeout: 3) {
            player.playing && !player.buffering && player.position == 0
        }
        XCTAssertTrue(started, "本地缓存音频未开始播放：\(player.error ?? "无错误信息")")
        guard started else { return }

        // At either 1× or 2×, 0.45 seconds is past the old subtitle cutoff but before the 2.4 s clip ends.
        try await Task.sleep(for: .milliseconds(450))
        XCTAssertEqual(player.position, 0, "字幕提前结束或末词未匹配时，仍须播放完整音频")
        let followed = try XCTUnwrap(player.followOffset)
        XCTAssertGreaterThanOrEqual(followed, firstRange.location)
        XCTAssertLessThan(followed, NSMaxRange(firstRange), "音频未结束前不得提前跟随到下一句")

        let advanced = try await miniMaxTailWait(timeout: 4) { player.position == 1 }
        XCTAssertTrue(advanced, "音频自然结束后应进入已缓存的下一句：\(player.error ?? "无错误信息")")
        XCTAssertEqual(player.position, 1)
    }

    @MainActor private func miniMaxTailWait(timeout: TimeInterval, until predicate: () -> Bool) async throws -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !predicate(), Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        return predicate()
    }

    private func miniMaxTailTestWav(seconds: Double) -> Data {
        let sampleRate: UInt32 = 16_000
        let pcm = Data(repeating: 0, count: Int(Double(sampleRate) * seconds) * 2)
        var wav = Data("RIFF".utf8)
        func put32(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { wav.append(contentsOf: $0) } }
        func put16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { wav.append(contentsOf: $0) } }
        put32(UInt32(36 + pcm.count)); wav.append(Data("WAVEfmt ".utf8))
        put32(16); put16(1); put16(1); put32(sampleRate); put32(sampleRate * 2); put16(2); put16(16)
        wav.append(Data("data".utf8)); put32(UInt32(pcm.count)); wav.append(pcm)
        return wav
    }
}


// MARK: - Figma reader appearance parity

extension NativeCoreTests {
    @MainActor func testReaderHighlightUsesPaperAppearanceInsteadOfAppAppearance() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let traits = UITraitCollection(userInterfaceStyle: style)
            for paper in ReaderPaper.allCases {
                let preferences = ReaderPreferences(paper: paper.rawValue)
                let followsDarkAppearance = paper.dark || (paper == .paper && style == .dark)
                let expected = UIColor(hex: followsDarkAppearance ? 0x8DA7FF : 0x315BEE)
                XCTAssertEqual(preferences.highlightBand.resolvedColor(with: traits), expected,
                               "\(paper.rawValue) 的跟读色必须按纸色明暗解析")
                let highlight = preferences.highlight.resolvedColor(with: traits)
                XCTAssertEqual(highlight.cgColor.alpha, followsDarkAppearance ? 0.26 : 0.14, accuracy: 0.001)
            }
        }
    }

    /// 原书模式与原生模式使用同一字体键、纸色与交互蓝；原出版物的图像比例和显式颜色不被重绘。
    @MainActor func testOriginalReaderAppliesBundledSansFontsAndThemeWithoutChangingPublicationArtwork() async throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 160, height: 90)).image { context in
            UIColor.systemTeal.setFill(); context.fill(CGRect(x: 0, y: 0, width: 160, height: 90))
        }
        let imageData = try XCTUnwrap(image.pngData())
        let source = "<p id='reader-text'>原书中的正文。</p><a id='reader-link' href='#chapter'>目录链接</a><a class='publication-link'>书内特定颜色</a><img id='artwork' src='data:image/png;base64,\(imageData.base64EncodedString())'><table><tr><td>原书表格</td></tr></table>"
        for key in ["hansans", "xixihei"] {
            let loaded = expectation(description: "Original reader \(key) loaded")
            let delegate = LoadDelegate { loaded.fulfill() }
            let config = WKWebViewConfiguration()
            config.defaultWebpagePreferences.allowsContentJavaScript = false
            config.websiteDataStore = .nonPersistent()
            let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 600), configuration: config)
            web.navigationDelegate = delegate
            web.loadHTMLString(OriginalDocument.html(source, css: ".publication-link {color:rgb(80, 65, 50)}", color: "#17233A", background: "transparent", paper: "#F6F0E4", preferences: ReaderPreferences(font: key), accent: "#315BEE"), baseURL: nil)
            await fulfillment(of: [loaded], timeout: 40)
            let font = try await web.evaluateJavaScript("getComputedStyle(document.getElementById('reader-text')).fontFamily", in: nil, contentWorld: .page) as? String ?? ""
            XCTAssertTrue(font.contains(try XCTUnwrap(ReaderPreferences.bundledFonts[key])), key)
            XCTAssertFalse(font.contains("Songti"), "无衬线字体不能在原书模式退回宋体")
            let style = try await web.evaluateJavaScript("JSON.stringify({paper:document.getElementById('ty-reader-book').dataset.tyPaper, color:getComputedStyle(document.body).color, background:getComputedStyle(document.body).backgroundColor, accent:getComputedStyle(document.getElementById('reader-link')).color, publication:getComputedStyle(document.querySelector('.publication-link')).color, ratio:document.getElementById('artwork').getBoundingClientRect().width/document.getElementById('artwork').getBoundingClientRect().height, tables:document.querySelectorAll('table').length})", in: nil, contentWorld: .page) as? String
            let data = try XCTUnwrap(style?.data(using: .utf8))
            let result = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertEqual(result["paper"] as? String, "#F6F0E4")
            XCTAssertEqual(result["color"] as? String, "rgb(23, 35, 58)")
            XCTAssertEqual(result["background"] as? String, "rgba(0, 0, 0, 0)")
            XCTAssertEqual(result["accent"] as? String, "rgb(49, 91, 238)")
            XCTAssertEqual(result["publication"] as? String, "rgb(80, 65, 50)")
            XCTAssertEqual(try XCTUnwrap(result["ratio"] as? Double), 160.0 / 90.0, accuracy: 0.01)
            XCTAssertEqual(result["tables"] as? Int, 1)
            withExtendedLifetime(delegate) {}
        }
    }
}

/// Publication import/display regression cases, also runnable with the unsigned configuration.
final class BookLoadingTests: XCTestCase {
    private func fixture(_ name: String) throws -> Book {
        let base = try XCTUnwrap(Bundle(for: Self.self).resourceURL?.appendingPathComponent("Fixtures"))
        return try BookImporter.read(base.appendingPathComponent(name)).book
    }
    func testEPUB3NavigationPreservesLabelsDepthAndSpineOrder() throws {
        let book = try fixture("loading-nav.epub")
        XCTAssertEqual(book.chapters.map(\.title), ["第二章", "第一卷 春风 续"])
        XCTAssertEqual(book.chapters.map { $0.fields["tocDepth"]?.int }, [1, 0])
        XCTAssertTrue(book.chapters[0].text.contains("第二章的正文"))
        XCTAssertTrue(book.chapters[1].text.contains("第一段粗体尾声"))
    }
    func testEPUB2NCXFallbackUsesPublicationLabels() throws {
        let book = try fixture("loading-ncx.epub")
        XCTAssertEqual(book.chapters.map(\.title), ["旧目录第二章", "旧目录第一卷"])
        XCTAssertEqual(book.chapters[0].fields["tocDepth"]?.int, 1)
    }
    func testEPUBResourcesAndInlineStylesSurviveImportAndBackup() throws {
        let book = try fixture("loading-nav.epub")
        let chapter = book.chapters[1]
        let refs = try XCTUnwrap(chapter.fields["nativeImages"]?.array?.compactMap(\.string))
        XCTAssertEqual(refs.count, 3, "Includes ordinary images and SVG image hrefs")
        XCTAssertNotNil(book.resourceData(refs[0]))
        let vector = try XCTUnwrap(book.resourceData(refs[1]))
        XCTAssertTrue(String(decoding: vector, as: UTF8.self).contains("<svg"))
        let document = try XCTUnwrap(chapter.fields["document"]?.object)
        let css = try XCTUnwrap(document["css"]?.string)
        XCTAssertTrue(css.contains("@font-face"))
        XCTAssertTrue(css.contains(".inline"))
        XCTAssertTrue(css.contains("tingye-resource:"))
        XCTAssertFalse(css.contains("../Images/"))
        XCTAssertFalse(css.contains("../Fonts/"))
        XCTAssertTrue(document["html"]?.string?.contains("正文示例 url(../Images/cover%20one.png)") == true)
        XCTAssertNotNil(book.coverData)
        let decoded = try JSONDecoder().decode(Book.self, from: Integrity.encoder().encode(book))
        XCTAssertEqual(decoded, book)
    }
    func testSVGReferencesAndStyleURLsDoNotRewriteProseOrOtherAttributes() {
        let source = #"<p>url(a.png)</p><img data-src="wrong.png" src="a.png"><svg><image xlink:href="a.png"/></svg>"#
        XCTAssertEqual(HTMLText.imageSources(source), ["a.png", "a.png"])
        let rewritten = HTMLText.replacingImageSources(in: source) { $0 == "a.png" ? "tingye-resource:r0" : nil }
        XCTAssertTrue(rewritten.contains("data-src=\"wrong.png\""))
        XCTAssertTrue(rewritten.contains("<p>url(a.png)</p>"))
        let styled = #"<p style="background:url('a.png')">url(a.png)</p>"#
        let result = HTMLText.replacingStyleURLs(in: styled) { _ in "tingye-resource:r0" }
        XCTAssertTrue(result.contains("background:url('tingye-resource:r0')"))
        XCTAssertTrue(result.contains(">url(a.png)</p>"))
    }
    func testEncodedPathsRemainLocalAndFragmentResolvesCurrentDocument() throws {
        XCTAssertEqual(try BookImporter.resolve(base: "OPS/Text/a.xhtml", href: "#section"), "OPS/Text/a.xhtml")
        XCTAssertEqual(try BookImporter.resolve(base: "OPS/Text/a.xhtml", href: "../Images/a%20b.png"), "OPS/Images/a b.png")
        for href in ["%2Fprivate/image.png", "%5Cimage.png", "https%3A//example.com/a", "../../../outside"] {
            XCTAssertThrowsError(try BookImporter.resolve(base: "OPS/Text/a.xhtml", href: href))
        }
    }
    func testHTMLMarksUseUTF16OffsetsWithEmoji() throws {
        let chapter = HTMLText.chapter("<p>前😀<strong>粗体</strong>后。</p>", title: "测试")
        let mark = try XCTUnwrap(chapter.fields["marks"]?.array?.first?.object)
        let start = try XCTUnwrap(mark["start"]?.int), end = try XCTUnwrap(mark["end"]?.int)
        XCTAssertEqual((chapter.text as NSString).substring(with: NSRange(location: start, length: end - start)), "粗体")
        XCTAssertEqual(start, 3)
    }
    func testLongTXTDoesNotSplitComposedCharactersOrLoseParagraphs() {
        let unit = "家👩‍👩‍👧‍👦e\u{301}"
        let text = String(repeating: unit, count: 900)
        let split = BookImporter.limitLength([Chapter(title: "长章", text: text)], maxLength: 1000)
        XCTAssertEqual(split.map(\.text).joined(), text)
        XCTAssertTrue(split.allSatisfy { $0.text.count <= 1000 })
        let paragraphs = (0..<1200).map { "第\($0)段，正文。" }
        let chapters = BookImporter.limitLength([Chapter(title: "多段", text: paragraphs.joined(separator: "\n"))], maxLength: 1000)
        XCTAssertEqual(chapters.flatMap { $0.text.components(separatedBy: "\n") }, paragraphs)
        XCTAssertTrue(chapters.allSatisfy { $0.text.count <= 1000 })
    }
    @MainActor func testImagePreviewIsDownsampledAndInvalidImageIsRejected() throws {
        let source = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 800)).image { context in
            UIColor.green.setFill(); context.fill(CGRect(x: 0, y: 0, width: 1200, height: 800))
        }
        let data = try XCTUnwrap(source.pngData())
        let thumb = try XCTUnwrap(BookImage.thumbnail(data, maxPixelSize: 120))
        XCTAssertLessThanOrEqual(max(thumb.size.width, thumb.size.height), 120)
        XCTAssertNil(BookImage.thumbnail(Data("not an image".utf8), maxPixelSize: 120))
        XCTAssertNil(BookImage.thumbnail(data, maxPixelSize: 0))
    }
}

@MainActor
final class LocalFileImportTests: XCTestCase {
    func testOrdinaryPickerUsesCopyModeAndSingleSelection() {
        let delegate = LocalBookPicker.Coordinator { _ in }
        let picker = LocalBookPicker.controller(allowsMultipleSelection: false, delegate: delegate)
        XCTAssertFalse(picker.allowsMultipleSelection)
        XCTAssertEqual(picker.documentPickerMode, .import)
        XCTAssertTrue(LocalBookPicker.controller(allowsMultipleSelection: true, delegate: delegate).allowsMultipleSelection)
    }
    func testPickerDeliversSelectedFileExactlyOnceAndCancellationIsEmpty() {
        let url = URL(fileURLWithPath: "/tmp/local.txt")
        var selections: [[URL]] = []
        let delegate = LocalBookPicker.Coordinator { selections.append($0) }
        let picker = LocalBookPicker.controller(allowsMultipleSelection: false, delegate: delegate)
        delegate.documentPicker(picker, didPickDocumentsAt: [url])
        delegate.documentPickerWasCancelled(picker)
        XCTAssertEqual(selections, [[url]])
        var canceled: [URL]?
        let cancelDelegate = LocalBookPicker.Coordinator { canceled = $0 }
        cancelDelegate.documentPickerWasCancelled(picker)
        XCTAssertEqual(canceled, [])
    }
    func testSelectedFileIsPersistedAndCanBeReadAfterSourceIsRemoved() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let disk = try LibraryDisk(owner: "local-import", base: folder)
        let model = AppModel(disk: disk, progressSync: ProgressSync(account: { false }))
        let source = folder.appendingPathComponent("本地书籍.TXT")
        try Data("第一章 开始\n本地文件正文。".utf8).write(to: source)
        try await model.importWithFeedback([source])
        let entry = try XCTUnwrap(model.entries.first)
        XCTAssertEqual(model.importReport?.successes, 1)
        XCTAssertEqual(model.importReport?.failures, 0)
        try FileManager.default.removeItem(at: source)
        XCTAssertTrue(try disk.read(entry.id).chapters[0].text.contains("本地文件正文"))
        XCTAssertEqual(try disk.catalog().first?.id, entry.id)
        model.clearIndexCache()
    }
    func testMissingProviderFileIsReportedInsteadOfSilentlyIgnoringSelection() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let disk = try LibraryDisk(owner: "missing-file", base: folder)
        let model = AppModel(disk: disk, progressSync: ProgressSync(account: { false }))
        try await model.importWithFeedback([folder.appendingPathComponent("missing.epub")])
        XCTAssertEqual(model.importReport?.failures, 1)
        XCTAssertTrue(model.entries.isEmpty)
        XCTAssertTrue(model.notice?.importResults == true)
    }
}

final class ReaderVoiceTests: XCTestCase {
    func testGLMChinaRequestUsesItsOwnEndpointAndAudioParameters() throws {
        let request = try CloudSpeech.glmURLRequest("你好，中国。", model: "glm-tts", voice: "tongtong", key: " cn-test-key \n")
        XCTAssertEqual(request.url?.absoluteString, "https://open.bigmodel.cn/api/paas/v4/audio/speech")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer cn-test-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let body = try JSONDecoder().decode([String: JSONValue].self, from: XCTUnwrap(request.httpBody))
        XCTAssertEqual(body["model"]?.string, "glm-tts")
        XCTAssertEqual(body["voice"]?.string, "tongtong")
        XCTAssertEqual(body["input"]?.string, "你好，中国。")
        XCTAssertEqual(body["response_format"]?.string, "wav")
    }
    func testMiniMaxChinaRequestAndTokenPlanGroupHandling() throws {
        let body = try CloudSpeech.minimaxSpeechBody("中文阅读。", model: "speech-2.8-hd", voice: "male-qn-qingse")
        let request = try CloudSpeech.minimaxURLRequest(body: body, key: "china-test-key", groupID: "group 123")
        XCTAssertEqual(request.url?.host, "api.minimax.cn")
        XCTAssertEqual(request.url?.path, "/v1/t2a_v2")
        XCTAssertEqual(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.queryItems?.first?.value, "group 123")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer china-test-key")
        XCTAssertEqual(body["model"]?.string, "speech-2.8-hd")
        XCTAssertEqual(body["text"]?.string, "中文阅读。")
        XCTAssertEqual(body["voice_setting"]?.object?["voice_id"]?.string, "male-qn-qingse")
        XCTAssertEqual(body["audio_setting"]?.object?["format"]?.string, "mp3")
        XCTAssertEqual(body["stream"]?.bool, false)
        let tokenPlan = try CloudSpeech.minimaxURLRequest(body: body, key: "sk-cp-test", groupID: "ignored-group")
        XCTAssertNil(URLComponents(url: try XCTUnwrap(tokenPlan.url), resolvingAgainstBaseURL: false)?.queryItems)
    }
    func testVoiceProvidersCannotSendEachOthersModelAndVoice() throws {
        let glm = try CloudSpeech.glmURLRequest("文字", model: "speech-2.8-hd", voice: "male-qn-qingse", key: "fake")
        let body = try JSONDecoder().decode([String: JSONValue].self, from: XCTUnwrap(glm.httpBody))
        XCTAssertEqual(body["model"]?.string, "glm-tts")
        XCTAssertEqual(body["voice"]?.string, "tongtong")
        let minimax = try CloudSpeech.minimaxSpeechBody("文字", model: "glm-tts", voice: "tongtong")
        XCTAssertEqual(minimax["model"]?.string, "speech-2.8-hd")
        XCTAssertEqual(minimax["voice_setting"]?.object?["voice_id"]?.string, "male-qn-qingse")
        XCTAssertNotEqual(VoiceOptions.secretKey("glm"), VoiceOptions.secretKey("minimax"))
    }
    func testChinaRequestsRejectMissingCredentialsAndEmptySpeech() throws {
        XCTAssertThrowsError(try CloudSpeech.glmURLRequest("文字", model: "glm-tts", voice: "tongtong", key: " "))
        XCTAssertThrowsError(try CloudSpeech.glmURLRequest(" \n", model: "glm-tts", voice: "tongtong", key: "fake"))
        XCTAssertThrowsError(try CloudSpeech.minimaxSpeechBody(" \n", model: "speech-2.8-hd", voice: "male-qn-qingse"))
        XCTAssertThrowsError(try CloudSpeech.minimaxURLRequest(body: [:], key: " ", groupID: ""))
        XCTAssertNil(CloudSpeech.decodeHex("ABC"))
    }
    @MainActor func testLegacyMarksRenderAsBackgroundWithoutRewritingSavedNotes() throws {
        let mark = ReaderMark(range: NSRange(location: 0, length: 2), color: "blue", kind: "wavy")
        XCTAssertEqual(mark.style.kind, "background")
        XCTAssertEqual(mark.kind, "wavy", "Saved content is preserved; only rendering is normalized")
        for kind in ["background", "underline", "wavy"] {
            XCTAssertEqual(ReaderMark.displayKind(kind), "background")
        }
        let source = NSAttributedString(string: "正文高亮", attributes: [.font: UIFont.systemFont(ofSize: 19)])
        let result = SpeechHighlight.apply(to: source, sentence: NSRange(location: 0, length: 2))
        XCTAssertNotNil(result.attribute(.backgroundColor, at: 0, effectiveRange: nil))
        XCTAssertNil(result.attribute(.underlineStyle, at: 0, effectiveRange: nil))
        XCTAssertNil(source.attribute(.backgroundColor, at: 0, effectiveRange: nil))
    }
}

@MainActor
final class ReaderOnlyListeningTests: XCTestCase {
    private func withModel(_ action: (AppModel, Book) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let disk = try LibraryDisk(owner: "reader-only", base: root)
        let model = AppModel(disk: disk, progressSync: ProgressSync(account: { false }))
        let book = Book(id: "reader-audio", title: "正文听书", format: "TXT", chapters: [
            Chapter(title: "第一章", text: "第一句。第二句。第三句。"), Chapter(title: "第二章", text: "另一章第一句。另一章第二句。")
        ])
        try await model.add(book)
        defer { model.player.stop() }
        try await action(model, book)
    }
    func testStartListeningOpensMatchingReaderAtAudioPosition() async throws {
        try await withModel { model, book in
            model.startListening(book, from: .init(chapter: 1, position: 1))
            model.player.pause()
            XCTAssertEqual(model.selectedBook?.id, book.id)
            XCTAssertEqual(model.listeningReaderID, book.id)
            XCTAssertEqual(model.readerJump?.chapter, 1)
            XCTAssertEqual(model.readerJump?.position, 1)
        }
    }
    func testInlineStartDoesNotPresentAnotherPageAndRevealPreservesPause() async throws {
        try await withModel { model, book in
            model.startListening(book, openReader: false, from: .init(chapter: 0, position: 1))
            model.player.pause()
            XCTAssertNil(model.selectedBook)
            XCTAssertNil(model.listeningReaderID)
            model.showListeningReader()
            XCTAssertEqual(model.selectedBook?.id, book.id)
            XCTAssertFalse(model.player.playing)
            XCTAssertEqual(model.player.position, 1)
            XCTAssertEqual(model.readerJump?.position, 1)
        }
    }
    func testChapterListeningTargetsReaderAndOrdinaryOpenClearsFollowRequest() async throws {
        try await withModel { model, book in
            model.startListening(book, openReader: false)
            model.player.pause()
            model.listen(book.id, chapter: 1, position: 1)
            model.player.pause()
            XCTAssertEqual(model.selectedBook?.id, book.id)
            XCTAssertEqual(model.readerJump?.chapter, 1)
            XCTAssertEqual(model.listeningReaderID, book.id)
            let reading = try XCTUnwrap(model.entries.first).progress
            model.open(try XCTUnwrap(model.entries.first))
            XCTAssertNil(model.listeningReaderID)
            XCTAssertNil(model.readerJump)
            XCTAssertEqual(model.entries.first?.progress, reading)
            model.showListeningReader()
            XCTAssertEqual(model.listeningReaderID, book.id)
            model.open(try XCTUnwrap(model.entries.first), chapter: 0, position: 2)
            XCTAssertNil(model.listeningReaderID, "定位打开章节或摘句时必须清除遗留的听书跟随请求")
            XCTAssertEqual(model.readerJump?.chapter, 0)
            XCTAssertEqual(model.readerJump?.position, 2)
        }
    }
    func testRevealWithNoAudioDoesNotOpenAnyPage() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = AppModel(disk: try LibraryDisk(owner: "no-audio", base: root), progressSync: ProgressSync(account: { false }))
        model.showListeningReader()
        XCTAssertNil(model.selectedBook)
        XCTAssertNil(model.listeningReaderID)
    }
}
