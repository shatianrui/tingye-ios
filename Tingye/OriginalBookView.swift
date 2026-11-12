import SwiftUI
import WebKit
import Combine

/// Render imported book documents with Apple's native WebKit, with book scripts and network access disabled.
enum OriginalDocument {
    static func sanitized(_ source: String) -> String {
        var result = source.replacingOccurrences(of: #"(?is)<a\b[^>]*class\s*=\s*["'][^"']*restored-source-link[^"']*"[^>]*>.*?</a\s*>"#, with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: #"(?is)<(script|head|iframe|object|form|noscript)\b[^>]*>.*?</\1\s*>|<!--.*?-->"#, with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: #"(?is)<![^>]*>|</?html\b[^>]*>|<(meta|link|base|embed|input|button)\b[^>]*>"#, with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: #"(?i)\son[a-z]+\s*=\s*(?:"[^"]*"|'[^']*'|[^\s>]+)"#, with: "", options: .regularExpression)
        return result
    }
    /// 由正文纯文本生成原书图文 HTML：与文本模式同源，两种模式下的句级高亮与进度天然一致。
    static func fromText(_ text: String) -> String {
        let escaped = text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
        return escaped.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { "<p>\($0)</p>" }
            .joined()
    }
    /// 书内图片保留 `tingye-resource:` 引用，由 `ResourceSchemeHandler` 按需提供：
    /// 不再把整本书的 base64 逐个替换进每章 HTML（多图书籍每次翻章要做几百次全文替换、生成十几 MB 的页面）。
    /// EPUB 是 XHTML，常见 `<span id="x"/>` 这类自闭合写法；按 HTML 解析时它们不会闭合，
    /// 会把后面的正文与插图层层包进去（数百层嵌套），导致插图压住文字、排版变慢。补全为成对标签。
    static func closingSelfClosedTags(_ html: String) -> String {
        html.replacingOccurrences(of: #"(?i)<(?!(?:area|base|br|col|embed|hr|img|input|link|meta|param|source|track|wbr)[\s/>])([a-z][a-z0-9:-]*)(\s[^<>]*?)?\s*/>"#, with: "<$1$2></$1>", options: .regularExpression)
    }
    /// `paper` 是阅读页纸色（WebView 透明，露出纸色）：页面脚本据此修正书籍样式写死的低对比文字颜色。
    static func html(_ source: String, css: String, color: String = "#17233A", background: String = "#F6F0E4", paper: String = "#F6F0E4", preferences: ReaderPreferences = .init(), accent: String = "#315BEE") -> String {
        var html = source.replacingOccurrences(of: #"(?is)<(script|iframe|object|embed|form|base)\b[^>]*>.*?</\1\s*>|<(script|iframe|object|embed|form|base|meta)\b[^>]*\/?>"#, with: "", options: .regularExpression)
        html = html.replacingOccurrences(of: #"(?i)\son[a-z]+\s*=\s*(?:"[^"]*"|'[^']*'|[^\s>]+)"#, with: "", options: .regularExpression)
        html = closingSelfClosedTags(html)
        let styles = css.replacingOccurrences(of: "</style", with: "", options: .caseInsensitive)
        let fontFamily: String = {
            if preferences.font == "system" { return "-apple-system, BlinkMacSystemFont, \"PingFang SC\", sans-serif" }
            if preferences.font == "kai" { return "\"LXGWWenKaiLite-Regular\", \"Kaiti SC\", serif" }
            if preferences.font.hasPrefix("custom:") {
                let name = String(preferences.font.dropFirst(7)).replacingOccurrences(of: "\"", with: "").replacingOccurrences(of: "\\", with: "")
                return "\"\(name)\", \"NotoSerifCJKsc-Regular\", serif"
            }
            if let registered = ReaderPreferences.bundledFonts[preferences.font] {
                let fallback = ["hansans", "xixihei"].contains(preferences.font) ? "sans-serif" : "serif"
                return "\"\(registered)\", \(fallback)"
            }
            return "\"NotoSerifCJKsc-Regular\", \"Songti SC\", serif"
        }()
        let fontSize = Int(preferences.fontSize.rounded())
        let lineHeight = String(format: "%.2f", (preferences.fontSize + preferences.lineSpacing * 1.35) / max(12, preferences.fontSize))
        let letterSpacing = preferences.letterSpacing != 0 ? "letter-spacing:\(preferences.letterSpacing)px;" : ""
        let textAlign = preferences.justified ? "text-align:justify;" : ""
        let paragraphMargin = Int(preferences.paragraphSpacing.rounded())
        let textIndent = preferences.indent ? "2em" : "0"
        // 左右分页：CSS 多栏，每栏恰好一屏宽、栏间距为 0，栏距 = 100vw，横向滚动即翻页。
        // 多栏会把栏宽撑满容器，若再加栏间距，每页就比屏宽多出间距，越往后翻错位越大；
        // 书籍自带 CSS（含合并到 body 上的 class）也可能改 body/容器的边距与宽度，故用 !important 锁定分页骨架。
        return """
        <!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data: tingye-resource:; style-src 'unsafe-inline'; font-src data: tingye-resource:; script-src 'none'; connect-src 'none'; frame-src 'none'; base-uri 'none'; form-action 'none'"><style>html,body{height:100%!important;width:auto!important;max-width:none!important;margin:0!important;padding:0!important;border:0!important;columns:auto!important}body{color:\(color);background:\(background);font:\(fontSize)px/\(lineHeight) \(fontFamily);\(letterSpacing)\(textAlign)overflow-wrap:break-word}img,svg,table,video{max-width:100%;height:auto}pre{white-space:pre-wrap}table{border-collapse:collapse}td,th{padding:6px}a{color:\(accent);text-decoration-thickness:1px;text-underline-offset:3px}::selection{background:\(accent);color:\(background == "transparent" ? paper : background)}a.restored-source-link{display:none} \(styles) #ty-reader-book{box-sizing:border-box!important;width:100vw!important;max-width:none!important;height:100%!important;margin:0!important;padding:20px 0!important;border:0!important;column-width:100vw!important;column-count:auto!important;column-gap:0!important;column-fill:auto!important;font:\(fontSize)px/\(lineHeight) \(fontFamily)!important;\(letterSpacing)\(textAlign)} #ty-reader-book p{margin-top:0!important;margin-bottom:\(paragraphMargin)px!important;text-indent:\(textIndent)!important;line-height:\(lineHeight)!important} #ty-reader-book *{overflow:visible!important;columns:auto!important} #ty-reader-book img,#ty-reader-book svg,#ty-reader-book video{height:auto!important;max-width:100%!important;max-height:calc(100vh - 48px)!important;object-fit:contain} #ty-reader-book figure{break-inside:avoid} #ty-reader-book figure img{display:block;margin-left:auto;margin-right:auto} #ty-reader-book pre,#ty-reader-book pre *,#ty-reader-book code{white-space:pre-wrap!important;overflow-wrap:anywhere!important}</style></head><body><article id="ty-reader-book" data-ty-paper="\(paper)" data-ty-fg="\(color)">\(html)</article></body></html>
        """
    }
}
/// Only this app-owned script executes, in an isolated content world. Publication scripts stay disabled.
enum OriginalSpeechHighlight {
    /// `spoken`：当前读到的字在本句中的位置（只数非空白字符的 UTF-16 单位），与纯文本模式按字跟随一致。
    /// 每换一句都要重建高亮：整章切句的结果缓存起来，免得在主线程上反复切整章（短段落换句频繁时最明显）。
    private final class SplitMemo: @unchecked Sendable {
        private let lock = NSLock()
        private var text = ""
        private var sentences: [Sentence] = []
        func sentences(_ value: String) -> [Sentence] {
            lock.lock(); defer { lock.unlock() }
            if value != text || (sentences.isEmpty && !value.isEmpty) { text = value; sentences = Sentence.split(value) }
            return sentences
        }
    }
    private static let memo = SplitMemo()
    static func script(text: String, range: NSRange?, follow: Bool, color: String, spoken: Int? = nil) -> String {
        let sentences = memo.sentences(text)
        let target = range.flatMap { wanted in sentences.firstIndex { NSIntersectionRange($0.range, wanted).length > 0 } }
        let payload: [String: JSONValue] = [
            "sentences": .array(sentences.map { .string($0.text) }),
            "target": .number(Double(target ?? -1)), "follow": .bool(follow), "color": .string(color),
            "spoken": .number(Double(spoken ?? 0))
        ]
        let json = String(data: try! Integrity.encoder().encode(payload), encoding: .utf8)!
        return "(() => { const input = " + json + "; return " + #"""
        (() => {
            const root = document.getElementById('ty-reader-book');
            if (!root) return 0;
            // 负的左右外边距（如插图的 margin-left:-40px）会把内容伸出本栏、露到相邻页边缘：每次载入后归零一次。
            if (!root.dataset.tyClamped) {
                root.dataset.tyClamped = 'true';
                root.querySelectorAll('*').forEach(el => {
                    const style = getComputedStyle(el);
                    if (parseFloat(style.marginLeft) < 0) el.style.setProperty('margin-left', '0', 'important');
                    if (parseFloat(style.marginRight) < 0) el.style.setProperty('margin-right', '0', 'important');
                });
            }
            // 书籍样式常把文字写死成黑色，夜间纸色下几乎看不清：每次载入检查一次文字与其实际背景的对比度，
            // 不足 4.5:1 时改色——深色底用阅读页正文色，浅色底（提示框、代码块）用深色字。
            if (!root.dataset.tyContrast) {
                root.dataset.tyContrast = 'true';
                const parse = c => { const m = /rgba?\(([^)]+)\)/.exec(c || ''); if (!m) return null; const p = m[1].split(',').map(parseFloat); return {r: p[0], g: p[1], b: p[2], a: p.length > 3 ? p[3] : 1}; };
                const hex = h => { const v = (h || '').replace('#', ''); return v.length === 6 ? {r: parseInt(v.slice(0, 2), 16), g: parseInt(v.slice(2, 4), 16), b: parseInt(v.slice(4, 6), 16), a: 1} : null; };
                const lum = c => { const f = v => { v /= 255; return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); }; return 0.2126 * f(c.r) + 0.7152 * f(c.g) + 0.0722 * f(c.b); };
                const ratio = (a, b) => { const x = lum(a), y = lum(b); return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05); };
                const paper = hex(root.dataset.tyPaper) || {r: 250, g: 250, b: 247, a: 1};
                const fg = hex(root.dataset.tyFg) || {r: 30, g: 27, b: 22, a: 1};
                const ink = {r: 20, g: 17, b: 15, a: 1};
                const backgrounds = new Map();
                const backgroundOf = el => {
                    if (!el || el === root || el === document.body) return paper;
                    if (backgrounds.has(el)) return backgrounds.get(el);
                    const own = parse(getComputedStyle(el).backgroundColor);
                    const value = own && own.a > 0.5 ? own : backgroundOf(el.parentElement);
                    backgrounds.set(el, value); return value;
                };
                root.querySelectorAll('*').forEach(el => {
                    if (![...el.childNodes].some(n => n.nodeType === 3 && n.data.trim())) return;
                    const color = parse(getComputedStyle(el).color); if (!color) return;
                    const bg = backgroundOf(el);
                    if (ratio(color, bg) >= 4.5) return;
                    const target = lum(bg) < 0.35 ? fg : ink;
                    el.style.setProperty('color', `rgb(${target.r}, ${target.g}, ${target.b})`, 'important');
                });
            }
            // 总宽补齐为整页的倍数：超宽元素撑出的零头会让最后一页停在非整页位置。
            const page = document.documentElement;
            page.style.minWidth = '';
            page.style.minWidth = Math.ceil(page.scrollWidth / innerWidth - 0.01) * innerWidth + 'px';
            root.querySelectorAll('mark[data-ty-speech]').forEach(mark => mark.replaceWith(...mark.childNodes));
            root.normalize();
            window.__tyFollow = null; window.__tyPage = -1;
            if (input.target < 0) return 0;
            const normalize = s => s.replace(/\s/g, '');
            const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
            const points = []; let text = '', node;
            while ((node = walker.nextNode())) {
                if (node.parentElement.closest('style,script,noscript,nav,svg,[hidden]')) continue;
                for (let i = 0; i < node.length; i++) {
                    if (!/\s/.test(node.data[i])) { text += node.data[i]; points.push([node, i]); }
                }
            }
            // 逐句顺序定位；某句找不到时跳过（不整体放弃），只有目标句本身找不到才不高亮。
            let cursor = 0, start = -1, end = -1;
            for (let i = 0; i <= input.target; i++) {
                const sentence = normalize(input.sentences[i]);
                if (!sentence.length) continue;
                let at = text.indexOf(sentence, cursor);
                if (at < 0) at = text.indexOf(sentence);
                if (at < 0) { if (i === input.target) return 0; continue; }
                if (i === input.target) { start = at; end = at + sentence.length; }
                cursor = at + sentence.length;
            }
            if (start < 0 || end <= start) return 0;
            const segments = [];
            for (let i = start; i < end; i++) {
                const [n, offset] = points[i], previous = segments[segments.length - 1];
                if (previous && previous.node === n) previous.end = offset + 1;
                else segments.push({node: n, start: offset, end: offset + 1});
            }
            for (const part of segments.reverse()) {
                const r = document.createRange(); r.setStart(part.node, part.start); r.setEnd(part.node, part.end);
                const mark = document.createElement('mark'); mark.dataset.tySpeech = 'true';
                // 钴蓝跟读带：与原生文字模式共用纸色适配后的高亮，只铺文字底部。
                mark.style.setProperty('background-image', 'linear-gradient(180deg, rgba(0,0,0,0) 62%, ' + input.color + ' 62%)', 'important');
                mark.style.setProperty('color', 'inherit', 'important'); r.surroundContents(mark);
            }
            // 按字跟随（与纯文本模式一致）：找到本句第 k 个非空白字所在页；跟随时该字进入新页即翻页，
            // 并始终对齐整页边界（布局宽度变化后也能自愈错位）。之后读到的字变化只需调用它，不必重建高亮。
            const marks = [...root.querySelectorAll('mark[data-ty-speech]')];
            window.__tyFollow = (k, follow) => {
                let rect = null, n = Math.max(0, k);
                outer: for (const mark of marks) {
                    const t = mark.firstChild; if (!t || t.nodeType !== 3) continue;
                    for (let i = 0; i < t.data.length; i++) {
                        if (/\s/.test(t.data[i])) continue;
                        const r = document.createRange(); r.setStart(t, i); r.setEnd(t, i + 1);
                        const box = r.getBoundingClientRect();
                        if (box.width || box.height) rect = box;
                        if (n-- === 0) break outer;
                    }
                }
                if (!rect) return -1;
                const page = Math.max(0, Math.floor((scrollX + rect.left + 1) / innerWidth));
                window.__tyPage = page;
                if (follow && Math.abs(scrollX - page * innerWidth) > 1) window.scrollTo({left: page * innerWidth, behavior: 'instant'});
                return page;
            };
            window.__tyFollow(input.spoken, input.follow);
            return segments.length;
        })(); })();
        """#
    }
    /// 读到的字变化而句子未变：只重新定位与翻页，不重建高亮。返回该字所在页（无高亮时 -1）。
    static func followScript(spoken: Int, follow: Bool) -> String {
        "window.__tyFollow ? window.__tyFollow(\(spoken), \(follow)) : -1"
    }
    /// 读到的字在本句中的位置：只数非空白字符的 UTF-16 单位，与页面脚本的计数方式一致。
    static func spokenIndex(text: String, sentence: NSRange?, offset: Int?) -> Int {
        guard let sentence, let offset else { return 0 }
        let ns = text as NSString
        let end = min(max(offset, sentence.location), NSMaxRange(sentence), ns.length)
        guard end > sentence.location else { return 0 }
        return ns.substring(with: NSRange(location: sentence.location, length: end - sentence.location))
            .unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) }
            .reduce(0) { $0 + ($1.value > 0xFFFF ? 2 : 1) }
    }
}

/// 章内位置沿用句子序号；每次查询重新读取 DOM，避免朗读高亮拆分文字节点后坐标失效。
enum OriginalReadingPosition {
    static func script(text: String) -> String {
        let sentences = Sentence.split(text).map(\.text)
        let json = String(data: try! Integrity.encoder().encode(sentences), encoding: .utf8)!
        return "window.__tyReading = (() => { const sentences = " + json + ";" + #"""
            function index() {
                const root = document.getElementById('ty-reader-book');
                if (!root) return {points: [], spans: []};
                const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
                const points = [], spans = []; let text = '', node;
                while ((node = walker.nextNode())) {
                    if (node.parentElement.closest('style,script,noscript,nav,svg,[hidden]')) continue;
                    for (let i = 0; i < node.length; i++) {
                        if (!/\s/.test(node.data[i])) { text += node.data[i]; points.push([node, i]); }
                    }
                }
                let cursor = 0;
                sentences.forEach((sentence, position) => {
                    const value = sentence.replace(/\s/g, '');
                    if (!value.length) return;
                    let start = text.indexOf(value, cursor);
                    if (start < 0) start = text.indexOf(value);
                    if (start < 0) return;
                    const end = start + value.length;
                    spans.push({position, start, end}); cursor = end;
                });
                return {points, spans};
            }
            function range(points, span, firstOnly) {
                const start = points[span.start], end = points[firstOnly ? span.start : span.end - 1];
                const r = document.createRange();
                r.setStart(start[0], start[1]); r.setEnd(end[0], end[1] + 1);
                return r;
            }
            return {
                goTo(position) {
                    const {points, spans} = index();
                    const span = spans.find(s => s.position >= position) || spans[spans.length - 1];
                    if (!span) return -1;
                    const rect = range(points, span, true).getBoundingClientRect();
                    const page = Math.max(0, Math.floor((scrollX + rect.left + 1) / innerWidth));
                    window.scrollTo({left: page * innerWidth, behavior: 'instant'});
                    return page;
                },
                position(page) {
                    const {points, spans} = index();
                    const left = page * innerWidth, right = left + innerWidth;
                    let preceding = -1;
                    for (const span of spans) {
                        const rects = [...range(points, span, false).getClientRects()];
                        if (rects.some(r => r.width > 0 && r.height > 0 && r.right + scrollX > left + 0.5 && r.left + scrollX < right - 0.5)) return span.position;
                        if (rects.some(r => r.right + scrollX <= left + 0.5)) preceding = span.position;
                    }
                    return preceding;
                }
            };
        })(); 0;
        """#
    }
    static func restore(_ position: Int) -> String { "window.__tyReading ? window.__tyReading.goTo(\(max(0, position))) : -1" }
    static func read(page: Int) -> String { "window.__tyReading ? window.__tyReading.position(\(max(0, page))) : -1" }
}

/// 阅读工具和设备方向改变可用视口时，重排完成后仍停在当前阅读句。
private final class OriginalReaderWebView: WKWebView {
    var onViewportChange: (() -> Void)?
    private var previousSize = CGSize.zero
    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 1, bounds.height > 1, bounds.size != previousSize else { return }
        previousSize = bounds.size
        onViewportChange?()
    }
}

struct OriginalBookView: UIViewRepresentable {
    let html: String
    let css: String
    let book: Book
    let chapter: Int
    /// 正文颜色跟随阅读页纸色；背景透明，露出阅读页自己的纸色。
    var foreground: Color = Theme.ink
    /// 阅读页纸色，用于修正书籍样式里低对比的文字颜色。
    var paper: Color = ReaderPaper.xuan
    /// 只用于阅读交互（链接、选区）；出版物的图片与版面保持原样。
    var accent: Color = Theme.accent
    var preferences: ReaderPreferences = .init()
    var highlight: NSRange? = nil
    /// 当前读到的字（章内 UTF-16 偏移，即 `SpeechPlayer.followPublisher`）：长句跨页时读到哪页翻到哪页。
    /// 由协调器直接订阅，逐字变化不经过 SwiftUI 刷新。
    var spokenSource: CurrentValueSubject<Int?, Never>? = nil
    var follow = true
    var highlightColor: UIColor = UIColor(Theme.wash)
    var readingPosition = 0
    /// 显式跳转与普通翻页回写区分开，避免每次保存位置又跳回当前句句首。
    var positionRevision = 0
    var onPositionChange: ((Int) -> Void)? = nil
    /// 点按中间区域：显示 / 隐藏工具栏。
    var onToggleChrome: (() -> Void)? = nil
    /// 手动翻到别的页（点按或滑动后页码确实变了）：停止朗读跟随，与纯文本翻页一致。
    var onManualPage: (() -> Void)? = nil
    /// 手动翻回正在朗读的那一页：恢复自动跟随，与纯文本翻页一致。
    /// 首页继续左点 / 末页继续右点：翻章。
    var onEdgeTurn: ((Int) -> Void)? = nil
    func makeCoordinator() -> Coordinator { Coordinator() }
    /// 为配置注册书内图片的按需加载；返回的处理器需随书籍切换更新资源。
    @discardableResult static func prepare(_ config: WKWebViewConfiguration, book: Book) -> ResourceSchemeHandler {
        let handler = ResourceSchemeHandler()
        handler.update(book)
        config.setURLSchemeHandler(handler, forURLScheme: ResourceSchemeHandler.scheme)
        return handler
    }
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration(); config.defaultWebpagePreferences.allowsContentJavaScript = false
        config.websiteDataStore = .nonPersistent()
        context.coordinator.resources = Self.prepare(config, book: book)
        let view = OriginalReaderWebView(frame: .zero, configuration: config); view.navigationDelegate = context.coordinator; view.isOpaque = false; view.backgroundColor = .clear
        // 横向分页：滑动吸附整页，方向锁定避免纵向漂移。
        view.scrollView.isPagingEnabled = true
        view.scrollView.isDirectionalLockEnabled = true
        view.scrollView.showsHorizontalScrollIndicator = false
        view.scrollView.showsVerticalScrollIndicator = false
        view.scrollView.contentInsetAdjustmentBehavior = .never
        view.scrollView.backgroundColor = .clear
        context.coordinator.view = view
        view.onViewportChange = { [weak coordinator = context.coordinator, weak view] in
            guard let view else { return }
            coordinator?.viewportDidChange(view)
        }
        view.accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: "显示或隐藏阅读工具", target: context.coordinator, selector: #selector(Coordinator.accessibilityToggleTools)),
            UIAccessibilityCustomAction(name: "上一页", target: context.coordinator, selector: #selector(Coordinator.accessibilityPreviousPage)),
            UIAccessibilityCustomAction(name: "下一页", target: context.coordinator, selector: #selector(Coordinator.accessibilityNextPage))
        ]
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        // 与 WebView 内部手势同时识别：正文中的链接等区域也要能响应点按翻页与收起工具栏。
        tap.delegate = context.coordinator
        view.addGestureRecognizer(tap)
        // 滑动翻页结束后按落定的页码判断是否接管跟随（不替换 scrollView 代理，避免干扰 WebKit 内部行为）。
        view.scrollView.panGestureRecognizer.addTarget(context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        return view
    }
    func updateUIView(_ view: WKWebView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onToggleChrome = onToggleChrome; coordinator.onManualPage = onManualPage; coordinator.onEdgeTurn = onEdgeTurn
        coordinator.onPositionChange = onPositionChange
        coordinator.requestPosition(readingPosition, revision: positionRevision)
        let color = UIColor(foreground).resolvedColor(with: view.traitCollection).cssHex
        let paperHex = UIColor(paper).resolvedColor(with: view.traitCollection).cssHex
        let accentHex = UIColor(accent).resolvedColor(with: view.traitCollection).cssHex
        view.tintColor = UIColor(accent)
        view.scrollView.indicatorStyle = preferences.kind.dark ? .white : .default
        let typoKey = "\(preferences.font)-\(Int(preferences.fontSize.rounded()))-\(Int(preferences.lineSpacing.rounded()))-\(Int(preferences.paragraphSpacing.rounded()))-\(preferences.letterSpacing)-\(preferences.indent)-\(preferences.justified)"
        let key = "\(book.id)-\(chapter)-\(color)-\(paperHex)-\(accentHex)-\(typoKey)-\(html.hashValue)-\(css.hashValue)"
        let highlightKey = "\(key)-\(String(describing: highlight))-\(highlightColor.resolvedColor(with: view.traitCollection).cssHex)"
        let text = book.chapters.indices.contains(chapter) ? book.chapters[chapter].text : ""
        if coordinator.text != text || coordinator.readingScript.isEmpty { coordinator.readingScript = OriginalReadingPosition.script(text: text) }
        coordinator.subscribe(spokenSource, view: view)
        coordinator.text = text; coordinator.highlight = highlight
        let spoken = OriginalSpeechHighlight.spokenIndex(text: text, sentence: highlight, offset: spokenSource?.value)
        coordinator.follow = follow; coordinator.spoken = spoken
        if highlight == nil { coordinator.spokenPage = nil }
        // 句子没变、只是读到的字或跟随状态变了：只重新定位翻页，不重建高亮。
        guard coordinator.highlightKey != highlightKey else {
            if coordinator.loaded && highlight != nil { coordinator.refollow(view) }
            if coordinator.loaded { coordinator.restorePosition(view) }
            return
        }
        coordinator.highlightKey = highlightKey
        let script = OriginalSpeechHighlight.script(text: text, range: highlight, follow: follow, color: highlightColor.resolvedColor(with: view.traitCollection).cssRgbaHalf, spoken: spoken)
        let changed = coordinator.script != script
        coordinator.script = script
        guard coordinator.key != key else {
            if changed && coordinator.loaded { coordinator.apply(view) }
            else if coordinator.loaded { coordinator.restorePosition(view) }
            return
        }
        coordinator.key = key; coordinator.loaded = false
        coordinator.pendingPosition = readingPosition
        coordinator.resources?.update(book)
        view.loadHTMLString(OriginalDocument.html(html, css: css, color: color, background: "transparent", paper: paperHex, preferences: preferences, accent: accentHex), baseURL: nil)
    }
    final class Coordinator: NSObject, WKNavigationDelegate, UIGestureRecognizerDelegate {
        var key = ""
        var highlightKey = ""
        var script = ""
        var loaded = false
        var resources: ResourceSchemeHandler?
        weak var view: WKWebView?
        /// 是否跟随朗读、读到的字在本句中的位置、该字所在页（无朗读高亮时为 nil）。
        var follow = true
        var spoken = 0
        var spokenPage: Int?
        var text = ""
        var highlight: NSRange?
        var readingScript = ""
        var readingPosition = 0
        var positionRevision: Int?
        var pendingPosition: Int?
        private var manualRevision = 0
        private var viewportRevision = 0
        var onPositionChange: ((Int) -> Void)?
        func requestPosition(_ position: Int, revision: Int) {
            readingPosition = position
            if positionRevision != revision { positionRevision = revision; pendingPosition = position }
        }
        func restorePosition(_ view: WKWebView) {
            guard let position = pendingPosition else { return }
            pendingPosition = nil
            guard highlight == nil || !follow else { return }
            view.evaluateJavaScript(OriginalReadingPosition.restore(position), in: nil, in: .defaultClient, completionHandler: nil)
        }
        func viewportDidChange(_ view: WKWebView) {
            viewportRevision += 1
            guard loaded else { return }
            let viewport = viewportRevision, documentKey = key, manual = manualRevision, revision = positionRevision
            let position = readingPosition
            // 一次工具栏动画会经历多次布局；只在最终尺寸稳定后恢复，避免中途跳页。
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self, weak view] in
                guard let self, let view, self.loaded, self.viewportRevision == viewport,
                      self.key == documentKey, self.manualRevision == manual,
                      self.positionRevision == revision else { return }
                self.pendingPosition = position
                self.apply(view)
            }
        }
        private var lastFollow: (Int, Bool)?
        private var spokenSubscription: AnyCancellable?
        private weak var spokenSubject: CurrentValueSubject<Int?, Never>?
        /// 读到的字一变就只做定位 / 翻页，不触发 SwiftUI 刷新整个阅读页。
        func subscribe(_ source: CurrentValueSubject<Int?, Never>?, view: WKWebView) {
            guard source !== spokenSubject else { return }
            spokenSubject = source
            spokenSubscription = source?.removeDuplicates().receive(on: DispatchQueue.main).sink { [weak self, weak view] offset in
                guard let self, let view, self.loaded, self.highlight != nil else { return }
                self.spoken = OriginalSpeechHighlight.spokenIndex(text: self.text, sentence: self.highlight, offset: offset)
                self.refollow(view)
            }
        }
        private var dragStartPage = 0
        var onToggleChrome: (() -> Void)?
        var onManualPage: (() -> Void)?
        var onEdgeTurn: ((Int) -> Void)?
        /// 允许与 WebView 内部点击 / 滚动手势同时识别，否则链接密集的正文里点按会失效。
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
        @objc func accessibilityToggleTools() -> Bool { onToggleChrome?(); return true }
        @objc func accessibilityPreviousPage() -> Bool { page(by: -1); return true }
        @objc func accessibilityNextPage() -> Bool { page(by: 1); return true }
        /// 与纯文本页一致的点按分区：左 28% 上一页，右 28% 下一页，中间显示 / 隐藏工具栏。
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let view else { return }
            let fraction = gesture.location(in: view).x / max(1, view.bounds.width)
            if fraction < 0.28 { page(by: -1) } else if fraction > 0.72 { page(by: 1) } else { onToggleChrome?() }
        }
        /// 滑动只有真正翻到别的页才算手动翻页；翻回朗读所在页则恢复跟随。
        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let view else { return }
            switch gesture.state {
            case .began: dragStartPage = currentPage(view)
            case .ended, .cancelled:
                // 已在末页还继续左滑（或已在首页继续右滑）：分页吸附本身到不了下一章，
                // 把这次越界拖拽顺势交给翻章通路，与点按边缘翻页（page(by:) 的越界分支）同一出口，
                // 免得每读完一章都得去目录里手选下一章。
                if loaded {
                    let translation = gesture.translation(in: view).x
                    let velocity = gesture.velocity(in: view).x
                    let width = max(1, view.scrollView.bounds.width)
                    let lastPage = max(0, Int((view.scrollView.contentSize.width / width).rounded()) - 1)
                    if dragStartPage >= lastPage, translation < -50 || velocity < -600 {
                        manualRevision += 1; pendingPosition = nil
                        onEdgeTurn?(1); return
                    }
                    if dragStartPage <= 0, translation > 50 || velocity > 600 {
                        manualRevision += 1; pendingPosition = nil
                        onEdgeTurn?(-1); return
                    }
                }
                // 等分页吸附动画落定再读页码。
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self, weak view] in
                    guard let self, let view else { return }
                    let page = self.currentPage(view)
                    if page != self.dragStartPage { self.settled(on: page) }
                }
            default: break
            }
        }
        private func currentPage(_ view: WKWebView) -> Int {
            Int((view.scrollView.contentOffset.x / max(1, view.scrollView.bounds.width)).rounded())
        }
        /// 手动翻页始终退出跟随；与正文工具中的显式“回到朗读处”区分。
        private func settled(on page: Int) {
            manualRevision += 1; pendingPosition = nil
            follow = false; onManualPage?()
            guard let view else { return }
            let documentKey = key, revision = manualRevision, requestedRevision = positionRevision
            view.evaluateJavaScript(OriginalReadingPosition.read(page: page), in: nil, in: .defaultClient) { [weak self] result in
                guard let self, self.key == documentKey, self.manualRevision == revision,
                      self.positionRevision == requestedRevision, !self.follow,
                      case .success(let value) = result, let position = value as? Int, position >= 0 else { return }
                self.readingPosition = position
                self.onPositionChange?(position)
            }
        }
        private func page(by delta: Int) {
            guard let view else { return }
            let scroll = view.scrollView
            let width = max(1, scroll.bounds.width)
            // 锁定整页边界，避免上一次滚动尚有亚像素偏移时累积到下一页。
            let target = CGFloat(currentPage(view) + delta) * width
            let last = max(0, scroll.contentSize.width - width)
            if target < -0.5 || target > last + 0.5 {
                manualRevision += 1; pendingPosition = nil
                onEdgeTurn?(delta); return
            }
            let x = min(max(0, target), last)
            settled(on: Int((x / width).rounded()))
            // 尚未挂入窗口的 WebView 没有可靠的滚动动画时钟；直接提交页码。
            // 实际可见页面继续使用原生动画，并尊重系统「减少动态效果」。
            let animates = view.window != nil && !UIAccessibility.isReduceMotionEnabled
            scroll.setContentOffset(CGPoint(x: x, y: 0), animated: animates)
        }
        func apply(_ view: WKWebView) {
            lastFollow = (spoken, follow)
            let documentKey = key
            view.evaluateJavaScript(readingScript + "\n" + script, in: nil, in: .defaultClient) { [weak self, weak view] _ in
                guard let self, let view, self.key == documentKey else { return }
                self.readSpokenPage(view)
                self.restorePosition(view)
            }
        }
        /// 读到的字变化：只定位该字所在页，跟随时翻过去。
        func refollow(_ view: WKWebView) {
            guard lastFollow.map({ $0 != (spoken, follow) }) ?? true else { return }
            lastFollow = (spoken, follow)
            view.evaluateJavaScript(OriginalSpeechHighlight.followScript(spoken: spoken, follow: follow), in: nil, in: .defaultClient) { [weak self] result in
                if case .success(let value) = result, let page = value as? Int { self?.spokenPage = page >= 0 ? page : nil }
            }
        }
        private func readSpokenPage(_ view: WKWebView) {
            view.evaluateJavaScript("window.__tyPage ?? -1", in: nil, in: .defaultClient) { [weak self] result in
                if case .success(let value) = result, let page = value as? Int { self?.spokenPage = page >= 0 ? page : nil }
            }
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            loaded = true; apply(webView)
            let documentKey = key, manual = manualRevision, revision = positionRevision
            // 布局稳定（尺寸 / 字体 / 图片落定）后再对齐一次整页边界，修正加载早期的错位。
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self, weak webView] in
                guard let self, let webView, self.loaded, self.key == documentKey,
                      self.manualRevision == manual, self.positionRevision == revision else { return }
                self.pendingPosition = self.readingPosition
                self.apply(webView)
            }
        }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
            decisionHandler(url.scheme == "about" ? .allow : .cancel)
        }
    }
}

/// 按需提供书内图片（`tingye-resource:r12`）：只解码当前章节真正用到的图片，且在后台线程解码。
final class ResourceSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "tingye-resource"
    private let lock = NSLock()
    private var bookID = ""
    private var resources: [String: JSONValue] = [:]
    /// 已停止的请求不能再回应，否则 WebKit 会抛异常。
    private var active = Set<ObjectIdentifier>()
    func update(_ book: Book) {
        lock.lock(); defer { lock.unlock() }
        guard book.id != bookID || resources.isEmpty else { return }
        bookID = book.id; resources = book.fields["resources"]?.object ?? [:]
    }
    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        let id = ObjectIdentifier(task); active.insert(id)
        let key = (task.request.url?.absoluteString ?? "").replacingOccurrences(of: Self.scheme + ":", with: "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        lock.lock(); let raw = resources[key]?.string; lock.unlock()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let decoded = raw.flatMap(Self.decode)
            DispatchQueue.main.async {
                guard let self, self.active.remove(id) != nil else { return }
                guard let (data, mime) = decoded, let url = task.request.url else { task.didFailWithError(URLError(.fileDoesNotExist)); return }
                task.didReceive(URLResponse(url: url, mimeType: mime, expectedContentLength: data.count, textEncodingName: nil))
                task.didReceive(data)
                task.didFinish()
            }
        }
    }
    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) { active.remove(ObjectIdentifier(task)) }
    /// `data:image/png;base64,....` → 数据与 MIME 类型。
    static func decode(_ raw: String) -> (Data, String)? {
        guard raw.hasPrefix("data:"), let comma = raw.firstIndex(of: ",") else { return nil }
        let header = raw[raw.index(raw.startIndex, offsetBy: 5)..<comma]
        let mime = header.split(separator: ";").first.map(String.init) ?? "application/octet-stream"
        guard let data = Data(base64Encoded: String(raw[raw.index(after: comma)...]), options: .ignoreUnknownCharacters) else { return nil }
        return (data, mime)
    }
}

private extension UIColor {
    var cssHex: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02x%02x%02x", Int((min(max(r, 0), 1) * 255).rounded()), Int((min(max(g, 0), 1) * 255).rounded()), Int((min(max(b, 0), 1) * 255).rounded()))
    }
    /// 柔和跟读底色，与原生分页 / 连续滚动的低饱和高亮一致。
    var cssRgbaHalf: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return "rgba(\(Int((min(max(r, 0), 1) * 255).rounded())), \(Int((min(max(g, 0), 1) * 255).rounded())), \(Int((min(max(b, 0), 1) * 255).rounded())), 0.18)"
    }
}
