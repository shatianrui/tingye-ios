import Foundation

struct PublicationMap: Codable, Equatable, Sendable {
    struct ChapterLink: Codable, Equatable, Sendable {
        let chapterIndex: Int
        /// HREF relative to the EPUB container, as exposed by Readium (not relative to OPF).
        let href: String
        let originalPath: String?
        let resourceRoot: String
    }
    static let schemaVersion = 1
    let version: Int
    let generatorVersion: Int
    let contentHash: String
    let publicationRevision: String
    let chapters: [ChapterLink]

    init(book: Book, contentHash: String) {
        version = Self.schemaVersion
        generatorVersion = LegacyEPUBBuilder.generatorVersion
        self.contentHash = contentHash
        publicationRevision = "legacy-\(generatorVersion)-\(contentHash)"
        chapters = book.chapters.enumerated().map { index, chapter in
            let path = chapter.fields["document"]?.object?["path"]?.string
            return ChapterLink(chapterIndex: index, href: String(format: "EPUB/text/ch-%06d.xhtml", index + 1),
                               originalPath: path, resourceRoot: "EPUB/images/")
        }
    }
    /// 原包不能按文本章下标硬对齐 spine：旧导入曾跳过非线性/空资源。
    /// 本单元只用路径或唯一标题提供资源映射；模糊全文消歧留单元 3。
    init(book: Book, readingOrder: [String], titles: [String: String], revision: String) {
        version = Self.schemaVersion
        generatorVersion = 0
        contentHash = revision
        publicationRevision = revision
        chapters = book.chapters.enumerated().compactMap { index, chapter in
            let original = chapter.fields["document"]?.object?["path"]?.string
            let byPath = original.flatMap(Self.normalized).flatMap { path in
                readingOrder.first { Self.normalized($0) == path }
            }
            let title = chapter.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let byTitle = readingOrder.filter { href in
                !title.isEmpty && titles[href]?.trimmingCharacters(in: .whitespacesAndNewlines) == title
            }
            guard let href = byPath ?? (byTitle.count == 1 ? byTitle.first : nil) else { return nil }
            return ChapterLink(chapterIndex: index, href: href, originalPath: original, resourceRoot: "")
        }
    }
    func href(for chapter: Int) -> String? { chapters.first { $0.chapterIndex == chapter }?.href }
    func chapter(for href: String) -> Int? {
        guard let path = Self.normalized(href) else { return nil }
        return chapters.first { Self.normalized($0.href) == path }?.chapterIndex
    }
    func chapters(forOriginalPath path: String) -> [ChapterLink] {
        guard let path = Self.normalized(path) else { return [] }
        return chapters.filter { $0.originalPath.flatMap(Self.normalized) == path }
    }
    static func normalized(_ raw: String) -> String? {
        guard !raw.hasPrefix("/"), !raw.contains(":"), !raw.contains("\\"),
              let path = raw.components(separatedBy: CharacterSet(charactersIn: "?#")).first?.removingPercentEncoding,
              !path.hasPrefix("/"), !path.contains(":"), !path.contains("\\"), !path.contains("\0") else { return nil }
        var parts: [String] = []
        for component in path.split(separator: "/") {
            if component == ".." { guard !parts.isEmpty else { return nil }; parts.removeLast() }
            else if component != "." { parts.append(String(component)) }
        }
        return parts.joined(separator: "/")
    }
    /// Only inputs consumed by the generator contribute. Local progress/read-state never invalidates it.
    static func contentHash(for book: Book) throws -> String {
        var fields: [String: JSONValue] = [:]
        for key in ["id", "title", "author", "format", "resources", "cover", "description", "category", "language"] {
            fields[key] = book.fields[key]
        }
        fields["chapters"] = .array(book.chapters.map { chapter in
            var snapshot: [String: JSONValue] = [:]
            for key in ["title", "text", "document", "nativeImages"] { snapshot[key] = chapter.fields[key] }
            return .object(snapshot)
        })
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return PublicationDigest.data(try encoder.encode(fields))
    }
    static func revision(for book: Book) throws -> String {
        if let source = book.epubSource { return "source-\(source.sha256)" }
        return "legacy-\(LegacyEPUBBuilder.generatorVersion)-\(try contentHash(for: book))"
    }
}
