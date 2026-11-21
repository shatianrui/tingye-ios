import SwiftUI

/// 专注会话（v29「书房」阶段二）：状态机 + 开始页 + 结束小结。
///
/// 计时口径（硬性）：阅读时长统计继续由 TingyeApp 的 5 秒 `recordUsageTick` 独占记录，
/// 本文件只用开始时间与当前时间的差值算「还剩多久」，绝不写入任何 usage / session 统计，避免双计。
/// 会话状态存 UserDefaults（与 @AppStorage 同一存储），杀 App 后按规则恢复：
/// 未到时继续、已过时按到时完成、超过目标 12 小时视为作废。
final class FocusSessionStore: ObservableObject {
    enum Phase: String, Equatable { case idle, running, finished }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var bookID: String?
    @Published private(set) var targetMinutes: Int = 25
    @Published private(set) var startedAt: Date?
    @Published private(set) var endedAt: Date?
    @Published private(set) var chapterAtStart: Int = 0
    @Published private(set) var chapterAtEnd: Int = 0
    @Published private(set) var highlightsAtStart: Int = 0

    static let shared = FocusSessionStore()

    /// 入口开关与目标时长的 @AppStorage 键（开始页与阅读器「更多」共用）。
    static let enabledKey = "study.focusEnabled"
    static let targetKey = "study.focusTargetMinutes"

    private enum Key {
        static let phase = "study.focus.phase"
        static let bookID = "study.focus.bookID"
        static let startedAt = "study.focus.startedAt"
        static let endedAt = "study.focus.endedAt"
        static let chapterAtStart = "study.focus.chapterAtStart"
        static let chapterAtEnd = "study.focus.chapterAtEnd"
        static let highlightsAtStart = "study.focus.highlightsAtStart"
    }

    init() { restore() }

    // MARK: 状态机

    func start(bookID: String, chapter: Int, highlights: Int, targetMinutes: Int) {
        self.bookID = bookID
        self.targetMinutes = targetMinutes
        startedAt = Date()
        endedAt = nil
        chapterAtStart = chapter
        chapterAtEnd = chapter
        highlightsAtStart = highlights
        phase = .running
        persist()
    }

    /// 提前结束：以当前时刻结算，进小结。
    func finish(currentChapter: Int) {
        guard phase == .running else { return }
        endedAt = Date()
        chapterAtEnd = currentChapter
        phase = .finished
        persist()
    }

    /// 到时完成：由界面的定时刷新调用；不打断阅读，只把状态翻到小结待查看。
    func completeIfDue(currentChapter: Int) {
        guard phase == .running, let startedAt else { return }
        let due = startedAt.addingTimeInterval(Double(targetMinutes) * 60)
        guard Date() >= due else { return }
        endedAt = due
        chapterAtEnd = currentChapter
        phase = .finished
        persist()
    }

    /// 小结看完（继续读 / 合上书）：清掉会话。
    func dismissSummary() { clear() }

    /// 放弃：不生成小结，直接清掉。
    func abandon() { clear() }

    // MARK: 派生值

    func remaining(at date: Date = Date()) -> TimeInterval {
        guard phase == .running, let startedAt else { return 0 }
        return max(0, startedAt.addingTimeInterval(Double(targetMinutes) * 60).timeIntervalSince(date))
    }

    var sessionSeconds: Double {
        guard let startedAt else { return 0 }
        return max(0, (endedAt ?? Date()).timeIntervalSince(startedAt))
    }

    // MARK: 持久化

    private func persist() {
        let defaults = UserDefaults.standard
        defaults.set(phase.rawValue, forKey: Key.phase)
        defaults.set(targetMinutes, forKey: FocusSessionStore.targetKey)
        defaults.set(chapterAtStart, forKey: Key.chapterAtStart)
        defaults.set(chapterAtEnd, forKey: Key.chapterAtEnd)
        defaults.set(highlightsAtStart, forKey: Key.highlightsAtStart)
        if let bookID { defaults.set(bookID, forKey: Key.bookID) } else { defaults.removeObject(forKey: Key.bookID) }
        if let startedAt { defaults.set(startedAt, forKey: Key.startedAt) } else { defaults.removeObject(forKey: Key.startedAt) }
        if let endedAt { defaults.set(endedAt, forKey: Key.endedAt) } else { defaults.removeObject(forKey: Key.endedAt) }
    }

    private func clear() {
        phase = .idle
        bookID = nil
        startedAt = nil
        endedAt = nil
        chapterAtStart = 0
        chapterAtEnd = 0
        highlightsAtStart = 0
        let defaults = UserDefaults.standard
        for key in [Key.phase, Key.bookID, Key.startedAt, Key.endedAt, Key.chapterAtStart, Key.chapterAtEnd, Key.highlightsAtStart] {
            defaults.removeObject(forKey: key)
        }
    }

    private func restore() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: FocusSessionStore.targetKey) != nil {
            targetMinutes = defaults.integer(forKey: FocusSessionStore.targetKey)
        }
        guard let raw = defaults.string(forKey: Key.phase), let savedPhase = Phase(rawValue: raw),
              let id = defaults.string(forKey: Key.bookID),
              let start = defaults.object(forKey: Key.startedAt) as? Date else { phase = .idle; return }
        bookID = id
        startedAt = start
        chapterAtStart = defaults.integer(forKey: Key.chapterAtStart)
        chapterAtEnd = defaults.integer(forKey: Key.chapterAtEnd)
        highlightsAtStart = defaults.integer(forKey: Key.highlightsAtStart)
        switch savedPhase {
        case .idle:
            clear()
        case .finished:
            endedAt = defaults.object(forKey: Key.endedAt) as? Date
            phase = .finished
        case .running:
            let due = start.addingTimeInterval(Double(targetMinutes) * 60)
            if Date() > due.addingTimeInterval(12 * 3600) {
                clear()
            } else if Date() >= due {
                endedAt = due
                phase = .finished
                persist()
            } else {
                phase = .running
            }
        }
    }
}

// MARK: - 开始页 / 进行中 / 小结（同一 sheet 内按状态切换）

struct FocusStartView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: FocusSessionStore = .shared
    @AppStorage(FocusSessionStore.targetKey) private var savedTarget = 25
    @State private var mode = 1
    @State private var customMinutes = 30

    let entry: ShelfEntry?
    let bookID: String
    let bookTitle: String
    let chapter: Int
    let chapterTitle: String
    /// 在阅读器里关闭整本书（收尾动作），由调用方提供。
    var onCloseBook: () -> Void = {}

    private var effectiveMinutes: Int { mode == 0 ? 25 : mode == 1 ? 45 : customMinutes }

    var body: some View {
        NavigationStack {
            IndexPage {
                IndexHeading(title: Text("专注阅读"), detail: Text(verbatim: bookTitle), large: true)
                switch store.phase {
                case .finished:
                    FocusSummaryView(store: store, entry: entry, onContinue: { dismiss() }, onCloseBook: { dismiss(); onCloseBook() })
                case .running where store.bookID == bookID:
                    runningSection
                case .running:
                    otherBookSection
                case .idle:
                    startSection
                }
            }
            .tint(IndexTheme.accent)
            .navigationTitle("专注阅读")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
            .onAppear {
                if savedTarget == 25 { mode = 0 }
                else if savedTarget == 45 { mode = 1 }
                else { mode = 2; customMinutes = min(90, max(10, savedTarget)) }
            }
        }
    }

    private var startSection: some View {
        VStack(alignment: .leading, spacing: Theme.space5) {
            VStack(alignment: .leading, spacing: Theme.space2) {
                Text(bookTitle).font(IndexTheme.editorial(20, relativeTo: .title3)).foregroundStyle(IndexTheme.muted)
                Text(chapterTitle.isEmpty ? "第 \(chapter + 1) 章" : "第 \(chapter + 1) 章 · \(chapterTitle)")
                    .font(.caption).foregroundStyle(IndexTheme.muted)
            }
            IndexHeading(title: Text("专注时长"))
            IndexScopePicker(options: [0, 1, 2], selection: mode,
                         title: { Text(L(["25 分钟", "45 分钟", "自定义"][$0])) }, onSelect: { mode = $0 })
            if mode == 2 {
                Stepper(value: $customMinutes, in: 10...90, step: 5) {
                    Text("自定义 \(customMinutes) 分钟").font(.subheadline).foregroundStyle(IndexTheme.ink)
                }
            }
            Text("专注期间照常计入阅读统计，不会重复计。")
                .font(.caption).foregroundStyle(IndexTheme.muted)
            Button("开始专注") {
                Haptics.light()
                savedTarget = effectiveMinutes
                store.start(bookID: bookID, chapter: chapter, highlights: entry?.notes.count ?? 0, targetMinutes: effectiveMinutes)
                dismiss()
            }
            .buttonStyle(IndexActionStyle(role: .primary, expands: true))
            .accessibilityIdentifier("focus.start")
        }
    }

    private var runningSection: some View {
        VStack(alignment: .leading, spacing: Theme.space5) {
            Label("正在专注", systemImage: Icon.sleepTimer).font(.headline).foregroundStyle(IndexTheme.accent)
            TimelineView(.periodic(from: .now, by: 15)) { context in
                timerFace(seconds: store.remaining(at: context.date),
                          progress: 1 - store.remaining(at: context.date) / Double(max(1, store.targetMinutes) * 60))
                    .accessibilityLabel(remainingLabel(at: context.date))
                    .onChange(of: context.date) { _, _ in store.completeIfDue(currentChapter: chapter) }
            }
            Text("目标 \(store.targetMinutes) 分钟 · 从第 \(store.chapterAtStart + 1) 章开始")
                .font(.caption).foregroundStyle(IndexTheme.muted)
            Button {
                store.finish(currentChapter: chapter)
            } label: { Text("结束专注") }
            .buttonStyle(IndexActionStyle(role: .secondary, expands: true))
            .accessibilityIdentifier("focus.finish")
            Button { store.abandon(); dismiss() } label: {
                Text("放弃这次专注").frame(minHeight: Theme.iconButtonSize).contentShape(Rectangle())
            }
            .buttonStyle(.plain).font(.caption).foregroundStyle(IndexTheme.muted)
        }
    }

    private var otherBookSection: some View {
        VStack(alignment: .leading, spacing: Theme.space5) {
            IndexStatus(kind: .empty, title: Text("正在专注另一本书"), detail: Text("结束或放弃上一场专注后，就可以为这本书开始新的会话。"))
            Button { store.finish(currentChapter: store.chapterAtEnd) } label: { Text("结束那次专注") }
                .buttonStyle(IndexActionStyle(role: .primary, expands: true))
            Button { store.abandon(); } label: {
                Text("放弃那次专注").frame(minHeight: Theme.iconButtonSize).contentShape(Rectangle())
            }
            .buttonStyle(.plain).font(.caption).foregroundStyle(IndexTheme.muted)
        }
    }

    /// The existing store has no pause state. This face only presents elapsed progress.
    private func timerFace(seconds: Double, progress: Double) -> some View {
        VStack(alignment: .leading, spacing: Theme.space3) {
            IndexMetric(value: Text(verbatim: StatsView.clock(seconds)), label: Text("剩余时间"), large: true)
            ProgressView(value: min(1, max(0, progress))).tint(IndexTheme.accent)
                .accessibilityHidden(true)
        }
        .padding(Theme.space4)
        .indexPanel(fill: IndexTheme.wash)
    }

    private func remainingLabel(at date: Date) -> String {
        let seconds = store.remaining(at: date)
        if seconds <= 60 { return L("还剩不足 1 分钟") }
        return String(format: L("还剩 %lld 分钟"), Int(ceil(seconds / 60)))
    }
}

// MARK: - 结束小结

struct FocusSummaryView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var store: FocusSessionStore
    let entry: ShelfEntry?
    var onContinue: () -> Void = {}
    var onCloseBook: () -> Void = {}

    private var minutesText: String {
        let seconds = store.sessionSeconds
        if seconds < 60 { return L("不足 1 分钟") }
        return String(format: L("%lld 分钟"), Int(seconds / 60))
    }
    private var newHighlights: Int? {
        guard let entry else { return nil }
        let diff = entry.notes.count - store.highlightsAtStart
        return diff > 0 ? diff : nil
    }
    /// 今日一句：优先本次书最近一条划线；其次按 DailyQuote 的现成选句；都没有时用统计页同款寄语兜底。
    private var quoteText: String {
        if let latest = entry?.notes.max(by: { $0.date < $1.date }), !latest.text.isEmpty { return latest.text }
        if let book = model.selectedBook, book.id == entry?.id,
           let quote = DailyQuote.pick(from: book, seed: Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0) { return quote.text }
        return L("把日子过慢一点，让喜欢的文字多停留一会儿。")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.space4) {
            SettingsGroup(title: "专注完成") {
                IndexMetric(value: Text(verbatim: minutesText), label: Text("专注时长"), large: true)
                Text("读到第 \(store.chapterAtEnd + 1) 章").font(.subheadline)
                if let newHighlights {
                    Text("新增 \(newHighlights) 条摘记").font(.caption).foregroundStyle(IndexTheme.muted)
                }
            }
            SettingsGroup(title: "今日一句") {
                Text(verbatim: quoteText).font(IndexTheme.editorial(20, relativeTo: .title3)).lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true).padding(.vertical, Theme.space2)
            }
            Button("继续读") { store.dismissSummary(); onContinue() }
                .buttonStyle(IndexActionStyle(role: .primary, expands: true))
                .accessibilityIdentifier("focus.summary.continue")
            Button("合上书") { store.dismissSummary(); onCloseBook() }
                .buttonStyle(IndexActionStyle(role: .secondary, expands: true))
                .accessibilityIdentifier("focus.summary.closeBook")
        }
    }
}
