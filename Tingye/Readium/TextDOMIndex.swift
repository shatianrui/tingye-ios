import Foundation
import SwiftSoup

/// UTF-16 half-open ranges. Every emitted code unit retains its source grapheme's range.
/// The same mapping is used for DOM alignment and display-only Chinese conversion.
struct TextOffsetMap: Sendable {
    let text: String
    let sourceRanges: [NSRange]
    init(_ source: String, transform: (String) -> String = { $0 }, omitWhitespace: Bool = false) {
        var output = "", ranges: [NSRange] = [], offset = 0
        for character in source {
            let input = String(character), range = NSRange(location: offset, length: input.utf16.count)
            offset += range.length
            let transformed = transform(input)
            for scalar in transformed.unicodeScalars {
                if omitWhitespace && (CharacterSet.whitespacesAndNewlines.contains(scalar) || scalar.value == 0x200B) { continue }
                let value = String(scalar)
                output += value
                ranges.append(contentsOf: repeatElement(range, count: value.utf16.count))
            }
        }
        text = output; sourceRanges = ranges
    }
    init(text: String, sourceRanges: [NSRange]) {
        self.text = text; self.sourceRanges = sourceRanges
    }
    /// Align length-changing replacement blocks using nearby unchanged graphemes.
    /// A block's interior has no invented one-to-one boundaries: partial selections are rejected below.
    static func aligning(_ source: String, display: String) -> TextOffsetMap {
        let a = source.map(String.init), b = display.map(String.init)
        var ranges: [NSRange] = [], offset = 0
        for value in a { ranges.append(NSRange(location: offset, length: value.utf16.count)); offset += value.utf16.count }
        var output: [NSRange] = [], i = 0, j = 0
        func append(_ range: NSRange, from: Int, to: Int) {
            for k in from..<to { output.append(contentsOf: repeatElement(range, count: b[k].utf16.count)) }
        }
        while i < a.count && j < b.count {
            if a.count - i == b.count - j || a[i] == b[j] {
                append(ranges[i], from: j, to: j + 1); i += 1; j += 1; continue
            }
            var anchor: (Int, Int)?
            for distance in 1...64 {
                for da in 0...distance {
                    let db = distance - da
                    if i + da < a.count, j + db < b.count, a[i + da] == b[j + db] {
                        anchor = (i + da, j + db); break
                    }
                }
                if anchor != nil { break }
            }
            let endA = anchor?.0 ?? a.count, endB = anchor?.1 ?? b.count
            let first = ranges[min(i, ranges.count - 1)]
            let last = ranges[max(i, endA - 1)]
            append(NSRange(location: first.location, length: NSMaxRange(last) - first.location), from: j, to: endB)
            i = endA; j = endB
        }
        if j < b.count {
            let last = ranges.last ?? NSRange(location: 0, length: source.utf16.count)
            append(last, from: j, to: b.count)
        }
        return TextOffsetMap(text: display, sourceRanges: output)
    }
    func mapsBoundary(_ offset: Int) -> Bool {
        guard offset >= 0, offset <= sourceRanges.count else { return false }
        return offset == 0 || offset == sourceRanges.count || sourceRanges[offset - 1] != sourceRanges[offset]
    }
    func sourceRange(_ range: NSRange) -> NSRange? {
        guard range.location >= 0, range.length > 0, range.location < sourceRanges.count,
              range.length <= sourceRanges.count - range.location else { return nil }
        let first = sourceRanges[range.location], last = sourceRanges[NSMaxRange(range) - 1]
        return NSRange(location: first.location, length: NSMaxRange(last) - first.location)
    }
    func outputRange(_ range: NSRange) -> NSRange? {
        guard range.location >= 0, range.length > 0,
              let first = sourceRanges.firstIndex(where: { NSMaxRange($0) > range.location }),
              let last = sourceRanges.lastIndex(where: { $0.location < NSMaxRange(range) }), first <= last else { return nil }
        return NSRange(location: first, length: last - first + 1)
    }
    static func normalized(_ text: String) -> String { TextOffsetMap(text, omitWhitespace: true).text }
}

struct TextDOMIndex: Sendable {
    struct Point: Equatable, Sendable {
        let cssSelector: String
        let textNodeIndex: Int
        let charOffset: Int
        var json: JSONValue { .object(["cssSelector": .string(cssSelector), "textNodeIndex": .number(Double(textNodeIndex)), "charOffset": .number(Double(charOffset))]) }
    }
    struct Span: Equatable, Sendable {
        let start: Point
        let end: Point
        var json: JSONValue { .object(["start": start.json, "end": end.json]) }
    }
    struct NodeText: Sendable {
        let selector: String
        let index: Int
        let range: NSRange
        let text: String
    }
    let native: String
    let domText: String
    let nativeMap: TextOffsetMap
    let domMap: TextOffsetMap
    let nodes: [NodeText]
    private let html: String
    private let isXHTML: Bool
    var memoryCost: Int { (native.utf16.count + domText.utf16.count) * 36 + html.utf8.count }

    init(native: String, xhtml: String, isXHTML: Bool = true) throws {
        self.native = native; html = xhtml; self.isXHTML = isXHTML
        let document: SwiftSoup.Document
        if isXHTML { document = try SwiftSoup.parseXML(xhtml) }
        else { document = try SwiftSoup.parse(xhtml) }
        var nodes: [NodeText] = [], joined = ""
        func visit(_ element: Element) {
            if ["head", "script", "style", "noscript", "nav"].contains(element.tagName().lowercased()) { return }
            var textIndex = 0
            for child in element.getChildNodes() {
                if let text = child as? TextNode {
                    let value = text.getWholeText()
                    nodes.append(NodeText(selector: Self.selector(element), index: textIndex,
                                          range: NSRange(location: joined.utf16.count, length: value.utf16.count), text: value))
                    joined += value; textIndex += 1
                } else if let element = child as? Element { visit(element) }
            }
        }
        if let body = document.body() { visit(body) }
        guard native.utf16.count + joined.utf16.count <= 350_000 else { throw ReaderError.message("本资源文本超过 DOM 索引预算。") }
        self.nodes = nodes; domText = joined
        nativeMap = TextOffsetMap(native, omitWhitespace: true)
        domMap = TextOffsetMap(joined, omitWhitespace: true)
    }
    private func parsed() throws -> Document {
        if isXHTML { return try SwiftSoup.parseXML(html) }
        return try SwiftSoup.parse(html)
    }
    static func selector(_ element: Element) -> String {
        let tag = element.tagName().lowercased()
        guard let parent = element.parent() else { return tag }
        if tag == "html" || tag == "body" { return tag }
        let peers = parent.children().array().filter { $0.tagName() == element.tagName() }
        let ordinal = (peers.firstIndex(where: { $0 === element }) ?? 0) + 1
        return selector(parent) + " > " + tag + ":nth-of-type(\(ordinal))"
    }
    /// Full normalized quote matching with actual context, never a truncated highlight range.
    static func matches(_ quote: String, in text: String, before: String? = nil, after: String? = nil,
                        preferred: Int? = nil) -> NSRange? {
        let needle = TextOffsetMap.normalized(quote), source = text as NSString
        guard !needle.isEmpty, needle.utf16.count <= source.length else { return nil }
        let prefix = before.map(TextOffsetMap.normalized) ?? "", suffix = after.map(TextOffsetMap.normalized) ?? ""
        var cursor = 0, hits: [(NSRange, Int)] = []
        while cursor < source.length, hits.count < 256 {
            let hit = source.range(of: needle, range: NSRange(location: cursor, length: source.length - cursor))
            if hit.location == NSNotFound { break }
            var score = 0
            if !prefix.isEmpty, source.substring(to: hit.location).hasSuffix(prefix) { score += 2 }
            if !suffix.isEmpty, source.substring(from: NSMaxRange(hit)).hasPrefix(suffix) { score += 2 }
            if let preferred, hit.location == preferred { score += 1 }
            hits.append((hit, score)); cursor = hit.location + 1
        }
        guard hits.count < 256 else { return nil }
        let best = hits.sorted { $0.1 > $1.1 }
        guard let first = best.first, best.count == 1 || first.1 > best[1].1 else { return nil }
        return first.0
    }
    func domRange(for nativeRange: NSRange, before: String? = nil, after: String? = nil) -> NSRange? {
        guard let normal = nativeMap.outputRange(nativeRange),
              let quoteRange = nativeMap.sourceRange(normal) else { return nil }
        let quote = (native as NSString).substring(with: quoteRange)
        let preferred = nativeMap.text == domMap.text ? normal.location : nil
        guard let match = Self.matches(quote, in: domMap.text, before: before, after: after, preferred: preferred) else { return nil }
        return domMap.sourceRange(match)
    }
    func nativeRange(quote: String, before: String?, after: String?, preferred: Int? = nil) -> NSRange? {
        let offset = preferred.flatMap { nativeMap.outputRange(NSRange(location: $0, length: 1))?.location }
        guard let hit = Self.matches(quote, in: nativeMap.text, before: before, after: after, preferred: offset) else { return nil }
        return nativeMap.sourceRange(hit)
    }
    func span(_ range: NSRange, mode: String = "none") -> Span? {
        guard range.length > 0, let start = point(at: range.location, end: false, mode: mode),
              let end = point(at: NSMaxRange(range), end: true, mode: mode), start != end else { return nil }
        return Span(start: start, end: end)
    }
    private func point(at offset: Int, end: Bool, mode: String) -> Point? {
        let candidates = nodes.filter { end ? ($0.range.location < offset && offset <= NSMaxRange($0.range)) : ($0.range.location <= offset && offset < NSMaxRange($0.range)) }
        guard let node = candidates.first else { return nil }
        let local = offset - node.range.location
        let displayOffset: Int
        if !EPUBTextTransform.enabled(mode) { displayOffset = local }
        else {
            let mapped = EPUBTextTransform.mapping(node.text, mode: mode)
            if mapped.sourceRanges.contains(where: { $0.location < local && local < NSMaxRange($0) }) { return nil }
            if end { displayOffset = mapped.sourceRanges.prefix { $0.location < local }.count }
            else { displayOffset = mapped.sourceRanges.firstIndex { NSMaxRange($0) > local } ?? mapped.text.utf16.count }
        }
        return Point(cssSelector: node.selector, textNodeIndex: node.index, charOffset: displayOffset)
    }
    /// Decode Readium's DOM range by resolving its CSS selector against the original DOM.
    func range(from span: JSONValue, mode: String = "none") -> NSRange? {
        func offset(_ value: JSONValue?) -> Int? {
            guard let object = value?.object, let css = object["cssSelector"]?.string,
                  let index = StoredLocator.integer(object["textNodeIndex"]), index >= 0,
                  let charOffset = StoredLocator.integer(object["charOffset"] ?? object["offset"]), charOffset >= 0 else { return nil }
            var selector = css
            if !nodes.contains(where: { $0.selector == css }) {
                guard let doc = try? parsed(), let element = try? doc.select(css).first() else { return nil }
                selector = Self.selector(element)
            }
            guard let node = nodes.first(where: { $0.selector == selector && $0.index == index }) else { return nil }
            if mode == "none" { return charOffset <= node.range.length ? node.range.location + charOffset : nil }
            let map = EPUBTextTransform.mapping(node.text, mode: mode)
            guard charOffset <= map.sourceRanges.count else { return nil }
            if charOffset > 0, charOffset < map.sourceRanges.count,
               map.sourceRanges[charOffset - 1] == map.sourceRanges[charOffset] { return nil }
            return node.range.location + (charOffset == map.sourceRanges.count ? node.range.length : map.sourceRanges[charOffset].location)
        }
        guard let object = span.object, let start = offset(object["start"]),
              let end = offset(object["end"] ?? object["start"]), start < end else { return nil }
        return NSRange(location: start, length: end - start)
    }
    func firstTextRange(in selector: String) -> NSRange? {
        guard let document = try? parsed(), let element = try? document.select(selector).first() else { return nil }
        let path = Self.selector(element)
        guard let node = nodes.first(where: { ($0.selector == path || $0.selector.hasPrefix(path + " > ")) && !TextOffsetMap.normalized($0.text).isEmpty }),
              let sentence = Sentence.split(node.text).first else { return nil }
        return NSRange(location: node.range.location + sentence.range.location, length: sentence.range.length)
    }
    func textContext(_ range: NSRange) -> (quote: String, before: String, after: String) {
        let source = domText as NSString
        return (source.substring(with: range), String(source.substring(to: range.location).suffix(40)),
                String(source.substring(from: NSMaxRange(range)).prefix(40)))
    }
}
