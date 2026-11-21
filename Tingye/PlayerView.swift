import SwiftUI
import AVFoundation

/// 正在听：书籍信息、句流与播放控制按任务分区，保留句序号与原文定位。
/// 大字号或低高度窗口改为整页滚动，确保控制区始终可达。
struct PlayerView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingCover = false
    @ObservedObject var player: SpeechPlayer
    /// 从阅读页打开时，「看原文」只需收起；从迷你播放器打开时要翻开这本书。
    var fromReader = false
    @State private var settings = false
    @State private var chaptersSheet = false
    @State private var endingListening = false
    @State private var showingContext = false
    /// 句子流可见高度与当前句高度：长句会被底部控制区挡住，换句时据此把当前句滚进视野。
    @State private var viewportHeight: CGFloat = 0
    @State private var currentHeight: CGFloat = 0
    /// 长句跟读：逐词进度每秒推送数次，用引用类型承载，跟读滚动不触发整页重算（与 followPublisher 的设计一致）。
    @State private var follow = SentenceFollow()

    private var content: Color { IndexTheme.ink }
    private var secondary: Color { IndexTheme.muted }
    private var tertiary: Color { IndexTheme.muted }

    var body: some View {
        ZStack(alignment: .top) {
            IndexTheme.canvas.ignoresSafeArea()
            if let book = player.book {
                GeometryReader { geometry in
                    if typeSize.isAccessibilitySize || geometry.size.height < 700 {
                        VStack(spacing: 0) {
                            ScrollView {
                                VStack(spacing: 0) {
                                    hero(book, coverWidth: geometry.size.height < 800 ? 112 : 144)
                                    VStack(spacing: Theme.space3) {
                                        SentenceProgressControl(player: player)
                                        footer
                                        returnToReader
                                    }
                                    .padding(.horizontal, Theme.inset).padding(.vertical, Theme.space3)
                                    readingContent
                                }
                            }
                            .accessibilityIdentifier("player.tools")
                            .accessibilityValue(typeSize.isAccessibilitySize ? "辅助功能字号" : "紧凑高度")
                            // 只固定最重要的播放 / 跳句，其他控件随内容滚动，不挤压正文。
                            IndexBottomBar { transportRow }
                                .accessibilityElement(children: .contain)
                                .accessibilitySortPriority(1)
                        }
                        // 大字号时不自动抢走滚动位置。
                    } else {
                        VStack(spacing: 0) {
                            hero(book, coverWidth: geometry.size.height < 800 ? 112 : 144)
                            followingReadingContent
                            controls
                        }
                    }
                }
            } else { emptyState }
        }
        .foregroundStyle(content)
        .tint(IndexTheme.accent)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .feedbackOverlay()
        .keepScreenAwake()
        .respectReducedMotion()
        .sheet(isPresented: $showingCover) {
            if let book = player.book {
                NavigationStack {
                    IndexPage {
                        IndexHeading(title: Text(verbatim: book.title), detail: Text(verbatim: book.author))
                        BookCoverView(title: book.title, color: book.color, author: book.author,
                                      image: model.covers[book.id], width: 220, usesIndexPalette: true)
                            .frame(maxWidth: .infinity)
                    }
                    .navigationTitle("书籍封面")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showingCover = false } } }
                }
            }
        }
        .confirmationDialog("结束这次听书？", isPresented: $endingListening, titleVisibility: .visible) {
            Button("结束听书", role: .destructive) {
                player.stop()
                if !fromReader { model.showingPlayer = false }
                dismiss()
            }
            Button("取消", role: .cancel) {}
        } message: { Text("阅读进度会保留，随时可以继续。") }
        .sheet(isPresented: $settings) {
            NavigationStack { VoiceSettingsView() }.environmentObject(model).tint(IndexTheme.accent)
        }
        .sheet(isPresented: $chaptersSheet) {
            if let book = player.book {
                NavigationStack { ChapterListView(book: book, player: player).environmentObject(model) }
                    .tint(IndexTheme.accent)
                    .presentationDetents([.medium, .large])
            }
        }
        #if DEBUG
        .task {
            switch UIReview.screen {
            case "player-voice": settings = true
            case "player-chapters": chaptersSheet = true
            default: break
            }
        }
        #endif
    }

    private var readingContent: some View {
        VStack(alignment: .leading, spacing: Theme.space4) {
            VStack(alignment: .leading, spacing: Theme.space1) {
                readingStatus
                sentenceStream
            }
            .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
            .padding(Theme.space3).indexPanel()
            if let error = player.error { errorNotice(error).id("player.error") }
        }
        .padding(.horizontal, Theme.inset).padding(.vertical, Theme.space2)
        .frame(maxWidth: 600, alignment: .leading).frame(maxWidth: .infinity)
    }

    /// 只滚动正文；状态与圆角卡片始终留在视口外，换句不会把卡片顶部一起滚走。
    private var followingReadingContent: some View {
        VStack(alignment: .leading, spacing: Theme.space1) {
            readingStatus
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.space4) {
                        sentenceStream
                        if let error = player.error { errorNotice(error).id("player.error") }
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
                .simultaneousGesture(DragGesture(minimumDistance: 12).onChanged { _ in follow.manualAt = Date() })
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { viewportHeight = $0 }
                .onAppear { updateFollow(player.followPublisher.value); revealCurrent(proxy, animated: false) }
                .onChange(of: player.position) { updateFollow(player.followPublisher.value); revealCurrent(proxy) }
                .onChange(of: player.chapter) { updateFollow(player.followPublisher.value); revealCurrent(proxy) }
                .onChange(of: currentHeight) { revealCurrent(proxy) }
                .onChange(of: player.error) { _, error in
                    if error != nil { proxy.scrollTo("player.error", anchor: .bottom) }
                }
                .onReceive(player.followPublisher) { offset in
                    updateFollow(offset)
                    // 长句随朗读滚动；手动翻阅后暂停 5 秒，不打断主动阅读。
                    guard sentenceOverflows, Date().timeIntervalSince(follow.manualAt) > 5 else { return }
                    revealCurrent(proxy)
                }
            }
        }
        .padding(Theme.cardInset)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .indexPanel()
        .padding(.horizontal, Theme.inset).padding(.vertical, Theme.space2)
        .frame(maxWidth: 600, alignment: .leading).frame(maxWidth: .infinity)
    }

    // MARK: 紧凑书名栏

    private func hero(_ book: Book, coverWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: Theme.space2) {
            HStack(alignment: .top, spacing: Theme.space2) {
                Button { dismiss() } label: { ThemeIcon(symbol: Icon.collapse, size: 18) }
                    .buttonStyle(IndexActionStyle())
                    .accessibilityLabel("收起播放器").accessibilityIdentifier("player.collapse")
                IndexHeading(title: Text("正在听"))
                Menu {
                    Button { showingCover = true } label: { Label("查看封面", systemImage: Icon.emptyBook) }
                    Button { chaptersSheet = true } label: { Label("听书目录", systemImage: Icon.contents) }
                        .accessibilityIdentifier("player.chapters")
                    Toggle("显示前后文", isOn: $showingContext)
                    Button { toggleListeningBookmark(book) } label: {
                        Label(listeningBookmarked(book) ? "移除听到处书签" : "为听到处加书签", systemImage: Icon.bookmark(listeningBookmarked(book)))
                    }
                    .accessibilityIdentifier("player.bookmarkListening")
                    Divider()
                    Button(role: .destructive) { endingListening = true } label: {
                        Label("结束听书", systemImage: Icon.stopListening)
                    }
                    .accessibilityIdentifier("player.endListening")
                } label: {
                    ThemeIcon(symbol: Icon.more, size: 20).foregroundStyle(IndexTheme.accent)
                        .frame(width: Theme.iconButtonSize, height: Theme.iconButtonSize).contentShape(Rectangle())
                }
                .accessibilityLabel("更多听书操作").accessibilityIdentifier("player.more")
            }
            IndexRule()
            HStack(alignment: .top, spacing: Theme.space3) {
                Button { showingCover = true } label: {
                    BookCoverView(title: book.title, color: book.color, author: book.author, image: model.covers[book.id],
                                  width: min(coverWidth, 72), usesIndexPalette: true)
                }
                .buttonStyle(PressButtonStyle())
                .accessibilityLabel("查看《\(book.title)》封面").accessibilityIdentifier("player.cover")
                VStack(alignment: .leading, spacing: Theme.space1) {
                    Text(verbatim: book.title).font(IndexTheme.editorial(22, relativeTo: .title2))
                        .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                    (player.chapterTitle.isEmpty ? Text("第 \(player.chapter + 1) 章") : Text(verbatim: player.chapterTitle))
                        .font(.subheadline).foregroundStyle(IndexTheme.muted)
                        .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                        .accessibilityLabel("第 \(player.chapter + 1) / \(max(1, player.chapterCount)) 章")
                        .accessibilityIdentifier("player.currentChapter")
                    Label(player.voiceLabel, systemImage: Icon.voice)
                        .font(.caption).foregroundStyle(IndexTheme.accent)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .foregroundStyle(IndexTheme.ink)
        .padding(.horizontal, Theme.space4).padding(.vertical, Theme.space2)
        .frame(maxWidth: 680, alignment: .leading).frame(maxWidth: .infinity)
    }

    // MARK: 句子流：状态固定，正文跟随朗读；上下文可读，轻点定位

    private var readingStatus: some View {
        HStack(spacing: 6) {
            if player.playing && !player.buffering {
                Image(systemName: Icon.listening).symbolEffect(.variableColor.iterative, isActive: !reduceMotion)
            }
            Text(player.buffering ? "正在准备声音" : (player.playing ? "正在朗读" : "朗读已暂停"))
        }
        .font(.caption2.weight(.medium)).foregroundStyle(IndexTheme.accent)
        .accessibilityIdentifier("player.readingStatus")
    }

    private var sentenceStream: some View {
        VStack(alignment: .leading, spacing: Theme.space3) {
            if showingContext {
                ForEach([2, 1], id: \.self) { back in
                    if player.position - back >= 0, let previous = player.surroundingSentence(before: player.position - back + 1) {
                        lyricLine(previous.text, offset: -back)
                    }
                }
            }
            if let sentence = player.currentSentence {
                Text(sentence.text)
                    .font(IndexTheme.editorial(21, relativeTo: .title3)).lineSpacing(7)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // 将留白纳入滚动目标，句首/句尾定位后字形仍与裁切边界保持距离。
                    .padding(.vertical, Theme.space2)
                    .id(player.position)
                    .transition(.opacity)
                    .accessibilityLabel("当前句：\(sentence.text)")
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { currentHeight = $0 }
                    .id(Self.currentSentenceID)
            } else {
                Text(player.book?.chapters.first?.text ?? "暂无内容")
                    .font(.body).lineSpacing(7).lineLimit(4)
            }
            if showingContext {
                ForEach([1, 2, 3], id: \.self) { ahead in
                    if let next = player.surroundingSentence(after: player.position + ahead - 1) {
                        lyricLine(next.text, offset: ahead)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .animation(.easeOut(duration: 0.25), value: player.position)
    }

    private static let currentSentenceID = "player.currentSentence"

    /// 长句跟读状态：fraction 为朗读进度在当前句内的比例（0–1）；manualAt 记录手动翻阅时刻，跟读随后暂停几秒。
    private final class SentenceFollow {
        var fraction = 0.0
        var manualAt = Date.distantPast
    }

    /// 当前句卡片是否比句子流可见区还高（24pt 余量），决定是否启用句内跟读。
    private var sentenceOverflows: Bool { viewportHeight > 0 && currentHeight > viewportHeight - 24 }

    /// 词级朗读进度换算成当前句内比例；换句、跳转或停止时回到句首。
    private func updateFollow(_ chapterOffset: Int?) {
        guard let offset = chapterOffset, let range = player.sentenceRange, range.length > 0 else { follow.fraction = 0; return }
        follow.fraction = min(1, max(0, Double(offset - range.location) / Double(range.length)))
    }

    /// 把当前句滚进视野：放得下时停在上方约四分之一处（上一句仍露出一截）；
    /// 比可见区还高的长句按朗读比例跟随滚动，正在朗读的位置始终留在视野内。内容本就放得下时 ScrollView 不会移动。
    private func revealCurrent(_ proxy: ScrollViewProxy, animated: Bool = true) {
        let anchor = sentenceOverflows ? UnitPoint(x: 0.5, y: follow.fraction) : UnitPoint(x: 0.5, y: 0.25)
        if animated && !reduceMotion { withAnimation(.easeOut(duration: 0.3)) { proxy.scrollTo(Self.currentSentenceID, anchor: anchor) } }
        else { proxy.scrollTo(Self.currentSentenceID, anchor: anchor) }
    }

    private func lyricLine(_ text: String, offset: Int) -> some View {
        Button { Haptics.light(); player.skip(offset) } label: {
            Text(text)
                .font(IndexTheme.editorial(18, relativeTo: .body)).lineSpacing(6)
                .foregroundStyle(IndexTheme.muted)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("跳到\(offset < 0 ? "前" : "后") \(abs(offset)) 句：\(text)")
    }

    // MARK: 控制区：句子进度、圆形播放键、四个轻量工具

    private var controls: some View {
        VStack(spacing: Theme.space2) {
            SentenceProgressControl(player: player)
            transportRow
            footer
            returnToReader
        }
        .padding(.top, Theme.space2).padding(.bottom, Theme.space2)
        .frame(maxWidth: 560)
        .padding(.horizontal, Theme.inset).padding(.bottom, Theme.space2)
        .frame(maxWidth: 600).frame(maxWidth: .infinity)
        .background(IndexTheme.canvas.ignoresSafeArea(edges: .bottom))
    }

    @ViewBuilder private var returnToReader: some View {
        if let book = player.book {
            Button {
                if book.format.uppercased() != "EPUB" {
                    if fromReader { dismiss() }
                    else { dismiss(); model.showingPlayer = false; model.selectedBook = book }
                    return
                }
                if let entry = model.entries.first(where: { $0.id == book.id }) {
                    let stored = entry.listeningProgress
                    var target = ReadiumSpeechBridge.sentence(book: book, chapter: player.chapter, position: player.position)
                    if stored?.chapter == player.chapter && stored?.position == player.position {
                        target.locator = stored?.locator; target.publicationRevision = stored?.publicationRevision
                    }
                    model.open(entry, target: target)
                }
                dismiss(); model.showingPlayer = false
            } label: { Text("回到原文") }
                .buttonStyle(IndexActionStyle(role: .secondary, expands: true))
                .accessibilityLabel("看原文")
                .accessibilityIdentifier("player.backToReader")
        }
    }

    /// v29 阶段三（p3b）：为当前朗读位置加书签，复用阅读页同款的切换式书签 API（同位置再点即移除）。
    private func listeningBookmarked(_ book: Book) -> Bool {
        model.entries.first { $0.id == book.id }?.bookmarks.contains { $0.chapter == player.chapter && $0.position == player.position } ?? false
    }

    private func toggleListeningBookmark(_ book: Book) {
        Haptics.selection()
        model.bookmark(book.id, chapter: player.chapter, position: player.position, excerpt: player.currentText)
    }

    private var transportRow: some View {
        HStack(spacing: typeSize.isAccessibilitySize ? 8 : 20) {
            TransportButton(systemName: Icon.previousSentence, label: "上一句", size: 40) { player.skip(-1) }
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("player.previousSentence")
            Button { Haptics.light(); player.toggle() } label: {
                Group {
                    if player.buffering { ProgressView().tint(IndexTheme.onAccent) }
                    else { ThemeIcon(symbol: Icon.playback(player.playing), size: 26) }
                }
                .foregroundStyle(IndexTheme.onAccent)
                .frame(width: 64, height: 52)
                .background(IndexTheme.accent, in: RoundedRectangle(cornerRadius: IndexTheme.panelRadius))
                .contentShape(Rectangle())
            }
            .buttonStyle(PressButtonStyle())
            .accessibilityLabel(player.buffering ? "正在准备声音" : (player.playing ? "暂停朗读" : "继续朗读"))
            .accessibilityIdentifier("player.toggle")
            TransportButton(systemName: Icon.nextSentence, label: "下一句", size: 40) { player.skip(1) }
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("player.nextSentence")
        }
        .padding(.horizontal, typeSize.isAccessibilitySize ? 0 : 12)
        .frame(maxWidth: .infinity, minHeight: 78)
    }

    private var footer: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .top), count: typeSize.isAccessibilitySize ? 2 : 4), spacing: Theme.space3) {
            Button { chaptersSheet = true } label: { footerItem(Icon.contents, "目录") }
                .accessibilityLabel("听书目录，第 \(player.chapter + 1) 章")
                .accessibilityIdentifier("player.contents")
            Menu {
                Picker("语速", selection: Binding(get: { player.rate }, set: { player.changeRate($0) })) {
                    ForEach([0.5, 0.75, 0.8, 1.0, 1.2, 1.25, 1.5, 1.75, 2.0], id: \.self) { value in
                        Text(value.rateText + "×").tag(value)
                    }
                }
            } label: { footerItem(Icon.rate, "语速", value: "\(player.rate.rateText)×", highlighted: player.rate != 1.0) }
            .accessibilityLabel("语速，当前 \(player.rate.rateText) 倍")
            .accessibilityIdentifier("player.rate")
            Button { settings = true } label: { footerItem(Icon.speaker, "声音") }
                .accessibilityLabel("声音设置，当前 \(player.voiceLabel)")
                .accessibilityIdentifier("player.voice")
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Menu {
                    Button("关闭定时") { player.setSleep(minutes: 0) }.disabled(player.sleepUntil == nil)
                    ForEach([15, 30, 45, 60], id: \.self) { minutes in
                        Button("\(minutes) 分钟后停止") { player.setSleep(minutes: minutes) }
                    }
                } label: { footerItem(Icon.sleepTimer, "定时", value: player.sleepUntil.map { _ in sleepLabel(at: context.date) }, highlighted: player.sleepUntil != nil) }
                .accessibilityLabel("定时停止")
                .accessibilityValue(player.sleepUntil == nil ? "未开启" : sleepLabel(at: context.date))
                .accessibilityIdentifier("player.sleep")
            }
        }
        .buttonStyle(.plain)
    }

    private func footerItem(_ symbol: String, _ title: String, value: String? = nil, highlighted: Bool = false) -> some View {
        VStack(spacing: Theme.space1) {
            ThemeIcon(symbol: symbol, size: 18).accessibilityHidden(true)
            Text(L(title)).font(.caption.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            if let value { Text(verbatim: value).font(.caption2.monospacedDigit()).foregroundStyle(IndexTheme.muted) }
        }
        .multilineTextAlignment(.center)
        .foregroundStyle(highlighted ? IndexTheme.accent : IndexTheme.ink)
        .padding(.vertical, Theme.space2)
        .frame(maxWidth: .infinity, minHeight: Theme.iconButtonSize)
        .background(highlighted ? IndexTheme.wash : IndexTheme.surface, in: RoundedRectangle(cornerRadius: IndexTheme.controlRadius))
        .contentShape(Rectangle())
        .accessibilityAddTraits(highlighted ? .isSelected : [])
    }

    private func errorNotice(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.space3) {
            IndexStatus(kind: .failure, title: Text("朗读暂时中断"), detail: Text(L(error)))
            ViewThatFits(in: .horizontal) {
                HStack { recoveryButtons }
                VStack(alignment: .leading) { recoveryButtons }
            }
        }
        .padding(.leading, Theme.space3).padding(.vertical, 6)
        .overlay(alignment: .leading) { Rectangle().fill(IndexTheme.danger).frame(width: 3) }
    }

    @ViewBuilder private var recoveryButtons: some View {
        Button("重试朗读") { player.resume() }.buttonStyle(IndexActionStyle(role: .primary))
        Button("检查声音设置") { settings = true }.buttonStyle(IndexActionStyle(role: .secondary))
    }

    private func sleepLabel(at date: Date) -> String {
        if let until = player.sleepUntil, until > date {
            return String(format: L("%lld 分后停"), Int(ceil(until.timeIntervalSince(date) / 60)))
        }
        return L("定时")
    }

    private var emptyState: some View {
        IndexPage {
            IndexStatus(kind: .empty, title: Text("暂无正在听的书"),
                        detail: Text("打开一本书，轻点耳机，继续书中的旅程。"))
            if let last = model.lastBook {
                Button("听《\(last.title)》") { model.listen(last.id) }
                    .buttonStyle(IndexActionStyle(role: .primary))
            }
        }
    }
}

// MARK: - 子组件

private struct TransportButton: View {
    let systemName: String
    let label: String
    let size: CGFloat
    var enabled = true
    let action: () -> Void
    var body: some View {
        Button { action(); Haptics.light() } label: {
            ThemeIcon(symbol: systemName, size: 28)
                .foregroundStyle(enabled ? IndexTheme.ink : IndexTheme.muted)
                .frame(width: size, height: size)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressButtonStyle(scale: 0.94))
        .disabled(!enabled)
        .accessibilityLabel(label)
    }
}

/// 直接拖动本章句子；触摸松手才跳转，VoiceOver / 键盘逐句调整。
/// 拖动中自然跨章或换书时放弃旧目标，不能误跳新章节。
/// 蓝色圆角进度轨保留 44pt 触摸区域，拖动手势直接作用在可访问控件上。
private struct SentenceProgressControl: View {
    @ObservedObject var player: SpeechPlayer
    @State private var dragging = false
    @State private var draft: Double = 0
    @State private var originBook: String?
    @State private var originChapter = 0
    private var maxPosition: Double { Double(max(1, player.count - 1)) }
    private var shown: Int { max(0, min(max(0, player.count - 1), dragging ? Int(draft.rounded()) : player.position)) }
    private var progress: Double { player.count <= 1 ? 0 : Double(shown) / maxPosition }
    private var sentenceLabel: String { player.count == 0 ? "本章暂无可朗读文字" : "本章第 \(shown + 1) / \(player.count) 句" }
    private var scrubbing: Bool { player.count > 1 }
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.space2) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    ProgressLine(value: progress, tint: IndexTheme.muted, height: Theme.progressHeight)
                        .accessibilityHidden(true)
                    Circle().fill(IndexTheme.muted).frame(width: Theme.space3, height: Theme.space3)
                        .position(x: min(max(5, geo.size.width * progress), max(5, geo.size.width - 5)), y: 22)
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard scrubbing else { return }
                        if !dragging {
                            originBook = player.book?.id; originChapter = player.chapter
                            draft = Double(player.position); dragging = true
                        }
                        draft = min(max(0, Double(value.location.x / geo.size.width)), 1) * maxPosition
                    }
                    .onEnded { _ in
                        guard scrubbing else { return }
                        if originBook == player.book?.id && originChapter == player.chapter { player.seek(shown) }
                        dragging = false
                    })
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("播放进度")
                .accessibilityValue(sentenceLabel)
                .accessibilityHint("左右拖动选择句子，松手跳转")
                .accessibilityIdentifier("player.sentence-progress")
                .accessibilityAdjustableAction { direction in
                    guard scrubbing else { return }
                    switch direction {
                    case .increment: player.seek(min(player.position + 1, player.count - 1))
                    case .decrement: player.seek(max(player.position - 1, 0))
                    @unknown default: break
                    }
                }
            }
            .frame(height: 44)
            ViewThatFits(in: .horizontal) {
                HStack { Text(sentenceLabel); Spacer(); estimate }
                VStack(alignment: .leading, spacing: Theme.space1) { Text(sentenceLabel); estimate }
            }
            .font(.caption).monospacedDigit().foregroundStyle(IndexTheme.muted)

        }
    }
    private var estimate: some View {
        Text(player.estimatedRemainingLabel(from: shown)).foregroundStyle(IndexTheme.muted)
    }
}

/// 章节滑杆：拖动结束后跳转章节
private struct ChapterProgressSlider: View {
    @ObservedObject var player: SpeechPlayer
    @State private var dragging = false
    @State private var value: Double = 0
    var body: some View {
        Slider(
            value: Binding(
                get: { dragging ? value : Double(player.chapter) },
                set: { value = $0 }
            ),
            in: 0...max(1, Double(player.chapterCount - 1)),
            step: 1
        ) { editing in
            if editing {
                value = Double(player.chapter)
                dragging = true
            } else {
                dragging = false
                let target = max(0, min(player.chapterCount - 1, Int(value.rounded())))
                player.seek(chapter: target, position: 0)
            }
        }
        .tint(IndexTheme.accent)
        .disabled(player.chapterCount <= 1)
        .accessibilityLabel("章节进度")
        .accessibilityValue("第 \(player.chapter + 1) 章，共 \(max(1, player.chapterCount)) 章")
    }
}

// MARK: - 章节列表（原生 List）

struct ChapterListView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    let book: Book
    @ObservedObject var player: SpeechPlayer
    @State private var query = ""
    private var filtered: [(index: Int, chapter: Chapter)] {
        book.chapters.enumerated()
            .filter { query.isEmpty || $0.element.title.localizedCaseInsensitiveContains(query) }
            .map { (index: $0.offset, chapter: $0.element) }
    }
    var body: some View {
        ScrollViewReader { proxy in
            List {
                IndexHeading(title: Text(verbatim: book.title),
                             detail: Text("共 \(book.chapters.count) 章 · 正在听第 \(player.chapter + 1) 章"))
                    .listRowBackground(Color.clear).listRowSeparator(.hidden)
                VStack(alignment: .leading, spacing: Theme.space1) {
                    Text(verbatim: player.timingLabel + " · " + player.rate.rateText + "×")
                        .font(.caption).foregroundStyle(IndexTheme.muted)
                    ChapterProgressSlider(player: player)
                    HStack(spacing: Theme.space2) {
                        Button { player.skipChapter(-1) } label: { IndexActionLabel(title: "上一章", symbol: Icon.back) }
                            .disabled(player.chapter == 0)
                        Spacer(minLength: 0)
                        Button { player.skipChapter(1) } label: { IndexActionLabel(title: "下一章", symbol: Icon.disclosure) }
                            .disabled(player.chapter + 1 >= player.chapterCount)
                    }
                    .buttonStyle(IndexActionStyle())
                }
                .padding(.vertical, Theme.space2)
                .listRowBackground(IndexTheme.surface)
                if filtered.isEmpty {
                    IndexStatus(kind: .empty, title: Text(query.isEmpty ? "没有章节" : "没有符合条件的章节"))
                        .listRowBackground(Color.clear)
                }
                ForEach(filtered, id: \.index) { item in
                    let current = item.index == player.chapter
                    Button {
                        player.seek(chapter: item.index, position: 0)
                        dismiss()
                    } label: {
                        IndexRowLabel(title: Text(verbatim: item.chapter.title),
                                      detail: current ? Text("正在听 · \(Int(player.progress * 100))%") : Text("第 \(item.index + 1) 章"),
                                      symbol: current ? Icon.listen : nil)
                    }
                    .buttonStyle(PressButtonStyle())
                    .listRowBackground(current ? IndexTheme.wash : IndexTheme.surface)
                    .id(item.index)
                }
            }
            .indexList()
            .searchable(text: $query, prompt: "搜索章节")
            .navigationTitle("听书目录").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { ThemeIcon(symbol: Icon.close) }
                        .accessibilityLabel("关闭章节列表")
                }
            }
            .onAppear {
                DispatchQueue.main.async { proxy.scrollTo(player.chapter, anchor: .center) }
            }
        }
    }

}

// MARK: - 听书与声音设置面板（原生 Form）

struct VoiceSettingsView: View {
    @EnvironmentObject var app: AppModel
    @State private var fetchedVoices: [CloudVoice] = []
    /// 系统音色异步加载（SpeechVoiceCache 全局只枚举一次），页面打开不再同步枚举卡顿。
    @State private var systemVoices: [AVSpeechSynthesisVoice] = SpeechVoiceCache.cached ?? []
    @State private var voicesLoaded = SpeechVoiceCache.cached != nil
    @State private var notice = ""
    typealias CloudVoice = CloudSpeech.Voice
    @Environment(\.dismiss) var dismiss
    @State private var provider = UserDefaults.standard.string(forKey: "voice.provider") ?? "system"
    @State private var rate = Double(VoiceOptions.load().rate)
    @State private var groupID = UserDefaults.standard.string(forKey: "voice.groupID") ?? ""
    @State private var customURL = UserDefaults.standard.string(forKey: VoiceOptions.customURLKey) ?? ""
    @State private var azureRegion = UserDefaults.standard.string(forKey: "voice.azureRegion") ?? ""
    @State private var roles = UserDefaults.standard.bool(forKey: "voice.roles")
    @State private var maleVoice = ""
    @State private var femaleVoice = ""
    @State private var voice = ""
    @State private var modelName = ""
    @State private var apiKey = ""
    @State private var error: String?
    @State private var preview: AVAudioPlayer?
    @State private var systemPreview = AVSpeechSynthesizer()
    @State private var previewTask: Task<Void, Never>?
    @State private var previewing = false
    @State private var pausedBookForPreview = false
    @State private var previewRevision = UUID()
    /// 各服务商未保存的修改：切换朗读方式时先存草稿，保存时一并写入，互不覆盖。
    @State private var drafts: [String: Draft] = [:]
    @State private var loadedProvider = ""
    private struct Draft { var voice: String; var model: String; var key: String; var male: String; var female: String }
    /// 只读已异步加载的系统音色（见 body 的 .task 与 SpeechVoiceCache）；不再同步枚举。
    private var voices: [AVSpeechSynthesisVoice] { systemVoices }

    var body: some View {
        Form {
            Section {
                voiceHero
            }
            .listRowBackground(IndexTheme.surface)
            if error != nil || !notice.isEmpty { voiceNotices }

            Section("播放设置") {
                NavigationLink {
                    voiceDetail("选择音色") { voiceSection }
                } label: { voiceSettingLabel("音色", value: currentVoiceName) }
                NavigationLink {
                    voiceDetail("朗读节奏") { rateSection }
                } label: { voiceSettingLabel("语速", value: rate.rateText + "×") }
                NavigationLink {
                    voiceDetail("分角色配音") { roleSection }
                } label: { voiceSettingLabel("分角色配音", value: roles ? L("已开启") : L("关闭")) }
            }
            .listRowBackground(IndexTheme.surface)

            Section("服务与输出") {
                NavigationLink { cloudConfiguration } label: {
                    IndexRowLabel(title: Text("连接云语音服务"), detail: Text("GLM / MiniMax / Azure / ElevenLabs / 自定义"))
                }
                .accessibilityIdentifier("voice.cloud")
                HStack(spacing: Theme.space2) {
                    IndexRowLabel(title: Text("音频输出"))
                    AirPlayButton().frame(width: Theme.iconButtonSize, height: Theme.iconButtonSize)
                }
                .accessibilityElement(children: .contain)
            }
            .listRowBackground(IndexTheme.surface)
        }
        .indexList()
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("声音与朗读")
        .navigationBarBackButtonHidden().navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }.accessibilityLabel("取消声音设置，不保存修改")
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            IndexBottomBar {
                Button("保存并应用") { save() }
                    .buttonStyle(IndexActionStyle(role: .primary, expands: true))
                    .accessibilityIdentifier("voice.save")
            }
        }
        .feedbackOverlay()
        .respectReducedMotion()
        .onAppear { if loadedProvider.isEmpty { load(provider) } }
        .task { await loadSystemVoices() }
        .onDisappear { stopPreview() }
    }

    private var voiceHero: some View {
        VStack(alignment: .leading, spacing: Theme.space2) {
            IndexHeading(title: Text(VoiceOptions.providerName(provider)),
                         detail: Text(provider == "system" ? "离线可用" : "云端合成"))
            Text(provider == "system" ? L("使用这台设备的声音，无需密钥。") : L(currentVoiceSubtitle))
                .font(.subheadline).foregroundStyle(IndexTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
            Button { previewing ? stopPreview() : testVoice() } label: {
                IndexActionLabel(title: previewing ? "停止试听" : "试听当前声音", symbol: Icon.listen)
            }
            .buttonStyle(IndexActionStyle(role: .secondary))
            .accessibilityIdentifier("voice.preview")
        }
        .padding(.vertical, Theme.space2)
    }

    private func voiceSettingLabel(_ title: String, value: String) -> some View {
        IndexRowLabel(title: Text(L(title)), detail: Text(verbatim: value))
    }

    private func voiceDetail<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        Form {
            IndexHeading(title: Text(L(title)), detail: Text("调整后可返回试听，保存并应用后用于听书。"))
                .listRowBackground(Color.clear)
            content().listRowBackground(IndexTheme.surface)
        }
        .indexList()
        .navigationTitle(L(title)).navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
    }

    private var cloudConfiguration: some View {
        Form {
            IndexHeading(title: Text("连接云语音"), detail: Text("使用你自己的服务。密钥仅保存在本机钥匙串，试听也会连接服务商。"))
                .listRowBackground(Color.clear)
            providerSection.listRowBackground(IndexTheme.surface)
            connectionSection.listRowBackground(IndexTheme.surface)
            voiceSection.listRowBackground(IndexTheme.surface)
            voiceNotices
        }
        .indexList()
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("连接云语音").navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            IndexBottomBar {
                VStack(spacing: Theme.space1) {
                    Button { previewing ? stopPreview() : testVoice() } label: {
                        Text(previewing ? "停止试听" : "试听")
                    }
                    .buttonStyle(IndexActionStyle())
                    .accessibilityIdentifier("voice.preview")
                    Button("保存并应用") { save() }.buttonStyle(IndexActionStyle(role: .primary, expands: true))
                        .accessibilityIdentifier("voice.save")
                }
            }
        }
    }

    private var voiceNotices: some View {
        Section {
            Text(L(auditionHint)).font(.footnote).foregroundStyle(IndexTheme.muted)
            if let error {
                IndexStatus(kind: .failure, title: Text("声音设置需要检查"), detail: Text(L(error)))
            }
            if !notice.isEmpty { IndexStatus(kind: .empty, title: Text(L(notice))) }
        }
        .listRowBackground(IndexTheme.surface)
    }

    private var providerSection: some View {
        Section {
            Picker("提供方", selection: $provider) {
                Text("系统声音 · 离线").tag("system")
                Text("智谱 GLM").tag("glm")
                Text("MiniMax").tag("minimax")
                Text("Microsoft Azure").tag("azure")
                Text("ElevenLabs").tag("elevenlabs")
                Text("自定义 TTS（OpenAI 兼容）").tag("custom")
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("voice.provider")
            .onChange(of: provider) { old, new in
                stopPreview()
                drafts[old] = Draft(voice: voice, model: modelName, key: apiKey, male: maleVoice, female: femaleVoice)
                fetchedVoices = []; notice = ""; error = nil
                load(new)
            }
        } header: { Text("选择朗读服务") } footer: { Text(providerNote) }
    }

    @ViewBuilder private var connectionSection: some View {
        if provider != "system" {
            Section {
                if provider == "custom" {
                    TextField("服务地址，如 https://example.com/v1", text: $customURL)
                        .keyboardType(.URL).textContentType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("voice.customURL")
                }
                SecureField(provider == "azure" ? "Speech Key（必填）" : provider == "custom" ? "API Key（自建服务可留空）" : "API Key（必填）", text: $apiKey)
                    .textContentType(.password).privacySensitive()
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                if provider == "azure" {
                    TextField("区域，例如 eastasia", text: $azureRegion).textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                if provider == "minimax" {
                    TextField("Group ID（选填）", text: $groupID).textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                if provider != "azure" {
                    Picker("模型", selection: $modelName) {
                        ForEach(presetModels, id: \.self) { Text($0).tag($0) }
                        if !presetModels.contains(modelName) { Text(modelName).tag(modelName) }
                    }
                    DisclosureGroup("自定义模型") {
                        TextField(provider == "glm" ? "模型 ID（需以 glm 开头，如 glm-tts）" : "模型 ID", text: $modelName).textInputAutocapitalization(.never).autocorrectionDisabled()
                    }
                }
            } header: { Text("连接 \(VoiceOptions.providerName(provider))") } footer: { Text(cloudNote) }
        }
    }

    private var voiceSection: some View {
        Section {
            IndexRowLabel(title: Text(verbatim: currentVoiceName), detail: Text(L(currentVoiceSubtitle)),
                          symbol: Icon.checkmark)
                .listRowBackground(IndexTheme.wash)
            voicePicker
            if provider == "minimax" || provider == "elevenlabs" {
                Button { refreshVoices() } label: { Label("刷新账号音色", systemImage: Icon.refresh) }
                    .disabled(app.busy || apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        } header: { Text("音色") }
    }

    private var rateSection: some View {
        Section {
            VStack(alignment: .leading, spacing: Theme.space2) {
                HStack {
                    Text("语速").font(.subheadline)
                    Spacer()
                    Text(rate.rateText + "×").font(.title3.weight(.medium)).monospacedDigit().foregroundStyle(IndexTheme.accent)
                }
                ReaderPreferenceSlider(value: $rate, in: 0.5...2, step: 0.05)
                    .accessibilityLabel("试听与朗读语速").accessibilityValue(rate.rateText + "倍")
            }
        } header: { Text("朗读节奏") } footer: { Text("试听使用当前语速，保存后应用到听书。") }
    }

    private var roleSection: some View {
        Section {
            DisclosureGroup("分角色配音") {
                Toggle("启用分角色配音", isOn: $roles)
                if roles {
                    Picker("男声", selection: $maleVoice) {
                        Text("与旁白相同").tag("")
                        ForEach(voiceChoices, id: \.value) { Text($0.label).tag($0.value) }
                    }
                    Picker("女声", selection: $femaleVoice) {
                        Text("与旁白相同").tag("")
                        ForEach(voiceChoices, id: \.value) { Text($0.label).tag($0.value) }
                    }
                }
                Text("中文小说中的男女对话使用对应音色；无法判断时使用旁白。此功能仍在测试中。")
                    .font(.caption).foregroundStyle(IndexTheme.muted)
            }
        } header: { Text("更多声音选项") }
    }

    // MARK: - Voice Picker

    @ViewBuilder
    private var voicePicker: some View {
        if provider == "system" {
            if !voicesLoaded {
                HStack(spacing: Theme.space2) {
                    ProgressView().controlSize(.small)
                    Text("正在加载音色…").font(.subheadline).foregroundStyle(IndexTheme.muted)
                }
            }
            Picker("系统声音", selection: $voice) {
                Text("默认中文声音").tag("")
                ForEach(voices, id: \.identifier) { v in
                    Text("\(v.name) · \(v.language)").tag(v.identifier)
                }
            }
        } else if provider == "glm" {
            Picker("音色", selection: $voice) {
                ForEach(glmVoices, id: \.value) { v in
                    Text(v.label).tag(v.value)
                }
                if !glmVoices.contains(where: { $0.value == voice }) { Text("自定义音色").tag(voice) }
            }
            DisclosureGroup("自定义 / 复刻音色") {
                TextField("音色 ID（如 tongtong 或复刻音色 ID）", text: $voice)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        } else if provider == "custom" {
            Picker("音色", selection: $voice) {
                ForEach(customVoices, id: \.value) { Text($0.label).tag($0.value) }
                if !customVoices.contains(where: { $0.value == voice }) { Text(voice.isEmpty ? "未填写" : voice).tag(voice) }
            }
            TextField("音色名（以你的服务为准）", text: $voice)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
        } else if provider == "azure" {
            Picker("音色", selection: $voice) {
                ForEach(AzureVoices.all, id: \.value) { v in Text(v.label).tag(v.value) }
                if !AzureVoices.all.contains(where: { $0.value == voice }) { Text(voice).tag(voice) }
            }
        } else if provider == "elevenlabs" {
            Picker("音色", selection: $voice) {
                ForEach(elevenVoices, id: \.value) { v in Text(v.label).tag(v.value) }
                if !elevenVoices.contains(where: { $0.value == voice }) { Text("自定义音色").tag(voice) }
            }
            TextField("音色 ID（可从 ElevenLabs 音色库复制）", text: $voice)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        } else {
            Picker("预设音色", selection: $voice) {
                ForEach(minimaxVoices, id: \.value) { v in Text(v.label).tag(v.value) }
                if !minimaxVoices.contains(where: { $0.value == voice }) { Text("自定义音色").tag(voice) }
            }
        }
    }

    private var glmVoices: [CloudVoice] {
        [("tongtong", "彤彤"), ("chuichui", "锤锤"), ("xiaochen", "小陈"), ("jam", "动动"), ("kazi", "卡子"), ("douji", "豆吉"), ("luodo", "洛多")].map { CloudVoice(value: $0.0, label: $0.1) }
    }

    private var minimaxVoices: [CloudVoice] {
        if !fetchedVoices.isEmpty { return fetchedVoices }
        return zip(["male-qn-qingse", "female-shaonv", "female-yujie", "female-chengshu", "female-tianmei", "presenter_male", "presenter_female", "audiobook_male_1", "audiobook_male_2", "audiobook_female_1", "audiobook_female_2", "male-qn-jingying", "male-qn-badao", "male-qn-daxuesheng", "female-qn-qingse", "female-qn-yujie", "female-qn-chengshu", "female-qn-tianmei"], ["青涩青年", "少女", "御姐", "成熟女性", "甜美女性", "男性主持人", "女性主持人", "有声书男声 1", "有声书男声 2", "有声书女声 1", "有声书女声 2", "精英青年", "霸道青年", "大学生", "青涩女声", "御姐女声", "成熟女声", "甜美女声"]).map { CloudVoice(value: $0.0, label: $0.1) }
    }

    private var providerNote: String {
        switch provider {
        case "system": return "使用设备自带声音，无需联网、免费。可在系统设置 → 辅助功能 → 朗读内容 → 声音中下载更多声音。"
        case "azure": return "使用你自己的 Azure 语音资源（Speech Key + 区域），提供大量中文神经网络音色，有免费额度。"
        case "elevenlabs": return "使用你自己的 ElevenLabs API Key，多语言音色自然，带逐字时间戳。"
        case "custom": return "连接任何兼容 OpenAI /audio/speech 接口的朗读服务，包括自建或本机运行的 TTS。"
        default: return "使用你自己的 API Key 直连服务商，音质更自然，按服务商计费。"
        }
    }
    private var cloudNote: String {
        let privacy = "密钥只保存在本机钥匙串；朗读时会将当前句及后续少量句子发送给服务商预合成，试听也会联网，费用按服务商规则计算。"
        switch provider {
        case "minimax": return "支持 MiniMax 国内版按量付费与 Token Plan（sk-cp- 开头）密钥，自动连接 api.minimax.cn。追求低延迟可选 speech-2.8-turbo。" + privacy
        case "azure": return "区域必须与 Azure 语音资源所在区域一致（在 Azure 门户的「密钥和终结点」中查看）。" + privacy
        case "elevenlabs": return "Flash 与 Turbo 模型延迟更低，Multilingual 适合长篇听书。" + privacy
        case "custom": return "只接受 https 地址，或局域网 / 本机的 http 地址。模型与音色名以你的服务为准。" + privacy
        default: return "不经过听页服务器。" + privacy
        }
    }
    private var presetModels: [String] {
        switch provider {
        case "glm": return ["glm-tts"]
        case "elevenlabs": return ["eleven_multilingual_v2", "eleven_turbo_v2_5", "eleven_flash_v2_5", "eleven_v3"]
        case "custom": return ["tts-1", "tts-1-hd", "gpt-4o-mini-tts"]
        default: return ["speech-2.8-hd", "speech-2.8-turbo", "speech-2.6-hd", "speech-2.6-turbo", "speech-02-hd", "speech-02-turbo", "speech-01-hd", "speech-01-turbo", "t2a-01-hd", "t2a-01"]
        }
    }
    private var customVoices: [CloudVoice] {
        ["alloy", "echo", "fable", "onyx", "nova", "shimmer"].map { CloudVoice(value: $0, label: $0) }
    }
    private var elevenVoices: [CloudVoice] {
        if !fetchedVoices.isEmpty { return fetchedVoices }
        return [CloudVoice(value: "21m00Tcm4TlvDq8ikWAM", label: "Rachel"), CloudVoice(value: "pNInz6obpgDQGcFmaJgB", label: "Adam"),
                CloudVoice(value: "EXAVITQu4vr4xnSDxMaL", label: "Sarah"), CloudVoice(value: "onwK4e9ZLuTAKqWW03F9", label: "Daniel")]
    }
    /// 当前朗读方式下可选的全部音色（分角色用）
    private var voiceChoices: [CloudVoice] {
        switch provider {
        case "system": return voices.map { CloudVoice(value: $0.identifier, label: "\($0.name) · \($0.language)") }
        case "glm":
            let cleaned = voice.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty && !glmVoices.contains(where: { $0.value == cleaned }) {
                return glmVoices + [CloudVoice(value: cleaned, label: cleaned)]
            }
            return glmVoices
        case "azure": return AzureVoices.all
        case "elevenlabs": return elevenVoices
        case "custom": return customVoices
        default: return minimaxVoices
        }
    }

    private var currentVoiceName: String {
        if provider == "system" {
            if voice.isEmpty { return "默认中文声音" }
            return voices.first(where: { $0.identifier == voice })?.name ?? "默认中文声音"
        }
        if provider == "glm" {
            return glmVoices.first(where: { $0.value == voice })?.label ?? voice
        }
        if provider == "azure" { return AzureVoices.all.first { $0.value == voice }?.label ?? voice }
        if provider == "elevenlabs" { return elevenVoices.first { $0.value == voice }?.label ?? voice }
        return minimaxVoices.first(where: { $0.value == voice })?.label ?? voice
    }

    private var currentVoiceSubtitle: String {
        if provider == "system" {
            if voice.isEmpty { return "系统 · 离线" }
            return voices.first(where: { $0.identifier == voice })?.language ?? ""
        }
        return ["glm": "智谱 GLM · 云端", "minimax": "MiniMax · 云端", "azure": "Microsoft Azure · 云端", "elevenlabs": "ElevenLabs · 云端"][provider] ?? "云端"
    }

    private func refreshVoices() {
        let key = apiKey, group = groupID, target = provider
        app.run("正在刷新音色") {
            let voices = target == "elevenlabs" ? try await CloudSpeech.elevenLabsVoices(key: key) : try await CloudSpeech.minimaxVoices(key: key, groupID: group)
            if target == "elevenlabs" { for v in voices { UserDefaults.standard.set(v.label, forKey: "voice.label.elevenlabs." + v.value) } }
            guard provider == target else { return }
            fetchedVoices = voices; notice = "已加载 \(voices.count) 个音色。"
        }
    }

    private var auditionHint: String {
        if previewing { return pausedBookForPreview ? "正在试听，听书已暂停。" : "正在试听当前配置…" }
        if pausedBookForPreview { return "试听后听书保持暂停；返回听书页轻点「播放」即可继续。" }
        return "确认音色后，试听并保存。试听会暂停当前听书。"
    }

    private var configurationIssue: String? {
        if provider == "custom" { return CloudSpeech.customSpeechEndpoint(customURL) == nil ? "请填写有效的自定义 TTS 地址（https，或局域网 / 本机 http）。" : nil }
        if provider != "system" && apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "请先填写提供方密钥，或选择系统声音。" }
        if provider == "azure" && azureRegion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "请填写 Azure 语音资源所在区域。" }
        return nil
    }

    private func stopPreview() {
        previewRevision = UUID(); previewTask?.cancel(); previewTask = nil
        preview?.stop(); preview = nil; systemPreview.stopSpeaking(at: .immediate); previewing = false
    }

    private func testVoice() {
        if let issue = configurationIssue { error = issue; return }
        stopPreview(); error = nil
        if app.player.playing { app.player.pause(); pausedBookForPreview = true }
        let chosen = VoiceOptions.sanitized(provider: provider, model: modelName, voice: voice)
        let config = (provider, chosen.model, chosen.voice, apiKey, provider == "azure" ? azureRegion : provider == "custom" ? customURL : groupID)
        let speed = rate, revision = previewRevision
        previewing = true
        previewTask = Task { @MainActor in
            defer { if previewRevision == revision { previewing = false } }
            do {
                try SpeechAudioSession.activate()
                let sample = "你好，这是听页的试听。选一种声音，让阅读慢慢继续。"
                if config.0 == "system" {
                    let line = AVSpeechUtterance(string: sample)
                    line.voice = config.2.isEmpty ? AVSpeechSynthesisVoice(language: "zh-CN") : AVSpeechSynthesisVoice(identifier: config.2)
                    line.rate = min(AVSpeechUtteranceMaximumSpeechRate, max(AVSpeechUtteranceMinimumSpeechRate, AVSpeechUtteranceDefaultSpeechRate * Float(speed)))
                    systemPreview.speak(line)
                    try await Task.sleep(for: .milliseconds(300))
                    while systemPreview.isSpeaking { try await Task.sleep(for: .milliseconds(150)) }
                } else {
                    let result = try await CloudSpeech.synthesize(sample, provider: config.0, model: config.1, voice: config.2, key: config.3, groupID: config.4)
                    try Task.checkCancellation()
                    guard previewRevision == revision else { return }
                    let audio = try AVAudioPlayer(data: result.audio)
                    audio.enableRate = true; audio.rate = Float(speed); audio.prepareToPlay(); audio.play(); preview = audio
                    while audio.isPlaying { try await Task.sleep(for: .milliseconds(150)) }
                }
            } catch is CancellationError {} catch {
                if previewRevision == revision { self.error = error.localizedDescription }
            }
        }
    }

    /// 系统音色只在首次进入时于后台枚举一次；再次进入直接命中 SpeechVoiceCache。
    private func loadSystemVoices() async {
        if let cached = SpeechVoiceCache.cached {
            systemVoices = cached
            voicesLoaded = true
            return
        }
        let list = await Task.detached(priority: .userInitiated) { SpeechVoiceCache.load() }.value
        systemVoices = list
        voicesLoaded = true
    }

    /// 读取某个服务商自己的模型、音色与密钥（与播放器同一套键），有未保存的草稿时优先用草稿。
    private func load(_ target: String) {
        VoiceOptions.migrateLegacy()
        loadedProvider = target
        if let draft = drafts[target] { voice = draft.voice; modelName = draft.model; apiKey = draft.key; maleVoice = draft.male; femaleVoice = draft.female; return }
        let d = UserDefaults.standard
        let chosen = VoiceOptions.sanitized(provider: target, model: d.string(forKey: VoiceOptions.modelKey(target)), voice: d.string(forKey: VoiceOptions.voiceKey(target)))
        voice = chosen.voice; modelName = chosen.model
        apiKey = VoiceOptions.apiKey(target)
        maleVoice = VoiceOptions.sanitizedRoleVoice(provider: target, voice: d.string(forKey: VoiceOptions.roleKey("male", target)))
        femaleVoice = VoiceOptions.sanitizedRoleVoice(provider: target, voice: d.string(forKey: VoiceOptions.roleKey("female", target)))
    }

    /// 仅保存时提交草稿；切换提供方不会改变正在使用的配置。
    private func save() {
        if let issue = configurationIssue { error = issue; return }
        drafts[provider] = Draft(voice: voice, model: modelName, key: apiKey, male: maleVoice, female: femaleVoice)
        let d = UserDefaults.standard
        do {
            for (target, draft) in drafts where target != "system" {
                let key = draft.key.trimmingCharacters(in: .whitespacesAndNewlines)
                if !key.isEmpty { try Keychain.save(Data(key.utf8), key: VoiceOptions.secretKey(target)) }
            }
        } catch { self.error = "无法保存密钥：" + error.localizedDescription; return }
        for (target, draft) in drafts {
            let chosen = VoiceOptions.sanitized(provider: target, model: draft.model, voice: draft.voice)
            d.set(chosen.voice, forKey: VoiceOptions.voiceKey(target))
            if target != "system" { d.set(chosen.model, forKey: VoiceOptions.modelKey(target)) }
            d.set(VoiceOptions.sanitizedRoleVoice(provider: target, voice: draft.male), forKey: VoiceOptions.roleKey("male", target))
            d.set(VoiceOptions.sanitizedRoleVoice(provider: target, voice: draft.female), forKey: VoiceOptions.roleKey("female", target))
        }
        d.set(provider, forKey: "voice.provider"); d.set(rate, forKey: "voice.rate")
        d.set(groupID, forKey: "voice.groupID"); d.set(azureRegion, forKey: "voice.azureRegion"); d.set(roles, forKey: "voice.roles")
        d.set(customURL.trimmingCharacters(in: .whitespacesAndNewlines), forKey: VoiceOptions.customURLKey)
        if provider == "elevenlabs", let label = elevenVoices.first(where: { $0.value == voice })?.label { d.set(label, forKey: "voice.label.elevenlabs." + voice) }
        stopPreview(); app.player.applyOptions(); dismiss()
    }

}

extension Double {
    /// 语速文字，最多两位小数：%.2g 会把 1.75 写成「1.8」。
    var rateText: String { formatted(.number.precision(.fractionLength(0...2))) }
}
