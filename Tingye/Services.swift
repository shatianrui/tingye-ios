import Foundation
import Security
import CryptoKit
import os

enum Keychain {
    static let service = "com.shatianrui.wereader.native"
    static func data(_ key: String, service: String = service, account: Any? = nil) throws -> Data? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrAccount as String: account ?? key, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var value: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &value)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw failure(status) }
        return value as? Data
    }
    static func save(_ data: Data, key: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key]
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else { throw failure(added) }
        } else if status != errSecSuccess { throw failure(status) }
    }
    static func remove(_ key: String) throws {
        let status = SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key] as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw failure(status) }
    }
    static func failure(_ status: OSStatus) -> ReaderError { .message("系统钥匙串暂不可用（\(status)）。请解锁设备后重试。") }
}

final class RedirectBlocker: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

/// 本机直连云语音服务商（智谱 GLM / MiniMax），使用用户自己的 API Key，不经过任何听页服务端。
enum CloudSpeech {
    struct Word: Codable, Sendable { let text: String; let start: Double; let end: Double }
    struct Result: Codable, Sendable { let audio: Data; let words: [Word] }
    struct Voice: Decodable, Sendable { let value: String; let label: String }
    static let glmEndpoint = URL(string: "https://open.bigmodel.cn/api/paas/v4/audio/speech")!
    private static let maxAudio = 16 * 1024 * 1024
    private static let maxDiskCacheBytes = 96 * 1024 * 1024
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 45; config.timeoutIntervalForResource = 120
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config, delegate: RedirectBlocker(), delegateQueue: nil)
    }()

    private static var diskCacheFolder: URL? {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let folder = caches.appendingPathComponent("TTSAudio", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    static func cachedResult(forKey key: String) -> Result? {
        guard let url = diskCacheFolder?.appendingPathComponent(key + ".json"),
              let data = try? Data(contentsOf: url),
              let result = try? JSONDecoder().decode(Result.self, from: data),
              !result.audio.isEmpty else { return nil }
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        return result
    }

    static func storeCachedResult(_ result: Result, forKey key: String) {
        guard !result.audio.isEmpty, let folder = diskCacheFolder else { return }
        let url = folder.appendingPathComponent(key + ".json")
        guard let data = try? JSONEncoder().encode(result) else { return }
        try? data.write(to: url, options: .atomic)
        pruneDiskCache(in: folder)
    }

    static func clearDiskCache() {
        guard let folder = diskCacheFolder else { return }
        try? FileManager.default.removeItem(at: folder)
    }

    private static func pruneDiskCache(in folder: URL) {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey], options: [.skipsHiddenFiles]) else { return }
        var entries: [(url: URL, size: Int, date: Date)] = []
        var total = 0
        for url in urls {
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else { continue }
            let size = values.fileSize ?? 0
            total += size
            entries.append((url, size, values.contentModificationDate ?? .distantPast))
        }
        guard total > maxDiskCacheBytes else { return }
        entries.sort { $0.date < $1.date }
        for entry in entries {
            try? fm.removeItem(at: entry.url)
            total -= entry.size
            if total <= maxDiskCacheBytes * 3 / 4 { break }
        }
    }

    static func synthesize(_ text: String, provider: String, model: String, voice: String, key: String, groupID: String) async throws -> Result {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw ReaderError.message("请先在「听书与声音」中填写自己的 \(VoiceOptions.providerName(provider)) API Key，或改用系统声音。") }
        let voice = voice.trimmingCharacters(in: .whitespacesAndNewlines), model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !voice.isEmpty, voice.count <= 200 else { throw ReaderError.message("请选择有效音色。") }
        switch provider {
        case "glm": return try await glm(text, model: model.isEmpty ? "glm-tts" : model, voice: voice, key: key)
        case "azure": return try await azure(text, voice: voice, key: key, region: groupID)
        case "elevenlabs": return try await elevenLabs(text, model: model.isEmpty ? "eleven_multilingual_v2" : model, voice: voice, key: key)
        default: return try await minimax(text, model: model.isEmpty ? "speech-2.8-hd" : model, voice: voice, key: key, groupID: groupID)
        }
    }

    // MARK: Microsoft Azure Speech（REST + SSML，MP3）

    private static func xmlEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    private static func azure(_ text: String, voice: String, key: String, region: String) async throws -> Result {
        let region = region.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !region.isEmpty, region.range(of: "^[a-z0-9]{2,30}$", options: .regularExpression) != nil else {
            throw ReaderError.message("请填写 Azure 语音资源的区域，例如 eastasia、southeastasia、eastus。")
        }
        guard let url = URL(string: "https://\(region).tts.speech.microsoft.com/cognitiveservices/v1") else { throw ReaderError.message("Azure 区域格式不正确。") }
        let escaped = xmlEscape(text)
        let safeVoice = xmlEscape(voice)
        let language = xmlEscape(voice.split(separator: "-").prefix(2).joined(separator: "-"))
        let ssml = "<speak version='1.0' xml:lang='\(language)'><voice name='\(safeVoice)'>\(escaped)</voice></speak>"
        var request = URLRequest(url: url); request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        request.setValue("application/ssml+xml", forHTTPHeaderField: "Content-Type")
        request.setValue("audio-24khz-48kbitrate-mono-mp3", forHTTPHeaderField: "X-Microsoft-OutputFormat")
        request.setValue("Tingye", forHTTPHeaderField: "User-Agent")
        request.httpBody = Data(ssml.utf8)
        let (data, http) = try await send(request)
        guard (200..<300).contains(http.statusCode) else { throw failure(http.statusCode, detail: detail(data)) }
        guard !data.isEmpty else { throw ReaderError.message("Azure 语音没有返回音频。") }
        return Result(audio: data, words: [])
    }

    // MARK: ElevenLabs（带逐字时间戳）

    private static func elevenLabs(_ text: String, model: String, voice: String, key: String) async throws -> Result {
        guard let id = voice.addingPercentEncoding(withAllowedCharacters: .alphanumerics),
              let url = URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(id)/with-timestamps?output_format=mp3_44100_128") else { throw ReaderError.message("ElevenLabs 音色 ID 无效。") }
        var request = URLRequest(url: url); request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try Integrity.encoder().encode(["text": JSONValue.string(text), "model_id": .string(model)])
        let (data, http) = try await send(request)
        guard (200..<300).contains(http.statusCode) else { throw failure(http.statusCode, detail: detailElevenLabs(data) ?? detail(data)) }
        let body = try JSONDecoder().decode([String: JSONValue].self, from: data)
        guard let base64 = body["audio_base64"]?.string, let audio = Data(base64Encoded: base64), !audio.isEmpty else { throw ReaderError.message("ElevenLabs 没有返回音频。") }
        var words: [Word] = []
        if let alignment = body["alignment"]?.object, let chars = alignment["characters"]?.array,
           let starts = alignment["character_start_times_seconds"]?.array, let ends = alignment["character_end_times_seconds"]?.array {
            for (i, item) in chars.enumerated() where i < starts.count && i < ends.count {
                guard let c = item.string, !c.trimmingCharacters(in: .whitespaces).isEmpty,
                      case .number(let start) = starts[i], case .number(let end) = ends[i] else { continue }
                words.append(Word(text: c, start: start, end: end))
            }
        }
        return Result(audio: audio, words: words)
    }

    private static func detailElevenLabs(_ data: Data) -> String? {
        guard let body = try? JSONDecoder().decode([String: JSONValue].self, from: data.prefix(4000)) else { return nil }
        return body["detail"]?.object?["message"]?.string ?? body["detail"]?.string
    }

    static func elevenLabsVoices(key: String) async throws -> [Voice] {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw ReaderError.message("请先填写 ElevenLabs API Key。") }
        var request = URLRequest(url: URL(string: "https://api.elevenlabs.io/v1/voices")!)
        request.setValue(key, forHTTPHeaderField: "xi-api-key")
        let (data, http) = try await send(request)
        guard (200..<300).contains(http.statusCode) else { throw failure(http.statusCode, detail: detailElevenLabs(data)) }
        let body = try JSONDecoder().decode([String: JSONValue].self, from: data)
        return (body["voices"]?.array ?? []).compactMap { item in
            guard let object = item.object, let id = object["voice_id"]?.string else { return nil }
            return Voice(value: id, label: object["name"]?.string ?? id)
        }
    }

    static func minimaxVoices(key: String, groupID: String) async throws -> [Voice] {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw ReaderError.message("请先填写 MiniMax API Key。") }
        let result = try await minimaxRequest("/v1/get_voice", body: ["voice_type": .string("all")], key: key, groupID: groupID)
        var seen = Set<String>(), voices: [Voice] = []
        for group in ["system_voice", "voice_cloning", "voice_generation"] {
            for item in result[group]?.array ?? [] {
                guard let object = item.object, let id = object["voice_id"]?.string, !id.isEmpty, seen.insert(id).inserted else { continue }
                let label = object["voice_name"]?.string ?? object["description"]?.array?.first?.string ?? id
                voices.append(Voice(value: id, label: label.isEmpty ? id : label))
            }
        }
        return voices
    }

    private static func glm(_ text: String, model: String, voice: String, key: String) async throws -> Result {
        // watermark_enabled=false 仅在账户允许时生效，否则 GLM 会在每句加入水印音。
        let body: [String: JSONValue] = ["model": .string(model), "voice": .string(voice), "input": .string(text), "response_format": .string("wav"), "speed": .number(1), "volume": .number(1), "watermark_enabled": .bool(false)]
        var request = URLRequest(url: glmEndpoint); request.httpMethod = "POST"
        request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try Integrity.encoder().encode(body)
        let (data, http) = try await send(request)
        let type = http.value(forHTTPHeaderField: "Content-Type") ?? ""
        guard (200..<300).contains(http.statusCode) else { throw failure(http.statusCode, detail: detail(data)) }
        guard !type.contains("json"), !type.hasPrefix("text/") else {
            let extra = detail(data).map { "（服务商返回：\($0)）" } ?? ""
            throw ReaderError.message("语音服务未返回音频，请检查账户额度和音色。" + extra)
        }
        return Result(audio: try normalizedWav(data), words: [])
    }

    private static func minimax(_ text: String, model: String, voice: String, key: String, groupID: String) async throws -> Result {
        let body: [String: JSONValue] = [
            "model": .string(model), "text": .string(text), "stream": .bool(false), "output_format": .string("hex"),
            "subtitle_enable": .bool(true), "subtitle_type": .string("word"), "language_boost": .string("auto"),
            "voice_setting": .object(["voice_id": .string(voice), "speed": .number(1), "vol": .number(1), "pitch": .number(0)]),
            "audio_setting": .object(["format": .string("mp3"), "sample_rate": .number(32000), "bitrate": .number(128000), "channel": .number(1)]),
        ]
        let result = try await minimaxRequest("/v1/t2a_v2", body: body, key: key, groupID: groupID)
        let payload = result["data"]?.object
        guard let hex = payload?["audio"]?.string, !hex.isEmpty, hex.utf8.count <= maxAudio * 2, hex.utf8.count % 2 == 0,
              let bytes = decodeHex(hex) else { throw ReaderError.message("MiniMax 未返回有效音频。") }
        var words: [Word] = []
        if let subtitles = payload?["subtitles"]?.array { words = minimaxWords(subtitles) }
        else if let file = payload?["subtitle_file"]?.string { words = (try? await subtitleWords(file)) ?? [] }
        return Result(audio: bytes, words: words)
    }

    /// 十六进制音频解码：按字节查表，避免每个字节创建一个 String（长句音频有数十万个字符，原实现解码就要数百毫秒）。
    static func decodeHex(_ hex: String) -> Data? {
        func nibble(_ c: UInt8) -> UInt8? {
            switch c {
            case 48...57: return c - 48
            case 97...102: return c - 87
            case 65...70: return c - 55
            default: return nil
            }
        }
        var output = Data(count: hex.utf8.count / 2)
        let ok: Bool = output.withUnsafeMutableBytes { raw in
            guard let out = raw.bindMemory(to: UInt8.self).baseAddress else { return false }
            var i = 0, high: UInt8 = 0, first = true
            for c in hex.utf8 {
                guard let v = nibble(c) else { return false }
                if first { high = v } else { out[i] = high << 4 | v; i += 1 }
                first.toggle()
            }
            return true
        }
        return ok ? output : nil
    }

    /// MiniMax 国内站：开放平台与 Token Plan（`sk-cp-` 开头的密钥）的官方域名为 api.minimax.cn；
    /// 旧域名 api.minimaxi.com 仍保留为备用。成功过的域名会被记住，之后直接使用。
    static let minimaxOrigins = [URL(string: "https://api.minimax.cn")!, URL(string: "https://api.minimaxi.com")!]
    private static let preferredOrigin = OSAllocatedUnfairLock<URL?>(initialState: nil)
    private struct MiniMaxAuthFailure: Error { let message: String }

    private static func minimaxRequest(_ path: String, body: [String: JSONValue], key: String, groupID: String) async throws -> [String: JSONValue] {
        let group = groupID.trimmingCharacters(in: .whitespacesAndNewlines)
        var origins = minimaxOrigins
        if let preferred = preferredOrigin.withLock({ $0 }), let index = origins.firstIndex(of: preferred) { origins.insert(origins.remove(at: index), at: 0) }
        // Token Plan 密钥不属于任何 Group：填了 Group ID 反而可能鉴权失败，失败时去掉 Group ID 再试一次。
        let groups = group.isEmpty || key.hasPrefix("sk-cp-") ? [""] : [group, ""]
        var lastError: Error?
        for origin in origins {
            for candidate in groups {
                do {
                    let result = try await minimaxRequest(origin: origin, path: path, body: body, key: key, groupID: candidate)
                    preferredOrigin.withLock { $0 = origin }
                    return result
                } catch let failure as MiniMaxAuthFailure {
                    lastError = failure; continue
                } catch let network as URLError where [.cannotFindHost, .cannotConnectToHost, .dnsLookupFailed, .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate, .cannotLoadFromNetwork].contains(network.code) {
                    lastError = network; break
                }
            }
        }
        if let failure = lastError as? MiniMaxAuthFailure {
            let hint = key.hasPrefix("sk-cp-") ? "请确认 Token Plan 套餐仍在有效期内且包含语音额度。" : "国内版 Token Plan 请直接填写 sk-cp- 开头的密钥，无需 Group ID。"
            throw ReaderError.message("MiniMax 密钥无效\(failure.message)。\(hint)")
        }
        throw lastError ?? ReaderError.message("无法连接 MiniMax 语音服务，请检查网络。")
    }

    private static func minimaxRequest(origin: URL, path: String, body: [String: JSONValue], key: String, groupID: String) async throws -> [String: JSONValue] {
        var components = URLComponents(url: origin.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !groupID.isEmpty { components.queryItems = [URLQueryItem(name: "GroupId", value: groupID)] }
        var request = URLRequest(url: components.url!); request.httpMethod = "POST"
        request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try Integrity.encoder().encode(body)
        let (data, http) = try await send(request)
        if http.statusCode == 401 { throw MiniMaxAuthFailure(message: detail(data).map { "（\($0)）" } ?? "") }
        guard (200..<300).contains(http.statusCode) else { throw failure(http.statusCode, detail: detail(data)) }
        guard let result = try? JSONDecoder().decode([String: JSONValue].self, from: data) else { throw ReaderError.message("MiniMax 返回数据异常。") }
        if let base = result["base_resp"]?.object, let code = base["status_code"]?.int, code != 0 {
            let message = base["status_msg"]?.string.map { "（\($0)）" } ?? ""
            switch code {
            case 1002, 1039: throw APIError(status: 429, code: "TTS_RATE_LIMIT", retryAfter: 2, message: "MiniMax 请求过快，请稍后重试\(message)")
            case 1008: throw ReaderError.message("MiniMax 语音额度不足，请检查账户余额或 Token Plan 用量\(message)")
            case 1004, 2049: throw MiniMaxAuthFailure(message: message)
            case 2013: throw ReaderError.message("MiniMax 参数异常\(message)，请检查模型与音色。")
            default: throw ReaderError.message("MiniMax 语音服务返回错误（\(code)\(message)），请检查密钥、语音权限与额度。")
            }
        }
        return result
    }

    static func minimaxWords(_ segments: [JSONValue]) -> [Word] {
        var words: [Word] = []
        for segment in segments {
            var previous: (Int, Int, String)?
            for raw in segment.object?["timestamped_words"]?.array ?? [] {
                guard let item = raw.object, let text = item["word"]?.string, text.count < 300,
                      case .number(let begin) = item["time_begin"], case .number(let end) = item["time_end"],
                      begin.isFinite, end.isFinite, begin >= 0, end > begin else { continue }
                let span = (item["word_begin"]?.int ?? -1, item["word_end"]?.int ?? -1, text)
                if let previous, span.0 >= 0, previous == span, let last = words.popLast() {
                    words.append(Word(text: last.text, start: last.start, end: max(last.end, end / 1000)))
                } else { words.append(Word(text: text, start: begin / 1000, end: end / 1000)) }
                previous = span
                if words.count > 4000 { return [] }
            }
        }
        return words
    }

    private static func subtitleWords(_ address: String) async throws -> [Word] {
        // 只访问 MiniMax 自有的字幕存储，且不携带密钥。
        guard let url = URL(string: address), url.scheme == "https", url.user == nil, url.password == nil, url.port == nil,
              let host = url.host, host.range(of: #"^[a-z0-9-]+\.oss-(cn|accelerate)[a-z0-9-]*\.aliyuncs\.com$"#, options: .regularExpression) != nil else { return [] }
        var request = URLRequest(url: url); request.timeoutInterval = 4
        let (data, http) = try await send(request)
        guard (200..<300).contains(http.statusCode), data.count <= 512_000 else { return [] }
        return minimaxWords((try? JSONDecoder().decode([JSONValue].self, from: data)) ?? [])
    }

    private static func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ReaderError.message("语音服务响应无效。") }
        if (300..<400).contains(http.statusCode) { throw ReaderError.message("语音服务地址发生跳转，已拦截以保护密钥。") }
        guard data.count <= maxAudio * 2 + 1024 * 1024 else { throw ReaderError.message("语音数据过大，请缩短朗读段落。") }
        return (data, http)
    }

    private static func detail(_ data: Data) -> String? {
        guard let body = try? JSONDecoder().decode([String: JSONValue].self, from: data.prefix(4000)) else { return nil }
        let message = body["error"]?.object?["message"]?.string ?? body["message"]?.string ?? body["base_resp"]?.object?["status_msg"]?.string
        return message.flatMap { $0.isEmpty ? nil : String($0.prefix(200)) }
    }

    private static func failure(_ status: Int, detail: String?) -> Error {
        let extra = detail.map { "（服务商返回：\($0)）" } ?? ""
        switch status {
        case 401: return ReaderError.message("语音密钥无效或已过期。" + extra)
        case 402: return ReaderError.message("语音服务余额不足，请充值后重试。" + extra)
        case 403: return ReaderError.message("当前密钥没有此语音模型的使用权限。" + extra)
        case 429: return APIError(status: 429, code: "TTS_RATE_LIMIT", retryAfter: 2, message: "语音服务额度不足或请求过快，请稍后重试。" + extra)
        default: return ReaderError.message("语音服务返回 \(status)，请检查模型权限和音色。" + extra)
        }
    }

    /// GLM 不返回逐字时间戳：把字数按权重均分到实际发声区间，用于朗读时逐字跟随翻页。
    static func estimatedWords(_ text: String, from start: Double, to end: Double) -> [Word] {
        guard end > start, start >= 0 else { return [] }
        let pauses = CharacterSet(charactersIn: "，,、；;：:。！？.!?…—")
        var units: [(String, Double)] = []
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: .byComposedCharacterSequences) { value, _, _, _ in
            guard let value, let scalar = value.unicodeScalars.first, !CharacterSet.whitespacesAndNewlines.contains(scalar) else { return }
            if pauses.contains(scalar) { units.append((value, 0.6)) }
            else if CharacterSet.punctuationCharacters.contains(scalar) || CharacterSet.symbols.contains(scalar) { units.append((value, 0)) }
            else { units.append((value, scalar.isASCII ? 0.5 : 1)) }
        }
        let total = units.reduce(0) { $0 + $1.1 }
        guard total > 0 else { return [] }
        var words: [Word] = [], cursor = start
        for (value, weight) in units {
            let next = min(end, cursor + (end - start) * weight / total)
            if weight > 0 { words.append(Word(text: value, start: cursor, end: next)) }
            cursor = next
        }
        return words
    }

    /// 16 位 PCM WAV 中实际发声的起止秒数（去掉首尾静音）；无法解析时返回 nil。
    static func speechSpan(wav source: Data) -> (start: Double, end: Double)? {
        let bytes = [UInt8](source)
        guard bytes.count >= 44, bytes[0..<4] == Array("RIFF".utf8)[...], bytes[8..<12] == Array("WAVE".utf8)[...] else { return nil }
        func u16(_ i: Int) -> Int { Int(bytes[i]) | Int(bytes[i + 1]) << 8 }
        func u32(_ i: Int) -> Int { u16(i) | u16(i + 2) << 16 }
        var p = 12, channels = 0, rate = 0, bits = 0, format = 0, data: Range<Int>?
        while p + 8 <= bytes.count {
            let size = u32(p + 4), body = p + 8
            guard body + size <= bytes.count else { break }
            let id = String(decoding: bytes[p..<p + 4], as: UTF8.self)
            if id == "fmt ", size >= 16 { format = u16(body); channels = u16(body + 2); rate = u32(body + 4); bits = u16(body + 14) }
            else if id == "data" { data = body..<body + size }
            p = body + size + size % 2
        }
        guard let data, format == 1 || format == 0xFFFE, bits == 16, channels > 0, rate > 0 else { return nil }
        let frameBytes = 2 * channels, frames = data.count / frameBytes
        let window = max(1, rate / 100)
        guard frames > window else { return nil }
        var levels: [Int] = []
        levels.reserveCapacity(frames / window + 1)
        var frame = 0
        while frame < frames {
            var peak = 0
            for f in frame..<min(frames, frame + window) {
                let i = data.lowerBound + f * frameBytes
                peak = max(peak, abs(Int(Int16(bitPattern: UInt16(bytes[i]) | UInt16(bytes[i + 1]) << 8))))
            }
            levels.append(peak); frame += window
        }
        let loudest = levels.max() ?? 0
        guard loudest > 0 else { return nil }
        let threshold = max(300, loudest / 20)
        guard let first = levels.firstIndex(where: { $0 >= threshold }), let last = levels.lastIndex(where: { $0 >= threshold }) else { return nil }
        let seconds = Double(window) / Double(rate), duration = Double(frames) / Double(rate)
        return (Double(first) * seconds, min(duration, Double(last + 1) * seconds))
    }

    /// 部分 GLM 返回的 WAV 中 RIFF 长度少报 4 字节，严格解码器会丢掉结尾；仅在各 chunk 完整时修正长度字段。
    static func normalizedWav(_ source: Data) throws -> Data {
        let invalid = ReaderError.message("GLM 音频文件不完整或格式异常，请重试。")
        let bytes = [UInt8](source)
        guard bytes.count >= 44, bytes.count <= 8 * 1024 * 1024, bytes[0..<4] == Array("RIFF".utf8)[...], bytes[8..<12] == Array("WAVE".utf8)[...] else { throw invalid }
        func u32(_ i: Int) -> Int { Int(bytes[i]) | Int(bytes[i + 1]) << 8 | Int(bytes[i + 2]) << 16 | Int(bytes[i + 3]) << 24 }
        var p = 12, hasData = false
        while p + 8 <= bytes.count {
            let size = u32(p + 4), body = p + 8
            guard body + size + size % 2 <= bytes.count else { throw invalid }
            if bytes[p..<p + 4] == Array("data".utf8)[...] { hasData = size > 0 }
            p = body + size + size % 2
        }
        guard p == bytes.count, hasData else { throw invalid }
        if u32(4) == bytes.count - 8 { return source }
        var repaired = source, length = UInt32(bytes.count - 8).littleEndian
        withUnsafeBytes(of: &length) { repaired.replaceSubrange(4..<8, with: $0) }
        return repaired
    }
}

struct LibraryDisk: Sendable {
    let root: URL
    init(owner: String, base: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]) throws {
        guard Book.validID(owner) else { throw ReaderError.message("账号标识无效。") }
        root = base.appendingPathComponent("TingyeNative", isDirectory: true).appendingPathComponent(owner, isDirectory: true)
        // Recover if the process was interrupted between the two restore renames.
        let rollback = root.appendingPathExtension("restore-backup")
        if FileManager.default.fileExists(atPath: rollback.path) {
            if !FileManager.default.fileExists(atPath: root.path) { try FileManager.default.moveItem(at: rollback, to: root) }
            else { try? FileManager.default.removeItem(at: rollback) }
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Books"), withIntermediateDirectories: true)
    }
    func file(_ id: String) throws -> URL {
        guard Book.validID(id) else { throw ReaderError.message("书籍标识无效。") }
        return root.appendingPathComponent("Books").appendingPathComponent(id + ".json")
    }
    func catalog() throws -> [ShelfEntry] {
        let url = root.appendingPathComponent("catalog.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try JSONDecoder().decode([ShelfEntry].self, from: Data(contentsOf: url))
    }
    func saveCatalog(_ entries: [ShelfEntry]) throws { try Integrity.encoder().encode(entries).write(to: root.appendingPathComponent("catalog.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) }
    func write(_ book: Book) throws { try Integrity.encoder().encode(book.validated()).write(to: file(book.id), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) }
    func read(_ id: String) throws -> Book { try JSONDecoder().decode(Book.self, from: Data(contentsOf: file(id))).validated() }
    func remove(_ id: String) throws { let url = try file(id); if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }; removeIndex(id) }

    /// 书架索引缓存（分类与封面缩略图）：重启后直接读取，免得每次启动都解码整本书（多图 EPUB 可达上百 MB）。
    struct IndexCache: Codable, Sendable { var category: String?; var hasCover: Bool }
    private var indexDirectory: URL { root.appendingPathComponent("Index", isDirectory: true) }
    func cachedIndex(_ id: String) -> (IndexCache, Data?)? {
        guard Book.validID(id), let data = try? Data(contentsOf: indexDirectory.appendingPathComponent(id + ".json")),
              let meta = try? JSONDecoder().decode(IndexCache.self, from: data) else { return nil }
        guard meta.hasCover else { return (meta, nil) }
        guard let cover = try? Data(contentsOf: indexDirectory.appendingPathComponent(id + ".jpg")) else { return nil }
        return (meta, cover)
    }
    func saveIndex(_ id: String, category: String?, cover: Data?) {
        guard Book.validID(id) else { return }
        try? FileManager.default.createDirectory(at: indexDirectory, withIntermediateDirectories: true)
        if let cover { try? cover.write(to: indexDirectory.appendingPathComponent(id + ".jpg"), options: .atomic) }
        if let data = try? JSONEncoder().encode(IndexCache(category: category, hasCover: cover != nil)) {
            try? data.write(to: indexDirectory.appendingPathComponent(id + ".json"), options: .atomic)
        }
    }
    /// 传入书籍标识只删这本的缓存；不传则清空全部。
    func removeIndex(_ id: String? = nil) {
        guard let id else { try? FileManager.default.removeItem(at: indexDirectory); return }
        guard Book.validID(id) else { return }
        for ext in ["json", "jpg"] { try? FileManager.default.removeItem(at: indexDirectory.appendingPathComponent(id + "." + ext)) }
    }
}

enum LegacyCatalog {
    static func entries(owner: String, directories: [URL]? = nil) throws -> [String: [String: JSONValue]] {
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let documents = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let candidates = directories ?? [support.appendingPathComponent("com.shatianrui.wereader/RCTAsyncLocalStorage_V1"), documents.appendingPathComponent("RCTAsyncLocalStorage_V1"), documents.appendingPathComponent("RCTAsyncLocalStorage")]
        let key = "tingye.vercel.catalog." + owner
        for directory in candidates {
            let path = directory.appendingPathComponent("manifest.json")
            guard fm.fileExists(atPath: path.path) else { continue }
            let manifest = try JSONDecoder().decode([String: JSONValue].self, from: Data(contentsOf: path))
            guard let value = manifest[key] else { continue }
            let data: Data
            if let inline = value.string { data = Data(inline.utf8) }
            else {
                let filename = Insecure.MD5.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
                data = try Data(contentsOf: directory.appendingPathComponent(filename))
            }
            let rows = try JSONDecoder().decode([[String: JSONValue]].self, from: data)
            var result: [String: [String: JSONValue]] = [:]
            for row in rows { if let id = row["id"]?.string, Book.validID(id) { result[id] = row } }
            return result
        }
        return [:]
    }
    static func row(book: Book, metadata: [String: JSONValue]?) -> ShelfEntry {
        guard let metadata else { return ShelfEntry(book: book) }
        let chapter = min(max(0, metadata["chapter"]?.int ?? 0), max(0, book.chapters.count - 1))
        let updatedAt = Double(max(0, metadata["updatedAt"]?.int ?? 0))
        var row = ShelfEntry(book: book, progress: .init(chapter: chapter, position: max(0, metadata["position"]?.int ?? 0), updatedAt: updatedAt))
        row.snapshotRevision = metadata["snapshotRevision"]?.string
        row.cloudRevision = metadata["cloudRevision"]?.string
        row.backupAt = metadata["backupAt"]?.int.map(Double.init)
        return row
    }
}

struct APIError: LocalizedError {
    let status: Int
    let code: String?
    let retryAfter: Double
    let message: String
    var errorDescription: String? { message }
}
