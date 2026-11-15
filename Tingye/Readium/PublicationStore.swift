import Foundation

/// One store per library session. This unit does not attach it to any UI/router.
actor PublicationStore {
    struct Prepared: Sendable {
        let url: URL
        let revision: String
        let map: PublicationMap?
        let report: LegacyEPUBBuilder.Report?
    }
    struct SessionFile: Sendable { let token: UUID; let url: URL }
    private struct Job { let token: UUID; let task: Task<LegacyEPUBBuilder.Result, Error> }
    private let disk: LibraryDisk
    let cacheRoot: URL
    private var jobs: [String: Job] = [:]
    private var pins: [UUID: URL] = [:]
    private var epochs: [String: UUID] = [:]

    init(disk: LibraryDisk, cacheBase: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]) {
        self.disk = disk
        cacheRoot = cacheBase.appendingPathComponent("TingyeReadium").appendingPathComponent(disk.root.lastPathComponent)
    }
    func prepare(_ book: Book) async throws -> Prepared {
        try Task.checkCancellation()
        guard book.format.uppercased() == "EPUB" else { throw ReaderError.message("只有 EPUB 可以准备 Publication。") }
        if let source = try disk.sourceURL(for: book), let metadata = book.epubSource {
            return Prepared(url: source, revision: "source-" + metadata.sha256, map: nil, report: nil)
        }
        let hash = try PublicationMap.contentHash(for: book)
        let diskEpoch = try disk.publicationCacheEpoch(book.id)
        let key = "\(book.id)/\(hash)-v\(LegacyEPUBBuilder.generatorVersion)-\(diskEpoch)"
        let destination = cacheRoot.appendingPathComponent(key, isDirectory: true)
        let epoch = epochs[book.id] ?? UUID(); epochs[book.id] = epoch
        let job: Job
        if let existing = jobs[key] { job = existing }
        else {
            job = Job(token: UUID(), task: Task.detached(priority: .userInitiated) {
                if let cached = try LegacyEPUBBuilder.cached(at: destination, contentHash: hash) { return cached }
                return try await LegacyEPUBBuilder().build(book, to: destination)
            })
            jobs[key] = job
        }
        defer { if jobs[key]?.token == job.token { jobs[key] = nil } }
        let built = try await job.task.value
        try Task.checkCancellation()
        guard epochs[book.id] == epoch, try disk.publicationCacheEpoch(book.id) == diskEpoch else { throw CancellationError() }
        return Prepared(url: built.url, revision: built.map.publicationRevision, map: built.map, report: built.report)
    }
    /// Repair/replacement invalidates in-flight snapshots. Content-addressed keys already prevent
    /// selecting an old artifact; callers in unit 2 must invalidate their retained session too.
    func invalidate(_ id: String) throws {
        guard Book.validID(id) else { throw ReaderError.message("书籍标识无效。") }
        epochs[id] = UUID()
        for key in Array(jobs.keys) where key.hasPrefix(id + "/") { jobs.removeValue(forKey: key)?.task.cancel() }
        try clearCache(bookID: id)
    }
    /// Session seam for unit 2. A private hard link/copy also keeps originals alive across repair/delete.
    func pin(_ prepared: Prepared) throws -> SessionFile {
        let token = UUID(), directory = cacheRoot.appendingPathComponent(".Sessions")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(token.uuidString + ".epub")
        do { try FileManager.default.linkItem(at: prepared.url, to: url) }
        catch { try FileManager.default.copyItem(at: prepared.url, to: url) }
        if prepared.revision.hasPrefix("source-"),
           (try? PublicationDigest.file(url)) != String(prepared.revision.dropFirst("source-".count)) {
            try? FileManager.default.removeItem(at: url)
            throw ReaderError.message("EPUB 原文件已替换，请重新准备 Publication。")
        }
        pins[token] = url
        return SessionFile(token: token, url: url)
    }
    func release(_ file: SessionFile) {
        if let url = pins.removeValue(forKey: file.token) { try? FileManager.default.removeItem(at: url) }
    }
    func clearCache(bookID: String? = nil) throws {
        let fm = FileManager.default
        if let bookID {
            guard Book.validID(bookID) else { throw ReaderError.message("书籍标识无效。") }
            // A running generator owns its staging directory until it finishes/cancels.
            guard !jobs.keys.contains(where: { $0.hasPrefix(bookID + "/") }) else { return }
            let directory = cacheRoot.appendingPathComponent(bookID)
            if fm.fileExists(atPath: directory.path) { try fm.removeItem(at: directory) }
        } else if fm.fileExists(atPath: cacheRoot.path) {
            for directory in try fm.contentsOfDirectory(at: cacheRoot, includingPropertiesForKeys: nil) {
                if directory.lastPathComponent == ".Sessions" {
                    for file in try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) where !pins.values.contains(file) {
                        try fm.removeItem(at: file)
                    }
                } else if !jobs.keys.contains(where: { $0.hasPrefix(directory.lastPathComponent + "/") }) {
                    try fm.removeItem(at: directory)
                }
            }
        }
    }
}
