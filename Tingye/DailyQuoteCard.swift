import SwiftUI

/// 今日一句：每天从书库轮换一本，摘出其中一句；「从这句读」一次性定位到原文（`AppModel.readerJump`）。
/// 显示在统计页的「日」视图。
struct DailyQuoteCard: View {
    @EnvironmentObject var model: AppModel
    /// 兼容历史调用；专注版不显示装饰编号。
    var number: String? = nil
    var compact = false
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
            VStack(alignment: .leading, spacing: Theme.space4) {
                VStack(alignment: .leading, spacing: Theme.space3) {
                    Text("今日摘句").mastheadStyle()
                    Group {
                        if let quote, quote.entryID == entry.id { Text(quote.text) }
                        else { Text("《\(entry.title)》").redacted(reason: quote == nil ? .placeholder : []) }
                    }
                    .font(Theme.serif(20, relativeTo: .title3))
                    .lineSpacing(Theme.space2)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(Theme.ink)
                    Text("—— " + sourceLine(entry))
                        .font(Theme.sans(13)).foregroundStyle(Theme.ink3)
                        .lineLimit(2)
                }
                .padding(.leading, Theme.space4)
                .overlay(alignment: .leading) { Rectangle().fill(Theme.clay).frame(width: Theme.ruleHeavy) }
                if !compact {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: Theme.space3) { quoteActions(entry) }
                        VStack(spacing: Theme.space3) { quoteActions(entry) }
                    }
                    if let quote, quote.entryID == entry.id {
                        QuoteShareLink(text: quote.text, title: entry.title, author: entry.author, chapter: quote.chapterTitle) {
                            Label { Text("分享摘句卡片") } icon: { ThemeIcon(symbol: Icon.share, size: 16) }
                                .font(Theme.sans(15)).foregroundStyle(Theme.clayDeep)
                                .frame(minHeight: Theme.iconButtonSize)
                        }
                        .accessibilityIdentifier("quote.share")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contextMenu {
                Button { model.open(entry) } label: { Label { Text(entry.started ? "继续阅读" : "开始阅读") } icon: { ThemeIcon(symbol: Icon.read) } }
                Button { model.listen(entry.id) } label: { Label { Text("听书") } icon: { ThemeIcon(symbol: Icon.listen) } }
                if let quote, quote.entryID == entry.id {
                    QuoteShareLink(text: quote.text, title: entry.title, author: entry.author, chapter: quote.chapterTitle) {
                        Label { Text("分享摘句卡片") } icon: { ThemeIcon(symbol: Icon.share) }
                    }
                }
            }
            .accessibilityAction(named: "从这句读") {
                if let quote, quote.entryID == entry.id { model.open(entry, target: .init(chapter: quote.chapter, position: quote.position, anchor: .init(quote: quote.text))) }
                else { model.open(entry) }
            }
            .task(id: entry.id + AppModel.dayKey(Date())) { await loadQuote(entry) }
        }
    }

    @ViewBuilder private func quoteActions(_ entry: ShelfEntry) -> some View {
        PrimaryButton(quote?.entryID == entry.id ? "从这句读" : "开始阅读") {
            Haptics.light()
            if let quote, quote.entryID == entry.id { model.open(entry, target: .init(chapter: quote.chapter, position: quote.position, anchor: .init(quote: quote.text))) }
            else { model.open(entry) }
        }
        SecondaryButton("听这本书") { model.listen(entry.id) }
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

// MARK: - 摘句卡片（分享图）

/// 摘句分享海报固定为放映厅深色，不随接收者的系统外观变化。
struct QuoteShareCard: View {
    let text: String
    let title: String
    var author = ""
    var chapter = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            HStack {
                Label("听页 · 封面放映厅", systemImage: "film")
                    .font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.marker)
                Spacer()
                Text(Date().formatted(.dateTime.year().month(.twoDigits).day(.twoDigits)))
                    .font(.system(size: 16)).monospacedDigit().foregroundStyle(Theme.ink3)
            }
            Rectangle().fill(Theme.line).frame(height: 1)
            Text(text)
                .font(Theme.serifBold(quoteSize)).lineSpacing(quoteSize * 0.4)
                .fixedSize(horizontal: false, vertical: true).padding(.vertical, 36)
            VStack(alignment: .leading, spacing: 10) {
                Rectangle().fill(Theme.marker).frame(width: 56, height: 4)
                Text("《\(title)》").font(Theme.serifBold(26))
                let byline = [author, chapter].filter { !$0.isEmpty }.joined(separator: " · ")
                if !byline.isEmpty {
                    Text(byline).font(.system(size: 18)).foregroundStyle(Theme.ink3)
                }
            }
            Spacer(minLength: 48)
            Rectangle().fill(Theme.line).frame(height: 1)
            Text("TINGYE · SCREENING ROOM").font(.system(size: 14, weight: .semibold)).tracking(2.5)
                .foregroundStyle(Theme.marker)
        }
        .padding(64)
        .frame(width: 900, alignment: .leading)
        .frame(minHeight: 1125, alignment: .top)
        .foregroundStyle(Theme.ink)
        .background(Theme.bg)
        .environment(\.colorScheme, .dark)
    }

    /// 渲染为分享图；失败返回 nil（调用方退回纯文字分享）。
    /// 短句放大成海报字号，长句回落，保证一屏内可读。
    private var quoteSize: CGFloat { text.count <= 24 ? 52 : text.count <= 60 ? 42 : 34 }

    @MainActor func render() -> UIImage? {
        let renderer = ImageRenderer(content: self)
        renderer.scale = 2
        return renderer.uiImage
    }
}

/// 分享摘句：有图时分享卡片图片，否则分享纯文字。
struct QuoteShareLink<Label: View>: View {
    let text: String
    let title: String
    var author = ""
    var chapter = ""
    @ViewBuilder var label: Label
    var body: some View {
        let card = QuoteShareCard(text: text, title: title, author: author, chapter: chapter)
        if let image = card.render() {
            ShareLink(item: Image(uiImage: image), preview: SharePreview("《\(title)》摘句", image: Image(uiImage: image))) { label }
        } else {
            ShareLink(item: "“\(text)”——《\(title)》") { label }
        }
    }
}
