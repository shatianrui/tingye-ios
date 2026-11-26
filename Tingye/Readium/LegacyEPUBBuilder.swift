import Foundation
import ImageIO
import NaturalLanguage
import UIKit
import SwiftSoup
import ReadiumZIPFoundation

/// Reconstructs a reflowable EPUB from the *unchanged* native text snapshot.
/// Losses are explicit, persisted alongside the artifact, and never written into Book/progress.
struct LegacyEPUBBuilder {
    static let generatorVersion = 1
    struct Loss: Codable, Equatable, Sendable {
        let chapter: Int?
        let code: String
        let detail: String
    }
    struct Report: Codable, Equatable, Sendable {
        let generatorVersion: Int
        let contentHash: String
        var losses: [Loss]
    }
    struct Result: Sendable {
        let url: URL
        let map: PublicationMap
        let report: Report
    }
    private struct Receipt: Codable {
        let epubSHA256: String
        let map: PublicationMap
        let report: Report
    }

    static func cached(at directory: URL, contentHash: String) throws -> Result? {
        let receiptURL = directory.appendingPathComponent("publication.json")
        guard let data = try? Data(contentsOf: receiptURL), let receipt = try? JSONDecoder().decode(Receipt.self, from: data),
              receipt.map.contentHash == contentHash, receipt.map.generatorVersion == generatorVersion,
              receipt.report.generatorVersion == generatorVersion else { return nil }
        let epub = directory.appendingPathComponent("publication.epub")
        guard (try? PublicationDigest.file(epub)) == receipt.epubSHA256 else { return nil }
        return Result(url: epub, map: receipt.map, report: receipt.report)
    }

    func build(_ input: Book, to destination: URL) async throws -> Result {
        let book = try input.validated()
        guard book.format.uppercased() == "EPUB" else { throw ReaderError.message("存量重建只支持 EPUB。") }
        try Task.checkCancellation()
        let hash = try PublicationMap.contentHash(for: book), map = PublicationMap(book: book, contentHash: hash)
        let fm = FileManager.default, parent = destination.deletingLastPathComponent()
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        // Same-volume sibling permits publishing the complete artifact + receipt in one rename.
        let staging = parent.appendingPathComponent(".staging-" + UUID().uuidString)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }
        let files = staging.appendingPathComponent("container")
        let state = BuildState(book: book, map: map, files: files)
        try state.generate()
        try Task.checkCancellation()
        let epub = staging.appendingPathComponent("publication.epub")
        let archive = try await Archive(url: epub, accessMode: .create)
        let paths = state.filesWritten.sorted()
        for path in ["mimetype"] + paths.filter({ $0 != "mimetype" }) {
            try Task.checkCancellation()
            // Mapped, not materialized: image entries can be tens of MB each and the archive
            // provider below is fed chunk by chunk, so resident memory stays near one chunk
            // plus the largest page instead of the largest whole file.
            let data = try Data(contentsOf: files.appendingPathComponent(path), options: .mappedIfSafe)
            try await archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count),
                                       modificationDate: Date(timeIntervalSince1970: 315532800),
                                       compressionMethod: path == "mimetype" ? .none : .deflate) { position, size in
                data.subdata(in: Int(position)..<(Int(position) + size))
            }
        }
        // Check the real archive, not just the directory it was built from.
        let entries = try await archive.entries()
        guard entries.map(\.path).first == "mimetype", Set(entries.map(\.path)) == Set(paths) else {
            throw ReaderError.message("派生 EPUB ZIP 结构校验失败。")
        }
        let handle = try FileHandle(forReadingFrom: epub); defer { try? handle.close() }
        let header = try handle.read(upToCount: 30) ?? Data()
        guard header.count == 30, header[8] == 0, header[9] == 0, header[28] == 0, header[29] == 0 else {
            throw ReaderError.message("EPUB mimetype 必须无压缩且无扩展字段。")
        }
        let report = Report(generatorVersion: Self.generatorVersion, contentHash: hash, losses: state.losses)
        let receipt = Receipt(epubSHA256: try PublicationDigest.file(epub), map: map, report: report)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        try encoder.encode(receipt).write(to: staging.appendingPathComponent("publication.json"), options: .atomic)
        try fm.removeItem(at: files)
        try Task.checkCancellation()
        // Existing complete artifacts stay readable until the new one has passed every validation.
        if fm.fileExists(atPath: destination.path) {
            if let existing = try Self.cached(at: destination, contentHash: hash) { return existing }
            _ = try fm.replaceItemAt(destination, withItemAt: staging)
        } else { try fm.moveItem(at: staging, to: destination) }
        return Result(url: destination.appendingPathComponent("publication.epub"), map: map, report: report)
    }
}

private final class BuildState {
    struct Image { let path: String; let mediaType: String }
    let book: Book
    let map: PublicationMap
    let files: URL
    var filesWritten: [String] = []
    var losses: [LegacyEPUBBuilder.Loss] = []
    var images: [String: Image] = [:] // by output path; all filenames are generated, never supplied by JSON
    var resourcePaths: [String: String] = [:]
    var imageHashes: [String: String] = [:]
    var documents: [SwiftSoup.Document] = []
    var bodyStyles: [Int: String] = [:]
    var language = "und"

    init(book: Book, map: PublicationMap, files: URL) { self.book = book; self.map = map; self.files = files }
    func loss(_ code: String, _ detail: String, chapter: Int? = nil) {
        losses.append(.init(chapter: chapter, code: code, detail: String(detail.prefix(240))))
    }
    func write(_ path: String, _ data: Data) throws {
        guard PublicationMap.normalized(path) == path else { throw ReaderError.message("重建输出路径无效。") }
        let url = files.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        filesWritten.append(path)
    }
    func writeXML(_ path: String, _ xml: String) throws {
        let data = Data(xml.utf8)
        guard Self.validXML(data) else { throw ReaderError.message("派生 EPUB XML 无法解析：\(path)") }
        try write(path, data)
    }
    static func validXML(_ data: Data) -> Bool {
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true; parser.shouldResolveExternalEntities = false
        return parser.parse()
    }
    static func escape(_ raw: String) -> String {
        let clean = raw.unicodeScalars.filter { $0.value == 9 || $0.value == 10 || $0.value == 13 || ($0.value >= 32 && $0.value != 0xFFFE && $0.value != 0xFFFF) }
        return String(String.UnicodeScalarView(clean)).replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "'", with: "&apos;")
    }
    func generate() throws {
        loss("publication-metadata", "原 nav 层级、非线性 spine、字体/布局元数据未保存；本产物使用现有章序和平铺目录、reflowable 布局。")
        let requestedLanguage = book.fields["language"]?.string ?? ""
        if requestedLanguage.range(of: "^[A-Za-z]{2,8}(?:-[A-Za-z0-9]{1,8})*$", options: .regularExpression) != nil { language = requestedLanguage }
        else {
            let recognizer = NLLanguageRecognizer()
            let sample = book.chapters.prefix(5).map { String($0.text.prefix(1600)) }.joined(separator: "\n")
            recognizer.processString(sample)
            if let detected = recognizer.dominantLanguage, (recognizer.languageHypotheses(withMaximum: 1)[detected] ?? 0) >= 0.5 { language = detected.rawValue }
            loss("language-inferred", "language=\(language)，源语言缺失；按正文识别，低置信度使用 und。")
        }
        for key in book.resourceMap.keys.sorted() {
            try Task.checkCancellation()
            // Each pass builds CGImageSource/UIImage temporaries; without a pool they pile up
            // until the detached task ends, which for hundreds of images is the peak-memory
            // difference between finishing and being jetsammed mid-rebuild.
            try autoreleasepool {
                if let uri = book.resourceMap[key]?.string, let path = try image(uri, chapter: nil) { resourcePaths["tingye-resource:" + key] = path }
                else { loss("resource-invalid", "资源 \(key) 不是可还原的图片 data URI。") }
            }
        }
        let cover = try book.fields["cover"]?.string.flatMap { try resource($0, chapter: nil) }
        if book.fields["cover"] != nil && cover == nil { loss("cover-missing", "已有封面引用无法还原，不将首图充作封面。") }
        for (index, chapter) in book.chapters.enumerated() {
            try Task.checkCancellation()
            // Same pool discipline as the resource pass: XMLParser/SwiftSoup temporaries from
            // one chapter are released before the next chapter is normalized.
            try autoreleasepool {
                documents.append(try chapterDocument(chapter, index: index))
                let css = try cleanCSS(chapter.fields["document"]?.object?["css"]?.string ?? "", chapter: index)
                try write(String(format: "EPUB/styles/ch-%06d.css", index + 1), Data((css + "\n" + (bodyStyles[index] ?? "")).utf8))
            }
        }
        try validateFragments()
        for (index, doc) in documents.enumerated() {
            try writeXML(map.chapters[index].href, try doc.outerHtml())
        }
        try write("mimetype", Data("application/epub+zip".utf8))
        try writeXML("META-INF/container.xml", """
        <?xml version="1.0" encoding="UTF-8"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="EPUB/package.opf" media-type="application/oebps-package+xml"/></rootfiles></container>
        """)
        let toc = book.chapters.enumerated().map { index, chapter in
            "<li><a href=\"text/\((map.chapters[index].href as NSString).lastPathComponent)\">\(Self.escape(chapter.title))</a></li>"
        }.joined()
        try writeXML("EPUB/nav.xhtml", """
        <?xml version="1.0" encoding="UTF-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" lang="\(language)" xml:lang="\(language)"><head><title>目录</title></head><body><nav epub:type="toc" id="toc"><h1>目录</h1><ol>\(toc)</ol></nav></body></html>
        """)
        var manifest = "<item id=\"nav\" href=\"nav.xhtml\" media-type=\"application/xhtml+xml\" properties=\"nav\"/>"
        var spine = ""
        for (index, chapter) in map.chapters.enumerated() {
            let name = (chapter.href as NSString).lastPathComponent
            manifest += "<item id=\"c\(index)\" href=\"text/\(name)\" media-type=\"application/xhtml+xml\"/>"
            manifest += String(format: "<item id=\"s%d\" href=\"styles/ch-%06d.css\" media-type=\"text/css\"/>", index, index + 1)
            spine += "<itemref idref=\"c\(index)\"/>"
        }
        for (index, path) in images.keys.sorted().enumerated() {
            let properties = path == cover ? " properties=\"cover-image\"" : ""
            manifest += "<item id=\"i\(index)\" href=\"\(path)\" media-type=\"\(images[path]!.mediaType)\"\(properties)/>"
        }
        let description = Self.escape(book.fields["description"]?.string ?? "")
        let category = Self.escape(book.fields["category"]?.string ?? "")
        try writeXML("EPUB/package.opf", """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id" prefix="rendition: http://www.idpf.org/vocab/rendition/#"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="id">urn:tingye:\(book.id)</dc:identifier><dc:title>\(Self.escape(book.title))</dc:title><dc:creator>\(Self.escape(book.author))</dc:creator><dc:language>\(language)</dc:language><dc:description>\(description)</dc:description><dc:subject>\(category)</dc:subject><meta property="dcterms:modified">2000-01-01T00:00:00Z</meta><meta property="rendition:layout">reflowable</meta></metadata><manifest>\(manifest)</manifest><spine>\(spine)</spine></package>
        """)
        // Manifest references are generated from these lists; require every referenced file to exist.
        for path in map.chapters.map(\.href) + images.keys.map({ "EPUB/" + $0 }) + ["EPUB/nav.xhtml"] {
            guard filesWritten.contains(path) else { throw ReaderError.message("派生 EPUB 缺少资源：\(path)") }
        }
    }

    func image(_ uri: String, chapter: Int?) throws -> String? {
        guard uri.hasPrefix("data:image/"), let comma = uri.firstIndex(of: ",") else { return nil }
        let header = String(uri[..<comma]).lowercased()
        guard ["data:image/png;base64", "data:image/jpeg;base64", "data:image/gif;base64", "data:image/webp;base64"].contains(header) else { return nil }
        let encoded = uri[uri.index(after: comma)...].filter { !$0.isWhitespace }
        // Keep malformed/unbounded resource declarations from allocating arbitrary output sizes.
        guard !encoded.isEmpty, encoded.utf8.count <= 128 * 1024 * 1024,
              var bytes = Data(base64Encoded: String(encoded)),
              let source = CGImageSourceCreateWithData(bytes as CFData, nil),
              let actual = CGImageSourceGetType(source) as String? else { return nil }
        let expected = ["data:image/png;base64": "public.png", "data:image/jpeg;base64": "public.jpeg", "data:image/gif;base64": "com.compuserve.gif", "data:image/webp;base64": "org.webmproject.webp"]
        guard expected[header] == actual else { loss("resource-mime-mismatch", header, chapter: chapter); return nil }
        var ext = header.contains("jpeg") ? "jpg" : "png", mime = header.contains("jpeg") ? "image/jpeg" : "image/png"
        if header.contains("gif") || header.contains("webp") {
            guard let decoded = UIImage(data: bytes), let png = decoded.pngData() else { return nil }
            bytes = png; ext = "png"; mime = "image/png"
            loss("image-converted", "GIF/WebP 转 PNG 核心媒体；动画只保留静态帧。", chapter: chapter)
        }
        let hash = PublicationDigest.data(bytes)
        if let path = imageHashes[hash] { return path }
        let path = "images/" + hash + "." + ext
        try write("EPUB/" + path, bytes)
        images[path] = Image(path: path, mediaType: mime); imageHashes[hash] = path
        return path
    }
    func resource(_ ref: String, chapter: Int?) throws -> String? {
        if let path = resourcePaths[ref] { return path }
        if let uri = book.resourceMap[ref]?.string { return try image(uri, chapter: chapter) }
        return try image(ref, chapter: chapter)
    }

    func cleanCSS(_ input: String, chapter: Int) throws -> String {
        var css = input
        for pattern in [#"(?is)@import\b[^;{}]*(?:;|$)"#, #"(?is)@font-face\s*\{[^}]*\}"#] {
            let cleaned = css.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
            if cleaned != css { loss("css-dependency-removed", "删除无法追溯原目录的 @import / @font-face。", chapter: chapter) }; css = cleaned
        }
        css = try replacing(css, pattern: #"(?is)url\(\s*(["']?)(.*?)\1\s*\)"#) { match, ns in
            let ref = ns.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
            if let path = try resource(ref, chapter: chapter) { return "url(\"../\(path)\")" }
            loss("css-url-removed", "无法还原样式引用：\(ref.prefix(100))", chapter: chapter)
            return "none"
        }
        // No escaped CSS network loads are retained; they cannot be reliably resolved from the snapshot.
        if css.contains("\\") || css.range(of: #"(?i)expression\s*\(|javascript:|behavior\s*:|-moz-binding"#, options: .regularExpression) != nil {
            loss("css-unsafe-removed", "样式含转义或活动内容，保守移除本段样式。", chapter: chapter); return ""
        }
        return css
    }
    func replacing(_ source: String, pattern: String, transform: (NSTextCheckingResult, NSString) throws -> String) throws -> String {
        let regex = try NSRegularExpression(pattern: pattern), ns = source as NSString
        var output = source
        for match in regex.matches(in: source, range: NSRange(location: 0, length: ns.length)).reversed() {
            output = (output as NSString).replacingCharacters(in: match.range, with: try transform(match, ns))
        }
        return output
    }

    func chapterDocument(_ chapter: Chapter, index: Int) throws -> SwiftSoup.Document {
        if let html = chapter.documentHTML, !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            do {
                let cleaned = OriginalDocument.closingSelfClosedTags(OriginalDocument.sanitized(html))
                if cleaned != html { loss("html-sanitized", "沿用 OriginalDocument 清理 head/脚本/事件及残留外壳；自闭合正文元素转成对标签。", chapter: index) }
                let doc = try SwiftSoup.parse(cleaned)
                try normalize(doc, index: index)
                try appendMissingImages(chapter, to: doc, index: index)
                let hasImage = try doc.select("img[src]").first() != nil
                guard doc.body()?.hasText() == true || hasImage || chapter.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw ReaderError.message("规范化后正文为空，改用已有 text。")
                }
                try finish(doc, chapter: chapter, index: index)
                if Self.validXML(Data(try doc.outerHtml().utf8)) { return doc }
                loss("html-fallback", "DOM 规范化后 XML 校验失败，退化为 text 段落。", chapter: index)
            } catch is CancellationError { throw CancellationError() }
            catch { loss("html-fallback", "HTML 规范化失败：\(error.localizedDescription)", chapter: index) }
        } else { loss("html-missing", "无 document.html，使用 text 段落；原版式无法恢复。", chapter: index) }
        let doc = try SwiftSoup.parse("<body>" + Self.escape(chapter.text).components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.map { "<p>\($0)</p>" }.joined() + "</body>")
        try appendMissingImages(chapter, to: doc, index: index)
        try finish(doc, chapter: chapter, index: index)
        guard Self.validXML(Data(try doc.outerHtml().utf8)) else { throw ReaderError.message("纯文本章节无法规范化。") }
        return doc
    }
    func finish(_ doc: SwiftSoup.Document, chapter: Chapter, index: Int) throws {
        _ = doc.outputSettings().syntax(syntax: .xml).escapeMode(.xhtml).prettyPrint(pretty: false)
        guard let html = try doc.select("html").first(), let head = doc.head() else { throw ReaderError.message("HTML 缺少根节点。") }
        try html.attr("xmlns", "http://www.w3.org/1999/xhtml")
        try html.attr("lang", language); try html.attr("xml:lang", language)
        try head.html("<title>\(Self.escape(chapter.title))</title><meta charset=\"utf-8\"/><link rel=\"stylesheet\" type=\"text/css\" href=\"../styles/\(String(format: "ch-%06d.css", index + 1))\"/>")
    }
    func normalize(_ doc: SwiftSoup.Document, index: Int) throws {
        // No scripts, network media, inline foreign vocabularies, forms or their side effects survive.
        for node in try doc.select("script,iframe,object,embed,form,input,button,base,meta,link,noscript,video,audio,source,track,svg,math") {
            loss("element-removed", "移除不完整或活动元素：\(node.tagName())", chapter: index)
            try node.remove()
        }
        for style in try doc.select("style") {
            bodyStyles[index, default: ""] += try cleanCSS(style.data(), chapter: index) + "\n"
            try style.remove()
        }
        guard let body = doc.body() else { throw ReaderError.message("HTML 缺少正文。") }
        let tags: Set<String> = ["body", "article", "section", "aside", "header", "footer", "main", "nav", "div", "p", "span", "h1", "h2", "h3", "h4", "h5", "h6", "a", "img", "br", "hr", "b", "strong", "i", "em", "u", "s", "small", "sub", "sup", "pre", "code", "blockquote", "q", "ol", "ul", "li", "dl", "dt", "dd", "table", "caption", "colgroup", "col", "thead", "tbody", "tfoot", "tr", "td", "th", "figure", "figcaption", "ruby", "rt", "rp", "rb", "rtc", "style", "mark", "abbr", "cite", "del", "ins", "time", "wbr"]
        let allowed: Set<String> = ["id", "class", "title", "lang", "dir", "style", "href", "src", "alt", "width", "height", "colspan", "rowspan", "scope", "start", "type", "value", "reversed"]
        var ids: Set<String> = []
        for node in try body.getAllElements() {
            try Task.checkCancellation()
            let tag = node.tagName().lowercased()
            if !tags.contains(tag) { try node.tagName("span"); loss("element-normalized", "未知标签 \(tag) 转 span，保留文本。", chapter: index) }
            for attr in node.getAttributes()?.asList() ?? [] {
                let key = attr.getKey().lowercased()
                if !allowed.contains(key) {
                    try node.removeAttr(attr.getKey())
                    if ["srcset", "poster", "background"].contains(key) { loss("attribute-removed", "无法完整还原 \(key)，保留已解析的 src/正文。", chapter: index) }
                }
            }
            if node.hasAttr("id") {
                let id = try node.attr("id")
                if id.isEmpty || id.contains(where: { $0.isWhitespace }) || !ids.insert(id).inserted {
                    try node.removeAttr("id"); loss("id-removed", "删除空白或重复锚点 ID。", chapter: index)
                }
            }
            if node.hasAttr("style") { try node.attr("style", cleanCSS(node.attr("style"), chapter: index)) }
            if tag == "style" { try node.text(cleanCSS(node.data(), chapter: index)); try node.attr("type", "text/css") }
            if tag == "img", !node.hasAttr("src") {
                try node.tagName("span"); try node.text(node.attr("alt"))
                loss("image-missing", "img 缺少 src，保留替代文本。", chapter: index)
            }
            if node.hasAttr("src") {
                let ref = try node.attr("src")
                if tag == "img", let path = try resource(ref, chapter: index) {
                    try node.attr("src", "../" + path)
                    if !node.hasAttr("alt") { try node.attr("alt", "") }
                }
                else {
                    loss("image-missing", "无法可靠映射图片：\(ref.prefix(100))；保留替代文本。", chapter: index)
                    let alt = try node.attr("alt")
                    try node.tagName("span"); try node.removeAttr("src"); try node.text(alt)
                }
            }
            if node.hasAttr("href") {
                let ref = try node.attr("href")
                if tag == "a", let href = link(ref, chapter: index) { try node.attr("href", href) }
                else { try node.removeAttr("href") }
            }
        }
    }
    func appendMissingImages(_ chapter: Chapter, to doc: SwiftSoup.Document, index: Int) throws {
        guard let body = doc.body() else { return }
        var present = Set(try body.select("img[src]").map { try $0.attr("src") })
        for ref in chapter.nativeImageRefs ?? [] {
            guard let path = try resource(ref, chapter: index) else { loss("native-image-missing", ref, chapter: index); continue }
            let src = "../" + path
            if present.insert(src).inserted {
                try body.append("<img src=\"\(src)\" alt=\"\"/>")
                loss("image-appended", "原图位置不可恢复，按 nativeImages 顺序补在章末。", chapter: index)
            }
        }
    }
    func link(_ ref: String, chapter: Int) -> String? {
        if ref.range(of: #"(?i)^(https?://|mailto:)"#, options: .regularExpression) != nil { return ref }
        let parts = ref.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        let fragment = parts.count > 1 ? "#" + String(parts[1]) : ""
        if parts[0].isEmpty { return fragment.isEmpty ? nil : fragment }
        guard let original = map.chapters[chapter].originalPath,
              let resolved = try? BookImporter.resolve(base: original, href: String(parts[0])),
              let normalized = PublicationMap.normalized(resolved) else {
            loss("link-removed", "无法解析章间链接：\(ref)", chapter: chapter); return nil
        }
        let matches = map.chapters(forOriginalPath: normalized)
        guard let match = matches.first else { loss("link-removed", "链接目标未保留：\(ref)", chapter: chapter); return nil }
        // Prefer the current occurrence for same-document links; otherwise first spine occurrence.
        let target = matches.first(where: { $0.chapterIndex == chapter }) ?? match
        if matches.count > 1 { loss("duplicate-path-link", "重复 path 链接优先本章，否则选首个章序。", chapter: chapter) }
        return (target.href as NSString).lastPathComponent + fragment
    }
    func validateFragments() throws {
        let anchors = try documents.map { doc in Set(try doc.select("[id]").map { try $0.attr("id") }) }
        for (index, doc) in documents.enumerated() {
            for node in try doc.select("a[href]") {
                let href = try node.attr("href")
                if href.contains(":") { continue } // Explicit external hyperlinks only.
                let parts = href.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
                let target = parts[0].isEmpty ? index : map.chapters.firstIndex { ($0.href as NSString).lastPathComponent == parts[0] }
                guard let target else { try node.removeAttr("href"); loss("link-removed", href, chapter: index); continue }
                if parts.count > 1, !parts[1].isEmpty {
                    let id = String(parts[1]).removingPercentEncoding ?? String(parts[1])
                    if !anchors[target].contains(id) {
                        try node.attr("href", (map.chapters[target].href as NSString).lastPathComponent)
                        loss("fragment-missing", "锚点丢失，链接退化到目标章首：\(href)", chapter: index)
                    }
                }
            }
        }
    }
}
