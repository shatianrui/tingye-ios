import Foundation
import Combine

/// Diagnostics are per reference, with no excerpts or note contents in the receipt.
struct LocatorMigrationReceipt: Codable, Sendable {
    let bookID: String
    let revision: String
    let version: Int
    let references: [String: LocatorResolution]
    let completedAt: Date
}

@MainActor
final class LocatorMigration: ObservableObject {
    enum State: Equatable {
        case waiting, running, cancelled, failed(String), completed(exact: Int, relocated: Int, approximate: Int, unresolved: Int)
    }
    @Published private(set) var states: [String: State] = [:]
    private(set) var receipts: [String: LocatorMigrationReceipt] = [:]
    func set(_ state: State, for id: String) { states[id] = state }
    func reset() { states = [:]; receipts = [:] }
    /// Equality token excludes shelf metadata, includes all four reference arrays and their business data.
    static func token(_ entry: ShelfEntry) throws -> Data {
        struct References: Encodable {
            let progress: ReadingProgress
            let listening: ReadingProgress?
            let bookmarks: [Bookmark]
            let highlights: [Highlight]?
        }
        return try Integrity.encoder().encode(References(progress: entry.progress, listening: entry.listeningProgress,
                                                         bookmarks: entry.bookmarks, highlights: entry.highlights))
    }
    nonisolated static func invalidated(_ entry: ShelfEntry) -> ShelfEntry {
        // Retain old locator/anchor for relocation, but revoke its same-revision authority.
        var next = entry
        next.progress.publicationRevision = nil
        next.listeningProgress?.publicationRevision = nil
        for index in next.bookmarks.indices { next.bookmarks[index].publicationRevision = nil }
        if let highlights = next.highlights {
            next.highlights = highlights.map { item in var item = item; item.publicationRevision = nil; return item }
        }
        return next
    }
    func convert(_ entry: ShelfEntry, using bridge: LocatorBridge) async throws -> (ShelfEntry, LocatorMigrationReceipt) {
        var next = entry, statuses: [String: LocatorResolution] = [:]
        func convert(_ value: ReadingProgress, key: String) async throws -> ReadingProgress {
            try Task.checkCancellation()
            let result = try await bridge.resolve(.init(value)); statuses[key] = result.status
            guard result.status != .unresolved, let locator = result.locator else { return value }
            var updated = value
            updated.locator = locator; updated.locatorVersion = LocatorBridge.version; updated.publicationRevision = bridge.revision
            if result.precise {
                updated.chapter = result.target.chapter; updated.position = result.target.position
                updated.anchor = result.target.anchor ?? value.anchor
            }
            // Clocks are unchanged here; approximate results never rewrite compatibility coordinates.
            return updated
        }
        next.progress = try await convert(entry.progress, key: "reading")
        if let listening = entry.listeningProgress { next.listeningProgress = try await convert(listening, key: "listening") }
        for index in entry.bookmarks.indices {
            try Task.checkCancellation()
            let mark = entry.bookmarks[index], key = "bookmark:\(mark.id)"
            let result = try await bridge.resolve(.init(mark)); statuses[key] = result.status
            if result.precise, let locator = result.locator {
                next.bookmarks[index].locator = locator; next.bookmarks[index].locatorVersion = LocatorBridge.version
                next.bookmarks[index].publicationRevision = bridge.revision
                next.bookmarks[index].chapter = result.target.chapter; next.bookmarks[index].position = result.target.position
                next.bookmarks[index].anchor = result.target.anchor ?? mark.anchor
            }
        }
        for index in (entry.highlights ?? []).indices {
            try Task.checkCancellation()
            guard let item = entry.highlights?[index] else { continue }
            let result = try await bridge.resolve(.init(item)); statuses["highlight:\(item.id)"] = result.status
            if result.precise, let locator = result.locator {
                next.highlights?[index].locator = locator; next.highlights?[index].locatorVersion = LocatorBridge.version
                next.highlights?[index].publicationRevision = bridge.revision
                next.highlights?[index].chapter = result.target.chapter; next.highlights?[index].start = result.target.position
                next.highlights?[index].end = result.target.end ?? item.end
                next.highlights?[index].anchor = result.target.anchor ?? item.anchor
            }
        }
        try Task.checkCancellation()
        return (next, LocatorMigrationReceipt(bookID: entry.id, revision: bridge.revision, version: LocatorBridge.version,
                                              references: statuses, completedAt: Date()))
    }
    func committed(_ receipt: LocatorMigrationReceipt) {
        receipts[receipt.bookID] = receipt
        let values = Array(receipt.references.values)
        states[receipt.bookID] = .completed(exact: values.filter { $0 == .exact }.count,
            relocated: values.filter { $0 == .textRelocated }.count, approximate: values.filter { $0 == .approximate }.count,
            unresolved: values.filter { $0 == .unresolved }.count)
    }
}

extension LibraryDisk {
    func snapshotForLocatorMigration(_ entry: ShelfEntry) throws {
        let directory = root.appendingPathComponent("LocatorMigration", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let catalog = directory.appendingPathComponent("catalog-before-v1.json")
        if !FileManager.default.fileExists(atPath: catalog.path) {
            let source = root.appendingPathComponent("catalog.json")
            if FileManager.default.fileExists(atPath: source.path) { try Data(contentsOf: source).write(to: catalog, options: .atomic) }
        }
        let path = directory.appendingPathComponent(entry.id + "-before-v1.json")
        try Integrity.encoder().encode(entry).write(to: path, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    func locatorReceipt(_ id: String) throws -> LocatorMigrationReceipt? {
        guard Book.validID(id) else { return nil }
        let url = root.appendingPathComponent("LocatorMigration/" + id + "-receipt.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(LocatorMigrationReceipt.self, from: Data(contentsOf: url))
    }
    func saveLocatorReceipt(_ receipt: LocatorMigrationReceipt) throws {
        let directory = root.appendingPathComponent("LocatorMigration", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Integrity.encoder().encode(receipt).write(to: directory.appendingPathComponent(receipt.bookID + "-receipt.json"), options: .atomic)
    }
}
