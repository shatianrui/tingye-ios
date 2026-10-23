import SwiftUI
import ImageIO
import Pow

/// 漫画模式（参照 PureLibro）：左→右翻页、右→左（日漫）、上下条漫三种；轻点中间显示工具栏，双击放大。
/// 每页对应一个章节，进度按页保存，与书籍的「章 + 句」进度、iCloud 同步一致。
struct ComicReaderView: View {
    @ScaledMetric(relativeTo: .body) private var uiScale: CGFloat = 1
    let book: Book
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.scenePhase) var scenePhase
    /// 每部漫画单独记住阅读方式；没设置过的用「漫画默认阅读方式」。
    @State private var mode: String
    init(book: Book) {
        self.book = book
        _mode = State(initialValue: ComicPreset.mode(for: book.id))
    }
    @State private var page = 0
    @State private var chrome = false
    @State private var scrubbing: Double?
    @State private var showingPages = false
    @State private var showingHelp = false
    @State private var onlyBookmarks = false
    @State private var pageJumpRevision = 0
    private var bookmarks: [Bookmark] { model.entries.first(where: { $0.id == book.id })?.bookmarks ?? [] }
    private var marked: Bool { bookmarks.contains { $0.chapter == page && $0.position == 0 } }
    private var directoryPages: [Int] {
        onlyBookmarks ? Array(Set(bookmarks.map(\.chapter))).filter { $0 >= 0 && $0 < count }.sorted() : Array(0..<count)
    }
    private var count: Int { book.chapters.count }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            if mode == "vertical" {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(0..<count, id: \.self) { index in
                                ComicPage(book: book, index: index, fit: .width)
                                    .id(index)
                                    .onAppear { page = index }
                            }
                        }
                    }
                    .onTapGesture { toggle() }
                    .onAppear { proxy.scrollTo(page, anchor: .top) }
                    .onChange(of: pageJumpRevision) { _, _ in proxy.scrollTo(page, anchor: .top) }
                }
                .ignoresSafeArea()
            } else {
                TabView(selection: $page) {
                    ForEach(0..<count, id: \.self) { index in
                        ComicPage(book: book, index: index, fit: .page, onTap: toggle)
                            .tag(index)
                            .environment(\.layoutDirection, .leftToRight)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .environment(\.layoutDirection, mode == "rtl" ? .rightToLeft : .leftToRight)
                .ignoresSafeArea()
            }

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Button { dismiss() } label: {
                        ThemeIcon(symbol: Icon.back, size: 24)
                            .frame(width: 44, height: 44)
                            .background(Theme.surface2, in: Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("返回")
                    VStack(alignment: .leading, spacing: 4) {
                        Text(book.title).font(Theme.sans(18 * uiScale, weight: .medium)).lineLimit(2)
                        Text("图像阅读 · \(modeLabel)")
                            .font(Theme.sans(12 * uiScale)).foregroundStyle(Theme.ink3)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // 与文字阅读页一致：书签放顶栏，底栏只放打开面板与切换方式
                    Button {
                        Haptics.selection()
                        model.bookmark(book.id, chapter: page, position: 0, excerpt: "第 \(page + 1) 页")
                    } label: {
                        ThemeIcon(symbol: Icon.bookmark(marked), size: 24)
                            .foregroundStyle(marked ? Theme.accent : Theme.ink)
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                            .id(marked)
                            .transition(marked ? .movingParts.pop(Theme.accent) : .identity)
                            .animation(.easeOut(duration: 0.25), value: marked)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(marked ? "移除本页书签" : "为本页添加书签")
                    .accessibilityAddTraits(marked ? .isSelected : [])
                    .accessibilityIdentifier("comic.bookmark")
                    Menu {
                        Button { onlyBookmarks = true; showingPages = true } label: { Label("查看书签", systemImage: Icon.bookmark(false)) }
                        Button { showingHelp = true } label: { Label("阅读操作说明", systemImage: Icon.help) }
                    } label: {
                        ThemeIcon(symbol: Icon.more, size: 24).frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                    .accessibilityLabel("更多漫画操作")
                }
                .padding(12)
                .glassSurface(in: Rectangle())
                Spacer()
                VStack(spacing: 4) {
                    HStack {
                        Text("页码进度")
                        Spacer()
                        Text("\(Int(scrubbing ?? Double(page)) + 1) / \(count) 页").monospacedDigit()
                    }
                    .font(Theme.sans(12 * uiScale)).foregroundStyle(Theme.ink3)
                    .padding(.horizontal, 8).padding(.top, 10)
                    HStack(spacing: 10) {
                        pageStep(-1, "上一页", Icon.back)
                        if count > 1 {
                            Slider(value: Binding(get: { scrubbing ?? Double(page) }, set: { scrubbing = $0 }), in: 0...Double(count - 1), step: 1) { editing in
                                if !editing, let value = scrubbing { goToPage(Int(value)); scrubbing = nil }
                            }
                            .tint(Theme.accent)
                            .environment(\.layoutDirection, mode == "rtl" ? .rightToLeft : .leftToRight)
                            .accessibilityLabel("页码").accessibilityValue("第 \(page + 1) 页，共 \(count) 页")
                        } else { Spacer() }
                        pageStep(1, "下一页", Icon.disclosure)
                    }
                    Rectangle().fill(Theme.line.opacity(0.5)).frame(height: 0.5)
                    HStack(spacing: 6) {
                        Button { onlyBookmarks = false; showingPages = true } label: { comicAction(Icon.grid, "页面目录") }
                            .accessibilityIdentifier("comic.contents")
                        Menu {
                            Picker("阅读方向", selection: $mode) {
                                Label("从左往右", systemImage: Icon.nextDirection).tag("ltr")
                                Label("从右往左（日漫）", systemImage: Icon.prevDirection).tag("rtl")
                                Label("上下滚动（条漫）", systemImage: Icon.downDirection).tag("vertical")
                            }
                        } label: { comicAction(Icon.readingDirection, modeLabel) }
                        .accessibilityLabel("翻页方式，当前\(modeLabel)")
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12).padding(.bottom, 8)
                .glassSurface(in: Rectangle())
            }
            .frame(maxWidth: 760)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .foregroundStyle(Theme.ink)
            .opacity(chrome ? 1 : 0)
            .allowsHitTesting(chrome)
            .accessibilityHidden(!chrome)
        }
        .toolbar(.hidden, for: .navigationBar)
        .statusBarHidden(!chrome)
        .animation(.snappy(duration: 0.22), value: chrome)
        .sheet(isPresented: $showingPages) { pageDirectory }
        .alert("漫画阅读操作", isPresented: $showingHelp) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(mode == "vertical" ? "上下滑动阅读，轻点画面显示或收起工具。底部页码条和页面目录都可以跳到指定页。" : "左右滑动翻页，轻点画面显示或收起工具。双击或双指可以放大画面，底部可切换日漫方向。")
        }
        .accessibilityAction(named: "显示阅读工具") { chrome = true }
        .onAppear {
            let saved = model.entries.first { $0.id == book.id }?.progress.chapter ?? 0
            page = min(max(0, saved), max(0, count - 1))
        }
        .onChange(of: page) { _, value in model.saveProgress(book.id, chapter: value, position: 0) }
        .onChange(of: mode) { _, value in ComicPreset.save(value, for: book.id) }
        .task { while !Task.isCancelled { do { try await Task.sleep(for: .seconds(5)) } catch { return }; if scenePhase == .active { model.recordReading(seconds: 5, bookID: book.id, title: book.title) } } }
    }
    private func comicAction(_ icon: String, _ title: String, selected: Bool = false) -> some View {
        VStack(spacing: 6) {
            ThemeIcon(symbol: icon, size: 24)
            Text(L(title)).font(Theme.sans(12 * uiScale)).fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(selected ? Theme.accent : Theme.ink)
        .frame(maxWidth: .infinity, minHeight: 58)
        .background(selected ? Theme.accentSoft : .clear, in: Rectangle())
        .contentShape(Rectangle())
    }
    private func pageStep(_ delta: Int, _ title: String, _ icon: String) -> some View {
        let enabled = (0..<count).contains(page + delta)
        return Button { goToPage(page + delta) } label: {
            ThemeIcon(symbol: icon, size: 20)
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(!enabled).opacity(enabled ? 1 : 0.3).accessibilityLabel(title)
    }
    private func goToPage(_ target: Int) {
        guard count > 0 else { return }
        page = min(max(0, target), count - 1)
        pageJumpRevision += 1
        Haptics.selection()
    }
    private var pageDirectory: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    Picker("页面类型", selection: $onlyBookmarks) {
                        Text("全部页面").tag(false)
                        Text("书签 \(bookmarks.count)").tag(true)
                    }
                    .pickerStyle(.segmented).listRowBackground(Color.clear)
                    if onlyBookmarks && directoryPages.isEmpty {
                        Text("还没有书签。阅读时轻点顶部的书签图标，保存当前页。")
                            .font(.subheadline).foregroundStyle(Theme.ink2).listRowBackground(Color.clear)
                    }
                    ForEach(directoryPages, id: \.self) { index in
                        Button { goToPage(index); showingPages = false } label: {
                            HStack(spacing: 14) {
                                Text(String(format: "%02d", index + 1)).font(.system(size: 13, weight: .medium).monospacedDigit())
                                    .foregroundStyle(index == page ? Theme.accent : Theme.ink3).frame(width: 36)
                                Text("第 \(index + 1) 页").font(.system(size: 15)).foregroundStyle(Theme.ink)
                                Spacer()
                                if bookmarks.contains(where: { $0.chapter == index }) { Image(systemName: Icon.bookmark(true)).font(.system(size: 13)).foregroundStyle(Theme.accent) }
                                if index == page { Text("在读").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.accent) }
                            }
                            .frame(minHeight: 48).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).listRowBackground(index == page ? Theme.accentSoft : Theme.surface).id(index)
                    }
                }
                .scrollContentBackground(.hidden).background(Theme.bg)
                .navigationTitle("页面目录").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showingPages = false } } }
                .onAppear { proxy.scrollTo(page, anchor: .center) }
            }
        }
        .tint(Theme.accent).presentationDetents([.medium, .large])
    }
    private var modeLabel: String {
        switch mode {
        case "rtl": "从右向左"
        case "vertical": "上下滚动"
        default: "从左向右"
        }
    }
    private func toggle() { chrome.toggle() }
}

/// 一页漫画：后台按屏幕尺寸降采样解码，避免几十张原图同时占满内存；双击放大 / 还原。
private struct ComicPage: View {
    enum Fit { case page, width }
    private static let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 12
        return c
    }()
    let book: Book
    let index: Int
    let fit: Fit
    var onTap: (() -> Void)? = nil
    @State private var image: UIImage?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Group {
            if let image {
                if fit == .width {
                    Image(uiImage: image).resizable().scaledToFit()
                        .transition(reduceMotion ? .opacity : .movingParts.blur(radius: 10))
                } else {
                    ZoomableComicImage(image: image, onTap: onTap)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(reduceMotion ? .opacity : .movingParts.blur(radius: 10))
                }
            } else {
                ProgressView().tint(Theme.accent).frame(maxWidth: .infinity, minHeight: fit == .width ? 400 : nil, maxHeight: fit == .width ? nil : .infinity)
            }
        }
        .animation(.easeOut(duration: 0.3), value: image != nil)
        .accessibilityLabel("第 \(index + 1) 页")
        .task(id: index) {
            guard image == nil else { return }
            let cacheKey = "\(book.id)-\(index)" as NSString
            if let cached = Self.cache.object(forKey: cacheKey) {
                image = cached
                return
            }
            let ref = book.chapters.indices.contains(index) ? book.chapters[index].fields["nativeImages"]?.array?.first?.string : nil
            let box = BookBox(book: book)
            let maxPixel = max(UIScreen.main.bounds.width, UIScreen.main.bounds.height) * UIScreen.main.scale
            let decoded = await Task.detached(priority: .userInitiated) { () -> UIImage? in
                guard let ref, let data = box.book.resourceData(ref), let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
                let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: maxPixel]
                return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary).map { UIImage(cgImage: $0) }
            }.value
            if let decoded {
                Self.cache.setObject(decoded, forKey: cacheKey)
                image = decoded
            }
        }
    }
    private struct BookBox: @unchecked Sendable { let book: Book }
}

/// 原生 UIScrollView 缩放容器：支持双指缩放、放大后自由拖拽平移、双击按触点放大/还原、单击显隐工具栏。
private struct ZoomableComicImage: UIViewRepresentable {
    let image: UIImage
    var onTap: (() -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(onTap: onTap) }

    func makeUIView(context: Context) -> ComicScrollView {
        let scroll = ComicScrollView()
        scroll.delegate = context.coordinator
        scroll.minimumZoomScale = 1
        scroll.maximumZoomScale = 4
        scroll.bouncesZoom = true
        scroll.showsHorizontalScrollIndicator = false
        scroll.showsVerticalScrollIndicator = false
        scroll.backgroundColor = .clear
        scroll.contentInsetAdjustmentBehavior = .never

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        scroll.addSubview(imageView)
        scroll.imageView = imageView
        context.coordinator.scrollView = scroll
        context.coordinator.imageView = imageView

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scroll.addGestureRecognizer(doubleTap)

        let singleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSingleTap))
        singleTap.numberOfTapsRequired = 1
        singleTap.require(toFail: doubleTap)
        scroll.addGestureRecognizer(singleTap)

        return scroll
    }

    func updateUIView(_ scroll: ComicScrollView, context: Context) {
        context.coordinator.onTap = onTap
        if scroll.imageView?.image !== image {
            scroll.zoomScale = 1
            scroll.imageView?.image = image
            scroll.setNeedsLayout()
        }
    }

    final class ComicScrollView: UIScrollView {
        weak var imageView: UIImageView?
        private var lastSize: CGSize = .zero
        override func layoutSubviews() {
            super.layoutSubviews()
            guard bounds.size != .zero, let imageView else { return }
            if lastSize != bounds.size {
                lastSize = bounds.size
                zoomScale = 1
                imageView.frame = bounds
                contentSize = bounds.size
            }
            let offsetX = max((bounds.width - contentSize.width) * 0.5, 0)
            let offsetY = max((bounds.height - contentSize.height) * 0.5, 0)
            imageView.center = CGPoint(x: contentSize.width * 0.5 + offsetX, y: contentSize.height * 0.5 + offsetY)
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var onTap: (() -> Void)?
        weak var scrollView: ComicScrollView?
        weak var imageView: UIImageView?
        init(onTap: (() -> Void)?) { self.onTap = onTap }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            scrollView.setNeedsLayout()
            scrollView.layoutIfNeeded()
        }

        @objc func handleSingleTap() { onTap?() }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scroll = scrollView, let imageView else { return }
            if scroll.zoomScale > 1.01 {
                scroll.setZoomScale(1, animated: true)
            } else {
                let point = gesture.location(in: imageView)
                let scale: CGFloat = 2.2
                let size = CGSize(width: scroll.bounds.width / scale, height: scroll.bounds.height / scale)
                let origin = CGPoint(x: point.x - size.width * 0.5, y: point.y - size.height * 0.5)
                scroll.zoom(to: CGRect(origin: origin, size: size), animated: true)
            }
        }
    }
}


/// 漫画阅读方式：全局默认（新加入的漫画使用）+ 每部漫画自己的选择。
enum ComicPreset {
    static let defaultKey = "comic.mode"
    static let modes: [(value: String, label: String)] = [("ltr", "左右翻页（从左到右）"), ("rtl", "左右翻页（日漫，从右到左）"), ("vertical", "上下滚动（条漫）")]
    static func key(_ id: String) -> String { "comic.mode." + id }
    static var defaultMode: String { UserDefaults.standard.string(forKey: defaultKey) ?? "ltr" }
    static func mode(for id: String) -> String { UserDefaults.standard.string(forKey: key(id)) ?? defaultMode }
    static func save(_ mode: String, for id: String) { UserDefaults.standard.set(mode, forKey: key(id)) }
}
