import Foundation
import CryptoKit

enum ReaderError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let value) = self { return value }; return nil }
}

/// Preserve fields produced by other clients when a native client re-uploads a book.
enum JSONValue: Codable, Equatable, Sendable {
    case string(String), number(Double), bool(Bool), object([String: JSONValue]), array([JSONValue]), null
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([String: JSONValue].self) { self = .object(v) }
        else { self = .array(try c.decode([JSONValue].self)) }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
    var string: String? { if case .string(let v) = self { return v }; return nil }
    var int: Int? { if case .number(let v) = self, v.isFinite, v >= Double(Int.min), v < Double(Int.max) { return Int(v) }; return nil }
    var object: [String: JSONValue]? { if case .object(let v) = self { return v }; return nil }
    var array: [JSONValue]? { if case .array(let v) = self { return v }; return nil }
    var bool: Bool? { if case .bool(let v) = self { return v }; return nil }
}

struct Chapter: Codable, Equatable, Sendable {
    var fields: [String: JSONValue]
    var title: String { fields["title"]?.string ?? "正文" }
    var text: String { fields["text"]?.string ?? "" }
    /// 原书清洗文档的 HTML（构建 142 起的类型化访问器，替代各处直读 fields["document"]；
    /// 141 的块解析与目录插图取用都走这里，落盘结构不变）。
    var documentHTML: String? { fields["document"]?.object?["html"]?.string }
    /// 本章的原生图片引用（document 顺序）；nil = 未记录（与「记录了但为空」区分，调用方据此回退到 HTML 提取）。
    var nativeImageRefs: [String]? { fields["nativeImages"]?.array?.compactMap(\.string) }
    init(title: String, text: String, extras: [String: JSONValue] = [:]) {
        fields = extras; fields["title"] = .string(title); fields["text"] = .string(text)
    }
    init(from decoder: Decoder) throws { fields = try [String: JSONValue](from: decoder) }
    func encode(to encoder: Encoder) throws { try fields.encode(to: encoder) }
}

struct Book: Codable, Identifiable, Equatable, Sendable {
    var fields: [String: JSONValue] { didSet { chapters = Self.chapters(in: fields) } }
    /// 章节数组随 `fields` 更新一次性生成：界面每次刷新都会读它，现算会为几千章的书反复分配整个数组。
    private(set) var chapters: [Chapter]
    private static func chapters(in fields: [String: JSONValue]) -> [Chapter] {
        (fields["chapters"]?.array ?? []).compactMap { $0.object.map { Chapter(fields: $0) } }
    }
    var id: String { fields["id"]?.string ?? "" }
    var title: String { fields["title"]?.string ?? "未命名" }
    var author: String { fields["author"]?.string ?? "佚名" }
    var format: String { fields["format"]?.string ?? "TXT" }
    var color: String { fields["color"]?.string ?? "green" }
    var sample: Bool { fields["sample"]?.bool ?? id.hasPrefix("sample-") }
    var pdf: Data? { fields["pdf"]?.string.flatMap { Data(base64Encoded: $0, options: .ignoreUnknownCharacters) } }
    var isPDF: Bool { fields["pdf"] != nil }
    /// 全书资源表（key → data: URL 字符串），与 resourceData(_:) 同源；供仍需整表取用的调用方。
    var resourceMap: [String: JSONValue] { fields["resources"]?.object ?? [:] }
    var coverData: Data? {
        guard let ref = fields["cover"]?.string else { return nil }
        return resourceData(ref)
    }
    func resourceData(_ ref: String) -> Data? {
        let key = ref.replacingOccurrences(of: "tingye-resource:", with: "")
        let raw = fields["resources"]?.object?[key]?.string ?? ref
        guard raw.hasPrefix("data:image/"), let comma = raw.firstIndex(of: ",") else { return nil }
        return Data(base64Encoded: String(raw[raw.index(after: comma)...]), options: .ignoreUnknownCharacters)
    }
    init(id: String = UUID().uuidString.lowercased(), title: String, author: String = "佚名", format: String, chapters: [Chapter], extras: [String: JSONValue] = [:]) {
        var values = extras
        values["id"] = .string(id); values["title"] = .string(title); values["author"] = .string(author)
        values["format"] = .string(format); values["chapters"] = .array(chapters.map { .object($0.fields) })
        fields = values; self.chapters = chapters
    }
    init(from decoder: Decoder) throws {
        let values = try [String: JSONValue](from: decoder)
        fields = values; chapters = Self.chapters(in: values)
    }
    func encode(to encoder: Encoder) throws { try fields.encode(to: encoder) }
    func validated() throws -> Book {
        guard Self.validID(id), fields["title"]?.string != nil,
              let raw = fields["chapters"]?.array, !raw.isEmpty,
              raw.allSatisfy({ $0.object?["title"]?.string != nil && $0.object?["text"]?.string != nil }) else {
            throw ReaderError.message("书籍格式无效。")
        }
        return self
    }
    static func validID(_ value: String) -> Bool { value.range(of: "^[a-zA-Z0-9_-]{1,100}$", options: .regularExpression) != nil }
}

private extension Chapter { init(fields: [String: JSONValue]) { self.fields = fields } }

/// Readium 式文本锚点（构建 142，借 Locator 模型）：与「章 + 句序号」坐标并存的可选校验信息。
/// quote 是所在句全文（上限 120 字，超出截断）；before / after 各取相邻至多两句拼接后
/// 截取的上下文（上限 40 字：before 取尾段、after 取首段），多处同文时用于消歧。
/// 坐标仍是主定位；锚点只在坐标处的句子与 quote 不一致时介入重定位，全部失败回落坐标。
/// 旧数据没有此字段：一律 Optional 解码 + nil 容忍，nil = 按旧行为只用坐标。
struct TextAnchor: Codable, Equatable, Sendable {
    var quote: String
    var before: String?
    var after: String?
    static let quoteLimit = 120
    static let contextLimit = 40
}

struct ReadingProgress: Codable, Equatable, Sendable {
    var chapter = 0
    /// Cross-platform protocol uses sentence index, not UTF-16 character offset.
    var position = 0
    var updatedAt: Double = 0
    /// 文本锚点（构建 142）：旧目录 / 旧备份无此字段，解码为 nil。
    var anchor: TextAnchor? = nil
    static var now: Double { Date().timeIntervalSince1970 * 1000 }
}
struct Bookmark: Codable, Identifiable, Sendable {
    var id = UUID()
    var chapter: Int
    var position: Int
    var excerpt: String
    /// 文本锚点（构建 142）：旧数据为 nil。
    var anchor: TextAnchor? = nil
    var date = Date()
}
struct ShelfEntry: Codable, Identifiable, Sendable {
    var id: String
    var title: String
    var author: String
    var format: String
    var color: String
    var sample: Bool
    var local: Bool
    var chapterCount: Int
    /// Local derived index; never added to the cross-platform BackupPacket.
    var sentenceCounts: [Int]?
    var progress: ReadingProgress
    /// 听书只更新这份本机位置；progress 始终是阅读与跨设备续读的位置。
    /// 旧目录没有此字段，首次听书沿用旧进度，不丢失历史位置。
    var listeningProgress: ReadingProgress?
    /// 最近主动翻开阅读的时间，不会被后台朗读刷新。
    var lastReadAt: Double?
    var snapshotRevision: String?
    var cloudRevision: String?
    var backupAt: Double?
    var bookmarks: [Bookmark]
    // 以下为本机书库整理字段，全部可选：旧书库与旧备份照常解码，跨端 BackupPacket 协议不变。
    /// 分组路径，多级用「/」分隔，如「科幻/阿西莫夫」；nil 表示未分组
    var group: String?
    /// 隐藏书籍：只在解锁隐藏模式后显示
    var hidden: Bool?
    /// 划线与笔记（句级坐标，与阅读进度同一套「章 + 句序号」）
    var highlights: [Highlight]?
    /// 加入书库的时间（毫秒），用于排序；旧书为 nil
    var addedAt: Double?
    /// 上次主动使用的方式，只存本机目录，不改变跨端进度协议。
    var lastActivity: ReadingActivity?
    var hasListened: Bool?
    /// 缓存书籍简介，避免打开详情页时为了读简介反序列化上百 MB 的整书 JSON
    var intro: String?
    init(book: Book, progress: ReadingProgress = .init()) {
        id = book.id; title = book.title; author = book.author; format = book.format; color = book.color
        sample = book.sample; local = true; chapterCount = book.chapters.count; self.progress = progress; bookmarks = []
        sentenceCounts = book.chapters.map { Sentence.split($0.text).count }
        addedAt = ReadingProgress.now
        intro = [book.fields["description"]?.string, book.fields["intro"]?.string]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }
    var isHidden: Bool { hidden == true }
    var notes: [Highlight] { highlights ?? [] }
    /// 漫画：CBZ / 图片压缩包导入的书，在书库「漫画」页显示，以图片翻页阅读
    var isComic: Bool { format.uppercased() == "CBZ" }
}

enum ReadingActivity: String, Codable, Sendable { case reading, listening }

/// 阅读始终是主要动作，听书状态仅用于辅助入口的文案。
struct ResumeActions: Equatable {
    let started: Bool
    let lastActivity: ReadingActivity
    let hasListened: Bool
    let playing: Bool
    var prefersListening: Bool { false }
    var readingTitle: String { started ? "继续阅读" : "开始阅读" }
    var listeningTitle: String { playing ? "暂停朗读" : hasListened ? "继续听" : started ? "听这本书" : "开始听书" }
}

struct AppNotice: Identifiable {
    let id = UUID()
    let text: String
    var importResults = false
}

/// 导入只报告实际完成的文件；不持有临时 URL 或超出授权期限的文件访问权限。
struct ImportItem: Identifiable {
    enum State: Equatable {
        case waiting, importing, imported(String), failed(String)
        var finished: Bool {
            switch self { case .imported, .failed: true; default: false }
        }
    }
    let id = UUID()
    let name: String
    var state: State = .waiting
}
struct ImportReport: Identifiable {
    let id = UUID()
    var items: [ImportItem]
    var completed: Int { items.filter { $0.state.finished }.count }
    var successes: Int { items.filter { if case .imported = $0.state { true } else { false } }.count }
    var failures: Int { items.filter { if case .failed = $0.state { true } else { false } }.count }
    var finished: Bool { !items.isEmpty && completed == items.count }
    var summary: String {
        if !finished { return "正在导入 \(completed) / \(items.count) 个文件" }
        return failures == 0 ? "已导入 \(successes) 个文件" : "已导入 \(successes) 个，\(failures) 个失败"
    }
}

/// 一段划线：从 `start` 句到 `end` 句（含），可附笔记。
struct Highlight: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var chapter: Int
    var start: Int
    var end: Int
    var text: String
    /// 起始句的文本锚点（构建 142）：旧数据为 nil。
    var anchor: TextAnchor? = nil
    /// yellow / green / blue / pink / purple
    var color: String = "yellow"
    /// background（浅底）/ underline（直线）/ wavy（波浪线）
    var style: String = "background"
    var note: String?
    var date = Date()
    func contains(chapter other: Int, sentence: Int) -> Bool { chapter == other && (start...end).contains(sentence) }
}

/// 一次阅读或听书：同一本书连续活动合并为一条，间隔超过 3 分钟另起一条。
struct ReadingSession: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var bookID: String
    var title: String
    var start: Date
    var end: Date
    var seconds: Double
    var listening: Bool
}

struct BackupPacket: Codable, Sendable {
    var format = "tingye-backup"
    var version = 2
    var book: Book
    var progress: ReadingProgress
    func validated(id: String) throws -> BackupPacket {
        _ = try book.validated()
        guard format == "tingye-backup", version == 2, book.id == id,
              progress.chapter >= 0, progress.chapter < book.chapters.count, progress.position >= 0,
              progress.updatedAt.isFinite, progress.updatedAt >= 0 else { throw ReaderError.message("备份内容或阅读位置无效。") }
        return self
    }
}
struct Sentence: Identifiable, Equatable, Sendable {
    var id: Int
    var text: String
    var range: NSRange
    private static let sentenceRegex = try! NSRegularExpression(pattern: #"[^。！？.!?\n\r]+[。！？.!?]+[”’」』"]?|[^。！？.!?\n\r]+(?:\n|$)"#)
    private static let chunkRegex = try! NSRegularExpression(pattern: #".{1,180}(?:[，,；;：:]|$)|.{1,180}"#)
    static func split(_ text: String) -> [Sentence] {
        let source = text as NSString
        var output: [Sentence] = []
        for match in sentenceRegex.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            let raw = source.substring(with: match.range)
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let local = (raw as NSString).range(of: trimmed)
            let base = match.range.location + local.location
            if trimmed.utf16.count > 260 {
                for part in chunkRegex.matches(in: trimmed, range: NSRange(location: 0, length: trimmed.utf16.count)) {
                    output.append(Sentence(id: output.count, text: (trimmed as NSString).substring(with: part.range), range: NSRange(location: base + part.range.location, length: part.range.length)))
                }
            } else { output.append(Sentence(id: output.count, text: trimmed, range: NSRange(location: base, length: trimmed.utf16.count))) }
        }
        return output
    }
    static func index(at offset: Int, in sentences: [Sentence]) -> Int {
        sentences.lastIndex(where: { $0.range.location <= offset }) ?? 0
    }
}

/// 锚点的生成与解析（构建 142）：坐标优先、锚点校验、文本重定位、回落钳制坐标。
/// 全部是纯函数：解析失败的最坏结果与构建 141 的旧行为完全一致（钳制后的原坐标），
/// 因此任何一本书都不会因为锚点而打不开或跳错到比旧行为更差的位置。
enum Locator {
    /// 从一章的句子列表为第 index 句生成锚点；越界或空句返回 nil（调用方存 nil 即旧行为）。
    static func anchor(in sentences: [Sentence], at index: Int) -> TextAnchor? {
        guard sentences.indices.contains(index) else { return nil }
        let quote = String(sentences[index].text.prefix(TextAnchor.quoteLimit))
        guard !quote.isEmpty else { return nil }
        var before: String?
        if index > 0 {
            let joined = sentences[max(0, index - 2)..<index].map(\.text).joined()
            if !joined.isEmpty { before = String(joined.suffix(TextAnchor.contextLimit)) }
        }
        var after: String?
        if index + 1 < sentences.count {
            let joined = sentences[(index + 1)..<min(sentences.count, index + 3)].map(\.text).joined()
            if !joined.isEmpty { after = String(joined.prefix(TextAnchor.contextLimit)) }
        }
        return TextAnchor(quote: quote, before: before, after: after)
    }

    /// quote 可能被截断到 120 字、句子也可能被分块切分，故前缀互含即视为同一句。
    private static func matches(_ text: String, quote: String) -> Bool {
        guard !text.isEmpty, !quote.isEmpty else { return false }
        return text == quote || text.hasPrefix(quote) || quote.hasPrefix(text)
    }

    /// 前后文吻合度：某一侧完整吻合记 2 分（before 取尾段比对、after 取首段比对）。
    private static func contextScore(at index: Int, anchor: TextAnchor, in sentences: [Sentence]) -> Int {
        var score = 0
        if let before = anchor.before, !before.isEmpty, index > 0 {
            let prev = sentences[max(0, index - 2)..<index].map(\.text).joined()
            if !prev.isEmpty, prev.hasSuffix(before) || before.hasSuffix(prev) { score += 2 }
        }
        if let after = anchor.after, !after.isEmpty, index + 1 < sentences.count {
            let next = sentences[(index + 1)..<min(sentences.count, index + 3)].map(\.text).joined()
            if !next.isEmpty, next.hasPrefix(after) || after.hasPrefix(next) { score += 2 }
        }
        return score
    }

    /// 解析一句在本章中的下标：
    /// 1) 坐标处句子与 quote 一致 → 用坐标；2) quote 在本章唯一出现 → 用该处；
    /// 3) 多处同文 → 前后文打分消歧（同分取离原坐标最近）；4) quote 已不存在 →
    /// 只靠上下文找吻合处（至少一侧完整吻合才认）；5) 全部失败 → 回落钳制后的原坐标。
    static func resolve(position: Int, anchor: TextAnchor?, in sentences: [Sentence]) -> Int {
        guard !sentences.isEmpty else { return 0 }
        let clamped = min(max(0, position), sentences.count - 1)
        guard let anchor, !anchor.quote.isEmpty else { return clamped }
        if matches(sentences[clamped].text, quote: anchor.quote) { return clamped }
        let hits = sentences.indices.filter { matches(sentences[$0].text, quote: anchor.quote) }
        if !hits.isEmpty {
            var best = hits[0], bestScore = contextScore(at: hits[0], anchor: anchor, in: sentences)
            for hit in hits.dropFirst() {
                let score = contextScore(at: hit, anchor: anchor, in: sentences)
                if score > bestScore || (score == bestScore && abs(hit - clamped) < abs(best - clamped)) { best = hit; bestScore = score }
            }
            return best
        }
        var best: Int?
        var bestScore = 0
        for index in sentences.indices {
            let score = contextScore(at: index, anchor: anchor, in: sentences)
            guard score >= 2 else { continue }
            if score > bestScore || (score == bestScore && best.map { abs(index - clamped) < abs($0 - clamped) } == true) {
                best = index; bestScore = score
            }
        }
        return best ?? clamped
    }

    /// 按章缓存分句结果的批量解析上下文（修书 / 同 ID 替换时整本重定位用，避免同章反复分句）。
    private static func splitter(for book: Book) -> (Int) -> [Sentence] {
        var cache: [Int: [Sentence]] = [:]
        return { index in
            if let cached = cache[index] { return cached }
            let value = book.chapters.indices.contains(index) ? Sentence.split(book.chapters[index].text) : []
            cache[index] = value
            return value
        }
    }

    /// 进度重定位：章号先钳制，再在本章内按锚点解析句号；位置实际移动过时按新位置重建锚点，
    /// 使下一次校验仍有据可依。无锚点时只钳制，与旧行为一致。
    static func resolve(_ progress: ReadingProgress, in book: Book) -> ReadingProgress {
        guard !book.chapters.isEmpty else { return progress }
        var next = progress
        next.chapter = min(max(0, progress.chapter), book.chapters.count - 1)
        let sentences = Sentence.split(book.chapters[next.chapter].text)
        next.position = resolve(position: progress.position, anchor: progress.anchor, in: sentences)
        if next.chapter != progress.chapter || next.position != progress.position {
            next.anchor = anchor(in: sentences, at: next.position) ?? progress.anchor
        }
        return next
    }

    static func resolve(_ bookmark: Bookmark, in book: Book) -> Bookmark {
        guard !book.chapters.isEmpty else { return bookmark }
        var next = bookmark
        next.chapter = min(max(0, bookmark.chapter), book.chapters.count - 1)
        let sentences = Sentence.split(book.chapters[next.chapter].text)
        next.position = resolve(position: bookmark.position, anchor: bookmark.anchor, in: sentences)
        if next.chapter != bookmark.chapter || next.position != bookmark.position {
            next.anchor = anchor(in: sentences, at: next.position) ?? bookmark.anchor
        }
        return next
    }

    /// 划线在给定句子列表上的重定位（渲染时内存修正与整本回写共用）：先解起始句，
    /// 结束句按原跨度平移并钳制；存有全文（text）时再校验拼接文本，不一致则逐个
    /// quote 候选试跨度，找到全文吻合的一组才采纳。章不存在 / 本章无句时原样返回，
    /// 由渲染侧既有的越界丢弃逻辑兜底（与旧行为一致）。
    static func resolve(_ highlight: Highlight, sentences: [Sentence]) -> Highlight {
        guard !sentences.isEmpty else { return highlight }
        var next = highlight
        let span = max(0, highlight.end - highlight.start)
        var start = resolve(position: highlight.start, anchor: highlight.anchor, in: sentences)
        var end = min(start + span, sentences.count - 1)
        if !highlight.text.isEmpty, let anchor = highlight.anchor, !anchor.quote.isEmpty,
           sentences[start...end].map(\.text).joined() != highlight.text {
            for hit in sentences.indices where matches(sentences[hit].text, quote: anchor.quote) {
                let candidateEnd = min(hit + span, sentences.count - 1)
                if sentences[hit...candidateEnd].map(\.text).joined() == highlight.text { start = hit; end = candidateEnd; break }
            }
        }
        next.start = start; next.end = end
        if start != highlight.start || end != highlight.end {
            next.anchor = anchor(in: sentences, at: start) ?? highlight.anchor
        }
        return next
    }

    static func resolve(_ highlight: Highlight, in book: Book) -> Highlight {
        guard book.chapters.indices.contains(highlight.chapter) else { return highlight }
        return resolve(highlight, sentences: Sentence.split(book.chapters[highlight.chapter].text))
    }

    /// 整本批量重定位（修书成功 / 同 ID 书被替换后回写）：按章缓存分句，逐条解析。
    /// 无锚点的旧条目原样保留（与构建 141 修书时「不动书签/划线」的行为一致），
    /// 只有带锚点的条目才写入重定位结果，避免把旧数据钳制到错误位置后永久落盘。
    static func relocated(_ bookmarks: [Bookmark], in book: Book) -> [Bookmark] {
        guard !book.chapters.isEmpty else { return bookmarks }
        let split = splitter(for: book)
        return bookmarks.map { mark in
            guard mark.anchor != nil else { return mark }
            var next = mark
            next.chapter = min(max(0, mark.chapter), book.chapters.count - 1)
            let sentences = split(next.chapter)
            next.position = resolve(position: mark.position, anchor: mark.anchor, in: sentences)
            if next.chapter != mark.chapter || next.position != mark.position {
                next.anchor = anchor(in: sentences, at: next.position) ?? mark.anchor
            }
            return next
        }
    }

    static func relocated(_ highlights: [Highlight], in book: Book) -> [Highlight] {
        let split = splitter(for: book)
        return highlights.map { item in
            guard item.anchor != nil, book.chapters.indices.contains(item.chapter) else { return item }
            return resolve(item, sentences: split(item.chapter))
        }
    }
}

enum Integrity {
    static func sha256(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    static func encoder() -> JSONEncoder { let e = JSONEncoder(); e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]; return e }
}
