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
              let raw = fields["chapters"]?.array, !raw.isEmpty, raw.count <= 3000,
              raw.allSatisfy({ $0.object?["title"]?.string != nil && $0.object?["text"]?.string != nil }),
              chapters.reduce(0, { $0 + $1.text.utf16.count }) <= 4_000_000 else {
            throw ReaderError.message("书籍格式无效，或超过 400 万字 / 3000 章限制。")
        }
        if let value = fields["pdf"]?.string, value.utf8.count > 30 * 1024 * 1024 { throw ReaderError.message("PDF 超过 22 MB，请拆分导入。") }
        return self
    }
    static func validID(_ value: String) -> Bool { value.range(of: "^[a-zA-Z0-9_-]{1,100}$", options: .regularExpression) != nil }
}

private extension Chapter { init(fields: [String: JSONValue]) { self.fields = fields } }

struct ReadingProgress: Codable, Equatable, Sendable {
    var chapter = 0
    /// Cross-platform protocol uses sentence index, not UTF-16 character offset.
    var position = 0
    var updatedAt: Double = 0
    static var now: Double { Date().timeIntervalSince1970 * 1000 }
}
struct Bookmark: Codable, Identifiable, Sendable {
    var id = UUID()
    var chapter: Int
    var position: Int
    var excerpt: String
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

/// 一段划线：从 `start` 句到 `end` 句（含），可附笔记。
struct Highlight: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var chapter: Int
    var start: Int
    var end: Int
    var text: String
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

enum Integrity {
    static func sha256(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    static func encoder() -> JSONEncoder { let e = JSONEncoder(); e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]; return e }
}
