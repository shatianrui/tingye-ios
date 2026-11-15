import XCTest
import ReadiumNavigator
import ReadiumShared
@testable import Tingye

final class ReadiumPreferencesTests: XCTestCase {
    private func mapped(_ prefs: ReaderPreferences = .init(), dark: Bool = false,
                        alwaysLight: Bool = false, doublePage: Bool = true,
                        width: Double = 390, fixed: Bool = false,
                        fontLineHeight: Double = 23) -> EPUBPreferences {
        ReadiumPreferencesBridge.preferences(
            prefs, darkAppearance: dark, alwaysLight: alwaysLight,
            doublePage: doublePage, viewportWidth: width, fixedLayout: fixed,
            fontFamily: "-apple-system", fontLineHeight: fontLineHeight)
    }

    func testEveryPaperResolvesExactDayNightAndAlwaysLightColors() {
        // PLAN 4.2 的独立期望表；不从生产 resolve 反推期望值。
        let cases: [(ReaderPaper, [UInt32], [UInt32])] = [
            (.paper, [0xFAF9F5, 0x1C1B18, 0x6E6A5A], [0x141413, 0xEFEDE6, 0x99968A]),
            (.mist, [0xE6EBF1, 0x14181F, 0x666666], [0x1D2733, 0xD8E2EC, 0x93A3B5]),
            (.ancient, [0xF3E7D6, 0x2C2418, 0x6E5F4B], [0x2A2118, 0xEAD9BE, 0xB39B78]),
            (.eink, [0xF0F0F0, 0x242424, 0x666666], [0x1E1E1E, 0xE8E8E8, 0xA8A8A8]),
            (.white, [0xFFFFFF, 0x14181F, 0x666666], [0x000000, 0xEFEFEA, 0xA9A9A2]),
            (.blue, [0x1A2C3A, 0xD5E4F0, 0x8AA0B4], [0x1A2C3A, 0xD5E4F0, 0x8AA0B4]),
            (.night, [0x101012, 0xEFEDE6, 0xA5A296], [0x101012, 0xEFEDE6, 0xA5A296])
        ]
        for (paper, day, night) in cases {
            for dark in [false, true] {
                for alwaysLight in [false, true] {
                    let expected = dark && !alwaysLight ? night : day
                    let palette = paper.resolve(darkAppearance: dark, alwaysLight: alwaysLight)
                    XCTAssertEqual([palette.background, palette.foreground, palette.secondary], expected, paper.rawValue)
                    let isDark = paper == .blue || paper == .night || (dark && !alwaysLight)
                    XCTAssertEqual(palette.isDark, isDark, paper.rawValue)
                    let bridge = mapped(.init(paper: paper.rawValue), dark: dark, alwaysLight: alwaysLight)
                    XCTAssertEqual(bridge.backgroundColor?.rawValue, Int(expected[0]))
                    XCTAssertEqual(bridge.textColor?.rawValue, Int(expected[1]))
                    XCTAssertEqual(bridge.theme, isDark ? .dark : .light)
                }
            }
        }
        XCTAssertEqual(ReaderPreferences(paper: "unknown").kind, .paper)
    }

    func testFontSizeAndNativeLineBoxBecomeReadiumRatios() throws {
        XCTAssertEqual(ReadiumPreferencesBridge.fontScale(16), 1, accuracy: 0.000001)
        XCTAssertEqual(try XCTUnwrap(mapped().fontSize), 1.1875, accuracy: 0.000001)
        XCTAssertEqual(try XCTUnwrap(mapped().lineHeight), 34.0 / 19.0, accuracy: 0.000001)
        let larger = mapped(.init(fontSize: 34, lineSpacing: 28), fontLineHeight: 41)
        XCTAssertEqual(try XCTUnwrap(larger.fontSize), 2.125, accuracy: 0.000001)
        XCTAssertEqual(try XCTUnwrap(larger.lineHeight), 69.0 / 34.0, accuracy: 0.000001)
        XCTAssertEqual(ReadiumPreferencesBridge.lineHeight(fontSize: 19, lineSpacing: 0, fontLineHeight: 10), 1)
    }

    func testParagraphMarginIndentAlignmentAndLetterSpacingUnits() throws {
        let prefs = ReaderPreferences(fontSize: 20, paragraphSpacing: 30, margin: 48,
                                      indent: false, justified: false, letterSpacing: 2)
        let result = mapped(prefs)
        XCTAssertEqual(result.pageMargins, 2)
        XCTAssertEqual(result.paragraphSpacing, 1.5)
        XCTAssertEqual(result.paragraphIndent, 0)
        XCTAssertEqual(result.textAlign, .start)
        XCTAssertEqual(try XCTUnwrap(result.letterSpacing), 0.2, accuracy: 0.000001)
        XCTAssertEqual(result.publisherStyles, false)
        XCTAssertEqual(result.fontFamily?.rawValue, "-apple-system")
        XCTAssertEqual(mapped().paragraphIndent, 2)
        XCTAssertEqual(mapped().textAlign, .justify)
        // Toolkit 3.11.1 不支持负 letterSpacing；不改 AppStorage 中的原负值。
        XCTAssertEqual(mapped(.init(letterSpacing: -1)).letterSpacing, 0)
    }

    func testScrollingAndTwoColumnsRespectWidthModePaperAndSwitch() {
        XCTAssertEqual(mapped(width: 650).columnCount, .one)
        XCTAssertEqual(mapped(width: 651).columnCount, .two)
        XCTAssertEqual(mapped(doublePage: false, width: 1024).columnCount, .one)
        XCTAssertEqual(mapped(.init(paper: "eink"), width: 1024).columnCount, .one)
        let scrolling = mapped(.init(scrolling: true), width: 1024)
        XCTAssertEqual(scrolling.scroll, true)
        XCTAssertEqual(scrolling.columnCount, .one)
        XCTAssertEqual(mapped(width: 1024).scroll, false)
    }

    func testFixedLayoutOnlyReceivesCanvasAndSpread() {
        let result = mapped(width: 1024, fixed: true)
        XCTAssertEqual(result.spread, .always)
        XCTAssertNotNil(result.backgroundColor)
        XCTAssertNil(result.fontSize)
        XCTAssertNil(result.fontFamily)
        XCTAssertNil(result.lineHeight)
        XCTAssertNil(result.pageMargins)
        XCTAssertNil(result.paragraphIndent)
        XCTAssertNil(result.paragraphSpacing)
        XCTAssertNil(result.letterSpacing)
        XCTAssertNil(result.publisherStyles)
        XCTAssertNil(result.scroll)
        XCTAssertNil(result.columnCount)
        XCTAssertNil(result.textColor)
        XCTAssertNil(result.theme)
        XCTAssertEqual(mapped(width: 390, fixed: true).spread, .never)
        XCTAssertEqual(mapped(.init(scrolling: true), width: 1024, fixed: true).spread, .never)
    }

    func testRouterUsesComicThenDecodablePDFThenEPUBThenNative() {
        var book = Book(title: "路由", author: "测试", format: "ePuB", chapters: [.init(title: "正文", text: "测试。")])
        XCTAssertEqual(ReaderRouter.destination(for: book), .epub)
        book.fields["pdf"] = .string("a")
        XCTAssertEqual(ReaderRouter.destination(for: book), .epub)
        book.fields["pdf"] = .number(1)
        XCTAssertEqual(ReaderRouter.destination(for: book), .epub)
        book.fields["pdf"] = .string(Data("%PDF".utf8).base64EncodedString())
        XCTAssertEqual(ReaderRouter.destination(for: book), .native)
        book.fields["comic"] = .bool(true)
        XCTAssertEqual(ReaderRouter.destination(for: book), .comic)
        book.fields["pdf"] = nil
        XCTAssertEqual(ReaderRouter.destination(for: book), .comic)
        book.fields["format"] = .string("TXT")
        XCTAssertEqual(ReaderRouter.destination(for: book), .comic)
    }

    func testRouterDoesNotGuessFromDocumentsResourcesOrComicFormat() {
        var book = Book(title: "原生", author: "测试", format: "TXT", chapters: [
            .init(title: "正文", text: "测试。", extras: ["document": .object(["html": .string("<p>测试</p>")])])
        ], extras: ["resources": .object(["r0": .string("image")])])
        for format in ["TXT", "MOBI", "PDF", "Markdown", "HTML", "DOCX", "CBZ", ""] {
            book.fields["format"] = .string(format)
            XCTAssertEqual(ReaderRouter.destination(for: book), .native, format)
        }
        book.fields["format"] = nil
        XCTAssertEqual(ReaderRouter.destination(for: book), .native)
    }

    func testOriginalMapPrefersNormalizedPathAndOnlyUsesUniqueTitleFallback() {
        let book = Book(title: "映射", author: "测试", format: "EPUB", chapters: [
            .init(title: "同名", text: "一。", extras: ["document": .object(["path": .string("OPS/目录/./c1.xhtml")])]),
            .init(title: "唯一", text: "二。"),
            .init(title: "同名", text: "三。"),
            .init(title: "缺失", text: "四。")
        ])
        let hrefs = ["OPS/extra.xhtml", "OPS/%E7%9B%AE%E5%BD%95/c1.xhtml", "OPS/c2.xhtml", "OPS/c3.xhtml"]
        let map = PublicationMap(book: book, readingOrder: hrefs,
                                 titles: [hrefs[0]: "同名", hrefs[1]: "同名", hrefs[2]: "唯一", hrefs[3]: "同名"], revision: "test")
        XCTAssertEqual(map.href(for: 0), hrefs[1])
        XCTAssertEqual(map.href(for: 1), hrefs[2])
        XCTAssertNil(map.href(for: 2))
        XCTAssertNil(map.href(for: 3))
        XCTAssertEqual(map.chapter(for: "OPS/目录/c1.xhtml#fragment"), 0)
        XCTAssertNil(PublicationMap.normalized("../outside.xhtml"))
    }

    func testApproximateProgressUsesSentenceRatioAndClampsBoundaries() {
        XCTAssertEqual(EPUBApproximateProgress.progression(position: 25, sentenceCount: 100), 0.25)
        XCTAssertEqual(EPUBApproximateProgress.position(progression: 0.25, sentenceCount: 100), 25)
        XCTAssertEqual(EPUBApproximateProgress.position(progression: 1, sentenceCount: 100), 99)
        XCTAssertEqual(EPUBApproximateProgress.position(progression: -1, sentenceCount: 100), 0)
        XCTAssertEqual(EPUBApproximateProgress.position(progression: .nan, sentenceCount: 100), 0)
        XCTAssertEqual(EPUBApproximateProgress.position(progression: .infinity, sentenceCount: 0), 0)
        XCTAssertEqual(EPUBApproximateProgress.progression(position: 10, sentenceCount: 0), 0)
    }

    func testMissingFontFileFallsBackWithoutChangingTheFontKey() {
        let missing = CustomFont(file: UUID().uuidString + ".ttf", postScript: "MissingFace", name: "缺失字体")
        let files = ReadiumFontProvider.files(custom: [missing])
        XCTAssertFalse(files.contains { $0.key == "custom:MissingFace" })
        XCTAssertEqual(ReadiumFontProvider.family(for: "custom:MissingFace", files: files), ReadiumFontProvider.system)
        XCTAssertEqual(ReadiumFontProvider.family(for: "kai", files: []), ReadiumFontProvider.system)
        XCTAssertEqual(ReadiumFontProvider.family(for: "system", files: files), ReadiumFontProvider.system)
    }

    func testCollectionFontFaceFragmentSurvivesWebViewServingURLRewrite() throws {
        let file = ReadiumFontProvider.FontFile(key: "custom:FaceOne", url: URL(fileURLWithPath: "/tmp/test.ttc"), postScript: "FaceOne")
        let declaration = try XCTUnwrap(ReadiumFontProvider.declarations(files: [file]).first)
        let served = try XCTUnwrap(AnyURL(string: "readium://assets/fonts/test.ttc")?.absoluteURL)
        let html = try declaration.inject(in: "<html><head></head><body>字体</body></html>") { _ in served }
        XCTAssertTrue(html.contains("test.ttc#FaceOne"))
        XCTAssertTrue(html.contains("FaceOne"))
        XCTAssertFalse(html.contains("file:///tmp"))
    }

    @MainActor func testCancelledSessionCanRetryAndRepeatedOpenReusesPublicationAndPin() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("readium-session-" + UUID().uuidString)
        let disk = try LibraryDisk(owner: "session", base: base)
        let store = PublicationStore(disk: disk, cacheBase: base.appendingPathComponent("cache"))
        let session = ReadiumReaderSession()
        defer { session.close(); try? FileManager.default.removeItem(at: base) }
        let book = Book(title: "会话", format: "EPUB", chapters: [.init(title: "正文", text: "一。二。三。")])
        let cancelled = Task { @MainActor in
            await session.open(book: book, store: store, progress: .init(), counts: [3])
        }
        cancelled.cancel()
        await cancelled.value
        XCTAssertNil(session.publication)
        XCTAssertNotNil(session.error)
        XCTAssertFalse(session.loading)
        await session.open(book: book, store: store, progress: .init(chapter: 0, position: 1), counts: [3])
        let first = try XCTUnwrap(session.publication)
        XCTAssertNil(session.error)
        await session.open(book: book, store: store, progress: .init(), counts: [3])
        XCTAssertTrue(session.publication === first)
        let root = await store.cacheRoot
        let pins = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent(".Sessions"), includingPropertiesForKeys: nil)
        XCTAssertEqual(pins.count, 1)
        session.close()
        XCTAssertNil(session.publication)
        XCTAssertNil(session.map)
    }
}
