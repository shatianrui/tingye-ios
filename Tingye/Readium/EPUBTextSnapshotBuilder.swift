import Foundation
import UIKit
import ReadiumShared

/// Readium alone interprets the container, OPF, reading order and TOC. The compatibility
/// text layer deliberately uses exactly the same HTMLText/Sentence rules as other HTML imports.
@MainActor
enum EPUBTextSnapshotBuilder {
    struct Snapshot: Sendable { let book: Book; let map: PublicationMap }
    /// Keep the Publication and all Toolkit API calls on MainActor; only the Sendable snapshot leaves it.
    static func open(_ url: URL, fallbackTitle: String, revision: String, id: String = UUID().uuidString.lowercased()) async throws -> Snapshot {
        let publication = try await ReadiumService().open(url)
        return try await build(publication, fallbackTitle: fallbackTitle, revision: revision, id: id)
    }
    private static func flatten(_ links: [ReadiumShared.Link]) -> [ReadiumShared.Link] {
        links.flatMap { [$0] + flatten($0.children) }
    }
    static func build(_ publication: Publication, fallbackTitle: String, revision: String, id: String = UUID().uuidString.lowercased()) async throws -> Snapshot {
        let toc = flatten((try? await publication.tableOfContents().get()) ?? [])
        var resources: [String: JSONValue] = [:], images: [String: String] = [:], styles: [String: String] = [:]
        for link in publication.readingOrder + publication.resources {
            try Task.checkCancellation()
            guard let path = PublicationMap.normalized(link.href), let resource = publication.get(link) else { continue }
            let type = link.mediaType?.string ?? ""
            if ["image/png", "image/jpeg", "image/gif", "image/webp"].contains(type), images[path] == nil {
                let bytes = try await resource.read().get(), key = "r\(resources.count)"
                resources[key] = .string("data:\(type);base64," + bytes.base64EncodedString()); images[path] = key
            } else if type == "text/css" {
                styles[path] = try BookImporter.decode(try await resource.read().get())
            }
        }
        var chapters: [Chapter] = []
        for link in publication.readingOrder {
            try Task.checkCancellation()
            guard let path = PublicationMap.normalized(link.href), let resource = publication.get(link) else {
                throw ReaderError.message("EPUB 正文资源不存在：\(link.href)")
            }
            guard ["application/xhtml+xml", "text/html", "image/svg+xml"].contains(link.mediaType?.string ?? "") else {
                throw ReaderError.message("EPUB 正文不是可提取文字的 HTML：\(link.href)")
            }
            let html = try BookImporter.decode(try await resource.read().get())
            let title = toc.first { PublicationMap.normalized($0.href) == path }?.title ?? link.title ?? "第 \(chapters.count + 1) 章"
            let imageMap = images, cssMap = styles
            let chapter = await Task.detached(priority: .userInitiated) {
                var chapter = HTMLText.chapter(html, title: title)
                // Publication TOC/resource titles take precedence over a heading in the body.
                chapter.fields["title"] = .string(title)
                chapter.fields["nativeImages"] = .array(HTMLText.imageSources(html).compactMap { source in
                    guard let resolved = try? BookImporter.resolve(base: path, href: source), let key = imageMap[resolved] else { return nil }
                    return .string("tingye-resource:" + key)
                })
                let original = HTMLText.replacingImageSources(in: html) { source in
                    guard let resolved = try? BookImporter.resolve(base: path, href: source), let key = imageMap[resolved] else { return nil }
                    return "tingye-resource:" + key
                }
                let regex = try! NSRegularExpression(pattern: #"(?i)<link\b[^>]*href\s*=\s*["']([^"']+)["'][^>]*>"#)
                let css = regex.matches(in: html, range: NSRange(location: 0, length: html.utf16.count)).compactMap { match -> String? in
                    let href = (html as NSString).substring(with: match.range(at: 1))
                    return (try? BookImporter.resolve(base: path, href: href)).flatMap { cssMap[$0] }
                }.joined(separator: "\n")
                chapter.fields["document"] = .object(["html": .string(OriginalDocument.sanitized(original)), "css": .string(css), "path": .string(path)])
                return chapter
            }.value
            // Keep every reading-order resource, including image-only/empty chapters, for stable mapping.
            chapters.append(chapter)
        }
        guard !chapters.isEmpty else { throw ReaderError.message("EPUB 没有可阅读的章节。") }
        let metadata = publication.metadata
        var extras: [String: JSONValue] = ["resources": .object(resources), "description": .string(metadata.description ?? ""),
            "category": .string(metadata.subjects.first?.name ?? "其他"), "language": .string(metadata.languages.first ?? "und")]
        if let cover = try await publication.cover().get(), let bytes = cover.pngData() {
            let key = "r\(resources.count)"; resources[key] = .string("data:image/png;base64," + bytes.base64EncodedString())
            extras["resources"] = .object(resources); extras["cover"] = .string("tingye-resource:" + key)
        }
        let authors = metadata.authors.map(\.name).joined(separator: "、")
        var book = Book(id: id, title: metadata.title ?? fallbackTitle, author: authors.isEmpty ? "佚名" : authors, format: "EPUB", chapters: chapters, extras: extras)
        let map = PublicationMap(book: book, readingOrder: publication.readingOrder.map(\.href), titles: [:], revision: revision)
        book.fields["epubTextMap"] = try JSONDecoder().decode(JSONValue.self, from: Integrity.encoder().encode(map))
        try Task.checkCancellation()
        return Snapshot(book: book, map: map)
    }
}

/// Optional, self-contained attachment. A malformed attachment never rejects the text backup.
struct EPUBBackupAttachment: Codable, Equatable, Sendable {
    var base64: String
    var sha256: String
    init(data: Data) { base64 = data.base64EncodedString(); sha256 = PublicationDigest.data(data) }
    init(from decoder: Decoder) throws {
        let values = try? decoder.container(keyedBy: CodingKeys.self)
        base64 = (try? values?.decode(String.self, forKey: .base64)) ?? ""
        sha256 = (try? values?.decode(String.self, forKey: .sha256)) ?? ""
    }
    var data: Data? {
        guard let bytes = Data(base64Encoded: base64), PublicationDigest.data(bytes) == sha256 else { return nil }
        return bytes
    }
}

extension LibraryDisk {
    func backupAttachment(for book: Book) throws -> EPUBBackupAttachment? {
        guard let url = try sourceURL(for: book) else { return nil }
        return EPUBBackupAttachment(data: try Data(contentsOf: url))
    }
}

extension BookImporter {
    static func restored(_ packet: BackupPacket) async throws -> Imported {
        try Task.checkCancellation()
        let packet = try packet.validated(id: packet.book.id)
        var fallback = packet.book; fallback.epubSource = nil
        fallback.fields.removeValue(forKey: "epubTextMap")
        guard fallback.format.uppercased() == "EPUB", let bytes = packet.epubAttachment?.data else {
            return Imported(book: fallback, progress: packet.progress)
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".epub")
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            try bytes.write(to: url)
            let source = try EPUBSourceStaging(copying: url)
            let snapshot = try await EPUBTextSnapshotBuilder.open(source.url, fallbackTitle: fallback.title,
                revision: "source-" + source.sha256, id: fallback.id)
            // Preserve unknown Book keys; only publication-derived data is regenerated.
            var book = fallback
            book.fields.removeValue(forKey: "cover")
            for (key, value) in snapshot.book.fields { book.fields[key] = value }
            return Imported(book: try book.validated(), progress: packet.progress, source: source)
        } catch is CancellationError { throw CancellationError() }
        catch {
            try Task.checkCancellation()
            return Imported(book: fallback, progress: packet.progress)
        }
    }
}
