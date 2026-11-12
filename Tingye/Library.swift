import SwiftUI
import LocalAuthentication

// MARK: - 书库整理：分组、隐藏、划线、阅读记录（参照 PureLibro 的书库管理）

extension AppModel {

    // MARK: 书库目录编辑

    /// 修改若干书的书库条目并写回目录；写盘失败时界面不变并提示。
    func updateEntries(_ ids: Set<String>, _ change: (inout ShelfEntry) -> Void) {
        guard !restoringLibrary else { message = "正在还原书库，请完成后再修改。"; return }
        var next = entries
        for i in next.indices where ids.contains(next[i].id) { change(&next[i]) }
        do { try disk?.saveCatalog(next); entries = next }
        catch { message = "书库保存失败：" + error.localizedDescription }
    }

    /// 当前可见的书：隐藏的书只在解锁隐藏模式后出现。
    var visibleEntries: [ShelfEntry] { hiddenUnlocked ? entries : entries.filter { !$0.isHidden } }

    /// 隐藏模式未解锁时，阅读记录也不能透露书名、封面或阅读时间。
    var visibleSessions: [ReadingSession] {
        Self.visibleSessions(sessions, entries: entries, hiddenUnlocked: hiddenUnlocked)
    }
    static func visibleSessions(_ sessions: [ReadingSession], entries: [ShelfEntry], hiddenUnlocked: Bool) -> [ReadingSession] {
        guard !hiddenUnlocked else { return sessions }
        let hiddenIDs = Set(entries.filter(\.isHidden).map(\.id))
        return sessions.filter { !hiddenIDs.contains($0.bookID) }
    }

    // MARK: 分组（多级，路径以「/」分隔）

    /// 全部分组路径（含各级父路径），按名称排序
    var groupPaths: [String] {
        var paths = Set<String>()
        for entry in visibleEntries {
            guard let group = entry.group, !group.isEmpty else { continue }
            let parts = group.split(separator: "/").map(String.init)
            for depth in 1...parts.count { paths.insert(parts.prefix(depth).joined(separator: "/")) }
        }
        return paths.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// 某一层的直接子分组名（parent 为 nil 表示顶层）
    func subgroups(of parent: String?) -> [String] {
        let prefix = parent.map { $0 + "/" } ?? ""
        let depth = parent.map { $0.split(separator: "/").count + 1 } ?? 1
        return groupPaths.filter { $0.hasPrefix(prefix) && $0.split(separator: "/").count == depth }
    }

    /// 分组内（含子分组）的全部书
    func books(inGroup path: String) -> [ShelfEntry] {
        visibleEntries.filter { guard let group = $0.group else { return false }; return group == path || group.hasPrefix(path + "/") }
    }

    func move(_ ids: Set<String>, toGroup path: String?) {
        let clean = path.map(Self.normalizedGroup).flatMap { $0.isEmpty ? nil : $0 }
        updateEntries(ids) { $0.group = clean }
    }

    /// 重命名分组：子分组一并改名
    func renameGroup(_ old: String, to new: String) {
        let target = Self.normalizedGroup(new)
        guard !target.isEmpty, target != old else { return }
        let ids = Set(entries.filter { $0.group == old || ($0.group ?? "").hasPrefix(old + "/") }.map(\.id))
        updateEntries(ids) { entry in
            guard let group = entry.group else { return }
            entry.group = target + group.dropFirst(old.count)
        }
    }

    /// 删除分组：书仍留在书库里，只是不再归入该分组（与 PureLibro 一致）
    func dissolveGroup(_ path: String) {
        let ids = Set(books(inGroup: path).map(\.id))
        let parent = path.split(separator: "/").dropLast().joined(separator: "/")
        updateEntries(ids) { $0.group = parent.isEmpty ? nil : parent }
    }

    nonisolated static func normalizedGroup(_ raw: String) -> String {
        raw.split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: "/")
    }

    // MARK: 隐藏

    func setHidden(_ ids: Set<String>, _ hidden: Bool) {
        updateEntries(ids) { $0.hidden = hidden ? true : nil }
    }

    /// 打开隐藏模式：面容 ID / 触控 ID / 设备密码验证通过后，本次运行期间显示隐藏的书
    func unlockHidden() async {
        if await PrivacyLock.authenticate(reason: "显示隐藏的书籍") { hiddenUnlocked = true }
    }

    // MARK: 划线与笔记

    func addHighlight(_ bookID: String, _ highlight: Highlight) {
        var highlight = highlight
        // 构建 142：创建处（阅读页选区）已带锚点时直接用；没带（如读完页摘句）时按当前缓存的书补写。
        if highlight.anchor == nil {
            highlight.anchor = locatorAnchor(bookID: bookID, chapter: highlight.chapter, position: highlight.start)
        }
        updateEntries([bookID]) { entry in
            var list = entry.highlights ?? []
            // 同一章里与新划线重叠的旧划线合并为新的一条
            list.removeAll { $0.chapter == highlight.chapter && $0.start <= highlight.end && highlight.start <= $0.end && $0.note == nil }
            list.append(highlight)
            entry.highlights = list.sorted { ($0.chapter, $0.start) < ($1.chapter, $1.start) }
        }
    }

    func updateHighlight(_ bookID: String, _ highlight: Highlight) {
        updateEntries([bookID]) { entry in
            guard let i = entry.highlights?.firstIndex(where: { $0.id == highlight.id }) else { return }
            entry.highlights?[i] = highlight
        }
    }

    func removeHighlight(_ bookID: String, id: UUID) {
        updateEntries([bookID]) { entry in
            entry.highlights?.removeAll { $0.id == id }
            if entry.highlights?.isEmpty == true { entry.highlights = nil }
        }
    }

    /// 全书库的笔记数（统计页）
    var noteCount: Int { entries.reduce(0) { $0 + $1.notes.count } }

    // MARK: 阅读记录

    private var sessionsKey: String { "reading.sessions." + owner }

    func loadSessions() {
        guard let data = UserDefaults.standard.data(forKey: sessionsKey),
              let value = try? JSONDecoder().decode([ReadingSession].self, from: data) else { sessions = []; return }
        sessions = value
    }

    /// 同一本书、同一种方式（读 / 听）在 3 分钟内的连续活动合并为一条记录；最多保留最近 3000 条。
    func appendSession(seconds: Double, bookID: String, title: String, listening: Bool) {
        let now = Date()
        var list = sessions
        if let last = list.last, last.bookID == bookID, last.listening == listening, now.timeIntervalSince(last.end) < 180,
           Calendar.current.isDate(last.start, inSameDayAs: now) {
            list[list.count - 1].end = now
            list[list.count - 1].seconds += seconds
        } else {
            let name = title.isEmpty ? (entries.first { $0.id == bookID }?.title ?? "") : title
            list.append(ReadingSession(bookID: bookID, title: name, start: now.addingTimeInterval(-seconds), end: now, seconds: seconds, listening: listening))
        }
        if list.count > 3000 { list.removeFirst(list.count - 3000) }
        sessions = list
        scheduleSessionsSave()
    }

    func scheduleSessionsSave() {
        sessionsDirty = true
        sessionsSaveTask?.cancel()
        sessionsSaveTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            self?.flushSessionsSave()
        }
    }

    func flushSessionsSave() {
        sessionsSaveTask?.cancel()
        sessionsSaveTask = nil
        guard sessionsDirty else { return }
        sessionsDirty = false
        UserDefaults.standard.set(readingSeconds, forKey: "reading.seconds." + owner)
        if let data = try? JSONEncoder().encode(sessions) {
            UserDefaults.standard.set(data, forKey: sessionsKey)
        }
    }
}

// MARK: - 隐私锁

enum PrivacyLock {
    /// 面容 ID / 触控 ID，失败或不可用时退回设备密码。没有设置任何密码的设备直接放行（无从验证）。
    @MainActor
    static func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return error?.code == LAError.passcodeNotSet.rawValue }
        return (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }

    static var biometryName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return "面容 ID"
        case .touchID: return "触控 ID"
        case .opticID: return "Optic ID"
        default: return "设备密码"
        }
    }
}

/// 应用锁：开启后，启动或从后台回来时先验证身份再显示书库。
struct AppLockGate: ViewModifier {
    @AppStorage("privacy.appLock") private var enabled = false
    @Environment(\.scenePhase) private var phase
    @State private var locked = true
    @State private var checking = false
    func body(content: Content) -> some View {
        content
            .overlay {
                if enabled && locked {
                    ZStack {
                        Rectangle().fill(.ultraThickMaterial).ignoresSafeArea()
                        VStack(spacing: 18) {
                            Image(systemName: Icon.lock(true)).font(.system(size: 40, weight: .medium)).foregroundStyle(Theme.accent)
                            Text("听页已上锁").font(.title2.weight(.bold))
                            Button("用\(PrivacyLock.biometryName)解锁") { Task { await unlock() } }
                                .buttonStyle(PrimaryButtonStyle())
                                .frame(width: 220)
                        }
                    }
                    .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.2), value: locked)
            .task { if enabled { await unlock() } }
            // 刚在设置里开启时不立即上锁，下次进入后台才生效
            .onChange(of: enabled) { _, on in if on { locked = false } }
            .onChange(of: phase) { _, value in
                guard enabled else { return }
                if value == .background { locked = true }
                if value == .active, locked { Task { await unlock() } }
            }
    }
    @MainActor private func unlock() async {
        guard !checking else { return }
        checking = true; defer { checking = false }
        if await PrivacyLock.authenticate(reason: "解锁听页") { locked = false }
    }
}
