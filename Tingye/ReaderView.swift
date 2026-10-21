import SwiftUI
import CoreText
import PDFKit

enum NativeTypesetter {
    static func attributed(_ chapter: Chapter, preferences: ReaderPreferences) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = preferences.lineSpacing
        paragraph.paragraphSpacing = preferences.paragraphSpacing
        paragraph.firstLineHeadIndent = preferences.indent ? preferences.fontSize * 2 : 0
        paragraph.alignment = preferences.justified ? .justified : .left
        var attributes: [NSAttributedString.Key: Any] = [.font: preferences.uiFont, .foregroundColor: UIColor(preferences.foreground), .paragraphStyle: paragraph]
        if preferences.letterSpacing != 0 { attributes[.kern] = preferences.letterSpacing }
        let string = NSMutableAttributedString(string: ChineseConvert.apply(chapter.text, preferences.convert), attributes: attributes)
        for value in chapter.fields["marks"]?.array ?? [] {
            guard let mark = value.object, let start = mark["start"]?.int, let end = mark["end"]?.int, start >= 0, end > start, end <= string.length else { continue }
            var traits: UIFontDescriptor.SymbolicTraits = []
            if mark["bold"]?.bool == true { traits.insert(.traitBold) }
            if mark["italic"]?.bool == true { traits.insert(.traitItalic) }
            if let descriptor = preferences.uiFont.fontDescriptor.withSymbolicTraits(traits) { string.addAttribute(.font, value: UIFont(descriptor: descriptor, size: preferences.fontSize), range: NSRange(location: start, length: end - start)) }
        }
        return string
    }
    static func pages(_ string: NSAttributedString, size: CGSize) -> [NSRange] {
        guard string.length > 0, size.width > 40, size.height > 40 else { return [NSRange(location: 0, length: string.length)] }
        let setter = CTFramesetterCreateWithAttributedString(string)
        let path = CGPath(rect: CGRect(origin: .zero, size: size), transform: nil)
        var result: [NSRange] = [], start = 0
        while start < string.length {
            let frame = CTFramesetterCreateFrame(setter, CFRange(location: start, length: 0), path, nil)
            let visible = CTFrameGetVisibleStringRange(frame)
            var length = visible.length
            if length <= 0 { length = (string.string as NSString).rangeOfComposedCharacterSequence(at: start).length }
            result.append(NSRange(location: start, length: length)); start += length
        }
        return result
    }
    /// 截取一页文字。页首落在段落中间时，单独排版会把它当作段首加上首行缩进，与分页时的宽度不符，页尾的字会被挤出画面，所以去掉这一行的缩进。
    static func page(_ string: NSAttributedString, range: NSRange) -> NSAttributedString {
        let page = string.attributedSubstring(from: range)
        guard range.location > 0, page.length > 0 else { return page }
        let previous = (string.string as NSString).character(at: range.location - 1)
        guard let scalar = Unicode.Scalar(previous), !CharacterSet.newlines.contains(scalar) else { return page }
        let result = NSMutableAttributedString(attributedString: page)
        let first = (page.string as NSString).paragraphRange(for: NSRange(location: 0, length: 0))
        result.enumerateAttribute(.paragraphStyle, in: first) { value, subrange, _ in
            guard let style = (value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle else { return }
            style.firstLineHeadIndent = style.headIndent
            result.addAttribute(.paragraphStyle, value: style, range: subrange)
        }
        return result
    }
}

enum SpeechHighlight {
    static func apply(to source: NSAttributedString, sentence: NSRange?, monochrome: Bool = false, color: UIColor? = nil) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: source)
        let full = NSRange(location: 0, length: result.length)
        if let sentence { let range = NSIntersectionRange(sentence, full); if range.length > 0 { result.addAttribute(.backgroundColor, value: color ?? (monochrome ? UIColor.lightGray : UIColor(Theme.wash)), range: range) } }
        return result
    }
}

/// 一本书在阅读页中的只读缓存：章节数组、PDF 数据和逐章句子只解析一次。
@MainActor
final class ReaderDocument: ObservableObject {
    let book: Book
    let chapters: [Chapter]
    let isPDF: Bool
    private(set) lazy var pdf: Data? = isPDF ? book.pdf : nil
    private var sentenceCache: [Int: [Sentence]] = [:]
    init(book: Book) { self.book = book; chapters = book.chapters; isPDF = book.fields["pdf"] != nil }
    func sentences(_ index: Int) -> [Sentence] {
        if let cached = sentenceCache[index] { return cached }
        let value = chapters.indices.contains(index) ? Sentence.split(chapters[index].text) : []
        sentenceCache[index] = value; return value
    }
}

private struct UncheckedBox<T>: @unchecked Sendable { let value: T }

struct ReaderView: View {
    @AppStorage(GeneralSettings.hideHomeIndicatorKey) private var hideHomeIndicator = true
    @ScaledMetric(relativeTo: .body) private var uiScale: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var measuredStripHeight: CGFloat = 64
    @State private var measuredToolsHeight: CGFloat = 240
    @State private var measuredTopBarHeight: CGFloat = 76
    @Environment(\.colorScheme) private var colorScheme
    let book: Book
    @ObservedObject var player: SpeechPlayer
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.scenePhase) var scenePhase
    @StateObject private var document: ReaderDocument
    @State private var chapter = 0
    @State private var sentencePosition = 0
    @State private var jumpRevision = 0
    @State private var pageIndex = 0
    @State private var pages: [NSRange] = []
    @State private var attributed = NSAttributedString(string: "")
    @State private var sheet: ReaderSheet?
    @State private var ready = false
    @State private var following = true
    @State private var chrome = false
    @State private var doublePage = false
    @State private var dayPaper: String?
    @State private var shareItem: ExportedBook?
    /// 长按选中的句区间（划线 / 笔记 / 从这句听）
    @State private var selection: ReaderSelection?
    @State private var noteTarget: Highlight?
    @AppStorage("reader.fontSize") private var fontSize = 19.0
    @AppStorage("reader.lineSpacing") private var lineSpacing = 11.0
    @AppStorage("reader.font") private var font = "system"
    @AppStorage("reader.paper") private var paper = "paper"
    @AppStorage("reader.scrolling") private var scrolling = false
    @AppStorage("reader.paragraphSpacing") private var paragraphSpacing = 15.0
    @AppStorage("reader.margin") private var margin = 24.0
    @AppStorage("reader.indent") private var indent = true
    @AppStorage("reader.justified") private var justified = true
    @AppStorage("reader.doublePage") private var automaticDouble = true
    @AppStorage("reader.original") private var original = false
    @AppStorage("reader.letterSpacing") private var letterSpacing = 0.0
    @AppStorage("reader.convert") private var convert = "none"
    @AppStorage("app.appearance") private var appearance = "system"
    /// 自动翻页间隔（秒），0 为关闭；只在本次阅读有效
    @State private var autoTurn = 0

    init(book: Book, player: SpeechPlayer) {
        self.book = book; self.player = player
        _document = StateObject(wrappedValue: ReaderDocument(book: book))
    }
    private var prefs: ReaderPreferences { .init(fontSize: fontSize, lineSpacing: lineSpacing, font: font, paper: paper, scrolling: scrolling, paragraphSpacing: paragraphSpacing, margin: margin, indent: indent, justified: justified, letterSpacing: letterSpacing, convert: convert) }
    /// 固定浅纸不跟随 App 的深色强调色，避免浅色控件落在浅纸上失去对比。
    private var isDarkPaper: Bool { prefs.kind.dark || (prefs.kind == .paper && colorScheme == .dark) }
    /// 按实际纸色选择深浅陶橙，固定浅纸不会误用夜间浅色控件。
    private var readerAccent: Color { isDarkPaper ? Color(hex: 0xF0AD88) : Color(hex: 0xA44A2C) }
    private var readerOnAccent: Color { isDarkPaper ? Color(hex: 0x322017) : .white }
    private var readerPanelPaper: Color { paper == "paper" ? Theme.surface : prefs.background }
    private var chapters: [Chapter] { document.chapters }
    private var current: Chapter { chapters[min(max(0, chapter), chapters.count - 1)] }
    private var sentences: [Sentence] { document.sentences(chapter) }
    private var active: Bool { player.book?.id == book.id }
    private var entry: ShelfEntry? { model.entries.first(where: { $0.id == book.id }) }
    private var marked: Bool { entry?.bookmarks.contains { $0.chapter == chapter && $0.position == sentencePosition } == true }
    private var highlightRange: NSRange? { active && player.chapter == chapter ? player.sentenceRange : nil }
    private var originalHTML: String? { original ? current.fields["document"]?.object?["html"]?.string : nil }
    private var chapterProgress: Double {
        let total = sentences.count
        guard total > 0 else { return 0 }
        return Double(min(max(0, sentencePosition), total - 1) + 1) / Double(total)
    }
    private var chapterProgressLabel: String { "\(Int(chapterProgress * 100))%" }
    private var pageLabel: String {
        if document.isPDF || scrolling || originalHTML != nil { return "第 \(chapter + 1) / \(chapters.count) 章" }
        let shown = doublePage ? min(pages.count, pageIndex + 2) : pageIndex + 1
        return "\(shown) / \(max(1, pages.count))"
    }

    /// 听条占用的高度：正在听时正文底部让出这块，高亮句不会被听条盖住（只在开始 / 结束听书时重新分页一次）。
    private var stripReserve: CGFloat { max(76, measuredStripHeight + 12) }

    var body: some View {
        ZStack(alignment: .bottom) {
            prefs.background.ignoresSafeArea()
            if let pdf = document.pdf {
                PDFReader(data: pdf, page: $chapter).ignoresSafeArea(edges: .bottom)
                    .padding(.bottom, active ? stripReserve : 0)
                    .simultaneousGesture(TapGesture().onEnded { toggleChrome() })
                    .onChange(of: chapter) { _, value in model.saveProgress(book.id, chapter: value, position: 0) }
            } else {
                textContent
            }

            // 工具浮在正文上，不触发重新分页；大字号 / 横屏时工具区独立滚动，保留返回入口。
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    topBar
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { measuredTopBarHeight = $0 }
                        .offset(y: chrome ? 0 : -16)
                        .opacity(chrome ? 1 : 0)
                        .allowsHitTesting(chrome)
                        .accessibilityHidden(!chrome)
                    Spacer(minLength: 12)
                    VStack(spacing: 10) {
                        if let selection { selectionPanel(selection).transition(.move(edge: .bottom).combined(with: .opacity)) }
                        if autoTurn > 0 && selection == nil && !active && !chrome {
                            Button { autoTurn = 0 } label: {
                                Label("自动翻页 · 每 \(autoTurn) 秒 · 轻点停止", systemImage: Icon.autoTurn)
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 12).frame(minHeight: 44)
                                    .glassSurface(in: Rectangle(), interactive: true)
                            }
                            .buttonStyle(.plain).foregroundStyle(prefs.secondary)
                        }
                        if chrome && selection == nil {
                            ScrollView {
                                VStack(spacing: 10) {
                                    if active && !following { returnPill }
                                    chapterBar
                                }
                                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { measuredToolsHeight = $0 }
                            }
                            .scrollBounceBehavior(.basedOnSize)
                            .accessibilityIdentifier("reader.tools")
                            .frame(height: min(measuredToolsHeight, max(80, geometry.size.height - measuredTopBarHeight - 24)))
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        } else if active {
                            if !following && selection == nil { returnPill }
                            listeningStrip.transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .frame(maxWidth: 760)
                    .padding(.horizontal, 24).padding(.bottom, 12)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
        .foregroundStyle(prefs.foreground)
        .toolbar(.hidden, for: .navigationBar)
        .statusBarHidden(!chrome)
        .persistentSystemOverlays(!chrome && hideHomeIndicator ? .hidden : .automatic)
        .background(WindowAppearance(style: prefs.kind.dark ? .dark : UIUserInterfaceStyle(appearance: appearance), restore: UIUserInterfaceStyle(appearance: appearance)))
        .animation(.snappy(duration: 0.25), value: chrome)
        .animation(Theme.smoothSpring, value: active)
        .animation(.snappy(duration: 0.2), value: following)
        .animation(Theme.smoothSpring, value: selection)
        .onChange(of: chapter) { _, _ in selection = nil }
        .task(id: autoTurn) {
            guard autoTurn > 0 else { return }
            chrome = false
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(autoTurn)) } catch { return }
                // 打开工具栏、正在划线或在听书时暂停翻页
                guard !chrome, selection == nil, !(active && player.playing) else { continue }
                if pageIndex + (doublePage ? 2 : 1) >= pages.count && chapter + 1 >= chapters.count { autoTurn = 0; return }
                turn(1)
            }
        }
        .sheet(item: $noteTarget) { note in
            NoteEditor(quote: note.text, text: note.note ?? "") { text in
                var next = note; next.note = text.isEmpty ? nil : text
                if entry?.notes.contains(where: { $0.id == note.id }) == true { model.updateHighlight(book.id, next) }
                else { model.addHighlight(book.id, next) }
            }
        }
        .feedbackOverlay()
        .respectReducedMotion()
        .onAppear {
            model.recordActivity(active && player.playing ? .listening : .reading, for: book.id)
            let progress = entry?.progress ?? .init()
            chapter = min(max(0, progress.chapter), chapters.count - 1); sentencePosition = progress.position
            jumpRevision += 1
            // 朗读暂停后若手动读到别处，重新打开时停在保存的位置，而不是被拉回暂停处。
            following = active && (player.playing || (player.chapter == chapter && player.position == sentencePosition))
            if let jump = model.readerJump, jump.id == book.id, chapters.indices.contains(jump.chapter) {
                // 今日一句「从这句读」：一次性定位，不打断正在进行的朗读跟随之外的东西。
                model.readerJump = nil
                following = false
                chapter = jump.chapter; sentencePosition = max(0, jump.position)
            }
            followSpeech()
        }
        .onChange(of: player.position) { _, _ in followSpeech() }
        .onChange(of: player.chapter) { _, _ in followSpeech() }
        // 逐字进度单独订阅：只在需要翻页时改动页码，不让整页（含悬浮面板）随每个字重算。
        .onReceive(player.followPublisher.removeDuplicates()) { _ in if !scrolling { followSpeech() } }
        .onDisappear { persist(); model.readerClosed(book.id) }
        .task { while !Task.isCancelled { do { try await Task.sleep(for: .seconds(5)) } catch { return }; if scenePhase == .active && !player.playing { model.recordReading(seconds: 5, bookID: book.id, title: book.title) } } }
        #if DEBUG
        .task {
            switch UIReview.screen {
            case "reader-contents": sheet = .contents
            case "reader-preferences": sheet = .preferences
            case "reader-voice": sheet = .voice
            case "reader-nochrome", "reader-listen", nil: break
            default: chrome = true
            }
        }
        #endif
        .sheet(item: $sheet) { value in
            Group {
                switch value {
                case .preferences: NavigationStack { ReadingPreferencesView() }.presentationDetents([.large]).presentationDragIndicator(.visible)
                case .voice: NavigationStack { VoiceSettingsView() }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
                case .focus: PlayerView(player: player, fromReader: true)
                case .contents: NavigationStack { ContentsView(book: book, chapters: chapters, currentChapter: chapter, listeningChapter: active ? player.chapter : nil, bookmarks: entry?.bookmarks ?? []) { c, p in following = false; jump(chapter: c, position: p); sheet = nil } }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
                }
            }.environmentObject(model).tint(Theme.accent)
        }
        .sheet(item: $shareItem) { ShareSheet(items: [$0.url]) }
    }

    // MARK: 正文

    private var textContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(book.title)
                    .font(.caption2)
                    .lineLimit(1)
                    .foregroundStyle(prefs.secondary)
                Text("·")
                    .foregroundStyle(prefs.secondary.opacity(0.5))
                Text(current.title)
                    .font(.caption2)
                    .lineLimit(1)
                    .foregroundStyle(prefs.secondary)
                Spacer()
                if active && player.playing {
                    HStack(spacing: 4) {
                        Image(systemName: Icon.listening)
                            .symbolEffect(.variableColor.iterative, isActive: !reduceMotion)
                        Text("正在朗读")
                            .font(.caption2)
                    }
                    .foregroundStyle(readerAccent)
                    .accessibilityLabel("正在朗读")
                }
            }
            .font(.system(size: 12))
            .frame(height: 46, alignment: .bottom)
            .padding(.bottom, 10)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(prefs.secondary.opacity(0.14))
                    .frame(height: 0.5)
            }
            .opacity(chrome ? 0 : 1)
            .accessibilityHidden(chrome)

            GeometryReader { geometry in
                Group {
                    if let html = originalHTML {
                        let displayedChapter = chapter, requestedRevision = jumpRevision
                        OriginalBookView(html: html, css: current.fields["document"]?.object?["css"]?.string ?? "", book: book, chapter: chapter, foreground: prefs.foreground, paper: prefs.background, preferences: prefs, highlight: highlightRange, spokenSource: player.followPublisher, follow: following, highlightColor: prefs.highlightBand, readingPosition: sentencePosition, positionRevision: jumpRevision, onPositionChange: { position in
                            guard chapter == displayedChapter, jumpRevision == requestedRevision else { return }
                            sentencePosition = position
                            model.saveProgress(book.id, chapter: chapter, position: position)
                        }, onToggleChrome: { toggleChrome() }, onManualPage: { following = false }, onResumeFollow: { following = true; followSpeech() }, onEdgeTurn: { delta in following = false; jump(chapter: chapter + delta, position: 0) })
                            // WebKit 视口宽取整，滚动分页按实际宽度；宽度取整后二者一致，翻页不累积亚像素错位。
                            .frame(width: geometry.size.width.rounded(.down))
                    } else if !ready { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
                    else if current.text.isEmpty { ContentUnavailableView("本章为插图", systemImage: Icon.illustration, description: Text("在「字样」中打开原书图文，或在目录的「插图」中查看。")).contentShape(Rectangle()).onTapGesture { toggleChrome() } }
                    else if scrolling {
                        ScrollingText(attributed: attributed, highlight: highlightRange, color: prefs.highlight, marks: chapterMarks, initialOffset: currentOffset, chapterID: "\(book.id)-\(chapter)-\(jumpRevision)", followOffset: active && following ? highlightRange?.location : nil, onSelect: { select(offset: $0) }) { offset in
                            following = false; let position = Sentence.index(at: offset, in: sentences)
                            if position != sentencePosition { sentencePosition = position }
                        }.simultaneousGesture(TapGesture().onEnded { toggleChrome() })
                    } else {
                        HStack(spacing: 36) {
                            NativeTextPage(attributed: pageText(pageIndex), onSelect: { offset in select(offset: pageStart(pageIndex) + offset) })
                            if doublePage {
                                NativeTextPage(attributed: pageText(pageIndex + 1), onSelect: { offset in select(offset: pageStart(pageIndex + 1) + offset) })
                            }
                        }
                        .overlay {
                            if doublePage {
                                Rectangle()
                                    .fill(prefs.secondary.opacity(0.16))
                                    .frame(width: 0.6)
                                    .padding(.vertical, 8)
                                    .allowsHitTesting(false)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { location in
                            let width = geometry.size.width
                            if selection != nil { selection = nil }
                            else if location.x < width * 0.28 { turn(-1) } else if location.x > width * 0.72 { turn(1) } else { toggleChrome() }
                        }
                        .gesture(DragGesture(minimumDistance: 30).onEnded { gesture in if abs(gesture.translation.width) > abs(gesture.translation.height) { turn(gesture.translation.width < 0 ? 1 : -1) } })
                        .accessibilityAction(named: "下一页") { turn(1) }.accessibilityAction(named: "上一页") { turn(-1) }
                        .accessibilityAction(named: "显示阅读工具") { chrome = true }
                    }
                }.task(id: RebuildKey(chapter: chapter, size: geometry.size, prefs: prefs, automaticDouble: automaticDouble)) { await rebuild(size: geometry.size) }
            }
            .padding(.top, 18)
            .padding(.bottom, 6)
            HStack {
                Text(document.isPDF ? "第 \(chapter + 1) 页" : "本章 \(chapterProgressLabel)")
                Spacer()
                Text(pageLabel)
            }
            .monospacedDigit()
            .font(.caption2)
            .foregroundStyle(prefs.secondary)
            .frame(minHeight: 26)
            .opacity(chrome ? 0 : 1)
            .accessibilityHidden(chrome)
        }
        .padding(.horizontal, margin)
        .padding(.bottom, active ? stripReserve : 0)
    }

    // MARK: 导航、章节进度与阅读操作

    private var topBar: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: { barIcon(Icon.back) }
                .accessibilityLabel("返回书架")
                .accessibilityIdentifier("reader.back")
            VStack(alignment: .leading, spacing: 4) {
                Text(current.title).font(Theme.sans(17 * uiScale, weight: .medium)).lineLimit(1)
                Text(book.title).font(Theme.sans(12 * uiScale)).foregroundStyle(prefs.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // 书签只针对当前位置，放在顶栏随手可点；底栏留给打开面板类的操作
            Button {
                Haptics.selection()
                model.bookmark(book.id, chapter: chapter, position: sentencePosition, excerpt: sentences.indices.contains(sentencePosition) ? sentences[sentencePosition].text : String(current.text.prefix(80)))
            } label: { barIcon(Icon.bookmark(marked)).foregroundStyle(marked ? readerAccent : prefs.foreground) }
            .accessibilityLabel(marked ? "移除当前位置的书签" : "为当前位置添加书签")
            .accessibilityAddTraits(marked ? .isSelected : [])
            .accessibilityIdentifier("reader.bookmark")
        }
        .buttonStyle(.plain)
        .foregroundStyle(prefs.foreground)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .readerPaperPanel(paper: readerPanelPaper, ink: prefs.foreground, radius: 8)
        .padding(.horizontal, 12)
        .frame(maxWidth: 760)
        .padding(.top, 4)
    }

    private func barIcon(_ name: String) -> some View {
        ThemeIcon(symbol: name, size: 24)
            .frame(width: 44, height: 44).contentShape(Rectangle())
    }

    private var chapterBar: some View {
        VStack(spacing: 4) {
            HStack {
                Text(document.isPDF ? "页码进度" : "章节进度")
                Spacer()
                Text("\(chapter + 1) / \(chapters.count)").monospacedDigit()
                    .accessibilityIdentifier("reader.currentChapter")
            }
            .font(Theme.sans(12 * uiScale)).foregroundStyle(prefs.secondary)
            .padding(.horizontal, 8).padding(.top, 12)
            if chapters.count > 1 {
                ChapterScrubber(chapter: chapter, count: chapters.count, isPDF: document.isPDF, tint: readerAccent, onStep: { changeChapter($0) }) { value in
                    following = false; jump(chapter: value, position: 0)
                }
            } else {
                Text(pageLabel).font(.system(size: 12)).monospacedDigit().foregroundStyle(prefs.secondary).frame(height: 44)
            }
            // 四个位置固定：目录 → 排版 → 听书 → 更多；播放状态不再让其他按键挪位。
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: typeSize.isAccessibilitySize ? 2 : 4), spacing: 8) {
                readerAction(Icon.contents, "目录") { sheet = .contents }
                    .accessibilityIdentifier("reader.contents")
                readerAction(Icon.typography, "排版") { sheet = .preferences }
                    .accessibilityIdentifier("reader.preferences")
                readerAction(Icon.listen, active ? "听书页" : "听书", selected: active) { openListening() }
                    .accessibilityLabel(active ? "进入听书页" : "开始听书并进入听书页")
                    .accessibilityIdentifier(active ? "reader.expandPlayer" : "reader.listen")
                moreMenu
            }
            if active {
                Rectangle().fill(prefs.secondary.opacity(0.14)).frame(height: 0.5).padding(.horizontal, 8)
                listeningControls(showsPlayerLink: false)
            }
        }
        .padding(.horizontal, 8).padding(.bottom, 8)
        .foregroundStyle(prefs.foreground)
        .readerPaperPanel(paper: readerPanelPaper, ink: prefs.foreground, radius: 8)
    }

    private var moreMenu: some View {
        Menu {
            Section("阅读外观") {
                Button { toggleNightMode() } label: {
                    Label(isDarkPaper ? "切换日间纸色" : "切换夜间纸色", systemImage: Icon.dayNight(isDark: isDarkPaper))
                }.accessibilityIdentifier("reader.dayNight")
            }
            if !document.isPDF {
                Section("阅读方式") {
                    Toggle(isOn: $original) { Label("原书图文", systemImage: Icon.original) }
                    if !scrolling && originalHTML == nil {
                        Picker(selection: $autoTurn) {
                            Text("关闭").tag(0)
                            ForEach([10, 20, 30, 45, 60], id: \.self) { Text("每 \($0) 秒翻一页").tag($0) }
                        } label: { Label("自动翻页", systemImage: Icon.autoTurn) }
                    }
                }
            }
            Section("书籍") {
                Button { shareBook() } label: { Label("导出备份", systemImage: Icon.share) }
            }
        } label: { readerActionLabel(Icon.more, "更多") }
        .buttonStyle(.plain)
        .accessibilityLabel("更多阅读操作")
        .accessibilityIdentifier("reader.more")
    }

    private func readerActionLabel(_ icon: String, _ title: String, selected: Bool = false) -> some View {
        VStack(spacing: 6) {
            ThemeIcon(symbol: icon, size: 24)
            Text(L(title)).font(.caption).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(selected ? readerAccent : prefs.foreground)
        .frame(maxWidth: .infinity, minHeight: 58)
        .background(selected ? readerAccent.opacity(0.09) : .clear, in: Rectangle())
        .contentShape(Rectangle())
    }

    private func readerAction(_ icon: String, _ title: String, selected: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) { readerActionLabel(icon, title, selected: selected) }
            .buttonStyle(.plain)
    }

    /// 阅读中的听条只承担播放状态与切换；精细控制统一在听书页。
    private var listeningStrip: some View {
        listeningControls(showsPlayerLink: true)
            .readerPaperPanel(paper: readerPanelPaper, ink: prefs.foreground, radius: 8)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { measuredStripHeight = $0 }
    }

    /// 听条内容：单独作为听条显示，或在工具层打开时并入章节栏。
    private func listeningControls(showsPlayerLink: Bool) -> some View {
        HStack(spacing: 12) {
            if showsPlayerLink {
                Button { sheet = .focus } label: {
                    HStack(spacing: 8) {
                        listeningStatus
                        ThemeIcon(symbol: Icon.expandUp, size: 18)
                    }.contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityLabel("展开听书页")
                .accessibilityIdentifier("reader.expandPlayer")
            } else { listeningStatus }
            Button { togglePlayback() } label: {
                ZStack {
                    Circle().fill(readerAccent)
                    if player.buffering { ProgressView().tint(readerOnAccent) }
                    else { Image(systemName: Icon.playback(player.playing)).font(.system(size: 18, weight: .semibold)).foregroundStyle(readerOnAccent) }
                }
                .frame(width: 46, height: 46)
            }
            .buttonStyle(PressButtonStyle(scale: 0.94))
            .accessibilityLabel(player.playing ? "暂停朗读" : "继续朗读")
            .accessibilityIdentifier("reader.toggle")
        }
        .foregroundStyle(prefs.foreground)
        .padding(.horizontal, 12).padding(.vertical, 8).frame(minHeight: 64)
        .overlay(alignment: .top) {
            ProgressBar(value: player.progress, track: prefs.foreground.opacity(0.12), tint: readerAccent, height: 2.5)
                .padding(.horizontal, 22).accessibilityHidden(true)
        }
        .simultaneousGesture(DragGesture(minimumDistance: 16).onEnded { value in
            if value.translation.height < -24 { sheet = .focus }
        })
    }

    private var listeningStatus: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(player.buffering ? "正在准备声音…" : (player.playing ? "边读边听" : "朗读已暂停"))
                .font(.subheadline.weight(.semibold))
            Text(player.error ?? "第 \(player.chapter + 1) 章 · \(player.rate.rateText)× · \(player.timingLabel)")
                .font(.caption).foregroundStyle(player.error == nil ? prefs.secondary : Theme.danger)
                .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
        }
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
    }

    private var returnPill: some View {
        Button { following = true; followSpeech() } label: {
            Label(player.chapter == chapter ? "回到朗读处" : "回到朗读处 · 第 \(player.chapter + 1) 章", systemImage: Icon.listening)
                .font(.caption.weight(.semibold)).foregroundStyle(readerAccent)
                .padding(.horizontal, 16).frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("reader.returnToSpeech")
        .readerPaperPanel(paper: prefs.background, ink: prefs.foreground, radius: 8)
    }

    private func openListening() {
        if !active { togglePlayback() }
        sheet = .focus
    }

    // MARK: 行为

    private var currentOffset: Int { sentences.indices.contains(sentencePosition) ? sentences[sentencePosition].range.location : 0 }
    private func pageStart(_ index: Int) -> Int { pages.indices.contains(index) ? pages[index].location : 0 }
    /// 只为当前页复制富文本并加高亮，避免每个朗读回调复制整章。
    private func pageText(_ index: Int) -> NSAttributedString {
        guard pages.indices.contains(index), NSMaxRange(pages[index]) <= attributed.length else { return NSAttributedString(string: "") }
        let range = pages[index]
        let page = ReaderMark.apply(chapterMarks, to: NativeTypesetter.page(attributed, range: range), pageRange: range)
        guard let sentence = highlightRange else { return page }
        let overlap = NSIntersectionRange(sentence, range)
        guard overlap.length > 0 else { return page }
        // 分页模式按行画「陶橙浅底 + 下划线」（CoreTextPageView），滚动模式整句铺软底
        return SpeechHighlight.apply(to: page, sentence: NSRange(location: overlap.location - range.location, length: overlap.length), color: prefs.highlightBand.withAlphaComponent(isDarkPaper ? 0.18 : 0.16))
    }
    private func rebuild(size: CGSize) async {
        let double = automaticDouble && paper != "eink" && size.width > 650 && !scrolling
        let string = NativeTypesetter.attributed(current, preferences: prefs)
        let pageSize = CGSize(width: double ? (size.width - 36) / 2 : size.width, height: size.height)
        let box = UncheckedBox(value: string)
        let result = scrolling ? [NSRange(location: 0, length: string.length)] : await Task.detached(priority: .userInitiated) { NativeTypesetter.pages(box.value, size: pageSize) }.value
        guard !Task.isCancelled else { return }
        doublePage = double; attributed = string; pages = result
        locate(active && following && player.chapter == chapter ? (highlightRange?.location ?? currentOffset) : currentOffset); ready = true
    }
    private func locate(_ offset: Int) { let index = pages.firstIndex(where: { NSLocationInRange(offset, $0) }) ?? (offset >= attributed.length ? max(0, pages.count - 1) : 0); pageIndex = doublePage ? index / 2 * 2 : index }
    private func followSpeech() {
        guard following, active else { return }
        if chapter != player.chapter, chapters.indices.contains(player.chapter) { ready = false; chapter = player.chapter; return }
        sentencePosition = player.position
        if ready, !scrolling { locate(player.followOffset ?? currentOffset) }
    }
    /// 跟随朗读时进度由播放器写入；手动翻页或跳章（即使朗读已暂停）则保存阅读页自己的位置。
    private func persist() { if !active || !following { model.saveProgress(book.id, chapter: chapter, position: sentencePosition) } }
    private func toggleChrome() { withAnimation(.snappy(duration: 0.24)) { chrome.toggle() } }
    private func togglePlayback() {
        if active {
            let resuming = !player.playing
            player.toggle()
            if resuming { following = true; followSpeech() }
        } else { persist(); model.startListening(book, showPlayer: false); following = true }
    }
    private func listenAt(offset: Int) {
        sentencePosition = Sentence.index(at: offset, in: sentences)
        model.saveProgress(book.id, chapter: chapter, position: sentencePosition)
        if active { player.seek(chapter: chapter, position: sentencePosition); if !player.playing { player.resume() } }
        else { model.startListening(book, showPlayer: false) }
        following = true
    }
    // MARK: 划线与笔记

    /// 本章要画的标记：已保存的划线 + 当前选择
    private var chapterMarks: [ReaderMark] {
        var marks = (entry?.highlights ?? []).filter { $0.chapter == chapter }.compactMap { item -> ReaderMark? in
            ReaderMark.range(start: item.start, end: item.end, in: sentences).map { ReaderMark(range: $0, color: item.color, kind: item.style) }
        }
        if let selection, selection.chapter == chapter, let range = ReaderMark.range(start: selection.start, end: selection.end, in: sentences) {
            marks.append(ReaderMark(range: range, color: "", kind: "selection"))
        }
        return marks
    }
    /// 选择区里已有的划线（长按落在划线上时整段选中它）
    private func existingHighlight(_ selection: ReaderSelection) -> Highlight? {
        entry?.notes.first { $0.chapter == selection.chapter && $0.start == selection.start && $0.end == selection.end }
    }
    private func select(offset: Int) {
        guard !sentences.isEmpty else { return }
        let index = Sentence.index(at: offset, in: sentences)
        if let hit = entry?.notes.first(where: { $0.contains(chapter: chapter, sentence: index) }) {
            selection = ReaderSelection(chapter: chapter, start: hit.start, end: hit.end)
        } else {
            selection = ReaderSelection(chapter: chapter, start: index, end: index)
        }
        withAnimation(.snappy(duration: 0.2)) { chrome = false }
    }
    private func selectedText(_ selection: ReaderSelection) -> String {
        guard sentences.indices.contains(selection.start), sentences.indices.contains(selection.end) else { return "" }
        return sentences[selection.start...selection.end].map(\.text).joined()
    }
    private func selectionPanel(_ value: ReaderSelection) -> some View {
        let existing = existingHighlight(value)
        let text = selectedText(value)
        return SelectionPanel(
            text: text,
            existing: existing,
            canExtendBack: value.start > 0,
            canExtendForward: value.end + 1 < sentences.count,
            tint: prefs.foreground,
            paper: paper == "paper" ? Theme.surface : prefs.background,
            accent: readerAccent,
            onMark: { color, style in
                Haptics.selection()
                if var item = existing { item.color = color; item.style = style; model.updateHighlight(book.id, item) }
                else { model.addHighlight(book.id, Highlight(chapter: value.chapter, start: value.start, end: value.end, text: text, color: color, style: style)) }
                selection = nil
            },
            onRemove: { if let existing { model.removeHighlight(book.id, id: existing.id) }; selection = nil },
            onNote: {
                let defaults = UserDefaults.standard
                noteTarget = existing ?? Highlight(chapter: value.chapter, start: value.start, end: value.end, text: text,
                                                   color: ReaderMark.newColor(defaults.string(forKey: "highlight.lastColor")),
                                                   style: defaults.string(forKey: "highlight.lastStyle") ?? "background")
                selection = nil
            },
            onListen: {
                if sentences.indices.contains(value.start) { listenAt(offset: sentences[value.start].range.location) }
                selection = nil
            },
            onCopy: { UIPasteboard.general.string = text; Haptics.light(); selection = nil },
            onExtend: { delta in
                guard var next = selection else { return }
                if delta < 0 { next.start = max(0, next.start - 1) } else { next.end = min(sentences.count - 1, next.end + 1) }
                selection = next
            },
            onClose: { selection = nil }
        )
    }

    private func changeChapter(_ delta: Int) {
        // 阅读导航只改变眼前的正文，不能偷偷跳转正在播放的声音。
        following = false
        jump(chapter: chapter + delta, position: 0)
    }
    private func jump(chapter newChapter: Int, position: Int) {
        guard chapters.indices.contains(newChapter) else { return }
        let sameChapter = newChapter == chapter
        chapter = newChapter; sentencePosition = max(0, position); pageIndex = 0; jumpRevision += 1; persist()
        if sameChapter { locate(currentOffset) } else { ready = false }
    }
    private func turn(_ delta: Int) {
        following = false
        if document.isPDF || scrolling || originalHTML != nil { jump(chapter: chapter + delta, position: 0); return }
        let next = pageIndex + delta * (doublePage ? 2 : 1)
        if next < 0, chapter > 0 { jump(chapter: chapter - 1, position: max(0, document.sentences(chapter - 1).count - 1)) }
        else if next >= pages.count, chapter + 1 < chapters.count { jump(chapter: chapter + 1, position: 0) }
        else if pages.indices.contains(next) {
            pageIndex = next; sentencePosition = Sentence.index(at: pages[next].location, in: sentences)
            // 手动翻回正在朗读的那一页时恢复自动跟随。
            if let spoken = active && player.chapter == chapter ? player.followOffset : nil,
               (next..<min(pages.count, next + (doublePage ? 2 : 1))).contains(where: { NSLocationInRange(spoken, pages[$0]) }) { following = true; followSpeech() }
            persist()
        }
    }
    private func toggleNightMode() {
        if isDarkPaper {
            paper = dayPaper ?? "white"
            dayPaper = nil
        } else {
            dayPaper = paper
            paper = "night"
        }
    }
    private func shareBook() {
        do {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(book.id + ".json")
            try Integrity.encoder().encode(BackupPacket(book: book, progress: entry?.progress ?? .init())).write(to: url, options: .atomic)
            shareItem = ExportedBook(url: url)
        } catch { model.message = error.localizedDescription }
    }
}
private struct RebuildKey: Equatable { let chapter: Int; let size: CGSize; let prefs: ReaderPreferences; let automaticDouble: Bool }
enum ReaderSheet: String, Identifiable { case contents, preferences, voice, focus; var id: String { rawValue } }

final class CoreTextPageView: UIView {
    var onSelect: ((Int) -> Void)?
    private var textFrame: CTFrame?
    var attributed = NSAttributedString(string: "") { didSet { guard attributed != oldValue else { return }; accessibilityLabel = attributed.string; setNeedsDisplay() } }
    override init(frame: CGRect) { super.init(frame: frame); isOpaque = false; backgroundColor = .clear; contentMode = .redraw; isAccessibilityElement = true; accessibilityTraits = .staticText; addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(selectSentence(_:))))
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: CoreTextPageView, _: UITraitCollection) in view.setNeedsDisplay() }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.textMatrix = .identity; context.translateBy(x: 0, y: bounds.height); context.scaleBy(x: 1, y: -1)
        let setter = CTFramesetterCreateWithAttributedString(attributed)
        let frame = CTFramesetterCreateFrame(setter, CFRange(location: 0, length: attributed.length), CGPath(rect: bounds, transform: nil), nil)
        textFrame = frame
        let lines = CTFrameGetLines(frame) as! [CTLine]
        var origins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
        for (index, line) in lines.enumerated() {
            for run in CTLineGetGlyphRuns(line) as! [CTRun] {
                let attributes = CTRunGetAttributes(run) as NSDictionary
                let mark = attributes[NSAttributedString.Key.tyMark] as? ReaderMark.Style
                let speech = attributes[NSAttributedString.Key.backgroundColor] as? UIColor
                guard mark != nil || speech != nil else { continue }
                let range = CTRunGetStringRange(run)
                var ascent: CGFloat = 0, descent: CGFloat = 0
                let width = CTRunGetTypographicBounds(run, CFRange(location: 0, length: 0), &ascent, &descent, nil)
                let x = CTLineGetOffsetForStringIndex(line, range.location, nil)
                // 划线：浅底 / 直线 / 波浪线
                if let mark { ReaderMark.draw(mark, in: context, box: CGRect(x: origins[index].x + x, y: origins[index].y - descent - 1, width: width, height: ascent + descent + 2)) }
                guard let color = speech else { continue }
                // 浅紫底由 CTFrameDraw 按背景色属性铺满行高，行底补一道与纸色适配的跟读线。
                context.setFillColor(color.cgColor.alpha > 0.45 ? UIColor(hex: 0x111111).cgColor : color.withAlphaComponent(0.9).cgColor)
                context.fill(CGRect(x: origins[index].x + x, y: origins[index].y - descent - 1, width: width, height: 2))
            }
        }
        CTFrameDraw(frame, context)
    }
    @objc private func selectSentence(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, let frame = textFrame else { return }
        let point = gesture.location(in: self)
        let lines = CTFrameGetLines(frame) as! [CTLine]
        var origins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
        guard let index = origins.indices.min(by: { abs(origins[$0].y - (bounds.height - point.y)) < abs(origins[$1].y - (bounds.height - point.y)) }) else { return }
        let offset = CTLineGetStringIndexForPosition(lines[index], CGPoint(x: point.x - origins[index].x, y: 0))
        if offset != kCFNotFound { UIImpactFeedbackGenerator(style: .light).impactOccurred(); onSelect?(offset) }
    }
}
struct NativeTextPage: UIViewRepresentable {
    let attributed: NSAttributedString
    var onSelect: ((Int) -> Void)? = nil
    func makeUIView(context: Context) -> CoreTextPageView { CoreTextPageView() }
    func updateUIView(_ view: CoreTextPageView, context: Context) { view.attributed = attributed; view.onSelect = onSelect }
}
/// 连续滚动：只在朗读句变化时增删高亮属性，不重设整章文字。
struct ScrollingText: UIViewRepresentable {
    let attributed: NSAttributedString
    var highlight: NSRange?
    var color: UIColor
    var marks: [ReaderMark] = []
    let initialOffset: Int
    let chapterID: String
    var followOffset: Int? = nil
    var onSelect: ((Int) -> Void)? = nil
    let onPosition: (Int) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> ReaderScrollTextView {
        let view = ReaderScrollTextView(usingTextLayoutManager: false); view.isEditable = false; view.isSelectable = false; view.backgroundColor = .clear
        view.textContainerInset = UIEdgeInsets(top: 0, left: 0, bottom: 40, right: 0); view.textContainer.lineFragmentPadding = 0; view.delegate = context.coordinator
        view.addGestureRecognizer(UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.longPress(_:))))
        return view
    }
    func updateUIView(_ view: ReaderScrollTextView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        if coordinator.base !== attributed { coordinator.base = attributed; view.attributedText = attributed; coordinator.highlight = nil; coordinator.marks = []; coordinator.chapterID = ""; coordinator.followOffset = nil }
        if coordinator.highlight != highlight || coordinator.marks != marks {
            // 先清掉旧的划线与朗读样式，再按「划线 → 朗读句」的顺序重画，朗读句永远在最上层
            let storage = view.textStorage
            storage.beginEditing()
            let full = NSRange(location: 0, length: storage.length)
            for range in coordinator.marks.map(\.range) + [coordinator.highlight].compactMap({ $0 }) {
                let r = NSIntersectionRange(range, full)
                storage.removeAttribute(.backgroundColor, range: r); storage.removeAttribute(.underlineStyle, range: r); storage.removeAttribute(.underlineColor, range: r)
            }
            for mark in marks {
                let r = NSIntersectionRange(mark.range, full); guard r.length > 0 else { continue }
                let style = mark.style
                switch mark.kind {
                case "underline": storage.addAttributes([.underlineStyle: NSUnderlineStyle.thick.rawValue, .underlineColor: style.color], range: r)
                case "wavy": storage.addAttributes([.underlineStyle: NSUnderlineStyle([.single, .patternDot]).rawValue | NSUnderlineStyle.thick.rawValue, .underlineColor: style.color], range: r)
                default: storage.addAttribute(.backgroundColor, value: style.color.withAlphaComponent(mark.kind == "selection" ? 0.22 : 0.32), range: r)
                }
            }
            if let new = highlight, NSMaxRange(new) <= storage.length { storage.addAttribute(.backgroundColor, value: color, range: new) }
            storage.endEditing(); coordinator.highlight = highlight; coordinator.marks = marks
        }
        if let followOffset, coordinator.followOffset != followOffset {
            coordinator.followOffset = followOffset
            view.requestPosition(followOffset)
        }
        if followOffset == nil { coordinator.followOffset = nil }
        if coordinator.chapterID != chapterID && followOffset == nil {
            coordinator.chapterID = chapterID
            view.requestPosition(initialOffset)
        }
    }
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: ScrollingText; var chapterID = ""; var followOffset: Int?; var base: NSAttributedString?; var highlight: NSRange?; var marks: [ReaderMark] = []
        init(_ parent: ScrollingText) { self.parent = parent }
        @objc func longPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began, let view = gesture.view as? UITextView,
                  let position = view.closestPosition(to: gesture.location(in: view)) else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            parent.onSelect?(view.offset(from: view.beginningOfDocument, to: position))
        }
        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            (scrollView as? ReaderScrollTextView)?.releasePosition()
        }
        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard let view = scrollView as? UITextView, view.isDragging || view.isDecelerating,
                  let position = view.closestPosition(to: CGPoint(x: 0, y: view.contentOffset.y + 4)) else { return }
            parent.onPosition(view.offset(from: view.beginningOfDocument, to: position))
        }
    }
}

/// Resolve long-document positions only after the view has its final width and
/// TextKit has laid out the full text. Estimated layout can land hundreds of lines early.
final class ReaderScrollTextView: UITextView {
    private var requestedOffset: Int?
    private var pendingPosition = false
    private var lastSize = CGSize.zero
    func requestPosition(_ offset: Int) {
        requestedOffset = max(0, offset); pendingPosition = true; setNeedsLayout()
    }
    func releasePosition() { requestedOffset = nil; pendingPosition = false }
    override func layoutSubviews() {
        super.layoutSubviews()
        let sizeChanged = bounds.size != lastSize
        lastSize = bounds.size
        guard bounds.width > 0, bounds.height > 0, textStorage.length > 0,
              let offset = requestedOffset, pendingPosition || sizeChanged else { return }
        pendingPosition = false
        layoutManager.ensureLayout(for: textContainer)
        let range = NSRange(location: min(offset, textStorage.length - 1), length: 1)
        let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        let rect = layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer)
        let height = layoutManager.usedRect(for: textContainer).maxY + textContainerInset.top + textContainerInset.bottom
        contentSize = CGSize(width: bounds.width, height: height)
        let y = max(-adjustedContentInset.top, min(rect.minY + textContainerInset.top - 8, height - bounds.height + adjustedContentInset.bottom))
        setContentOffset(CGPoint(x: 0, y: y), animated: false)
    }
}

struct PDFReader: UIViewRepresentable {
    let data: Data
    @Binding var page: Int
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> PDFView {
        let view = PDFView(); view.document = PDFDocument(data: data); view.autoScales = true; view.displayMode = .singlePageContinuous; view.backgroundColor = UIColor(Theme.bg)
        context.coordinator.observer = NotificationCenter.default.addObserver(forName: .PDFViewPageChanged, object: view, queue: .main) { [weak coordinator = context.coordinator] _ in
            guard let coordinator, let current = view.currentPage, let doc = view.document else { return }
            let index = doc.index(for: current)
            if coordinator.parent.page != index { coordinator.parent.page = index }
        }
        return view
    }
    func updateUIView(_ view: PDFView, context: Context) {
        context.coordinator.parent = self
        if let doc = view.document, let target = doc.page(at: page), view.currentPage !== target { view.go(to: target) }
    }
    final class Coordinator {
        var parent: PDFReader; var observer: NSObjectProtocol?
        init(_ parent: PDFReader) { self.parent = parent }
        deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
    }
}

// MARK: - 目录

struct ContentsView: View {
    private struct SearchHit: Identifiable, Sendable {
        var id: Int { index }
        let index: Int
        let snippet: String
        let offset: Int
    }
    let book: Book
    let chapters: [Chapter]
    let currentChapter: Int
    /// 正在朗读的章（朗读这本书时），目录里标出声波
    var listeningChapter: Int? = nil
    let bookmarks: [Bookmark]
    let jump: (Int, Int) -> Void
    @Environment(\.dismiss) var dismiss
    @State private var query = ""
    @State private var hits: [SearchHit]? = nil
    @State private var mode = 0
    @State private var bookmarkToRemove: Bookmark?
    @EnvironmentObject var model: AppModel
    private var noteCount: Int { model.entries.first { $0.id == book.id }?.notes.count ?? 0 }
    var body: some View {
        ScrollViewReader { proxy in
            List {
                VStack(alignment: .leading, spacing: 7) {
                    Text(book.title).font(Theme.serifSemibold(23, relativeTo: .title2)).foregroundStyle(Theme.ink)
                    Text("共 \(chapters.count) 章 · 阅读到第 \(currentChapter + 1) 章")
                        .font(.system(size: 12)).foregroundStyle(Theme.ink3)
                }
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 12, trailing: 0))
                Picker("目录类型", selection: $mode) { Text("章节").tag(0); Text("书签 \(bookmarks.count)").tag(1); Text("笔记 \(noteCount)").tag(3); Text("插图").tag(2) }
                    .pickerStyle(.segmented).listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 12, trailing: 0))
                if mode == 0 {
                    if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        ForEach(Array(chapters.enumerated()), id: \.offset) { index, chapter in
                            chapterRow(index: index, chapter: chapter, snippet: nil, matchOffset: nil)
                        }
                    } else if let hits {
                        ForEach(hits) { hit in
                            if chapters.indices.contains(hit.index) {
                                chapterRow(index: hit.index, chapter: chapters[hit.index], snippet: hit.snippet, matchOffset: hit.offset)
                            }
                        }
                    }
                } else if mode == 3 {
                    NotesList(entryID: book.id, chapterTitle: { chapters.indices.contains($0) ? chapters[$0].title : "第 \($0 + 1) 章" }) { note in jump(note.chapter, note.start) }
                } else if mode == 1 {
                    if bookmarks.isEmpty { Text("在阅读页底部轻点「书签」，为当前页留下记号。").font(.subheadline).foregroundStyle(Theme.ink2).listRowBackground(Color.clear) }
                    ForEach(bookmarks.sorted { ($0.chapter, $0.position) < ($1.chapter, $1.position) }) { bookmark in
                        HStack(spacing: 10) {
                            Button { jump(bookmark.chapter, bookmark.position) } label: {
                                VStack(alignment: .leading, spacing: 7) {
                                    Text(chapters.indices.contains(bookmark.chapter) ? chapters[bookmark.chapter].title : "第 \(bookmark.chapter + 1) 章")
                                        .font(.body).foregroundStyle(Theme.ink)
                                    Text(bookmark.excerpt).font(.caption).lineLimit(3).foregroundStyle(Theme.ink2)
                                    Label("回到此处", systemImage: Icon.jumpHere)
                                        .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.accent)
                                }
                                .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("打开书签，\(bookmark.excerpt)")
                            Menu {
                                Button { jump(bookmark.chapter, bookmark.position) } label: { Label("回到此处", systemImage: Icon.read) }
                                Button(role: .destructive) { bookmarkToRemove = bookmark } label: { Label("移除书签", systemImage: Icon.removeBookmark) }
                            } label: {
                                Image(systemName: Icon.more).frame(width: 44, height: 44).contentShape(Rectangle())
                            }
                            .accessibilityLabel("书签的更多操作")
                        }
                        .padding(.vertical, 6).listRowBackground(Theme.surface)
                    }
                } else {
                    let refs = imageRefs
                    if refs.isEmpty { Text("本章没有可显示的插图。").font(.subheadline).foregroundStyle(Theme.ink2).listRowBackground(Color.clear) }
                    ForEach(Array(refs.enumerated()), id: \.offset) { _, ref in IllustrationRow(book: book, ref: ref) }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden).background(Theme.bg)
            .navigationTitle("目录与摘记").navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "搜索章节与全文")
            .task(id: query) {
                let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !keyword.isEmpty else { hits = nil; return }
                do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
                let snapshot = UncheckedBox(value: chapters)
                let results = await Task.detached(priority: .userInitiated) { () -> [SearchHit] in
                    var found: [SearchHit] = []
                    for (index, chapter) in snapshot.value.enumerated() {
                        if Task.isCancelled { return [] }
                        let titleMatch = chapter.title.localizedCaseInsensitiveContains(keyword)
                        let ns = chapter.text as NSString
                        let range = ns.range(of: keyword, options: .caseInsensitive)
                        guard titleMatch || range.location != NSNotFound else { continue }
                        let excerpt: String
                        if range.location != NSNotFound {
                            let start = max(0, range.location - 20), end = min(ns.length, NSMaxRange(range) + 60)
                            excerpt = ns.substring(with: ns.rangeOfComposedCharacterSequences(for: NSRange(location: start, length: end - start)))
                        } else {
                            excerpt = String(chapter.text.prefix(80))
                        }
                        found.append(SearchHit(index: index, snippet: excerpt, offset: range.location == NSNotFound ? 0 : range.location))
                    }
                    return found
                }.value
                if !Task.isCancelled { hits = results }
            }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .confirmationDialog("移除这枚书签？", isPresented: Binding(get: { bookmarkToRemove != nil }, set: { if !$0 { bookmarkToRemove = nil } }), titleVisibility: .visible, presenting: bookmarkToRemove) { bookmark in
                Button("移除书签", role: .destructive) {
                    if model.entries.first(where: { $0.id == book.id })?.bookmarks.contains(where: { $0.id == bookmark.id }) == true {
                        model.bookmark(book.id, chapter: bookmark.chapter, position: bookmark.position, excerpt: bookmark.excerpt)
                    }
                    bookmarkToRemove = nil
                }
                Button("取消", role: .cancel) { bookmarkToRemove = nil }
            } message: { _ in Text("正文与阅读进度会保留。") }
            .onAppear { proxy.scrollTo(currentChapter, anchor: .center) }
        }
    }
    private func chapterRow(index: Int, chapter: Chapter, snippet: String?, matchOffset: Int?) -> some View {
        Button { open(index, chapter, matchOffset: matchOffset) } label: {
            HStack(spacing: 12) {
                Text("\(index + 1)").font(.system(size: 13, weight: index == currentChapter ? .semibold : .regular)).monospacedDigit().foregroundStyle(index == currentChapter ? Theme.accent : Theme.ink3).frame(minWidth: 26, alignment: .leading)
                VStack(alignment: .leading, spacing: 5) {
                    Text(chapter.title).font(.body.weight(index == currentChapter ? .semibold : .regular)).foregroundStyle(Theme.ink)
                    if let snippet, !snippet.isEmpty { Text(snippet).font(.caption).lineLimit(2).foregroundStyle(Theme.ink2) }
                }
                Spacer()
                if index == listeningChapter { Image(systemName: Icon.listening).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.accent).accessibilityLabel("正在朗读") }
                if index == currentChapter {
                    Text("在读").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.accent)
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(Theme.accent.opacity(0.09), in: Rectangle())
                }
            }.padding(.vertical, 9)
        }
        .listRowSeparator(.hidden)
        .listRowBackground(index == currentChapter ? Theme.accentSoft : Theme.surface)
        .id(index)
    }
    private func open(_ index: Int, _ chapter: Chapter, matchOffset: Int?) {
        guard let matchOffset else { jump(index, 0); return }
        jump(index, Sentence.index(at: matchOffset, in: Sentence.split(chapter.text)))
    }
    /// 只取引用；图片由每一行在后台按需解码，多图章节打开目录不再卡顿。
    private var imageRefs: [String] {
        guard chapters.indices.contains(currentChapter) else { return [] }
        let chapter = chapters[currentChapter]
        return chapter.fields["nativeImages"]?.array?.compactMap(\.string) ?? HTMLText.imageSources(chapter.fields["document"]?.object?["html"]?.string ?? "")
    }
}

/// 阅读定位：箭头与滑杆都只改变阅读位置。触摸松手提交，辅助功能直接调整即时提交。
private struct ChapterScrubber: View {
    let chapter: Int
    let count: Int
    let isPDF: Bool
    let tint: Color
    let onStep: (Int) -> Void
    let onCommit: (Int) -> Void
    @State private var dragging = false
    @State private var draft: Double = 0
    @State private var originChapter = 0
    @State private var invalidated = false
    private var unit: String { isPDF ? "页" : "章" }
    private var shown: Int { max(0, min(count - 1, Int((dragging ? draft : Double(chapter)).rounded()))) }
    var body: some View {
        VStack(spacing: 0) {
            Slider(value: Binding(get: { dragging ? draft : Double(chapter) }, set: {
                draft = $0
                if !dragging { onCommit(Int($0.rounded())) }
            }), in: 0...Double(max(1, count - 1)), step: 1) { editing in
                if editing {
                    originChapter = chapter; draft = Double(chapter); invalidated = false; dragging = true
                } else {
                    let target = shown
                    dragging = false
                    if !invalidated && chapter == originChapter && target != chapter { onCommit(target) }
                }
            }
            .tint(tint).frame(minHeight: 44).disabled(count <= 1)
            .accessibilityLabel(isPDF ? "页码进度" : "章节进度")
            .accessibilityValue("第 \(shown + 1) \(unit)，共 \(count) \(unit)")
            .accessibilityIdentifier("reader.chapter-progress")
            HStack {
                Button { onStep(-1) } label: { stepLabel(Icon.back, "上一" + unit) }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .disabled(chapter == 0).opacity(chapter == 0 ? 0.35 : 1)
                    .accessibilityIdentifier("reader.previousChapter")
                Button { onStep(1) } label: { stepLabel(Icon.disclosure, "下一" + unit) }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .disabled(chapter + 1 >= count).opacity(chapter + 1 >= count ? 0.35 : 1)
                    .accessibilityIdentifier("reader.nextChapter")
            }
        }
        .buttonStyle(.plain)
        .onChange(of: chapter) { _, _ in if dragging { invalidated = true } }
    }
    private func stepLabel(_ name: String, _ title: String) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                ThemeIcon(symbol: name, size: 18)
                Text(L(title)).font(.caption)
            }.fixedSize(horizontal: true, vertical: true)
            VStack(spacing: 4) {
                ThemeIcon(symbol: name, size: 18)
                Text(L(title)).font(.caption).fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundStyle(tint).padding(.horizontal, 8).frame(minHeight: 44).contentShape(Rectangle())
    }
}

/// 目录「插图」中的一行：滚动到时才在后台解码，并缩成列表宽度的缩略图，避免整章原图同时进内存。
private struct IllustrationRow: View {
    let book: Book
    let ref: String
    @State private var image: UIImage?
    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFit().clipShape(Rectangle()) }
            else { Rectangle().fill(Theme.surface2).aspectRatio(16 / 10, contentMode: .fit) }
        }
        .accessibilityLabel("本章插图")
        .task(id: ref) {
            let book = book, ref = ref
            image = await Task.detached(priority: .userInitiated) {
                book.resourceData(ref).flatMap(UIImage.init(data:))?.preparingThumbnail(of: CGSize(width: 900, height: 1400))
            }.value
        }
    }
}

// MARK: - 字样与排版

/// 字样：第一屏放常用项（字号、字体、纸色、翻页方式），其余收进「更多排版」。
/// 在阅读页以半高 sheet 打开，正文实时预览；从设置进入时显示示例文字。
struct ReadingPreferencesView: View {
    @ScaledMetric(relativeTo: .body) private var uiScale: CGFloat = 1
    var showsPreview = true
    @Environment(\.dismiss) var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage("reader.fontSize") private var size = 19.0
    @AppStorage("reader.lineSpacing") private var spacing = 11.0
    @AppStorage("reader.font") private var font = "system"
    @AppStorage("reader.paper") private var paper = "paper"
    @AppStorage("reader.scrolling") private var scrolling = false
    private let mainPapers: [ReaderPaper] = [.paper, .white, .mist, .ancient, .night]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("每一行，都读得舒服")
                    .font(Theme.sans(12 * uiScale)).foregroundStyle(Theme.ink3)
                if showsPreview {
                    Text("我所记得的故乡全不如此。\n我的故乡好得多了。")
                        .font(Font(ReaderPreferences(fontSize: size, font: font).uiFont))
                        .lineSpacing(spacing)
                        .foregroundStyle(ReaderPreferences(paper: paper).foreground)
                        .padding(20)
                        .frame(maxWidth: .infinity, minHeight: 136, alignment: .topLeading)
                        .background(paper == "paper" ? Theme.surface : ReaderPreferences(paper: paper).background, in: Rectangle())
                        .accessibilityLabel("排版预览")
                }

                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Text("字号").font(Theme.sans(15 * uiScale, weight: .medium))
                        stepButton("A−", label: "减小字号") { size = max(14, size - 1) }
                        Spacer(minLength: 0)
                        Text("\(Int(size))").font(Theme.sans(15 * uiScale, weight: .medium)).monospacedDigit()
                        stepButton("A+", label: "增大字号") { size = min(34, size + 1) }
                    }
                    Slider(value: $size, in: 14...34, step: 1)
                        .accessibilityLabel("字号").accessibilityValue("\(Int(size))")
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(Theme.surface, in: Rectangle())

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("字体").font(Theme.sans(12 * uiScale)).foregroundStyle(Theme.ink3)
                        Spacer()
                        NavigationLink { MyFontsView() } label: {
                            Text(font.hasPrefix("custom:") ? (FontLibrary.fonts.first { "custom:" + $0.postScript == font }?.name ?? "我的字体") : "我的字体")
                                .font(Theme.sans(12 * uiScale)).lineLimit(2).frame(minHeight: 44)
                        }
                    }
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(spacing: 8) { fontChoices }
                    } else {
                        HStack(spacing: 8) { fontChoices }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("纸色").font(Theme.sans(12 * uiScale)).foregroundStyle(Theme.ink3)
                        Spacer()
                        Menu {
                            Picker("全部纸色", selection: $paper) {
                                ForEach(ReaderPaper.allCases) { item in Text(item.name).tag(item.rawValue) }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(ReaderPaper(rawValue: paper)?.name ?? "暖纸")
                                Image(systemName: Icon.collapse).font(.caption2)
                            }
                            .font(Theme.sans(12 * uiScale)).frame(minHeight: 44)
                        }
                        .accessibilityLabel("全部纸色")
                    }
                    HStack(spacing: 12) {
                        ForEach(mainPapers) { item in
                            Button { Haptics.selection(); paper = item.rawValue } label: {
                                Rectangle()
                                    .fill(item == .paper ? ReaderPaper.xuan : item.swatch)
                                    .frame(maxWidth: .infinity).frame(height: 58)
                                    .overlay {
                                        Rectangle()
                                            .strokeBorder(paper == item.rawValue ? Theme.accent : Theme.line, lineWidth: paper == item.rawValue ? 2 : 1)
                                    }
                                    .overlay {
                                        if paper == item.rawValue {
                                            ThemeIcon(symbol: Icon.checkmark, size: 20)
                                                .foregroundStyle(ReaderPreferences(paper: item.rawValue).foreground)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(item.name)
                            .accessibilityAddTraits(paper == item.rawValue ? .isSelected : [])
                        }
                    }
                }

                Picker("翻页方式", selection: $scrolling) {
                    Text("左右翻页").tag(false)
                    Text("上下滚动").tag(true)
                }
                .pickerStyle(.segmented)

                NavigationLink { MoreTypographyView() } label: {
                    HStack(spacing: 12) {
                        ThemeIcon(symbol: Icon.moreTypography, size: 24)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("更多排版").font(Theme.sans(15 * uiScale, weight: .medium))
                            Text("行距、段距、页边距与简繁转换")
                                .font(Theme.sans(12 * uiScale)).foregroundStyle(Theme.ink3)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        ThemeIcon(symbol: Icon.disclosure, size: 18)
                    }
                    .foregroundStyle(Theme.ink)
                    .padding(16)
                    .frame(minHeight: 64)
                    .background(Theme.surface, in: Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 20)
            .frame(maxWidth: 620).frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .background(Theme.bg)
        .tint(Theme.accent)
        .navigationTitle("阅读排版").navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button("完成") { dismiss() }
                .buttonStyle(PrimaryButtonStyle(height: 48))
                .padding(.horizontal, 24).padding(.vertical, 12)
                .frame(maxWidth: 620).frame(maxWidth: .infinity)
                .background(Theme.bg)
        }
    }

    @ViewBuilder private var fontChoices: some View {
        fontChip("serif", "思源宋体")
        fontChip("kai", "霞鹜文楷")
        fontChip("system", "系统字体")
    }

    private func fontChip(_ key: String, _ title: String) -> some View {
        Button { Haptics.selection(); font = key } label: {
            Text(L(title)).font(Theme.sans(12 * uiScale))
                .foregroundStyle(font == key ? Theme.accent : Theme.ink3)
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(font == key ? Theme.accentSoft : Theme.surface, in: Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(font == key ? .isSelected : [])
    }

    private func stepButton(_ text: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text).font(Theme.sans(15 * uiScale, weight: .medium))
                .foregroundStyle(Theme.ink).frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityLabel(label)
    }
}

/// 不常用的排版项：行距、段距、边距、缩进、对齐、双页、原书图文、恢复默认。
private struct MoreTypographyView: View {
    @AppStorage("reader.fontSize") private var size = 19.0
    @AppStorage("reader.lineSpacing") private var spacing = 11.0
    @AppStorage("reader.font") private var font = "system"
    @AppStorage("reader.paper") private var paper = "paper"
    @AppStorage("reader.scrolling") private var scrolling = false
    @AppStorage("reader.paragraphSpacing") private var paragraph = 15.0
    @AppStorage("reader.margin") private var margin = 24.0
    @AppStorage("reader.indent") private var indent = true
    @AppStorage("reader.justified") private var justified = true
    @AppStorage("reader.doublePage") private var doublePage = true
    @AppStorage("reader.original") private var original = false
    @AppStorage("reader.letterSpacing") private var letterSpacing = 0.0
    @AppStorage("reader.convert") private var convert = "none"
    var body: some View {
        Form {
            Section("版式") {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("字间距")
                        Spacer()
                        Text(letterSpacing.formatted(.number.precision(.fractionLength(0...1)))).font(.system(size: 13)).monospacedDigit().foregroundStyle(Theme.ink3)
                    }
                    Slider(value: $letterSpacing, in: -1...6, step: 0.5).accessibilityLabel("字间距")
                }
                adjustment("行距", value: $spacing, range: 2...28)
                adjustment("段落间距", value: $paragraph, range: 0...36)
                adjustment("页边距", value: $margin, range: 16...52)
                Toggle("首行两字缩进", isOn: $indent)
                Toggle("两端对齐", isOn: $justified)
            }
            if !scrolling {
                Section {
                    Toggle(isOn: $doublePage) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("宽屏自动双页")
                            Text("iPad 或横屏时并排显示两页").font(.caption).foregroundStyle(Theme.ink3)
                        }
                    }
                }
            }
            Section {
                Picker("简繁", selection: $convert) {
                    Text("原文").tag("none")
                    Text("简→繁").tag("s2t")
                    Text("繁→简").tag("t2s")
                }
                .pickerStyle(.segmented)
            } header: { Text("简繁转换") } footer: { Text("只改变显示，不修改书籍文件；朗读仍按原文。") }
            Section("内容") {
                Toggle(isOn: $original) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("原书图文")
                        Text("保留 EPUB / HTML 的图片、表格与样式").font(.caption).foregroundStyle(Theme.ink3)
                    }
                }
            }
            Section {
                Button("恢复护眼默认排版") {
                    size = 19; spacing = 11; paragraph = 15; margin = 24; indent = true; justified = true
                    font = "system"; paper = "paper"; doublePage = true; scrolling = false; original = false
                    letterSpacing = 0; convert = "none"
                }
                .frame(maxWidth: .infinity)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .navigationTitle("更多排版").navigationBarTitleDisplayMode(.inline)
    }
    private func adjustment(_ name: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(name)
                Spacer()
                Text("\(Int(value.wrappedValue))").font(.system(size: 13)).monospacedDigit().foregroundStyle(Theme.ink3)
            }
            Slider(value: value, in: range, step: 1).accessibilityLabel(name)
        }
    }
}

private extension View {
    /// 工具条保持用户纸色，以细边界而非重投影分层，正文不受工具显隐影响。
    func readerPaperPanel(paper: Color, ink: Color, radius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: max(24, radius), style: .continuous)
        return self.background(shape.fill(paper))
            .overlay(shape.strokeBorder(ink.opacity(0.12), lineWidth: 0.5))
    }
}
