import Foundation
import ReadiumZIPFoundation

// MARK: - 漫画压缩包分发（CBZ / CBT 已落地；CBR / CB7 留接口）

/// 漫画导入的统一归档接口：只暴露 ComicImporter 需要的两件事——普通文件条目
/// 路径列表与按路径批量取数据，语义与 SafeArchive 对齐（缺失路径抛
/// 「压缩书籍缺少资源」、同名条目先到先得）。
/// 后端：CBZ / 图片 ZIP 走既有 SafeArchive（ZIPFoundation，本轮导入优化的
/// 批量流式提取）；CBT 走仓内纯 Swift 的 TarArchive；CBR（RAR）与 CB7（7z）
/// 暂未接入解码库，在 open 时给出明确的未支持报错，不静默失败。
final class ComicArchive {
    private enum Backend {
        case zip(SafeArchive)
        case tar(TarArchive)
    }

    private let backend: Backend
    /// 归档内普通文件的路径（归档原始顺序，未排序、同名已去重）。
    let filePaths: [String]

    private init(backend: Backend, filePaths: [String]) {
        self.backend = backend
        self.filePaths = filePaths
    }

    static func open(url: URL) throws -> ComicArchive {
        switch url.pathExtension.lowercased() {
        case "cbt":
            let tar = try TarArchive(url: url)
            return ComicArchive(backend: .tar(tar), filePaths: tar.entries.map(\.path))
        case "cbr":
            // abbeycode/UnrarKit 仅有 CocoaPods / Carthage 分发、无 SPM 支持，
            // 与本工程全量 SPM 的依赖方式不兼容，故暂不接入（详见导入格式报告）。
            throw ReaderError.message("暂不支持 CBR（RAR）漫画包，请先转换为 CBZ 后重新导入。")
        case "cb7":
            // PLzmaSDK 虽有官方 SPM 包，但本轮未在可编译环境完成接入验证，
            // 先留接口：识别格式并给出明确报错（详见导入格式报告）。
            throw ReaderError.message("暂不支持 CB7（7z）漫画包，请先转换为 CBZ 后重新导入。")
        default:
            let zip = try SafeArchive(url: url)
            return ComicArchive(backend: .zip(zip), filePaths: zip.archive.filter { $0.type == .file }.map(\.path))
        }
    }

    func data(for paths: [String]) throws -> [String: Data] {
        switch backend {
        case .zip(let zip): return try zip.data(for: paths)
        case .tar(let tar): return try tar.data(for: paths)
        }
    }
}

// MARK: - CBT（TAR）纯 Swift 流式读取

/// 仓内实现的 ustar 读取器（零依赖）。构造时只顺序扫描 512 字节页头建立
/// 路径 → 数据偏移索引（逐头验证校验和，损坏即报明确错误）；取数据时按偏移
/// 直读对应区间，因此额外驻留内存只与单次批量取用的页数有关，与包大小无关。
/// 支持 ustar 前缀、GNU 长文件名（'L'）与 pax 扩展头（'x' 中的 path 记录），
/// 尺寸字段支持八进制与 GNU base-256 两种编码。
final class TarArchive {
    struct Entry {
        let path: String
        let size: Int
        let dataOffset: UInt64
    }

    let entries: [Entry]
    private let handle: FileHandle

    init(url: URL) throws {
        let handle = try FileHandle(forReadingFrom: url)
        let scanned: [Entry]
        do {
            scanned = try Self.scan(handle)
        } catch {
            try? handle.close()
            throw error
        }
        self.handle = handle
        entries = scanned
    }

    deinit { try? handle.close() }

    /// 与 SafeArchive.data(for:) 相同语义：同名条目先到先得，缺失即抛错。
    func data(for paths: [String]) throws -> [String: Data] {
        var index: [String: Entry] = [:]
        index.reserveCapacity(entries.count)
        for entry in entries where index[entry.path] == nil { index[entry.path] = entry }
        var result: [String: Data] = [:]
        result.reserveCapacity(paths.count)
        for path in paths {
            guard let entry = index[path] else { throw ReaderError.message("压缩书籍缺少资源：\(path)") }
            try Task.checkCancellation()
            result[path] = try Self.readExact(handle, at: entry.dataOffset, size: entry.size)
        }
        return result
    }

    private static func readExact(_ handle: FileHandle, at offset: UInt64, size: Int) throws -> Data {
        try handle.seek(toOffset: offset)
        var data = Data()
        data.reserveCapacity(size)
        var remaining = size
        while remaining > 0 {
            guard let chunk = try handle.read(upToCount: min(remaining, 1 << 20)), !chunk.isEmpty else {
                throw ReaderError.message("CBT 文件已损坏或被截断。")
            }
            data.append(chunk)
            remaining -= chunk.count
        }
        return data
    }

    private static func scan(_ handle: FileHandle) throws -> [Entry] {
        let fileSize = try handle.seekToEnd()
        var entries: [Entry] = []
        var seen: Set<String> = []
        var pendingName: String?
        var offset: UInt64 = 0
        while offset < fileSize {
            guard fileSize - offset >= 512 else {
                // 尾部不足一个页头的残块：全零视为填充，否则文件已损坏。
                try handle.seek(toOffset: offset)
                let rest = try handle.read(upToCount: Int(fileSize - offset)) ?? Data()
                guard rest.allSatisfy({ $0 == 0 }) else { throw ReaderError.message("CBT 文件已损坏或被截断。") }
                break
            }
            try handle.seek(toOffset: offset)
            let header = try handle.read(upToCount: 512) ?? Data()
            guard header.count == 512 else { throw ReaderError.message("CBT 文件已损坏或被截断。") }
            if header.allSatisfy({ $0 == 0 }) { break }  // 结束标记（两个零块，读到第一个即停）
            guard checksumMatches(header) else { throw ReaderError.message("CBT 文件已损坏：页头校验失败。") }
            let size = try entrySize(header)
            let dataOffset = offset + 512
            guard dataOffset + size <= fileSize else { throw ReaderError.message("CBT 文件已损坏或被截断。") }
            switch header[156] {
            case 0x4C:  // 'L' GNU 长文件名：数据即下一个条目的完整路径
                pendingName = try readName(handle, at: dataOffset, size: Int(size))
            case 0x78:  // 'x' pax 扩展头：取其中的 path 记录（无则保留既有长名）
                if let path = try paxPath(handle, at: dataOffset, size: Int(size)) { pendingName = path }
            case 0x30, 0, 0x37:  // '0' / '\0' 普通文件，'7' 连续文件
                let name = pendingName ?? fullName(header)
                pendingName = nil
                if !name.isEmpty, !name.hasSuffix("/"), seen.insert(name).inserted {
                    entries.append(Entry(path: name, size: Int(size), dataOffset: dataOffset))
                }
            default:  // '5' 目录、'1'/'2' 链接、'g' 全局头等：跳过数据，不产出条目
                pendingName = nil
            }
            offset = dataOffset + (size + 511) / 512 * 512
        }
        return entries
    }

    private static func readName(_ handle: FileHandle, at offset: UInt64, size: Int) throws -> String {
        let data = try readExact(handle, at: offset, size: size)
        let end = data.firstIndex(of: 0) ?? data.endIndex
        return String(decoding: data[..<end], as: UTF8.self)
    }

    private static func paxPath(_ handle: FileHandle, at offset: UInt64, size: Int) throws -> String? {
        let data = try readExact(handle, at: offset, size: size)
        var path: String?
        var index = data.startIndex
        while index < data.endIndex {
            // 记录格式："<十进制总长> <key>=<value>\n"，总长含长度数字自身与换行。
            guard let space = data[index...].firstIndex(of: 0x20),
                  let length = Int(String(decoding: data[index..<space], as: UTF8.self)),
                  length > 0, index + length <= data.endIndex, index + length > space else { break }
            let recordEnd = index + length
            if let equals = data[(space + 1)..<recordEnd].firstIndex(of: 0x3D) {
                let key = String(decoding: data[(space + 1)..<equals], as: UTF8.self)
                var valueEnd = recordEnd
                if valueEnd > equals + 1, data[valueEnd - 1] == 0x0A { valueEnd -= 1 }
                if key == "path" { path = String(decoding: data[(equals + 1)..<valueEnd], as: UTF8.self) }
            }
            index = recordEnd
        }
        return path
    }

    private static func fullName(_ header: Data) -> String {
        let name = fieldString(header, 0, 100)
        guard fieldString(header, 257, 5) == "ustar" else { return name }  // 非 ustar 无前缀字段
        let prefix = fieldString(header, 345, 155)
        return prefix.isEmpty ? name : prefix + "/" + name
    }

    private static func fieldString(_ header: Data, _ start: Int, _ length: Int) -> String {
        let field = header[start..<(start + length)]
        let end = field.firstIndex(of: 0) ?? field.endIndex
        return String(decoding: field[..<end], as: UTF8.self)
    }

    private static func checksumMatches(_ header: Data) -> Bool {
        guard let stored = parseOctal(header, 148, 8) else { return false }
        var sum = 0
        for index in 0..<512 { sum += (148..<156).contains(index) ? 0x20 : Int(header[index]) }
        return sum == stored
    }

    private static func entrySize(_ header: Data) throws -> UInt64 {
        if header[124] & 0x80 != 0 {  // GNU base-256（二进制）尺寸编码
            var value: UInt64 = UInt64(header[124] & 0x7F)
            for index in 125..<136 {
                value = value << 8 | UInt64(header[index])
                guard value <= 1 << 40 else { throw ReaderError.message("CBT 文件已损坏：条目尺寸异常。") }
            }
            return value
        }
        guard let octal = parseOctal(header, 124, 12) else { throw ReaderError.message("CBT 文件已损坏：尺寸字段无效。") }
        return UInt64(octal)
    }

    /// 八进制字段解析：跳过前导空格 / NUL，读到非八进制字符为止；无数字返回 nil。
    private static func parseOctal(_ header: Data, _ start: Int, _ length: Int) -> Int? {
        var value: Int?
        for index in start..<(start + length) {
            let byte = header[index]
            if byte == 0 || byte == 0x20 {
                if value != nil { break }
                continue
            }
            guard byte >= 0x30, byte <= 0x37 else { return nil }
            value = (value ?? 0) * 8 + Int(byte - 0x30)
        }
        return value
    }
}
