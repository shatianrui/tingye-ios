import SwiftUI
import ReadiumShared

/// 资源内比例与旧章句之间的近似转换。绝不使用 Readium locations.position 作为句序号。
enum EPUBApproximateProgress {
    static func progression(position: Int, sentenceCount: Int) -> Double {
        Double(min(max(0, position), max(0, sentenceCount - 1))) / Double(max(1, sentenceCount))
    }
    static func position(progression: Double, sentenceCount: Int) -> Int {
        guard progression.isFinite else { return 0 }
        return min(max(0, sentenceCount - 1), max(0, Int((min(1, max(0, progression)) * Double(max(1, sentenceCount))).rounded(.down))))
    }
}

@MainActor
final class ReadiumReaderSession: ObservableObject {
    struct ContentsItem: Identifiable {
        let id: String
        let link: ReadiumShared.Link
        let depth: Int
    }
    @Published private(set) var publication: Publication?
    @Published private(set) var contents: [ContentsItem] = []
    @Published var error: String?
    @Published private(set) var loading = false
    private(set) var map: PublicationMap?
    private(set) var initialLocation: ReadiumShared.Locator?
    private(set) var initialChapter = 0
    private var store: PublicationStore?
    private var pin: PublicationStore.SessionFile?
    private let service = ReadiumService()
    private var generation = UUID()
    private var bookID: String?

    static func flatten(_ links: [ReadiumShared.Link], prefix: String = "", depth: Int = 0) -> [ContentsItem] {
        links.enumerated().flatMap { index, link in
            let id = prefix + String(index)
            return [ContentsItem(id: id, link: link, depth: depth)] + flatten(link.children, prefix: id + ".", depth: depth + 1)
        }
    }
    func open(book: Book, store: PublicationStore, progress: ReadingProgress, counts: [Int]) async {
        // SwiftUI 重复求值/同书再打开复用当前会话；有错误时重试才重新 prepare/pin。
        guard bookID != book.id || error != nil || (!loading && publication == nil) else { return }
        close()
        bookID = book.id
        let token = generation
        loading = true; error = nil
        var acquired: PublicationStore.SessionFile?
        do {
            let prepared = try await store.prepare(book)
            let file = try await store.pin(prepared)
            acquired = file
            try Task.checkCancellation()
            let publication = try await service.open(file.url)
            // 无目录不是打开失败：退到文本层章列表。
            let toc = (try? await publication.tableOfContents().get()) ?? []
            let rows = Self.flatten(toc)
            var titles: [String: String] = [:]
            for link in publication.readingOrder { titles[link.href] = link.title }
            for row in rows {
                if let href = publication.readingOrder.first(where: { PublicationMap.normalized($0.href) == PublicationMap.normalized(row.link.href) })?.href,
                   titles[href] == nil { titles[href] = row.link.title }
            }
            let map = prepared.map ?? PublicationMap(book: book, readingOrder: publication.readingOrder.map(\.href), titles: titles, revision: prepared.revision)
            let chapter = min(max(0, progress.chapter), max(0, book.chapters.count - 1))
            guard let initial = Self.location(chapter: chapter, position: progress.position, counts: counts, map: map, publication: publication) else {
                throw ReaderError.message(String(localized: "无法将当前章节映射到 EPUB 资源。阅读位置已保留，请用修书补齐原文件后重试。"))
            }
            try Task.checkCancellation()
            guard generation == token else { throw CancellationError() }
            self.store = store; pin = file; acquired = nil
            self.map = map; initialLocation = initial; initialChapter = chapter
            contents = rows
            self.publication = publication
            loading = false
        } catch {
            if let acquired { await store.release(acquired) }
            guard generation == token else { return }
            loading = false
            self.error = error is CancellationError ? String(localized: "EPUB 打开已取消，请重试。") : error.localizedDescription
        }
    }
    static func location(chapter: Int, position: Int, counts: [Int], map: PublicationMap, publication: Publication) -> ReadiumShared.Locator? {
        guard let href = map.href(for: chapter),
              let link = publication.readingOrder.first(where: { PublicationMap.normalized($0.href) == PublicationMap.normalized(href) }) else { return nil }
        let count = counts.indices.contains(chapter) ? counts[chapter] : 0
        return ReadiumShared.Locator(href: link.url(), mediaType: link.mediaType ?? .xhtml, title: link.title,
                                    locations: .init(progression: EPUBApproximateProgress.progression(position: position, sentenceCount: count)))
    }
    func close() {
        generation = UUID()
        bookID = nil; loading = false
        publication = nil; initialLocation = nil; map = nil; contents = []
        if let pin, let store { Task { await store.release(pin) } }
        pin = nil; store = nil
    }
    deinit {
        if let pin, let store { Task { await store.release(pin) } }
    }
}

struct ReadiumReaderView: View {
    let book: Book
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var session = ReadiumReaderSession()
    @State private var chapter = 0
    @State private var position = 0
    @State private var currentTitle: String?
    @State private var mappedChapter = false
    @State private var ready = false
    @State private var visible = false
    @State private var chrome = true
    @State private var sheet: Sheet?
    @State private var retry = UUID()
    @State private var request: EPUBNavigatorHost.Request?
    @State private var expectedLocation: ReadiumShared.Locator?
    @State private var expectedChapter: Int?
    @State private var pendingJump: (chapter: Int, position: Int)?
    @State private var fonts = ReadiumFontProvider.files()
    @AppStorage("reader.fontSize") private var fontSize = 19.0
    @AppStorage("reader.lineSpacing") private var lineSpacing = 11.0
    @AppStorage("reader.font") private var font = "system"
    @AppStorage("reader.paper") private var paper = "paper"
    @AppStorage("reader.scrolling") private var scrolling = false
    @AppStorage("reader.paragraphSpacing") private var paragraphSpacing = 15.0
    @AppStorage("reader.margin") private var margin = 24.0
    @AppStorage("reader.indent") private var indent = true
    @AppStorage("reader.justified") private var justified = true
    @AppStorage("reader.doublePage") private var doublePage = true
    @AppStorage("reader.letterSpacing") private var letterSpacing = 0.0
    @AppStorage("reader.convert") private var convert = "none"
    @AppStorage("study.paperAlwaysLight") private var alwaysLight = false
    @AppStorage("app.appearance") private var appearance = "system"
    private enum Sheet: String, Identifiable { case contents, preferences, player; var id: String { rawValue } }
    private var entry: ShelfEntry? { model.entries.first { $0.id == book.id } }
    private var prefs: ReaderPreferences {
        .init(fontSize: fontSize, lineSpacing: lineSpacing, font: font, paper: paper, scrolling: scrolling,
              paragraphSpacing: paragraphSpacing, margin: margin, indent: indent, justified: justified,
              letterSpacing: letterSpacing, convert: convert)
    }
    private var darkAppearance: Bool { appearance == "dark" || (appearance == "system" && colorScheme == .dark) }
    private var palette: ReaderPaper.Palette { prefs.kind.resolve(darkAppearance: darkAppearance, alwaysLight: alwaysLight) }
    private var counts: [Int] {
        if let counts = entry?.sentenceCounts, counts.count == book.chapters.count { return counts }
        return book.chapters.map { Sentence.split($0.text).count }
    }
    private var title: String {
        if mappedChapter, book.chapters.indices.contains(chapter), !book.chapters[chapter].title.isEmpty { return book.chapters[chapter].title }
        return currentTitle ?? book.title
    }
    var body: some View {
        ZStack {
            Color(hex: palette.background).ignoresSafeArea()
            GeometryReader { geometry in
                if let publication = session.publication, let initial = session.initialLocation {
                    EPUBNavigatorHost(
                        publication: publication, initialLocation: initial,
                        preferences: ReadiumPreferencesBridge.preferences(
                            prefs, darkAppearance: darkAppearance, alwaysLight: alwaysLight,
                            doublePage: doublePage, viewportWidth: geometry.size.width,
                            fixedLayout: publication.metadata.layout == .fixed,
                            fontFamily: ReadiumFontProvider.family(for: font, files: fonts),
                            fontLineHeight: ReadiumFontProvider.lineHeight(for: font, size: fontSize, files: fonts)),
                        fonts: fonts, request: request, onLocation: locationChanged,
                        onTap: { withAnimation(.snappy(duration: 0.25)) { chrome.toggle() } },
                        onError: { session.error = $0; updateVisibility() }
                    )
                    .accessibilityIdentifier("reader.epubNavigator")
                }
            }
            if session.loading { ProgressView("正在打开 EPUB…") }
            if let error = session.error {
                VStack(spacing: 16) {
                    Text("EPUB 打开失败").font(.headline)
                    Text(error).font(.callout).multilineTextAlignment(.center)
                    Text("阅读位置和摘记已保留。可重试，或返回书架通过修书补齐文件。")
                        .font(.footnote).foregroundStyle(Color(hex: palette.secondary))
                    Button("重试") { persist(); ready = false; retry = UUID() }.buttonStyle(.borderedProminent)
                }
                .padding(24).frame(maxWidth: 500)
                .background(Color(hex: palette.background), in: RoundedRectangle(cornerRadius: 18))
                .padding(20)
            }
        }
        .overlay(alignment: .top) { if chrome || session.error != nil || session.loading { topBar } }
        .overlay(alignment: .bottom) { if chrome && ready && session.error == nil { bottomBar } }
        .foregroundStyle(Color(hex: palette.foreground))
        .toolbar(.hidden, for: .navigationBar)
        .statusBarHidden(true)
        .keepScreenAwake()
        .onAppear { visible = true; updateVisibility() }
        .task(id: retry) { await open() }
        .onDisappear {
            visible = false; updateVisibility(); persist(); model.readerClosed(book.id)
            session.close()
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { persist() } }
        .onChange(of: sheet) { _, _ in updateVisibility() }
        .onChange(of: font) { _, _ in fonts = ReadiumFontProvider.files() }
        .onReceive(model.$selectedBook) { selected in
            guard selected?.id == book.id, session.publication != nil, let jump = model.readerJump, jump.id == book.id else { return }
            jumpTo(chapter: jump.chapter, position: jump.position, explicit: true)
        }
        .sheet(item: $sheet, onDismiss: {
            fonts = ReadiumFontProvider.files()
            updateVisibility()
        }) { value in
            Group {
                switch value {
                case .preferences:
                    NavigationStack {
                        ReadingPreferencesView(showsPreview: false)
                            .safeAreaInset(edge: .bottom) {
                                Text("EPUB 使用标准翻页；简繁转换尚未支持，设置值会保留。")
                                    .font(.footnote).foregroundStyle(Theme.ink3).padding(12).frame(maxWidth: .infinity).background(Theme.bg)
                            }
                    }
                case .contents: NavigationStack { contentsView }
                case .player: PlayerView(player: model.player, fromReader: true)
                }
            }
            .environmentObject(model).tint(Theme.accent)
            .presentationDetents([.large]).presentationDragIndicator(.visible)
        }
    }
    private var topBar: some View {
        HStack(spacing: 12) {
            Button { persist(); dismiss() } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                .accessibilityLabel("返回")
            Text(title).font(Theme.sans(14, weight: .medium)).lineLimit(1).frame(maxWidth: .infinity)
            // 对称留白使章节标题始终居中。
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 12)
        .background(Color(hex: palette.background))
    }
    private var bottomBar: some View {
        HStack(spacing: 0) {
            chromeButton("目录", symbol: "list.bullet") { sheet = .contents }
            chromeButton("听书", symbol: "headphones", enabled: mappedChapter) {
                model.startListening(book, showPlayer: false, from: .init(chapter: chapter, position: 0))
                sheet = .player
            }
            chromeButton("设置", symbol: "textformat.size") { sheet = .preferences }
        }
        .padding(.vertical, 12)
        .background(Color(hex: palette.background).ignoresSafeArea(edges: .bottom))
    }
    private func chromeButton(_ title: LocalizedStringKey, symbol: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) { Image(systemName: symbol); Text(title).font(.caption) }
                .frame(maxWidth: .infinity, minHeight: 44)
        }.buttonStyle(.plain).disabled(!enabled)
    }
    private var contentsView: some View {
        List {
            if !session.contents.isEmpty {
                ForEach(session.contents) { item in
                    Button {
                        expectedLocation = nil; expectedChapter = nil
                        // go(to: ReadiumShared.Link) 由 Publication.locate 解释目录 fragment/type。
                        request = .init(link: item.link)
                        sheet = nil
                    } label: {
                        Text(item.link.title ?? item.link.href).padding(.leading, CGFloat(item.depth * 16))
                    }
                }
            } else {
                ForEach(book.chapters.indices, id: \.self) { index in
                    Button { jumpTo(chapter: index, position: 0); sheet = nil } label: { Text(book.chapters[index].title) }
                        .disabled(session.map?.href(for: index) == nil)
                }
            }
        }
        .navigationTitle("目录").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { sheet = nil } } }
    }
    @MainActor private func open() async {
        ready = false; mappedChapter = false
        request = nil; expectedLocation = nil; expectedChapter = nil
        updateVisibility()
        do {
            let stored = entry?.progress ?? .init()
            let jump = model.readerJump.flatMap { $0.id == book.id ? $0 : nil }
            if let jump, !book.chapters.indices.contains(jump.chapter) {
                session.close()
                session.error = String(localized: "无法将当前章节映射到 EPUB 资源。阅读位置已保留，请用修书补齐原文件后重试。")
                return
            }
            let c = min(max(0, jump?.chapter ?? stored.chapter), max(0, book.chapters.count - 1))
            let sentences = book.chapters.indices.contains(c) ? Sentence.split(book.chapters[c].text) : []
            let p = jump?.position ?? Locator.resolve(position: stored.position, anchor: stored.anchor, in: sentences)
            pendingJump = jump.map { ($0.chapter, $0.position) }
            chapter = c; position = max(0, p)
            await session.open(book: book, store: try model.publicationStore(), progress: .init(chapter: c, position: position), counts: counts)
            guard !Task.isCancelled, session.publication != nil else { return }
            expectedLocation = session.initialLocation; expectedChapter = session.initialChapter
            // prepare/open 等待期间 selectedBook 可收到同书的新「从这里读」。以最新目标为准。
            if let latest = model.readerJump, latest.id == book.id,
               latest.chapter != jump?.chapter || latest.position != jump?.position {
                jumpTo(chapter: latest.chapter, position: latest.position, explicit: true)
            }
        } catch { session.error = error.localizedDescription }
    }
    private func jumpTo(chapter: Int, position: Int, explicit: Bool = false) {
        guard let map = session.map, let publication = session.publication,
              let locator = ReadiumReaderSession.location(chapter: chapter, position: position, counts: counts, map: map, publication: publication) else {
            session.error = String(localized: "无法将当前章节映射到 EPUB 资源。阅读位置已保留，请用修书补齐原文件后重试。")
            updateVisibility(); return
        }
        expectedLocation = locator; expectedChapter = chapter
        if explicit { pendingJump = (chapter, position) }
        request = .init(locator: locator)
    }
    private func locationChanged(resource: Int?, locator: ReadiumShared.Locator, confirmedRequest: UUID?) {
        guard session.error == nil, let resource, let publication = session.publication,
              publication.readingOrder.indices.contains(resource), let map = session.map else { return }
        // 防止初始化默认页回调抢先覆盖恢复/显式跳转；确认目标资源后才落盘和消费 readerJump。
        // UUID 同时隔离同一资源内连续两次跳转，旧 go 完成不能消费新请求。
        if expectedLocation != nil, let request, confirmedRequest != request.id { return }
        if let expectedLocation,
           PublicationMap.normalized(expectedLocation.href.string) != PublicationMap.normalized(locator.href.string) { return }
        let href = publication.readingOrder[resource].href
        let candidates = map.chapters.filter { PublicationMap.normalized($0.href) == PublicationMap.normalized(href) }
        let target = expectedChapter.flatMap { c in candidates.first { $0.chapterIndex == c } }
            ?? candidates.first { $0.chapterIndex == chapter } ?? candidates.first
        guard let target else {
            // 原包额外的非线性章/脚注没有旧文本章，不回写错误坐标。
            mappedChapter = false
            currentTitle = locator.title ?? publication.readingOrder[resource].title
            ready = true; updateVisibility(); return
        }
        mappedChapter = true
        chapter = target.chapterIndex
        let count = counts.indices.contains(chapter) ? counts[chapter] : 0
        position = EPUBApproximateProgress.position(progression: locator.locations.progression ?? 0, sentenceCount: count)
        currentTitle = locator.title
        expectedLocation = nil; expectedChapter = nil
        if let pendingJump, let jump = model.readerJump, jump.id == book.id,
           chapter == pendingJump.chapter,
           jump.chapter == pendingJump.chapter, jump.position == pendingJump.position {
            model.readerJump = nil
        }
        pendingJump = nil
        if !ready { model.recordActivity(.reading, for: book.id) }
        ready = true; updateVisibility(); persist()
    }
    private func persist() {
        guard ready, mappedChapter, expectedLocation == nil, session.error == nil else { return }
        // 与 ReaderView.persist 共用 sync.update / TextAnchor / KVS / 1200ms catalog 防抖。
        model.saveProgress(book.id, chapter: chapter, position: position)
    }
    private func updateVisibility() {
        model.setReadingSurface(book.id, visible: visible && ready && session.error == nil && sheet != .player)
    }
}
