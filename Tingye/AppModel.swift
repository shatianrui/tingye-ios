import SwiftUI
import Combine

extension ShelfEntry {
    var started: Bool { progress.updatedAt > 0 }
    var readFraction: Double {
        guard started else { return 0 }
        guard let counts = sentenceCounts, counts.count == chapterCount, !counts.isEmpty else {
            return Double(min(max(0, progress.chapter), max(0, chapterCount - 1))) / Double(max(1, chapterCount))
        }
        let weights = counts.map { max(1, $0) }
        let chapter = min(max(0, progress.chapter), weights.count - 1)
        let current = min(max(0, progress.position), weights[chapter] - 1) + 1
        return Double(weights.prefix(chapter).reduce(0, +) + current) / Double(weights.reduce(0, +))
    }
    var percentText: String { started ? "\(Int((readFraction * 100).rounded()))%" : "未开卷" }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var entries: [ShelfEntry] = []
    /// 需要处理的错误；普通成功使用 notice，不再要求点确认。
    @Published var message: String?
    @Published var notice: AppNotice?
    @Published private(set) var importReport: ImportReport?
    private var noticeTask: Task<Void, Never>?
    private var listeningObserver: AnyCancellable?
    @Published var busy = false
    @Published var activity = ""
    @Published var tab = 0
    /// 首页搜索交给书架处理，沿用同一套跨分组搜索，不建立第二份查询状态。
    @Published var shelfSearchRequested = false
    /// 书架排序方式:recent 最近阅读 / title 书名 / author 作者 / added 添加时间
    @Published var sortOrder = "recent"
    @Published var selectedBook: Book?
    @Published var showingPlayer = false
    /// 一次性跳转目标：阅读页打开时消费（今日一句「从这句读」），不改动书架上的进度，直到读者在那里翻页或关闭。
    var readerJump: (id: String, chapter: Int, position: Int)?
    @Published var readingSeconds: [String: Double] = [:]
    /// 逐次阅读 / 听书记录（统计页的时段与排行），按书库保存在本机
    @Published var sessions: [ReadingSession] = []
    /// 隐藏模式：用面容 ID / 密码验证后，本次运行期间显示隐藏的书
    @Published var hiddenUnlocked = false
    /// 书架用的轻量索引：封面缩略图与分类在后台读取，不把整本书留在内存里。
    @Published private(set) var covers: [String: UIImage] = [:]
    @Published private(set) var categories: [String: String] = [:]
    private var indexed: Set<String> = []
    private var cacheOrder: [String] = []
    private static let dayFormatter: DateFormatter = { let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f }()
    static func dayKey(_ date: Date) -> String { dayFormatter.string(from: date) }
    let player = SpeechPlayer()
    let sync: ProgressSync
    /// 手动 iCloud 备份 / 还原的当前阶段；存于模型中，离开再进入页面仍可看到。
    @Published var icloud: ICloudTransfer?
    @Published var pendingRestore: ICloudArchive?
    @Published var backupUpload: ICloudUploadStatus?
    var icloudTask: Task<Void, Never>?
    var uploadTask: Task<Void, Never>?
    private var openTask: Task<Void, Never>?
    private var catalogSaveTask: Task<Void, Never>?
    private var catalogDirty = false
    var sessionsSaveTask: Task<Void, Never>?
    var sessionsDirty = false
    /// 还原替换书库期间暂停目录和书籍写入。
    @Published var restoringLibrary = false
    private var activeBookWrites = 0
    private var libraryGeneration = UUID()
    private var indexTasks: [UUID: Task<Void, Never>] = [:]
    private var playbackObserver: AnyCancellable?
    private(set) var disk: LibraryDisk?
    private var cache: [String: Book] = [:]
    /// 书库目录名。旧版登录过的用户沿用原账号目录，避免书籍、进度与 iCloud 存档"消失"。
    let owner: String
    var lastBook: ShelfEntry? { entries.filter(\.local).max { $0.progress.updatedAt < $1.progress.updatedAt } }

    init(disk suppliedDisk: LibraryDisk? = nil, progressSync: ProgressSync? = nil) {
        owner = suppliedDisk?.root.lastPathComponent ?? LocalOwner.resolve()
        sync = progressSync ?? ProgressSync()
        do {
            if let suppliedDisk {
                disk = suppliedDisk; entries = try suppliedDisk.catalog(); indexLibrary()
            } else { try loadLibrary() }
        } catch { message = error.localizedDescription }
        player.onProgress = { [weak self] id, chapter, position in self?.saveProgress(id, chapter: chapter, position: position) }
        sync.start { [weak self] in self?.pullProgress() }
        // 朗读暂停或结束后，合并期间被搁置的远端进度（延后一拍，等播放器状态落定）。
        playbackObserver = player.$playing.removeDuplicates().filter { !$0 }.dropFirst()
            .receive(on: DispatchQueue.main).sink { [weak self] _ in
                self?.flushPendingSaves()
                self?.pullProgress()
            }
        listeningObserver = player.$playing.removeDuplicates().filter { $0 }
            .receive(on: DispatchQueue.main).sink { [weak self] _ in
                guard let self, self.player.playing, let id = self.player.book?.id else { return }
                self.recordActivity(.listening, for: id)
            }
        pullProgress()
    }
    func loadLibrary() throws {
        try requireWritableLibrary()
        flushPendingSaves()
        player.stop(); selectedBook = nil
        invalidateLibraryCache()
        let next = try LibraryDisk(owner: owner)
        var rows = try next.catalog()
        let migrationMarker = next.root.appendingPathComponent("legacy-migration-v1.complete")
        var shouldMigrate = !FileManager.default.fileExists(atPath: migrationMarker.path)
        var legacyRows: [String: [String: JSONValue]] = [:]
        if shouldMigrate {
            do { legacyRows = try LegacyCatalog.entries(owner: owner) }
            catch { shouldMigrate = false; message = "旧版书架目录暂时无法读取，原文件已保留：" + error.localizedDescription }
        }
        // 纯本地版不再有云端目录；移除旧版残留的"仅云端"条目。
        rows.removeAll { !$0.local }
        // The old client's book JSON is protocol-compatible; leave originals intact.
        let legacy = next.root.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("tingye-vercel").appendingPathComponent(owner)
        if shouldMigrate && FileManager.default.fileExists(atPath: legacy.path) {
            for url in try FileManager.default.contentsOfDirectory(at: legacy, includingPropertiesForKeys: nil) where url.pathExtension == "json" {
                guard let book = try? JSONDecoder().decode(Book.self, from: Data(contentsOf: url)).validated(), !rows.contains(where: { $0.id == book.id }) else { continue }
                if legacyRows[book.id]?["deleted"]?.bool == true { continue }
                try next.write(book); rows.append(LegacyCatalog.row(book: book, metadata: legacyRows[book.id]))
            }
        }
        for book in Samples.books where !rows.contains(where: { $0.id == book.id }) { try next.write(book); rows.append(LegacyCatalog.row(book: book, metadata: legacyRows[book.id])) }
        try next.saveCatalog(rows)
        if shouldMigrate { try Data("complete".utf8).write(to: migrationMarker, options: .atomic) }
        disk = next; entries = rows
        readingSeconds = UserDefaults.standard.dictionary(forKey: "reading.seconds." + owner) as? [String: Double] ?? [:]
        loadSessions()
        indexLibrary()
    }
    func notify(_ text: String, importResults: Bool = false) {
        noticeTask?.cancel()
        let next = AppNotice(text: text, importResults: importResults)
        notice = next
        if UIAccessibility.isVoiceOverRunning { UIAccessibility.post(notification: .announcement, argument: text) }
        // VoiceOver 用户自行关闭，避免来不及读完或操作。
        guard !UIAccessibility.isVoiceOverRunning else { return }
        noticeTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(8)) } catch { return }
            if self?.notice?.id == next.id { self?.notice = nil }
        }
    }
    func recordActivity(_ activity: ReadingActivity, for id: String) {
        guard !restoringLibrary, let index = entries.firstIndex(where: { $0.id == id }) else { return }
        guard entries[index].lastActivity != activity || (activity == .listening && entries[index].hasListened != true) else { return }
        entries[index].lastActivity = activity
        if activity == .listening { entries[index].hasListened = true }
        scheduleCatalogSave()
    }
    func resumeActions(for entry: ShelfEntry) -> ResumeActions {
        let history = sessions.filter { $0.bookID == entry.id }
        let latest = history.max { $0.end < $1.end }
        let current = player.book?.id == entry.id
        return ResumeActions(started: entry.started || entry.lastActivity != nil,
                             lastActivity: entry.lastActivity ?? (latest?.listening == true ? .listening : .reading),
                             hasListened: current || entry.hasListened == true || history.contains(where: \.listening),
                             playing: current && player.playing)
    }
    func run(_ title: String, operation: @escaping @MainActor () async throws -> Void) {
        guard !busy else { notify("请等待当前操作完成后重试。"); return }
        busy = true; activity = title
        Task { defer { busy = false; activity = "" }; do { try await operation() } catch is CancellationError {} catch { message = error.localizedDescription } }
    }
    func open(_ entry: ShelfEntry) {
        readerJump = nil
        openBook(entry)
    }
    /// 打开到指定的章与句。
    func open(_ entry: ShelfEntry, chapter: Int, position: Int) {
        readerJump = (entry.id, chapter, position)
        openBook(entry)
    }
    private func openBook(_ entry: ShelfEntry) {
        guard !restoringLibrary else { return }
        openTask?.cancel()
        if let cached = cache[entry.id] {
            recordActivity(.reading, for: entry.id)
            selectedBook = cached
            return
        }
        let showActivity = !busy
        if showActivity { busy = true; activity = "正在翻开《\(entry.title)》" }
        openTask = Task { [weak self] in
            defer { if let self, showActivity { self.busy = false; self.activity = "" } }
            guard let self else { return }
            do {
                let loaded = try await self.loadBook(entry.id)
                try Task.checkCancellation()
                self.recordActivity(.reading, for: entry.id)
                self.selectedBook = loaded
            } catch is CancellationError {} catch {
                self.message = error.localizedDescription
            }
        }
    }
    /// 在后台读取并解码：多图 EPUB 的书籍文件可达上百 MB，放在主线程会让翻开时整屏卡住。
    func loadBook(_ id: String) async throws -> Book {
        try requireWritableLibrary()
        if let value = cache[id] { return value }
        guard let disk else { throw ReaderError.message("本机书架尚未就绪。") }
        let generation = libraryGeneration
        let value = try await Task.detached(priority: .userInitiated) { try disk.read(id) }.value
        guard !restoringLibrary, generation == libraryGeneration else { throw CancellationError() }
        remember(value); return value
    }
    func book(_ id: String) throws -> Book {
        try requireWritableLibrary()
        if let value = cache[id] { return value }
        guard let disk else { throw ReaderError.message("本机书架尚未就绪。") }
        let value = try disk.read(id); remember(value); return value
    }
    private func remember(_ value: Book) {
        cache[value.id] = value
        cacheOrder.removeAll { $0 == value.id }; cacheOrder.append(value.id)
        while cacheOrder.count > 4 { let old = cacheOrder.removeFirst(); if old != player.book?.id && old != selectedBook?.id { cache[old] = nil } }
    }
    /// 只丢弃封面缩略图与分类索引并在后台重建；不重载书架，正在听的书不受影响。
    func clearIndexCache() {
        guard !restoringLibrary else { return }
        invalidateLibraryCache(); disk?.removeIndex(); indexLibrary()
    }
    private func invalidateLibraryCache() {
        libraryGeneration = UUID()
        for task in indexTasks.values { task.cancel() }
        cache = [:]; cacheOrder = []; covers = [:]; categories = [:]; indexed = []
    }
    private func requireWritableLibrary() throws {
        guard !restoringLibrary else { throw ReaderError.message("正在还原书库，请完成后重试。") }
    }
    /// 提交旧目录后，取消并等候全部后台索引任务，避免它们写入替换后的书库。
    func beginLibraryRestore() async throws -> [ShelfEntry] {
        try requireWritableLibrary()
        guard activeBookWrites == 0 else { throw ReaderError.message("书籍正在保存，请完成后重试还原。") }
        player.stop()
        try commitCatalogSave()
        flushSessionsSave()
        restoringLibrary = true
        openTask?.cancel(); openTask = nil; selectedBook = nil
        let tasks = Array(indexTasks.values)
        invalidateLibraryCache()
        for task in tasks { await task.value }
        return entries
    }
    /// 成功时接纳事务返回的目录；失败时继续使用原来的内存和磁盘书库。
    func endLibraryRestore(_ restored: [ShelfEntry]?) {
        if let restored { entries = restored }
        restoringLibrary = false
        indexLibrary()
        if restored != nil { refreshProgressSync() }
    }
    private func forget(_ id: String) { cache[id] = nil; cacheOrder.removeAll { $0 == id }; covers[id] = nil; categories[id] = nil; indexed.remove(id); disk?.removeIndex(id) }
    /// 在后台为尚未索引的本机书籍读取分类与封面缩略图。
    func indexLibrary() {
        guard !restoringLibrary, let disk else { return }
        let ids = entries.filter { $0.local && !indexed.contains($0.id) }.map(\.id)
        guard !ids.isEmpty else { return }
        indexed.formUnion(ids)
        let captured = owner, generation = libraryGeneration, taskID = UUID()
        // 句数索引已在书架目录里、且有缩略图缓存的书，直接读缓存，不必解码整本书。
        let counted = Set(entries.filter { $0.sentenceCounts != nil }.map(\.id))
        indexTasks[taskID] = Task.detached(priority: .utility) { [weak self] in
            for id in ids {
                guard !Task.isCancelled else { break }
                if counted.contains(id), let (meta, data) = disk.cachedIndex(id) {
                    let cover = data.flatMap(UIImage.init(data:))
                    await MainActor.run { [weak self] in
                        guard let self, !self.restoringLibrary, self.libraryGeneration == generation,
                              self.owner == captured, self.indexed.contains(id) else { return }
                        if let category = meta.category { self.categories[id] = category }
                        if let cover { self.covers[id] = cover }
                    }
                    continue
                }
                guard let book = try? disk.read(id) else { continue }
                guard !Task.isCancelled else { break }
                let counts = book.chapters.map { Sentence.split($0.text).count }
                let category = book.fields["category"]?.string
                let intro = [book.fields["description"]?.string, book.fields["intro"]?.string]
                    .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .first { !$0.isEmpty }
                let cover = book.coverData.flatMap(UIImage.init(data:))?.preparingThumbnail(of: CGSize(width: 240, height: 343))
                let coverData = cover?.jpegData(compressionQuality: 0.85)
                guard !Task.isCancelled else { break }
                await MainActor.run { [weak self] in
                    guard let self, !self.restoringLibrary, self.libraryGeneration == generation,
                          self.owner == captured, self.indexed.contains(id) else { return }
                    disk.saveIndex(id, category: category, cover: coverData)
                    if let i = self.entries.firstIndex(where: { $0.id == id }),
                       self.entries[i].sentenceCounts != counts || (self.entries[i].intro == nil && intro != nil) {
                        var next = self.entries; next[i].sentenceCounts = counts; next[i].chapterCount = counts.count
                        if next[i].intro == nil { next[i].intro = intro }
                        self.entries = next
                        self.scheduleCatalogSave()
                    }
                    if let category { self.categories[id] = category }
                    if let cover { self.covers[id] = cover }
                }
            }
            await MainActor.run { [weak self] in self?.indexTasks[taskID] = nil }
        }
    }
    /// 写入新导入的书籍。编码、校验与逐章分句在后台进行，大书导入不阻塞界面。
    func add(_ book: Book, progress: ReadingProgress = .init()) async throws {
        try requireWritableLibrary()
        activeBookWrites += 1; defer { activeBookWrites -= 1 }
        guard let disk else { throw ReaderError.message("本机书架尚未就绪。") }
        let entry = try await Task.detached(priority: .userInitiated) {
            try disk.write(book)
            return ShelfEntry(book: book, progress: progress)
        }.value
        var updated = entries.filter { $0.id != book.id }
        updated.insert(entry, at: 0)
        catalogSaveTask?.cancel(); catalogDirty = false
        try disk.saveCatalog(updated); entries = updated; forget(book.id); remember(book); indexLibrary()
    }
    func scheduleCatalogSave() {
        guard !restoringLibrary else { return }
        catalogDirty = true
        catalogSaveTask?.cancel()
        catalogSaveTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(1200)) } catch { return }
            self?.flushCatalogSave()
        }
    }
    private func commitCatalogSave() throws {
        guard !restoringLibrary else { return }
        catalogSaveTask?.cancel()
        catalogSaveTask = nil
        guard catalogDirty, let disk else { return }
        try disk.saveCatalog(entries)
        catalogDirty = false
    }
    private func flushCatalogSave() {
        do { try commitCatalogSave() }
        catch { message = "阅读位置保存失败：" + error.localizedDescription }
    }
    func flushPendingSaves() {
        flushCatalogSave()
        flushSessionsSave()
    }
    func saveProgress(_ id: String, chapter: Int, position: Int) {
        guard !restoringLibrary else { return }
        guard let i = entries.firstIndex(where: { $0.id == id }), entries[i].local,
              let progress = sync.update(entries[i], chapter: chapter, position: position) else { return }
        entries[i].progress = progress
        if sync.push(entries[i]) { sync.recordCommit(1) }
        scheduleCatalogSave()
    }
    func bookmark(_ id: String, chapter: Int, position: Int, excerpt: String) {
        guard !restoringLibrary else { return }
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        var next = entries
        if let index = next[i].bookmarks.firstIndex(where: { $0.chapter == chapter && $0.position == position }) { next[i].bookmarks.remove(at: index) }
        else { next[i].bookmarks.append(Bookmark(chapter: chapter, position: position, excerpt: String(excerpt.prefix(80)))) }
        catalogSaveTask?.cancel(); catalogDirty = false
        do { try disk?.saveCatalog(next); entries = next } catch { message = error.localizedDescription }
    }
    func removeLocal(_ id: String) throws {
        try requireWritableLibrary()
        if player.book?.id == id { player.stop() }
        var next = entries
        next.removeAll { $0.id == id }
        catalogSaveTask?.cancel(); catalogDirty = false
        // Commit catalog first so a failed delete never leaves a missing file listed as readable.
        try disk?.saveCatalog(next); entries = next; forget(id); try disk?.remove(id)
    }
    /// 删除本机副本，并从全部 iCloud 备份快照与进度同步中移除该书。iCloud 失败时本机副本保留，可重试。
    func removeLocalAndICloud(_ id: String) {
        run("正在删除本机与 iCloud 副本") { [self] in
            guard let entry = entries.first(where: { $0.id == id }) else { return }
            let store = try await Task.detached(priority: .utility) { try ICloudBackupStore.connected() }.value
            let result = try await Task.detached(priority: .utility) { try await store.removeBook(id) }.value
            sync.removeProgress(entry)
            try removeLocal(id)
            var text = "已删除《\(entry.title)》的本机副本与 iCloud 备份"
            if result.rewritten + result.deleted > 0 { text += "（改写 \(result.rewritten) 份快照、删除 \(result.deleted) 份空快照）" }
            notify(text + "。")
        }
    }
    private func checkOwner(_ captured: String) throws {
        guard owner == captured else { throw ReaderError.message("书库已变化，请重新操作。") }
    }
    func beginImport(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        run("正在导入书籍") { [self] in try await importWithFeedback(urls) }
    }
    /// 可恢复的单项失败留在结果列表，其他文件继续，不弹出一串警告。
    func importWithFeedback(_ urls: [URL]) async throws {
        let previous = importReport?.id
        do { try await importFiles(urls) }
        catch {
            guard let report = importReport, report.id != previous, report.finished else { throw error }
        }
        if let report = importReport { notify(report.summary, importResults: true) }
    }
    func importFiles(_ urls: [URL]) async throws {
        try requireWritableLibrary()
        guard !urls.isEmpty else { return }
        guard importReport?.finished != false else { throw ReaderError.message("已有导入任务，请等待完成后重试。") }
        importReport = ImportReport(items: urls.map { ImportItem(name: $0.lastPathComponent) })
        // 解析中的导入也属于写入事务，防止旧文件在还原完成后才继续提交。
        activeBookWrites += 1; defer { activeBookWrites -= 1 }
        let captured = owner
        var failures: [String] = []
        for (index, url) in urls.enumerated() {
            importReport?.items[index].state = .importing
            do {
                let secured = url.startAccessingSecurityScopedResource(); defer { if secured { url.stopAccessingSecurityScopedResource() } }
                let imported = try await Task.detached(priority: .userInitiated) { try BookImporter.read(url) }.value
                try checkOwner(captured); try await add(imported.book, progress: imported.progress)
                importReport?.items[index].state = .imported(imported.book.id)
            } catch {
                let reason = error is DecodingError ? "文件内容无法解析，可能已损坏或不是有效的听页备份。请重新下载原文件后再导入。" : error.localizedDescription
                importReport?.items[index].state = .failed(reason)
                failures.append(url.lastPathComponent + "：" + reason)
            }
        }
        if !failures.isEmpty { throw ReaderError.message(failures.joined(separator: "\n")) }
    }
    func startListening(_ book: Book, showPlayer: Bool = true) {
        guard !restoringLibrary else { return }
        guard book.fields["comic"]?.bool != true else { message = "漫画没有可以朗读的文字。"; return }
        let progress = entries.first(where: { $0.id == book.id })?.progress ?? .init()
        recordActivity(.listening, for: book.id)
        player.start(book: book, chapter: progress.chapter, position: progress.position)
        showingPlayer = showPlayer
    }
    /// 所有「听书」入口共用：正在听这本书时只继续并打开听读页，不从头重建朗读。
    func listen(_ id: String, showPlayer: Bool = true) {
        guard !restoringLibrary else { return }
        if player.book?.id == id {
            if !player.playing { player.resume() }
            showingPlayer = showPlayer
            return
        }
        run("正在打开") { [self] in
            startListening(try await loadBook(id), showPlayer: showPlayer)
        }
    }
    func category(_ row: ShelfEntry) -> String { categories[row.id] ?? "其他" }
    func markChapters(_ id: String, chapters: Set<Int>, read: Bool) async throws {
        try requireWritableLibrary()
        activeBookWrites += 1; defer { activeBookWrites -= 1 }
        guard let disk else { throw ReaderError.message("本机书架尚未就绪。") }
        var value = try await loadBook(id)
        var marked = Set(value.fields["nativeReadChapters"]?.array?.compactMap(\.int) ?? [])
        if read { marked.formUnion(chapters) } else { marked.subtract(chapters) }
        value.fields["nativeReadChapters"] = .array(marked.sorted().map { .number(Double($0)) })
        // 大书的整本编码放后台，避免阻塞界面。
        try await Task.detached(priority: .userInitiated) { try disk.write(value) }.value
        remember(value); objectWillChange.send()
    }
    func repair(_ id: String, from url: URL) async throws {
        try requireWritableLibrary()
        activeBookWrites += 1; defer { activeBookWrites -= 1 }
        let captured = owner
        guard let row = entries.first(where: { $0.id == id }) else { return }
        let secured = url.startAccessingSecurityScopedResource(); defer { if secured { url.stopAccessingSecurityScopedResource() } }
        var value = try await Task.detached { try BookImporter.read(url).book }.value
        try checkOwner(captured)
        guard value.format.caseInsensitiveCompare(row.format) == .orderedSame else { throw ReaderError.message("请选择与原书相同格式的文件。") }
        value.fields["id"] = .string(id)
        let old = try await loadBook(id)
        for key in ["nativeReadChapters", "category"] { if let field = old.fields[key] { value.fields[key] = field } }
        // 大书的整本编码与逐章分句放后台，避免阻塞界面。
        let counts = try await Task.detached(priority: .userInitiated) { [disk] in
            try disk?.write(value)
            return value.chapters.map { Sentence.split($0.text).count }
        }.value
        forget(id); remember(value); indexLibrary()
        if let index = entries.firstIndex(where: { $0.id == id }) {
            var next = entries; next[index].title = value.title; next[index].author = value.author; next[index].chapterCount = value.chapters.count
            next[index].sentenceCounts = counts
            next[index].intro = [value.fields["description"]?.string, value.fields["intro"]?.string]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty }
            next[index].progress.chapter = max(0, min(row.progress.chapter, value.chapters.count - 1))
            catalogSaveTask?.cancel(); catalogDirty = false
            try disk?.saveCatalog(next); entries = next
        }
        if player.book?.id == id { player.stop() }
        notify("原书图文与封面已修复，书籍标识、书签和阅读进度已保留。")
    }
    /// 阅读页关闭（已保存最终位置）后，合并阅读期间被搁置的远端进度。
    func readerClosed(_ id: String) {
        flushPendingSaves()
        guard selectedBook?.id != id else { return }
        pullProgress()
    }
    /// 记一段阅读或听书时间：按日累计（统计图表），并合并进这本书的当前阅读记录。
    func recordReading(seconds: Double, bookID: String? = nil, title: String = "", listening: Bool = false) {
        guard seconds > 0, seconds <= 30 else { return }
        readingSeconds[Self.dayKey(Date()), default: 0] += seconds
        if let bookID { appendSession(seconds: seconds, bookID: bookID, title: title, listening: listening) }
        else { scheduleSessionsSave() }
    }

}

import Security
/// 纯本地版：书库归属固定在本机。旧版登录用户的书存放在其账号目录下，首次启动时记住该目录并清除已无用的登录凭据。
enum LocalOwner {
    static let key = "library.owner"
    static func resolve() -> String {
        let defaults = UserDefaults.standard
        if let saved = defaults.string(forKey: key), Book.validID(saved) { return saved }
        var owner = "guest"
        let legacyAccount = Data("tingye.vercel.session.v1".utf8)
        let candidates = [(try? Keychain.data("session")) ?? nil] + ["app:no-auth", "app"].map { (try? Keychain.data("", service: $0, account: legacyAccount)) ?? nil }
        for case let data? in candidates {
            if let value = try? JSONDecoder().decode([String: JSONValue].self, from: data), let id = value["user"]?.object?["userId"]?.string, Book.validID(id) { owner = id; break }
        }
        defaults.set(owner, forKey: key)
        try? Keychain.remove("session")
        for service in ["app:no-auth", "app"] { SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: legacyAccount] as CFDictionary) }
        return owner
    }
}
