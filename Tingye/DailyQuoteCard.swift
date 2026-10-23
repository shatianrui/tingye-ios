import SwiftUI
import Pow

/// 今日一句：每天从书库轮换一本，摘出其中一句；「从这句读」一次性定位到原文（`AppModel.readerJump`）。
/// 显示在统计页的「日」视图。
struct DailyQuoteCard: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                Text("“").font(Theme.serifBold(52, relativeTo: .largeTitle)).foregroundStyle(Theme.accent)
                    .frame(height: 30, alignment: .top)
                    .accessibilityHidden(true)
                Group {
                    if let quote, quote.entryID == entry.id {
                        Text(quote.text)
                    } else {
                        Text("《\(entry.title)》").redacted(reason: quote == nil ? .placeholder : [])
                    }
                }
                .font(Theme.serif(20, relativeTo: .title3))
                .serifEmbolden(20)
                .lineSpacing(8)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(Theme.ink)
                .changeEffect(.shine(duration: 1.0), value: quote == nil, isEnabled: !reduceMotion)
                Text("—— " + sourceLine(entry))
                    .font(Theme.serif(13, relativeTo: .caption))
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
                if let quote, quote.entryID == entry.id {
                    QuoteShareLink(text: quote.text, title: entry.title, author: entry.author, chapter: quote.chapterTitle) {
                        HStack(spacing: 6) { ThemeIcon(symbol: Icon.share, size: 16); Text("分享摘句卡片") }
                            .font(.footnote.weight(.medium)).foregroundStyle(Theme.accent)
                            .frame(minHeight: 44)
                    }
                    .accessibilityIdentifier("quote.share")
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            // 刊内摘句框：浅灰平底、零圆角，与封面卡同一语汇
            .background(Theme.surface2)
            .contextMenu {
                Button { model.open(entry) } label: { Label(entry.started ? "继续阅读" : "开始阅读", systemImage: Icon.read) }
                Button { model.listen(entry.id) } label: { Label("听书", systemImage: Icon.listen) }
                if let quote, quote.entryID == entry.id {
                    QuoteShareLink(text: quote.text, title: entry.title, author: entry.author, chapter: quote.chapterTitle) {
                        Label("分享摘句卡片", systemImage: Icon.share)
                    }
                }
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

// MARK: - 摘句卡片（分享图）

/// 刊式摘句卡：宣纸白、报头双线、靛蓝引号与题条。导出为图片分享，始终使用日间配色。
struct QuoteShareCard: View {
    let text: String
    let title: String
    var author = ""
    var chapter = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("TINGYE · 听页")
                Spacer()
                Text(Date().formatted(.dateTime.year().month(.twoDigits).day(.twoDigits)))
            }
            .font(.system(size: 13, weight: .bold).width(.expanded)).tracking(1.4)
            .foregroundStyle(Color(hex: 0x1F1F1F))
            Rectangle().fill(Color(hex: 0x1F1F1F)).frame(height: 4).padding(.top, 10)
            Rectangle().fill(Color(hex: 0x1F1F1F)).frame(height: 1).padding(.top, 4)
            Spacer(minLength: 48)
            Text("“").font(.system(size: 120, weight: .bold, design: .serif)).foregroundStyle(Theme.clay)
                .frame(height: 80, alignment: .top).offset(x: -6)
            Text(text)
                .font(Theme.serifBold(quoteSize)).lineSpacing(quoteSize * 0.4)
                .foregroundStyle(Color(hex: 0x1F1F1F))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 48)
            Rectangle().fill(Theme.clay).frame(width: 120, height: 12)
            Text("《\(title)》").font(Theme.serifBold(26)).foregroundStyle(Color(hex: 0x1F1F1F)).padding(.top, 20)
            let byline = [author, chapter].filter { !$0.isEmpty }.joined(separator: " · ")
            if !byline.isEmpty {
                Text(byline).font(.system(size: 18)).foregroundStyle(Color(hex: 0x666666)).padding(.top, 6)
            }
            Rectangle().fill(Color(hex: 0x1F1F1F)).frame(height: 1).padding(.top, 28)
        }
        .padding(64)
        .frame(width: 900, alignment: .leading)
        .frame(minHeight: 1125, alignment: .top)
        .background(Color(hex: 0xFFFFFF))
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
