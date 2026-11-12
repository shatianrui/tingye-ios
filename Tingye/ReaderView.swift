import SwiftUI
import CoreText
import PDFKit
import Pow

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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var measuredStripHeight: CGFloat = 52
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
    /// 最近一次翻页方向，决定滑动动画进出场边。
    @State private var turnDelta = 1
    @State private var pages: [NSRange] = []
    @State private var attributed = NSAttributedString(string: "")
    @State private var sheet: ReaderSheet?
    @State private var ready = false
    @State private var following = false
    /// v29 阶段三（p3a）：结束听书与听书页统一走确认流程，不再立即停止。
    @State private var endingListening = false
    @State private var chrome = false
    @State private var doublePage = false
    @State private var dayPaper: String?
    @State private var shareItem: ExportedBook?
    /// v29 阶段二：专注会话与读完收尾页（会话本体在 FocusSessionStore，不另计统计）。
    @AppStorage(FocusSessionStore.enabledKey) private var focusEnabled = true
    @ObservedObject private var focusStore = FocusSessionStore.shared
    @State private var focusPresented = false
    @State private var finishPresented = false
    /// 「更多」工具面板（自制 popover，替代系统 Menu 以便跟随阅读纸面配色）；子页为自动翻页选项。
    @State private var morePresented = false
    @State private var moreShowsAutoTurn = false
    @State private var didAutoPresentFinish = false
    /// 长按选中的句区间（划线 / 笔记 / 从这句听）
    @State private var selection: ReaderSelection?
    @State private var noteTarget: Highlight?
    @AppStorage("reader.fontSize") private var fontSize = 19.0
    @AppStorage("reader.lineSpacing") private var lineSpacing = 11.0
    @AppStorage("reader.font") private var font = "system"
    @AppStorage("reader.paper") private var paper = "paper"
    @AppStorage("reader.scrolling") private var scrolling = false
    @AppStorage("reader.pageTurn") private var pageTurn = "slide"
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
    /// 控件以当前纸色决定明暗；固定浅色纸在深色 App 中仍使用标准钴蓝。
    /// 构建 136 起 chrome（底部面板、滑杆、上下章）已改用 Theme 陶土令牌，此色仅余正文侧
    /// 用途（原书图文链接/选区、选区面板传参、顶栏书签与正文页眉状态字），不要再往 chrome 里加。
    private var readerAccent: Color { isDarkPaper ? Color(hex: 0x8DA7FF) : Color(hex: 0x315BEE) }
    private var readerOnAccent: Color { isDarkPaper ? Color(hex: 0x17233A) : .white }
    /// chrome 浮层实体面：浅纸用白、深纸用炭黑（Theme.surface 深色值），不再用旧海军蓝。
    private var readerPanelPaper: Color { isDarkPaper ? Color(hex: 0x1F1E1D) : .white }
    private var chapters: [Chapter] { document.chapters }
    private var current: Chapter { chapters[min(max(0, chapter), chapters.count - 1)] }
    private var sentences: [Sentence] { document.sentences(chapter) }
    private var active: Bool { player.book?.id == book.id }
    private var entry: ShelfEntry? { model.entries.first(where: { $0.id == book.id }) }
    private var marked: Bool { entry?.bookmarks.contains { $0.chapter == chapter && $0.position == sentencePosition } == true }
    private var highlightRange: NSRange? { active && following && player.chapter == chapter ? player.sentenceRange : nil }
    private var originalHTML: String? { original ? current.fields["document"]?.object?["html"]?.string : nil }
    private var chapterProgress: Double {
        let total = sentences.count
        guard total > 0 else { return 0 }
        return Double(min(max(0, sentencePosition), total - 1) + 1) / Double(total)
    }
    private var chapterProgressLabel: String { "\(Int(chapterProgress * 100))%" }
    private var pageLabel: String {
        if document.isPDF { return "第 \(chapter + 1) / \(chapters.count) 页" }
        if scrolling || originalHTML != nil { return "第 \(chapter + 1) / \(chapters.count) 章" }
        let shown = doublePage ? min(pages.count, pageIndex + 2) : pageIndex + 1
        return "\(shown) / \(max(1, pages.count))"
    }

    /// 阅读状态小字的底边距（只在 selection == nil 时调用）：工具面板展开时位于面板上方，
    /// 听书条浮现时位于听书条上方，自动翻页浮排在时位于其上方，其余时候贴近底边。
    private func statusLineBottomPadding(toolsHeight: CGFloat) -> CGFloat {
        if chrome { return toolsHeight + 6 }
        if active { return measuredStripHeight + 24 }
        if autoTurn > 0 { return 64 }
        return 4
    }

    /// 翻页动画：slide 按翻页方向平移，fade/blur 对称过渡，none 直切；开启减弱动态效果时全部直切。
    private var pageTurnTransition: AnyTransition {
        guard !reduceMotion else { return .identity }
        let forward = turnDelta >= 0
        switch pageTurn {
        case "fade": return .opacity
        case "blur": return .movingParts.blur(radius: 14)
        case "none": return .identity
        default: return .asymmetric(
            insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity))
        }
    }

    var body: some View {
        let showsListeningStrip = active && (!chrome || selection != nil)
        ZStack(alignment: .bottom) {
            (document.isPDF ? Theme.bg : prefs.background).ignoresSafeArea()
            GeometryReader { geometry in
                // 正文始终占据同一视口，悬浮工具只覆盖其上，开合不会触发重新分页。
                let minimumReadingHeight = min(160.0, geometry.size.height * 0.35)
                let toolsHeight = min(measuredToolsHeight, max(80, geometry.size.height - measuredTopBarHeight - minimumReadingHeight - 12))
                ZStack(alignment: .bottom) {
                    Group {
                        if let pdf = document.pdf {
                            PDFReader(data: pdf, page: $chapter)
                                .simultaneousGesture(TapGesture().onEnded { toggleChrome() })
                                .onChange(of: chapter) { _, value in model.saveProgress(book.id, chapter: value, position: 0) }
                        } else {
                            textContent
                        }
                    }
                    .padding(.bottom, active ? max(66, measuredStripHeight + 12) : 0)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()

                    VStack(spacing: 10) {
                        if let selection { selectionPanel(selection).transition(.move(edge: .bottom).combined(with: .opacity)) }
                        if autoTurn > 0 && selection == nil && !active && !chrome {
                            Button { autoTurn = 0 } label: {
                                Label("自动翻页 · 每 \(autoTurn) 秒 · 轻点停止", systemImage: Icon.autoTurn)
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 12).frame(minHeight: 44)
                                    .background(readerPanelPaper, in: Capsule())
                            }
                            .buttonStyle(.plain).foregroundStyle(prefs.secondary)
                        }
                        if !(chrome && selection == nil) && showsListeningStrip {
                            listeningStrip
                                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { measuredStripHeight = $0 }
                        }
                    }
                    .frame(maxWidth: 760)
                    .padding(.horizontal, 24)
                    .padding(.bottom, chrome || active || selection != nil || autoTurn > 0 ? 12 : 0)

                    // 底部菜单栏独立成贴边全宽面板（构建 136）：不再与上面的浮层共用居中限宽容器，
                    // chapterBar 的实心背景由此连续覆盖到屏幕底边，卡间缝与悬浮边距不再透出正文。
                    if chrome && selection == nil {
                        ScrollView {
                            VStack(spacing: 10) {
                                if active && !following { returnPill }
                                chapterBar(bottomInset: geometry.safeAreaInsets.bottom)
                            }
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { measuredToolsHeight = $0 }
                        }
                        .scrollBounceBehavior(.basedOnSize)
                        .accessibilityIdentifier("reader.tools")
                        .frame(height: toolsHeight)
                    }

                    // 阅读状态小字（时间 · 电量）：常驻底部，沉浸时也在；选区面板浮现时让位隐藏，
                    // 其余浮层（工具面板 / 听书条 / 自动翻页）出现时上移到其上方，不重叠、不拦截手势。
                    if selection == nil {
                        ReaderStatusLine(foreground: prefs.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.bottom, statusLineBottomPadding(toolsHeight: toolsHeight))
                            .allowsHitTesting(false)
                            .accessibilityIdentifier("reader.statusLine")
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .overlay(alignment: .top) {
                    if chrome {
                        topBar
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { measuredTopBarHeight = $0 }
                    }
                }
            }
        }
        .foregroundStyle(prefs.foreground)
        .toolbar(.hidden, for: .navigationBar)
        // 状态栏显隐同样会改变部分设备的安全区，阅读时保持一致。
        .statusBarHidden(true)
        .persistentSystemOverlays(!chrome && hideHomeIndicator ? .hidden : .automatic)
        .keepScreenAwake()
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
            model.setReadingSurface(book.id, visible: true)
            model.recordActivity(.reading, for: book.id)
            let progress = entry?.progress ?? .init()
            chapter = min(max(0, progress.chapter), chapters.count - 1); sentencePosition = progress.position
            jumpRevision += 1
            // 翻开书先恢复阅读位置；后台音频不能把正文拉去另一章。
            following = false
            if let jump = model.readerJump, jump.id == book.id, chapters.indices.contains(jump.chapter) {
                // 今日一句「从这句读」：一次性定位，不打断正在进行的朗读跟随之外的东西。
                model.readerJump = nil
                following = false
                chapter = jump.chapter; sentencePosition = max(0, jump.position)
            }
            persist()
            // 书房大卡「开始专注」直达：暂存键与本书 id 相符时消费一次并打开专注面板。
            if UserDefaults.standard.string(forKey: "study.openFocus.bookID") == book.id {
                UserDefaults.standard.removeObject(forKey: "study.openFocus.bookID")
                if focusEnabled { focusPresented = true }
            }
        }
        .onChange(of: player.position) { _, _ in followSpeech() }
        .onChange(of: player.chapter) { _, _ in followSpeech() }
        // 逐字进度单独订阅：只在需要翻页时改动页码，不让整页（含悬浮面板）随每个字重算。
        .onReceive(player.followPublisher.removeDuplicates()) { _ in if !scrolling { followSpeech() } }
        .onDisappear { model.setReadingSurface(book.id, visible: false); persist(); model.readerClosed(book.id) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { followSpeech() } else { persist() }
        }
        .onChange(of: sheet) { _, value in model.setReadingSurface(book.id, visible: value != .focus) }
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
                case .contents, .notes, .search: NavigationStack { ContentsView(book: book, chapters: chapters, currentChapter: chapter, listeningChapter: active ? player.chapter : nil, bookmarks: entry?.bookmarks ?? [], initialMode: value == .notes ? 3 : 0, startsSearching: value == .search) { c, p in following = false; jump(chapter: c, position: p); sheet = nil } }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
                }
            }.environmentObject(model).tint(Theme.accent)
        }
        .sheet(item: $shareItem) { ShareSheet(items: [$0.url]) }
        .confirmationDialog("结束这次听书？", isPresented: $endingListening, titleVisibility: .visible) {
            Button("结束听书", role: .destructive) { player.stop(); following = false }
            Button("取消", role: .cancel) {}
        } message: { Text("阅读进度会保留，随时可以继续。") }
        .sheet(isPresented: $focusPresented) {
            FocusStartView(entry: entry, bookID: book.id, bookTitle: book.title, chapter: chapter, chapterTitle: current.title) {
                focusPresented = false; dismiss()
            }
            .environmentObject(model).tint(Theme.accent)
        }
        .sheet(isPresented: $finishPresented) {
            if let entry {
                BookFinishView(entry: entry, onOpenNext: { next in
                    finishPresented = false
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { model.open(next) }
                }, onCloseBook: { finishPresented = false; dismiss() })
                .environmentObject(model).tint(Theme.accent)
            }
        }
    }

    // MARK: 正文

    private var textContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(book.title)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(prefs.foreground)
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
                            .font(.caption2.weight(.medium))
                    }
                    .foregroundStyle(readerAccent)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("正在朗读")
                }
                if focusEnabled, focusStore.bookID == book.id, focusStore.phase != .idle {
                    focusStatusButton
                }
            }
            .font(.system(size: 12))
            .frame(height: 46, alignment: .bottom)
            .padding(.bottom, 10)
            .opacity(chrome ? 0 : 1)
            .accessibilityHidden(chrome)

            if originalHTML == nil {
                VStack(alignment: .leading, spacing: 12) {
                    Text("第 \(chapter + 1) 章").font(.caption).foregroundStyle(prefs.secondary)
                    Text(current.title)
                        .font(Theme.serif(23, relativeTo: .title2)).foregroundStyle(prefs.foreground)
                        .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 20).padding(.bottom, 8)
            }

            GeometryReader { geometry in
                Group {
                    if let html = originalHTML {
                        let displayedChapter = chapter, requestedRevision = jumpRevision
                        OriginalBookView(html: html, css: current.fields["document"]?.object?["css"]?.string ?? "", book: book, chapter: chapter, foreground: prefs.foreground, paper: prefs.background, accent: readerAccent, preferences: prefs, highlight: highlightRange, spokenSource: player.followPublisher, follow: following, highlightColor: prefs.highlightBand, readingPosition: sentencePosition, positionRevision: jumpRevision, onPositionChange: { position in
                            guard chapter == displayedChapter, jumpRevision == requestedRevision else { return }
                            sentencePosition = position
                            model.saveProgress(book.id, chapter: chapter, position: position)
                        }, onToggleChrome: { toggleChrome() }, onManualPage: { following = false }, onEdgeTurn: { delta in
                            following = false
                            // 向前翻章落到下一章开头；向后翻章落到上一章末尾，与分页模式 turn(-1) 的落点一致。
                            if delta < 0, chapter > 0 { jump(chapter: chapter - 1, position: max(0, document.sentences(chapter - 1).count - 1)) }
                            else { jump(chapter: chapter + delta, position: 0) }
                        })
                            // WebKit 视口宽取整，滚动分页按实际宽度；宽度取整后二者一致，翻页不累积亚像素错位。
                            .frame(width: geometry.size.width.rounded(.down), height: geometry.size.height)
                    } else if !ready { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
                    else if current.text.isEmpty { ContentUnavailableView("本章为插图", systemImage: Icon.illustration, description: Text("在「更多」中打开原书图文，或在目录的「插图」中查看。")).contentShape(Rectangle()).onTapGesture { toggleChrome() } }
                    else if scrolling {
                        ScrollingText(attributed: attributed, highlight: highlightRange, color: prefs.highlight, marks: chapterMarks, initialOffset: currentOffset, chapterID: "\(book.id)-\(chapter)-\(jumpRevision)", followOffset: active && following ? highlightRange?.location : nil, onSelect: { select(offset: $0) }, onOverscroll: { delta in turn(delta) }) { offset in
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
                        // 章 + 页共同决定身份；只有 turn() 里的手动翻页带动画，跟读、跳转、重排直接切换。
                        .id("\(chapter)-\(pageIndex)")
                        .transition(pageTurnTransition)
                        .accessibilityAction(named: "下一页") { turn(1) }.accessibilityAction(named: "上一页") { turn(-1) }
                        .accessibilityAction(named: "显示阅读工具") { chrome = true }
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
                .task(id: RebuildKey(chapter: chapter, size: geometry.size, prefs: prefs, automaticDouble: automaticDouble)) { await rebuild(size: geometry.size) }
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
    }

    // MARK: 导航、章节进度与阅读操作

    private var topBar: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: { barIcon(Icon.back) }
                .accessibilityLabel("返回书架")
                .accessibilityIdentifier("reader.back")
            VStack(spacing: 2) {
                Text(chapterHeading)
                    .font(Theme.serif(15))
                    .foregroundStyle(prefs.foreground)
                    .lineLimit(1)
                Text(chapterSubheading)
                    .font(.caption2)
                    .foregroundStyle(prefs.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            // 专注入口上台面：与「更多」菜单里的开始专注共用同一面板（focusPresented）。
            if focusEnabled { focusQuickButton }
            // 书签只针对当前位置，放在顶栏随手可点；底栏留给打开面板类的操作
            Button {
                Haptics.selection()
                model.bookmark(book.id, chapter: chapter, position: sentencePosition, excerpt: sentences.indices.contains(sentencePosition) ? sentences[sentencePosition].text : String(current.text.prefix(80)))
            } label: {
                barIcon(Icon.bookmark(marked))
                    .foregroundStyle(marked ? readerAccent : prefs.foreground)
                    .id(marked)
                    .transition(marked ? .movingParts.pop(readerAccent) : .identity)
                    .animation(.easeOut(duration: 0.25), value: marked)
            }
            .accessibilityLabel(marked ? "移除当前位置的书签" : "为当前位置添加书签")
            .accessibilityAddTraits(marked ? .isSelected : [])
            .accessibilityIdentifier("reader.bookmark")
        }
        .buttonStyle(.plain)
        .foregroundStyle(prefs.foreground)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(document.isPDF ? Theme.bg : prefs.background, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 12)
        .frame(maxWidth: 760)
        .padding(.top, 4)
    }

    private func barIcon(_ name: String) -> some View {
        ThemeIcon(symbol: name, size: 24)
            .frame(width: 44, height: 44).contentShape(Rectangle())
    }

    /// 顶栏居中两行：第一行章节标题；第二行「第 X 章 · 全书 %」，
    /// 全书百分比沿用 ShelfEntry.percentText 的既有口径，未开卷时只报章节序号。
    private var chapterHeading: String { current.title.isEmpty ? book.title : current.title }
    private var chapterSubheading: String {
        if document.isPDF { return "第 \(chapter + 1) / \(chapters.count) 页" }
        if let entry, entry.started { return "第 \(chapter + 1) 章 · 全书 \(entry.percentText)" }
        return "第 \(chapter + 1) / \(chapters.count) 章"
    }

    /// 底部菜单栏（构建 136 重做）：滑杆区与动作排合并为一块贴边全宽的实心面板——
    /// 背景自顶边发丝线连续覆盖到屏幕底边（含安全区），内部只留一条发丝线，不再有两张卡之间的缝。
    /// 内容仍居中限宽 760，与顶栏同宽口径；面板底色沿用 chrome 浮层的 readerPanelPaper。
    private func chapterBar(bottomInset: CGFloat) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 2) {
                HStack {
                    Text(document.isPDF ? "页码进度" : "章节进度")
                    Spacer()
                    Text("\(chapter + 1) / \(chapters.count)").monospacedDigit()
                        .accessibilityIdentifier("reader.currentChapter")
                }
                .font(.caption).foregroundStyle(prefs.secondary)
                if chapters.count > 1 {
                    ChapterScrubber(chapter: chapter, count: chapters.count, isPDF: document.isPDF, tint: prefs.foreground, onStep: { changeChapter($0) }) { value in
                        following = false; jump(chapter: value, position: 0)
                    }
                } else {
                    Text(pageLabel).font(.caption).monospacedDigit().foregroundStyle(prefs.secondary).frame(minHeight: 44)
                }
            }
            .frame(maxWidth: 760)
            .padding(.horizontal, 24).padding(.top, 10).padding(.bottom, 6)

            Rectangle().fill(Theme.line).frame(height: 1)

            // 四项工具共享同一块面板，读听状态不会改变按钮位置。
            VStack(spacing: 8) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: typeSize.isAccessibilitySize ? 2 : 4), spacing: 8) {
                    readerAction(Icon.contents, "目录") { sheet = .contents }
                        .accessibilityIdentifier("reader.contents")
                    readerAction(Icon.typography, "排版") { sheet = .preferences }
                        .accessibilityIdentifier("reader.preferences")
                    readerAction(Icon.note, "摘记") { sheet = .notes }
                        .accessibilityLabel("查看本书摘记")
                        .accessibilityIdentifier("reader.notes")
                    moreMenu
                }
                if active {
                    listeningControls(showsPlayerLink: true)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { measuredStripHeight = $0 }
                }
            }
            .frame(maxWidth: 760)
            .padding(.horizontal, 16).padding(.vertical, 8)

            // 背景延伸到屏幕底边：安全区一段同色填充，不透正文。
            Color.clear.frame(height: bottomInset)
        }
        .frame(maxWidth: .infinity)
        .background(readerPanelPaper)
        .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
        .foregroundStyle(prefs.foreground)
    }

    /// 「更多」工具面板（构建 136）：原为系统 Menu，弹层底色/圆角由系统外观决定，
    /// 与阅读纸面脱节（浅纸上弹出深灰大圆角层）。改为自制 popover：容器跟随 chrome 纸面
    /// （readerPanelPaper，与底部面板同色）、圆角 Theme.radius、Theme.line 描边；
    /// 分区、条目、动作与无障碍标识与原 Menu 逐一一致，仅呈现容器不同。
    private var moreMenu: some View {
        Button { morePresented = true } label: { readerActionLabel(Icon.more, "更多") }
            .buttonStyle(.plain)
            .accessibilityLabel("更多阅读操作")
            .accessibilityIdentifier("reader.more")
            .popover(isPresented: $morePresented, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
                morePanel
                    .presentationCompactAdaptation(.popover)
                    .onDisappear { moreShowsAutoTurn = false }
            }
    }

    private var morePanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if moreShowsAutoTurn { autoTurnPanelRows } else { morePanelRows }
            }
            .padding(.vertical, 8)
        }
        .frame(width: 300)
        .frame(maxHeight: 540)
        .background(readerPanelPaper)
        .foregroundStyle(prefs.foreground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
        .overlay { RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.line, lineWidth: 1) }
    }

    @ViewBuilder
    private var morePanelRows: some View {
        moreSectionHeader("查找与整理")
        moreRow(Icon.search, "书内搜索", identifier: "reader.search") { sheet = .search }
        moreSectionHeader("阅读外观")
        moreRow(Icon.dayNight(isDark: isDarkPaper), isDarkPaper ? "切换日间纸色" : "切换夜间纸色", identifier: "reader.dayNight") { toggleNightMode() }
        if !document.isPDF {
            moreSectionHeader("阅读方式")
            if current.fields["document"]?.object?["html"]?.string != nil {
                moreRow(Icon.original, "原书图文", checkmarked: original) { original.toggle() }
            }
            if !scrolling && originalHTML == nil {
                moreRow(Icon.autoTurn, "自动翻页", trailing: autoTurn == 0 ? "关闭" : "每 \(autoTurn) 秒", closesPanel: false) { moreShowsAutoTurn = true }
            }
        }
        moreSectionHeader("辅助听书")
        moreRow(Icon.listen, "从当前阅读位置听", identifier: "reader.startListening") { startReadingAloud() }
        if active {
            moreRow(Icon.listening, "跟随朗读位置") { following = true; followSpeech() }
            moreRow(Icon.listen, "听书设置与控制", identifier: "reader.openPlayer") { sheet = .focus }
            moreRow(Icon.stopListening, "结束辅助听书") { endingListening = true }
        }
        moreSectionHeader("书房")
        if focusEnabled {
            moreRow(Icon.sleepTimer, focusStore.phase == .running && focusStore.bookID == book.id ? "查看专注会话" : "开始专注", identifier: "reader.focusSession") { focusPresented = true }
        }
        moreRow(Icon.checkmark, "读完收尾", identifier: "reader.finish") { presentFinish() }
        moreSectionHeader("书籍")
        moreRow(Icon.share, "导出备份") { shareBook() }
    }

    /// 自动翻页子页：与主列表同一容器，选项行以陶土对勾标记当前值，选定后关面板。
    @ViewBuilder
    private var autoTurnPanelRows: some View {
        Button { moreShowsAutoTurn = false } label: {
            HStack(spacing: 8) {
                ThemeIcon(symbol: Icon.back, size: 16)
                Text("自动翻页").font(.subheadline.weight(.medium))
            }
            .foregroundStyle(prefs.foreground)
            .padding(.horizontal, 16).frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("返回更多面板")
        ForEach([0, 10, 20, 30, 45, 60], id: \.self) { seconds in
            moreRow(Icon.autoTurn, seconds == 0 ? "关闭" : "每 \(seconds) 秒翻一页", checkmarked: autoTurn == seconds) { autoTurn = seconds }
        }
    }

    private func moreSectionHeader(_ title: String) -> some View {
        Text(L(title))
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Theme.ink2)
            .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 2)
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private func moreRow(_ icon: String, _ title: String, identifier: String? = nil, checkmarked: Bool = false, trailing: String? = nil, closesPanel: Bool = true, action: @escaping () -> Void) -> some View {
        let row = Button {
            if closesPanel { morePresented = false }
            action()
        } label: {
            HStack(spacing: 12) {
                ThemeIcon(symbol: icon, size: 18).frame(width: 22)
                Text(L(title)).font(.subheadline)
                Spacer()
                if let trailing {
                    Text(trailing).font(.caption).foregroundStyle(prefs.secondary)
                    ThemeIcon(symbol: Icon.disclosure, size: 13).foregroundStyle(prefs.secondary)
                }
                if checkmarked {
                    ThemeIcon(symbol: Icon.checkmark, size: 16).foregroundStyle(Theme.accent)
                }
            }
            .foregroundStyle(prefs.foreground)
            .padding(.horizontal, 16).frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        if let identifier { row.accessibilityIdentifier(identifier) } else { row }
    }

    private func readerActionLabel(_ icon: String, _ title: String, selected: Bool = false) -> some View {
        VStack(spacing: 5) {
            ThemeIcon(symbol: icon, size: 21)
            Text(L(title)).font(.system(size: 10, weight: selected ? .semibold : .regular)).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(selected ? Theme.accent : prefs.foreground)
        .frame(maxWidth: .infinity, minHeight: 58)
        .background(selected ? Theme.accent.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
    }

    private func readerAction(_ icon: String, _ title: String, selected: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) { readerActionLabel(icon, title, selected: selected) }
            .buttonStyle(.plain)
    }

    /// 顶栏专注快捷按钮（书签旁）：未开始显示「专注」；本书专注进行中显示剩余时间；
    /// 已完成显示「专注完成」。点按一律打开既有专注面板，剩余时间数据源与正文页眉的
    /// 专注状态小字相同（focusStore.remaining(at:)），不在此另造计时。
    @ViewBuilder
    private var focusQuickButton: some View {
        if focusStore.bookID == book.id, focusStore.phase == .running {
            TimelineView(.periodic(from: .now, by: 15)) { context in
                Button { focusPresented = true } label: {
                    HStack(spacing: 4) {
                        Image(systemName: Icon.sleepTimer)
                        Text(focusQuickLabel(at: context.date))
                    }
                    .font(.caption2.weight(.medium))
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain).foregroundStyle(Theme.accent)
                .accessibilityLabel("正在专注，查看专注会话")
                .accessibilityIdentifier("reader.focusQuick")
                .onChange(of: context.date) { _, _ in focusStore.completeIfDue(currentChapter: chapter) }
            }
        } else {
            let finished = focusStore.bookID == book.id && focusStore.phase == .finished
            Button { focusPresented = true } label: {
                Text(finished ? "专注完成" : "专注")
                    .font(.caption.weight(.medium))
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain).foregroundStyle(Theme.accent)
            .accessibilityLabel(finished ? "专注完成，查看小结" : "开始专注")
            .accessibilityIdentifier("reader.focusQuick")
        }
    }

    private func focusQuickLabel(at date: Date) -> String {
        let seconds = focusStore.remaining(at: date)
        if seconds <= 60 { return "还剩不足 1 分钟" }
        return "还剩 \(Int(ceil(seconds / 60))) 分钟"
    }

    /// 专注状态小字（正文页眉右侧，工具层收起时可见）：进行中显示剩余时间，
    /// 到时完成后显示完成提示；点开是专注面板。剩余时间只驱动显示，会话到时由 completeIfDue 翻状态。
    @ViewBuilder
    private var focusStatusButton: some View {
        if focusStore.phase == .finished {
            Button { focusPresented = true } label: {
                HStack(spacing: 4) {
                    Image(systemName: Icon.checkmark)
                    Text(focusStore.sessionSeconds < 60 ? "专注完成 · 不足 1 分钟" : "专注完成 · 共读 \(Int(focusStore.sessionSeconds / 60)) 分钟")
                }
                .font(.caption2.weight(.medium))
            }
            .buttonStyle(.plain).foregroundStyle(readerAccent)
            .accessibilityLabel("专注完成，查看小结")
            .accessibilityIdentifier("reader.focusFinished")
        } else {
            TimelineView(.periodic(from: .now, by: 15)) { context in
                Button { focusPresented = true } label: {
                    HStack(spacing: 4) {
                        Image(systemName: Icon.sleepTimer)
                        Text(focusRemainingLabel(at: context.date))
                    }
                    .font(.caption2.weight(.medium))
                }
                .buttonStyle(.plain).foregroundStyle(prefs.secondary)
                .accessibilityLabel("正在专注，查看专注会话")
                .accessibilityIdentifier("reader.focusRunning")
                .onChange(of: context.date) { _, _ in focusStore.completeIfDue(currentChapter: chapter) }
            }
        }
    }

    private func focusRemainingLabel(at date: Date) -> String {
        let seconds = focusStore.remaining(at: date)
        if seconds <= 60 { return "专注 · 还剩不足 1 分钟" }
        return "专注 · 还剩 \(Int(ceil(seconds / 60))) 分钟"
    }

    /// 阅读中的听条只承担播放状态与切换；精细控制统一在听书页。
    private var listeningStrip: some View {
        listeningControls(showsPlayerLink: true)
            .readerPaperPanel(paper: readerPanelPaper, ink: prefs.foreground)
            .contentShape(Rectangle())
            .onTapGesture { }
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
                    Circle().fill(prefs.foreground.opacity(0.07))
                    if player.buffering { ProgressView().tint(prefs.foreground) }
                    else { Image(systemName: Icon.playback(player.playing)).font(.system(size: 18, weight: .semibold)).foregroundStyle(prefs.foreground) }
                }
                .frame(width: 46, height: 46)
            }
            .buttonStyle(PressButtonStyle(scale: 0.94))
            .accessibilityLabel(player.playing ? "暂停朗读" : "继续朗读")
            .accessibilityIdentifier("reader.toggle")
        }
        .foregroundStyle(prefs.foreground)
        .padding(.horizontal, 8).padding(.vertical, 4).frame(minHeight: 52)
        .simultaneousGesture(DragGesture(minimumDistance: 16).onEnded { value in
            if value.translation.height < -24 { sheet = .focus }
        })
    }

    private var listeningStatus: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(player.buffering ? "正在准备声音…" : (player.playing ? (following ? "跟随朗读" : "辅助听书中") : "朗读已暂停"))
                .font(.caption.weight(.medium))
            Text(player.error ?? "第 \(player.chapter + 1) 章 · \(player.rate.rateText)× · \(player.timingLabel)")
                .font(.caption).foregroundStyle(player.error == nil ? prefs.secondary : Theme.danger)
                .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }

    private var returnPill: some View {
        Button { following = true; followSpeech() } label: {
            Label(player.chapter == chapter ? "回到朗读处" : "回到朗读处 · 第 \(player.chapter + 1) 章", systemImage: Icon.listening)
                .font(.caption).foregroundStyle(prefs.secondary)
                .padding(.horizontal, 12).frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("reader.returnToSpeech")
    }

    private func startReadingAloud() {
        persist()
        model.startListening(book, showPlayer: false, from: .init(chapter: chapter, position: sentencePosition))
        following = true
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
        // 分页模式按行画「信号蓝浅底 + 下划线」（CoreTextPageView），滚动模式整句铺软底
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
        guard following, active, scenePhase == .active else { return }
        if chapter != player.chapter, chapters.indices.contains(player.chapter) { ready = false; chapter = player.chapter }
        sentencePosition = player.position
        if ready, !scrolling { locate(player.followOffset ?? currentOffset) }
        persist()
    }
    /// 阅读只保存眼前的正文位置；听书回调保存另一份位置。
    private func persist() { model.saveProgress(book.id, chapter: chapter, position: sentencePosition) }

    /// 手动打开读完收尾页（「更多」菜单）。
    private func presentFinish() {
        guard entry != nil else { return }
        finishPresented = true
    }

    /// 读完自动触发：只由 turn() 在读者明确做出「翻过全书最后一页」的动作时调用，
    /// 且每次打开本书只自动弹一次；单纯停在最后一页、最后一章中途退出都不触发。
    private func requestFinish() {
        guard !didAutoPresentFinish, entry != nil else { return }
        didAutoPresentFinish = true
        finishPresented = true
    }
    private func toggleChrome() { withAnimation(.snappy(duration: 0.24)) { chrome.toggle() } }
    private func togglePlayback() {
        if active {
            player.toggle()
        } else { startReadingAloud() }
    }
    private func listenAt(offset: Int) {
        sentencePosition = Sentence.index(at: offset, in: sentences)
        model.saveProgress(book.id, chapter: chapter, position: sentencePosition)
        if active { player.seek(chapter: chapter, position: sentencePosition); if !player.playing { player.resume() } }
        else { model.startListening(book, showPlayer: false, from: .init(chapter: chapter, position: sentencePosition)) }
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
            paper: readerPanelPaper,
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
        turnDelta = delta
        if document.isPDF || scrolling || originalHTML != nil {
            // 最后一章（PDF 为最后一页）再向前翻 = 翻过全书末尾，触发读完收尾；
            // 滚动与原书图文还要求已经读到本章最后一句，避免章中误触。
            if delta > 0, chapter == chapters.count - 1, document.isPDF || sentencePosition >= max(0, sentences.count - 1) { requestFinish() }
            jump(chapter: chapter + delta, position: 0); return
        }
        let next = pageIndex + delta * (doublePage ? 2 : 1)
        if next < 0, chapter > 0 { jump(chapter: chapter - 1, position: max(0, document.sentences(chapter - 1).count - 1)) }
        else if next >= pages.count, chapter + 1 < chapters.count { jump(chapter: chapter + 1, position: 0) }
        else if pages.indices.contains(next) {
            if reduceMotion || pageTurn == "none" { pageIndex = next }
            else { withAnimation(.easeInOut(duration: 0.3)) { pageIndex = next } }
            sentencePosition = Sentence.index(at: pages[next].location, in: sentences)
            // 手动阅读始终由读者决定位置；只有显式“回到朗读处”才恢复跟随。
            persist()
        }
        // 已在最后一章最后一页还向前翻：翻过全书末尾，触发读完收尾。
        else if next >= pages.count { requestFinish() }
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
enum ReaderSheet: String, Identifiable { case contents, notes, search, preferences, voice, focus; var id: String { rawValue } }

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
                // 跟读浅底由 CTFrameDraw 按背景色属性铺满行高，行底补一道与纸色适配的跟读线。
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
    func makeUIView(context: Context) -> CoreTextPageView {
        let view = CoreTextPageView()
        view.accessibilityIdentifier = "reader.nativePage"
        return view
    }
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
    /// 滚到章末（或章首）再继续拉、松手时触发：顺势翻章（+1 下一章 / -1 上一章）。
    var onOverscroll: ((Int) -> Void)? = nil
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
        /// 拖拽松手时若已越出内容边界一段（回弹区），视为「继续读」的明确意图，顺势翻章；
        /// 普通滑行落定不触发（松手时偏移还在界内），避免读到章末附近就被抢走。
        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            guard parent.onOverscroll != nil else { return }
            let top = -scrollView.adjustedContentInset.top
            let bottom = max(top, scrollView.contentSize.height + scrollView.adjustedContentInset.bottom - scrollView.bounds.height)
            if scrollView.contentOffset.y > bottom + 60 { parent.onOverscroll?(1) }
            else if scrollView.contentOffset.y < top - 60 { parent.onOverscroll?(-1) }
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

/// 阅读状态小字：沉浸阅读时系统状态栏隐藏，这里在页面底部常驻当前时间与电量。
/// 时间由 TimelineView 每 30 秒刷新一帧（不逐秒重绘）；电量走系统变更通知（以 5% 步进），
/// 另在每次时间刷新时顺带重读一次，双保险且都不是轮询热路径。
private struct ReaderStatusLine: View {
    let foreground: Color
    @State private var batteryLevel: Float = UIDevice.current.batteryLevel
    @State private var batteryState: UIDevice.BatteryState = UIDevice.current.batteryState

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            HStack(spacing: 5) {
                Text(Self.timeText(context.date))
                if batteryLevel >= 0 {
                    Text("·").accessibilityHidden(true)
                    Image(systemName: Self.batterySymbol(level: batteryLevel)).accessibilityHidden(true)
                    Text("\(Int((batteryLevel * 100).rounded()))%")
                    if batteryState == .charging || batteryState == .full { Text("充电中") }
                }
            }
            .font(.caption2)
            .monospacedDigit()
            .foregroundStyle(foreground)
            .accessibilityElement(children: .combine)
        }
        .onAppear {
            UIDevice.current.isBatteryMonitoringEnabled = true
            batteryLevel = UIDevice.current.batteryLevel
            batteryState = UIDevice.current.batteryState
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.batteryLevelDidChangeNotification)) { _ in
            batteryLevel = UIDevice.current.batteryLevel
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.batteryStateDidChangeNotification)) { _ in
            batteryState = UIDevice.current.batteryState
            batteryLevel = UIDevice.current.batteryLevel
        }
    }

    private static func timeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
    private static func batterySymbol(level: Float) -> String {
        switch level {
        case 0.95...: return "battery.100"
        case 0.65...: return "battery.75"
        case 0.40...: return "battery.50"
        case 0.15...: return "battery.25"
        default: return "battery.0"
        }
    }
}

#if DEBUG
/// UI 回归读取 PDFKit 的真实页位置与缩放，避免仅凭 SwiftUI 状态误判正文没有移动。
private final class ReviewPDFView: PDFView {
    override var accessibilityValue: String? {
        get {
            guard UIReview.isolated, let document, let currentPage else { return super.accessibilityValue }
            let rect = convert(currentPage.bounds(for: displayBox), from: currentPage)
            let state: [String: Double] = ["page": Double(document.index(for: currentPage)), "scale": scaleFactor,
                                           "pageX": rect.minX, "pageY": rect.minY,
                                           "pageWidth": rect.width, "pageHeight": rect.height]
            guard let data = try? JSONSerialization.data(withJSONObject: state, options: .sortedKeys) else { return nil }
            return String(data: data, encoding: .utf8)
        }
        set { super.accessibilityValue = newValue }
    }
}
#endif

struct PDFReader: UIViewRepresentable {
    let data: Data
    @Binding var page: Int
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> PDFView {
#if DEBUG
        let view: PDFView = ReviewPDFView()
        if UIReview.isolated {
            view.isAccessibilityElement = true
            view.accessibilityIdentifier = "reader.pdf"
            view.accessibilityLabel = "PDF 正文"
        }
#else
        let view = PDFView()
#endif
        view.document = PDFDocument(data: data); view.autoScales = true
        view.displayMode = .singlePageContinuous; view.displayDirection = .vertical
        view.displaysPageBreaks = true; view.pageBreakMargins = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        view.backgroundColor = UIColor(Theme.bg)
        context.coordinator.observer = NotificationCenter.default.addObserver(forName: .PDFViewPageChanged, object: view, queue: .main) { [weak coordinator = context.coordinator] _ in
            guard let coordinator, let current = view.currentPage, let doc = view.document else { return }
            let index = doc.index(for: current)
            if coordinator.parent.page != index { coordinator.parent.page = index }
        }
        return view
    }
    func updateUIView(_ view: PDFView, context: Context) {
        context.coordinator.parent = self
        view.backgroundColor = UIColor(Theme.bg)
        if let doc = view.document, let target = doc.page(at: page), view.currentPage !== target { view.go(to: target) }
    }
    final class Coordinator {
        var parent: PDFReader; var observer: NSObjectProtocol?
        init(_ parent: PDFReader) { self.parent = parent }
        deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
    }
}

// MARK: - 目录

/// 全文检索保留同章内每一次命中，使用 UTF-16 坐标与正文定位保持一致。
enum ReaderSearch {
    struct Match: Identifiable, Sendable {
        var id: String { "\(index):\(offset)" }
        let index: Int
        let snippet: String
        let offset: Int
    }
    static func matches(in chapters: [Chapter], query: String, limit: Int = 200) -> [Match] {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty, limit > 0 else { return [] }
        var results: [Match] = []
        for (index, chapter) in chapters.enumerated() {
            if Task.isCancelled { return [] }
            let text = chapter.text as NSString
            var cursor = 0, matchedBody = false
            while cursor < text.length {
                if Task.isCancelled { return [] }
                let range = text.range(of: keyword, options: .caseInsensitive, range: NSRange(location: cursor, length: text.length - cursor))
                guard range.location != NSNotFound, range.length > 0 else { break }
                matchedBody = true
                let start = max(0, range.location - 24), end = min(text.length, NSMaxRange(range) + 64)
                let context = text.rangeOfComposedCharacterSequences(for: NSRange(location: start, length: end - start))
                let snippet = (context.location > 0 ? "…" : "") + text.substring(with: context) + (NSMaxRange(context) < text.length ? "…" : "")
                results.append(Match(index: index, snippet: snippet, offset: range.location))
                if results.count >= limit { return results }
                cursor = NSMaxRange(range)
            }
            if !matchedBody, chapter.title.localizedCaseInsensitiveContains(keyword) {
                results.append(Match(index: index, snippet: String(chapter.text.prefix(80)), offset: 0))
                if results.count >= limit { return results }
            }
        }
        return results
    }
}

struct ContentsView: View {
    let book: Book
    let chapters: [Chapter]
    let currentChapter: Int
    /// 正在朗读的章（朗读这本书时），目录里标出声波
    var listeningChapter: Int? = nil
    let bookmarks: [Bookmark]
    var initialMode: Int = 0
    var startsSearching: Bool = false
    let jump: (Int, Int) -> Void
    @Environment(\.dismiss) var dismiss
    @State private var query = ""
    @State private var hits: [ReaderSearch.Match]? = nil
    @State private var mode = 0
    @State private var searchPresented = false
    @State private var bookmarkToRemove: Bookmark?
    @EnvironmentObject var model: AppModel
    private var noteCount: Int { model.entries.first { $0.id == book.id }?.notes.count ?? 0 }
    var body: some View {
        ScrollViewReader { proxy in
            List {
                VStack(alignment: .leading, spacing: 7) {
                    Text(book.title).font(.title3.weight(.semibold)).foregroundStyle(Theme.ink)
                    Text("共 \(chapters.count) 章 · 阅读到第 \(currentChapter + 1) 章")
                        .font(.system(size: 12)).foregroundStyle(Theme.ink3)
                }
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 12, trailing: 0))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        contentsTab("章节", value: 0)
                        contentsTab("书签 \(bookmarks.count)", value: 1)
                        contentsTab("笔记 \(noteCount)", value: 3)
                        contentsTab("插图", value: 2)
                    }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 12, trailing: 0))
                if mode == 0 {
                    if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        ForEach(Array(chapters.enumerated()), id: \.offset) { index, chapter in
                            chapterRow(index: index, chapter: chapter, snippet: nil, matchOffset: nil)
                        }
                    } else if let hits {
                        if !hits.isEmpty {
                            Text(hits.count >= 200 ? "显示前 200 处匹配，可输入更完整的词句缩小范围。" : "找到 \(hits.count) 处匹配")
                                .font(.caption).foregroundStyle(Theme.ink2)
                                .accessibilityIdentifier("reader.searchResultCount")
                                .listRowBackground(Color.clear)
                        }
                        ForEach(hits) { hit in
                            if chapters.indices.contains(hit.index) {
                                chapterRow(index: hit.index, chapter: chapters[hit.index], snippet: hit.snippet, matchOffset: hit.offset)
                            }
                        }
                    }
                    if hits?.isEmpty == true && !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        ContentUnavailableView.search(text: query).listRowBackground(Color.clear)
                    }
                } else if mode == 3 {
                    NotesList(entryID: book.id, chapterTitle: { chapters.indices.contains($0) ? chapters[$0].title : "第 \($0 + 1) 章" }) { note in jump(note.chapter, note.start) }
                } else if mode == 1 {
                    if bookmarks.isEmpty { Text("在阅读页顶部轻点书签图标，为当前页留下记号。").font(.subheadline).foregroundStyle(Theme.ink2).listRowBackground(Color.clear) }
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
            .searchable(text: $query, isPresented: $searchPresented, prompt: "搜索章节与全文")
            .task(id: query) {
                let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !keyword.isEmpty else { hits = nil; return }
                mode = 0
                hits = nil
                do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
                let snapshot = UncheckedBox(value: chapters)
                let searchTask = Task.detached(priority: .userInitiated) { ReaderSearch.matches(in: snapshot.value, query: keyword) }
                let results = await withTaskCancellationHandler { await searchTask.value } onCancel: { searchTask.cancel() }
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
            .onAppear {
                mode = initialMode
                if initialMode == 0 { proxy.scrollTo("chapter:\(currentChapter)", anchor: .center) }
                searchPresented = startsSearching
            }
        }
    }
    private func contentsTab(_ title: String, value: Int) -> some View {
        Button { mode = value } label: {
            Text(title).font(.caption)
                .foregroundStyle(mode == value ? Theme.onAccent : Theme.ink3)
                .padding(.horizontal, 14).frame(minHeight: 44)
                .background(mode == value ? Theme.accent : Theme.surface2, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(mode == value ? .isSelected : [])
    }
    private func chapterRow(index: Int, chapter: Chapter, snippet: String?, matchOffset: Int?) -> some View {
        Button { open(index, chapter, matchOffset: matchOffset) } label: {
            HStack(spacing: 12) {
                Text(String(format: "%02d", index + 1)).font(.caption.weight(index == currentChapter ? .semibold : .regular)).monospacedDigit().foregroundStyle(index == currentChapter ? Theme.accent : Theme.ink3).frame(minWidth: 26, alignment: .leading)
                VStack(alignment: .leading, spacing: 5) {
                    Text(chapter.title).font(.body.weight(index == currentChapter ? .semibold : .regular)).foregroundStyle(Theme.ink)
                    if let snippet, !snippet.isEmpty { Text(snippet).font(.caption).lineLimit(2).foregroundStyle(Theme.ink2) }
                }
                Spacer()
                if index == listeningChapter { Image(systemName: Icon.listening).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.accent).accessibilityLabel("正在朗读") }
                if index == currentChapter {
                    Text("在读").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.accent)
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(Theme.accent.opacity(0.09), in: Capsule())
                }
            }
            .padding(16).frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .background(index == currentChapter ? Theme.accentSoft : Theme.surface, in: RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .id(matchOffset.map { "\(index):\($0)" } ?? "chapter:\(index)")
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
    /// 上一章/下一章的常态前景（纸面墨色）；滑杆绘制已改走 Theme 陶土令牌，不再用此色。
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
            scrubTrack
            HStack {
                Button { onStep(-1) } label: { stepLabel(Icon.back, "上一" + unit) }
                    .buttonStyle(ChapterStepButtonStyle(normal: tint))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .disabled(chapter == 0).opacity(chapter == 0 ? 0.35 : 1)
                    .accessibilityIdentifier("reader.previousChapter")
                Button { onStep(1) } label: { stepLabel(Icon.disclosure, "下一" + unit) }
                    .buttonStyle(ChapterStepButtonStyle(normal: tint))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .disabled(chapter + 1 >= count).opacity(chapter + 1 >= count ? 0.35 : 1)
                    .accessibilityIdentifier("reader.nextChapter")
            }
        }
        .buttonStyle(.plain)
        .onChange(of: chapter) { _, _ in if dragging { invalidated = true } }
    }

    /// 自绘滑杆（构建 136）：轨道 3pt（底 Theme.line、已读 Theme.clay），滑块为 18pt 陶土实心圆，
    /// 取代系统 Slider 的钴蓝粗轨与白色药丸滑块。拖动语义与原 Slider 完全一致：按下记原点、
    /// 拖动只改草稿、松手才提交；外部改章会作废本次拖动；VoiceOver 用可调动作即时步进提交。
    private var scrubTrack: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let maximum = Double(max(1, count - 1))
            let value = dragging ? draft : Double(chapter)
            let fraction = min(1, max(0, value / maximum))
            // 滑块中心在轨道内缩一个半径行程，填充宽度正好到达滑块中心。
            let knobCenter = 9 + fraction * max(0, width - 18)
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.line).frame(height: 3)
                Capsule().fill(Theme.clay).frame(width: knobCenter, height: 3)
                Circle().fill(Theme.clay).frame(width: 18, height: 18).offset(x: knobCenter - 9)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        if !dragging {
                            originChapter = chapter; draft = Double(chapter); invalidated = false; dragging = true
                        }
                        let span = max(1, width - 18)
                        let ratio = min(1, max(0, (gesture.location.x - 9) / span))
                        draft = ratio * maximum
                    }
                    .onEnded { _ in
                        let target = shown
                        dragging = false
                        if !invalidated && chapter == originChapter && target != chapter { onCommit(target) }
                    },
                including: count > 1 ? .all : .none
            )
        }
        .frame(height: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isPDF ? "页码进度" : "章节进度")
        .accessibilityValue("第 \(shown + 1) \(unit)，共 \(count) \(unit)")
        .accessibilityIdentifier("reader.chapter-progress")
        .accessibilityAdjustableAction { direction in
            if direction == .increment { onCommit(min(count - 1, chapter + 1)) }
            else if direction == .decrement { onCommit(max(0, chapter - 1)) }
        }
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
        .padding(.horizontal, 8).frame(minHeight: 44).contentShape(Rectangle())
    }
}

/// 上一章/下一章按钮：常态用传入的墨色，按下时整体转陶土强调（前景由样式统一施加，
/// 标签内部不再单独着色，否则显式色会压过样式）。
private struct ChapterStepButtonStyle: ButtonStyle {
    let normal: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(configuration.isPressed ? Theme.accent : normal)
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
    var showsPreview = true
    @Environment(\.dismiss) var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage("reader.fontSize") private var size = 19.0
    @AppStorage("reader.lineSpacing") private var spacing = 11.0
    @AppStorage("reader.font") private var font = "system"
    @AppStorage("reader.paper") private var paper = "paper"
    @AppStorage("study.paperAlwaysLight") private var paperAlwaysLight = false
    @AppStorage("reader.scrolling") private var scrolling = false
    @AppStorage("reader.pageTurn") private var pageTurn = "slide"
    private let mainPapers: [ReaderPaper] = [.paper, .white, .mist, .ancient, .night]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("设置只影响正文，原书图文也会同步应用。")
                    .font(Theme.sans(12)).foregroundStyle(Theme.ink3)
                if showsPreview {
                    Text("清晨，湖面还没有醒来。\n让光缓缓移过纸面。")
                        .font(Font(ReaderPreferences(fontSize: size, font: font).uiFont))
                        .lineSpacing(spacing)
                        .foregroundStyle(ReaderPreferences(paper: paper).foreground)
                        .padding(20)
                        .frame(maxWidth: .infinity, minHeight: 136, alignment: .topLeading)
                        .background(ReaderPreferences(paper: paper).background, in: RoundedRectangle(cornerRadius: 16))
                        .accessibilityLabel("排版预览")
                }

                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Text("字号").font(Theme.sans(15, weight: .medium))
                        stepButton("A−", label: "减小字号") { size = max(14, size - 1) }
                        Spacer(minLength: 0)
                        Text("\(Int(size))").font(Theme.sans(15, weight: .medium)).monospacedDigit()
                        stepButton("A+", label: "增大字号") { size = min(34, size + 1) }
                    }
                    Slider(value: $size, in: 14...34, step: 1)
                        .accessibilityLabel("字号").accessibilityValue("\(Int(size))")
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("字体").font(Theme.sans(12)).foregroundStyle(Theme.ink3)
                        Spacer()
                        NavigationLink { MyFontsView() } label: {
                            Text(font.hasPrefix("custom:") ? (FontLibrary.fonts.first { "custom:" + $0.postScript == font }?.name ?? "我的字体") : "我的字体")
                                .font(Theme.sans(12)).lineLimit(2).frame(minHeight: 44)
                        }
                    }
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(spacing: 8) { fontChoices }
                    } else {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) { fontChoices }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("纸色").font(Theme.sans(12)).foregroundStyle(Theme.ink3)
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
                            .font(Theme.sans(12)).frame(minHeight: 44)
                        }
                        .accessibilityLabel("全部纸色")
                    }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: dynamicTypeSize.isAccessibilitySize ? 3 : 5), spacing: 12) {
                        ForEach(mainPapers) { item in
                            Button { Haptics.selection(); paper = item.rawValue } label: {
                                VStack(spacing: 8) {
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(item == .paper ? ReaderPaper.xuan : item.swatch)
                                        .frame(maxWidth: .infinity).frame(height: 44)
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 12)
                                                .strokeBorder(paper == item.rawValue ? Theme.accent : Theme.line, lineWidth: paper == item.rawValue ? 2 : 1)
                                        }
                                        .overlay {
                                            if paper == item.rawValue {
                                                ThemeIcon(symbol: Icon.checkmark, size: 18)
                                                    .foregroundStyle(ReaderPreferences(paper: item.rawValue).foreground)
                                            }
                                        }
                                    Text(item.name).font(.caption2).foregroundStyle(Theme.ink3)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(item.name)
                            .accessibilityAddTraits(paper == item.rawValue ? .isSelected : [])
                        }
                    }
                }

                Toggle(isOn: $paperAlwaysLight) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("浅纸常亮").font(Theme.sans(15, weight: .medium))
                        Text("深色外观下，纸色也保持日间值")
                            .font(Theme.sans(12)).foregroundStyle(Theme.ink3)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))

                Picker("翻页方式", selection: $scrolling) {
                    Text("左右翻页").tag(false)
                    Text("上下滚动").tag(true)
                }
                .pickerStyle(.segmented)

                if !scrolling {
                    Picker("翻页动画", selection: $pageTurn) {
                        Text("滑动").tag("slide")
                        Text("淡入").tag("fade")
                        Text("模糊").tag("blur")
                        Text("无").tag("none")
                    }
                    .pickerStyle(.segmented)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                NavigationLink { MoreTypographyView() } label: {
                    HStack(spacing: 12) {
                        ThemeIcon(symbol: Icon.moreTypography, size: 24)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("更多排版").font(Theme.sans(15, weight: .medium))
                            Text("行距、段距、页边距与简繁转换")
                                .font(Theme.sans(12)).foregroundStyle(Theme.ink3)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        ThemeIcon(symbol: Icon.disclosure, size: 18)
                    }
                    .foregroundStyle(Theme.ink)
                    .padding(16)
                    .frame(minHeight: 64)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
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
                .buttonStyle(PrimaryButtonStyle(height: 50))
                .padding(.horizontal, 24).padding(.vertical, 12)
                .frame(maxWidth: 620).frame(maxWidth: .infinity)
                .background(Theme.bg)
        }
    }

    @ViewBuilder private var fontChoices: some View {
        fontChip("serif", "思源宋体")
        fontChip("kai", "霞鹜文楷")
        fontChip("hansans", "思源黑体")
        fontChip("xixihei", "霞鹜新晰黑")
        fontChip("system", "系统字体")
    }

    private func fontChip(_ key: String, _ title: String) -> some View {
        Button { Haptics.selection(); font = key } label: {
            Text(L(title)).font(Theme.sans(12))
                .foregroundStyle(font == key ? Theme.onAccent : Theme.ink3)
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(font == key ? Theme.accent : Theme.surface2, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(font == key ? .isSelected : [])
    }

    private func stepButton(_ text: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text).font(Theme.sans(15, weight: .medium))
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
    /// 阅读工具采用实体圆角表面，深浅取决于正文纸色，而非系统材质。
    func readerPaperPanel(paper: Color, ink: Color) -> some View {
        self.background(paper, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
