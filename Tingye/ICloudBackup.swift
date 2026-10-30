import Foundation
import SwiftUI
import CryptoKit

/// 跨线程报告"已处理 / 总数"。
typealias ICloudProgress = @Sendable (_ completed: Int, _ total: Int) -> Void

/// An independent archive: existing v2 account backups remain unchanged.
struct ICloudArchive: Codable, Sendable {
    var format = "tingye-icloud"
    var version = 1
    var owner: String
    var createdAt = Date()
    var books: [Item]
    struct Item: Codable, Sendable {
        var packet: BackupPacket
        var bookmarks: [Bookmark]
        /// 本机整理信息（分组、隐藏、划线）。可选：旧备份没有这些字段，旧版本读新备份会忽略它们。
        var group: String?
        var hidden: Bool?
        var highlights: [Highlight]?
        var listeningProgress: ReadingProgress?
        var lastReadAt: Double?
        func validated() throws -> Self {
            let packet = try packet.validated(id: packet.book.id)
            if let listeningProgress {
                guard packet.book.chapters.indices.contains(listeningProgress.chapter), listeningProgress.position >= 0,
                      listeningProgress.updatedAt.isFinite, listeningProgress.updatedAt >= 0 else {
                    throw ReaderError.message("iCloud 备份中的听书位置无效，本机书架未更改。")
                }
            }
            if let lastReadAt, !lastReadAt.isFinite || lastReadAt < 0 {
                throw ReaderError.message("iCloud 备份中的阅读时间无效，本机书架未更改。")
            }
            for mark in bookmarks {
                guard packet.book.chapters.indices.contains(mark.chapter), mark.position >= 0 else {
                    throw ReaderError.message("iCloud 备份中《\(packet.book.title)》的书签无效，本机书架未更改。")
                }
            }
            return self
        }
    }
    /// 只校验格式、账号与目录；逐本校验见 `Item.validated()`。
    func validatedHeader(owner expected: String) throws -> Self {
        guard format == "tingye-icloud", version == 1, owner == expected,
              Set(books.map { $0.packet.book.id }).count == books.count else {
            throw ReaderError.message("iCloud 备份版本、账号或目录无效，本机书架未更改。")
        }
        guard !books.isEmpty else { throw ReaderError.message("该 iCloud 备份不包含书籍，本机书架未更改。") }
        return self
    }
    func validated(owner expected: String, progress: ICloudProgress? = nil) throws -> Self {
        _ = try validatedHeader(owner: expected)
        progress?(0, books.count)
        for (index, item) in books.enumerated() {
            _ = try item.validated()
            progress?(index + 1, books.count)
        }
        return self
    }
}

struct ICloudBackupStore: Sendable {
    static let containerID = "iCloud.com.shatianrui.wereader"
    enum DownloadState: Equatable, Sendable { case ready, downloading, failed(String) }
    enum UploadState: Equatable, Sendable { case notUbiquitous, waiting, uploading, uploaded, failed(String) }
    let root: URL
    init(root: URL) { self.root = root }
    /// Called off the main thread: resolving a ubiquity container can block.
    static func connected() throws -> Self {
        guard let url = FileManager.default.url(forUbiquityContainerIdentifier: containerID) else {
            throw ReaderError.message("iCloud Drive 不可用。请在系统设置中登录 Apple 账号并开启 iCloud Drive；开发安装还需启用 iCloud 签名权限。")
        }
        return Self(root: url.appendingPathComponent("Documents/Backups", isDirectory: true))
    }
    func directory(owner: String) throws -> URL {
        guard Book.validID(owner) else { throw ReaderError.message("备份账号无效。") }
        return root.appendingPathComponent(owner, isDirectory: true)
    }
    func save(_ archive: ICloudArchive) throws -> URL {
        _ = try archive.validated(owner: archive.owner)
        let directory = try directory(owner: archive.owner)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Immutable snapshots avoid overwriting a newer backup made on another device.
        let url = directory.appendingPathComponent("\(Int(archive.createdAt.timeIntervalSince1970 * 1000))-\(UUID().uuidString).json")
        let data = try Integrity.encoder().encode(archive)
        var coordinationError: NSError?, writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: [], error: &coordinationError) { target in
            do { try data.write(to: target, options: .atomic) } catch { writeError = error }
        }
        if let error = coordinationError ?? writeError { throw error }
        return url
    }
    /// 新到旧排序。尚未下载的旧式占位文件（`.名称.json.icloud`）按真实文件名列出。
    func snapshots(owner: String) throws -> [URL] {
        let directory = try directory(owner: owner)
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        var names = Set<String>()
        for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            let name = url.lastPathComponent
            if name.hasPrefix("."), name.hasSuffix(".json.icloud") { names.insert(String(name.dropFirst().dropLast(".icloud".count))) }
            else if url.pathExtension == "json" { names.insert(name) }
        }
        return names.sorted(by: >).map { directory.appendingPathComponent($0) }
    }
    /// Backups 下全部账号目录。新设备可能以 guest 运行，而旧备份在登录账号目录下。
    func snapshotOwners() throws -> [String] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: root.path) else { return [] }
        return try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey])
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true && Book.validID($0.lastPathComponent) }
            .map(\.lastPathComponent)
    }
    /// 全部账号目录中最新的一份快照及其所属账号；快照名以毫秒时间戳开头，可直接按文件名比较新旧。
    func latestSnapshotAcrossOwners() throws -> (owner: String, url: URL)? {
        var best: (owner: String, url: URL)?
        for owner in try snapshotOwners() {
            guard let url = try snapshots(owner: owner).first else { continue }
            if best == nil || url.lastPathComponent > best!.url.lastPathComponent { best = (owner, url) }
        }
        return best
    }
    /// 从全部账号目录的所有快照中移除指定书籍：含该书且还有其他书的快照改写回原文件，只含该书的快照删除。
    /// 未下载的快照先请求 iCloud 下载。返回 (改写数, 删除数)。
    func removeBook(_ bookID: String) async throws -> (rewritten: Int, deleted: Int) {
        var rewritten = 0, deleted = 0
        for owner in try snapshotOwners() {
            for url in try snapshots(owner: owner) {
                var waited = 0
                while true {
                    let state = try downloadState(url, owner: owner, request: waited == 0)
                    if state == .ready { break }
                    if case .failed(let reason) = state { throw ReaderError.message("iCloud 下载备份失败：\(reason)。请检查网络后重试。") }
                    if waited >= 120 { throw ReaderError.message("部分 iCloud 备份尚未下载完成，系统会在后台继续下载，请保持联网后重试。") }
                    try await Task.sleep(for: .seconds(1)); waited += 1
                }
                let archive = try decode(url, owner: owner)
                guard archive.books.contains(where: { $0.packet.book.id == bookID }) else { continue }
                var next = archive
                next.books.removeAll { $0.packet.book.id == bookID }
                if next.books.isEmpty {
                    try FileManager.default.removeItem(at: url)
                    deleted += 1
                } else {
                    let data = try Integrity.encoder().encode(next)
                    var coordinationError: NSError?, writeError: Error?
                    NSFileCoordinator().coordinate(writingItemAt: url, options: [], error: &coordinationError) { target in
                        do { try data.write(to: target, options: .atomic) } catch { writeError = error }
                    }
                    if let error = coordinationError ?? writeError { throw error }
                    rewritten += 1
                }
            }
        }
        return (rewritten, deleted)
    }
    private func checked(_ url: URL, owner: String) throws -> URL {
        guard url.deletingLastPathComponent().standardizedFileURL == (try directory(owner: owner)).standardizedFileURL else {
            throw ReaderError.message("备份路径无效。")
        }
        return url
    }
    /// `request` 为 true 时（每次读取的首次检查）向系统发起下载，忽略上次遗留的下载错误。
    func downloadState(_ url: URL, owner: String, request: Bool) throws -> DownloadState {
        let url = try checked(url, owner: owner), fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else {
            let placeholder = url.deletingLastPathComponent().appendingPathComponent("." + url.lastPathComponent + ".icloud")
            guard fm.fileExists(atPath: placeholder.path) else { throw ReaderError.message("这份 iCloud 备份已被移除，请重新读取。") }
            if request { try fm.startDownloadingUbiquitousItem(at: url) }
            return .downloading
        }
        var fresh = url; fresh.removeAllCachedResourceValues()
        let values = try fresh.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey, .ubiquitousItemIsDownloadingKey, .ubiquitousItemDownloadingErrorKey])
        guard values.isUbiquitousItem == true else { return .ready }
        // 快照不可变，已下载的旧版本与最新版本内容一致。
        if values.ubiquitousItemDownloadingStatus == .current || values.ubiquitousItemDownloadingStatus == .downloaded { return .ready }
        if request { try fm.startDownloadingUbiquitousItem(at: url); return .downloading }
        if let error = values.ubiquitousItemDownloadingError { return .failed(error.localizedDescription) }
        return .downloading
    }
    func uploadState(_ url: URL) throws -> UploadState {
        var fresh = url; fresh.removeAllCachedResourceValues()
        let values = try fresh.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemIsUploadedKey, .ubiquitousItemIsUploadingKey, .ubiquitousItemUploadingErrorKey])
        guard values.isUbiquitousItem == true else { return .notUbiquitous }
        if values.ubiquitousItemIsUploaded == true { return .uploaded }
        if let error = values.ubiquitousItemUploadingError { return .failed(error.localizedDescription) }
        return values.ubiquitousItemIsUploading == true ? .uploading : .waiting
    }
    /// 解码但不逐本校验，便于调用方分步报告校验进度。
    func decode(_ url: URL, owner: String) throws -> ICloudArchive {
        let url = try checked(url, owner: owner)
        guard try downloadState(url, owner: owner, request: false) == .ready else {
            throw ReaderError.message("备份尚未从 iCloud 下载完成，请稍后重试。")
        }
        var coordinationError: NSError?, result: Result<Data, Error>?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { target in
            result = Result { try Data(contentsOf: target) }
        }
        if let error = coordinationError { throw error }
        guard let result else { throw ReaderError.message("无法读取 iCloud 备份。") }
        do { return try JSONDecoder().decode(ICloudArchive.self, from: result.get()).validatedHeader(owner: owner) }
        catch is DecodingError { throw ReaderError.message("iCloud 备份文件无法解析，可能已损坏，本机书架未更改。") }
    }
    func read(_ url: URL, owner: String, progress: ICloudProgress? = nil) throws -> ICloudArchive {
        try decode(url, owner: owner).validated(owner: owner, progress: progress)
    }
}

extension LibraryDisk {
    /// Validate and stage the full merged library before replacing any existing files.
    /// `progress` 在每本书暂存后报告；`willReplace` 在替换本机书库前调用。
    func restore(_ archive: ICloudArchive, owner: String, entries: [ShelfEntry], progress: ICloudProgress? = nil, willReplace: (@Sendable () -> Void)? = nil) throws -> [ShelfEntry] {
        // 存档 owner 是来源账号（可能来自旧账号目录），按存档自身校验；内容还原进当前书库。
        _ = try archive.validated(owner: archive.owner)
        let fm = FileManager.default, parent = root.deletingLastPathComponent()
        let staging = parent.appendingPathComponent("restore-" + UUID().uuidString)
        let rollback = root.appendingPathExtension("restore-backup")
        defer { try? fm.removeItem(at: staging) }
        try fm.copyItem(at: root, to: staging)
        var next = entries
        progress?(0, archive.books.count)
        for (index, item) in archive.books.enumerated() {
            let book = item.packet.book
            var row = ShelfEntry(book: book, progress: item.packet.progress)
            row.bookmarks = item.bookmarks
            row.group = item.group; row.hidden = item.hidden; row.highlights = item.highlights
            row.listeningProgress = item.listeningProgress; row.lastReadAt = item.lastReadAt
            row.hasListened = item.listeningProgress != nil
            if let i = next.firstIndex(where: { $0.id == book.id }) { row.addedAt = next[i].addedAt }
            if let i = next.firstIndex(where: { $0.id == book.id }) {
                row.cloudRevision = next[i].cloudRevision; row.backupAt = next[i].backupAt
                next[i] = row
            } else { next.append(row) }
            try Integrity.encoder().encode(book).write(to: staging.appendingPathComponent("Books/\(book.id).json"), options: .atomic)
            // 同标识书籍的资源、封面和分类也可能变化，暂存目录不能沿用旧索引。
            for ext in ["json", "jpg"] {
                let indexURL = staging.appendingPathComponent("Index/\(book.id).\(ext)")
                if fm.fileExists(atPath: indexURL.path) { try fm.removeItem(at: indexURL) }
            }
            progress?(index + 1, archive.books.count)
        }
        try Integrity.encoder().encode(next).write(to: staging.appendingPathComponent("catalog.json"), options: .atomic)
        willReplace?()
        if fm.fileExists(atPath: rollback.path) { try fm.removeItem(at: rollback) }
        try fm.moveItem(at: root, to: rollback)
        do { try fm.moveItem(at: staging, to: root) }
        catch { try fm.moveItem(at: rollback, to: root); throw error }
        try? fm.removeItem(at: rollback)
        return next
    }
}

/// 手动 iCloud 备份 / 还原的阶段与真实计数。总数为 0 的阶段无法预估，界面显示不确定进度。
struct ICloudTransfer: Equatable {
    enum Kind: Equatable { case backup, restore }
    enum Stage: Equatable {
        case connecting, readingLocal, writing
        case finding, downloading, reading, validating, confirming
        case restoring, replacing, reloading
        case done, failed, cancelled
    }
    let id = UUID()
    var kind: Kind
    var stage: Stage
    /// 失败或取消时所处的阶段。
    var lastActive: Stage
    var completed = 0
    var total = 0
    var detail = ""
    init(kind: Kind, stage: Stage, detail: String = "") { self.kind = kind; self.stage = stage; lastActive = stage; self.detail = detail }

    var steps: [Stage] {
        switch kind {
        case .backup: return [.connecting, .readingLocal, .writing]
        case .restore: return [.restoring, .replacing, .reloading].contains(lastActive)
            ? [.restoring, .replacing, .reloading] : [.connecting, .finding, .downloading, .reading, .validating]
        }
    }
    var finished: Bool { [.done, .failed, .cancelled].contains(stage) }
    var running: Bool { !finished && stage != .confirming }
    var cancellable: Bool { [.connecting, .readingLocal, .finding, .downloading, .reading, .validating].contains(stage) }
    var countable: Bool { total > 0 && [.readingLocal, .validating, .restoring].contains(stage) }
    var fraction: Double? { countable ? min(1, max(0, Double(completed) / Double(total))) : nil }
    var countText: String? { countable ? "\(completed)/\(total) 本" : nil }
    var activity: String { Self.title(stage, kind) + (countText.map { " " + $0 } ?? "") }
    var title: String { Self.title(stage, kind) }
    static func title(_ stage: Stage, _ kind: Kind) -> String {
        switch stage {
        case .connecting: return "连接 iCloud Drive"
        case .readingLocal: return "读取本机书籍"
        case .writing: return "写入 iCloud Drive"
        case .finding: return "查找最新备份"
        case .downloading: return "等待 iCloud 下载"
        case .reading: return "读取备份"
        case .validating: return "校验备份"
        case .confirming: return "等待确认还原"
        case .restoring: return "还原书籍"
        case .replacing: return "替换本机书库"
        case .reloading: return "重新载入书架"
        case .done: return kind == .backup ? "备份已写入" : "还原完成"
        case .failed: return kind == .backup ? "备份失败" : "还原失败"
        case .cancelled: return "已取消"
        }
    }
    mutating func advance(_ next: Stage, completed: Int = 0, total: Int = 0, detail: String? = nil) {
        if ![.done, .failed, .cancelled].contains(next) { lastActive = next }
        stage = next; self.completed = completed; self.total = total
        if let detail { self.detail = detail }
    }
}

/// 备份文件写入后由系统上传；这里只如实反映系统报告的上传状态。
struct ICloudUploadStatus: Equatable {
    enum State: Equatable { case checking, waiting, uploading, uploaded, notUbiquitous, failed(String) }
    var url: URL
    var state: State = .checking
    var checkedAt: Date?
    /// 自动查询已停止（超时）；可手动刷新。
    var paused = false
    var text: String {
        switch state {
        case .checking: return "正在查询上传状态…"
        case .waiting: return paused ? "已写入本机 iCloud Drive 文件夹，系统尚未开始上传。可稍后刷新查看。" : "已写入本机 iCloud Drive 文件夹，等待系统开始上传…"
        case .uploading: return paused ? "系统仍在上传，可稍后刷新查看。" : "系统正在上传到 iCloud…"
        case .uploaded: return "iCloud 已确认上传完成。其他设备需等其 iCloud Drive 同步后才能看到这份备份。"
        case .notUbiquitous: return "该文件不在 iCloud 中，未上传。"
        case .failed(let reason): return "上传出错：\(reason)。系统会自动重试；请检查网络与 iCloud 存储空间。"
        }
    }
    var settled: Bool { switch state { case .uploaded, .notUbiquitous, .failed: return true; default: return false } }
}

/// 后台执行期间请求系统宽限时间，切到后台时尽量完成当前步骤。
@MainActor
private final class BackgroundAssertion {
    private var id = UIBackgroundTaskIdentifier.invalid
    init(_ name: String) {
        id = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            MainActor.assumeIsolated { self?.end() }
        }
    }
    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id); id = .invalid
    }
}

extension AppModel {
    static let downloadWaitSeconds = 120

    private func step(_ id: UUID, _ stage: ICloudTransfer.Stage, completed: Int = 0, total: Int = 0, detail: String? = nil) {
        guard var value = icloud, value.id == id, !value.finished else { return }
        value.advance(stage, completed: completed, total: total, detail: detail)
        icloud = value; activity = value.activity
    }
    /// 后台线程的计数回调按顺序回到主线程，且只更新同一次、仍在进行的操作。
    private func reporter(_ id: UUID, _ stage: ICloudTransfer.Stage, detail: String? = nil) -> ICloudProgress {
        { [weak self] completed, total in
            DispatchQueue.main.async { MainActor.assumeIsolated {
                guard let self, self.icloud?.id == id, self.icloud?.stage == stage else { return }
                self.step(id, stage, completed: completed, total: total, detail: detail)
            } }
        }
    }
    /// 运行一次手动 iCloud 操作。`work` 返回完成说明；返回 nil 表示停在等待确认。
    private func runICloud(_ kind: ICloudTransfer.Kind, _ first: ICloudTransfer.Stage, detail: String = "", _ work: @escaping @MainActor (UUID) async throws -> String?) {
        guard !busy else { return }
        icloudTask?.cancel()
        let transfer = ICloudTransfer(kind: kind, stage: first, detail: detail)
        icloud = transfer; busy = true; activity = transfer.activity
        let assertion = BackgroundAssertion("听页 iCloud")
        icloudTask = Task { [weak self] in
            defer { assertion.end() }
            guard let self else { return }
            defer { if self.icloud?.id == transfer.id { self.busy = false; self.activity = "" } }
            do {
                if let summary = try await work(transfer.id) { self.step(transfer.id, .done, detail: summary) }
            } catch is CancellationError {
                self.step(transfer.id, .cancelled, detail: "已取消，本机书架未更改。")
            } catch {
                self.step(transfer.id, .failed, detail: error.localizedDescription)
            }
        }
    }
    func cancelICloud() {
        guard icloud?.cancellable == true else { return }
        icloudTask?.cancel()
    }
    func dismissICloudStatus() {
        guard let value = icloud, value.finished else { return }
        icloud = nil
    }
    func retryICloud() {
        guard let value = icloud, value.stage == .failed || value.stage == .cancelled else { return }
        // 还原重试从重新读取备份开始，确认后才会替换书库。
        value.kind == .backup ? backupToICloud() : readLatestICloudBackup()
    }

    func backupToICloud() {
        runICloud(.backup, .connecting, detail: "正在定位你的 iCloud Drive 容器…") { [self] id in
            guard let disk else { throw ReaderError.message("本机书架尚未就绪。") }
            let captured = owner, rows = entries.filter { $0.local }
            guard !rows.isEmpty else { throw ReaderError.message("没有可备份的本机书籍。") }
            let store = try await Task.detached(priority: .utility) { try ICloudBackupStore.connected() }.value
            try Task.checkCancellation()
            step(id, .readingLocal, completed: 0, total: rows.count, detail: "读取书籍内容、资源、进度与书签。")
            var items: [ICloudArchive.Item] = []
            for (index, row) in rows.enumerated() {
                let book: Book
                do { book = try await Task.detached(priority: .utility) { try disk.read(row.id) }.value }
                catch { throw ReaderError.message("读取《\(row.title)》失败，未写入备份：\(error.localizedDescription)") }
                try Task.checkCancellation()
                items.append(ICloudArchive.Item(packet: BackupPacket(book: book, progress: row.progress), bookmarks: row.bookmarks, group: row.group, hidden: row.hidden, highlights: row.highlights, listeningProgress: row.listeningProgress, lastReadAt: row.lastReadAt))
                step(id, .readingLocal, completed: index + 1, total: rows.count)
            }
            step(id, .writing, detail: "正在把 \(items.count) 本书写入一份新快照（单个文件，无法细分进度）。")
            let url = try await Task.detached(priority: .utility) { try store.save(ICloudArchive(owner: captured, books: items)) }.value
            watchUpload(url)
            return "已把 \(items.count) 本书及进度、书签写入本机 iCloud Drive 文件夹。上传由系统在后台进行，见下方上传状态。"
        }
    }

    func refreshUploadStatus() { if let url = backupUpload?.url { watchUpload(url) } }
    private func watchUpload(_ url: URL) {
        uploadTask?.cancel()
        backupUpload = ICloudUploadStatus(url: url)
        uploadTask = Task { [weak self] in
            for attempt in 0..<45 {
                if attempt > 0 { do { try await Task.sleep(for: .seconds(2)) } catch { return } }
                let result = await Task.detached(priority: .utility) { Result { try ICloudBackupStore(root: url).uploadState(url) } }.value
                guard let self, self.backupUpload?.url == url, !Task.isCancelled else { return }
                var status = ICloudUploadStatus(url: url, checkedAt: Date())
                switch result {
                case .success(.notUbiquitous): status.state = .notUbiquitous
                case .success(.waiting): status.state = .waiting
                case .success(.uploading): status.state = .uploading
                case .success(.uploaded): status.state = .uploaded
                case .success(.failed(let reason)): status.state = .failed(reason)
                case .failure(let error): status.state = .failed("无法查询上传状态（\(error.localizedDescription)）")
                }
                status.paused = attempt == 44 && !status.settled
                self.backupUpload = status
                if status.settled { return }
            }
        }
    }

    func readLatestICloudBackup() {
        runICloud(.restore, .connecting, detail: "正在定位你的 iCloud Drive 容器…") { [self] id in
            pendingRestore = nil
            let captured = owner
            let store = try await Task.detached(priority: .utility) { try ICloudBackupStore.connected() }.value
            try Task.checkCancellation()
            step(id, .finding, detail: "在 iCloud Drive「听页/Backups」中查找最新快照。")
            // 设备可能以 guest 运行，而其他设备在登录账号目录下备份：始终取全部账号目录中最新的一份，
            // 避免当前账号目录里的旧快照遮住其他目录中更新的备份。
            guard let (sourceOwner, url) = try await Task.detached(priority: .utility, operation: { try store.latestSnapshotAcrossOwners() }).value else {
                throw ReaderError.message("当前书架没有 iCloud 备份。如刚换设备，iCloud Drive 可能尚未同步完文件列表，请稍后重试。")
            }
            try Task.checkCancellation()
            var waited = 0
            while true {
                let request = waited == 0
                let state = try await Task.detached(priority: .utility) { try store.downloadState(url, owner: sourceOwner, request: request) }.value
                try Task.checkCancellation()
                if state == .ready { break }
                if case .failed(let reason) = state { throw ReaderError.message("iCloud 下载备份失败：\(reason)。请检查网络后重试。") }
                if waited >= Self.downloadWaitSeconds {
                    throw ReaderError.message("已等待约 \(Self.downloadWaitSeconds / 60) 分钟，备份仍未下载完成。系统会在后台继续下载，请保持联网后重试。")
                }
                if waited == 0 { step(id, .downloading, detail: "iCloud 正在把备份下载到本机，耗时取决于网络与备份大小。可以离开此页面。") }
                try await Task.sleep(for: .seconds(1))
                waited += 1
            }
            step(id, .reading, detail: "解析备份文件。")
            let archive = try await Task.detached(priority: .utility) { try store.decode(url, owner: sourceOwner) }.value
            try Task.checkCancellation()
            let total = archive.books.count
            step(id, .validating, completed: 0, total: total, detail: "逐本校验章节、资源与书签。")
            for (index, item) in archive.books.enumerated() {
                _ = try await Task.detached(priority: .utility) { try item.validated() }.value
                try Task.checkCancellation()
                step(id, .validating, completed: index + 1, total: total)
            }
            pendingRestore = archive
            let provenance = sourceOwner == captured ? "" : "该备份来自旧账号目录，还原后归入当前书架。"
            step(id, .confirming, detail: "备份有效：\(archive.createdAt.formatted()) · \(total) 本书。\(provenance)确认后才会改动本机书架。")
            return nil
        }
    }
    func cancelPendingRestore() {
        guard pendingRestore != nil else { return }
        pendingRestore = nil
        if let value = icloud, value.stage == .confirming { step(value.id, .cancelled, detail: "未还原，本机书架未更改。") }
    }
    func restoreICloud(_ archive: ICloudArchive) {
        pendingRestore = nil
        if let value = icloud, value.stage == .confirming { icloud = nil }
        runICloud(.restore, .restoring, detail: "先在临时目录写入全部书籍，成功后才替换本机书库。") { [self] id in
            guard let disk else { throw ReaderError.message("本机书架尚未就绪。") }
            let captured = owner
            // 存档的 owner 是来源账号（可能是旧账号目录），只校验存档自洽；书籍还原进当前书架。
            _ = try archive.validatedHeader(owner: archive.owner)
            let rows = try await beginLibraryRestore()
            var restored: [ShelfEntry]?
            defer { endLibraryRestore(restored) }
            step(id, .restoring, completed: 0, total: archive.books.count)
            let progress = reporter(id, .restoring)
            let replacing: @Sendable () -> Void = { [weak self] in
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.step(id, .replacing, detail: "正在替换本机书库。") } }
            }
            do {
                restored = try await Task.detached(priority: .userInitiated) {
                    try disk.restore(archive, owner: captured, entries: rows, progress: progress, willReplace: replacing)
                }.value
            } catch { throw ReaderError.message("\(error.localizedDescription)\n还原未完成，本机书架保持原样。") }
            step(id, .reloading, detail: "重新载入书架。")
            // defer 接纳事务返回的目录，避免 loadLibrary 的旧目录 flush 覆盖恢复结果。
            return "已还原 \(archive.books.count) 本书的内容、进度与书签，其余书籍保留。"
        }
    }
}

/// 进度同步使用的键值存储接口；测试可注入内存实现。
protocol ProgressKeyValueStore: AnyObject {
    func dictionary(forKey key: String) -> [String: Any]?
    func set(_ value: Any?, forKey key: String)
    func removeObject(forKey key: String)
    var dictionaryRepresentation: [String: Any] { get }
    func synchronize() -> Bool
}
extension NSUbiquitousKeyValueStore: ProgressKeyValueStore {}

/// 通过 iCloud 键值存储在多台设备间同步每本书的阅读位置（只含章节与句序号，不含书籍内容）。
/// 书籍 ID 在各设备导入时随机生成，因此用规范化的书名、作者与格式作为跨设备指纹（不含章数，删并章节后仍能匹配）；
/// 应用远端进度前校验章节不越界。同时读写旧版（含章数）的键，兼容已安装的旧版本。
/// 时间戳采用混合逻辑时钟：本机写入时间不早于已见过的远端时间 + 1，避免设备时钟偏差导致新操作被判为旧。
/// 状态只记录本机能确知的事实：本机提交给系统、收到系统推送的变化、本机合并结果与错误；
/// 系统不会告知何时上传完成或另一台设备何时收到。
@MainActor
final class ProgressSync: ObservableObject {
    static let enabledKey = "sync.progress"
    static let clockKey = "sync.progress.clock"
    /// 新旧键共用此前缀，变化通知与容量裁剪同时覆盖两者。
    private static let prefix = "progress."
    private static let fingerprintPrefix = "progress.v2."
    private static let limit = 900
    static let unavailableMessage = "无法访问 iCloud 键值存储（可能未登录 Apple 账号、iCloud 已关闭或签名缺少权限）。阅读位置仍保存在本机。"
    struct Summary: Equatable { var title: String; var symbol: String; var detail: String; var problem: Bool }

    @Published private(set) var accountAvailable: Bool
    @Published private(set) var lastCommit: Date?
    @Published private(set) var lastCommitCount = 0
    @Published private(set) var lastReceived: Date?
    @Published private(set) var lastReceivedCount = 0
    @Published private(set) var lastApplied = 0
    @Published private(set) var lastKept = 0
    @Published private(set) var lastChecked: Date?
    @Published private(set) var lastError: String?
    private let store: ProgressKeyValueStore
    private let defaults: UserDefaults
    private let account: () -> Bool
    private var observers: [NSObjectProtocol] = []
    /// 收到推送后，下一次合并的结果归属于这次推送。
    private var awaitingMerge = false
    var enabled: Bool { defaults.object(forKey: Self.enabledKey) as? Bool ?? true }

    init(store: ProgressKeyValueStore = NSUbiquitousKeyValueStore.default, defaults: UserDefaults = .standard,
         account: @escaping () -> Bool = { FileManager.default.ubiquityIdentityToken != nil }) {
        self.store = store; self.defaults = defaults; self.account = account
        accountAvailable = account()
    }

    static func key(_ entry: ShelfEntry) -> String {
        let source = [entry.title, entry.author, entry.format].map(normalized).joined(separator: "\u{1}")
        return fingerprintPrefix + digest(source)
    }
    /// build 61 及更早版本使用的键（含章数、不做规范化）。
    static func legacyKey(_ entry: ShelfEntry) -> String {
        prefix + digest([entry.title, entry.author, entry.format, String(entry.chapterCount)].joined(separator: "\u{1}"))
    }
    /// 去掉所有空白，统一大小写与全半角。
    static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) }.map(String.init).joined()
    }
    private static func digest(_ source: String) -> String {
        SHA256.hash(data: Data(source.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
    }
    /// 已见过的最大远端（及本机写入）时间戳，持久保存。
    private(set) var clock: Double {
        get { defaults.double(forKey: Self.clockKey) }
        set { defaults.set(newValue, forKey: Self.clockKey) }
    }
    private func observe(_ time: Double) { if time.isFinite, time > clock { clock = time } }
    /// 本机新进度的时间戳：max(当前时间, 已见远端最大时间 + 1)。
    func stamp(now: Double = ReadingProgress.now) -> Double {
        let value = max(now, clock + 1)
        clock = value
        return value
    }
    func start(onChange: @escaping @MainActor @Sendable () -> Void) {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: store, queue: .main) { note in
            let reason = (note.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? NSNumber)?.intValue
            let keys = note.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] ?? []
            MainActor.assumeIsolated { [weak self] in if self?.receive(reason: reason, keys: keys) == true { onChange() } }
        })
        observers.append(center.addObserver(forName: .NSUbiquityIdentityDidChange, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { [weak self] in self?.synchronize(); onChange() }
        })
        synchronize()
    }
    /// 处理系统推送的外部变化，返回是否需要合并。
    @discardableResult func receive(reason: Int?, keys: [String]) -> Bool {
        switch reason {
        case NSUbiquitousKeyValueStoreQuotaViolationChange:
            lastError = "iCloud 键值存储空间已满，部分阅读位置可能无法同步。"
            return false
        case NSUbiquitousKeyValueStoreAccountChange:
            accountAvailable = account(); lastError = nil
            return true
        default:
            let count = keys.filter { $0.hasPrefix(Self.prefix) }.count
            guard count > 0 else { return false }
            lastReceived = Date(); lastReceivedCount = count
            lastApplied = 0; lastKept = 0; awaitingMerge = true
            return true
        }
    }
    /// 让系统同步内存与磁盘中的键值。返回 true 只代表本机可访问键值存储，不代表已上传。
    @discardableResult func synchronize() -> Bool {
        accountAvailable = account()
        guard enabled else { return true }
        if store.synchronize() {
            if lastError == Self.unavailableMessage { lastError = nil }
            return true
        }
        lastError = Self.unavailableMessage
        return false
    }
    func refreshAccount() { accountAvailable = account() }
    /// 本机较新时写入键值存储，返回是否写入（仅提交给系统，不代表已上传）。
    private var pushes = 0
    @discardableResult func push(_ entry: ShelfEntry) -> Bool {
        guard enabled, entry.local, entry.progress.updatedAt > 0 else { return false }
        if let old = remote(entry), old.updatedAt >= entry.progress.updatedAt { return false }
        let value: [String: Any] = ["c": entry.progress.chapter, "p": entry.progress.position, "t": entry.progress.updatedAt]
        // 新键供本版本匹配，旧键让仍在用旧版本的设备继续收到进度。
        store.set(value, forKey: Self.key(entry))
        store.set(value, forKey: Self.legacyKey(entry))
        observe(entry.progress.updatedAt)
        // 朗读时每句都会推送进度；清理要遍历整个键值存储，每 50 次推送做一次即可（上限 1024 键，余量充足）。
        pushes += 1
        if pushes % 50 == 1 { prune() }
        return true
    }
    func recordCommit(_ count: Int) {
        guard count > 0 else { return }
        lastCommit = Date(); lastCommitCount = count
    }
    /// 删除书籍时清除该书的远端进度（新旧两个键）。
    func removeProgress(_ entry: ShelfEntry) {
        store.removeObject(forKey: Self.key(entry))
        store.removeObject(forKey: Self.legacyKey(entry))
    }
    /// 记录一次合并检查。没有收到推送但读到较新的远端进度时，也视为收到更新。
    func recordMerge(applied: Int, kept: Int) {
        lastChecked = Date()
        if awaitingMerge {
            awaitingMerge = false; lastApplied = applied; lastKept = kept
        } else if applied > 0 {
            lastReceived = Date(); lastReceivedCount = applied; lastApplied = applied; lastKept = kept
        }
        if lastError?.hasPrefix("合并") == true { lastError = nil }
    }
    func recordFailure(_ text: String) { lastError = text }
    /// 远端比本机更新且位置不同时返回远端进度。
    func newer(than entry: ShelfEntry) -> ReadingProgress? {
        guard enabled, entry.local, let value = remote(entry), value.updatedAt > entry.progress.updatedAt,
              value.chapter >= 0, value.chapter < max(1, entry.chapterCount), value.position >= 0,
              value.chapter != entry.progress.chapter || value.position != entry.progress.position else { return nil }
        return value
    }
    func summary(enabled: Bool) -> Summary {
        if !enabled { return Summary(title: "已关闭", symbol: Icon.syncPaused, detail: "不会提交或应用阅读位置，本机进度不受影响。之前同步到 iCloud 的位置记录会保留。", problem: false) }
        if let lastError { return Summary(title: "同步出错", symbol: Icon.cloudError, detail: lastError, problem: true) }
        if !accountAvailable { return Summary(title: "等待 iCloud", symbol: Icon.cloudDisconnected, detail: "未检测到可用的 iCloud（未登录 Apple 账号或已关闭 iCloud Drive）。阅读位置仍保存在本机，iCloud 可用后自动继续。", problem: true) }
        if lastCommit == nil && lastReceived == nil { return Summary(title: "已开启 · 等待 iCloud", symbol: Icon.cloud, detail: "本次启动尚未与其他设备交换进度。同步由系统在后台进行，到达时间取决于网络与 iCloud，不保证即时。", problem: false) }
        return Summary(title: "已开启", symbol: Icon.cloudSynced, detail: "同步由系统在后台进行，到达时间取决于网络与 iCloud，不保证即时。", problem: false)
    }
    /// 新旧两个键中较新的一条；读到的时间戳计入混合逻辑时钟。
    private func remote(_ entry: ShelfEntry) -> ReadingProgress? {
        let values = [Self.key(entry), Self.legacyKey(entry)].compactMap(remote(key:))
        values.forEach { observe($0.updatedAt) }
        return values.max { $0.updatedAt < $1.updatedAt }
    }
    private func remote(key: String) -> ReadingProgress? {
        guard let value = store.dictionary(forKey: key),
              let chapter = (value["c"] as? NSNumber)?.intValue, let position = (value["p"] as? NSNumber)?.intValue,
              let time = (value["t"] as? NSNumber)?.doubleValue, time.isFinite else { return nil }
        return ReadingProgress(chapter: chapter, position: position, updatedAt: time)
    }
    /// 合并远端阅读进度。`protected` 中正在阅读的书保留本机位置，稍后再合并。
    func merge(_ entries: [ShelfEntry], protected: Set<String>) -> (entries: [ShelfEntry], applied: [String], kept: Int) {
        var next = entries, applied: [String] = [], kept = 0
        for i in next.indices {
            guard let value = newer(than: next[i]) else { continue }
            if protected.contains(next[i].id) { kept += 1; continue }
            next[i].progress = value; applied.append(next[i].id)
        }
        return (next, applied, kept)
    }
    /// 本机新位置；与已保存位置相同时返回 nil，避免仅凭新时间戳覆盖其他设备的进度。
    func update(_ entry: ShelfEntry, chapter: Int, position: Int, now: Double = ReadingProgress.now) -> ReadingProgress? {
        let chapter = max(0, chapter), position = max(0, position)
        if entry.progress.updatedAt > 0, entry.progress.chapter == chapter, entry.progress.position == position { return nil }
        return ReadingProgress(chapter: chapter, position: position, updatedAt: stamp(now: now))
    }
    /// 键值存储最多 1024 个键，超出时丢弃最久未读的书。
    private func prune() {
        let rows = store.dictionaryRepresentation.compactMap { key, value -> (String, Double)? in
            guard key.hasPrefix(Self.prefix) else { return nil }
            return (key, ((value as? [String: Any])?["t"] as? NSNumber)?.doubleValue ?? 0)
        }
        guard rows.count > Self.limit else { return }
        for (key, _) in rows.sorted(by: { $0.1 < $1.1 }).prefix(rows.count - Self.limit) { store.removeObject(forKey: key) }
    }
}

extension AppModel {
    /// 合并其他设备更新的进度，并补推本机较新的进度。正在阅读或朗读中的书不被打断。
    func pullProgress() {
        guard !restoringLibrary, sync.enabled else { return }
        var protected = Set<String>()
        if let id = selectedBook?.id { protected.insert(id) }
        let (next, applied, kept) = sync.merge(entries, protected: protected)
        if !applied.isEmpty {
            guard let disk else { sync.recordFailure("合并其他设备的阅读进度失败：本机书架尚未就绪。"); return }
            do { try disk.saveCatalog(next) }
            catch { sync.recordFailure("合并其他设备的阅读进度失败：" + error.localizedDescription); return }
            entries = next
            // 听书位置独立保存；合并阅读位置不打断正在播放或暂停的声音。
        }
        sync.recordMerge(applied: applied.count, kept: kept)
        sync.recordCommit(entries.reduce(0) { $0 + (sync.push($1) ? 1 : 0) })
    }
    func refreshProgressSync() { sync.synchronize(); pullProgress() }
}

struct ICloudBackupView: View {
    @EnvironmentObject var model: AppModel
    @AppStorage(ProgressSync.enabledKey) private var syncProgress = true
    private var localBookCount: Int { model.entries.filter(\.local).count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                PageMasthead(title: "安心保管。", subtitle: "你的书，始终属于你。", kicker: "ARCHIVE · 备份", issue: "ICLOUD")
                    .padding(.bottom, 16)
                if let transfer = model.icloud {
                    sectionTitle("当前操作")
                    ICloudTransferCard(transfer: transfer)
                        .padding(16).background(Theme.surface, in: Rectangle())
                }

                sectionTitle("保存当前书库")
                HStack(spacing: 12) {
                    ThemeIcon(symbol: Icon.shelf, size: 24).accessibilityHidden(true)
                    Text("本机可备份书籍").font(.subheadline.weight(.medium))
                    Spacer(minLength: 8)
                    Text("\(localBookCount) 本").font(.subheadline).monospacedDigit().foregroundStyle(Theme.accent)
                }
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 16).padding(.vertical, 14).frame(minHeight: 52)
                .background(Theme.surface, in: Rectangle())
                if let upload = model.backupUpload {
                    VStack(alignment: .leading, spacing: 8) {
                        ICloudUploadRow(status: upload)
                        if !upload.settled || upload.paused {
                            Button { model.refreshUploadStatus() } label: { Label("刷新上传状态", systemImage: Icon.refresh) }
                                .frame(minHeight: 44)
                        }
                    }
                    .padding(16).background(Theme.surface, in: Rectangle())
                }

                sectionTitle("恢复书库")
                Button("查找并查看最新备份") { model.readLatestICloudBackup() }
                    .buttonStyle(SecondaryButtonStyle()).disabled(model.busy)
                    .accessibilityIdentifier("icloud.restore")
                Text("先查看备份日期与书籍数量。确认还原后，会替换对应书籍的内容、进度与书摘，其余书籍保留。")
                    .font(.caption).foregroundStyle(Theme.ink2)
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.accentSoft.opacity(0.55), in: Rectangle())

                sectionTitle("自动同步")
                Toggle(isOn: $syncProgress) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("自动同步阅读进度").font(.subheadline.weight(.medium)).foregroundStyle(Theme.ink)
                        Text("只同步章节与句子位置，不上传书籍")
                            .font(.caption).foregroundStyle(Theme.ink2)
                    }
                }
                .tint(Theme.accent).padding(16)
                .background(Theme.surface, in: Rectangle())
                ProgressSyncStatusRows(sync: model.sync, enabled: syncProgress)
                if syncProgress {
                    Button("立即检查进度同步") { model.refreshProgressSync() }
                        .buttonStyle(SecondaryButtonStyle())
                        .accessibilityIdentifier("icloud.sync.check")
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("手动备份包含已下载书籍、阅读进度、书签和书摘笔记，每次保存独立副本；不包含语音密钥与阅读统计。")
                    Text("备份写入后由系统上传，上传完成不代表其他设备已下载。自动同步要求同一 Apple 账号，且两台设备都有相同的书籍；到达时间由系统和网络决定。")
                }
                .font(.caption).foregroundStyle(Theme.ink2).padding(.top, 8)
            }
            .padding(.horizontal, Theme.inset).padding(.top, 12).padding(.bottom, 24)
            .frame(maxWidth: Theme.pageWidth).frame(maxWidth: .infinity)
        }
        .background(Theme.bg)
        .navigationTitle("备份与同步")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom) {
            Button("立即备份到 iCloud") { model.backupToICloud() }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(model.busy || localBookCount == 0)
                .accessibilityIdentifier("icloud.backup")
                .padding(.horizontal, Theme.inset).padding(.vertical, 12)
                .frame(maxWidth: Theme.pageWidth).frame(maxWidth: .infinity).background(Theme.bg)
        }
        .onAppear { model.sync.refreshAccount() }
        .onChange(of: syncProgress) { _, on in if on { model.refreshProgressSync() } }
        .confirmationDialog("还原备份并替换对应书籍？", isPresented: Binding(get: { model.pendingRestore != nil }, set: { if !$0 { model.cancelPendingRestore() } }), titleVisibility: .visible) {
            Button("确认还原并替换对应书籍", role: .destructive) {
                guard let archive = model.pendingRestore else { return }
                model.restoreICloud(archive)
            }
            Button("取消，保留本机书库", role: .cancel) { model.cancelPendingRestore() }
        } message: {
            if let pending = model.pendingRestore {
                Text("备份日期：\(pending.createdAt.formatted())\n包含 \(pending.books.count) 本书。还原将替换相同标识书籍的内容、进度、书签与书摘笔记，其余书籍保留。")
            }
        }
    }
    private func sectionTitle(_ title: String) -> some View {
        Text(L(title)).font(.caption2.weight(.medium)).foregroundStyle(Theme.ink2).padding(.top, 4)
    }

}

/// 手动备份 / 还原的阶段清单、真实计数与操作按钮。
private struct ICloudTransferCard: View {
    @EnvironmentObject var model: AppModel
    let transfer: ICloudTransfer
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                if transfer.running { ProgressView() }
                else { Image(systemName: symbol).foregroundStyle(tint).font(.system(size: 18, weight: .semibold)) }
                Text(transfer.title).font(.headline)
                Spacer(minLength: 0)
                if let count = transfer.countText { Text(count).font(.subheadline).monospacedDigit().foregroundStyle(.secondary) }
            }
            if let fraction = transfer.fraction, transfer.running {
                ProgressView(value: fraction).accessibilityLabel(transfer.activity)
            } else if transfer.running {
                Text("此步骤无法预估进度").font(.caption).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(transfer.steps.enumerated()), id: \.offset) { _, stage in
                    let state = stepState(stage)
                    HStack(spacing: 8) {
                        Image(systemName: state.symbol).foregroundStyle(state.tint).frame(width: 18)
                        Text(ICloudTransfer.title(stage, transfer.kind)).font(.subheadline).foregroundStyle(state.pending ? Color.secondary : Theme.ink)
                    }.accessibilityElement(children: .combine)
                }
            }
            if !transfer.detail.isEmpty {
                Text(transfer.detail).font(.footnote).foregroundStyle(transfer.stage == .failed ? Theme.danger : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
            HStack(spacing: 16) {
                if transfer.running && transfer.cancellable {
                    Button("取消本次操作") { model.cancelICloud() }.frame(minHeight: 44)
                }
                if transfer.stage == .failed || transfer.stage == .cancelled {
                    Button("重新尝试") { model.retryICloud() }.frame(minHeight: 44).disabled(model.busy)
                }
                if transfer.finished {
                    Button("收起状态") { model.dismissICloudStatus() }.frame(minHeight: 44).foregroundStyle(Theme.ink2)
                }
            }
            .buttonStyle(.borderless).font(.subheadline.weight(.medium))
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("icloud.transfer")
    }
    private var symbol: String {
        switch transfer.stage {
        case .done: return Icon.selection(true)
        case .failed: return Icon.transferFailed
        case .cancelled: return Icon.transferCancelled
        default: return Icon.help
        }
    }
    private var tint: Color { transfer.stage == .failed ? Theme.danger : transfer.stage == .done ? Theme.ink : .secondary }
    private func stepState(_ stage: ICloudTransfer.Stage) -> (symbol: String, tint: Color, pending: Bool) {
        let steps = transfer.steps
        guard let index = steps.firstIndex(of: stage) else { return (Icon.markUnread, .secondary, true) }
        let current = steps.firstIndex(of: transfer.lastActive) ?? (transfer.stage == .confirming ? steps.count : 0)
        if transfer.stage == .done || transfer.stage == .confirming || index < current { return (Icon.selection(true), Theme.ink, false) }
        if index == current {
            switch transfer.stage {
            case .failed: return (Icon.stepFailed, Theme.danger, false)
            case .cancelled: return (Icon.transferCancelled, .secondary, false)
            default: return (Icon.stepInProgress, Theme.accent, false)
            }
        }
        return (Icon.markUnread, .secondary, true)
    }
}

private struct ICloudUploadRow: View {
    let status: ICloudUploadStatus
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            switch status.state {
            case .checking, .waiting, .uploading:
                if status.paused { Image(systemName: Icon.duration).foregroundStyle(.secondary) } else { ProgressView() }
            case .uploaded: Image(systemName: Icon.cloudSynced).foregroundStyle(Theme.accent)
            case .notUbiquitous: Image(systemName: Icon.cloudDisconnected).foregroundStyle(.secondary)
            case .failed: Image(systemName: Icon.cloudError).foregroundStyle(Theme.danger)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(status.text).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                if let checked = status.checkedAt { Text("查询于 " + checked.formatted(date: .omitted, time: .standard)).font(.caption).foregroundStyle(.secondary) }
            }
        }.accessibilityElement(children: .combine).accessibilityIdentifier("icloud.upload")
    }
}

/// 自动同步状态：只展示本机确知的事实。
private struct ProgressSyncStatusRows: View {
    @ObservedObject var sync: ProgressSync
    let enabled: Bool
    var body: some View {
        let summary = sync.summary(enabled: enabled)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ThemeIcon(symbol: summary.symbol, size: 24).foregroundStyle(summary.problem ? Theme.danger : Theme.ink).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("同步状态").font(.subheadline.weight(.medium)).foregroundStyle(Theme.ink)
                    Text(summary.title).font(.caption).foregroundStyle(summary.problem ? Theme.danger : Theme.accent)
                    Text(summary.detail).font(.caption).foregroundStyle(Theme.ink2).fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine).accessibilityIdentifier("icloud.sync.status")
            if enabled {
                DisclosureGroup("同步详情") {
                    VStack(alignment: .leading, spacing: 12) {
                        row("最近本机提交", sync.lastCommit.map { "\(time($0)) · \(sync.lastCommitCount) 本 · 已交给系统，上传时间由 iCloud 决定" } ?? "本次启动尚未提交")
                        row("最近收到更新", sync.lastReceived.map { received($0) } ?? "本次启动尚未收到其他设备的更新")
                    }
                    .padding(.top, 8).frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.caption).tint(Theme.ink2)
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: Rectangle())
    }
    private func received(_ date: Date) -> String {
        var text = "\(time(date)) · \(sync.lastReceivedCount) 条变化"
        if sync.lastApplied > 0 { text += " · 已应用 \(sync.lastApplied) 本" }
        if sync.lastKept > 0 { text += " · \(sync.lastKept) 本正在阅读或朗读，保留本机位置" }
        return text
    }
    private func time(_ date: Date) -> String { date.formatted(date: Calendar.current.isDateInToday(date) ? .omitted : .abbreviated, time: .shortened) }
    private func row(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(L(title)).font(.caption).foregroundStyle(.secondary)
            Text(L(value)).font(.footnote).fixedSize(horizontal: false, vertical: true)
        }.accessibilityElement(children: .combine)
    }
}
