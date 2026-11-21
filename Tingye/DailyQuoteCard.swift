import SwiftUI

/// 今日一句：每天从书库轮换一本，摘出其中一句；「从这句读」一次性定位到原文（`AppModel.readerJump`）。
/// 在书库与我的概览提供本书摘句。
struct DailyQuoteCard: View {
    @EnvironmentObject var model: AppModel
    /// 兼容历史调用；专注版不显示装饰编号。
    var number: String? = nil
    var compact = false
    @State private var quote: DailyQuote?
    @State private var loadedEntryID: String?
    @State private var failedEntryID: String?
    @State private var retryQuote = 0

    /// 每天固定轮换一本，而不是总是第一本。
    private var pick: ShelfEntry? {
        let rows = model.visibleEntries.filter { $0.local && !$0.isComic }
        guard !rows.isEmpty else { return nil }
        let day = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0
        return rows[day % rows.count]
    }

    var body: some View {
        if let entry = pick {
            VStack(alignment: .leading, spacing: Theme.space3) {
                IndexHeading(title: Text("今日摘句"))
                if let quote, quote.entryID == entry.id {
                    Text(verbatim: quote.text)
                        .font(IndexTheme.editorial(21, relativeTo: .title3)).lineSpacing(6)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("《\(entry.title)》第 \(quote.chapter + 1) 章 · \(quote.chapterTitle)").font(.caption).foregroundStyle(IndexTheme.muted)
                    QuoteShareLink(text: quote.text, title: entry.title, author: entry.author, chapter: quote.chapterTitle) {
                        IndexActionLabel(title: "分享摘句卡片", symbol: Icon.share)
                    }
                    .buttonStyle(IndexActionStyle())
                    .accessibilityIdentifier("quote.share")
                } else {
                    Text(verbatim: entry.title).font(.headline)
                    if loadedEntryID != entry.id {
                        IndexStatus(kind: .loading, title: Text("正在载入摘句"))
                    } else if failedEntryID == entry.id {
                        IndexStatus(kind: .failure, title: Text("暂时无法读取摘句"))
                        Button("重试") { retryQuote += 1 }.buttonStyle(IndexActionStyle(role: .secondary))
                    } else {
                        IndexStatus(kind: .empty, title: Text("这本书暂无可分享的摘句"))
                    }
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Theme.space2) { quoteActions(entry) }.fixedSize(horizontal: true, vertical: false)
                    VStack(alignment: .leading, spacing: Theme.space1) { quoteActions(entry) }
                }
            }
            .foregroundStyle(IndexTheme.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.space4)
            .indexPanel(fill: IndexTheme.wash)
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
            .task(id: "\(entry.id):\(AppModel.dayKey(Date())):\(retryQuote)") { await loadQuote(entry) }
        }
    }

    @ViewBuilder private func quoteActions(_ entry: ShelfEntry) -> some View {
        Button(quote?.entryID == entry.id ? "从这句读" : "开始阅读") {
            Haptics.light()
            if let quote, quote.entryID == entry.id { model.open(entry, target: .init(chapter: quote.chapter, position: quote.position, anchor: .init(quote: quote.text))) }
            else { model.open(entry) }
        }
        .buttonStyle(IndexActionStyle(role: .primary))
        if !compact {
            Button("听这本书") { model.listen(entry.id) }.buttonStyle(IndexActionStyle(role: .secondary))
        }
    }

    /// 在后台切句，挑一句长度适中的话；同一天同一本书总是同一句。
    private func loadQuote(_ entry: ShelfEntry) async {
        loadedEntryID = nil
        failedEntryID = nil
        defer { if !Task.isCancelled { loadedEntryID = entry.id } }
        guard let book = try? await model.loadBook(entry.id) else {
            if !Task.isCancelled {
                quote = nil
                failedEntryID = entry.id
            }
            return
        }
        let day = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0
        let box = BookBox(book: book)
        let picked = await Task.detached(priority: .utility) { DailyQuote.pick(from: box.book, seed: day) }.value
        if !Task.isCancelled { quote = picked }
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

/// 摘句分享图沿用暖纸、深绿与书目说明，导出使用日间色。
struct QuoteShareCard: View {
    let text: String
    let title: String
    var author = ""
    var chapter = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack(alignment: .firstTextBaseline) {
                Text("听页 · 阅读摘句").font(.system(size: 18, weight: .medium))
                Spacer()
                Text(Date().formatted(.dateTime.year().month(.twoDigits).day(.twoDigits)))
                    .font(.system(size: 16))
            }.foregroundStyle(Color(hex: 0x545D53))
            Capsule().fill(Color(hex: 0x2D594B)).frame(width: 36, height: 3)
            Text(text)
                .font(Theme.serifBold(quoteSize)).lineSpacing(quoteSize * 0.4)
                .foregroundStyle(Color(hex: 0x232823))
                .fixedSize(horizontal: false, vertical: true).padding(.vertical, 36)
            VStack(alignment: .leading, spacing: 10) {
                Text("《\(title)》").font(Theme.serifBold(26)).foregroundStyle(Color(hex: 0x232823))
                let byline = [author, chapter].filter { !$0.isEmpty }.joined(separator: " · ")
                if !byline.isEmpty {
                    Text(byline).font(.system(size: 18)).foregroundStyle(Color(hex: 0x545D53))
                }
            }
            Spacer(minLength: 48)
            Rectangle().fill(Color(hex: 0xD9D5C8)).frame(height: 1)
        }
        .padding(64)
        .frame(width: 900, alignment: .leading)
        .frame(minHeight: 1125, alignment: .top)
        .background(Color(hex: 0xF5F1E8))
        .environment(\.colorScheme, .light)
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
