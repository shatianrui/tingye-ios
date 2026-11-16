import Foundation
import ReadiumShared
import SwiftSoup

/// Display-only transform. The disabled path returns the upstream container and bytes unchanged.
/// Never transforms markup, attributes, source.epub, or Book.text.
enum EPUBTextTransform {
    static func enabled(_ mode: String) -> Bool { mode == "s2t" || mode == "t2s" }
    static func mapping(_ text: String, mode: String) -> TextOffsetMap {
        guard enabled(mode) else { return TextOffsetMap(text) }
        let transform = StringTransform(mode == "s2t" ? "Hans-Hant" : "Hant-Hans")
        let display = text.applyingTransform(transform, reverse: false) ?? text
        let template = TextOffsetMap(text, transform: { $0.applyingTransform(transform, reverse: false) ?? $0 })
        if template.sourceRanges.count == display.utf16.count {
            return TextOffsetMap(text: display, sourceRanges: template.sourceRanges)
        }
        return TextOffsetMap.aligning(text, display: display)
    }
    static func transform(xhtml: Data, mode: String, isXHTML: Bool = true) throws -> Data {
        guard enabled(mode) else { return xhtml }
        guard xhtml.count <= 4 * 1024 * 1024, let source = String(data: xhtml, encoding: .utf8) else {
            throw ReaderError.message("EPUB 显示转换资源过大或编码无效。")
        }
        let document: SwiftSoup.Document
        if isXHTML { document = try SwiftSoup.parseXML(source) }
        else { document = try SwiftSoup.parse(source) }
        func visit(_ element: Element) throws {
            if ["head", "script", "style", "noscript", "nav"].contains(element.tagName().lowercased()) { return }
            for child in element.getChildNodes() {
                if let text = child as? TextNode { _ = text.text(mapping(text.getWholeText(), mode: mode).text) }
                else if let element = child as? Element { try visit(element) }
            }
        }
        if let body = document.body() { try visit(body) }
        _ = document.outputSettings().syntax(syntax: .xml).escapeMode(.xhtml).prettyPrint(pretty: false)
        return Data(try document.outerHtml().utf8)
    }
    static func container(_ upstream: ReadiumShared.Container, mode: String, mediaTypes: [String: String] = [:]) -> ReadiumShared.Container {
        guard enabled(mode) else { return upstream }
        return TransformingContainer(container: upstream) { href, resource in
            let path = href.string.lowercased().components(separatedBy: "?")[0]
            let mime = mediaTypes[PublicationMap.normalized(href.string) ?? href.string]
            guard mime == "application/xhtml+xml" || mime == "text/html" || path.hasSuffix(".xhtml") || path.hasSuffix(".html") || path.hasSuffix(".htm") else { return resource }
            let isXHTML = mime.map { $0 != "text/html" } ?? path.hasSuffix(".xhtml")
            return TransformingResource(resource) { result in
                switch result {
                case .failure(let error): return .failure(error)
                case .success(let data):
                    do { return .success(try transform(xhtml: data, mode: mode, isXHTML: isXHTML)) }
                    catch { return .failure(.decoding(error)) }
                }
            }
        }
    }
}
