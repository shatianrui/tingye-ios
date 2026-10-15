import Foundation
import CoreFoundation
import PDFKit
import ZIPFoundation

enum BookImporter {
    struct Imported: Sendable { let book: Book; var progress = ReadingProgress() }
    static func read(_ url: URL) throws -> Imported {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 100 * 1024 * 1024 else { throw ReaderError.message("文件超过 100 MB，请拆分导入。") }
        let title = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension.lowercased()
        if ext == "epub" { return Imported(book: try epub(url).validated()) }
        if ext == "docx" { return Imported(book: try docx(url, title: title).validated()) }
        if ["mobi", "azw", "azw3", "prc"].contains(ext) { return Imported(book: try MobiReader.book(url, fallbackTitle: title).validated()) }
        if ["cbz", "zip"].contains(ext) { return Imported(book: try ComicImporter.book(url, title: title).validated()) }
        let data = try Data(contentsOf: url)
        if ext == "pdf" {
            guard data.count <= 22 * 1024 * 1024, let document = PDFDocument(data: data), !document.isLocked, document.pageCount > 0 else { throw ReaderError.message("PDF 无法读取、已加密或超过 22 MB。") }
            let chapters = (0..<document.pageCount).map { Chapter(title: "第 \($0 + 1) 页", text: document.page(at: $0)?.string ?? "") }
            return Imported(book: try Book(title: title, format: "PDF", chapters: chapters, extras: ["pdf": .string(data.base64EncodedString())]).validated())
        }
        if ext == "json" {
            if let packet = try? JSONDecoder().decode(BackupPacket.self, from: data) {
                let valid = try packet.validated(id: packet.book.id)
                return Imported(book: valid.book, progress: valid.progress)
            }
            return Imported(book: try JSONDecoder().decode(Book.self, from: data).validated())
        }
        let text = try decode(data)
        let chapters: [Chapter]
        if ["html", "htm", "xhtml"].contains(ext) { chapters = [HTMLText.chapter(text, title: title)] }
        // Markdown 的原书图文由正文同源生成，保证开关原书图文时句级高亮与进度一致。
        else if ["md", "markdown"].contains(ext) { chapters = splitText(markdown(text), title: title).map(withOriginalDocument) }
        else if ["txt", "text", ""].contains(ext) { chapters = splitText(text, title: title) }
        else { throw ReaderError.message("支持 EPUB、MOBI、AZW3、TXT、PDF、HTML、Markdown、DOCX、CBZ 和听页备份 JSON。") }
        guard chapters.contains(where: { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { throw ReaderError.message("未找到可阅读的文字。") }
        return Imported(book: try Book(title: title, format: ext.uppercased(), chapters: chapters).validated())
    }
    static func decode(_ data: Data) throws -> String {
        if let text = String(data: data, encoding: .utf8) { return normalize(text) }
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]), let text = String(data: data, encoding: .utf16) { return normalize(text) }
        let gb = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        if let text = String(data: data, encoding: gb) { return normalize(text) }
        throw ReaderError.message("文字编码无法识别，请保存为 UTF-8 后重新导入。")
    }
    static func normalize(_ text: String) -> String { text.replacingOccurrences(of: "\u{FEFF}", with: "").replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n") }
    private static let headingRegex = try! NSRegularExpression(pattern: #"(?m)^(?:第[零〇一二三四五六七八九十百千万两\d]+[章回卷部篇节].{0,65}|Chapter\s+\d+.{0,65}|#{1,3}\s+.{1,65})$"#, options: [.caseInsensitive])
    private static let linkRegex = try! NSRegularExpression(pattern: #"(?i)<link\b[^>]*href\s*=\s*["']([^"']+)["'][^>]*>"#)
    static func splitText(_ source: String, title: String) -> [Chapter] {
        let text = normalize(source)
        let ns = text as NSString
        let headings = headingRegex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !headings.isEmpty else { return [Chapter(title: title, text: text)] }
        var chapters: [Chapter] = []
        if headings[0].range.location > 0 {
            let preface = ns.substring(to: headings[0].range.location).trimmingCharacters(in: .whitespacesAndNewlines)
            if !preface.isEmpty { chapters.append(Chapter(title: "卷首", text: preface)) }
        }
        for (i, heading) in headings.enumerated() {
            let end = i + 1 < headings.count ? headings[i + 1].range.location : ns.length
            let start = NSMaxRange(heading.range)
            chapters.append(Chapter(title: ns.substring(with: heading.range).replacingOccurrences(of: #"^#+\s*"#, with: "", options: .regularExpression), text: ns.substring(with: NSRange(location: start, length: end - start)).trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        return chapters
    }
    static func markdown(_ source: String) -> String {
        // Native semantic text; links remain readable and embedded HTML never executes.
        var text = source.replacingOccurrences(of: #"\A(?:\uFEFF)?---\s*\n[\s\S]*?\n(?:---|\.\.\.)\s*(?:\n|$)"#, with: "", options: .regularExpression)
        for (pattern, template) in [(#"!\[([^\]]*)\]\([^)]*\)"#, "$1"), (#"\[([^\]]+)\]\([^)]*\)"#, "$1"), (#"(?m)^\s*```[^\n]*\n?"#, ""), (#"\*\*(.*?)\*\*"#, "$1"), (#"`([^`]+)`"#, "$1"), (#"(?m)^>\s?"#, "")] { text = text.replacingOccurrences(of: pattern, with: template, options: .regularExpression) }
        return text
    }
    /// 给章节补上与正文同源的原书图文（Markdown 等没有出版物 HTML 的格式）。
    private static func withOriginalDocument(_ chapter: Chapter) -> Chapter {
        var chapter = chapter
        var document = chapter.fields["document"]?.object ?? [:]
        document["html"] = .string(OriginalDocument.fromText(chapter.text))
        document["css"] = .string("")
        document["path"] = .string("")
        chapter.fields["document"] = .object(document)
        return chapter
    }
    static func resolve(base: String, href: String) throws -> String {
        guard !href.hasPrefix("/"), !href.contains(":"), !href.contains("\\"), let decoded = href.components(separatedBy: CharacterSet(charactersIn: "?#")).first?.removingPercentEncoding else { throw ReaderError.message("EPUB 资源路径无效。") }
        var parts = base.split(separator: "/").dropLast().map(String.init)
        for part in decoded.split(separator: "/") {
            if part == ".." { guard !parts.isEmpty else { throw ReaderError.message("EPUB 资源路径越界。") }; parts.removeLast() }
            else if part != "." { parts.append(String(part)) }
        }
        return parts.joined(separator: "/")
    }
    private static func epub(_ url: URL) throws -> Book {
        let zip = try SafeArchive(url: url)
        let container = try XMLNode.parse(zip.data("META-INF/container.xml"))
        guard let path = container.descendants("rootfile").first?.attributes["full-path"], !path.hasPrefix("/"), !path.split(separator: "/").contains("..") else { throw ReaderError.message("EPUB 缺少书籍目录。") }
        let opf = try XMLNode.parse(zip.data(path))
        let title = opf.descendants("title").first?.allText.trimmingCharacters(in: .whitespacesAndNewlines) ?? url.deletingPathExtension().lastPathComponent
        let author = opf.descendants("creator").first?.allText ?? "佚名"
        let items = opf.descendants("item")
        var manifest: [String: XMLNode] = [:]
        for item in items { if let id = item.attributes["id"] { manifest[id] = item } }
        var resources: [String: JSONValue] = [:], imagePaths: [String: String] = [:]
        var cover: String?
        let coverID = opf.descendants("meta").first(where: { $0.attributes["name"] == "cover" })?.attributes["content"]
        for item in items {
            guard let type = item.attributes["media-type"], ["image/png", "image/jpeg", "image/gif", "image/webp"].contains(type), let href = item.attributes["href"] else { continue }
            let resourcePath = try resolve(base: path, href: href)
            let bytes = try zip.data(resourcePath)
            let key = "r\(resources.count)"
            resources[key] = .string("data:\(type);base64," + bytes.base64EncodedString()); imagePaths[resourcePath] = key
            if item.attributes["properties"]?.contains("cover-image") == true || item.attributes["id"] == coverID { cover = "tingye-resource:" + key }
        }
        var cssFiles: [String: String] = [:]
        for item in items where item.attributes["media-type"] == "text/css" {
            if let href = item.attributes["href"] { let cssPath = try resolve(base: path, href: href); cssFiles[cssPath] = try decode(zip.data(cssPath)) }
        }
        var chapters: [Chapter] = []
        for ref in opf.descendants("itemref") where ref.attributes["linear"] != "no" {
            guard let id = ref.attributes["idref"], let item = manifest[id], let href = item.attributes["href"] else { continue }
            let chapterPath = try resolve(base: path, href: href)
            let html = try decode(zip.data(chapterPath))
            var chapter = HTMLText.chapter(html, title: "第 \(chapters.count + 1) 章")
            let images = HTMLText.imageSources(html).compactMap { href -> JSONValue? in
                guard let path = try? resolve(base: chapterPath, href: href), let key = imagePaths[path] else { return nil }
                return .string("tingye-resource:" + key)
            }
            chapter.fields["nativeImages"] = .array(images)
            let original = HTMLText.replacingImageSources(in: html) { source in
                guard let resourcePath = try? resolve(base: chapterPath, href: source), let key = imagePaths[resourcePath] else { return nil }
                return "tingye-resource:" + key
            }
            var styles = ""
            for match in linkRegex.matches(in: html, range: NSRange(location: 0, length: html.utf16.count)) {
                let href = (html as NSString).substring(with: match.range(at: 1))
                if let target = try? resolve(base: chapterPath, href: href), let css = cssFiles[target] { styles += css + "\n" }
            }
            chapter.fields["document"] = .object(["html": .string(OriginalDocument.sanitized(original)), "css": .string(styles), "path": .string(chapterPath)])
            if !chapter.text.isEmpty || !images.isEmpty { chapters.append(chapter) }
        }
        guard !chapters.isEmpty else { throw ReaderError.message("EPUB 未找到可阅读章节；不支持 DRM 加密书籍。") }
        var extras: [String: JSONValue] = ["resources": .object(resources), "description": .string(opf.descendants("description").first?.allText ?? ""), "category": .string(opf.descendants("subject").first?.allText ?? "其他")]
        if let cover { extras["cover"] = .string(cover) }
        return Book(title: title, author: author, format: "EPUB", chapters: chapters, extras: extras)
    }
    private static func docx(_ url: URL, title: String) throws -> Book {
        let zip = try SafeArchive(url: url)
        let document = try XMLNode.parse(zip.data("word/document.xml"))
        var text = ""
        for p in document.descendants("p") {
            let content = p.descendants("t").map(\.allText).joined()
            if !content.isEmpty { text += content + "\n\n" }
        }
        guard !text.isEmpty else { throw ReaderError.message("DOCX 中未找到文字。") }
        return Book(title: title, format: "DOCX", chapters: splitText(text, title: title))
    }
}

final class SafeArchive {
    let archive: Archive
    var extracted = 0
    init(url: URL) throws {
        archive = try Archive(url: url, accessMode: .read)
        var count = 0, total: UInt64 = 0
        for entry in archive {
            count += 1; total += entry.uncompressedSize
            guard count <= 20_000, total <= 130 * 1024 * 1024 else { throw ReaderError.message("压缩书籍解压后过大。") }
        }
    }
    func data(_ path: String) throws -> Data {
        guard let entry = archive[path], entry.type == .file, entry.uncompressedSize <= 30 * 1024 * 1024 else { throw ReaderError.message("压缩书籍缺少资源或单个资源过大：\(path)") }
        var data = Data()
        _ = try archive.extract(entry) { chunk in
            guard self.extracted + chunk.count <= 130 * 1024 * 1024 else { throw ReaderError.message("书籍资源超过大小限制。") }
            self.extracted += chunk.count; data.append(chunk)
        }
        return data
    }
}

private final class XMLNode: NSObject, XMLParserDelegate {
    var name = ""
    var attributes: [String: String] = [:]
    var children: [XMLNode] = []
    var text = ""
    private var stack: [XMLNode] = []
    var allText: String { text + children.map(\.allText).joined() }
    func descendants(_ name: String) -> [XMLNode] { children.flatMap { ($0.name == name ? [$0] : []) + $0.descendants(name) } }
    static func parse(_ data: Data) throws -> XMLNode {
        let root = XMLNode(), parser = XMLParser(data: data)
        root.stack = [root]; parser.delegate = root; parser.shouldResolveExternalEntities = false
        guard parser.parse() else { throw ReaderError.message("书籍目录 XML 无法解析。") }
        root.stack = []; return root
    }
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        let node = XMLNode(); node.name = elementName.components(separatedBy: ":").last ?? elementName; node.attributes = attributeDict
        stack.last?.children.append(node); stack.append(node)
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { stack.last?.text += string }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) { if stack.count > 1 { stack.removeLast() } }
}

enum HTMLText {
    private static let tokenRegex = try! NSRegularExpression(pattern: #"<[^>]*>|[^<]+"#)
    private static let imgSrcRegex = try! NSRegularExpression(pattern: #"(?i)<img\b[^>]*\bsrc\s*=\s*["']([^"']+)["']"#)
    private static let entityRegex = try! NSRegularExpression(pattern: #"&#(x[0-9a-fA-F]+|[0-9]+);"#)
    static func chapter(_ source: String, title fallback: String) -> Chapter {
        // 机器还原的译文 EPUB 常插入大量「原文链接」回链，属转换残留，导入时剔除。
        let cleaned = source.replacingOccurrences(of: #"(?is)<a\b[^>]*class\s*=\s*["'][^"']*restored-source-link[^"']*"[^>]*>.*?</a\s*>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)<(script|style|head|nav|noscript)\b[^>]*>.*?</\1\s*>|<!--.*?-->"#, with: "", options: .regularExpression)
        let ns = cleaned as NSString
        var text = "", title = fallback, marks: [JSONValue] = [], stack: [(String, Int)] = []
        var headingStart: Int?
        for match in tokenRegex.matches(in: cleaned, range: NSRange(location: 0, length: ns.length)) {
            let token = ns.substring(with: match.range)
            if token.hasPrefix("<") {
                let tag = token.lowercased().replacingOccurrences(of: #"^</?\s*|[\s/>].*$"#, with: "", options: .regularExpression)
                let close = token.hasPrefix("</")
                if ["p", "div", "section", "article", "blockquote", "li", "h1", "h2", "h3", "h4", "br", "tr"].contains(tag), !text.isEmpty, !text.hasSuffix("\n") { text += "\n" }
                if ["h1", "h2", "h3"].contains(tag) {
                    if close, let start = headingStart, title == fallback { title = (text as NSString).substring(from: start).trimmingCharacters(in: .whitespacesAndNewlines); headingStart = nil }
                    else if !close { headingStart = text.utf16.count }
                }
                if ["b", "strong", "i", "em"].contains(tag) {
                    if close, let index = stack.lastIndex(where: { $0.0 == tag }) {
                        let start = stack.remove(at: index).1
                        if text.utf16.count > start { marks.append(.object(["start": .number(Double(start)), "end": .number(Double(text.utf16.count)), "bold": .bool(tag == "b" || tag == "strong"), "italic": .bool(tag == "i" || tag == "em")])) }
                    } else if !close { stack.append((tag, text.utf16.count)) }
                }
            } else { text += entities(token.replacingOccurrences(of: #"[\t\r\n ]+"#, with: " ", options: .regularExpression)) }
        }
        return Chapter(title: String(title.prefix(200)), text: text, extras: ["marks": .array(marks), "document": .object(["html": .string(OriginalDocument.sanitized(source)), "css": .string("")])])
    }
    static func imageSources(_ html: String) -> [String] {
        imgSrcRegex.matches(in: html, range: NSRange(location: 0, length: html.utf16.count)).map { (html as NSString).substring(with: $0.range(at: 1)) }
    }
    /// 仅替换 `<img>` 标签内的 `src` 属性值，避免短文件名（如 `1.jpg`）误替换正文或其他属性。
    static func replacingImageSources(in html: String, transform: (String) -> String?) -> String {
        var output = html
        for match in imgSrcRegex.matches(in: html, range: NSRange(location: 0, length: html.utf16.count)).reversed() {
            let srcRange = match.range(at: 1)
            let source = (html as NSString).substring(with: srcRange)
            if let replacement = transform(source), let range = Range(srcRange, in: output) {
                output.replaceSubrange(range, with: replacement)
            }
        }
        return output
    }
    static func entities(_ source: String) -> String {
        var text = source
        for match in entityRegex.matches(in: text, range: NSRange(location: 0, length: text.utf16.count)).reversed() {
            let raw = (text as NSString).substring(with: match.range(at: 1))
            if let code = UInt32(raw.hasPrefix("x") ? String(raw.dropFirst()) : raw, radix: raw.hasPrefix("x") ? 16 : 10), let scalar = UnicodeScalar(code), let range = Range(match.range, in: text) { text.replaceSubrange(range, with: String(scalar)) }
        }
        for (entity, value) in [("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&apos;", "'"), ("&amp;", "&")] { text = text.replacingOccurrences(of: entity, with: value) }
        return text
    }
}
