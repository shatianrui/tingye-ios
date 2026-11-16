import XCTest
import ReadiumShared
@testable import Tingye

@MainActor
final class ReadiumBackupSourceTests: XCTestCase {
    private func imported(_ name: String = "snapshot") async throws -> BookImporter.Imported {
        try await BookImporter.read(ReadiumUnit4Support.fixture(self, name))
    }
    private func commit(_ imported: BookImporter.Imported, to disk: LibraryDisk) throws -> Book {
        let write = try disk.prepareImport(imported.book, source: imported.source)
        try disk.commitImport(write, catalog: [ShelfEntry(book: write.book)])
        return write.book
    }
    func testSingleBookPacketJSONRoundTripRestoresOriginalAndRebuildsTextMap() async throws {
        let disk = try ReadiumUnit4Support.disk(self), source = try await imported()
        let book = try commit(source, to: disk), attachment = try XCTUnwrap(disk.backupAttachment(for: book))
        let bridge = try LocatorBridge(book: book, map: JSONDecoder().decode(PublicationMap.self, from: Integrity.encoder().encode(book.fields["epubTextMap"])))
        // Store a real source Locator with its old compatibility coordinates and anchor.
        let publication = try await ReadiumService().open(XCTUnwrap(disk.sourceURL(for: book)))
        let live = try LocatorBridge(book: book, map: bridge.map, publication: publication)
        let resolved = try await live.resolve(.init(chapter: 0, position: 1))
        var progress = ReadingProgress(chapter: 0, position: 1, updatedAt: 123, anchor: resolved.target.anchor)
        progress.locator = resolved.locator; progress.publicationRevision = live.revision
        let packet = BackupPacket(book: book, progress: progress, epubAttachment: attachment)
        let url = disk.root.appendingPathComponent("export.json")
        try Integrity.encoder().encode(packet).write(to: url)
        let restored = try await BookImporter.read(url)
        XCTAssertEqual(restored.progress, progress)
        XCTAssertEqual(restored.book.id, book.id); XCTAssertEqual(restored.book.chapters, book.chapters)
        XCTAssertEqual(restored.source?.sha256, book.epubSource?.sha256)
        let newDisk = try ReadiumUnit4Support.disk(self), stored = try commit(restored, to: newDisk)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(newDisk.sourceURL(for: stored))), attachment.data)
        let store = PublicationStore(disk: newDisk), prepared = try await store.prepare(stored)
        XCTAssertEqual(prepared.revision, live.revision)
    }
    func testLibraryFileRoundTripKeepsOriginalFourReferencesAndOtherBooks() async throws {
        let disk = try ReadiumUnit4Support.disk(self), book = try commit(try await imported(), to: disk)
        let attachment = try XCTUnwrap(disk.backupAttachment(for: book))
        let model = try ReadiumUnit4Support.model(self, disk)
        let exportURL = try await model.makeLibraryExportFile()
        addTeardownBlock { try? FileManager.default.removeItem(at: exportURL) }
        let exported = try JSONDecoder().decode(ICloudArchive.self, from: Data(contentsOf: exportURL))
        XCTAssertEqual(exported.books.first?.epubAttachment?.data, attachment.data)
        let mark = Bookmark(chapter: 0, position: 1, excerpt: "春&风，归来😀。")
        let note = Highlight(chapter: 0, start: 1, end: 1, text: mark.excerpt, note: "笔记")
        let packet = BackupPacket(book: book, progress: .init(chapter: 0, position: 1, updatedAt: 42))
        let archive = ICloudArchive(owner: "old-owner", books: [.init(packet: packet, bookmarks: [mark], highlights: [note], listeningProgress: .init(chapter: 0, position: 2, updatedAt: 43), epubAttachment: attachment)])
        let bytes = try Integrity.encoder().encode(archive), recovered = try JSONDecoder().decode(ICloudArchive.self, from: bytes)
        XCTAssertEqual(recovered.version, 1)
        let destination = try ReadiumUnit4Support.disk(self)
        let other = Book(id: "other", title: "保留", format: "TXT", chapters: [Chapter(title: "一", text: "原文。")])
        try destination.write(other); try destination.saveCatalog([ShelfEntry(book: other)])
        let rows = try await destination.restore(recovered, owner: destination.root.lastPathComponent, entries: destination.catalog())
        let row = try XCTUnwrap(rows.first { $0.id == book.id }), restored = try destination.read(book.id)
        XCTAssertEqual(rows.count, 2); XCTAssertEqual(try destination.read(other.id), other)
        XCTAssertEqual(row.progress.position, 1); XCTAssertEqual(row.listeningProgress?.position, 2)
        XCTAssertEqual(try Integrity.encoder().encode(row.bookmarks), try Integrity.encoder().encode([mark])); XCTAssertEqual(row.notes, [note])
        XCTAssertEqual(restored.chapters, book.chapters); XCTAssertNotNil(restored.fields["epubTextMap"])
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(destination.sourceURL(for: restored))), attachment.data)
        let cloud = ICloudBackupStore(root: destination.root.appendingPathComponent("cloud"))
        var combined = recovered
        combined.books.append(.init(packet: .init(book: other, progress: .init()), bookmarks: []))
        let bothURL = try cloud.save(combined)
        var only = recovered; only.owner = "only"
        let onlyURL = try cloud.save(only)
        let removal = try await cloud.removeBook(book.id)
        XCTAssertEqual(removal.rewritten, 1); XCTAssertEqual(removal.deleted, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: onlyURL.path))
        let kept = try cloud.read(bothURL, owner: combined.owner)
        XCTAssertEqual(kept.books.map { $0.packet.book.id }, [other.id])
        XCTAssertFalse(String(decoding: try Data(contentsOf: bothURL), as: UTF8.self).contains(attachment.base64))
    }
    func testOldBackupWithSameIDRevokesSourceAndCacheEpochButKeepsPinnedSession() async throws {
        let disk = try ReadiumUnit4Support.disk(self), book = try commit(try await imported(), to: disk)
        let store = PublicationStore(disk: disk), pin = try await store.pin(store.prepare(book))
        let epoch = try disk.publicationCacheEpoch(book.id)
        let row = ShelfEntry(book: book)
        let archive = ICloudArchive(owner: "old", books: [.init(packet: .init(book: book, progress: .init()), bookmarks: [])])
        _ = try await disk.restore(archive, owner: disk.root.lastPathComponent, entries: [row])
        let restored = try disk.read(book.id)
        XCTAssertNil(restored.epubSource); XCTAssertNil(try disk.sourceURL(for: restored))
        XCTAssertNotEqual(try disk.publicationCacheEpoch(book.id), epoch)
        XCTAssertTrue(FileManager.default.fileExists(atPath: pin.url.path))
        let derived = try await store.prepare(restored)
        XCTAssertTrue(derived.revision.hasPrefix("legacy-"))
        try await store.clearCache()
        XCTAssertTrue(FileManager.default.fileExists(atPath: pin.url.path))
        await store.release(pin)
    }
    func testCorruptMissingWrongTypeAndUnreadableAttachmentsFallBackWithoutRejectingBook() async throws {
        let source = try await imported(), valid = EPUBBackupAttachment(data: try Data(contentsOf: XCTUnwrap(source.source).url))
        var badHash = valid; badHash.sha256 = String(repeating: "0", count: 64)
        var badBase64 = valid; badBase64.base64 = "!invalid!"
        for attachment in [nil, badHash, badBase64, EPUBBackupAttachment(data: Data("not epub".utf8))] {
            let result = try await BookImporter.restored(.init(book: source.book, progress: .init(), epubAttachment: attachment))
            XCTAssertNil(result.source); XCTAssertNil(result.book.epubSource)
            XCTAssertEqual(result.book.chapters, source.book.chapters)
        }
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Integrity.encoder().encode(BackupPacket(book: source.book, progress: .init()))) as? [String: Any])
        json["epubAttachment"] = ["base64": 123, "sha256": false]
        let decoded = try JSONDecoder().decode(BackupPacket.self, from: JSONSerialization.data(withJSONObject: json))
        let result = try await BookImporter.restored(decoded)
        XCTAssertNil(result.source)
    }
    func testSameIDArchiveReplacementUsesNewBytesAndInvalidatesStoredRevision() async throws {
        let disk = try ReadiumUnit4Support.disk(self), old = try commit(try await imported("original"), to: disk)
        let epoch = try disk.publicationCacheEpoch(old.id), next = try await imported()
        let model = try ReadiumUnit4Support.model(self, disk)
        await model.migrateLocators(old.id)
        let oldGeneration = model.publicationGeneration[old.id]
        let oldLocator = try XCTUnwrap(model.entries.first?.progress.locator)
        let priorRows = try await model.beginLibraryRestore()
        var book = next.book; book.fields["id"] = .string(old.id)
        let attachment = EPUBBackupAttachment(data: try Data(contentsOf: XCTUnwrap(next.source).url))
        var progress = ReadingProgress(chapter: 0, position: 1)
        progress.publicationRevision = "old-revision"
        let archive = ICloudArchive(owner: "backup", books: [.init(packet: .init(book: book, progress: progress), bookmarks: [], epubAttachment: attachment)])
        let rows = try await disk.restore(archive, owner: disk.root.lastPathComponent, entries: priorRows)
        model.endLibraryRestore(rows)
        model.saveProgress(old.id, chapter: 0, position: 0, locator: oldLocator, revision: "old-revision", generation: oldGeneration)
        XCTAssertEqual(model.entries.first?.progress.position, 1, "Revoked reader callbacks cannot overwrite restored progress")
        let stored = try disk.read(old.id)
        XCTAssertNotEqual(stored.epubSource?.sha256, old.epubSource?.sha256)
        XCTAssertEqual(stored.epubSource?.sha256, attachment.sha256)
        XCTAssertNotEqual(try disk.publicationCacheEpoch(old.id), epoch)
        XCTAssertNil(rows.first?.progress.publicationRevision)
    }
    func testStorageSeparatesOriginalsAndCacheAndCleanupPreservesSourceAndPins() async throws {
        let disk = try ReadiumUnit4Support.disk(self), book = try commit(try await imported(), to: disk)
        let store = PublicationStore(disk: disk, cacheBase: try LocatorTestSupport.temporary(self))
        let prepared = try await store.prepare(book), pin = try await store.pin(prepared)
        let usage = StorageUsage.scan(libraryRoot: disk.root, derivedRoot: await store.cacheRoot)
        XCTAssertGreaterThan(try XCTUnwrap(usage.first { $0.kind == .originals }).bytes, 0)
        XCTAssertFalse(StorageUsage.Kind.originals.clearable)
        let bytes = try Data(contentsOf: XCTUnwrap(disk.sourceURL(for: book)))
        // Simulate a new Store after restore while an old reader still retains its pin.
        let replacementStore = PublicationStore(disk: disk, cacheBase: await store.cacheRoot.deletingLastPathComponent().deletingLastPathComponent())
        try await replacementStore.clearCache()
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(disk.sourceURL(for: book))), bytes)
        XCTAssertEqual(try Data(contentsOf: pin.url), bytes)
        await store.release(pin)
    }
}
