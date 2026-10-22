import SwiftUI
import AVFoundation

/// 余白听书页：暖沙书签、衬线跟读与石墨控制台；句序号与定位始终真实。
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
    /// 句子流可见高度与当前句高度：长句会被底部控制区挡住，换句时据此把当前句滚进视野。
    @State private var viewportHeight: CGFloat = 0
    @State private var currentHeight: CGFloat = 0
    /// 长句跟读：逐词进度每秒推送数次，用引用类型承载，跟读滚动不触发整页重算（与 followPublisher 的设计一致）。
    @State private var follow = SentenceFollow()

    private var content: Color { Theme.ink }
    private var secondary: Color { Theme.ink2 }
    private var tertiary: Color { Theme.ink3 }

    var body: some View {
        ZStack(alignment: .top) {
            Theme.bg.ignoresSafeArea()
            if let book = player.book {
                GeometryReader { geometry in
                    if typeSize.isAccessibilitySize || geometry.size.height < 560 {
                        VStack(spacing: 0) {
                            ScrollView {
                                VStack(spacing: 0) {
                                    hero(book)
                                    VStack(spacing: 12) {
                                        SentenceProgressControl(player: player)
                                        footer
                                    }
                                    .padding(.horizontal, Theme.inset).padding(.vertical, 12)
                                    readingContent
                                }
                            }
                            // 只固定最重要的播放 / 跳句，其他控件随内容滚动，不挤压正文。
                            transportRow
                                .padding(.horizontal, Theme.inset).padding(.vertical, 10)
                                .background(Theme.bg)
                                .overlay(alignment: .top) { InkRule(height: 1.5) }
                                .accessibilityElement(children: .contain)
                                .accessibilitySortPriority(1)
                        }
                        // 大字号时不自动抢走滚动位置。
                    } else {
                        VStack(spacing: 0) {
                            hero(book)
                            ScrollViewReader { proxy in
                                ScrollView { readingContent }
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
                                        // 长句跟读：卡片高于可见区时随朗读滚动；手动翻阅后暂停 5 秒，不打断主动阅读。
                                        guard sentenceOverflows, Date().timeIntervalSince(follow.manualAt) > 5 else { return }
                                        revealCurrent(proxy)
                                    }
                            }
                            controls
                        }
                    }
                }
            } else { emptyState }
        }
        .foregroundStyle(content)
        .tint(Theme.accent)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .feedbackOverlay()
        .keepScreenAwake()
        .respectReducedMotion()
        .sheet(isPresented: $showingCover) {
            if let book = player.book {
                NavigationStack {
                    ScrollView {
                        VStack(spacing: 20) {
                            BookCoverView(title: book.title, color: book.color, author: book.author, image: model.covers[book.id], width: 220)
                            Text(book.title).font(.title3.weight(.semibold)).multilineTextAlignment(.center)
                            Text(book.author).font(.body)
                        }.padding(24).frame(maxWidth: .infinity)
                    }
                    .paperBackground().navigationTitle("书籍封面")
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
            NavigationStack { VoiceSettingsView() }.environmentObject(model).tint(Theme.accent)
        }
        .sheet(isPresented: $chaptersSheet) {
            if let book = player.book {
                NavigationStack { ChapterListView(book: book, player: player).environmentObject(model) }
                    .tint(Theme.accent)
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
        VStack(alignment: .leading, spacing: 16) {
            sentenceStream
            if let error = player.error { errorNotice(error).id("player.error") }
        }
        .padding(.horizontal, Theme.inset).padding(.vertical, 16)
        .frame(maxWidth: 600, alignment: .leading).frame(maxWidth: .infinity)
    }

    // MARK: 紧凑书名栏

    private func hero(_ book: Book) -> some View {
        let meta = "第 \(player.chapter + 1) / \(max(1, player.chapterCount)) 章"
        return VStack(alignment: .leading, spacing: 8) {
            // v22 顶栏：左收起、报纸蓝「看原文」、右侧目录与低频操作；眉题另起一栏，不与按钮叠放
            HStack(spacing: 4) {
                Button { dismiss() } label: {
                    ThemeIcon(symbol: Icon.collapse, size: 22)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .accessibilityLabel("收起播放器")
                .accessibilityIdentifier("player.collapse")
                Spacer(minLength: 8)
                // 回到正文是听书时最常用的跳转，单独放在顶栏
                Button {
                    if fromReader { dismiss() }
                    else { dismiss(); model.showingPlayer = false; model.selectedBook = book }
                } label: {
                    Text("看原文")
                        .font(.subheadline.weight(.medium)).foregroundStyle(Theme.link)
                        .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                }
                .accessibilityLabel("看原文")
                .accessibilityIdentifier("player.backToReader")
                Button { chaptersSheet = true } label: {
                    ThemeIcon(symbol: Icon.contents, size: 22)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .accessibilityLabel("听书目录，第 \(player.chapter + 1) 章")
                .accessibilityIdentifier("player.chapters")
                // 章节跳转归目录，声音归底部；这里只保留低频操作。
                Menu {
                    Button { showingCover = true } label: { Label("查看封面", systemImage: Icon.emptyBook) }
                    Divider()
                    Button(role: .destructive) { endingListening = true } label: { Label("结束听书", systemImage: Icon.stopListening) }
                        .accessibilityIdentifier("player.endListening")
                } label: {
                    ThemeIcon(symbol: Icon.more, size: 24)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .accessibilityLabel("更多听书操作")
                .accessibilityIdentifier("player.more")
            }
            .buttonStyle(.plain)
            .padding(.horizontal, -10)
            // 报刊栏目条：墨线 + 眉题与章节 + 细线
            VStack(spacing: 0) {
                Rectangle().fill(Theme.rulePaint).frame(height: 1)
                HStack {
                    Text("听书 · 正在朗读").font(Theme.kicker).tracking(1.5)
                    Spacer(minLength: 8)
                    Text(meta).font(.caption2).foregroundStyle(Theme.ink2)
                        .accessibilityIdentifier("player.currentChapter")
                }
                .padding(.vertical, 7)
                Rectangle().fill(Theme.line).frame(height: 1)
            }
            VStack(spacing: 6) {
                if !typeSize.isAccessibilitySize {
                    Button { showingCover = true } label: {
                        BookCoverView(title: book.title, color: book.color, image: model.covers[book.id], width: 64)
                    }.buttonStyle(.plain).accessibilityLabel("查看《\(book.title)》封面")
                        .accessibilityIdentifier("player.cover")
                }
                Text(book.title)
                    .font(Theme.serifBold(24, relativeTo: .title2)).serifEmbolden(24)
                    .multilineTextAlignment(.center)
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                if !book.author.isEmpty {
                    Text(book.author).font(.caption).foregroundStyle(Theme.ink2)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .foregroundStyle(content)
        .padding(.horizontal, Theme.inset).padding(.top, 10).padding(.bottom, 12)
        .frame(maxWidth: 600, alignment: .leading).frame(maxWidth: .infinity)
    }

    // MARK: 句子流：暖色表面与短竖线标记当前句；上下文可读，轻点定位

    private var sentenceStream: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 6) {
                if player.playing && !player.buffering {
                    Image(systemName: Icon.listening).symbolEffect(.variableColor.iterative, isActive: !reduceMotion)
                }
                Text(player.buffering ? "正在准备声音" : (player.playing ? "正在朗读" : "朗读已暂停"))
            }
            .font(.caption).foregroundStyle(Theme.accent)
            ForEach([2, 1], id: \.self) { back in
                if player.position - back >= 0, let previous = player.surroundingSentence(before: player.position - back + 1) {
                    lyricLine(previous.text, offset: -back)
                }
            }
            if let sentence = player.currentSentence {
                VStack(alignment: .leading, spacing: 0) {
                    Text("“").font(Theme.serifBold(56, relativeTo: .largeTitle)).foregroundStyle(Theme.clay)
                        .frame(height: 40, alignment: .top).accessibilityHidden(true)
                    Text(sentence.text)
                        .font(Theme.serifBold(24, relativeTo: .title2)).lineSpacing(10)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .markerHighlight()
                        .id(player.position)
                        .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
                        .accessibilityLabel("当前句：\(sentence.text)")
                }
                .padding(12)
                .overlay { RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).strokeBorder(Theme.line, lineWidth: 1) }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { currentHeight = $0 }
                .id(Self.currentSentenceID)
            } else {
                Text(player.book?.chapters.first?.text ?? "暂无内容")
                    .font(.body).lineSpacing(7).lineLimit(4)
            }
            ForEach([1, 2, 3], id: \.self) { ahead in
                if let next = player.surroundingSentence(after: player.position + ahead - 1) {
                    lyricLine(next.text, offset: ahead)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .animation(.easeOut(duration: 0.3), value: player.position)
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
                .font(Theme.serif(18, relativeTo: .body)).lineSpacing(6)
                .foregroundStyle(Theme.ink2)
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
        VStack(spacing: 8) {
            SentenceProgressControl(player: player)
            transportRow
            footer
        }
        .padding(.top, 14).padding(.bottom, 8)
        .frame(maxWidth: 560)
        .overlay(alignment: .top) { Rectangle().fill(Theme.rulePaint).frame(height: 1) }
        .padding(.horizontal, Theme.inset).padding(.bottom, 8)
        .frame(maxWidth: 600).frame(maxWidth: .infinity)
        .background(Theme.bg.ignoresSafeArea(edges: .bottom))
    }

    private var transportRow: some View {
        HStack(spacing: typeSize.isAccessibilitySize ? 8 : 20) {
            TransportButton(systemName: Icon.previousSentence, label: "上一句", size: 40) { player.skip(-1) }
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("player.previousSentence")
            Button { Haptics.light(); player.toggle() } label: {
                ZStack {
                    Circle().fill(Theme.clay)
                    if player.buffering { ProgressView().tint(Theme.onClay) }
                    else { ThemeIcon(symbol: Icon.playback(player.playing), size: 26).foregroundStyle(Theme.onClay) }
                }
                .frame(width: 64, height: 64)
                .contentShape(Circle())
            }
            .buttonStyle(PressButtonStyle(scale: 0.94))
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
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .top), count: typeSize.isAccessibilitySize ? 2 : 4), spacing: 12) {
            Button { chaptersSheet = true } label: { footerItem(Icon.contents, "目录") }
                .accessibilityLabel("听书目录，第 \(player.chapter + 1) 章")
                .accessibilityIdentifier("player.contents")
            Menu {
                Picker("语速", selection: Binding(get: { player.rate }, set: { player.changeRate($0) })) {
                    ForEach([0.5, 0.75, 0.8, 1.0, 1.2, 1.25, 1.5, 1.75, 2.0], id: \.self) { value in
                        Text(value.rateText + "×").tag(value)
                    }
                }
            } label: { footerItem(Icon.rate, "\(player.rate.rateText)×", highlighted: player.rate != 1.0) }
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
                } label: { footerItem(Icon.sleepTimer, sleepLabel(at: context.date), highlighted: player.sleepUntil != nil) }
                .accessibilityLabel("定时停止")
                .accessibilityValue(player.sleepUntil == nil ? "未开启" : sleepLabel(at: context.date))
                .accessibilityIdentifier("player.sleep")
            }
        }
        .buttonStyle(.plain)
    }

    /// v22 报刊工具：线性图标在上、小字在下，无边框；开启状态加粗并加下划线。
    private func footerItem(_ symbol: String, _ title: String, highlighted: Bool = false) -> some View {
        VStack(spacing: 4) {
            ThemeIcon(symbol: symbol, size: 21)
            Text(L(title)).font(.caption.weight(highlighted ? .bold : .regular))
                .foregroundStyle(highlighted ? Theme.ink : Theme.ink2)
                .underline(highlighted, color: Theme.ink)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .foregroundStyle(content)
        .frame(maxWidth: .infinity, minHeight: 50)
        .contentShape(Rectangle())
    }

    private func errorNotice(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(error).font(.footnote).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
            ViewThatFits(in: .horizontal) {
                HStack { recoveryButtons }
                VStack(alignment: .leading) { recoveryButtons }
            }
        }
        .padding(.leading, 14).padding(.vertical, 6)
        .overlay(alignment: .leading) { Rectangle().fill(Theme.danger).frame(width: 3) }
    }

    @ViewBuilder private var recoveryButtons: some View {
        Button("重试朗读") { player.resume() }.frame(minHeight: 44)
        Button("检查声音设置") { settings = true }.frame(minHeight: 44)
    }

    private func sleepLabel(at date: Date) -> String {
        if let until = player.sleepUntil, until > date {
            return "\(Int(ceil(until.timeIntervalSince(date) / 60))) 分后停"
        }
        return "定时"
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("听一卷书，歇一歇眼", systemImage: Icon.listen)
        } description: { Text("打开一本书，轻点耳机，继续书中的旅程。") } actions: {
            if let last = model.lastBook {
                Button("听《\(last.title)》") { model.listen(last.id) }
                    .buttonStyle(PrimaryButtonStyle(height: 44)).frame(maxWidth: 240)
            }
        }
        .foregroundStyle(content)
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
                .foregroundStyle(enabled ? Theme.ink : Theme.ink3)
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
/// v21 刻度进度轨：33 根 1px 刻度，已播 20px 蓝色、未播 8px 灰色，10px 蓝圆点 thumb。
/// 刻度轨本体直接承载拖动：v21 初版叠了一层 opacity 0.02 的隐形 Slider 作交互层，
/// 但低透明度视图被 UIKit 命中测试排除，真实触摸与 XCUITest 拖动都穿过了它，滑杆不可拖。
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
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                let ticks = 33
                let done = Int((progress * Double(ticks)).rounded())
                ZStack(alignment: .leading) {
                    HStack(spacing: 0) {
                        ForEach(0..<ticks, id: \.self) { i in
                            Rectangle()
                                .fill(i < done ? Theme.accent : Theme.line)
                                .frame(width: 1, height: i < done ? 20 : 8)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    Circle().fill(Theme.clay)
                        .frame(width: 10, height: 10)
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
                VStack(alignment: .leading, spacing: 4) { Text(sentenceLabel); estimate }
            }
            .font(Theme.masthead).monospacedDigit().foregroundStyle(Theme.ink2)
        }
    }
    private var estimate: some View {
        Text(player.estimatedRemainingLabel(from: shown)).foregroundStyle(Theme.ink3)
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
        .tint(Theme.accent)
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
                VStack(alignment: .leading, spacing: 8) {
                    Text(book.title).font(.title3.weight(.semibold)).foregroundStyle(Theme.ink)
                    HStack(spacing: 7) {
                        Image(systemName: Icon.listening)
                        Text("共 \(book.chapters.count) 章 · 正在听第 \(player.chapter + 1) 章")
                    }
                    .font(.caption).foregroundStyle(Theme.accent)
                    Text("\(player.timingLabel) · \(player.rate.rateText)×")
                        .font(.caption).foregroundStyle(Theme.ink3)
                }
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 14, trailing: 0))
                VStack(spacing: 8) {
                    HStack {
                        Button { player.skipChapter(-1) } label: { Label("上一章", systemImage: Icon.back) }
                            .disabled(player.chapter == 0)
                        Spacer()
                        Button { player.skipChapter(1) } label: { Label("下一章", systemImage: Icon.disclosure) }
                            .disabled(player.chapter + 1 >= player.chapterCount)
                    }
                    .font(.subheadline).buttonStyle(.borderless)
                    .frame(minHeight: 44)
                    ChapterProgressSlider(player: player)
                }
                .listRowBackground(Theme.surface)
                ForEach(filtered, id: \.index) { item in
                    let current = item.index == player.chapter
                    Button {
                        player.seek(chapter: item.index, position: 0)
                        dismiss()
                    } label: {
                        HStack(spacing: 14) {
                            Text(String(format: "%02d", item.index + 1))
                                .font(.system(size: 12, weight: current ? .semibold : .regular).monospacedDigit())
                                .foregroundStyle(current ? Theme.accent : Theme.ink3)
                                .frame(width: 30, alignment: .leading)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(item.chapter.title)
                                    .font(.body.weight(current ? .medium : .regular))
                                    .foregroundStyle(current ? Theme.ink : Theme.ink2)
                                if current {
                                    Text("正在听 · \(Int(player.progress * 100))%")
                                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                                        .foregroundStyle(Theme.accent)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            if current {
                                Image(systemName: Icon.listening).font(.system(size: 17)).foregroundStyle(Theme.accent)
                            }
                        }
                        .padding(.vertical, 9)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowSeparator(.hidden)
                    .listRowBackground(current ? Theme.accentSoft : Theme.surface)
                    .id(item.index)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .searchable(text: $query, prompt: "搜索章节")
            .navigationTitle("听书目录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: Icon.close)
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .accessibilityLabel("关闭章节列表")
                }
            }
            .onAppear {
                DispatchQueue.main.async {
                    proxy.scrollTo(player.chapter, anchor: .center)
                }
            }
        }
    }

}

// MARK: - 听书与声音设置面板（原生 Form）

struct VoiceSettingsView: View {
    @EnvironmentObject var app: AppModel
    @State private var fetchedVoices: [CloudVoice] = []
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
    private var voices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("zh") || $0.language.hasPrefix("en") }.sorted { $0.language + $0.name < $1.language + $1.name }
    }

    var body: some View {
        Form {
            providerSection.listRowBackground(Theme.surface)
            connectionSection.listRowBackground(Theme.surface)
            voiceSection.listRowBackground(Theme.surface)
            rateSection.listRowBackground(Theme.surface)
            roleSection.listRowBackground(Theme.surface)
            Section {
                HStack {
                    Label("音频输出", systemImage: Icon.speaker)
                    Spacer(minLength: 8)
                    AirPlayButton().frame(width: 44, height: 44)
                        .accessibilityLabel("选择音频输出设备")
                        .accessibilityIdentifier("voice.audioOutput")
                }
            } header: { Text("播放设备") } footer: {
                Text("选择扬声器、耳机或 AirPlay。设备切换立即生效，不需要保存声音设置。")
            }
            .listRowBackground(Theme.surface)
            Section {
                Text(auditionHint)
                    .font(.caption).foregroundStyle(Theme.ink2)
                if let error { Text(error).font(.caption).foregroundStyle(Theme.danger) }
                if !notice.isEmpty { Text(L(notice)).font(.caption).foregroundStyle(Theme.ink2) }
            } header: { Text("3 · 试听与保存") }
        }
        .scrollContentBackground(.hidden).background(Theme.bg).tint(Theme.accent)
        .navigationTitle("声音设置")
            .navigationBarBackButtonHidden().navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }.accessibilityLabel("取消声音设置，不保存修改")
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 12) {
                Button { previewing ? stopPreview() : testVoice() } label: {
                    Label(previewing ? "停止试听" : "试听", systemImage: Icon.previewPlayback(previewing))
                }
                .buttonStyle(SecondaryButtonStyle(height: 48))
                .accessibilityIdentifier("voice.preview")
                Button("保存并应用") { save() }
                    .buttonStyle(PrimaryButtonStyle(height: 48))
                    .accessibilityIdentifier("voice.save")
            }
            .padding(.horizontal, 24).padding(.vertical, 12)
            .frame(maxWidth: 760).frame(maxWidth: .infinity)
            .background(Theme.bg)
        }
        .feedbackOverlay()
        .respectReducedMotion()
        .onAppear { if loadedProvider.isEmpty { load(provider) } }
        .onDisappear { stopPreview() }
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
        } header: { Text("1 · 选择提供方") } footer: { Text(providerNote) }
    }

    @ViewBuilder private var connectionSection: some View {
        if provider != "system" {
            Section {
                if provider == "custom" {
                    TextField("服务地址，如 https://example.com/v1", text: $customURL)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("voice.customURL")
                }
                SecureField(provider == "azure" ? "Speech Key（必填）" : provider == "custom" ? "API Key（自建服务可留空）" : "API Key（必填）", text: $apiKey)
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
            HStack(spacing: 12) {
                Image(systemName: Icon.voice).font(.system(size: 21)).foregroundStyle(Theme.onAccent)
                    .frame(width: 44, height: 44).background(Theme.auroraGradient, in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 4) {
                    Text(currentVoiceName).font(.body.weight(.semibold)).foregroundStyle(Theme.ink)
                    Text(currentVoiceSubtitle).font(.caption2).foregroundStyle(Theme.ink3)
                }
            }
            voicePicker
            if provider == "minimax" || provider == "elevenlabs" {
                Button { refreshVoices() } label: { Label("刷新账号音色", systemImage: Icon.refresh) }
                    .disabled(app.busy || apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        } header: { Text("2 · 选择音色") }
    }

    private var rateSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("语速").font(.subheadline)
                    Spacer()
                    Text(rate.rateText + "×").font(.title3.weight(.medium)).monospacedDigit().foregroundStyle(Theme.accent)
                }
                Slider(value: $rate, in: 0.5...2, step: 0.05)
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
                    .font(.caption).foregroundStyle(Theme.ink3)
            }
        } header: { Text("更多声音选项") }
    }

    // MARK: - Voice Picker

    @ViewBuilder
    private var voicePicker: some View {
        if provider == "system" {
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
