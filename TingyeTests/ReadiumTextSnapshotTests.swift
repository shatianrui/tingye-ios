import XCTest
import ReadiumShared
@testable import Tingye

// Async equivalents preserve the failure assertions at the importer/restore API boundary.
func assertImportThrows(_ url: URL, file: StaticString = #filePath, line: UInt = #line, check: (Error) -> Void = { _ in }) async {
    do { _ = try await BookImporter.read(url); XCTFail("Import should fail", file: file, line: line) }
    catch { check(error) }
}
func assertRestoreThrows(_ disk: LibraryDisk, _ archive: ICloudArchive, owner: String, entries: [ShelfEntry], file: StaticString = #filePath, line: UInt = #line) async {
    do { _ = try await disk.restore(archive, owner: owner, entries: entries); XCTFail("Restore should fail", file: file, line: line) }
    catch {}
}

@MainActor
enum ReadiumUnit4Support {
    static func fixture(_ test: XCTestCase, _ name: String = "snapshot") throws -> URL {
        let bytes = try LocatorTestSupport.fixture(name + ".epub.b64")
        let data = try XCTUnwrap(Data(base64Encoded: String(decoding: bytes, as: UTF8.self), options: .ignoreUnknownCharacters))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".epub")
        try data.write(to: url); test.addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    static func disk(_ test: XCTestCase) throws -> LibraryDisk {
        try LibraryDisk(owner: UUID().uuidString, base: LocatorTestSupport.temporary(test))
    }
    static func model(_ test: XCTestCase, _ disk: LibraryDisk) throws -> AppModel {
        let suite = UUID().uuidString, defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.set(false, forKey: ProgressSync.enabledKey)
        let model = AppModel(disk: disk, progressSync: ProgressSync(store: LocatorKeyValueStore(), defaults: defaults, account: { false }))
        test.addTeardownBlock { @MainActor in
            _ = try await model.beginLibraryRestore()
            try await model.publicationStore().clearCache()
            defaults.removePersistentDomain(forName: suite)
        }
        return model
    }
}

@MainActor
final class ReadiumTextSnapshotTests: XCTestCase {
    func testPublicationTextMatchesHTMLAndSentenceRulesIncludingUTF16AndLongChunks() async throws {
        let url = try ReadiumUnit4Support.fixture(self)
        let publication = try await ReadiumService().open(url)
        let snapshot = try await EPUBTextSnapshotBuilder.build(publication, fallbackTitle: "fallback", revision: "fixture")
        let zip = try SafeArchive(url: url)
        for (index, link) in publication.readingOrder.enumerated() {
            let html = try BookImporter.decode(zip.data(link.href))
            let expected = HTMLText.chapter(html, title: "old path")
            XCTAssertEqual(snapshot.book.chapters[index].text, expected.text)
            XCTAssertEqual(snapshot.book.chapters[index].fields["marks"], expected.fields["marks"])
            XCTAssertEqual(Sentence.split(snapshot.book.chapters[index].text), Sentence.split(expected.text))
        }
        XCTAssertTrue(snapshot.book.chapters[0].text.contains("春&风，归来😀。"))
        XCTAssertFalse(snapshot.book.chapters[0].text.contains("不能朗读"))
        XCTAssertGreaterThan(Sentence.split(snapshot.book.chapters[0].text).count, 8)
    }
    func testMetadataCoverTOCAndAllReadingOrderResourcesAreMapped() async throws {
        let url = try ReadiumUnit4Support.fixture(self), publication = try await ReadiumService().open(url)
        let snapshot = try await EPUBTextSnapshotBuilder.build(publication, fallbackTitle: "fallback", revision: "source-fixture")
        XCTAssertEqual(snapshot.book.title, "文本快照夹具"); XCTAssertEqual(snapshot.book.author, "夹具作者")
        XCTAssertEqual(snapshot.book.fields["description"]?.string, "元数据摘要")
        XCTAssertEqual(snapshot.book.fields["category"]?.string, "测试分类")
        XCTAssertNotNil(snapshot.book.coverData)
        XCTAssertEqual(snapshot.book.chapters.map(\.title), ["目录优先标题", "纯插图", "空章节"])
        XCTAssertEqual(snapshot.map.chapters.map(\.href), publication.readingOrder.map(\.href))
        XCTAssertEqual(snapshot.map.publicationRevision, "source-fixture")
        XCTAssertEqual(snapshot.book.chapters[2].text, "")
        XCTAssertFalse(snapshot.book.chapters[1].fields["nativeImages"]?.array?.isEmpty ?? true)
        XCTAssertTrue(snapshot.book.chapters[0].fields["document"]?.object?["css"]?.string?.contains("#123456") == true)
        XCTAssertNotNil(snapshot.book.fields["epubTextMap"])
    }
    func testReadiumRejectsInvalidEPUBWithoutLegacyFallbackOrLibraryMutation() async throws {
        let disk = try ReadiumUnit4Support.disk(self), model = try ReadiumUnit4Support.model(self, disk)
        let url = disk.root.appendingPathComponent("bad.epub")
        try Data("not an EPUB".utf8).write(to: url)
        await assertImportThrows(url)
        do { try await model.importFiles([url]); XCTFail("Bad EPUB must report failure") } catch {}
        XCTAssertTrue(model.entries.isEmpty); XCTAssertTrue(try disk.catalog().isEmpty)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: disk.root.appendingPathComponent("Books").path).isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: disk.root.appendingPathComponent("Publications").path))
    }
    func testImportCommitFailureRollsBackBookOriginalAndCatalogTogether() async throws {
        let disk = try ReadiumUnit4Support.disk(self)
        let imported = try await BookImporter.read(ReadiumUnit4Support.fixture(self))
        let prepared = try disk.prepareImport(imported.book, source: imported.source)
        try disk.commitImport(prepared)
        let before = try disk.read(prepared.book.id), source = try XCTUnwrap(disk.sourceURL(for: before))
        let bytes = try Data(contentsOf: source), epoch = try disk.publicationCacheEpoch(before.id)
        try FileManager.default.createDirectory(at: disk.root.appendingPathComponent("catalog.json"), withIntermediateDirectories: false)
        let replacement = try disk.prepareImport(before, source: nil)
        XCTAssertThrowsError(try disk.commitImport(replacement, catalog: []))
        XCTAssertEqual(try disk.read(before.id), before); XCTAssertEqual(try Data(contentsOf: source), bytes)
        XCTAssertEqual(try disk.publicationCacheEpoch(before.id), epoch)
    }
    func testSpeechStartsAtVisibleOriginalSentenceAndMapsPlaybackBackInDisplayMode() async throws {
        let book = LocatorTestSupport.book(["第一句。简体汉语😀。第三句。"]), bridge = try await LocatorTestSupport.bridge(book, self)
        let (result, location, decoration) = try await ReadiumSpeechBridge.playback(chapter: 0, position: 1, bridge: bridge, mode: "s2t")
        let start = try await ReadiumSpeechBridge.start(visible: result.locator, chapter: 0, position: 0, bridge: bridge)
        XCTAssertEqual(start.position, 1); XCTAssertEqual(start.chapter, 0)
        XCTAssertEqual(location.text.highlight, "簡體漢語😀。")
        XCTAssertNotNil(decoration); XCTAssertEqual(decoration?.locator, location)
        XCTAssertEqual(book.chapters[0].text, "第一句。简体汉语😀。第三句。")
        XCTAssertNotEqual(ReadiumAnnotations.speechGroup, ReadiumAnnotations.userGroup)
        XCTAssertNotEqual(ReadiumAnnotations.searchGroup, ReadiumAnnotations.speechGroup)
    }
    func testRepeatedSearchResultsKeepTheirExactUTF16Ranges() async throws {
        let book = LocatorTestSupport.book(["甲😀目标。乙😀目标。"]), bridge = try await LocatorTestSupport.bridge(book, self)
        let hits = ReaderSearch.matches(in: book.chapters, query: "😀目标")
        XCTAssertEqual(hits.count, 2)
        XCTAssertEqual(ReaderSearch.hitRange(in: book.chapters[0], query: "  😀目标  ", offset: hits[1].offset), NSRange(location: hits[1].offset, length: 4))
        XCTAssertNil(ReaderSearch.hitRange(in: Chapter(title: "只中标题", text: "不相干正文。"), query: "只中标题", offset: 0))
        var locations: [Tingye.JSONValue] = []
        for hit in hits {
            let result = try await bridge.resolve(.init(chapter: hit.index, position: Sentence.index(at: hit.offset, in: Sentence.split(book.chapters[hit.index].text)), textRange: NSRange(location: hit.offset, length: 4)))
            XCTAssertTrue(result.precise)
            locations.append(try XCTUnwrap(result.locator))
            let display = try await bridge.displayLocator(result.locator, mode: "none", requireRange: true)
            XCTAssertEqual(display?.text.highlight, "😀目标")
        }
        XCTAssertNotEqual(locations[0], locations[1])
    }
}
