import SwiftUI
import Combine
import UIKit
import ReadiumShared
import ReadiumNavigator

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
    private(set) var bridge: LocatorBridge?
    private(set) var initialOriginal: JSONValue?
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
    func open(book: Book, store: PublicationStore, progress: ReadingProgress, counts: [Int], target: LocatorTarget? = nil, displayMode: String = "none") async {
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
            let bridge = try LocatorBridge(book: book, map: map, publication: publication)
            let resolved = try await bridge.resolve(target ?? .init(progress))
            guard let initial = try await bridge.displayLocator(resolved.locator, mode: displayMode) else {
                throw ReaderError.message(String(localized: "无法将当前章节映射到 EPUB 资源。阅读位置已保留，请用修书补齐原文件后重试。"))
            }
            let displayed: Publication
            if EPUBTextTransform.enabled(displayMode) { displayed = try await service.open(file.url, displayMode: displayMode) }
            else { displayed = publication }
            let chapter = resolved.target.chapter
            try Task.checkCancellation()
            guard generation == token else { throw CancellationError() }
            self.store = store; pin = file; acquired = nil
            self.map = map; initialLocation = initial; initialChapter = chapter
            self.bridge = bridge; initialOriginal = resolved.locator
            contents = rows
            self.publication = displayed
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
        publication = nil; initialLocation = nil; map = nil; contents = []; bridge = nil; initialOriginal = nil
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
    @State private var sessionEpoch: UUID?
    @State private var originalLocation: JSONValue?
    @State private var expectedOriginal: JSONValue?
    @State private var decorations: [Decoration] = []
    @State private var speechDecorations: [Decoration] = []
    @State private var searchDecorations: [Decoration] = []
    @State private var startSpeechTask: Task<Void, Never>?
    @State private var speechTask: Task<Void, Never>?
    @State private var searchTask: Task<Void, Never>?
    @State private var following = false
    @State private var audioActive = false
    @State private var audioPlaying = false
    @State private var speechNavigation = false
    @State private var pendingSearch: Decoration?
    @State private var unresolvedAnnotations: [UUID] = []
    @State private var draft: Highlight?
    @State private var locationTask: Task<Void, Never>?
    @State private var jumpTask: Task<Void, Never>?
    @State private var locationGeneration = UUID()
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
    private enum Sheet: String, Identifiable { case contents, preferences, player, annotation, note, search; var id: String { rawValue } }
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
                        fonts: fonts, request: request, decorations: decorations,
                        speechDecorations: speechDecorations, searchDecorations: searchDecorations,
                        onSelection: selection, onDecoration: activateDecoration,
                        onLocation: locationChanged,
                        onTap: { withAnimation(.snappy(duration: 0.25)) { chrome.toggle() } },
                        onError: { session.error = $0; updateVisibility() }
                    )
                    .accessibilityIdentifier("reader.epubNavigator")
                    .simultaneousGesture(DragGesture(minimumDistance: 12).onChanged { _ in
                        guard expectedLocation == nil else { return }
                        following = false; speechNavigation = false
                    })
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
            locationTask?.cancel(); jumpTask?.cancel(); speechTask?.cancel(); startSpeechTask?.cancel(); searchTask?.cancel(); locationGeneration = UUID()
            session.close()
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { persist() } }
        .onChange(of: sheet) { _, value in
            updateVisibility()
            if value == nil { refreshSpeech(playing: model.player.playing, chapter: model.player.chapter, position: model.player.position) }
        }
        .task(id: annotationKey) { await refreshAnnotations() }
        .onChange(of: model.publicationGeneration[book.id]) { _, _ in
            locationTask?.cancel(); jumpTask?.cancel(); speechTask?.cancel(); startSpeechTask?.cancel(); searchTask?.cancel(); locationGeneration = UUID()
            ready = false; sheet = nil; draft = nil; session.close(); retry = UUID()
        }
        .onChange(of: convert) { _, _ in
            persist(); ready = false; session.close(); retry = UUID()
        }
        .onChange(of: model.readerJump) { _, jump in
            guard let jump, jump.id == book.id, session.bridge != nil else { return }
            jumpTo(jump.target, explicit: true)
        }
        .onReceive(model.player.$playing.combineLatest(model.player.$chapter, model.player.$position).receive(on: DispatchQueue.main)) { _ in
            refreshSpeech(playing: model.player.playing, chapter: model.player.chapter, position: model.player.position)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshSpeech(playing: model.player.playing, chapter: model.player.chapter, position: model.player.position) }
        }
        .onChange(of: font) { _, _ in fonts = ReadiumFontProvider.files() }
        .onReceive(model.$selectedBook) { selected in
            guard selected?.id == book.id, session.publication != nil, let jump = model.readerJump, jump.id == book.id else { return }
            jumpTo(jump.target, explicit: true)
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
                                Text("EPUB 使用标准翻页。简繁转换仅作用于显示，摘记保存原文位置。")
                                    .font(.footnote).foregroundStyle(Theme.ink3).padding(12).frame(maxWidth: .infinity).background(Theme.bg)
                            }
                    }
                case .contents: NavigationStack { contentsView }
                case .player: PlayerView(player: model.player, fromReader: true)
                case .search:
                    NavigationStack {
                        ContentsView(book: book, chapters: book.chapters, currentChapter: chapter,
                                     bookmarks: entry?.bookmarks ?? [], startsSearching: true,
                                     onTarget: { target in jumpTo(target, search: true); sheet = nil }) { c, p in
                            jumpTo(chapter: c, position: p); sheet = nil
                        }
                    }
                case .annotation: annotationPanel
                case .note:
                    if let draft {
                        NoteEditor(quote: draft.text, text: draft.note ?? "") { note in
                            var changed = draft; changed.note = note.isEmpty ? nil : note
                            saveAnnotation(changed)
                        }
                    }
                }
            }
            .environmentObject(model).tint(Theme.accent)
            .presentationDetents([.large]).presentationDragIndicator(.visible)
        }
    }
    private var topBar: some View {
        HStack(spacing: 12) {
            Button { persist(); dismiss() } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                .accessibilityLabel("返回").accessibilityIdentifier("reader.back")
            Text(title).accessibilityIdentifier("reader.currentTitle").font(Theme.sans(14, weight: .medium)).lineLimit(1).frame(maxWidth: .infinity)
            Button {
                let text = book.chapters.indices.contains(chapter) ? Sentence.split(book.chapters[chapter].text).dropFirst(position).first?.text ?? "" : ""
                model.bookmark(book.id, chapter: chapter, position: position, excerpt: text,
                               locator: originalLocation, revision: session.bridge?.revision, generation: sessionEpoch)
            } label: {
                Image(systemName: entry?.bookmarks.contains(where: { $0.chapter == chapter && $0.position == position }) == true ? "bookmark.fill" : "bookmark")
                    .frame(width: 44, height: 44)
            }.disabled(!ready || !mappedChapter).accessibilityLabel("书签").accessibilityIdentifier("reader.bookmark")
        }
        .padding(.horizontal, 12)
        .background(Color(hex: palette.background))
    }
    private var bottomBar: some View {
        HStack(spacing: 0) {
            chromeButton("目录", symbol: "list.bullet") { sheet = .contents }.accessibilityIdentifier("reader.contents")
            chromeButton("听书", symbol: "headphones", enabled: mappedChapter) {
                startSpeech()
            }
            .accessibilityIdentifier("reader.listen")
            if audioActive {
                chromeButton(audioPlaying ? "暂停" : "继续", symbol: audioPlaying ? "pause.fill" : "play.fill") {
                    if model.player.playing { model.player.pause() } else { model.player.resume() }
                }.accessibilityIdentifier("reader.toggle")
                .accessibilityLabel(audioPlaying ? "暂停朗读" : "继续朗读")
                chromeButton(following ? "停止跟随" : "回到朗读", symbol: "text.line.first.and.arrowtriangle.forward") {
                    if following {
                        following = false
                    } else if model.player.playing {
                        following = true
                        refreshSpeech(playing: true, chapter: model.player.chapter, position: model.player.position)
                    } else {
                        jumpTo(ReadiumSpeechBridge.sentence(book: book, chapter: model.player.chapter, position: model.player.position))
                    }
                }.accessibilityIdentifier("reader.returnToSpeech")
                .accessibilityValue(speechDecorations.isEmpty ? "无跟读高亮" : "跟读高亮")
            }
            chromeButton("设置", symbol: "textformat.size") { sheet = .preferences }.accessibilityIdentifier("reader.preferences")
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
            Button("搜索书内文字") { following = false; sheet = .search }.accessibilityIdentifier("reader.search")
            if !session.contents.isEmpty {
                ForEach(session.contents) { item in
                    Button {
                        navigateLink(item.link)
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
            Section("书签") {
                ForEach(entry?.bookmarks ?? []) { mark in
                    Button(mark.excerpt) { jumpTo(.init(mark)); sheet = nil }
                        .swipeActions { Button("删除", role: .destructive) { model.removeBookmark(book.id, id: mark.id) } }
                }
            }
            Section("摘记") {
                if !unresolvedAnnotations.isEmpty { Text("有 \(unresolvedAnnotations.count) 条标注尚未定位，原文与笔记已保留。").font(.caption) }
                NotesList(entryID: book.id, unresolvedIDs: Set(unresolvedAnnotations)) { note in jumpTo(.init(note)); sheet = nil }
            }
        }
        .accessibilityIdentifier("reader.epubContents")
        .navigationTitle("目录").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { sheet = nil } } }
    }
    @MainActor private func open() async {
        ready = false; mappedChapter = false
        speechDecorations = []; searchDecorations = []; pendingSearch = nil; speechNavigation = false
        locationTask?.cancel(); jumpTask?.cancel(); speechTask?.cancel(); startSpeechTask?.cancel(); searchTask?.cancel(); locationGeneration = UUID()
        request = nil; expectedLocation = nil; expectedChapter = nil; expectedOriginal = nil
        updateVisibility()
        do {
            sessionEpoch = model.publicationGeneration[book.id]
            let stored = entry?.progress ?? .init()
            let jump = model.readerJump.flatMap { $0.id == book.id ? $0 : nil }
            pendingJump = jump.map { ($0.chapter, $0.position) }
            chapter = stored.chapter; position = stored.position
            await session.open(book: book, store: try model.publicationStore(), progress: stored, counts: counts,
                               target: jump?.target, displayMode: convert)
            guard !Task.isCancelled, session.publication != nil else { return }
            expectedLocation = session.initialLocation; expectedChapter = session.initialChapter
            expectedOriginal = session.initialOriginal; originalLocation = session.initialOriginal
            if let latest = model.readerJump, latest.id == book.id, latest != jump { jumpTo(latest.target, explicit: true) }
            await refreshAnnotations()
            refreshSpeech(playing: model.player.playing, chapter: model.player.chapter, position: model.player.position)
        } catch { session.error = error.localizedDescription }
    }
    private func navigateLink(_ link: ReadiumShared.Link) {
        following = false
        guard let bridge = session.bridge else { return }
        jumpTask?.cancel()
        jumpTask = Task { @MainActor in
            guard let result = await bridge.resolve(link: link), let locator = try? await bridge.displayLocator(result.locator, mode: convert), !Task.isCancelled, session.bridge === bridge else { return }
            speechNavigation = false; pendingSearch = nil
            expectedLocation = locator; expectedOriginal = result.locator
            expectedChapter = bridge.map?.chapter(for: locator.href.string)
            request = .init(locator: locator)
        }
    }
    private func jumpTo(chapter: Int, position: Int, explicit: Bool = false) {
        jumpTo(.init(chapter: chapter, position: position), explicit: explicit)
    }
    private func jumpTo(_ target: LocatorTarget, explicit: Bool = false, search: Bool = false) {
        following = false
        guard let bridge = session.bridge else { return }
        jumpTask?.cancel()
        jumpTask = Task { @MainActor in
            do {
                let resolved = try await bridge.resolve(target)
                let locator = try await bridge.displayLocator(resolved.locator, mode: convert)
                try Task.checkCancellation()
                guard session.bridge === bridge else { return }
                guard let locator else { throw ReaderError.message("无法定位所选原文，标注已保留。") }
                var hitDecoration: Decoration?
                if search, target.textRange != nil, resolved.precise, let hit = try await bridge.displayLocator(resolved.locator, mode: convert, requireRange: true) {
                    hitDecoration = Decoration(id: "search-hit", locator: hit, style: ReadiumAnnotations.style(color: "yellow", kind: "background"))
                }
                try Task.checkCancellation()
                guard session.bridge === bridge else { return }
                speechNavigation = false; pendingSearch = hitDecoration
                expectedOriginal = resolved.locator; expectedLocation = locator; expectedChapter = resolved.target.chapter
                if explicit { pendingJump = (target.chapter, target.position) }
                request = .init(locator: locator)
            } catch is CancellationError {} catch { model.message = error.localizedDescription }
        }
    }
    private func locationChanged(resource: Int?, locator: ReadiumShared.Locator, confirmedRequest: UUID?) {
        guard session.error == nil, let bridge = session.bridge else { return }
        if expectedLocation != nil, let request, confirmedRequest != request.id { return }
        if let expectedLocation, PublicationMap.normalized(expectedLocation.href.string) != PublicationMap.normalized(locator.href.string) { return }
        locationTask?.cancel()
        let token = UUID(); locationGeneration = token
        let pending = expectedOriginal, mode = convert
        locationTask = Task { @MainActor in
            do {
                let input = StoredLocator.readium(pending) ?? locator
                let result = try await bridge.reverse(input, chapterHint: expectedChapter ?? chapter,
                                                      displayMode: pending == nil ? mode : "none")
                try Task.checkCancellation()
                guard locationGeneration == token, session.bridge === bridge else { return }
                mappedChapter = result.status != .unresolved
                currentTitle = locator.title
                guard mappedChapter else { ready = true; updateVisibility(); return }
                chapter = result.target.chapter; position = result.target.position
                originalLocation = result.locator
                if let pendingSearch { showSearch(pendingSearch); self.pendingSearch = nil }
                expectedLocation = nil; expectedChapter = nil; expectedOriginal = nil
                if let pendingJump, let jump = model.readerJump, jump.id == book.id,
                   jump.chapter == pendingJump.chapter, jump.position == pendingJump.position { model.readerJump = nil }
                pendingJump = nil
                if !ready { model.recordActivity(.reading, for: book.id) }
                ready = true; updateVisibility(); persist()
            } catch is CancellationError {} catch { model.message = error.localizedDescription }
        }
    }
    private func persist() {
        guard ready, mappedChapter, !following, !speechNavigation, expectedLocation == nil, session.error == nil else { return }
        // 与 ReaderView.persist 共用 sync.update / TextAnchor / KVS / 1200ms catalog 防抖。
        model.saveProgress(book.id, chapter: chapter, position: position, locator: originalLocation, revision: session.bridge?.revision, generation: sessionEpoch)
    }
    private var annotationKey: String {
        let data = (try? Integrity.encoder().encode(entry?.notes ?? [])) ?? Data()
        return PublicationDigest.data(data) + convert + String(session.publication != nil)
    }
    @MainActor private func refreshAnnotations() async {
        guard let bridge = session.bridge else { return }
        let key = annotationKey
        do {
            let batch = try await ReadiumAnnotations.decorations(entry?.notes ?? [], bridge: bridge, mode: convert)
            try Task.checkCancellation()
            guard key == annotationKey, session.bridge === bridge else { return }
            decorations = batch.decorations; unresolvedAnnotations = batch.unresolved
        } catch is CancellationError {} catch { model.message = error.localizedDescription }
    }
    private func selection(_ locator: ReadiumShared.Locator, action: ReadiumAnnotations.SelectionAction) {
        guard let bridge = session.bridge else { return }
        Task { @MainActor in
            do {
                let result = try await bridge.reverse(locator, chapterHint: chapter, displayMode: convert)
                guard visible, session.bridge === bridge, sessionEpoch == model.publicationGeneration[book.id] else { return }
                guard result.precise, let raw = result.locator else { throw ReaderError.message("选区无法与原文精确对齐，请重新选择。") }
                let target = result.target
                if action == .bookmark {
                    model.bookmark(book.id, chapter: target.chapter, position: target.position, excerpt: target.text ?? "",
                                   locator: raw, revision: bridge.revision, generation: sessionEpoch)
                } else {
                    draft = Highlight(chapter: target.chapter, start: target.position, end: target.end ?? target.position,
                                      text: target.text ?? "", anchor: target.anchor, locator: raw,
                                      locatorVersion: LocatorBridge.version, publicationRevision: bridge.revision,
                                      color: ReaderMark.newColor(UserDefaults.standard.string(forKey: "highlight.lastColor")),
                                      style: UserDefaults.standard.string(forKey: "highlight.lastStyle") ?? "background")
                    sheet = action == .note ? .note : .annotation
                }
            } catch { model.message = error.localizedDescription }
        }
    }
    private func activateDecoration(_ id: String) {
        guard let item = entry?.notes.first(where: { $0.id.uuidString == id }) else { return }
        draft = item; sheet = .annotation
    }
    @ViewBuilder private var annotationPanel: some View {
        if let draft {
            SelectionPanel(text: draft.text, existing: entry?.notes.first { $0.id == draft.id },
                           canExtendBack: false, canExtendForward: false, tint: Color(hex: palette.foreground),
                           paper: Color(hex: palette.background), accent: Theme.accent,
                           onMark: { color, style in var changed = draft; changed.color = color; changed.style = style; saveAnnotation(changed) },
                           onRemove: { model.removeHighlight(book.id, id: draft.id); sheet = nil },
                           onNote: { sheet = .note },
                           onListen: { model.startListening(book, showPlayer: false, from: .init(chapter: draft.chapter, position: draft.start)); sheet = .player },
                           onCopy: { UIPasteboard.general.string = draft.text }, onExtend: { _ in }, onClose: { sheet = nil })
        }
    }
    private func saveAnnotation(_ highlight: Highlight) {
        guard sessionEpoch == model.publicationGeneration[book.id] else { return }
        if entry?.notes.contains(where: { $0.id == highlight.id }) == true { model.updateHighlight(book.id, highlight) }
        else { model.addHighlight(book.id, highlight) }
        sheet = nil
    }
    private func startSpeech() {
        guard ready, expectedLocation == nil, let bridge = session.bridge else { return }
        startSpeechTask?.cancel()
        startSpeechTask = Task { @MainActor in
            do {
                await locationTask?.value
                try Task.checkCancellation()
                let progress = try await ReadiumSpeechBridge.start(visible: originalLocation, chapter: chapter, position: position, bridge: bridge)
                try Task.checkCancellation()
                guard visible, session.bridge === bridge, sessionEpoch == model.publicationGeneration[book.id] else { return }
                following = true
                model.startListening(book, showPlayer: false, from: progress)
                sheet = .player
            } catch is CancellationError {} catch { model.message = error.localizedDescription }
        }
    }
    private func refreshSpeech(playing: Bool, chapter c: Int, position p: Int) {
        speechTask?.cancel()
        audioActive = model.player.book?.id == book.id
        audioPlaying = playing && audioActive
        guard playing, audioActive, let bridge = session.bridge else { speechDecorations = []; return }
        let mode = convert
        speechTask = Task { @MainActor in
            do {
                let (result, locator, mark) = try await ReadiumSpeechBridge.playback(chapter: c, position: p, bridge: bridge, mode: mode)
                try Task.checkCancellation()
                guard visible, session.bridge === bridge, sessionEpoch == model.publicationGeneration[book.id] else { return }
                speechDecorations = mark.map { [$0] } ?? []
                if following, sheet != .player, scenePhase == .active {
                    speechNavigation = true
                    expectedOriginal = result.locator; expectedLocation = locator; expectedChapter = result.target.chapter
                    request = .init(locator: locator)
                }
            } catch is CancellationError {} catch { speechDecorations = [] }
        }
    }
    private func showSearch(_ decoration: Decoration) {
        searchTask?.cancel(); searchDecorations = [decoration]
        searchTask = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(2)); try Task.checkCancellation(); searchDecorations = [] }
            catch {}
        }
    }
    private func updateVisibility() {
        model.setReadingSurface(book.id, visible: visible && ready && session.error == nil && sheet != .player)
    }
}
