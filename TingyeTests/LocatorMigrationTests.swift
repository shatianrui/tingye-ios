import XCTest
import ReadiumShared
@testable import Tingye

final class LocatorKeyValueStore: ProgressKeyValueStore {
    var values: [String: Any] = [:]
    func dictionary(forKey key: String) -> [String: Any]? { values[key] as? [String: Any] }
    func set(_ value: Any?, forKey key: String) { values[key] = value }
    func removeObject(forKey key: String) { values[key] = nil }
    var dictionaryRepresentation: [String: Any] { values }
    func synchronize() -> Bool { true }
}

@MainActor
final class LocatorMigrationTests: XCTestCase {
    func testBothCatalogGenerationsMigrateAllFourKindsAndAreIdempotent() async throws {
        let book = try JSONDecoder().decode(Book.self, from: LocatorTestSupport.fixture("locator-book.json"))
        let bridge = try await LocatorTestSupport.bridge(book, self)
        let migration = LocatorMigration()
        for version in [141, 142] {
            let entry = try XCTUnwrap(JSONDecoder().decode([ShelfEntry].self, from: LocatorTestSupport.fixture("catalog-\(version).json")).first)
            let (next, receipt) = try await migration.convert(entry, using: bridge)
            XCTAssertEqual(receipt.references.count, 4)
            XCTAssertTrue(receipt.references.values.allSatisfy { $0 == .exact })
            XCTAssertNotNil(next.progress.locator); XCTAssertNotNil(next.listeningProgress?.locator)
            XCTAssertNotNil(next.bookmarks[0].locator); XCTAssertNotNil(next.notes[0].locator)
            XCTAssertEqual(next.progress.chapter, entry.progress.chapter); XCTAssertEqual(next.progress.position, entry.progress.position)
            XCTAssertEqual(next.progress.updatedAt, entry.progress.updatedAt); XCTAssertEqual(next.progress.anchor?.quote, "山中有一页。")
            XCTAssertEqual(next.listeningProgress?.position, entry.listeningProgress?.position)
            XCTAssertEqual(next.notes[0].id, entry.notes[0].id); XCTAssertEqual(next.notes[0].date, entry.notes[0].date)
            XCTAssertEqual(next.notes[0].note, entry.notes[0].note); XCTAssertEqual(next.notes[0].text, entry.notes[0].text)
            XCTAssertEqual(next.notes[0].anchor?.quote, "山中有一页。"); XCTAssertEqual(next.notes[0].color, "green")
            let (again, _) = try await migration.convert(next, using: bridge)
            XCTAssertEqual(try LocatorMigration.token(again), try LocatorMigration.token(next))
            migration.committed(receipt)
            XCTAssertEqual(migration.states[entry.id], .completed(exact: 4, relocated: 0, approximate: 0, unresolved: 0))
        }
    }
    func testUnresolvedHighlightKeepsEveryOriginalByteOfBusinessData() async throws {
        let book = LocatorTestSupport.book(["实际原文。"])
        let bridge = try await LocatorTestSupport.bridge(book, self)
        var entry = ShelfEntry(book: book)
        entry.highlights = [.init(chapter: 9, start: 90, end: 91, text: "已经删除的原文。第二句。", anchor: .init(quote: "已经删除的原文。"), color: "green", style: "wavy", note: "不能丢")]
        let before = try Integrity.encoder().encode(entry.notes)
        let (next, receipt) = try await LocatorMigration().convert(entry, using: bridge)
        XCTAssertEqual(try Integrity.encoder().encode(next.notes), before)
        XCTAssertEqual(receipt.references["highlight:\(entry.notes[0].id)"], .unresolved)
        let batch = try await ReadiumAnnotations.decorations(next.notes, bridge: bridge, mode: "none")
        XCTAssertTrue(batch.decorations.isEmpty); XCTAssertEqual(batch.unresolved.count, 1)
    }
    func testCancelledConversionCanRunAgainAndDoesNotTouchCatalog() async throws {
        let book = LocatorTestSupport.book(format: "TXT")
        var entry = ShelfEntry(book: book, progress: .init(chapter: 0, position: 1))
        entry.highlights = (0..<50).map { _ in Highlight(chapter: 0, start: 1, end: 1, text: "重复。") }
        let bridge = try LocatorBridge(book: book), migration = LocatorMigration()
        let original = try LocatorMigration.token(entry)
        let task = Task { try await migration.convert(entry, using: bridge) }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancellation must abort the book transaction") } catch is CancellationError { }
        XCTAssertEqual(try LocatorMigration.token(entry), original)
        let (next, receipt) = try await migration.convert(entry, using: bridge)
        XCTAssertNotNil(next.progress.locator); XCTAssertEqual(receipt.references.count, 51)
    }
    func testRevisionInvalidationPreservesReferencesAndMigratesAgain() async throws {
        let old = LocatorTestSupport.book(["第一句。目标句。"], format: "TXT")
        let bridge = try LocatorBridge(book: old), migration = LocatorMigration()
        var entry = ShelfEntry(book: old, progress: .init(chapter: 0, position: 1, anchor: .init(quote: "目标句。")))
        entry.bookmarks = [.init(chapter: 0, position: 1, excerpt: "目标句。", anchor: .init(quote: "目标句。"))]
        let (migrated, _) = try await migration.convert(entry, using: bridge)
        XCTAssertEqual(migrated.progress.anchor, TextAnchor(quote: "目标句。", before: "第一句。", after: nil))
        let invalid = LocatorMigration.invalidated(migrated)
        XCTAssertNil(invalid.progress.publicationRevision); XCTAssertNotNil(invalid.progress.locator)
        XCTAssertEqual(invalid.progress.anchor, migrated.progress.anchor)
        let changed = LocatorTestSupport.book(["新增句。第一句。目标句。"], format: "TXT")
        let nextBridge = try LocatorBridge(book: changed)
        let (next, _) = try await migration.convert(invalid, using: nextBridge)
        XCTAssertEqual(next.progress.publicationRevision, nextBridge.revision)
        XCTAssertNotEqual(next.progress.publicationRevision, migrated.progress.publicationRevision)
        XCTAssertEqual(next.progress.position, 2, "Precise conversions update the retained compatibility fields")
        XCTAssertEqual(next.progress.anchor, TextAnchor(quote: "目标句。", before: "新增句。第一句。", after: nil))
        let location = try XCTUnwrap(StoredLocator.readium(next.progress.locator))
        let restored = try await nextBridge.reverse(location)
        XCTAssertEqual(restored.target.position, 2)
    }
    func testAtomicAppMigrationCreatesSnapshotAndCanBeRetriedAfterFailure() async throws {
        let base = try LocatorTestSupport.temporary(self)
        let disk = try LibraryDisk(owner: "locator-test", base: base)
        let book = LocatorTestSupport.book(format: "TXT")
        let entry = ShelfEntry(book: book, progress: .init(chapter: 0, position: 1))
        try disk.write(book); try disk.saveCatalog([entry])
        let suite = "locator." + UUID().uuidString, defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: ProgressSync.enabledKey)
        let model = AppModel(disk: disk, progressSync: ProgressSync(store: LocatorKeyValueStore(), defaults: defaults, account: { false }))
        defer { model.cancelAllLocatorMigrations() }
        await model.migrateLocators(book.id)
        XCTAssertNotNil(try disk.catalog()[0].progress.locator)
        let snapshot = disk.root.appendingPathComponent("LocatorMigration/catalog-before-v1.json")
        let old = try JSONDecoder().decode([ShelfEntry].self, from: Data(contentsOf: snapshot))
        XCTAssertNil(old[0].progress.locator)
        let committed = try Data(contentsOf: disk.root.appendingPathComponent("catalog.json"))
        let bookURL = try disk.file(book.id), backup = try Data(contentsOf: bookURL)
        try Data("bad json".utf8).write(to: bookURL)
        await model.migrateLocators(book.id)
        if case .failed(_)? = model.locatorMigration.states[book.id] {} else { XCTFail("Failed book must have a retryable state") }
        XCTAssertEqual(try Data(contentsOf: disk.root.appendingPathComponent("catalog.json")), committed)
        try backup.write(to: bookURL)
        await model.migrateLocators(book.id)
        XCTAssertNotNil(model.locatorMigration.receipts[book.id])
    }
    func testRepairSameIDRevokesOldLocatorAndRelocatesOnlyOnPreciseConversion() async throws {
        let base = try LocatorTestSupport.temporary(self), disk = try LibraryDisk(owner: "repair-locators", base: base)
        let old = LocatorTestSupport.book(["旧章。", "目标句。后句。"])
        let oldBridge = try await LocatorTestSupport.bridge(old, self)
        var entry = ShelfEntry(book: old, progress: .init(chapter: 1, position: 0, anchor: .init(quote: "目标句。")))
        entry.bookmarks = [.init(chapter: 1, position: 0, excerpt: "目标句。", anchor: .init(quote: "目标句。"))]
        entry.highlights = [.init(chapter: 1, start: 0, end: 1, text: "目标句。后句。", anchor: .init(quote: "目标句。"), note: "旧笔记")]
        let (migrated, _) = try await LocatorMigration().convert(entry, using: oldBridge)
        try disk.write(old); try disk.saveCatalog([migrated])
        let suite = "repair-locator." + UUID().uuidString, defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: ProgressSync.enabledKey)
        let model = AppModel(disk: disk, progressSync: ProgressSync(store: LocatorKeyValueStore(), defaults: defaults, account: { false }))
        defer { model.cancelAllLocatorMigrations() }
        let replacement = LocatorTestSupport.book(["目标句。后句。", "新增章。", "旧章。"])
        let built = try await LegacyEPUBBuilder().build(replacement, to: base.appendingPathComponent("replacement"))
        try await model.repair(old.id, from: built.url)
        XCTAssertNil(model.entries[0].progress.publicationRevision)
        XCTAssertEqual(model.entries[0].progress.chapter, 1)
        XCTAssertEqual(model.entries[0].notes[0].id, migrated.notes[0].id)
        let protected = model.entries[0].progress
        model.saveProgress(old.id, chapter: 0, position: 0, locator: migrated.progress.locator,
                           revision: migrated.progress.publicationRevision, generation: nil)
        XCTAssertEqual(model.entries[0].progress, protected, "A replaced reader session cannot overwrite the repaired entry")
        await model.migrateLocators(old.id)
        let next = try XCTUnwrap(model.entries.first { $0.id == old.id })
        XCTAssertNotEqual(next.progress.publicationRevision, migrated.progress.publicationRevision)
        XCTAssertEqual(next.progress.chapter, 0); XCTAssertEqual(next.notes[0].note, "旧笔记")
        XCTAssertEqual(next.progress.locator?.object?["locations"]?.object?["tingyeChapter"]?.int, 0)
    }
    func testCatalogCommitFailureLeavesInMemoryReferencesUntouched() async throws {
        let base = try LocatorTestSupport.temporary(self), disk = try LibraryDisk(owner: "failure-locators", base: base)
        let book = LocatorTestSupport.book(format: "TXT"), row = ShelfEntry(book: LocatorTestSupport.book(format: "TXT"))
        try disk.write(book); try disk.saveCatalog([row]); try disk.snapshotForLocatorMigration(row)
        let suite = "failure-locator." + UUID().uuidString, defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(disk: disk, progressSync: ProgressSync(store: LocatorKeyValueStore(), defaults: defaults, account: { false }))
        defer { model.cancelAllLocatorMigrations() }
        let catalog = disk.root.appendingPathComponent("catalog.json"), saved = disk.root.appendingPathComponent("catalog.saved")
        try FileManager.default.moveItem(at: catalog, to: saved)
        try FileManager.default.createDirectory(at: catalog, withIntermediateDirectories: false)
        await model.migrateLocators(book.id)
        XCTAssertNil(model.entries[0].progress.locator)
        if case .failed(_)? = model.locatorMigration.states[book.id] {} else { XCTFail("Expected commit failure") }
        XCTAssertEqual(try JSONDecoder().decode([ShelfEntry].self, from: Data(contentsOf: saved))[0].progress, row.progress)
        try FileManager.default.removeItem(at: catalog); try FileManager.default.moveItem(at: saved, to: catalog)
        await model.migrateLocators(book.id)
        XCTAssertNotNil(model.entries[0].progress.locator)
    }
    func testKVSCoexistsWithOldFieldsAndSameSentenceLocatorUpdates() async throws {
        let book = LocatorTestSupport.book(["同一句内有多个位置。"], format: "TXT")
        let bridge = try LocatorBridge(book: book)
        let result = try await bridge.resolve(.init(chapter: 0, position: 0))
        let store = LocatorKeyValueStore(), suite = "locator-sync." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
        let sync = ProgressSync(store: store, defaults: defaults, account: { true })
        var entry = ShelfEntry(book: book, progress: .init(chapter: 0, position: 0, updatedAt: 100,
                            anchor: .init(quote: "同一句内有多个位置。"), locator: result.locator, locatorVersion: 1, publicationRevision: bridge.revision))
        XCTAssertTrue(sync.push(entry))
        for key in [ProgressSync.key(entry), ProgressSync.legacyKey(entry)] {
            let payload = try XCTUnwrap(store.dictionary(forKey: key))
            XCTAssertEqual(payload["c"] as? Int, 0); XCTAssertEqual(payload["p"] as? Int, 0); XCTAssertEqual(payload["t"] as? Double, 100)
            XCTAssertNotNil(payload["locator"]); XCTAssertNotNil(payload["anchor"]); XCTAssertNotNil(payload["revision"])
        }
        var raw = try XCTUnwrap(result.locator?.object), locations = try XCTUnwrap(result.locator?.object?["locations"]?.object)
        locations["tingyeRange"] = LocatorBridge.rangeJSON(NSRange(location: 2, length: 2)); raw["locations"] = .object(locations)
        let changed = try XCTUnwrap(sync.update(entry, chapter: 0, position: 0, locator: .object(raw), revision: bridge.revision, now: 1))
        XCTAssertGreaterThan(changed.updatedAt, 100)
        entry.progress = changed; XCTAssertTrue(sync.push(entry))
        var old = entry; old.progress = .init(chapter: 0, position: 0, updatedAt: 100)
        XCTAssertEqual(sync.newer(than: old)?.locator, changed.locator)
        XCTAssertEqual(sync.merge([old], protected: [book.id]).kept, 1)
        store.values = [ProgressSync.legacyKey(old): ["c": 0, "p": 0, "t": 800.0]]
        XCTAssertNil(sync.newer(than: entry), "An old-client same-sentence echo must not erase precise location")
    }
    func testKVSBoundedFieldsIgnoreInvalidLocatorWithoutLosingProgress() {
        let store = LocatorKeyValueStore(), suite = "locator-payload." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let sync = ProgressSync(store: store, defaults: defaults, account: { true })
        let entry = ShelfEntry(book: LocatorTestSupport.book(format: "TXT"))
        store.values[ProgressSync.key(entry)] = ["c": 0, "p": 1, "t": 500.0, "locator": "{\"href\":7}", "anchor": "bad"]
        let progress = sync.newer(than: entry)
        XCTAssertEqual(progress?.position, 1); XCTAssertNil(progress?.locator); XCTAssertNil(progress?.anchor)
        var huge = ReadingProgress(chapter: 0, position: 1, updatedAt: 1)
        huge.locator = .object(["href": .string("tingye://book/b/chapter/0"), "type": .string("text/plain"), "text": .object(["highlight": .string(String(repeating: "字", count: 20_000))])])
        XCTAssertNil(ProgressSync.payload(huge)["locator"])
        XCTAssertEqual(ProgressSync.payload(huge)["p"] as? Int, 1)
    }
    func testArchiveAndPacketRetainOptionalLocatorFieldsInTheirExistingScopes() async throws {
        let book = LocatorTestSupport.book(format: "TXT"), bridge = try LocatorBridge(book: LocatorTestSupport.book(format: "TXT"))
        let result = try await bridge.resolve(.init(chapter: 0, position: 1))
        let progress = ReadingProgress(chapter: 0, position: 1, updatedAt: 1, locator: result.locator, locatorVersion: 1, publicationRevision: bridge.revision)
        let mark = Bookmark(chapter: 0, position: 1, excerpt: "重复。", locator: result.locator, locatorVersion: 1, publicationRevision: bridge.revision)
        let note = Highlight(chapter: 0, start: 1, end: 1, text: "重复。", locator: result.locator, locatorVersion: 1, publicationRevision: bridge.revision, note: "笔记")
        let archive = ICloudArchive(owner: "owner", books: [.init(packet: .init(book: book, progress: progress), bookmarks: [mark], highlights: [note], listeningProgress: progress)])
        let decoded = try JSONDecoder().decode(ICloudArchive.self, from: JSONEncoder().encode(archive)).validated(owner: "owner")
        XCTAssertEqual(decoded.books[0].packet.progress.locator, result.locator)
        XCTAssertEqual(decoded.books[0].bookmarks[0].locator, result.locator)
        XCTAssertEqual(decoded.books[0].highlights?[0].note, "笔记")
        XCTAssertEqual(decoded.books[0].listeningProgress?.locator, result.locator)
    }
}
