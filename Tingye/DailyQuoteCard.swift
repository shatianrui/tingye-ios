import SwiftUI

/// 今日一句：每天从书库轮换一本，摘出其中一句；「从这句读」一次性定位到原文（`AppModel.readerJump`）。
/// 显示在统计页的「日」视图。
struct DailyQuoteCard: View {
    @EnvironmentObject var model: AppModel
    /// 兼容历史调用；专注版不显示装饰编号。
    var number: String? = nil
    @State private var quote: DailyQuote?

    /// 每天固定轮换一本，而不是总是第一本。
    private var pick: ShelfEntry? {
        let rows = model.visibleEntries.filter { $0.local && !$0.isComic }
        guard !rows.isEmpty else { return nil }
        let day = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0
        return rows[day % rows.count]
    }

    var body: some View {
        if let entry = pick {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle(text: "今日一句", number: number)
                ThemeIcon(symbol: Icon.quote, size: 22, weight: .regular)
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)
                Group {
                    if let quote, quote.entryID == entry.id {
                        Text(quote.text)
                    } else {
                        Text("《\(entry.title)》").redacted(reason: quote == nil ? .placeholder : [])
                    }
                }
                .font(Theme.serif(20, relativeTo: .title3))
                .lineSpacing(8)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(Theme.ink)
                Text("—— " + sourceLine(entry))
                    .font(.caption)
                    .foregroundStyle(Theme.ink2)
                    .lineLimit(2)
                HStack(spacing: 10) {
                    Button {
                        Haptics.light()
                        if let quote, quote.entryID == entry.id { model.open(entry, chapter: quote.chapter, position: quote.position) }
                        else { model.open(entry) }
                    } label: { Text(quote?.entryID == entry.id ? "从这句读" : "开始阅读") }
                    .buttonStyle(PrimaryButtonStyle(height: 44))
                    Button { model.listen(entry.id) } label: { Text("听这本书") }
                    .buttonStyle(SecondaryButtonStyle(height: 44))
                }
                .padding(.top, 2)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.hero, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .contextMenu {
                Button { model.open(entry) } label: { Label(entry.started ? "继续阅读" : "开始阅读", systemImage: Icon.read) }
                Button { model.listen(entry.id) } label: { Label("听书", systemImage: Icon.listen) }
            }
            .task(id: entry.id + AppModel.dayKey(Date())) { await loadQuote(entry) }
        }
    }

    private func sourceLine(_ entry: ShelfEntry) -> String {
        guard let quote, quote.entryID == entry.id else { return "《\(entry.title)》· \(entry.author)" }
        return "《\(entry.title)》第 \(quote.chapter + 1) 章 · \(quote.chapterTitle)"
    }

    /// 在后台切句，挑一句长度适中的话；同一天同一本书总是同一句。
    private func loadQuote(_ entry: ShelfEntry) async {
        guard let book = try? await model.loadBook(entry.id) else { quote = nil; return }
        let day = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0
        let box = BookBox(book: book)
        quote = await Task.detached(priority: .utility) { DailyQuote.pick(from: box.book, seed: day) }.value
    }
}

private struct BookBox: @unchecked Sendable { let book: Book }

/// 今日一句：书中的一句原文及其位置（章 + 句序号，与阅读进度同一坐标）。
struct DailyQuote: Equatable, Sendable {
    let entryID: String
    let chapter: Int
    let position: Int
    let chapterTitle: String
    let text: String

    /// 取前 40 章里 12–60 字、不以标点开头的句子，按日期种子轮换。
    static func pick(from book: Book, seed: Int) -> DailyQuote? {
        var candidates: [DailyQuote] = []
        for (index, chapter) in book.chapters.prefix(40).enumerated() {
            for sentence in Sentence.split(chapter.text) {
                let text = sentence.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard (12...60).contains(text.count), let first = text.unicodeScalars.first,
                      !CharacterSet.punctuationCharacters.contains(first) else { continue }
                candidates.append(DailyQuote(entryID: book.id, chapter: index, position: sentence.id, chapterTitle: chapter.title, text: text))
                if candidates.count >= 400 { break }
            }
            if candidates.count >= 400 { break }
        }
        guard !candidates.isEmpty else { return nil }
        return candidates[abs(seed &* 7919) % candidates.count]
    }
}
