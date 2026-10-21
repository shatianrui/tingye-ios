import SwiftUI
import AVKit

@main
struct TingyeApp: App {
    @StateObject private var model: AppModel = {
        #if DEBUG
        if UIReview.isolated {
            do { return try UIReview.makeFixture()! }
            catch { fatalError("UI fixture could not be created: \(error)") }
        }
        #endif
        return AppModel()
    }()
    init() {
        FontLibrary.registerAll()
        let navigation = UINavigationBarAppearance()
        navigation.configureWithTransparentBackground()
        navigation.titleTextAttributes = [.foregroundColor: UIColor(Theme.ink)]
        navigation.largeTitleTextAttributes = [.foregroundColor: UIColor(Theme.ink)]
        UINavigationBar.appearance().standardAppearance = navigation
        UINavigationBar.appearance().scrollEdgeAppearance = navigation
        let tabs = UITabBarAppearance()
        tabs.configureWithOpaqueBackground()
        tabs.backgroundColor = UIColor(Theme.bg).withAlphaComponent(0.96)
        UITabBar.appearance().standardAppearance = tabs
        UITabBar.appearance().scrollEdgeAppearance = tabs
    }
    @AppStorage("app.appearance") private var appearanceMode = "system"
    var body: some Scene {
        WindowGroup {
            RootView()
                #if DEBUG
                .modifier(UIReviewAppearance())
                #endif
                .environmentObject(model)
                .tint(Theme.accent)
                .background(WindowAppearance(style: UIUserInterfaceStyle(appearance: appearanceMode)))
                .onOpenURL { url in
                    model.beginImport([url])
                }
        }
    }
}

#if DEBUG
/// 无头模拟器 UI 走查：以 `-uireview <场景>` 启动后直达对应界面，供截图核查。
/// 场景：now / shelf / shelf-list / shelf-edit / sources[-wifi|-webdav]（经书库导入面板）/ stats / profile / detail / chapters / appearance / backup /
/// reader[-nochrome|-contents|-preferences|-voice|-listen] / player[-chapters|-voice] / miniplayer。
enum UIReview {
    static var isolated: Bool { ProcessInfo.processInfo.arguments.contains("-ui-fixture") }
    static var showcase: Bool { isolated && ProcessInfo.processInfo.arguments.contains("-ui-showcase") }
    /// UI 回归只写临时书库，不修改用户书籍，也不连接云语音 / iCloud。
    @MainActor static func makeFixture() throws -> AppModel? {
        guard isolated else { return nil }
        if ProcessInfo.processInfo.arguments.contains("-ui-reset-preferences") {
            // 仅自动化临时书库：写入可修改的初值。启动参数域会锁住 @AppStorage，无法测试用户切换。
            UserDefaults.standard.set("paper", forKey: "reader.paper")
            UserDefaults.standard.set("list", forKey: "shelf.layout")
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-ui-appearance"), args.indices.contains(i + 1),
               ["system", "light", "dark"].contains(args[i + 1]) {
                UserDefaults.standard.set(args[i + 1], forKey: "app.appearance")
            }
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ui-review-" + UUID().uuidString)
        let disk = try LibraryDisk(owner: "fixture", base: root)
        let text = (1...12).map { "第\($0)句，" + String(repeating: "安静读书，", count: 22) + "这一段结束。" }.joined()
        let first = Book(id: "ui-long", title: "一本用来检查长标题和阅读体验的书", author: "测试作者", format: "TXT", chapters: [.init(title: "第一章：长句与听书进度", text: text), .init(title: "第二章", text: text)])
        let second = Book(id: "ui-recent", title: "最近在读", format: "TXT", chapters: [.init(title: "正文", text: "另一段阅读。")])
        let books = showcase ? showcaseBooks() : [first, second]
        guard !books.isEmpty else { throw ReaderError.message("预览示例未加载。") }
        for book in books { try disk.write(book) }
        let rows = books.enumerated().map { index, book in
            var row = ShelfEntry(book: book, progress: .init(chapter: 0, position: showcase ? (index == 0 ? 4 : 1) : (index == 0 ? 1 : 0), updatedAt: Double(books.count - index) * 100))
            row.lastActivity = .reading
            return row
        }
        try disk.saveCatalog(rows)
        let defaults = UserDefaults(suiteName: "ui-review.offline")!
        defaults.set(false, forKey: ProgressSync.enabledKey)
        let model = AppModel(disk: disk, progressSync: ProgressSync(defaults: defaults, account: { false }))
        if showcase {
            // 仅用于截图的演示记录；正常书库与发布构建不会生成这些数据。
            for offset in 0..<7 {
                let end = Calendar.current.date(byAdding: .day, value: -offset, to: Date())!
                let seconds = Double([18, 26, 12, 22, 0, 31, 16][offset] * 60)
                model.readingSeconds[AppModel.dayKey(end)] = seconds
                if seconds > 0 {
                    model.sessions.append(.init(bookID: books[0].id, title: books[0].title, start: end.addingTimeInterval(-seconds), end: end, seconds: seconds, listening: offset % 3 == 1))
                }
            }
        }
        return model
    }
    /// 使用项目已有的公版节选与本地绘制的示意书封；不从网络取图，也不改写 Samples。
    @MainActor private static func showcaseBooks() -> [Book] {
        Samples.books.enumerated().map { index, source in
            var book = source
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: 240, height: 344))
            let image = renderer.image { context in
                let palettes: [(UInt32, UInt32, UInt32)] = [(0x294C5A, 0x8DAAA3, 0xC4B58E), (0xDFE7D6, 0x91AF9B, 0x527A70), (0xE4D8C2, 0x91A7AD, 0x496C7B)]
                let palette = palettes[index % palettes.count]
                UIColor(hex: palette.0).setFill(); context.fill(CGRect(x: 0, y: 0, width: 240, height: 344))
                UIColor(hex: index == 0 ? 0xE6CA8F : 0xF6EFCE).setFill()
                UIBezierPath(ovalIn: CGRect(x: 139, y: 133, width: 63, height: 63)).fill()
                for layer in 0..<2 {
                    UIColor(hex: layer == 0 ? palette.1 : palette.2).setFill()
                    let y = CGFloat(225 + layer * 38)
                    let path = UIBezierPath()
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addCurve(to: CGPoint(x: 240, y: y - 8), controlPoint1: CGPoint(x: 90, y: y - 70), controlPoint2: CGPoint(x: 150, y: y + 58))
                    path.addLine(to: CGPoint(x: 240, y: 344)); path.addLine(to: CGPoint(x: 0, y: 344)); path.close(); path.fill()
                }
                let foreground = UIColor(hex: index == 0 ? 0xF4EEDB : 0x304B4F)
                (book.title as NSString).draw(in: CGRect(x: 28, y: 36, width: 190, height: 80), withAttributes: [.font: UIFont.systemFont(ofSize: 31, weight: .medium), .foregroundColor: foreground, .kern: 4])
                (book.author as NSString).draw(at: CGPoint(x: 30, y: 91), withAttributes: [.font: UIFont.systemFont(ofSize: 13), .foregroundColor: foreground])
                ("听页 · 示例节选" as NSString).draw(at: CGPoint(x: 27, y: 315), withAttributes: [.font: UIFont.systemFont(ofSize: 11), .foregroundColor: UIColor.white])
            }
            if let data = image.pngData() { book.fields["cover"] = .string("data:image/png;base64," + data.base64EncodedString()) }
            return book
        }
    }

    static let screen: String? = {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-uireview"), args.count > i + 1 else { return nil }
        return args[i + 1]
    }()
    /// `-uireview-chapter N`：打开书籍后直接跳到第 N 章（0 起）。
    static let chapter: Int? = {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-uireview-chapter"), args.count > i + 1 else { return nil }
        return Int(args[i + 1])
    }()
}
#endif

/// 三个独立导航栈；轻量页签栏与可选的迷你播放器。
struct RootView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var navigationHidden = false
    var body: some View {
        VStack(spacing: 0) {
        TabView(selection: $model.tab) {
            tabRoot { ShelfView() }
                .tabItem { Label("书", systemImage: Icon.shelf) }
                .tag(0)
            tabRoot { NowView(player: model.player) }
                .tabItem { Label("读", systemImage: Icon.read) }
                .tag(1)
            tabRoot { StatsView(ji: true) }
                .tabItem { Label("己", systemImage: Icon.profile) }
                .tag(2)
        }
        .toolbar(.hidden, for: .tabBar)
        if !navigationHidden { LibraryNavigationBar(player: model.player) }
        }
        .disabled(model.restoringLibrary)
        .paperBackground()
        .onPreferenceChange(LibraryNavigationHiddenKey.self) { navigationHidden = $0 }
        .onChange(of: model.tab) { _, _ in Haptics.selection() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                model.refreshProgressSync()
            } else {
                model.flushPendingSaves()
                if phase == .background { model.hiddenUnlocked = false; model.notice = nil }
            }
        }
        .task {
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
                if model.player.playing && !model.player.buffering, let book = model.player.book {
                    model.recordReading(seconds: 5, bookID: book.id, title: book.title, listening: true)
                }
            }
        }
        #if DEBUG
        .task {
            if UIReview.screen != nil {
                // Wait for TabView to finish installing its native selection binding.
                try? await Task.sleep(for: .milliseconds(350))
                driveUIReview()
            }
        }
        #endif
        .fullScreenCover(item: $model.selectedBook) { book in
            NavigationStack {
                if book.fields["comic"]?.bool == true { ComicReaderView(book: book) }
                else { ReaderView(book: book, player: model.player) }
            }
                .environmentObject(model)
                .tint(Theme.accent)
        }
        .sheet(isPresented: $model.showingPlayer) {
            PlayerView(player: model.player)
                .environmentObject(model)
        }
        .alert("操作未完成", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
            Button("关闭", role: .cancel) { model.message = nil }
        } message: { Text(model.message ?? "") }
        .feedbackOverlay()
        .modifier(AppLockGate())
        .respectReducedMotion()
    }

    /// 每个页签一个导航栈，切换页签时各自的栈状态保留。
    private func tabRoot<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        NavigationStack { content().toolbar(.hidden, for: .tabBar) }
            .toolbar(.hidden, for: .tabBar)
    }

    #if DEBUG
    private func driveUIReview() {
        guard let screen = UIReview.screen else { return }
        if screen == "now" { model.tab = 1; return }
        if screen == "import-results", UIReview.isolated {
            model.tab = 0
            model.run("正在导入书籍") {
                let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: folder) }
                let good = folder.appendingPathComponent("成功示例.txt"), bad = folder.appendingPathComponent("失败示例.json")
                try Data("导入成功的文字。".utf8).write(to: good)
                try Data("broken".utf8).write(to: bad)
                try await model.importWithFeedback([good, bad])
            }
            return
        }
        if screen.hasPrefix("shelf") || screen == "detail" || screen == "chapters" || screen.hasPrefix("sources") { model.tab = 0; return }
        if screen.hasPrefix("stats") || ["profile", "appearance", "backup"].contains(screen) { model.tab = 2; return }
        if screen == "comic", let comic = model.entries.first(where: \.isComic) { model.open(comic); return }
        guard let entry = model.lastBook ?? model.entries.first(where: \.local) else { return }
        if screen == "reader-original" {
            let target = model.entries.first { $0.format.uppercased() == "EPUB" } ?? entry
            if let chapter = UIReview.chapter { model.saveProgress(target.id, chapter: chapter, position: 0) }
            model.open(target)
        } else if screen == "reader-original-listen" || screen == "reader-listen" {
            let target = screen == "reader-listen" ? entry : model.entries.first { $0.format.uppercased() == "EPUB" } ?? entry
            model.run("正在打开") { [model] in
                let book = try model.book(target.id)
                model.selectedBook = book
                model.startListening(book, showPlayer: false)
            }
        } else if screen.hasPrefix("reader") {
            model.open(entry)
        } else if screen == "miniplayer" {
            model.run("正在打开") { [model] in model.startListening(try model.book(entry.id), showPlayer: false) }
        } else if screen.hasPrefix("player") {
            model.run("正在打开") { [model] in
                model.startListening(try model.book(entry.id))
                if UIReview.isolated { model.player.pause() }
            }
        }
    }
    #endif
}

#if DEBUG
private struct UIReviewAppearance: ViewModifier {
    func body(content: Content) -> some View {
        content
            .transaction {
                if ProcessInfo.processInfo.arguments.contains("-ui-reduce-motion") { $0.animation = nil; $0.disablesAnimations = true }
            }
    }
}
#endif

/// 刊导航：顶部墨线 + 编号与宋体页签，选中项由墨色、字重与陶土下划线共同标记。
private struct LibraryNavigationBar: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var player: SpeechPlayer
    private let items = [("书", Icon.shelf), ("读", Icon.read), ("己", Icon.profile)]
    var body: some View {
        VStack(spacing: 0) {
            if player.book != nil {
                MiniPlayer(player: player)
                    .frame(maxWidth: 560)
                    .padding(.horizontal, Theme.inset)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            HStack(spacing: 6) {
                ForEach(items.indices, id: \.self) { index in
                    let selected = model.tab == index
                    Button { Haptics.selection(); model.tab = index } label: {
                        VStack(spacing: 2) {
                            Text(String(format: "%02d", index + 1))
                                .font(.system(size: 10, weight: .bold)).tracking(1)
                                .foregroundStyle(selected ? Theme.accent : Theme.ink3)
                            Text(items[index].0).font(Theme.serif(20, relativeTo: .title3))
                                .fontWeight(selected ? .bold : .regular)
                                .foregroundStyle(selected ? Theme.ink : Theme.ink3)
                            Rectangle().fill(selected ? Theme.clay : .clear).frame(width: 22, height: 3)
                        }
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressButtonStyle(scale: 0.96))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .accessibilityLabel(items[index].0)
                    .accessibilityIdentifier("navigation.tab.\(index)")
                }
            }
            .padding(.top, 8)
            .frame(maxWidth: 560)
            .padding(.horizontal, Theme.inset)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .top) { Rectangle().fill(Theme.rulePaint).frame(height: Theme.ruleMedium) }
            .background(Theme.bg.ignoresSafeArea(edges: .bottom))
        }
        .animation(Theme.smoothSpring, value: player.book?.id)
    }
}

/// 直接设定窗口外观。SwiftUI 的 preferredColorScheme 从 .dark 改回 nil 后不会恢复系统外观，深色纸切回浅色纸会停在深色。
struct WindowAppearance: UIViewRepresentable {
    let style: UIUserInterfaceStyle
    /// 视图离开窗口时恢复的外观，如阅读页关闭后回到 App 外观；nil 表示不恢复。
    var restore: UIUserInterfaceStyle? = nil
    func makeUIView(context: Context) -> Probe { Probe() }
    func updateUIView(_ view: Probe, context: Context) { view.restore = restore; view.style = style }
    final class Probe: UIView {
        var restore: UIUserInterfaceStyle?
        var style = UIUserInterfaceStyle.unspecified { didSet { if style != oldValue { apply() } } }
        override init(frame: CGRect) { super.init(frame: frame); isUserInteractionEnabled = false; isHidden = true }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func didMoveToWindow() { super.didMoveToWindow(); apply() }
        override func willMove(toWindow newWindow: UIWindow?) {
            super.willMove(toWindow: newWindow)
            if newWindow == nil, let restore { window?.overrideUserInterfaceStyle = restore }
        }
        private func apply() { window?.overrideUserInterfaceStyle = style }
    }
}

extension UIUserInterfaceStyle {
    init(appearance: String) { self = appearance == "dark" ? .dark : appearance == "light" ? .light : .unspecified }
}

// MARK: - 迷你播放器（底部导航上方）

/// 迷你播放器只负责「展开」与「播放 / 暂停」；跳句、设置和结束统一在完整听书页。
struct MiniPlayer: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var player: SpeechPlayer
    @Environment(\.dynamicTypeSize) private var typeSize
    private var layout: AnyLayout { typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 4)) : AnyLayout(HStackLayout(spacing: 4)) }
    var body: some View {
        if let book = player.book {
            VStack(spacing: 0) {
                layout {
                    Button { model.showingPlayer = true } label: {
                        HStack(spacing: 12) {
                            BookCoverView(title: book.title, color: book.color, image: model.covers[book.id], width: 34)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(book.title)
                                    .font(Theme.serifSemibold(15, relativeTo: .subheadline))
                                    .foregroundStyle(Theme.ink)
                                    .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
                                Text(subtitle)
                                    .font(.caption)
                                    .monospacedDigit()
                                    .foregroundStyle(Theme.ink3)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            ThemeIcon(symbol: Icon.expandUp, size: 18).foregroundStyle(Theme.ink3)
                                .accessibilityHidden(true)
                        }
                        .frame(minHeight: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("展开听书页：\(book.title)，\(subtitle)")
                    .accessibilityIdentifier("miniPlayer.open")

                    Button { Haptics.light(); player.toggle() } label: {
                        Group {
                            if player.buffering {
                                ProgressView().controlSize(.small).tint(Theme.onClay)
                            } else {
                                ThemeIcon(symbol: Icon.playback(player.playing), size: 24)
                            }
                        }
                        .foregroundStyle(Theme.onClay)
                        .frame(width: 48, height: 44)
                        .background(Theme.clay, in: Rectangle())
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressButtonStyle(scale: 0.88))
                    .accessibilityLabel(player.playing ? "暂停朗读" : "继续朗读")
                    .accessibilityIdentifier("miniPlayer.toggle")
                }
                .padding(.leading, 8)
                .padding(.trailing, 4)
                .padding(.vertical, 7)
                ProgressBar(value: player.progress, tint: Theme.clay, height: 2)
                    .accessibilityHidden(true)
            }
            .background(Theme.surface, in: Rectangle())
            .overlay { Rectangle().strokeBorder(Theme.rulePaint, lineWidth: 1) }
        }
    }
    private var subtitle: String {
        if player.error != nil { return "朗读出错 · 轻点打开重试" }
        if player.buffering { return "正在合成语音…" }
        return "\(player.playing ? "正在听" : "已暂停") · \(player.chapterTitle.isEmpty ? "第 \(player.chapter + 1) 章" : player.chapterTitle)"
    }
}

/// 不阻断操作的成功反馈；导入失败在逐项结果页处理，删除/覆盖仍保留原确认流程。
private struct FeedbackOverlay: ViewModifier {
    @EnvironmentObject private var model: AppModel
    @State private var showingResults = false
    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .top, spacing: 0) {
            if let notice = model.notice {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top, spacing: 8) {
                        Text(notice.text).font(.subheadline).foregroundStyle(Theme.ink)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 10)
                        Button { model.notice = nil } label: {
                            ThemeIcon(symbol: Icon.close).frame(width: 44, height: 44)
                        }.accessibilityLabel("关闭提示")
                    }
                    if notice.importResults {
                        Button("查看逐项结果") { model.notice = nil; showingResults = true }
                            .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                            .accessibilityIdentifier("import.results")
                    }
                }
                .padding(.horizontal, 16)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
                .background(Theme.surface)
                .overlay(alignment: .bottom) { RowDivider() }
            } else if model.busy {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(model.activity).font(.footnote).fixedSize(horizontal: false, vertical: true)
                }
                .padding(12).frame(maxWidth: .infinity).background(Theme.surface)
                .accessibilityElement(children: .combine)
            }
        }
        .sheet(isPresented: $showingResults) {
            NavigationStack { ImportResultsView() }.environmentObject(model).tint(Theme.accent)
        }
    }
}
extension View {
    func feedbackOverlay() -> some View { modifier(FeedbackOverlay()) }
}

/// 系统 AirPlay 路由选择按钮
struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.activeTintColor = UIColor(Theme.accent)
        view.tintColor = UIColor(Theme.ink)
        return view
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
struct LibraryNavigationHiddenKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}
