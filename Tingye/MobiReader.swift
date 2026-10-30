import Foundation

/// MOBI / AZW / AZW3（KF8）导入：解析 PalmDB 记录，解压正文（PalmDOC 或 HUFF/CDIC），按分页标记拆章。
/// 只读文字与封面，不支持 DRM 加密书籍。混合格式（MOBI6 + KF8）取 MOBI6 部分。
enum MobiReader {
    static func book(_ url: URL, fallbackTitle: String) throws -> Book {
        let data = try Data(contentsOf: url)
        let bytes = [UInt8](data)
        guard bytes.count > 78 else { throw ReaderError.message("MOBI 文件不完整。") }
        let type = String(decoding: bytes[60..<68], as: UTF8.self)
        guard ["BOOKMOBI", "TEXtREAd"].contains(type) else { throw ReaderError.message("不是有效的 MOBI / AZW 文件。") }
        let count = Int(u16(bytes, 76))
        guard count > 1, 78 + count * 8 <= bytes.count else { throw ReaderError.message("MOBI 记录表损坏。") }
        let offsets = (0..<count).map { Int(u32(bytes, 78 + $0 * 8)) } + [bytes.count]
        guard offsets[0] >= 78 + count * 8,
              zip(offsets, offsets.dropFirst()).allSatisfy({ $0 <= $1 && $1 <= bytes.count }) else {
            throw ReaderError.message("MOBI 记录表损坏。")
        }
        func record(_ i: Int) -> ArraySlice<UInt8> {
            guard i >= 0, i < count, offsets[i] <= offsets[i + 1], offsets[i + 1] <= bytes.count else { return [] }
            return bytes[offsets[i]..<offsets[i + 1]]
        }

        let r0 = Array(record(0))
        guard r0.count >= 16 else { throw ReaderError.message("MOBI 文件头不完整。") }
        let compression = u16(r0, 0)
        let textRecords = Int(u16(r0, 8))
        guard textRecords > 0, textRecords < count else { throw ReaderError.message("MOBI 正文记录损坏。") }
        guard u16(r0, 12) == 0 else { throw ReaderError.message("这本书有 DRM 加密，无法导入。") }

        let gbEncoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        var title = fallbackTitle, author = "佚名", encoding = String.Encoding.windowsCP1252
        var extraFlags: UInt16 = 0, firstImage = -1, coverIndex: Int?
        var huffRecords: [ArraySlice<UInt8>] = []
        if r0.count >= 0x84, String(decoding: r0[16..<20], as: UTF8.self) == "MOBI" {
            let headerLength = Int(u32(r0, 20))
            let codepage = u32(r0, 28)
            if codepage == 65001 { encoding = .utf8 }
            else if codepage == 936 { encoding = gbEncoding }
            let nameOffset = Int(u32(r0, 0x54)), nameLength = Int(u32(r0, 0x58))
            if nameOffset + nameLength <= r0.count, nameLength > 0, let name = String(bytes: r0[nameOffset..<nameOffset + nameLength], encoding: encoding) { title = name }
            firstImage = Int(u32(r0, 0x6C))
            if headerLength >= 0xE4, r0.count >= 0xF4 { extraFlags = u16(r0, 0xF2) }
            if compression == 17480 {
                let start = Int(u32(r0, 0x70)), total = Int(u32(r0, 0x74))
                guard start > textRecords, start < count, total > 0, total <= count - start else {
                    throw ReaderError.message("MOBI 的 HUFF 压缩表损坏。")
                }
                huffRecords = (start..<start + total).map(record)
            }
            // EXTH：作者 100、书名 503、封面 201（相对首图的序号）
            if u32(r0, 0x80) & 0x40 != 0 {
                var p = 16 + headerLength
                if p + 12 <= r0.count, String(decoding: r0[p..<p + 4], as: UTF8.self) == "EXTH" {
                    let items = Int(u32(r0, p + 8)); p += 12
                    for _ in 0..<items {
                        guard p + 8 <= r0.count else { break }
                        let kind = u32(r0, p), length = Int(u32(r0, p + 4))
                        guard length >= 8, p + length <= r0.count else { break }
                        let value = r0[(p + 8)..<(p + length)]
                        switch kind {
                        case 100: if let text = String(bytes: value, encoding: encoding) { author = author == "佚名" ? text : author + "、" + text }
                        case 503: if let text = String(bytes: value, encoding: encoding), !text.isEmpty { title = text }
                        case 201: if value.count >= 4 { coverIndex = Int(u32(Array(value), 0)) }
                        default: break
                        }
                        p += length
                    }
                }
            }
        }

        // 正文：第 1…textRecords 条记录，去掉尾部附加数据后解压
        let huff = compression == 17480 ? try HuffCDIC(huffRecords) : nil
        var raw = Data()
        for i in 1...textRecords {
            var chunk = Array(record(i))
            chunk.removeLast(min(chunk.count, trailingSize(chunk, flags: extraFlags)))
            switch compression {
            case 1: raw.append(contentsOf: chunk)
            case 2: raw.append(contentsOf: palmDOC(chunk))
            case 17480: raw.append(contentsOf: try huff!.unpack(chunk))
            default: throw ReaderError.message("不支持这种 MOBI 压缩方式（\(compression)）。")
            }
        }
        guard let html = String(data: raw, encoding: encoding) ?? String(data: raw, encoding: .utf8) ?? String(data: raw, encoding: gbEncoding) ?? String(data: raw, encoding: .windowsCP1252) else {
            throw ReaderError.message("MOBI 正文编码无法识别。")
        }

        // 拆章：MOBI6 用 <mbp:pagebreak/>，KF8 每个 HTML 文件以 </html> 结尾
        let parts = html.components(separatedBy: "<mbp:pagebreak").flatMap { $0.components(separatedBy: "</html>") }
        var chapters: [Chapter] = []
        for part in parts {
            let source = part.hasPrefix("/>") || part.hasPrefix(">") ? String(part.drop { $0 != ">" }.dropFirst()) : part
            let chapter = HTMLText.chapter(source, title: "第 \(chapters.count + 1) 章")
            if !chapter.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { chapters.append(chapter) }
        }
        // 没有分页标记的单篇长文按标题 / 字数再拆
        if chapters.count == 1, let only = chapters.first, only.text.count > 30_000 { chapters = BookImporter.splitText(only.text, title: title) }
        guard !chapters.isEmpty else { throw ReaderError.message("MOBI 中没有找到可阅读的文字。") }

        var extras: [String: JSONValue] = ["category": .string("其他")]
        if firstImage > 0, let coverIndex {
            let image = Data(record(firstImage + coverIndex))
            if let type = imageType(image) {
                extras["resources"] = .object(["cover": .string("data:\(type);base64," + image.base64EncodedString())])
                extras["cover"] = .string("tingye-resource:cover")
            }
        }
        let format = url.pathExtension.uppercased() == "AZW3" ? "AZW3" : "MOBI"
        return Book(title: title.trimmingCharacters(in: .whitespacesAndNewlines), author: author, format: format, chapters: chapters, extras: extras)
    }

    // MARK: 工具

    static func u16<C: RandomAccessCollection>(_ b: C, _ i: Int) -> UInt16 where C.Element == UInt8, C.Index == Int {
        guard i >= 0, i <= b.count - 2 else { return 0 }
        let s = b.startIndex + i
        return UInt16(b[s]) << 8 | UInt16(b[s + 1])
    }
    static func u32<C: RandomAccessCollection>(_ b: C, _ i: Int) -> UInt32 where C.Element == UInt8, C.Index == Int {
        guard i >= 0, i <= b.count - 4 else { return 0 }
        let s = b.startIndex + i
        return UInt32(b[s]) << 24 | UInt32(b[s + 1]) << 16 | UInt32(b[s + 2]) << 8 | UInt32(b[s + 3])
    }

    /// 记录尾部附加数据长度（extra data flags：多字节字符重叠 + TBS 索引等）
    static func trailingSize(_ data: [UInt8], flags: UInt16) -> Int {
        var size = 0
        var bits = flags >> 1
        while bits != 0 {
            if bits & 1 != 0 {
                var value = 0, shift = 0, p = data.count - size
                while p > 0 {
                    let v = data[p - 1]
                    value |= Int(v & 0x7F) << shift
                    shift += 7; p -= 1
                    if v & 0x80 != 0 || shift >= 28 { break }
                }
                size += value
            }
            bits >>= 1
        }
        if flags & 1 != 0, data.count > size { size += Int(data[data.count - size - 1] & 0x3) + 1 }
        return min(size, data.count)
    }

    /// PalmDOC（LZ77 变体）解压
    static func palmDOC(_ input: [UInt8]) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(input.count * 2)
        var i = 0
        while i < input.count {
            let c = input[i]; i += 1
            switch c {
            case 1...8:
                let end = min(input.count, i + Int(c))
                out.append(contentsOf: input[i..<end]); i = end
            case 0, 9...0x7F:
                out.append(c)
            case 0xC0...0xFF:
                out.append(0x20); out.append(c ^ 0x80)
            default:
                guard i < input.count else { break }
                let pair = Int(c) << 8 | Int(input[i]); i += 1
                let distance = (pair >> 3) & 0x7FF, length = (pair & 7) + 3
                guard distance > 0, distance <= out.count else { continue }
                for _ in 0..<length { out.append(out[out.count - distance]) }
            }
        }
        return out
    }

    static func imageType(_ data: Data) -> String? {
        if data.starts(with: [0xFF, 0xD8]) { return "image/jpeg" }
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "image/png" }
        if data.starts(with: [0x47, 0x49, 0x46]) { return "image/gif" }
        return nil
    }
}

/// HUFF/CDIC 解压（亚马逊工具生成的 MOBI 常用），算法与 calibre 的 HuffReader 相同。
final class HuffCDIC {
    private var dict1: [(length: Int, term: Bool, max: UInt64)] = []
    private var minCode: [UInt64] = []
    private var maxCode: [UInt64] = []
    private var dictionary: [(bytes: [UInt8], done: Bool)?] = []
    private var depth = 0

    init(_ records: [ArraySlice<UInt8>]) throws {
        guard let huff = records.first.map(Array.init), huff.count >= 16, huff.starts(with: Array("HUFF".utf8)) else { throw ReaderError.message("MOBI 的 HUFF 压缩表缺失。") }
        let off1 = Int(MobiReader.u32(huff, 8)), off2 = Int(MobiReader.u32(huff, 12))
        guard off1 >= 16, off2 >= 16, off1 + 1024 <= huff.count, off2 + 256 <= huff.count else { throw ReaderError.message("MOBI 的 HUFF 压缩表损坏。") }
        for i in 0..<256 {
            let v = MobiReader.u32(huff, off1 + i * 4)
            let length = Int(v & 0x1F), term = v & 0x80 != 0
            let maxValue = length == 0 ? 0 : ((UInt64(v >> 8) + 1) << UInt64(32 - length)) - 1
            dict1.append((length, term, maxValue))
        }
        minCode = [0]; maxCode = [0]
        for i in 0..<32 {
            let lo = UInt64(MobiReader.u32(huff, off2 + i * 8)), hi = UInt64(MobiReader.u32(huff, off2 + i * 8 + 4))
            let length = UInt64(i + 1)
            minCode.append(lo << (32 - length))
            maxCode.append(((hi + 1) << (32 - length)) &- 1)
        }
        var phraseCount: Int?
        for cdic in records.dropFirst().map(Array.init) {
            guard cdic.count >= 16, cdic.starts(with: Array("CDIC".utf8)) else { throw ReaderError.message("MOBI 的 CDIC 压缩表损坏。") }
            let phrases = Int(MobiReader.u32(cdic, 8)), bits = Int(MobiReader.u32(cdic, 12))
            guard (0...31).contains(bits), phrases > dictionary.count,
                  phraseCount == nil || phraseCount == phrases else { throw ReaderError.message("MOBI 的 CDIC 压缩表损坏。") }
            phraseCount = phrases
            let n = min(1 << bits, phrases - dictionary.count)
            guard n <= (cdic.count - 16) / 2 else { throw ReaderError.message("MOBI 的 CDIC 压缩表损坏。") }
            for k in 0..<n {
                let off = Int(MobiReader.u16(cdic, 16 + k * 2))
                guard off >= n * 2, 18 + off <= cdic.count else { throw ReaderError.message("MOBI 的 CDIC 压缩表损坏。") }
                let blen = Int(MobiReader.u16(cdic, 16 + off))
                let start = 18 + off, end = start + (blen & 0x7FFF)
                guard end <= cdic.count else { throw ReaderError.message("MOBI 的 CDIC 压缩表损坏。") }
                dictionary.append((Array(cdic[start..<end]), blen & 0x8000 != 0))
            }
        }
        guard !dictionary.isEmpty, phraseCount == dictionary.count else { throw ReaderError.message("MOBI 的 CDIC 压缩表缺失或不完整。") }
    }

    func unpack(_ input: [UInt8], limit: Int = Int.max) throws -> [UInt8] {
        depth += 1; defer { depth -= 1 }
        guard depth < 32, limit >= 0 else { throw ReaderError.message("MOBI 压缩数据异常。") }
        var data = input + [UInt8](repeating: 0, count: 8)
        var bitsLeft = input.count * 8
        var pos = 0
        func q(_ p: Int) -> UInt64 { (0..<8).reduce(UInt64(0)) { $0 << 8 | UInt64(data[p + $1]) } }
        var x = q(pos)
        var n = 32
        var out: [UInt8] = []
        while bitsLeft > 0 {
            if n <= 0 {
                pos += 4
                if pos + 8 > data.count { data += [UInt8](repeating: 0, count: 8) }
                x = q(pos); n += 32
            }
            let code = (x >> UInt64(n)) & 0xFFFF_FFFF
            var (length, term, maxValue) = dict1[Int(code >> 24)]
            if !term {
                while length < 32, code < minCode[length] { length += 1 }
                maxValue = maxCode[length]
            }
            guard length > 0 else { throw ReaderError.message("MOBI 压缩数据异常。") }
            n -= length
            bitsLeft -= length
            if bitsLeft < 0 { break }
            guard (term || code >= minCode[length]), maxValue >= code,
                  let r = Int(exactly: (maxValue - code) >> UInt64(32 - length)),
                  dictionary.indices.contains(r), let entry = dictionary[r] else { throw ReaderError.message("MOBI 压缩字典损坏。") }
            if entry.done {
                guard entry.bytes.count <= limit - out.count else { throw ReaderError.message("MOBI 正文过大。") }
                out += entry.bytes
            }
            else {
                dictionary[r] = nil
                let expanded = try unpack(entry.bytes, limit: limit - out.count)
                dictionary[r] = (expanded, true)
                out += expanded
            }
        }
        return out
    }
}

// MARK: - 漫画（CBZ / 图片 ZIP）

/// 每张图是一「页」（一个章节，正文为空），进度、同步、统计沿用「章 + 句」坐标。
enum ComicImporter {
    static func book(_ url: URL, title: String) throws -> Book {
        let zip = try SafeArchive(url: url)
        let images = zip.archive
            .filter { entry in
                let path = entry.path
                let ext = (path as NSString).pathExtension.lowercased()
                return entry.type == .file && ["jpg", "jpeg", "png", "webp", "gif", "heic"].contains(ext)
                    && !path.contains("__MACOSX") && !(path as NSString).lastPathComponent.hasPrefix(".")
            }
            .map(\.path)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        guard !images.isEmpty else { throw ReaderError.message("压缩包里没有图片；ZIP 只支持漫画 / 图集（CBZ）。") }
        var resources: [String: JSONValue] = [:]
        var chapters: [Chapter] = []
        for (index, path) in images.enumerated() {
            let data = try zip.data(path)
            let ext = (path as NSString).pathExtension.lowercased()
            let type = ext == "jpg" ? "image/jpeg" : "image/" + ext
            let key = "p\(index)"
            resources[key] = .string("data:\(type);base64," + data.base64EncodedString())
            chapters.append(Chapter(title: "第 \(index + 1) 页", text: "", extras: ["nativeImages": .array([.string("tingye-resource:" + key)])]))
        }
        return Book(title: title, author: "佚名", format: "CBZ", chapters: chapters,
                    extras: ["resources": .object(resources), "cover": .string("tingye-resource:p0"), "comic": .bool(true), "category": .string("漫画")])
    }
}
