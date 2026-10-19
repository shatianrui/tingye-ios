import SwiftUI
import AVKit

@main
struct TingyeApp: App {
    @StateObject private var model = AppModel()
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
                .environmentObject(model)
                .tint(Theme.accent)
                .background(WindowAppearance(style: UIUserInterfaceStyle(appearance: appearanceMode)))
                .onOpenURL { url in
                    model.run("正在导入书籍") {
                        try await model.importFiles([url])
                        model.message = "已导入《\(url.deletingPathExtension().lastPathComponent)》。"
                    }
                }
        }
    }
}

#if DEBUG
/// 无头模拟器 UI 走查：以 `-uireview <场景>` 启动后直达对应界面，供截图核查。
/// 场景：now / shelf / shelf-list / shelf-edit / sources[-wifi|-webdav]（经书库导入面板）/ stats / profile / detail / chapters / appearance / backup /
/// reader[-nochrome|-contents|-preferences|-voice|-listen] / player[-chapters|-voice] / miniplayer。
enum UIReview {
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

/// 外壳：四个独立导航栈（今日 / 书架 / 足迹 / 设置）；底部是纸底实色页签栏（顶部墨线），迷你播放器常驻其上。
struct RootView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var navigationHidden = false
    var body: some View {
        VStack(spacing: 0) {
        TabView(selection: $model.tab) {
            tabRoot { NowView(player: model.player) }
                .tabItem { Label("今日", systemImage: Icon.now) }
                .tag(0)
            tabRoot { ShelfView() }
                .tabItem { Label("书架", systemImage: Icon.shelf) }
                .tag(1)
            tabRoot { StatsView() }
                .tabItem { Label("足迹", systemImage: Icon.stats) }
                .tag(2)
            tabRoot { ProfileView() }
                .tabItem { Label("设置", systemImage: Icon.settings) }
                .tag(3)
        }
        .toolbar(.hidden, for: .tabBar)
        if !navigationHidden { LibraryNavigationBar(player: model.player) }
        }
        .disabled(model.restoringLibrary)
        .paperBackground()
        .onPreferenceChange(LibraryNavigationHiddenKey.self) { navigationHidden = $0 }
        .modifier(AppLockGate())
        .accessibilityLabel("听页主界面")
        .onChange(of: model.tab) { _, _ in Haptics.selection() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                model.refreshProgressSync()
            } else {
                model.flushPendingSaves()
                if phase == .background { model.hiddenUnlocked = false }
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
        .alert("听页提示", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
            Button("知道了", role: .cancel) { model.message = nil }
        } message: { Text(model.message ?? "") }
        .overlay(alignment: .top) {
            if model.busy {
                HStack(spacing: 10) { ProgressView(); Text(model.activity).font(.footnote).lineLimit(1) }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .glassSurface(in: Capsule())
                    .padding(.top, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .accessibilityElement(children: .combine)
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.busy)
    }

    /// 每个页签一个导航栈，切换页签时各自的栈状态保留。
    private func tabRoot<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        NavigationStack { content().toolbar(.hidden, for: .tabBar) }
            .toolbar(.hidden, for: .tabBar)
    }

    #if DEBUG
    private func driveUIReview() {
        guard let screen = UIReview.screen else { return }
        if screen == "now" { model.tab = 0; return }
        if screen.hasPrefix("shelf") || screen == "detail" || screen == "chapters" || screen.hasPrefix("sources") { model.tab = 1; return }
        if screen.hasPrefix("stats") { model.tab = 2; return }
        if ["profile", "appearance", "backup"].contains(screen) { model.tab = 3; return }
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
            model.run("正在打开") { [model] in model.startListening(try model.book(entry.id)) }
        }
    }
    #endif
}

/// 四个固定目的地与常驻的迷你播放器；各页签保留自己的导航栈。纸底实色栏，顶部 1.5pt 墨线。
private struct LibraryNavigationBar: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var player: SpeechPlayer
    private let items = [("今日", Icon.now), ("书架", Icon.shelf), ("足迹", Icon.stats), ("设置", Icon.settings)]
    var body: some View {
        VStack(spacing: 0) {
            if player.book != nil {
                MiniPlayer(player: player)
                    .frame(maxWidth: 560)
                    .padding(.horizontal, Theme.inset)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            HStack(spacing: 0) {
                ForEach(items.indices, id: \.self) { index in
                    let selected = model.tab == index
                    Button { model.tab = index } label: {
                        VStack(spacing: 4) {
                            ThemeIcon(symbol: items[index].1, size: 24, weight: selected ? .semibold : .regular)
                            Text(items[index].0).font(.system(size: 10, weight: selected ? .bold : .medium))
                            Rectangle().fill(Theme.accent).frame(width: 16, height: 3).opacity(selected ? 1 : 0)
                        }
                        .foregroundStyle(selected ? Theme.ink : Theme.ink3)
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressButtonStyle(scale: 0.92))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .accessibilityLabel(items[index].0)
                }
            }
            .frame(maxWidth: 560)
            .padding(.top, 8)
            .frame(maxWidth: .infinity)
            .background(Theme.bg.ignoresSafeArea(edges: .bottom))
            .overlay(alignment: .top) { InkRule(height: 1.5) }
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

/// 迷你播放器：墨底实色条（夜间反白），封面色块缩略图、书名与章节、播放 / 下一句，底边荧光黄进度线。
struct MiniPlayer: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var player: SpeechPlayer
    var body: some View {
        if let book = player.book {
            VStack(spacing: 0) {
                HStack(spacing: 4) {
                    Button { model.showingPlayer = true } label: {
                        HStack(spacing: 12) {
                            BookCoverView(title: book.title, color: book.color, image: model.covers[book.id], width: 34)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(book.title)
                                    .font(Theme.serifSemibold(15, relativeTo: .subheadline))
                                    .foregroundStyle(Theme.onInk)
                                    .lineLimit(1)
                                Text(subtitle)
                                    .font(.system(size: 11))
                                    .monospacedDigit()
                                    .foregroundStyle(player.error == nil ? Theme.onInk.opacity(0.65) : Theme.accent)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("打开播放器：\(book.title)")

                    Button { Haptics.light(); player.toggle() } label: {
                        Group {
                            if player.buffering {
                                ProgressView().controlSize(.small).tint(Theme.onInk)
                            } else {
                                ThemeIcon(symbol: Icon.playback(player.playing), size: 26)
                            }
                        }
                        .foregroundStyle(Theme.onInk)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressButtonStyle(scale: 0.88))
                    .accessibilityLabel(player.playing ? "暂停朗读" : "继续朗读")

                    Button { Haptics.light(); player.skip(1) } label: {
                        ThemeIcon(symbol: Icon.nextSentence, size: 22)
                            .foregroundStyle(Theme.onInk)
                            .frame(width: 40, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressButtonStyle(scale: 0.88))
                    .accessibilityLabel("下一句")

                    Menu {
                        if let entry = model.entries.first(where: { $0.id == book.id }) {
                            Button { model.open(entry) } label: { Label("回到正文", systemImage: Icon.read) }
                        }
                        Button { player.stop() } label: { Label("结束听书", systemImage: Icon.stopListening) }
                    } label: {
                        ThemeIcon(symbol: Icon.more, size: 20)
                            .foregroundStyle(Theme.onInk.opacity(0.7))
                            .frame(width: 34, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("听书更多操作")
                }
                .padding(.leading, 8)
                .padding(.trailing, 4)
                .padding(.vertical, 7)
                ProgressBar(value: player.progress, track: Theme.onInk.opacity(0.15), tint: Theme.marker, height: 3)
                    .accessibilityHidden(true)
            }
            .background(Theme.ink, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        }
    }
    private var subtitle: String {
        if player.error != nil { return "朗读出错 · 轻点打开重试" }
        if player.buffering { return "正在合成语音…" }
        return "\(player.playing ? "正在听" : "已暂停") · \(player.chapterTitle.isEmpty ? "第 \(player.chapter + 1) 章" : player.chapterTitle)"
    }
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
