import SwiftUI

/// 读完收尾页（v29「书房」阶段二）：读完感 + 今日一句 + 本书统计一行 + 下一本。
///
/// 统计口径与统计页同源：本书总时长与天数都从 `model.visibleSessions` 按书汇总
/// （与 StatsView「与这些书相伴」的排行算法一致，读与听都计入），分钟取整与 NowView 的今日分钟一致。
/// 读完感的存储：优先走既有划线 API——把读完感作为一条带 note 的 Highlight 存进本书摘记
/// （挂在今日一句的位置上），其 id 指针存 @AppStorage 同名键以便回读与修改；
/// 当既没有划线也没有可定位的句子时，降级为 @AppStorage 按书存纯文本。
struct BookFinishView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    let entry: ShelfEntry
    /// 打开下一本（由阅读器提供：先关收尾页与本书，再开下一本）。
    var onOpenNext: (ShelfEntry) -> Void = { _ in }
    /// 回到书库（由阅读器提供：关闭本书）。
    var onCloseBook: () -> Void = {}

    private struct QuoteCandidate { let text: String; let chapter: Int?; let position: Int? }
    @State private var quotes: [QuoteCandidate] = []
    @State private var quoteIndex = 0
    @State private var finishNote = ""
    @State private var noteSaved = false
    @State private var loaded = false

    private static let fallbackQuote = "把日子过慢一点，让喜欢的文字多停留一会儿。"

    // MARK: 与统计页同源的本书数字

    private var bookSessions: [ReadingSession] { model.visibleSessions.filter { $0.bookID == entry.id } }
    private var totalSeconds: Double { bookSessions.reduce(0) { $0 + $1.seconds } }
    private var readingDays: Int { Set(bookSessions.map { AppModel.dayKey($0.start) }).count }
    private var statsLine: String {
        "共读 \(readingDays) 天 · \(Int(totalSeconds / 60)) 分钟 · \(entry.notes.count) 条摘记"
    }

    /// 下一本：与 NowView「待读清单」完全相同的选择（本地、未开卷、按加入时间倒序的第一本）。
    private var nextEntry: ShelfEntry? {
        model.visibleEntries.filter { $0.local && !$0.started && $0.id != entry.id }
            .sorted { ($0.addedAt ?? 0) > ($1.addedAt ?? 0) }.first
    }

    private var currentQuote: QuoteCandidate? { quotes.indices.contains(quoteIndex) ? quotes[quoteIndex] : nil }
    private var quoteText: String { currentQuote?.text ?? Self.fallbackQuote }
    private var quoteChapterLabel: String {
        guard let chapter = currentQuote?.chapter else { return "" }
        return "第 \(chapter + 1) 章"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    quoteCard
                    finishNoteSection
                    nextSection
                }
                .padding(.horizontal, Theme.inset).padding(.top, 10).padding(.bottom, 24)
                .frame(maxWidth: 680).frame(maxWidth: .infinity)
            }
            .paperBackground()
            .navigationTitle("读完")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .task { await loadContent() }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            BookCoverView(title: entry.title, color: entry.color, author: entry.author, image: model.covers[entry.id], width: 84)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                Text("全书读完").font(.caption).foregroundStyle(Theme.accent)
                Text(entry.title).font(Theme.serifSemibold(23, relativeTo: .title2)).foregroundStyle(Theme.ink)
                Text(entry.author.isEmpty ? L("佚名") : entry.author).font(.caption).foregroundStyle(Theme.ink2)
                Text(statsLine).font(.caption).foregroundStyle(Theme.ink2)
                    .accessibilityIdentifier("finish.statsLine")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var quoteCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("今日一句").font(.caption2.weight(.medium))
                Spacer()
                if quotes.count > 1 {
                    Button { quoteIndex = (quoteIndex + 1) % quotes.count; noteSaved = false } label: {
                        Text("换一句").font(.caption).frame(minHeight: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("finish.quote.next")
                }
            }
            Text(quoteText).font(Theme.serifSemibold(20, relativeTo: .title3)).lineSpacing(7)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 16) {
                Text("《\(entry.title)》" + (quoteChapterLabel.isEmpty ? "" : " · \(quoteChapterLabel)"))
                    .font(.caption)
                Spacer()
                QuoteShareLink(text: quoteText, title: entry.title, author: entry.author, chapter: quoteChapterLabel) {
                    HStack(spacing: 6) { ThemeIcon(symbol: Icon.share, size: 16); Text("分享").underline() }
                        .font(.footnote.weight(.medium)).frame(minHeight: 44).contentShape(Rectangle())
                }
                .accessibilityIdentifier("finish.quote.share")
            }
        }
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.warm, in: RoundedRectangle(cornerRadius: Theme.heroRadius, style: .continuous))
        .foregroundStyle(Theme.onWarm)
    }

    private var finishNoteSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "读完感")
            TextEditor(text: $finishNote)
                .frame(minHeight: 110)
                .padding(8)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).strokeBorder(Theme.line, lineWidth: 1) }
                .onChange(of: finishNote) { _, _ in noteSaved = false }
                .accessibilityLabel("读完感")
            HStack {
                Button { saveFinishNote() } label: { Text(noteSaved ? "已保存" : "保存读完感") }
                    .buttonStyle(SecondaryButtonStyle(height: 44))
                    .disabled(finishNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !hasSavedNote)
                    .accessibilityIdentifier("finish.note.save")
                Spacer()
                Text("会存进本书摘记").font(.caption2).foregroundStyle(Theme.ink2)
            }
        }
    }

    @ViewBuilder
    private var nextSection: some View {
        if let next = nextEntry {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(title: "下一本")
                HStack(spacing: 14) {
                    BookCoverView(title: next.title, color: next.color, author: next.author, image: model.covers[next.id], width: 56)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(next.title).font(.subheadline.weight(.medium)).foregroundStyle(Theme.ink).lineLimit(2)
                        Text(next.author.isEmpty ? L("佚名") : next.author).font(.caption).foregroundStyle(Theme.ink2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Button { onOpenNext(next) } label: { Text("开始下一本") }
                    .buttonStyle(PrimaryButtonStyle(height: 50))
                    .accessibilityIdentifier("finish.next.open")
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("书库里还没有待读的书。").font(.subheadline).foregroundStyle(Theme.ink2)
                Button { dismiss(); onCloseBook() } label: { Text("回到书库") }
                    .buttonStyle(SecondaryButtonStyle(height: 50))
            }
        }
    }

    // MARK: 内容装载与读完感存取

    private var pointerKey: String { "study.finishNoteHighlight." + entry.id }
    private var textKey: String { "study.finishNoteText." + entry.id }
    private var hasSavedNote: Bool {
        if let raw = UserDefaults.standard.string(forKey: pointerKey), let uuid = UUID(uuidString: raw) {
            return entry.notes.contains { $0.id == uuid }
        }
        return UserDefaults.standard.string(forKey: textKey) != nil
    }

    private func loadContent() async {
        guard !loaded else { return }
        loaded = true
        loadFinishNote()
        var candidates: [QuoteCandidate] = entry.notes
            .sorted { $0.date > $1.date }
            .map { QuoteCandidate(text: $0.text, chapter: $0.chapter, position: $0.start) }
        if let book = try? await model.loadBook(entry.id) {
            let day = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0
            for seed in [day, day + 7, day + 13, day + 29] {
                if let quote = DailyQuote.pick(from: book, seed: seed),
                   !candidates.contains(where: { $0.text == quote.text }) {
                    candidates.append(QuoteCandidate(text: quote.text, chapter: quote.chapter, position: quote.position))
                }
                if candidates.count >= 6 { break }
            }
        }
        quotes = candidates.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private func loadFinishNote() {
        if let raw = UserDefaults.standard.string(forKey: pointerKey), let uuid = UUID(uuidString: raw),
           let existing = entry.notes.first(where: { $0.id == uuid }) {
            finishNote = existing.note ?? ""
        } else if let text = UserDefaults.standard.string(forKey: textKey) {
            finishNote = text
        }
    }

    private func saveFinishNote() {
        let text = finishNote.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            // 清空即删除：有挂靠的划线就删掉它，避免留下一条没有内容的摘记。
            if let raw = UserDefaults.standard.string(forKey: pointerKey), let uuid = UUID(uuidString: raw),
               entry.notes.contains(where: { $0.id == uuid }) {
                model.removeHighlight(entry.id, id: uuid)
            }
            UserDefaults.standard.removeObject(forKey: pointerKey)
            UserDefaults.standard.removeObject(forKey: textKey)
            noteSaved = true
            return
        }
        if let raw = UserDefaults.standard.string(forKey: pointerKey), let uuid = UUID(uuidString: raw),
           var existing = entry.notes.first(where: { $0.id == uuid }) {
            existing.note = text
            model.updateHighlight(entry.id, existing)
        } else if let quote = currentQuote, let chapter = quote.chapter, let position = quote.position {
            let highlight = Highlight(chapter: chapter, start: position, end: position, text: quote.text, note: text)
            model.addHighlight(entry.id, highlight)
            UserDefaults.standard.set(highlight.id.uuidString, forKey: pointerKey)
            UserDefaults.standard.removeObject(forKey: textKey)
        } else {
            // 降级：没有任何可定位的句子时，只按书存本地文本，不进摘记。
            UserDefaults.standard.set(text, forKey: textKey)
        }
        noteSaved = true
    }
}
