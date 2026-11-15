import SwiftUI
import UIKit
import ReadiumShared
import ReadiumNavigator

/// UIKit 容器允许报告初始化错误。只在字体文件清单改变时重建 child，并保留 currentLocation。
struct EPUBNavigatorHost: UIViewControllerRepresentable {
    let publication: Publication
    let initialLocation: ReadiumShared.Locator
    let preferences: EPUBPreferences
    let fonts: [ReadiumFontProvider.FontFile]
    let request: Request?
    let onLocation: (Int?, ReadiumShared.Locator, UUID?) -> Void
    let onTap: () -> Void
    let onError: (String) -> Void

    struct Request {
        let id = UUID()
        let locator: ReadiumShared.Locator?
        let link: Link?
        init(locator: ReadiumShared.Locator) { self.locator = locator; link = nil }
        init(link: Link) { self.link = link; locator = nil }
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
        coordinator.navigateIfNeeded()
    }
    static func dismantleUIViewController(_ controller: Container, coordinator: Coordinator) {
        coordinator.navigationTask?.cancel()
        coordinator.navigator = nil
        controller.navigator?.delegate = nil
    }
    final class Container: UIViewController {
        var navigator: EPUBNavigatorViewController?
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
        weak var navigator: EPUBNavigatorViewController?
        var navigatorReady = false
        var deferredLocation: ReadiumShared.Locator?
        init(_ parent: EPUBNavigatorHost) { self.parent = parent }
        func install(in controller: Container, location: ReadiumShared.Locator) {
            if navigationTask != nil { requestID = nil }
            navigationTask?.cancel(); navigationTask = nil
            navigatorReady = false; deferredLocation = nil
            do {
                let next = try EPUBNavigatorViewController(
                    publication: parent.publication, initialLocation: location,
                    config: .init(preferences: parent.preferences,
                                  fontFamilyDeclarations: ReadiumFontProvider.declarations(files: parent.fonts),
                                  readiumCSSRSProperties: .init(pageGutter: CSSPxLength(ReadiumPreferencesBridge.basePageGutter)))
                )
                next.delegate = self
                controller.navigator?.delegate = nil
                navigator = next
                controller.set(next)
                fonts = parent.fonts
                preferences = parent.preferences
            } catch {
                // SwiftUI 状态不能在 make/updateUIViewController 的栈内写入。
                Task { @MainActor [weak self] in self?.parent.onError(error.localizedDescription) }
            }
        }
        func navigateIfNeeded() {
            // go() 在 Navigator 初始化前会返回 false；收到首个位置回调后再发请求。
            guard navigatorReady, let navigator, let request = parent.request, requestID != request.id else { return }
            requestID = request.id
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
        func reportLocation(_ locator: ReadiumShared.Locator, confirmedRequest: UUID? = nil) {
            let resource = parent.publication.readingOrder.firstIndex {
                PublicationMap.normalized($0.href) == PublicationMap.normalized(locator.href.string)
            }
            parent.onLocation(resource, locator, confirmedRequest)
        }
        func navigator(_ navigator: Navigator, locationDidChange locator: ReadiumShared.Locator) {
            guard self.navigator === navigator else { return }
            navigatorReady = true
            navigateIfNeeded()
            if navigationTask != nil { deferredLocation = locator; return }
            reportLocation(locator)
        }
        func navigator(_ navigator: VisualNavigator, didTapAt point: CGPoint) { parent.onTap() }
        func navigator(_ navigator: Navigator, presentExternalURL url: URL) {
            UIApplication.shared.open(url)
        }
        func navigator(_ navigator: VisualNavigator, shouldNavigateToLink link: Link) -> Bool {
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
