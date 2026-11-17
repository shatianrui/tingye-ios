import SwiftUI
import UIKit
import ReadiumShared
import ReadiumNavigator

/// UIKit 容器允许报告初始化错误。只在字体文件清单改变时重建 child，并保留 currentLocation。
struct EPUBNavigatorHost: UIViewControllerRepresentable {
    let publication: Publication
    let initialLocation: ReadiumShared.Locator
    let preferences: EPUBPreferences
    let palette: ReaderPaper.Palette
    let fonts: [ReadiumFontProvider.FontFile]
    let request: Request?
    var decorations: [Decoration] = []
    var speechDecorations: [Decoration] = []
    var searchDecorations: [Decoration] = []
    var onSelection: (ReadiumShared.Locator, ReadiumAnnotations.SelectionAction) -> Void = { _, _ in }
    var onDecoration: (String) -> Void = { _ in }
    let onLocation: (Int?, ReadiumShared.Locator, UUID?) -> Void
    /// Last visible character's exclusive DOM point, plus the resource href it belongs to.
    var onVisibleEnd: (JSONValue, String) -> Void = { _, _ in }
    let onTap: () -> Void
    let onError: (String) -> Void

    struct Request {
        let id = UUID()
        let locator: ReadiumShared.Locator?
        let link: ReadiumShared.Link?
        init(locator: ReadiumShared.Locator) { self.locator = locator; link = nil }
        init(link: ReadiumShared.Link) { self.link = link; locator = nil }
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIViewController(context: Context) -> Container {
        let controller = Container()
        context.coordinator.install(in: controller, location: initialLocation)
        return controller
    }
    func updateUIViewController(_ controller: Container, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        if coordinator.fonts != fonts {
            coordinator.install(in: controller, location: controller.navigator?.currentLocation ?? initialLocation)
        } else if coordinator.preferences != preferences {
            coordinator.preferences = preferences
            // Toolkit 在重新排版时持有当前 Locator。不能在此重新 go(initialLocation)。
            controller.navigator?.submitPreferences(preferences)
        }
        coordinator.applyDecorations()
        coordinator.applyAppearance()
        coordinator.navigateIfNeeded()
    }
    static func dismantleUIViewController(_ controller: Container, coordinator: Coordinator) {
        coordinator.navigationTask?.cancel()
        coordinator.reportTask?.cancel()
        coordinator.navigator = nil
        controller.navigator?.delegate = nil
    }
    final class Container: UIViewController {
        var navigator: EPUBNavigatorViewController?
        var onSelection: ((ReadiumShared.Locator, ReadiumAnnotations.SelectionAction) -> Void)?
        @objc func highlightSelection() { capture(.highlight) }
        @objc func bookmarkSelection() { capture(.bookmark) }
        @objc func noteSelection() { capture(.note) }
        private func capture(_ action: ReadiumAnnotations.SelectionAction) {
            guard let navigator, let selection = navigator.currentSelection else { return }
            Task { @MainActor [weak self, weak navigator] in
                guard let navigator, let self else { return }
                var locator = selection.locator
                // Selection inherits the page locator. Only a freshly captured range belongs to the selection.
                if var raw = StoredLocator.json(locator)?.object {
                    var locations = raw["locations"]?.object ?? [:]
                    locations.removeValue(forKey: "domRange"); locations.removeValue(forKey: "tingyeRange")
                    raw["locations"] = .object(locations)
                    locator = StoredLocator.readium(.object(raw)) ?? locator
                }
                if case .success(let value) = await navigator.evaluateJavaScript(ReadiumAnnotations.selectionRangeScript),
                   JSONSerialization.isValidJSONObject(value),
                   let data = try? JSONSerialization.data(withJSONObject: value),
                   let span = try? JSONDecoder().decode(JSONValue.self, from: data),
                   var raw = StoredLocator.json(locator)?.object {
                    var locations = raw["locations"]?.object ?? [:]; locations["domRange"] = span
                    raw["locations"] = .object(locations)
                    locator = StoredLocator.readium(.object(raw)) ?? locator
                }
                guard self.navigator === navigator else { return }
                self.onSelection?(locator, action)
                navigator.clearSelection()
            }
        }
        func set(_ next: EPUBNavigatorViewController) {
            navigator?.willMove(toParent: nil)
            navigator?.view.removeFromSuperview()
            navigator?.removeFromParent()
            navigator = next
            addChild(next)
            view.addSubview(next.view)
            next.view.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                next.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                next.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                next.view.topAnchor.constraint(equalTo: view.topAnchor),
                next.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
            next.didMove(toParent: self)
        }
    }
    @MainActor final class Coordinator: NSObject, EPUBNavigatorDelegate {
        var parent: EPUBNavigatorHost
        var fonts: [ReadiumFontProvider.FontFile] = []
        var preferences: EPUBPreferences?
        var requestID: UUID?
        var navigationTask: Task<Void, Never>?
        var reportTask: Task<Void, Never>?
        weak var navigator: EPUBNavigatorViewController?
        var navigatorReady = false
        var deferredLocation: ReadiumShared.Locator?
        var appliedDecorations: [Decoration]?
        var appliedSpeech: [Decoration]?
        var appliedSearch: [Decoration]?
        init(_ parent: EPUBNavigatorHost) { self.parent = parent }
        func install(in controller: Container, location: ReadiumShared.Locator) {
            if navigationTask != nil { requestID = nil }
            navigationTask?.cancel(); navigationTask = nil
            navigatorReady = false; deferredLocation = nil; reportTask?.cancel()
            do {
                let next = try EPUBNavigatorViewController(
                    publication: parent.publication, initialLocation: location,
                    config: .init(preferences: parent.preferences,
                                  editingActions: EditingAction.defaultActions + [
                                    EditingAction(title: "划线", action: #selector(Container.highlightSelection)),
                                    EditingAction(title: "书签", action: #selector(Container.bookmarkSelection)),
                                    EditingAction(title: "写笔记", action: #selector(Container.noteSelection))
                                  ], decorationTemplates: ReadiumAnnotations.templates(),
                                  fontFamilyDeclarations: ReadiumFontProvider.declarations(files: parent.fonts),
                                  readiumCSSRSProperties: .init(pageGutter: CSSPxLength(ReadiumPreferencesBridge.basePageGutter)))
                )
                next.delegate = self
                controller.navigator?.delegate = nil
                navigator = next
                controller.set(next)
                controller.onSelection = { [weak self] locator, action in self?.parent.onSelection(locator, action) }
                next.observeDecorationInteractions(inGroup: ReadiumAnnotations.userGroup) { [weak self] event in
                    self?.parent.onDecoration(event.decoration.id)
                }
                appliedDecorations = nil; appliedSpeech = nil; appliedSearch = nil
                applyDecorations()
                fonts = parent.fonts
                preferences = parent.preferences
            } catch {
                // SwiftUI 状态不能在 make/updateUIViewController 的栈内写入。
                Task { @MainActor [weak self] in self?.parent.onError(error.localizedDescription) }
            }
        }
        func applyDecorations() {
            guard let navigator else { return }
            if appliedDecorations != parent.decorations {
                navigator.apply(decorations: parent.decorations, in: ReadiumAnnotations.userGroup)
                appliedDecorations = parent.decorations
            }
            if appliedSpeech != parent.speechDecorations {
                navigator.apply(decorations: parent.speechDecorations, in: ReadiumAnnotations.speechGroup)
                appliedSpeech = parent.speechDecorations
            }
            if appliedSearch != parent.searchDecorations {
                navigator.apply(decorations: parent.searchDecorations, in: ReadiumAnnotations.searchGroup)
                appliedSearch = parent.searchDecorations
            }
        }
        func navigateIfNeeded() {
            // go() 在 Navigator 初始化前会返回 false；收到首个位置回调后再发请求。
            guard navigatorReady, let navigator, let request = parent.request, requestID != request.id else { return }
            requestID = request.id
            reportTask?.cancel()
            navigationTask?.cancel()
            deferredLocation = nil
            navigationTask = Task { @MainActor [weak self, weak navigator] in
                guard let navigator else { return }
                let moved: Bool
                if let locator = request.locator { moved = await navigator.go(to: locator, options: .none) }
                else if let link = request.link { moved = await navigator.go(to: link, options: .none) }
                else { moved = false }
                guard !Task.isCancelled, let self, self.navigator === navigator else { return }
                self.navigationTask = nil
                if moved {
                    // 同一 href 内跳转也必须等 go 成功才能消费；不会被旧页回调抢先确认。
                    if let locator = request.locator { self.reportLocation(locator, confirmedRequest: request.id) }
                    else if let locator = self.deferredLocation { self.reportLocation(locator, confirmedRequest: request.id) }
                } else {
                    self.parent.onError(String(localized: "无法跳到所选章节，请重试或选择目录中的其他章节。"))
                }
                self.deferredLocation = nil
            }
        }
        func deliver(_ locator: ReadiumShared.Locator, confirmedRequest: UUID?) {
            let resource = parent.publication.readingOrder.firstIndex {
                PublicationMap.normalized($0.href) == PublicationMap.normalized(locator.href.string)
            }
            parent.onLocation(resource, locator, confirmedRequest)
        }
        func reportLocation(_ locator: ReadiumShared.Locator, confirmedRequest: UUID? = nil) {
            // 目录跳章必须先把目标位置交出去。可见范围脚本要等新页排完，期间旧页回调会取消这次任务，
            // 章节标题就一直停在跳转前。
            if confirmedRequest != nil { deliver(locator, confirmedRequest: confirmedRequest) }
            reportTask?.cancel()
            guard let navigator else { return }
            reportTask = Task { @MainActor [weak self, weak navigator] in
                guard let self, let navigator else { return }
                var precise = locator
                if confirmedRequest == nil, let visible = await navigator.firstVisibleElementLocator(),
                   PublicationMap.normalized(visible.href.string) == PublicationMap.normalized(locator.href.string) {
                    precise = visible.copy(locations: { locations in
                        locations.progression = locator.locations.progression
                        locations.totalProgression = locator.locations.totalProgression
                        locations.position = locator.locations.position
                    })
                }
                if case .success(let value) = await navigator.evaluateJavaScript(ReadiumAnnotations.visibleRangeScript),
                   JSONSerialization.isValidJSONObject(value),
                   let data = try? JSONSerialization.data(withJSONObject: value),
                   let span = try? JSONDecoder().decode(JSONValue.self, from: data) {
                    guard !Task.isCancelled, self.navigator === navigator else { return }
                    if let pageEnd = span.object?["pageEnd"] {
                        let href = navigator.currentLocation?.href.string ?? precise.href.string
                        self.parent.onVisibleEnd(pageEnd, href)
                    }
                    if confirmedRequest == nil, var raw = StoredLocator.json(precise)?.object {
                        var stored = span
                        if var object = stored.object { object.removeValue(forKey: "pageEnd"); stored = .object(object) }
                        var locations = raw["locations"]?.object ?? [:]; locations["domRange"] = stored
                        raw["locations"] = .object(locations)
                        precise = StoredLocator.readium(.object(raw)) ?? precise
                    }
                }
                guard confirmedRequest == nil, !Task.isCancelled, self.navigator === navigator else { return }
                self.deliver(precise, confirmedRequest: nil)
            }
        }
        func navigator(_ navigator: Navigator, locationDidChange locator: ReadiumShared.Locator) {
            guard self.navigator === navigator else { return }
            navigatorReady = true
            applyAppearance()
            navigateIfNeeded()
            if navigationTask != nil { deferredLocation = locator; return }
            reportLocation(locator)
        }
        /// 只注入颜色，不插入正文节点、不改变文字或排版尺寸。
        func applyAppearance() {
            guard navigatorReady, let navigator, parent.publication.metadata.layout != .fixed else { return }
            let palette = parent.palette
            let css = String(format: "a{color:#%06X!important}::selection{background:#%06X!important;color:#%06X!important}",
                             palette.accent, palette.highlight, palette.foreground)
            guard let data = try? JSONEncoder().encode(css), let literal = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor [weak self, weak navigator] in
                guard let self, let navigator, self.navigator === navigator else { return }
                _ = await navigator.evaluateJavaScript("""
                (() => { let style = document.getElementById('tingye-reader-appearance');
                  if (!style) { style = document.createElement('style'); style.id = 'tingye-reader-appearance'; document.head.appendChild(style); }
                  if (style.textContent !== \(literal)) style.textContent = \(literal);
                })();
                """)
            }
        }
        func navigator(_ navigator: VisualNavigator, didTapAt point: CGPoint) { parent.onTap() }
        func navigator(_ navigator: Navigator, presentExternalURL url: URL) {
            UIApplication.shared.open(url)
        }
        func navigator(_ navigator: VisualNavigator, shouldNavigateToLink link: ReadiumShared.Link) -> Bool {
            if let url = URL(string: link.href), let scheme = url.scheme {
                if ["http", "https", "mailto", "tel"].contains(scheme.lowercased()) { UIApplication.shared.open(url) }
                return false
            }
            // 内部资源和 fragment 由 Navigator 的 go(to: link) 处理，保留脚注/目录锚点。
            return true
        }
        func navigator(_ navigator: Navigator, presentError error: NavigatorError) {
            guard self.navigator === navigator else { return }
            parent.onError("阅读操作未完成：\(error)")
        }
        func navigator(_ navigator: Navigator, didFailToLoadResourceAt href: RelativeURL, withError error: ReadError) {
            guard self.navigator === navigator else { return }
            parent.onError("EPUB 章节加载失败：\(href.string)\n\(error)")
        }
    }
}
