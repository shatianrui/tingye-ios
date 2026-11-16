import XCTest
import ReadiumShared
import ReadiumNavigator
@testable import Tingye

@MainActor
enum LocatorTestSupport {
    static func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle(for: ReadiumLocatorTests.self).url(forResource: name, withExtension: nil, subdirectory: "Fixtures/readium"))
        return try Data(contentsOf: url)
    }
    static func temporary(_ test: XCTestCase) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("locator-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        test.addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }
    static func book(_ texts: [String] = ["前句。重复。中间。重复。后句。"], format: String = "EPUB") -> Book {
        Book(id: "locator-book", title: "定位测试", format: format, chapters: texts.enumerated().map { index, text in
            Chapter(title: "第\(index)章", text: text, extras: ["document": .object([
                "path": .string("old/\(index).xhtml"), "html": .string("<body><p>\(text)</p></body>"), "css": .string("")])])
        })
    }
    static func bridge(_ book: Book, _ test: XCTestCase) async throws -> LocatorBridge {
        let root = try temporary(test)
        let built = try await LegacyEPUBBuilder().build(book, to: root.appendingPathComponent("artifact"))
        let publication = try await ReadiumService().open(built.url)
        return try LocatorBridge(book: book, map: built.map, publication: publication)
    }
}

@MainActor
final class ReadiumLocatorTests: XCTestCase {
    func test141And142FourKindsRoundTripWithoutChangingOldFields() async throws {
        let book = try JSONDecoder().decode(Book.self, from: LocatorTestSupport.fixture("locator-book.json"))
        let bridge = try await LocatorTestSupport.bridge(book, self)
        for version in [141, 142] {
            let entry = try XCTUnwrap(JSONDecoder().decode([ShelfEntry].self, from: LocatorTestSupport.fixture("catalog-\(version).json")).first)
            let targets = [LocatorTarget(entry.progress), LocatorTarget(try XCTUnwrap(entry.listeningProgress)),
                           LocatorTarget(entry.bookmarks[0]), LocatorTarget(entry.notes[0])]
            for target in targets {
                let resolved = try await bridge.resolve(target)
                XCTAssertTrue(resolved.precise)
                let locator = try XCTUnwrap(StoredLocator.readium(resolved.locator))
                XCTAssertNil(locator.locations.position, "Readium position is never a sentence index")
                let restored = try await bridge.reverse(locator, chapterHint: target.chapter)
                XCTAssertEqual(restored.target.chapter, target.chapter)
                XCTAssertEqual(restored.target.position, target.position)
                if let end = target.end { XCTAssertEqual(restored.target.end, end) }
                XCTAssertEqual(StoredLocator.json(locator), resolved.locator)
            }
        }
    }
    func testRepeatedQuoteUsesFullContextAndRejectsAmbiguity() throws {
        let text = "甲。重复。乙。重复。丙。"
        XCTAssertNil(TextDOMIndex.matches("重复。", in: text))
        let match = try XCTUnwrap(TextDOMIndex.matches("重复。", in: text, before: "乙。", after: "丙。"))
        XCTAssertEqual(match.location, 7)
        XCTAssertEqual(TextDOMIndex.matches("重复。", in: text, preferred: 2)?.location, 2)
    }
    func testFullMultisentenceHighlightBeyondAnchorLimit() async throws {
        let first = String(repeating: "山", count: 160) + "。", second = String(repeating: "水", count: 140) + "。"
        let book = LocatorTestSupport.book([first + second + "终句。"])
        let sentences = Sentence.split(book.chapters[0].text)
        let note = Highlight(chapter: 0, start: 0, end: 1, text: first + second, anchor: Locator.anchor(in: sentences, at: 0), note: "全文")
        let bridge = try await LocatorTestSupport.bridge(book, self)
        let resolved = try await bridge.resolve(.init(note))
        let locator = try XCTUnwrap(StoredLocator.readium(resolved.locator))
        XCTAssertEqual(locator.text.highlight, first + second)
        let restored = try await bridge.reverse(locator)
        XCTAssertEqual(restored.target.end, 1)
        XCTAssertEqual(restored.target.text, first + second)
    }
    func testUTF16EntitiesWhitespaceTableRubyAndFootnoteAlignment() throws {
        let native = "标题\n甲 & 乙😀。\n汉han注脚。"
        let html = "<html><head><title>不入正文</title></head><body><h1>标题</h1><table><tr><td>甲 &amp;  乙&#x1F600;。</td></tr></table><ruby>汉<rt>han</rt></ruby><aside>注脚。</aside></body></html>"
        let index = try TextDOMIndex(native: native, xhtml: html)
        let range = (native as NSString).range(of: "甲 & 乙😀。")
        let dom = try XCTUnwrap(index.domRange(for: range))
        let span = try XCTUnwrap(index.span(dom))
        XCTAssertTrue(span.start.cssSelector.contains("td"))
        XCTAssertFalse(span.start.cssSelector.contains("tbody"), "XHTML XML DOM must not receive an implicit HTML tbody")
        XCTAssertEqual(index.range(from: span.json), dom)
        XCTAssertEqual(index.nativeRange(quote: index.textContext(dom).quote, before: nil, after: nil), range)
        XCTAssertEqual(range.length, 8)
    }
    func testDisplayTransformOffIsByteIdenticalAndLengthChangingMapIsReversible() throws {
        let bytes = Data("<body><p title='汉'>简体汉语😀。</p><script>汉</script></body>".utf8)
        XCTAssertEqual(try EPUBTextTransform.transform(xhtml: bytes, mode: "none"), bytes)
        let transformed = try EPUBTextTransform.transform(xhtml: bytes, mode: "s2t")
        let string = try XCTUnwrap(String(data: transformed, encoding: .utf8))
        XCTAssertTrue(string.contains("簡體漢語😀。")); XCTAssertTrue(string.contains("title=\"汉\""))
        XCTAssertTrue(string.contains("<script>汉</script>"))
        XCTAssertEqual(EPUBTextTransform.mapping("头发和干杯", mode: "s2t").text,
                       "头发和干杯".applyingTransform(StringTransform("Hans-Hant"), reverse: false))
        let mapping = TextOffsetMap("Aß😀", transform: { $0 == "ß" ? "SS" : $0 })
        XCTAssertEqual(mapping.text, "ASS😀")
        XCTAssertEqual(mapping.sourceRange(NSRange(location: 1, length: 2)), NSRange(location: 1, length: 1))
        XCTAssertEqual(mapping.outputRange(NSRange(location: 2, length: 2)), NSRange(location: 3, length: 2))
    }
    func testDisplayLocatorAndSelectionAlwaysPersistOriginalText() async throws {
        let book = LocatorTestSupport.book(["简体汉语😀。后面一句。"])
        let bridge = try await LocatorTestSupport.bridge(book, self)
        let resolved = try await bridge.resolve(.init(chapter: 0, position: 0))
        let displayed = try await bridge.displayLocator(resolved.locator, mode: "s2t")
        let shown = try XCTUnwrap(displayed)
        XCTAssertEqual(shown.text.highlight, "簡體漢語😀。")
        let original = try await bridge.reverse(shown, chapterHint: 0, displayMode: "s2t")
        XCTAssertEqual(original.target.text, "简体汉语😀。")
        XCTAssertEqual(original.target.position, 0)
        XCTAssertEqual(book.chapters[0].text, "简体汉语😀。后面一句。")
    }
    func testSpineAddDeleteReorderRelocatesByAnchorAndPaths() async throws {
        let old = LocatorTestSupport.book(["旧第一。", "目标句。后句。"])
        let first = try await LocatorTestSupport.bridge(old, self)
        let reference = try await first.resolve(.init(chapter: 1, position: 0, anchor: .init(quote: "目标句。", after: "后句。")))
        let changed = LocatorTestSupport.book(["新增章。", "旧第一。", "目标句。后句。"])
        let second = try await LocatorTestSupport.bridge(changed, self)
        var target = reference.target; target.locator = reference.locator; target.publicationRevision = first.revision
        let relocated = try await second.resolve(target)
        XCTAssertEqual(relocated.status, .textRelocated); XCTAssertEqual(relocated.target.chapter, 2)
        XCTAssertNotEqual(first.revision, second.revision)
        let href = try XCTUnwrap(relocated.locator?.object?["href"]?.string)
        XCTAssertEqual(href, second.map?.href(for: 2))
    }
    func testMissingPathSearchesResourceTextAndRetainsReverseMapping() async throws {
        let book = LocatorTestSupport.book(["移到其他资源的原句。"])
        let working = try await LocatorTestSupport.bridge(book, self)
        let publication = try XCTUnwrap(working.publication)
        let map = PublicationMap(book: book, readingOrder: publication.readingOrder.map(\.href), titles: [:], revision: "remapped-source")
        XCTAssertTrue(map.chapters.isEmpty)
        let bridge = try LocatorBridge(book: book, map: map, publication: publication)
        let result = try await bridge.resolve(.init(chapter: 0, position: 0, anchor: .init(quote: "移到其他资源的原句。")))
        XCTAssertEqual(result.status, .textRelocated)
        let restored = try await bridge.reverse(XCTUnwrap(StoredLocator.readium(result.locator)))
        XCTAssertEqual(restored.target.chapter, 0); XCTAssertEqual(restored.target.position, 0)
        let shown = try await bridge.displayLocator(result.locator, mode: "s2t")
        XCTAssertNotNil(shown)
    }
    func testFirstVisibleCSSSelectorResolvesOriginalSentence() async throws {
        let book = LocatorTestSupport.book(["第一句。第二句。"])
        let bridge = try await LocatorTestSupport.bridge(book, self)
        let publication = try XCTUnwrap(bridge.publication)
        var locator = ReadiumShared.Locator(href: publication.readingOrder[0].url(), mediaType: .xhtml)
        locator.locations.cssSelector = "body > p"
        let result = try await bridge.reverse(locator)
        XCTAssertTrue(result.precise); XCTAssertEqual(result.target.position, 0)
        XCTAssertNotNil(result.locator?.object?["locations"]?.object?["domRange"])
    }
    func testOriginalEPUBFixtureUsesDocumentPathsNotSpineOffsets() async throws {
        let encoded = try LocatorTestSupport.fixture("original.epub.b64")
        let text = try XCTUnwrap(String(data: encoded, encoding: .utf8))
        let data = try XCTUnwrap(Data(base64Encoded: text, options: .ignoreUnknownCharacters))
        let url = try LocatorTestSupport.temporary(self).appendingPathComponent("original.epub")
        try data.write(to: url)
        let book = try BookImporter.read(url).book
        let publication = try await ReadiumService().open(url)
        let map = PublicationMap(book: book, readingOrder: ["EPUB/extra.xhtml"] + publication.readingOrder.map(\.href), titles: [:], revision: PublicationDigest.data(data))
        let bridge = try LocatorBridge(book: book, map: map, publication: publication)
        let result = try await bridge.resolve(.init(chapter: 0, position: 0))
        XCTAssertEqual(result.locator?.object?["href"]?.string, publication.readingOrder.first?.href)
    }
    func testDuplicatePathsGetUniqueDerivedHrefsAndCorrectRanges() async throws {
        var book = LocatorTestSupport.book(["甲句。", "乙句。"])
        var chapters = book.chapters
        for i in chapters.indices { var document = chapters[i].fields["document"]?.object ?? [:]; document["path"] = .string("same.xhtml"); chapters[i].fields["document"] = .object(document) }
        book.fields["chapters"] = .array(chapters.map { .object($0.fields) })
        let bridge = try await LocatorTestSupport.bridge(book, self)
        XCTAssertNotEqual(bridge.map?.href(for: 0), bridge.map?.href(for: 1))
        for chapter in 0...1 {
            let result = try await bridge.resolve(.init(chapter: chapter, position: 0))
            let reverse = try await bridge.reverse(XCTUnwrap(StoredLocator.readium(result.locator)), chapterHint: chapter)
            XCTAssertEqual(reverse.target.chapter, chapter)
        }
    }
    func testImageOnlyResourceIsApproximateAndNeverDecorated() async throws {
        let book = LocatorTestSupport.book([""])
        let bridge = try await LocatorTestSupport.bridge(book, self)
        let result = try await bridge.resolve(.init(chapter: 0, position: 0))
        XCTAssertEqual(result.status, .approximate)
        let marks = [Highlight(chapter: 0, start: 0, end: 0, text: "丢失的标注")]
        let batch = try await ReadiumAnnotations.decorations(marks, bridge: bridge, mode: "none")
        XCTAssertTrue(batch.decorations.isEmpty); XCTAssertEqual(batch.unresolved, marks.map(\.id))
    }
    func testFiveColorsLegacyGreenAndThreeDecorationStyles() async throws {
        let bridge = try await LocatorTestSupport.bridge(LocatorTestSupport.book(["选段。"]), self)
        let colors = ReaderMark.palette.map(\.key) + ["green"]
        for kind in ["background", "underline", "wavy"] {
            let marks = colors.map { Highlight(chapter: 0, start: 0, end: 0, text: "选段。", color: $0, style: kind) }
            let batch = try await ReadiumAnnotations.decorations(marks, bridge: bridge, mode: "none")
            XCTAssertEqual(batch.decorations.count, 6); XCTAssertTrue(batch.unresolved.isEmpty)
            for (decoration, mark) in zip(batch.decorations, marks) {
                XCTAssertEqual(decoration.id, mark.id.uuidString)
                XCTAssertEqual((decoration.style.config as? Decoration.Style.HighlightConfig)?.tint, ReaderMark.uiColor(mark.color))
                XCTAssertEqual(decoration.style.id, kind == "wavy" ? ReadiumAnnotations.wavy : kind == "underline" ? .underline : .highlight)
            }
        }
        XCTAssertNotEqual(ReadiumAnnotations.userGroup, ReadiumAnnotations.speechGroup)
        XCTAssertNotEqual(ReadiumAnnotations.userGroup, ReadiumAnnotations.searchGroup)
        XCTAssertNotNil(ReadiumAnnotations.templates()[ReadiumAnnotations.wavy])
    }
    func testNativeLogicalHrefsRoundTripAllFormats() async throws {
        for format in ["TXT", "Markdown", "MOBI", "DOCX", "HTML", "PDF", "CBZ"] {
            var book = LocatorTestSupport.book(["一句😀。后句。"], format: format)
            if format == "PDF" { book.fields["pdf"] = .string("") }
            if format == "CBZ" { book.fields["comic"] = .bool(true) }
            let bridge = try LocatorBridge(book: book)
            let result = try await bridge.resolve(.init(chapter: 0, position: 1))
            let locator = try XCTUnwrap(StoredLocator.readium(result.locator))
            XCTAssertTrue(locator.href.string.hasPrefix("tingye://book/locator-book/"))
            XCTAssertTrue(locator.href.string.contains(format == "PDF" || format == "CBZ" ? "/page/" : "/chapter/"))
            let reverse = try await bridge.reverse(locator)
            XCTAssertEqual(reverse.target.chapter, 0); XCTAssertEqual(reverse.target.position, 1)
        }
    }
    func testInvalidLocatorIsolatedInProgressBookmarkHighlightAndBackups() throws {
        let book = LocatorTestSupport.book(format: "TXT")
        let originals: [JSONValue] = [.number(42), .object(["href": .string("x"), "type": .string("text/plain"), "locations": .object(["progression": .number(2)])]), .object(["type": .string("text/plain")])]
        for invalid in originals {
            var row = ShelfEntry(book: book, progress: .init(chapter: 0, position: 1, anchor: .init(quote: "重复。")))
            row.bookmarks = [.init(chapter: 0, position: 1, excerpt: "重复。")]
            row.highlights = [.init(chapter: 0, start: 1, end: 1, text: "重复。", note: "笔记")]
            var raw = try XCTUnwrap(JSONDecoder().decode(JSONValue.self, from: Integrity.encoder().encode(row)).object)
            var progress = try XCTUnwrap(raw["progress"]?.object); progress["locator"] = invalid; raw["progress"] = .object(progress)
            for key in ["bookmarks", "highlights"] {
                var item = try XCTUnwrap(raw[key]?.array?.first?.object); item["locator"] = invalid; raw[key] = .array([.object(item)])
            }
            let decoded = try JSONDecoder().decode(ShelfEntry.self, from: JSONEncoder().encode(JSONValue.object(raw)))
            XCTAssertNil(decoded.progress.locator); XCTAssertNil(decoded.bookmarks[0].locator); XCTAssertNil(decoded.notes[0].locator)
            XCTAssertEqual(decoded.progress.anchor, row.progress.anchor); XCTAssertEqual(decoded.notes[0].note, "笔记")
            let packet = BackupPacket(book: book, progress: decoded.progress)
            XCTAssertEqual(try JSONDecoder().decode(BackupPacket.self, from: JSONEncoder().encode(packet)).progress, row.progress)
        }
    }
}
