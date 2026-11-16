import XCTest
import ReadiumShared
import ReadiumZIPFoundation
@testable import Tingye

@MainActor
final class ReadiumPublicationTests: XCTestCase {
    private func fixture(_ name: String) throws -> URL {
        // original.epub 以 base64 文本形式入库（仓库推送通道只支持文本文件），用时解码到临时目录。
        if name == "original.epub" {
            let b64URL = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "original.epub.b64", withExtension: nil, subdirectory: "Fixtures/readium"))
            let text = try String(contentsOf: b64URL, encoding: .utf8)
            let data = try XCTUnwrap(Data(base64Encoded: text, options: [.ignoreUnknownCharacters]))
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("readium-fixture-" + UUID().uuidString + ".epub")
            try data.write(to: url)
            addTeardownBlock { try? FileManager.default.removeItem(at: url) }
            return url
        }
        return try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: nil, subdirectory: "Fixtures/readium"))
    }
    private func legacy() throws -> Book {
        try JSONDecoder().decode(Book.self, from: Data(contentsOf: fixture("legacy-book.json"))).validated()
    }
    private func temporary() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("readium-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    private func xml(_ data: Data) -> Bool {
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true; parser.shouldResolveExternalEntities = false
        return parser.parse()
    }
    private func string(_ zip: SafeArchive, _ path: String) throws -> String {
        try XCTUnwrap(String(data: zip.data(path), encoding: .utf8))
    }

    func testReadiumOpensOriginalFixtureAndSafeArchiveStillExtractsIt() async throws {
        let url = try fixture("original.epub")
        let publication = try await ReadiumService().open(url)
        XCTAssertEqual(publication.readingOrder.count, 2)
        let cover = try await publication.cover().get()
        XCTAssertNotNil(cover)
        let toc = try await publication.tableOfContents().get()
        XCTAssertEqual(toc.first?.title, "第一章 原包")
        XCTAssertEqual(toc.first?.href, publication.readingOrder.first?.href)
        let zip = try SafeArchive(url: url)
        XCTAssertEqual(try string(zip, "mimetype"), "application/epub+zip")
        XCTAssertTrue(try string(zip, "EPUB/one.xhtml").contains("第一章 原包"))
        let imported = try await BookImporter.read(url)
        XCTAssertEqual(imported.book.chapters.count, 2)
        XCTAssertNotNil(imported.source)
        XCTAssertNil(imported.book.epubSource) // Metadata binds only when a library transaction commits.
    }

    func testLegacyRebuildOpensInReadiumWithOrderedSpineNavImagesAndCover() async throws {
        let book = try legacy(), base = try temporary()
        let result = try await LegacyEPUBBuilder().build(book, to: base.appendingPathComponent("artifact"))
        let publication = try await ReadiumService().open(result.url)
        XCTAssertEqual(publication.readingOrder.count, book.chapters.count)
        let cover = try await publication.cover().get()
        XCTAssertNotNil(cover)
        XCTAssertEqual(publication.readingOrder.map(\.href), result.map.chapters.map(\.href))
        let toc = try await publication.tableOfContents().get()
        XCTAssertEqual(toc.map(\.title), book.chapters.map { Optional($0.title) })
        let zip = try SafeArchive(url: result.url)
        let opf = try string(zip, "EPUB/package.opf")
        XCTAssertTrue(opf.contains("properties=\"nav\""))
        XCTAssertTrue(opf.contains("properties=\"cover-image\""))
        XCTAssertTrue(opf.contains("media-type=\"image/png\""))
        XCTAssertEqual(zip.archive.filter { $0.path.hasPrefix("EPUB/images/") }.count, 1) // Hash deduplication.
        for entry in zip.archive where ["xml", "opf", "xhtml"].contains((entry.path as NSString).pathExtension) {
            XCTAssertTrue(xml(try zip.data(entry.path)), entry.path)
        }
        let first = try string(zip, result.map.chapters[0].href)
        XCTAssertEqual(first.components(separatedBy: "<body").count - 1, 1)
        XCTAssertTrue(first.contains("class=\"publisher\""))
        XCTAssertTrue(first.contains("ch-000002.xhtml#end"))
        XCTAssertTrue(first.contains("../images/"))
        XCTAssertFalse(first.contains("tingye-resource:"))
        let css = try string(zip, "EPUB/styles/ch-000001.css")
        XCTAssertTrue(css.contains("../images/")); XCTAssertFalse(css.contains("@import")); XCTAssertFalse(css.contains("lost.woff"))
        let second = try string(zip, result.map.chapters[1].href)
        XCTAssertFalse(second.contains("lost.jpg")); XCTAssertFalse(second.contains("<script"))
        XCTAssertTrue(result.report.losses.contains { $0.code == "html-missing" && $0.chapter == 2 })
        XCTAssertTrue(result.report.losses.contains { $0.code == "image-missing" })
        XCTAssertEqual(result.map.chapters(forOriginalPath: "OEBPS/中文/第一章.xhtml").count, 2)
        XCTAssertEqual(try legacy(), book) // No text snapshot mutation.
        let raw = try Data(contentsOf: result.url)
        XCTAssertEqual(Array(raw[8..<10]), [0, 0]); XCTAssertEqual(Array(raw[28..<30]), [0, 0])
        XCTAssertEqual(String(data: raw[30..<38], encoding: .utf8), "mimetype")
    }

    func testInlineDataURIIsExtractedAndBrokenXMLFallsBackToText() async throws {
        var book = try legacy()
        let image = try XCTUnwrap(book.resourceMap["r0"]?.string)
        let chapters = [Chapter(title: "内嵌图", text: "内嵌图。", extras: ["document": .object([
            "html": .string("<body><p>内嵌图。</p><img src=\"\(image)\"/></body>"), "css": .string("")])]),
            Chapter(title: "坏 XML", text: "可靠的纯文本。", extras: ["document": .object([
                "html": .string("<p>坏控制符\u{0001}</p>"), "css": .string("")])])]
        book.fields["chapters"] = .array(chapters.map { .object($0.fields) })
        let destination = try temporary().appendingPathComponent("inline")
        let built = try await LegacyEPUBBuilder().build(book, to: destination)
        let zip = try SafeArchive(url: built.url)
        XCTAssertTrue(try string(zip, built.map.chapters[0].href).contains("../images/"))
        XCTAssertTrue(built.report.losses.contains { $0.code == "html-fallback" && $0.chapter == 1 })
        XCTAssertTrue(try string(zip, built.map.chapters[1].href).contains("可靠的纯文本"))
        _ = try await ReadiumService().open(built.url)
    }

    func testRevisionIgnoresReadStateButChangesWithContentAndGeneratorKey() throws {
        let book = try legacy(), hash = try PublicationMap.contentHash(for: book)
        var changed = book
        changed.fields["nativeReadChapters"] = .array([.number(1)])
        XCTAssertEqual(try PublicationMap.contentHash(for: changed), hash)
        changed.fields["title"] = .string("新版本")
        XCTAssertNotEqual(try PublicationMap.contentHash(for: changed), hash)
        XCTAssertTrue(try PublicationMap.revision(for: book).contains("legacy-\(LegacyEPUBBuilder.generatorVersion)-"))
        XCTAssertNil(PublicationMap.normalized("%2fetc/passwd"))
        XCTAssertNil(PublicationMap.normalized("%2e%2e/file"))
        XCTAssertNil(PublicationMap.normalized("a/%2e%2e/%2e%2e/file"))
    }

    func testCacheCoalescesRegeneratesAndPinsFilesAcrossCleanup() async throws {
        let base = try temporary(), disk = try LibraryDisk(owner: "cache", base: base), book = try legacy()
        let store = PublicationStore(disk: disk, cacheBase: base.appendingPathComponent("Caches"))
        async let a = store.prepare(book)
        async let b = store.prepare(book)
        let (first, second) = try await (a, b)
        XCTAssertEqual(first.url, second.url)
        let session = try await store.pin(first)
        try await store.clearCache()
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.url.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: session.url.path))
        let regenerated = try await store.prepare(book)
        XCTAssertEqual(regenerated.revision, first.revision)
        XCTAssertTrue(FileManager.default.fileExists(atPath: regenerated.url.path))
        // Corruption must not be accepted merely because a completion receipt exists.
        try Data("broken".utf8).write(to: regenerated.url)
        let repaired = try await store.prepare(book)
        _ = try await ReadiumService().open(repaired.url)
        // Even identical JSON replacements invalidate the previous generation's physical cache.
        try disk.commitImport(disk.prepareImport(book, source: nil))
        let replaced = try await store.prepare(book)
        XCTAssertNotEqual(replaced.url, repaired.url)
        XCTAssertEqual(replaced.revision, repaired.revision)
        await store.release(session)
        XCTAssertFalse(FileManager.default.fileExists(atPath: session.url.path))
    }

    func testSourceCommitRepairReplacementAndDeleteAreBoundToBookAndSidecar() async throws {
        let base = try temporary(), disk = try LibraryDisk(owner: "source", base: base)
        let imported = try await BookImporter.read(fixture("original.epub"))
        let prepared = try disk.prepareImport(imported.book, source: imported.source)
        try disk.commitImport(prepared, catalog: [ShelfEntry(book: prepared.book)])
        let stored = try disk.read(imported.book.id)
        let source = try XCTUnwrap(disk.sourceURL(for: stored))
        XCTAssertEqual(stored.epubSource?.relativePath, "Publications/\(stored.id)/source.epub")
        XCTAssertEqual(try PublicationDigest.file(source), stored.epubSource?.sha256)
        XCTAssertEqual(try disk.catalog().first?.id, stored.id)
        var stateOnly = stored; stateOnly.fields["nativeReadChapters"] = .array([.number(1)])
        try disk.write(stateOnly)
        XCTAssertEqual(try disk.sourceURL(for: disk.read(stored.id)), source)
        let repair = try disk.prepareImport(stored, source: imported.source, origin: .repaired)
        try disk.commitImport(repair)
        XCTAssertEqual(try disk.read(stored.id).epubSource?.origin, .repaired)
        // A backup carrying only the old relative path must never inherit this device's source.
        let replacement = try disk.prepareImport(stored, source: nil)
        try disk.commitImport(replacement)
        XCTAssertNil(try disk.read(stored.id).epubSource)
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        try disk.commitImport(disk.prepareImport(stored, source: imported.source))
        try disk.remove(stored.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: try disk.file(stored.id).path))
    }

    func testSourceCatalogFailureRollsBackAndRestartReplaysUnfinishedJournal() async throws {
        let base = try temporary(), disk = try LibraryDisk(owner: "rollback", base: base)
        let imported = try await BookImporter.read(fixture("original.epub"))
        let first = try disk.prepareImport(imported.book, source: imported.source)
        try disk.commitImport(first)
        let old = try disk.read(first.book.id), original = try XCTUnwrap(disk.sourceURL(for: old))
        let oldBytes = try Data(contentsOf: original)
        let catalog = disk.root.appendingPathComponent("catalog.json")
        try FileManager.default.createDirectory(at: catalog, withIntermediateDirectories: false)
        var changed = old; changed.fields["title"] = .string("不应提交")
        XCTAssertThrowsError(try disk.commitImport(disk.prepareImport(changed, source: nil), catalog: []))
        XCTAssertEqual(try disk.read(old.id), old)
        XCTAssertEqual(try Data(contentsOf: original), oldBytes)
        try FileManager.default.removeItem(at: catalog)

        let interrupted = disk.root.appendingPathComponent(".PublicationTransactions/interrupted")
        try FileManager.default.createDirectory(at: interrupted, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: disk.file(old.id), to: interrupted.appendingPathComponent("old-book"))
        try FileManager.default.copyItem(at: disk.publicationDirectory(old.id), to: interrupted.appendingPathComponent("old-publication"))
        let journal: [String: Any] = ["id": old.id, "previous": ["book": true, "publication": true]]
        try JSONSerialization.data(withJSONObject: journal).write(to: interrupted.appendingPathComponent("journal.json"))
        try Data("invalid new book".utf8).write(to: disk.file(old.id))
        try FileManager.default.removeItem(at: disk.publicationDirectory(old.id))
        let reopened = try LibraryDisk(owner: "rollback", base: base)
        XCTAssertEqual(try reopened.read(old.id), old)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(reopened.sourceURL(for: old))), oldBytes)
        XCTAssertFalse(FileManager.default.fileExists(atPath: interrupted.path))
    }

    func testAppImportAndRepairPersistOriginalWithoutChangingLegacyReaderSnapshot() async throws {
        let base = try temporary(), disk = try LibraryDisk(owner: "app-import", base: base)
        let suite = "readium.app." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: ProgressSync.enabledKey)
        let model = AppModel(disk: disk, progressSync: ProgressSync(store: ReadiumMemoryKeyValueStore(), defaults: defaults, account: { false }))
        try await model.importFiles([fixture("original.epub")])
        let row = try XCTUnwrap(model.entries.first), imported = try disk.read(row.id)
        XCTAssertNotNil(try disk.sourceURL(for: imported))
        XCTAssertEqual(imported.chapters.map(\.title), ["第一章 原包", "第二章 原包"])
        try await model.repair(row.id, from: fixture("original.epub"))
        let repaired = try disk.read(row.id)
        XCTAssertEqual(repaired.epubSource?.origin, .repaired)
        XCTAssertEqual(repaired.chapters, imported.chapters)
        XCTAssertEqual(repaired.id, row.id)
        var backup = repaired; backup.epubSource = nil
        try await model.add(backup)
        XCTAssertNil(try disk.sourceURL(for: disk.read(row.id)))
        model.flushPendingSaves()
        _ = try await model.beginLibraryRestore() // Drain background index tasks before removing the test directory.
    }

    func testBadSourceAndMissingResourcesFailOrReportWithoutPublishingPartialArtifact() async throws {
        let base = try temporary(), disk = try LibraryDisk(owner: "bad", base: base)
        var book = try legacy()
        book.epubSource = EPUBSource(relativePath: "../../outside.epub", sha256: String(repeating: "a", count: 64), origin: .imported, mappingVersion: 1)
        XCTAssertNil(book.epubSource)
        XCTAssertNil(try disk.sourceURL(for: book))
        let bad = base.appendingPathComponent("bad.epub"); try Data("not zip".utf8).write(to: bad)
        do { _ = try await ReadiumService().open(bad); XCTFail("Bad EPUB must fail") } catch {}
        let nonEPUB = Book(title: "TXT", format: "TXT", chapters: [.init(title: "正文", text: "文字")])
        let destination = base.appendingPathComponent("bad-output")
        do { _ = try await LegacyEPUBBuilder().build(nonEPUB, to: destination); XCTFail("Only EPUB") } catch {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        book.fields["resources"] = .object([:])
        let result = try await LegacyEPUBBuilder().build(book, to: base.appendingPathComponent("missing"))
        XCTAssertTrue(result.report.losses.contains { $0.code == "cover-missing" })
        _ = try await ReadiumService().open(result.url)
    }

    func testCancelledBuildAndUnwritableDestinationDoNotPublish() async throws {
        let base = try temporary(), book = try legacy(), destination = base.appendingPathComponent("cancelled")
        let cancelled = Task<LegacyEPUBBuilder.Result, Error> {
            try Task.checkCancellation()
            return try await LegacyEPUBBuilder().build(book, to: destination)
        }
        cancelled.cancel()
        do { _ = try await cancelled.value; XCTFail("Must cancel") } catch is CancellationError {} catch { XCTFail("\(error)") }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        let blocker = base.appendingPathComponent("file-not-directory")
        try Data().write(to: blocker)
        do { _ = try await LegacyEPUBBuilder().build(book, to: blocker.appendingPathComponent("artifact")); XCTFail("Must fail") } catch {}
        XCTAssertNil(try LegacyEPUBBuilder.cached(at: destination, contentHash: PublicationMap.contentHash(for: book)))
    }
}

private final class ReadiumMemoryKeyValueStore: ProgressKeyValueStore {
    private var values: [String: Any] = [:]
    func dictionary(forKey key: String) -> [String: Any]? { values[key] as? [String: Any] }
    func set(_ value: Any?, forKey key: String) { values[key] = value }
    func removeObject(forKey key: String) { values[key] = nil }
    var dictionaryRepresentation: [String: Any] { values }
    func synchronize() -> Bool { true }
}


extension ReadiumPublicationTests {
    func testCoordinatedEPUBImportRetainsIndependentOriginalForReadiumAfterProviderDisappears() async throws {
        let external = try fixture("original.epub")
        let digest = try PublicationDigest.file(external)
        let imported = try await BookImporter.readCoordinated(external)
        let source = try XCTUnwrap(imported.source)
        defer { withExtendedLifetime(source) {} }
        try FileManager.default.removeItem(at: external)
        XCTAssertEqual(source.sha256, digest)
        XCTAssertEqual(try PublicationDigest.file(source.url), digest)
        XCTAssertEqual(imported.book.chapters.map(\.title), ["第一章 原包", "第二章 原包"])
        let publication = try await ReadiumService().open(source.url)
        XCTAssertEqual(publication.readingOrder.count, 2)
        let contents = try await publication.tableOfContents().get()
        XCTAssertFalse(contents.isEmpty)
    }
}
