import Foundation
import ReadiumShared

/// One target type for every entry point. The legacy Locator utility keeps its public name.
struct LocatorTarget: Equatable, Sendable {
    var chapter: Int
    var position: Int
    var textRange: NSRange? = nil
    var end: Int? = nil
    var text: String? = nil
    var anchor: TextAnchor? = nil
    var locator: JSONValue? = nil
    var publicationRevision: String? = nil
    init(chapter: Int, position: Int, end: Int? = nil, text: String? = nil, textRange: NSRange? = nil, anchor: TextAnchor? = nil,
         locator: JSONValue? = nil, publicationRevision: String? = nil) {
        self.chapter = chapter; self.position = position; self.end = end; self.text = text; self.textRange = textRange
        self.anchor = anchor; self.locator = locator; self.publicationRevision = publicationRevision
    }
    init(_ value: ReadingProgress) {
        self.init(chapter: value.chapter, position: value.position, text: value.locator?.object?["text"]?.object?["highlight"]?.string, anchor: value.anchor, locator: value.locator, publicationRevision: value.publicationRevision)
    }
    init(_ value: Bookmark) {
        self.init(chapter: value.chapter, position: value.position, text: value.excerpt, anchor: value.anchor, locator: value.locator, publicationRevision: value.publicationRevision)
    }
    init(_ value: Highlight) {
        self.init(chapter: value.chapter, position: value.start, end: value.end, text: value.text, anchor: value.anchor, locator: value.locator, publicationRevision: value.publicationRevision)
    }
}

enum LocatorResolution: String, Codable, Sendable { case exact, textRelocated, approximate, unresolved }
struct LocatorResult: Sendable {
    let target: LocatorTarget
    let locator: JSONValue?
    let revision: String
    let status: LocatorResolution
    let confidence: Double
    var precise: Bool { status == .exact || status == .textRelocated }
}

/// Resource-local indexes are evicted LRU; publications and source bytes are never modified.
@MainActor
final class LocatorBridge {
    static let version = 1
    let book: Book
    let map: PublicationMap?
    let publication: Publication?
    let revision: String
    private var indexes: [String: TextDOMIndex] = [:]
    private var order: [String] = []
    private var cost = 0
    private var relocatedResources: [String: Int] = [:]
    private let memoryLimit = 16 * 1024 * 1024
    private let searchLimit = 8 * 1024 * 1024
    init(book: Book, map: PublicationMap? = nil, publication: Publication? = nil, publicationRevision: String? = nil) throws {
        self.book = book; self.map = map; self.publication = publication
        if let publicationRevision { revision = publicationRevision }
        else if let map { revision = map.publicationRevision }
        else if book.format.uppercased() == "EPUB" { revision = try PublicationMap.revision(for: book) }
        else { revision = try Self.logicalRevision(for: book) }
    }
    nonisolated static func logicalRevision(for book: Book) throws -> String {
        let hash = try PublicationMap.contentHash(for: book)
        let pdf = book.fields["pdf"]?.string.map { PublicationDigest.data(Data($0.utf8)) } ?? ""
        return "logical-v1-" + PublicationDigest.data(Data((hash + pdf).utf8))
    }
    private func result(_ target: LocatorTarget, _ json: JSONValue?, _ status: LocatorResolution) -> LocatorResult {
        LocatorResult(target: target, locator: json, revision: revision, status: status,
                      confidence: status == .exact ? 1 : status == .textRelocated ? 0.9 : status == .approximate ? 0.25 : 0)
    }
    private func index(chapter: Int, href: String) async throws -> TextDOMIndex {
        let key = "\(chapter):\(href)"
        if let cached = indexes[key] {
            order.removeAll { $0 == key }; order.append(key); return cached
        }
        guard let publication, let link = (publication.readingOrder + publication.resources).first(where: { PublicationMap.normalized($0.href) == PublicationMap.normalized(href) }),
              let resource = publication.get(link), book.chapters.indices.contains(chapter) else {
            throw ReaderError.message("定位资源不存在。")
        }
        if let length = try await resource.estimatedLength().get(), length > 4 * 1024 * 1024 {
            throw ReaderError.message("定位资源超过索引上限。")
        }
        let data = try await resource.read(range: 0..<UInt64(4 * 1024 * 1024 + 1)).get()
        guard data.count <= 4 * 1024 * 1024, let xhtml = String(data: data, encoding: .utf8) else {
            throw ReaderError.message("定位资源无法解码。")
        }
        let native = book.chapters[chapter].text
        let isXHTML = link.mediaType?.string != "text/html"
        let built = try await Task.detached(priority: .utility) { try TextDOMIndex(native: native, xhtml: xhtml, isXHTML: isXHTML) }.value
        try Task.checkCancellation()
        while cost + built.memoryCost > memoryLimit, let oldest = order.first {
            cost -= indexes.removeValue(forKey: oldest)?.memoryCost ?? 0; order.removeFirst()
        }
        if built.memoryCost <= memoryLimit { indexes[key] = built; order.append(key); cost += built.memoryCost }
        return built
    }
    nonisolated private static func range(_ target: LocatorTarget, book: Book) -> NSRange? {
        guard book.chapters.indices.contains(target.chapter) else { return nil }
        if let range = target.textRange, range.location >= 0, range.length > 0, NSMaxRange(range) <= book.chapters[target.chapter].text.utf16.count { return range }
        let sentences = Sentence.split(book.chapters[target.chapter].text)
        return ReaderMark.range(start: target.position, end: target.end ?? target.position, in: sentences)
    }
    /// Text layer first, then a bounded whole-book search only when the quoted text is absent locally.
    nonisolated static func textTarget(_ target: LocatorTarget, in book: Book) -> (LocatorTarget, Bool) {
        guard !book.chapters.isEmpty else { return (target, false) }
        var next = target
        let chapter = min(max(0, target.chapter), book.chapters.count - 1)
        let sentences = Sentence.split(book.chapters[chapter].text)
        let position = Locator.resolve(position: target.position, anchor: target.anchor, in: sentences)
        next.chapter = chapter; next.position = position
        if let end = target.end { next.end = min(max(position, position + max(0, end - target.position)), max(0, sentences.count - 1)) }
        let quote = target.end != nil ? target.text : target.anchor?.quote ?? target.text
        guard let quote, !quote.isEmpty else {
            let valid = target.chapter == chapter && target.position == position
                && (sentences.indices.contains(position) || sentences.isEmpty && position == 0)
            return (next, target.end == nil && valid)
        }
        func find(in chapter: Int, preferred: Int?) -> NSRange? {
            let text = book.chapters[chapter].text
            let normalized = TextOffsetMap(text, omitWhitespace: true)
            let expected = preferred.flatMap { index -> Int? in
                let s = Sentence.split(text)
                guard s.indices.contains(index) else { return nil }
                return normalized.outputRange(s[index].range)?.location
            }
            guard let hit = TextDOMIndex.matches(quote, in: normalized.text, before: target.anchor?.before,
                                                 after: target.end == nil ? target.anchor?.after : nil, preferred: expected) else { return nil }
            return normalized.sourceRange(hit)
        }
        func located(_ c: Int, _ range: NSRange) -> LocatorTarget {
            var value = target; let split = Sentence.split(book.chapters[c].text)
            if c != target.chapter { value.textRange = nil }
            value.chapter = c; value.position = Sentence.index(at: range.location, in: split)
            if target.end != nil { value.end = Sentence.index(at: NSMaxRange(range) - 1, in: split) }
            return value
        }
        if let hit = find(in: chapter, preferred: position) { return (located(chapter, hit), true) }
        // Ambiguous local matches must not be "resolved" by choosing an unrelated chapter.
        let local = TextOffsetMap.normalized(book.chapters[chapter].text)
        if local.contains(TextOffsetMap.normalized(quote)) { return (next, false) }
        var bytes = 0, hits: [LocatorTarget] = []
        for c in book.chapters.indices.prefix(512) where c != chapter {
            if Task.isCancelled { return (next, false) }
            bytes += book.chapters[c].text.utf16.count * 2
            if bytes > 8 * 1024 * 1024 { break }
            if let hit = find(in: c, preferred: nil) { hits.append(located(c, hit)) }
            if hits.count > 32 { return (next, false) }
        }
        if hits.count == 1 { return (hits[0], true) }
        if let title = target.locator?.object?["title"]?.string {
            let titled = hits.filter { book.chapters[$0.chapter].title == title }
            if titled.count == 1 { return (titled[0], true) }
        }
        return (next, false)
    }
    func resolve(_ target: LocatorTarget) async throws -> LocatorResult {
        try Task.checkCancellation()
        if target.publicationRevision == revision, let stored = StoredLocator.readium(target.locator) {
            let restored = try await reverse(stored, chapterHint: target.chapter)
            let completeRange = target.end == nil || target.text.map { TextOffsetMap.normalized($0) == TextOffsetMap.normalized(restored.target.text ?? "") } == true
            if restored.precise && completeRange || target.end == nil && restored.status == .approximate { return restored }
        }
        let textBook = book
        let search = Task.detached(priority: .utility) { Self.textTarget(target, in: textBook) }
        let (textTarget, matched) = await withTaskCancellationHandler(operation: { await search.value }, onCancel: { search.cancel() })
        try Task.checkCancellation()
        guard book.chapters.indices.contains(textTarget.chapter) else { return result(target, nil, .unresolved) }
        if book.format.uppercased() != "EPUB" {
            guard matched else { return result(target, nil, .unresolved) }
            let converted = logical(textTarget, matched: true)
            return result(converted.target, converted.locator, textTarget.chapter == target.chapter && textTarget.position == target.position && target.publicationRevision == nil ? .exact : .textRelocated)
        }
        guard let publication, let map else { return result(target, nil, .unresolved) }
        let mappedHref = map.href(for: textTarget.chapter)
        var href = mappedHref
        var selectedIndex: TextDOMIndex?
        var domRange: NSRange?
        if matched, let href, let nativeRange = Self.range(textTarget, book: book) {
            let index = try await self.index(chapter: textTarget.chapter, href: href)
            var range = nativeRange
            if target.end != nil, let text = target.text,
               let full = index.nativeRange(quote: text, before: target.anchor?.before, after: nil, preferred: range.location) { range = full }
            domRange = index.domRange(for: range, before: target.anchor?.before, after: target.end == nil ? target.anchor?.after : nil)
            selectedIndex = index
        }
        // A removed/missing resource may have moved in the spine. Never pair chapters by array index.
        if domRange == nil, matched, let nativeRange = Self.range(textTarget, book: book) {
            let quote = (book.chapters[textTarget.chapter].text as NSString).substring(with: nativeRange)
            var candidates: [(String, TextDOMIndex, NSRange)] = [], budget = 0
            for link in publication.readingOrder.prefix(64) where PublicationMap.normalized(link.href) != href.flatMap(PublicationMap.normalized) {
                try Task.checkCancellation()
                let idx = try await index(chapter: textTarget.chapter, href: link.href)
                budget += idx.domText.utf16.count * 2
                if budget > searchLimit { break }
                if let hit = TextDOMIndex.matches(quote, in: idx.domMap.text, before: target.anchor?.before, after: target.end == nil ? target.anchor?.after : nil),
                   let range = idx.domMap.sourceRange(hit) { candidates.append((link.href, idx, range)) }
                if candidates.count > 1 { break }
            }
            if candidates.count == 1 { href = candidates[0].0; selectedIndex = candidates[0].1; domRange = candidates[0].2 }
        }
        if let href, let index = selectedIndex, let range = domRange, let span = index.span(range),
           let link = (publication.readingOrder + publication.resources).first(where: { PublicationMap.normalized($0.href) == PublicationMap.normalized(href) }) {
            let context = index.textContext(range)
            var json = StoredLocator.json(ReadiumShared.Locator(href: link.url(), mediaType: link.mediaType ?? .xhtml, title: link.title,
                 locations: .init(progression: Double(range.location) / Double(max(1, index.domText.utf16.count))),
                 text: .init(after: context.after, before: context.before, highlight: context.quote)))?.object ?? [:]
            var locations = json["locations"]?.object ?? [:]
            locations["domRange"] = span.json
            locations["tingyeChapter"] = .number(Double(textTarget.chapter))
            if let key = PublicationMap.normalized(href) { relocatedResources[key] = textTarget.chapter }
            if let native = index.nativeRange(quote: context.quote, before: context.before, after: context.after,
                                              preferred: Self.range(textTarget, book: book)?.location) {
                locations["tingyeRange"] = Self.rangeJSON(native)
            }
            json["locations"] = .object(locations)
            var updated = textTarget
            updated.anchor = Locator.anchor(in: Sentence.split(book.chapters[updated.chapter].text), at: updated.position)
            let status: LocatorResolution = textTarget.chapter == target.chapter && textTarget.position == target.position && matched && target.publicationRevision == nil && PublicationMap.normalized(href) == mappedHref.flatMap(PublicationMap.normalized) ? .exact : .textRelocated
            return result(updated, .object(json), status)
        }
        if target.end != nil { return result(target, nil, .unresolved) }
        // Navigation-only fallback, never a Decoration or an exact migrated annotation.
        let oldHref = target.locator?.object?["href"]?.string
        if let link = publication.readingOrder.first(where: { PublicationMap.normalized($0.href) == (oldHref ?? href).flatMap(PublicationMap.normalized) }) {
            let storedProgress = target.locator?.object?["locations"]?.object?["progression"]
            let progression: Double
            if let storedProgress, case .number(let p) = storedProgress, p.isFinite { progression = min(1, max(0, p)) }
            else { progression = 0 }
            return result(textTarget, StoredLocator.json(ReadiumShared.Locator(href: link.url(), mediaType: link.mediaType ?? .xhtml,
                          locations: .init(progression: progression))), .approximate)
        }
        return result(target, nil, .unresolved)
    }
    static func rangeJSON(_ range: NSRange) -> JSONValue {
        .object(["start": .number(Double(range.location)), "end": .number(Double(NSMaxRange(range)))])
    }
    static func parseRange(_ raw: JSONValue?, length: Int) -> NSRange? {
        guard let object = raw?.object, let start = StoredLocator.integer(object["start"]), let end = StoredLocator.integer(object["end"]),
              start >= 0, end > start, end <= length else { return nil }
        return NSRange(location: start, length: end - start)
    }
    private func logical(_ target: LocatorTarget, matched: Bool) -> LocatorResult {
        if !matched { return result(target, nil, .unresolved) }
        let paged = book.isPDF || book.fields["comic"]?.bool == true
        let href = "tingye://book/\(book.id)/\(paged ? "page" : "chapter")/\(target.chapter)" + (book.isPDF ? "#page=\(target.chapter + 1)" : "")
        var locations: [String: JSONValue] = [:]
        if let range = Self.range(target, book: book) { locations["tingyeRange"] = Self.rangeJSON(range) }
        locations["tingyeSentence"] = .number(Double(target.position))
        let resource = book.chapters[target.chapter].nativeImageRefs?.first
        if let resource { locations["tingyeResource"] = .string(resource) }
        let imageMIME = resource.flatMap { ref -> String? in
            let key = ref.replacingOccurrences(of: "tingye-resource:", with: "")
            guard let raw = book.resourceMap[key]?.string, raw.hasPrefix("data:"), let end = raw.firstIndex(of: ";") else { return nil }
            return String(raw[raw.index(raw.startIndex, offsetBy: 5)..<end])
        } ?? "image/png"
        let type = book.isPDF ? "application/pdf" : book.fields["comic"]?.bool == true ? imageMIME : "text/plain"
        var raw: [String: JSONValue] = ["href": .string(href), "type": .string(type), "locations": .object(locations)]
        if let range = Self.range(target, book: book) {
            raw["text"] = .object(["highlight": .string((book.chapters[target.chapter].text as NSString).substring(with: range))])
        }
        var updated = target
        updated.anchor = Locator.anchor(in: Sentence.split(book.chapters[target.chapter].text), at: target.position) ?? target.anchor
        return result(updated, .object(raw), .exact)
    }
    func reverse(_ locator: ReadiumShared.Locator, chapterHint: Int? = nil, displayMode: String = "none") async throws -> LocatorResult {
        guard let raw = StoredLocator.json(locator)?.object else { return result(.init(chapter: chapterHint ?? 0, position: 0), nil, .unresolved) }
        let logicalPrefix = "tingye://book/\(book.id)/"
        let candidates: [Int]
        if locator.href.string.hasPrefix(logicalPrefix), book.format.uppercased() != "EPUB" {
            let tail = String(locator.href.string.dropFirst(logicalPrefix.count)).components(separatedBy: "#")[0].split(separator: "/")
            candidates = tail.count == 2 && ["chapter", "page"].contains(String(tail[0])) ? Int(tail[1]).map { [$0] } ?? [] : []
        } else {
            let mapped = map?.chapters.filter { PublicationMap.normalized($0.href) == PublicationMap.normalized(locator.href.string) }.map(\.chapterIndex) ?? []
            if !mapped.isEmpty { candidates = mapped }
            else if let key = PublicationMap.normalized(locator.href.string), let chapter = relocatedResources[key] { candidates = [chapter] }
            else if let chapter = raw["locations"]?.object?["tingyeChapter"]?.int { candidates = [chapter] }
            else if let quote = locator.text.highlight, !quote.isEmpty {
                var matches: [Int] = [], budget = 0
                for chapter in book.chapters.indices.prefix(512) {
                    try Task.checkCancellation()
                    budget += book.chapters[chapter].text.utf16.count * 2
                    if budget > searchLimit { break }
                    let shown = EPUBTextTransform.enabled(displayMode) ? EPUBTextTransform.mapping(book.chapters[chapter].text, mode: displayMode).text : book.chapters[chapter].text
                    if TextDOMIndex.matches(quote, in: TextOffsetMap.normalized(shown), before: locator.text.before, after: locator.text.after) != nil { matches.append(chapter) }
                    if matches.count > 8 { break }
                }
                candidates = matches
            } else { candidates = [] }
        }
        var precise: [LocatorResult] = []
        for chapter in candidates where book.chapters.indices.contains(chapter) {
            let text = book.chapters[chapter].text, sentences = Sentence.split(text)
            let locations = raw["locations"]?.object
            var range: NSRange?
            var originalQuote = locator.text.highlight
            var before = locator.text.before, after = locator.text.after
            var canonical = raw
            var originalDOMRange: NSRange?
            if book.format.uppercased() == "EPUB" {
                let idx = try await index(chapter: chapter, href: locator.href.string)
                if originalQuote == nil, let selector = locator.locations.cssSelector, let dom = idx.firstTextRange(in: selector) {
                    originalDOMRange = dom
                    let context = idx.textContext(dom)
                    originalQuote = context.quote; before = context.before; after = context.after
                }
                if let span = locations?["domRange"], let dom = idx.range(from: span, mode: displayMode) {
                    originalDOMRange = dom
                    let context = idx.textContext(dom)
                    originalQuote = context.quote; before = context.before; after = context.after
                } else if EPUBTextTransform.enabled(displayMode), let quote = locator.text.highlight {
                    let mapping = EPUBTextTransform.mapping(idx.domText, mode: displayMode)
                    let normal = TextOffsetMap(mapping.text, omitWhitespace: true)
                    if let hit = TextDOMIndex.matches(quote, in: normal.text, before: before, after: after),
                       let display = normal.sourceRange(hit), mapping.mapsBoundary(display.location), mapping.mapsBoundary(NSMaxRange(display)), let dom = mapping.sourceRange(display) {
                        let context = idx.textContext(dom)
                        originalQuote = context.quote; before = context.before; after = context.after
                    } else { continue }
                }
                if let quote = originalQuote {
                    let preferred = Self.parseRange(locations?["tingyeRange"], length: text.utf16.count)?.location
                    range = idx.nativeRange(quote: quote, before: before, after: after, preferred: preferred)
                    if let range, let dom = originalDOMRange ?? idx.domRange(for: range, before: before, after: after), let span = idx.span(dom) {
                        var loc = locations ?? [:]; loc["domRange"] = span.json; loc["tingyeRange"] = Self.rangeJSON(range)
                        loc["tingyeChapter"] = .number(Double(chapter))
                        canonical["locations"] = .object(loc)
                        canonical["text"] = .object(["highlight": .string(quote), "before": .string(before ?? ""), "after": .string(after ?? "")])
                    }
                }
            } else { range = Self.parseRange(locations?["tingyeRange"], length: text.utf16.count) }
            if let range {
                let start = Sentence.index(at: range.location, in: sentences), end = Sentence.index(at: NSMaxRange(range) - 1, in: sentences)
                let target = LocatorTarget(chapter: chapter, position: start, end: end, text: originalQuote,
                          anchor: Locator.anchor(in: sentences, at: start), locator: .object(canonical), publicationRevision: revision)
                precise.append(result(target, .object(canonical), .exact))
            } else if book.format.uppercased() != "EPUB", let sentence = locations?["tingyeSentence"]?.int {
                return result(.init(chapter: chapter, position: min(max(0, sentence), max(0, sentences.count - 1))), .object(raw), .exact)
            }
        }
        if let chapterHint, let found = precise.first(where: { $0.target.chapter == chapterHint }) { return found }
        if precise.count == 1 { return precise[0] }
        if precise.count > 1 { return result(.init(chapter: chapterHint ?? 0, position: 0), nil, .unresolved) }
        if let chapter = candidates.first, book.chapters.indices.contains(chapter) {
            let count = Sentence.split(book.chapters[chapter].text).count
            return result(.init(chapter: chapter, position: EPUBApproximateProgress.position(progression: locator.locations.progression ?? 0, sentenceCount: count)), .object(raw), .approximate)
        }
        return result(.init(chapter: chapterHint ?? 0, position: 0), nil, .unresolved)
    }
    func resolve(link: ReadiumShared.Link) async -> LocatorResult? {
        guard let publication, let locator = await publication.locate(link) else { return nil }
        let chapter = map?.chapter(for: locator.href.string) ?? 0
        return result(.init(chapter: chapter, position: 0), StoredLocator.json(locator), .approximate)
    }
    /// Native chapter offset just after the last character still visible on the current page.
    func nativePageEnd(href: String, pageEnd: JSONValue, mode: String) async throws -> (chapter: Int, offset: Int)? {
        guard let map, let chapter = map.chapter(for: href), book.chapters.indices.contains(chapter) else { return nil }
        let index = try await self.index(chapter: chapter, href: href)
        guard let domEnd = index.domOffset(ofEnd: pageEnd, mode: mode), let native = index.nativeOffset(atDOMEnd: domEnd) else { return nil }
        return (chapter, native)
    }
    /// Convert an original persisted locator to the current display DOM. Only the returned copy changes.
    func displayLocator(_ raw: JSONValue?, mode: String, requireRange: Bool = false) async throws -> ReadiumShared.Locator? {
        guard let locator = StoredLocator.readium(raw), EPUBTextTransform.enabled(mode) else { return StoredLocator.readium(raw) }
        guard let chapter = map?.chapter(for: locator.href.string) ?? raw?.object?["locations"]?.object?["tingyeChapter"]?.int, book.chapters.indices.contains(chapter) else { return locator.copy(text: { $0 = .init() }) }
        let idx = try await index(chapter: chapter, href: locator.href.string)
        let storedDOM = raw?.object?["locations"]?.object?["domRange"]
        func approximate() -> ReadiumShared.Locator? {
            guard !requireRange else { return nil }
            return locator.copy(locations: { $0.otherLocations.removeValue(forKey: "domRange") }, text: { $0 = .init() })
        }
        guard let range = Self.parseRange(raw?.object?["locations"]?.object?["tingyeRange"], length: book.chapters[chapter].text.utf16.count),
              let dom = storedDOM.flatMap({ idx.range(from: $0) }) ?? idx.domRange(for: range, before: locator.text.before, after: locator.text.after), let span = idx.span(dom, mode: mode),
              var json = raw?.object else { return approximate() }
        let context = idx.textContext(dom)
        var locations = json["locations"]?.object ?? [:]; locations["domRange"] = span.json; json["locations"] = .object(locations)
        json["text"] = .object(["highlight": .string(EPUBTextTransform.mapping(context.quote, mode: mode).text),
                                "before": .string(EPUBTextTransform.mapping(context.before, mode: mode).text),
                                "after": .string(EPUBTextTransform.mapping(context.after, mode: mode).text)])
        return StoredLocator.readium(.object(json))
    }
}
