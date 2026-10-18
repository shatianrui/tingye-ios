import XCTest
import SwiftUI
import AVFoundation
import CoreText
@testable import Tingye

final class NativeCoreTests: XCTestCase {
    func testSpokenAudioSessionActivatesAndReactivatesAfterDeactivation() throws {
        let session = AVAudioSession.sharedInstance()
        defer { try? session.setActive(false, options: .notifyOthersOnDeactivation) }
        try SpeechAudioSession.activate()
        XCTAssertEqual(session.category, .playback)
        XCTAssertEqual(session.mode, .spokenAudio)
        try session.setActive(false, options: .notifyOthersOnDeactivation)
        try session.setCategory(.ambient, mode: .default)
        try SpeechAudioSession.activate()
        XCTAssertEqual(session.category, .playback)
        XCTAssertEqual(session.mode, .spokenAudio)
    }

    func testSentenceIndicesRemainCompatibleWithExistingClient() {
        let text = "我回来了。\n风，轻轻地吹！“还好吗？”\nHello world.\n最后一句"
        let parts = Sentence.split(text)
        XCTAssertEqual(parts.map(\.text), ["我回来了。", "风，轻轻地吹！", "“还好吗？”", "Hello world.", "最后一句"])
        for part in parts { XCTAssertEqual((text as NSString).substring(with: part.range), part.text) }
        XCTAssertEqual(Sentence.index(at: parts[3].range.location, in: parts), 3)
        let long = Sentence.split(String(repeating: "你", count: 401) + "。")
        XCTAssertTrue(long.allSatisfy { $0.text.count <= 181 })
        XCTAssertEqual(long.map(\.text).joined(), String(repeating: "你", count: 401) + "。")
    }
    func testGLMWithoutTimestampsGetsEstimatedPerCharacterTimingInsideSpeech() {
        // 0.5 s 静音 + 2 s 发声 + 1 s 尾部静音，16 kHz 单声道 16 位 PCM。
        let rate = 16000
        var samples = [Int16](repeating: 0, count: rate / 2)
        samples += (0..<rate * 2).map { Int16(8000 * sin(Double($0) * 0.2)) }
        samples += [Int16](repeating: 0, count: rate)
        var wav = Data("RIFF".utf8)
        func put(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { wav.append(contentsOf: $0) } }
        func put16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { wav.append(contentsOf: $0) } }
        put(UInt32(36 + samples.count * 2)); wav.append(contentsOf: Array("WAVEfmt ".utf8))
        put(16); put16(1); put16(1); put(UInt32(rate)); put(UInt32(rate * 2)); put16(2); put16(16)
        wav.append(contentsOf: Array("data".utf8)); put(UInt32(samples.count * 2))
        for sample in samples { put16(UInt16(bitPattern: sample)) }
        let span = try! XCTUnwrap(CloudSpeech.speechSpan(wav: wav))
        XCTAssertEqual(span.start, 0.5, accuracy: 0.02)
        XCTAssertEqual(span.end, 2.5, accuracy: 0.02)

        let words = CloudSpeech.estimatedWords("你好，世界。", from: span.start, to: span.end)
        XCTAssertEqual(words.map(\.text), ["你", "好", "，", "世", "界", "。"])
        XCTAssertEqual(words.first!.start, span.start, accuracy: 0.001)
        XCTAssertEqual(words.last!.end, span.end, accuracy: 0.001)
        for (a, b) in zip(words, words.dropFirst()) { XCTAssertEqual(a.end, b.start, accuracy: 0.0001); XCTAssertLessThan(a.start, a.end) }
        XCTAssertTrue(CloudSpeech.estimatedWords("  \n", from: 0, to: 1).isEmpty)
        XCTAssertTrue(CloudSpeech.estimatedWords("好", from: 1, to: 1).isEmpty)
        XCTAssertNil(CloudSpeech.speechSpan(wav: Data(repeating: 0, count: 64)))
    }

    func testMiniMaxTokenPlanAndHexDecoding() {
        XCTAssertEqual(CloudSpeech.minimaxOrigins.first?.absoluteString, "https://api.minimax.cn")
        let hex = "48656c6c6f"
        XCTAssertEqual(CloudSpeech.decodeHex(hex), Data("Hello".utf8))
        XCTAssertNil(CloudSpeech.decodeHex("invalid_hex!"))
        let upperHex = "414243"
        XCTAssertEqual(CloudSpeech.decodeHex(upperHex), Data("ABC".utf8))
        XCTAssertEqual(CloudSpeech.decodeHex(""), Data())

        let s1 = VoiceOptions.sanitized(provider: "minimax", model: "speech-2.8-turbo", voice: "female-shaonv")
        XCTAssertEqual(s1.model, "speech-2.8-turbo")
        XCTAssertEqual(s1.voice, "female-shaonv")

        let s2 = VoiceOptions.sanitized(provider: "minimax", model: "glm-4", voice: "tongtong")
        XCTAssertEqual(s2.model, "speech-2.8-hd")
        XCTAssertEqual(s2.voice, "male-qn-qingse")
    }

    func testEmojiAndUTF16Ranges() {
        let text = "山⛰️与书📖。春风又绿江南岸。"
        for line in Sentence.split(text) { XCTAssertEqual((text as NSString).substring(with: line.range), line.text) }
    }
    func testHTMLStripsActiveContentAndPreservesMarks() {
        let chapter = HTMLText.chapter("<head><title>hidden</title></head><h1>山水</h1><p>春<b>风</b>&amp;&#x4E66;。</p><script>steal()</script>", title: "fallback")
        XCTAssertEqual(chapter.title, "山水")
        XCTAssertTrue(chapter.text.contains("春风&书。"))
        XCTAssertFalse(chapter.text.contains("steal"))
        XCTAssertFalse(chapter.text.contains("hidden"))
        let mark = chapter.fields["marks"]?.array?.first?.object
        XCTAssertEqual(mark?["bold"]?.bool, true)
        XCTAssertEqual((chapter.text as NSString).substring(with: NSRange(location: mark!["start"]!.int!, length: mark!["end"]!.int! - mark!["start"]!.int!)), "风")
    }
    func testChapterSplittingAndEncodedText() throws {
        let parts = BookImporter.splitText("序言\n第一章 山水\n春风。\n第二章 归人\n归来。", title: "书")
        XCTAssertEqual(parts.map(\.title), ["卷首", "第一章 山水", "第二章 归人"])
        XCTAssertEqual(parts[1].text, "春风。")
        XCTAssertEqual(try BookImporter.decode(Data([0xEF,0xBB,0xBF] + Array("听页\r\n书斋".utf8))), "听页\n书斋")
        XCTAssertEqual(try BookImporter.decode(Data([0xCC,0xFD,0xD2,0xB3])), "听页")
        XCTAssertEqual(BookImporter.markdown("---\ntitle: 古书\naliases: [书]\n---\n# 正文\n春风。"), "# 正文\n春风。")
    }
    func testLegacyCatalogKeepsProgressAndCloudRevision() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let rows: [[String: JSONValue]] = [["id": .string("old-book"), "chapter": .number(1), "position": .number(5), "updatedAt": .number(10000), "snapshotRevision": .string("revision-v2")]]
        let manifest = ["tingye.vercel.catalog.reader": String(data: try Integrity.encoder().encode(rows), encoding: .utf8)!]
        try Integrity.encoder().encode(manifest).write(to: base.appendingPathComponent("manifest.json"))
        let found = try LegacyCatalog.entries(owner: "reader", directories: [base])
        let book = Book(id: "old-book", title: "旧书", format: "TXT", chapters: [Chapter(title: "一", text: "一。"), Chapter(title: "二", text: "二。")])
        let row = LegacyCatalog.row(book: book, metadata: found["old-book"])
        XCTAssertEqual(row.progress.chapter, 1); XCTAssertEqual(row.progress.position, 5)
        XCTAssertEqual(row.snapshotRevision, "revision-v2")
        XCTAssertTrue(try LegacyCatalog.entries(owner: "another-user", directories: [base]).isEmpty)
    }
    func testEPUBPathsCannotEscapeOrLoadRemoteContent() throws {
        XCTAssertEqual(try BookImporter.resolve(base: "OEBPS/Text/a.xhtml", href: "../Images/a%20b.png"), "OEBPS/Images/a b.png")
        XCTAssertThrowsError(try BookImporter.resolve(base: "a.opf", href: "../outside"))
        XCTAssertThrowsError(try BookImporter.resolve(base: "a.opf", href: "https://example.com/a"))
        XCTAssertThrowsError(try BookImporter.resolve(base: "a.opf", href: "%2E%2E/outside"))
    }
    func testBackupRoundTripPreservesOtherClientFields() throws {
        let chapter = Chapter(title: "章", text: "一。二。", extras: ["document": .object(["html": .string("<p>一。二。</p>"), "css": .string("p{color:red}")])])
        let book = Book(id: "book-1", title: "书", format: "EPUB", chapters: [chapter], extras: ["resources": .object(["r0": .string("data:image/png;base64,AAAA")])])
        let packet = BackupPacket(book: book, progress: .init(chapter: 0, position: 1, updatedAt: 1000))
        let data = try Integrity.encoder().encode(packet)
        let result = try JSONDecoder().decode(BackupPacket.self, from: data).validated(id: "book-1")
        XCTAssertEqual(result.book, book); XCTAssertEqual(result.progress.position, 1)
        XCTAssertEqual(Integrity.sha256(Data("abc".utf8)), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        var wrong = packet; wrong.progress.chapter = 8
        XCTAssertThrowsError(try wrong.validated(id: "book-1"))
        XCTAssertThrowsError(try packet.validated(id: "another-book"))
    }
    func testCatalogReservedNameAndAccountIsolation() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let first = try LibraryDisk(owner: "user-a", base: base), second = try LibraryDisk(owner: "user-b", base: base)
        let book = Book(id: "catalog", title: "不冲突", format: "TXT", chapters: [Chapter(title: "正文", text: "一个句子。")])
        try first.write(book); try first.saveCatalog([ShelfEntry(book: book)])
        XCTAssertEqual(try first.read("catalog"), book)
        XCTAssertEqual(try first.catalog().count, 1)
        XCTAssertThrowsError(try second.read("catalog"))
        XCTAssertThrowsError(try first.file("../../secret"))
        XCTAssertThrowsError(try LibraryDisk(owner: "../outside", base: base))
    }
    func testSignedKeychainRoundTrip() throws {
        let key = "test-" + UUID().uuidString
        defer { try? Keychain.remove(key) }
        try Keychain.save(Data("original".utf8), key: key)
        try Keychain.save(Data("updated".utf8), key: key)
        XCTAssertEqual(try Keychain.data(key), Data("updated".utf8))
        try Keychain.remove(key); XCTAssertNil(try Keychain.data(key))
    }
    @MainActor func testPaginationCoversEveryCharacterWithoutGaps() {
        let chapter = Chapter(title: "长章", text: String(repeating: "我冒了严寒，回到相隔二千余里，别了二十余年的故乡去。📖\n", count: 100))
        let text = NativeTypesetter.attributed(chapter, preferences: .init())
        let pages = NativeTypesetter.pages(text, size: CGSize(width: 345, height: 510))
        XCTAssertGreaterThan(pages.count, 1)
        XCTAssertEqual(pages.first?.location, 0)
        XCTAssertEqual(pages.reduce(0) { $0 + $1.length }, text.length)
        for i in 1..<pages.count { XCTAssertEqual(NSMaxRange(pages[i-1]), pages[i].location) }
        XCTAssertEqual(pages.map { text.attributedSubstring(from: $0).string }.joined(), chapter.text)
    }
    /// 每页单独排版时也要完整显示：页首在段落中间不能再加首行缩进，否则页尾的字被挤掉。
    @MainActor func testEveryPageRendersAllOfItsCharacters() {
        let paragraph = String(repeating: "春眠不觉晓，处处闻啼鸟。夜来风雨声，花落知多少。", count: 40)
        let chapter = Chapter(title: "长段", text: paragraph + "\n" + paragraph)
        let size = CGSize(width: 346, height: 620)
        let text = NativeTypesetter.attributed(chapter, preferences: .init())
        let pages = NativeTypesetter.pages(text, size: size)
        XCTAssertGreaterThan(pages.count, 2)
        let path = CGPath(rect: CGRect(origin: .zero, size: size), transform: nil)
        for (index, range) in pages.enumerated() {
            let page = NativeTypesetter.page(text, range: range)
            XCTAssertEqual(page.string, (text.string as NSString).substring(with: range))
            let frame = CTFramesetterCreateFrame(CTFramesetterCreateWithAttributedString(page), CFRange(location: 0, length: 0), path, nil)
            XCTAssertEqual(CTFrameGetVisibleStringRange(frame).length, range.length, "第 \(index + 1) 页有字被挤出")
        }
    }
    func testEPUBAndDOCXImportFixtures() throws {
        let base = try XCTUnwrap(Bundle(for: Self.self).resourceURL?.appendingPathComponent("Fixtures"))
        let epub = try BookImporter.read(base.appendingPathComponent("book.epub")).book
        XCTAssertEqual(epub.title, "山水书")
        XCTAssertEqual(epub.chapters.count, 2)
        XCTAssertTrue(epub.chapters[0].text.contains("春风"))
        XCTAssertTrue(epub.chapters[1].text.contains("归人"))
        let docx = try BookImporter.read(base.appendingPathComponent("book.docx")).book
        XCTAssertTrue(docx.chapters[0].text.contains("听页原生阅读"))
    }
    @MainActor func testBundledFontAndSamples() {
        XCTAssertNotNil(UIFont(name: Theme.serifName, size: 20))
        XCTAssertEqual(Samples.books.count, 3)
        XCTAssertTrue(Samples.books.allSatisfy(\.sample))
    }
    @MainActor func testSpeechHighlightUsesUTF16AndKeepsSourceUnchanged() {
        let chapter = Chapter(title: "正文", text: "山📖。清风徐来，水波不兴。")
        let source = NativeTypesetter.attributed(chapter, preferences: .init())
        let sentences = Sentence.split(chapter.text)
        let word = (chapter.text as NSString).range(of: "水波")
        let result = SpeechHighlight.apply(to: source, sentence: sentences[1].range)
        XCTAssertEqual(result.string, source.string)
        XCTAssertNil(source.attribute(.backgroundColor, at: word.location, effectiveRange: nil))
        XCTAssertEqual(result.attribute(.backgroundColor, at: word.location, effectiveRange: nil) as? UIColor, UIColor(Theme.wash))
        for offset in sentences[1].range.location..<NSMaxRange(sentences[1].range) {
            XCTAssertEqual(result.attribute(.backgroundColor, at: offset, effectiveRange: nil) as? UIColor, UIColor(Theme.wash))
            XCTAssertEqual(result.attribute(.foregroundColor, at: offset, effectiveRange: nil) as? UIColor, source.attribute(.foregroundColor, at: offset, effectiveRange: nil) as? UIColor)
        }
        XCTAssertNil(result.attribute(.backgroundColor, at: 0, effectiveRange: nil))
        let invalid = SpeechHighlight.apply(to: source, sentence: NSRange(location: 9999, length: 30))
        XCTAssertEqual(invalid.string, source.string)
    }
    /// GLM 与 MiniMax 的模型、音色互不串用；已串用的旧值回到各自默认值。
    func testVoiceOptionsKeepProvidersSeparate() {
        XCTAssertEqual(VoiceOptions.sanitized(provider: "minimax", model: "glm-tts", voice: "tongtong").model, "speech-2.8-hd")
        XCTAssertEqual(VoiceOptions.sanitized(provider: "minimax", model: "glm-tts", voice: "tongtong").voice, "male-qn-qingse")
        XCTAssertEqual(VoiceOptions.sanitized(provider: "glm", model: "speech-2.8-hd", voice: "female-shaonv").model, "glm-tts")
        XCTAssertEqual(VoiceOptions.sanitized(provider: "glm", model: "speech-2.8-hd", voice: "female-shaonv").voice, "tongtong")
        XCTAssertEqual(VoiceOptions.sanitized(provider: "minimax", model: "speech-02-turbo", voice: "audiobook_female_1").model, "speech-02-turbo")
        XCTAssertEqual(VoiceOptions.sanitized(provider: "glm", model: "glm-tts", voice: "xiaochen").voice, "xiaochen")
        XCTAssertEqual(VoiceOptions.sanitized(provider: "system", model: "glm-tts", voice: "tongtong").voice, "")
    }
    /// 旧版不分服务商的设置按内容迁到各自的键，不覆盖已有的分服务商设置。
    func testLegacyVoiceSettingsMigrateToOwningProvider() throws {
        let suite = "voice-migration-\(UUID().uuidString)"
        let d = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { d.removePersistentDomain(forName: suite) }
        d.set("speech-02-hd", forKey: "voice.model"); d.set("tongtong", forKey: "voice.id")
        d.set("speech-2.6-turbo", forKey: "voice.model.minimax")
        VoiceOptions.migrateLegacy(defaults: d, moveSecret: false)
        XCTAssertEqual(d.string(forKey: "voice.model.minimax"), "speech-2.6-turbo", "已有的 MiniMax 模型不被旧值覆盖")
        XCTAssertEqual(d.string(forKey: "voice.name.glm"), "tongtong", "GLM 预设音色迁到 GLM")
        XCTAssertNil(d.string(forKey: "voice.model")); XCTAssertNil(d.string(forKey: "voice.id"))
    }
    func testOriginalDocumentRetainsTablesResourcesAndBlocksActiveContent() {
        let raw = "<table><tr><td>正文</td></tr></table><img src='tingye-resource:r0' onerror='bad()'><script>bad()</script>"
        let html = OriginalDocument.html(raw, css: "table {color:red}")
        XCTAssertTrue(html.contains("<table>"))
        // 图片保留引用，由 ResourceSchemeHandler 按需提供，不再内嵌 base64。
        XCTAssertTrue(html.contains("src='tingye-resource:r0'"))
        XCTAssertTrue(html.contains("img-src data: tingye-resource:"))
        XCTAssertEqual(ResourceSchemeHandler.decode("data:image/png;base64,AAAA")?.1, "image/png")
        XCTAssertEqual(OriginalDocument.closingSelfClosedTags(#"<p>a<span class="x"/>b<br/><img src="i"/><a id='k' /></p>"#), #"<p>a<span class="x"></span>b<br/><img src="i"/><a id='k'></a></p>"#)
        XCTAssertTrue(html.contains("table {color:red}"))
        XCTAssertFalse(html.contains("onerror="))
        XCTAssertFalse(html.contains("<script>"))
        XCTAssertTrue(html.contains("script-src 'none'"))
    }
    func testEPUBRetainsOriginalHTMLAndStylesForRepair() throws {
        let base = try XCTUnwrap(Bundle(for: Self.self).resourceURL?.appendingPathComponent("Fixtures"))
        let book = try BookImporter.read(base.appendingPathComponent("book.epub")).book
        XCTAssertTrue(book.chapters.allSatisfy { $0.fields["document"]?.object?["html"]?.string != nil })
        let data = try Integrity.encoder().encode(book)
        XCTAssertEqual(try JSONDecoder().decode(Book.self, from: data), book)
    }
    @MainActor func testKaiFontIsBundled() { XCTAssertNotNil(UIFont(name: "LXGWWenKaiLite-Regular", size: 21)) }

}

import WebKit

final class ProgressAndBackupTests: XCTestCase {
    func testSingleChapterProgressAndOldCatalogCompatibility() throws {
        let book = Book(id: "progress", title: "四百句", format: "TXT", chapters: [Chapter(title: "正文", text: String(repeating: "一句。", count: 400))])
        var row = ShelfEntry(book: book)
        XCTAssertEqual(row.percentText, "未开卷")
        row.progress = .init(chapter: 0, position: 197, updatedAt: 1)
        XCTAssertEqual(row.readFraction, 198.0 / 400.0, accuracy: 0.00001)
        XCTAssertEqual(row.percentText, "50%")
        row.progress.position = 0
        XCTAssertLessThan(row.readFraction, 0.01)
        row.progress.position = 399
        XCTAssertEqual(row.readFraction, 1)
        var old = try XCTUnwrap(JSONSerialization.jsonObject(with: Integrity.encoder().encode(row)) as? [String: Any])
        old.removeValue(forKey: "sentenceCounts")
        let decoded = try JSONDecoder().decode(ShelfEntry.self, from: JSONSerialization.data(withJSONObject: old))
        XCTAssertNil(decoded.sentenceCounts)
        XCTAssertLessThan(decoded.readFraction, 1)
        let packet = try Integrity.encoder().encode(BackupPacket(book: book, progress: row.progress))
        XCTAssertFalse(String(decoding: packet, as: UTF8.self).contains("sentenceCounts"))
    }
    func testInterruptedRestoreRecoversPreviousLibrary() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let disk = try LibraryDisk(owner: "guest", base: base)
        let book = Book(id: "safe", title: "保留", format: "TXT", chapters: [Chapter(title: "正文", text: "原书。")])
        try disk.write(book); try disk.saveCatalog([ShelfEntry(book: book)])
        try FileManager.default.moveItem(at: disk.root, to: disk.root.appendingPathExtension("restore-backup"))
        let recovered = try LibraryDisk(owner: "guest", base: base)
        XCTAssertEqual(try recovered.read(book.id), book)
        XCTAssertEqual(try recovered.catalog().count, 1)
    }
    func testWeightedChaptersEmptyTextAndOutOfRangeProgress() {
        let book = Book(title: "混合", format: "TXT", chapters: [Chapter(title: "一", text: "一。二。"), Chapter(title: "二", text: "三。四。五。六。"), Chapter(title: "插图", text: "")])
        var row = ShelfEntry(book: book, progress: .init(chapter: 1, position: 1, updatedAt: 1))
        XCTAssertEqual(row.readFraction, 4.0 / 7.0, accuracy: 0.00001)
        row.progress = .init(chapter: 999, position: 999, updatedAt: 1)
        XCTAssertEqual(row.readFraction, 1)
        row.progress = .init(chapter: -1, position: -1, updatedAt: 1)
        XCTAssertGreaterThanOrEqual(row.readFraction, 0)
    }
    func testICloudSnapshotsRestoreResourcesProgressBookmarksAndKeepOtherBooks() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let store = ICloudBackupStore(root: base.appendingPathComponent("cloud"))
        let disk = try LibraryDisk(owner: "guest", base: base)
        let chapter = HTMLText.chapter("<p>春<b>风</b>。归来。</p>", title: "正文")
        let book = Book(id: "restore", title: "书", format: "EPUB", chapters: [chapter], extras: ["resources": .object(["r0": .string("data:image/png;base64,AAAA")])])
        let other = Book(id: "other", title: "保留", format: "TXT", chapters: [Chapter(title: "正文", text: "另一书。")])
        try disk.write(other); try disk.saveCatalog([ShelfEntry(book: other)])
        let mark = Bookmark(chapter: 0, position: 1, excerpt: "归来。")
        let archive = ICloudArchive(owner: "guest", books: [.init(packet: .init(book: book, progress: .init(chapter: 0, position: 1, updatedAt: 123)), bookmarks: [mark])])
        let first = try store.save(archive), second = try store.save(archive)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(try store.snapshots(owner: "guest").count, 2)
        XCTAssertTrue(try store.snapshots(owner: "other-account").isEmpty)
        let recovered = try store.read(first, owner: "guest")
        let rows = try disk.restore(recovered, owner: "guest", entries: disk.catalog())
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(try disk.read(book.id), book)
        XCTAssertEqual(try disk.read(other.id), other)
        let row = try XCTUnwrap(rows.first { $0.id == book.id })
        XCTAssertEqual(row.progress.position, 1)
        XCTAssertEqual(row.bookmarks.first?.id, mark.id)
        XCTAssertEqual(row.sentenceCounts, [2])
        XCTAssertEqual(try disk.catalog().count, 2)
        XCTAssertThrowsError(try store.read(first, owner: "other-account"))
        let before = try Data(contentsOf: disk.root.appendingPathComponent("catalog.json"))
        var invalid = recovered; invalid.books[0].packet.progress.chapter = 999
        XCTAssertThrowsError(try disk.restore(invalid, owner: "guest", entries: rows))
        XCTAssertEqual(try Data(contentsOf: disk.root.appendingPathComponent("catalog.json")), before)
        try Data("broken".utf8).write(to: second)
        XCTAssertThrowsError(try store.read(second, owner: "guest"))
        XCTAssertEqual(try disk.read(book.id), book)
    }

    /// 新设备以 guest 运行时，旧账号目录下的快照仍可被发现并还原进当前书库。
    func testICloudRestoreFallsBackToSnapshotsUnderOtherOwners() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let store = ICloudBackupStore(root: base.appendingPathComponent("cloud"))
        let disk = try LibraryDisk(owner: "guest", base: base)
        let book = Book(id: "legacy", title: "旧书", format: "TXT", chapters: [Chapter(title: "正文", text: "旧账号的书。")])
        let archive = ICloudArchive(owner: "legacy-account", books: [.init(packet: .init(book: book, progress: .init(chapter: 0, position: 0, updatedAt: 123)), bookmarks: [])])
        let saved = try store.save(archive)
        XCTAssertTrue(try store.snapshots(owner: "guest").isEmpty)
        XCTAssertEqual(try store.snapshotOwners(), ["legacy-account"])
        let found = try XCTUnwrap(store.latestSnapshotAcrossOwners())
        XCTAssertEqual(found.owner, "legacy-account")
        XCTAssertEqual(found.url, saved)
        let recovered = try store.read(found.url, owner: found.owner)
        let rows = try disk.restore(recovered, owner: "guest", entries: disk.catalog())
        XCTAssertEqual(rows.map(\.id), [book.id])
        XCTAssertEqual(try disk.read(book.id), book)
        // 目录账号与存档记录不一致时仍拒绝。
        XCTAssertThrowsError(try store.read(found.url, owner: "guest"))
    }

    /// 当前账号（guest）目录里的旧快照不能遮住其他账号目录中更新的备份。
    func testICloudLatestSnapshotPrefersNewestAcrossOwners() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let store = ICloudBackupStore(root: base.appendingPathComponent("cloud"))
        let book = Book(id: "b", title: "书", format: "TXT", chapters: [Chapter(title: "正文", text: "内容。")])
        let item = ICloudArchive.Item(packet: .init(book: book, progress: .init(chapter: 0, position: 0, updatedAt: 1)), bookmarks: [])
        _ = try store.save(ICloudArchive(owner: "guest", createdAt: Date(timeIntervalSince1970: 1_000), books: [item]))
        let newer = try store.save(ICloudArchive(owner: "account", createdAt: Date(timeIntervalSince1970: 2_000), books: [item]))
        let found = try XCTUnwrap(store.latestSnapshotAcrossOwners())
        XCTAssertEqual(found.owner, "account")
        XCTAssertEqual(found.url, newer)
    }

    /// 删除书籍时从快照中移除该书：含其他书的快照被改写，只含该书的快照被删除。
    func testICloudRemoveBookRewritesSnapshotsAndDeletesEmptyOnes() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let store = ICloudBackupStore(root: base.appendingPathComponent("cloud"))
        let target = Book(id: "target", title: "待删", format: "TXT", chapters: [Chapter(title: "正文", text: "要删除的书。")])
        let kept = Book(id: "kept", title: "保留", format: "TXT", chapters: [Chapter(title: "正文", text: "保留的书。")])
        let both = ICloudArchive(owner: "guest", books: [target, kept].map { .init(packet: .init(book: $0, progress: .init()), bookmarks: []) })
        let onlyTarget = ICloudArchive(owner: "legacy-account", books: [.init(packet: .init(book: target, progress: .init()), bookmarks: [])])
        let bothURL = try store.save(both), onlyURL = try store.save(onlyTarget)
        let result = try await store.removeBook("target")
        XCTAssertEqual(result.rewritten, 1)
        XCTAssertEqual(result.deleted, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: onlyURL.path))
        let remaining = try store.read(bothURL, owner: "guest")
        XCTAssertEqual(remaining.books.map { $0.packet.book.id }, ["kept"])
        XCTAssertEqual(try store.snapshots(owner: "legacy-account").count, 0)
    }

    func testICloudTransferShowsRealCountsOnlyForCountableStages() {
        var transfer = ICloudTransfer(kind: .restore, stage: .connecting)
        XCTAssertNil(transfer.fraction); XCTAssertTrue(transfer.running); XCTAssertTrue(transfer.cancellable)
        transfer.advance(.downloading, completed: 3, total: 10)
        XCTAssertNil(transfer.fraction, "下载进度不可测，不能显示百分比")
        XCTAssertEqual(transfer.activity, "等待 iCloud 下载")
        transfer.advance(.validating, completed: 2, total: 5)
        XCTAssertEqual(try XCTUnwrap(transfer.fraction), 0.4, accuracy: 0.0001)
        XCTAssertEqual(transfer.countText, "2/5 本")
        XCTAssertEqual(transfer.steps, [.connecting, .finding, .downloading, .reading, .validating])
        transfer.advance(.confirming)
        XCTAssertFalse(transfer.running); XCTAssertFalse(transfer.finished); XCTAssertFalse(transfer.cancellable)
        var apply = ICloudTransfer(kind: .restore, stage: .restoring)
        apply.advance(.restoring, completed: 0, total: 0)
        XCTAssertNil(apply.fraction)
        apply.advance(.replacing)
        XCTAssertFalse(apply.cancellable)
        apply.advance(.failed, detail: "磁盘已满")
        XCTAssertEqual(apply.lastActive, .replacing)
        XCTAssertEqual(apply.steps, [.restoring, .replacing, .reloading])
        XCTAssertTrue(apply.finished); XCTAssertEqual(apply.title, "还原失败")
        var backup = ICloudTransfer(kind: .backup, stage: .writing)
        XCTAssertNil(backup.fraction)
        backup.advance(.done)
        XCTAssertEqual(backup.title, "备份已写入")
        XCTAssertFalse(ICloudUploadStatus(url: URL(fileURLWithPath: "/a"), state: .waiting).settled)
        XCTAssertFalse(ICloudUploadStatus(url: URL(fileURLWithPath: "/a"), state: .waiting).text.contains("已确认"))
        XCTAssertTrue(ICloudUploadStatus(url: URL(fileURLWithPath: "/a"), state: .uploaded).settled)
    }

    func testICloudReadAndRestoreReportPerBookProgressAndRejectEmptyOrBrokenBackups() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let store = ICloudBackupStore(root: base.appendingPathComponent("cloud"))
        let disk = try LibraryDisk(owner: "guest", base: base)
        let books = (0..<3).map { Book(id: "b\($0)", title: "书\($0)", format: "TXT", chapters: [Chapter(title: "一", text: "第\($0)句。")]) }
        let archive = ICloudArchive(owner: "guest", books: books.map { .init(packet: .init(book: $0, progress: .init()), bookmarks: []) })
        let url = try store.save(archive)
        XCTAssertEqual(try store.downloadState(url, owner: "guest", request: false), .ready)
        XCTAssertEqual(try store.uploadState(url), .notUbiquitous)
        let calls = ProgressCalls()
        let read = try store.read(url, owner: "guest") { calls.add($0, $1) }
        XCTAssertEqual(calls.values, [[0, 3], [1, 3], [2, 3], [3, 3]])
        let restored = ProgressCalls()
        let rows = try disk.restore(read, owner: "guest", entries: [], progress: { restored.add($0, $1) }, willReplace: { restored.add(-1, -1) })
        XCTAssertEqual(restored.values, [[0, 3], [1, 3], [2, 3], [3, 3], [-1, -1]])
        XCTAssertEqual(rows.count, 3)

        XCTAssertThrowsError(try ICloudArchive(owner: "guest", books: []).validated(owner: "guest")) {
            XCTAssertTrue($0.localizedDescription.contains("不包含书籍"))
        }
        let before = try Data(contentsOf: disk.root.appendingPathComponent("catalog.json"))
        XCTAssertThrowsError(try disk.restore(ICloudArchive(owner: "guest", books: []), owner: "guest", entries: rows))
        XCTAssertEqual(try Data(contentsOf: disk.root.appendingPathComponent("catalog.json")), before)
        try Data("{\"format\":1}".utf8).write(to: url)
        XCTAssertThrowsError(try store.read(url, owner: "guest")) { XCTAssertTrue($0.localizedDescription.contains("无法解析")) }
    }

    func testICloudSnapshotsListUndownloadedPlaceholdersAndReportDownloadState() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let store = ICloudBackupStore(root: base)
        let directory = try store.directory(owner: "guest")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data().write(to: directory.appendingPathComponent(".2000-b.json.icloud"))
        try Data().write(to: directory.appendingPathComponent("1000-a.json"))
        try Data().write(to: directory.appendingPathComponent("notes.txt"))
        let list = try store.snapshots(owner: "guest")
        XCTAssertEqual(list.map(\.lastPathComponent), ["2000-b.json", "1000-a.json"])
        XCTAssertEqual(try store.downloadState(list[0], owner: "guest", request: false), .downloading)
        XCTAssertThrowsError(try store.decode(list[0], owner: "guest")) { XCTAssertTrue($0.localizedDescription.contains("尚未从 iCloud 下载完成")) }
        XCTAssertThrowsError(try store.downloadState(directory.appendingPathComponent("3000-c.json"), owner: "guest", request: false)) {
            XCTAssertTrue($0.localizedDescription.contains("已被移除"))
        }
        XCTAssertThrowsError(try store.downloadState(base.appendingPathComponent("x.json"), owner: "guest", request: false))
        XCTAssertTrue(try ICloudBackupStore(root: base.appendingPathComponent("none")).snapshots(owner: "guest").isEmpty)
    }

    @MainActor func testProgressSyncStatusReportsOnlyLocalFacts() throws {
        let suite = "tests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = MemoryKeyValueStore()
        var signedIn = false
        let sync = ProgressSync(store: store, defaults: defaults, account: { signedIn })
        XCTAssertEqual(sync.summary(enabled: true).title, "等待 iCloud")
        signedIn = true; sync.refreshAccount()
        XCTAssertEqual(sync.summary(enabled: true).title, "已开启 · 等待 iCloud")
        XCTAssertTrue(sync.synchronize())

        let book = Book(id: "sync", title: "同步", format: "TXT", chapters: [Chapter(title: "一", text: "一。二。"), Chapter(title: "二", text: "三。")])
        var entry = ShelfEntry(book: book, progress: .init(chapter: 1, position: 0, updatedAt: 100))
        XCTAssertTrue(sync.push(entry))
        XCTAssertFalse(sync.push(entry), "远端已有同样新的进度时不重复提交")
        sync.recordCommit(1)
        XCTAssertEqual(sync.lastCommitCount, 1)
        let summary = sync.summary(enabled: true)
        XCTAssertEqual(summary.title, "已开启")
        for text in [summary.detail, ICloudUploadStatus(url: URL(fileURLWithPath: "/a"), state: .uploading).text] {
            XCTAssertFalse(text.contains("已上传") || text.contains("已送达") || text.contains("秒内"))
        }

        store.values[ProgressSync.key(entry)] = ["c": 0, "p": 1, "t": 200.0]
        XCTAssertTrue(sync.receive(reason: NSUbiquitousKeyValueStoreServerChange, keys: [ProgressSync.key(entry), "other"]))
        XCTAssertEqual(sync.lastReceivedCount, 1)
        XCTAssertEqual(sync.newer(than: entry), ReadingProgress(chapter: 0, position: 1, updatedAt: 200))
        sync.recordMerge(applied: 0, kept: 1)
        XCTAssertEqual(sync.lastKept, 1)
        XCTAssertFalse(sync.receive(reason: NSUbiquitousKeyValueStoreServerChange, keys: ["unrelated"]))
        entry.progress.updatedAt = 300
        XCTAssertNil(sync.newer(than: entry))

        sync.recordFailure("合并其他设备的阅读进度失败：磁盘已满")
        XCTAssertEqual(sync.summary(enabled: true).title, "同步出错")
        sync.recordMerge(applied: 0, kept: 0)
        XCTAssertNil(sync.lastError)
        XCTAssertFalse(sync.receive(reason: NSUbiquitousKeyValueStoreQuotaViolationChange, keys: []))
        XCTAssertTrue(sync.summary(enabled: true).problem)
        store.available = false
        XCTAssertFalse(sync.synchronize())
        XCTAssertEqual(sync.lastError, ProgressSync.unavailableMessage)
        store.available = true
        XCTAssertTrue(sync.synchronize())
        XCTAssertNil(sync.lastError)

        defaults.set(false, forKey: ProgressSync.enabledKey)
        XCTAssertFalse(sync.push(entry))
        XCTAssertNil(sync.newer(than: ShelfEntry(book: book)))
        XCTAssertEqual(sync.summary(enabled: false).title, "已关闭")
    }

    @MainActor private func makeSync(_ store: MemoryKeyValueStore) throws -> (ProgressSync, UserDefaults, String) {
        let suite = "tests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        return (ProgressSync(store: store, defaults: defaults, account: { true }), defaults, suite)
    }
    private func syncBook(_ title: String = "红楼梦", author: String = "曹雪芹", chapters: Int = 3) -> Book {
        Book(id: UUID().uuidString, title: title, author: author, format: "TXT", chapters: (0..<chapters).map { Chapter(title: "\($0)", text: "一。二。三。") })
    }

    @MainActor func testClosingReaderDoesNotOverwriteNewerRemoteProgressAndAppliesItAfterwards() throws {
        let store = MemoryKeyValueStore()
        let (sync, defaults, suite) = try makeSync(store); defer { defaults.removePersistentDomain(forName: suite) }
        let book = syncBook()
        let local = ShelfEntry(book: book, progress: .init(chapter: 1, position: 0, updatedAt: 100))
        store.values[ProgressSync.key(local)] = ["c": 2, "p": 1, "t": 200.0]
        // 阅读中：远端进度被搁置。
        let reading = sync.merge([local], protected: [book.id])
        XCTAssertEqual(reading.kept, 1); XCTAssertTrue(reading.applied.isEmpty)
        XCTAssertEqual(reading.entries[0].progress, local.progress)
        // 关闭阅读页：位置未变，不产生新时间戳，也不推送。
        XCTAssertNil(sync.update(local, chapter: 1, position: 0, now: 999_999))
        XCTAssertFalse(sync.push(local))
        XCTAssertEqual((store.values[ProgressSync.key(local)] as? [String: Any])?["t"] as? Double, 200)
        // 关闭后重新合并：应用远端。
        let closed = sync.merge(reading.entries, protected: [])
        XCTAssertEqual(closed.applied, [book.id])
        XCTAssertEqual(closed.entries[0].progress, ReadingProgress(chapter: 2, position: 1, updatedAt: 200))
        // 真正移动了位置才写入。
        XCTAssertNotNil(sync.update(closed.entries[0], chapter: 2, position: 2))
        XCTAssertNotNil(sync.update(ShelfEntry(book: book), chapter: 0, position: 0), "未开卷的书首次打开需要记录")
    }

    @MainActor func testLocalWritesAfterSeeingRemoteAreNewerDespiteClockSkew() throws {
        let store = MemoryKeyValueStore()
        let (sync, defaults, suite) = try makeSync(store); defer { defaults.removePersistentDomain(forName: suite) }
        let book = syncBook()
        let local = ShelfEntry(book: book, progress: .init(chapter: 0, position: 0, updatedAt: 1_000))
        let fast = 5_000_000.0  // 另一台设备时钟快了很多
        store.values[ProgressSync.key(local)] = ["c": 1, "p": 0, "t": fast]
        let merged = sync.merge([local], protected: [])
        XCTAssertEqual(merged.entries[0].progress.updatedAt, fast)
        XCTAssertEqual(sync.clock, fast)
        let mine = try XCTUnwrap(sync.update(merged.entries[0], chapter: 1, position: 2, now: 2_000))
        XCTAssertEqual(mine.updatedAt, fast + 1)
        var moved = merged.entries[0]; moved.progress = mine
        XCTAssertTrue(sync.push(moved), "看过远端之后的本机操作必须被视为更新")
        XCTAssertEqual((store.values[ProgressSync.key(local)] as? [String: Any])?["p"] as? Int, 2)
        XCTAssertGreaterThan(sync.stamp(now: 0), mine.updatedAt, "时间戳单调递增")
        XCTAssertEqual(sync.stamp(now: 9e9), 9e9, "本机时钟更晚时直接用本机时间")
        let reloaded = ProgressSync(store: store, defaults: defaults, account: { true })
        XCTAssertGreaterThanOrEqual(reloaded.clock, 9e9, "时钟持久保存")
    }

    @MainActor func testFingerprintIgnoresChapterCountAndWhitespaceAndKeepsLegacyKeys() throws {
        let store = MemoryKeyValueStore()
        let (sync, defaults, suite) = try makeSync(store); defer { defaults.removePersistentDomain(forName: suite) }
        let a = ShelfEntry(book: syncBook("Red  Chamber", author: "Cao Xueqin", chapters: 3))
        let b = ShelfEntry(book: syncBook("red chamber", author: " CAO XUEQIN ", chapters: 5))
        let c = ShelfEntry(book: syncBook("Ｒｅｄ Chamber", author: "Cao Xueqin", chapters: 2))
        XCTAssertEqual(ProgressSync.key(a), ProgressSync.key(b))
        XCTAssertEqual(ProgressSync.key(a), ProgressSync.key(c), "全角半角视为同一书名")
        XCTAssertNotEqual(ProgressSync.key(a), ProgressSync.key(ShelfEntry(book: syncBook("Red Chamber 2", author: "Cao Xueqin"))))
        XCTAssertNotEqual(ProgressSync.key(a), ProgressSync.key(ShelfEntry(book: syncBook("Red Chamber", author: "Other"))))
        XCTAssertNotEqual(ProgressSync.key(a), ProgressSync.legacyKey(a))
        XCTAssertTrue(ProgressSync.key(a).hasPrefix("progress."))
        // 删并章节后仍匹配；越界章节不应用。
        store.values[ProgressSync.key(b)] = ["c": 4, "p": 0, "t": 50.0]
        XCTAssertNil(sync.newer(than: a), "远端章节超出本机章数时忽略")
        store.values[ProgressSync.key(b)] = ["c": 2, "p": 1, "t": 50.0]
        XCTAssertEqual(sync.newer(than: a)?.chapter, 2)
        // 旧版本写入的旧键仍可读取，并迁移到新键；推送时新旧键同时写入。
        store.values = [:]
        let old = ShelfEntry(book: syncBook(chapters: 3))
        store.values[ProgressSync.legacyKey(old)] = ["c": 1, "p": 2, "t": 80.0]
        let migrated = sync.merge([old], protected: [])
        XCTAssertEqual(migrated.entries[0].progress, ReadingProgress(chapter: 1, position: 2, updatedAt: 80))
        var mine = migrated.entries[0]
        mine.progress = try XCTUnwrap(sync.update(mine, chapter: 2, position: 0, now: 10))
        XCTAssertTrue(sync.push(mine))
        for key in [ProgressSync.key(old), ProgressSync.legacyKey(old)] {
            XCTAssertEqual((store.values[key] as? [String: Any])?["c"] as? Int, 2)
        }
        // 新键较旧、旧键较新时取较新的一条。
        store.values[ProgressSync.legacyKey(old)] = ["c": 0, "p": 0, "t": 1e12]
        XCTAssertEqual(sync.newer(than: mine)?.updatedAt, 1e12)
    }

    func testCatalystEntitlementsIncludeKeyValueStore() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        for name in ["Tingye-macOS.entitlements", "Tingye.entitlements"] {
            let data = try Data(contentsOf: root.appendingPathComponent("Tingye/" + name))
            let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
            XCTAssertEqual(plist["com.apple.developer.ubiquity-kvstore-identifier"] as? String, "$(TeamIdentifierPrefix)$(CFBundleIdentifier)", name)
        }
    }

    @MainActor func testOriginalWebViewHighlightsAcrossTagsRepeatedSentencesAndClears() async throws {
        let loaded = expectation(description: "WebKit loaded")
        let delegate = LoadDelegate { loaded.fulfill() }
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        config.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 600), configuration: config)
        web.navigationDelegate = delegate
        let html = "<p>春<b>风</b>📖。归来。</p><p>归来。</p><script>window.unsafe = true;</script>"
        let chapter = HTMLText.chapter(html, title: "正文")
        web.loadHTMLString(OriginalDocument.html(html, css: ""), baseURL: nil)
        await fulfillment(of: [loaded], timeout: 20)
        let sentences = Sentence.split(chapter.text)
        XCTAssertEqual(sentences.count, 3)
        let first = try await web.evaluateJavaScript(OriginalSpeechHighlight.script(text: chapter.text, range: sentences[0].range, follow: true, color: "#dce8e1"), in: nil, contentWorld: .defaultClient)
        XCTAssertEqual(first as? Int, 3)
        let highlighted = try await web.evaluateJavaScript("Array.from(document.querySelectorAll('mark[data-ty-speech]')).map(m=>m.textContent).join('')", in: nil, contentWorld: .defaultClient)
        XCTAssertEqual(highlighted as? String, "春风📖。")
        _ = try await web.evaluateJavaScript(OriginalSpeechHighlight.script(text: chapter.text, range: sentences[2].range, follow: false, color: "#35504a"), in: nil, contentWorld: .defaultClient)
        let repeated = try await web.evaluateJavaScript("document.querySelectorAll('p')[1].querySelector('mark').textContent", in: nil, contentWorld: .defaultClient)
        XCTAssertEqual(repeated as? String, "归来。")
        _ = try await web.evaluateJavaScript(OriginalSpeechHighlight.script(text: chapter.text, range: nil, follow: false, color: "#35504a"), in: nil, contentWorld: .defaultClient)
        let remaining = try await web.evaluateJavaScript("document.querySelectorAll('mark').length", in: nil, contentWorld: .defaultClient)
        XCTAssertEqual(remaining as? Int, 0)
        let bold = try await web.evaluateJavaScript("document.querySelector('b').textContent", in: nil, contentWorld: .defaultClient)
        XCTAssertEqual(bold as? String, "风")
        let publicationScriptRan = try await web.evaluateJavaScript("window.unsafe === true", in: nil, contentWorld: .page)
        XCTAssertEqual(publicationScriptRan as? Bool, false)
        withExtendedLifetime(delegate) {}
    }

    /// 原书图文为横向分页：长文产生多页；跟读定位到后面页的句子时自动翻到该页。
    @MainActor func testOriginalWebViewPagingAndAutoPageTurn() async throws {
        let loaded = expectation(description: "WebKit loaded")
        let delegate = LoadDelegate { loaded.fulfill() }
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        config.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 600), configuration: config)
        web.navigationDelegate = delegate
        let text = (1...300).map { "这是第\($0)句用来铺满多页的话。" }.joined()
        web.loadHTMLString(OriginalDocument.html("<p>\(text)</p>", css: ""), baseURL: nil)
        await fulfillment(of: [loaded], timeout: 20)
        // 等排版与字体应用完成后再量宽度。
        try await Task.sleep(for: .milliseconds(300))
        let pageWidth = try await web.evaluateJavaScript("innerWidth", in: nil, contentWorld: .page) as? Int
        let pages = try await web.evaluateJavaScript("Math.ceil(document.documentElement.scrollWidth / innerWidth)", in: nil, contentWorld: .page) as? Int
        XCTAssertEqual(pageWidth, 390)
        XCTAssertGreaterThan(pages ?? 0, 1, "长文应排成多个横页")
        let sentences = Sentence.split(text)
        let marked = try await web.evaluateJavaScript(OriginalSpeechHighlight.script(text: text, range: sentences.last?.range, follow: true, color: "#dce8e1"), in: nil, contentWorld: .defaultClient)
        XCTAssertGreaterThan(marked as? Int ?? 0, 0, "末句应被高亮")
        let offsetX = try await web.evaluateJavaScript("Math.round(scrollX / innerWidth)", in: nil, contentWorld: .page) as? Int
        XCTAssertGreaterThan(offsetX ?? 0, 0, "跟读末句应自动翻到后面页")
        withExtendedLifetime(delegate) {}
    }

    /// 与纯文本模式一致按字跟随：同一长句跨多页时，读到哪个字就翻到那个字所在页；不跟随时只报告页码不翻页。
    @MainActor func testOriginalWebViewFollowsSpokenCharacterWithinLongSentence() async throws {
        let loaded = expectation(description: "WebKit loaded")
        let delegate = LoadDelegate { loaded.fulfill() }
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        config.websiteDataStore = .nonPersistent()
        // 句子最长 180 字（Sentence.split 会切开更长的）：用矮视图让一个 170 字的单句横跨好几页。
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 200), configuration: config)
        web.navigationDelegate = delegate
        let text = String(repeating: "长", count: 170) + "。"
        web.loadHTMLString(OriginalDocument.html("<p>\(text)</p>", css: ""), baseURL: nil)
        await fulfillment(of: [loaded], timeout: 20)
        try await Task.sleep(for: .milliseconds(300))
        let sentences = Sentence.split(text)
        XCTAssertEqual(sentences.count, 1, "整段应是一个长句")
        let sentence = try XCTUnwrap(sentences.first?.range)
        _ = try await web.evaluateJavaScript(OriginalSpeechHighlight.script(text: text, range: sentence, follow: true, color: "#dce8e1", spoken: 0), in: nil, contentWorld: .defaultClient)
        let start = try await web.evaluateJavaScript("Math.round(scrollX / innerWidth)", in: nil, contentWorld: .page) as? Int
        XCTAssertEqual(start, 0, "刚开始读，停在第一页")
        let late = OriginalSpeechHighlight.spokenIndex(text: text, sentence: sentence, offset: NSMaxRange(sentence) - 3)
        let quiet = try await web.evaluateJavaScript(OriginalSpeechHighlight.followScript(spoken: late, follow: false), in: nil, contentWorld: .defaultClient) as? Int ?? -1
        XCTAssertGreaterThan(quiet, 0, "读到句尾的字在后面的页")
        let unmoved = try await web.evaluateJavaScript("Math.round(scrollX / innerWidth)", in: nil, contentWorld: .page) as? Int
        XCTAssertEqual(unmoved, 0, "不跟随时不翻页")
        let page = try await web.evaluateJavaScript(OriginalSpeechHighlight.followScript(spoken: late, follow: true), in: nil, contentWorld: .defaultClient) as? Int ?? -1
        let moved = try await web.evaluateJavaScript("Math.round(scrollX / innerWidth)", in: nil, contentWorld: .page) as? Int
        XCTAssertEqual(moved, page, "跟随时翻到读到的字所在页")
        XCTAssertEqual(page, quiet)
        withExtendedLifetime(delegate) {}
    }

    /// 夜间纸色下，书籍样式写死的深色正文要改成阅读页正文色；浅色底的提示框里保留深色字。
    @MainActor func testOriginalWebViewFixesLowContrastBookColorsAtNight() async throws {
        let loaded = expectation(description: "WebKit loaded")
        let delegate = LoadDelegate { loaded.fulfill() }
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        config.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 600), configuration: config)
        web.navigationDelegate = delegate
        let html = #"<p class="normal">正文写死成深灰。</p><div class="note"><p>提示框里的字。</p></div>"#
        let css = ".normal{color:#333} .note{background:#fff8dc} .note p{color:#999}"
        web.loadHTMLString(OriginalDocument.html(html, css: css, color: "#e8e6e3", background: "transparent", paper: "#1c1b19"), baseURL: nil)
        await fulfillment(of: [loaded], timeout: 20)
        _ = try await web.evaluateJavaScript(OriginalSpeechHighlight.script(text: "正文写死成深灰。\n提示框里的字。", range: nil, follow: false, color: "#4a3226"), in: nil, contentWorld: .defaultClient)
        let body = try await web.evaluateJavaScript("getComputedStyle(document.querySelector('.normal')).color", in: nil, contentWorld: .page) as? String
        let note = try await web.evaluateJavaScript("getComputedStyle(document.querySelector('.note p')).color", in: nil, contentWorld: .page) as? String
        XCTAssertEqual(body, "rgb(232, 230, 227)", "深色底上的正文改用阅读页正文色")
        XCTAssertEqual(note, "rgb(20, 17, 15)", "浅色提示框里改用深色字（v2 现代书店墨色 #14110F）")
        withExtendedLifetime(delegate) {}
    }

    /// 每栏起点必须恰好落在整页边界上：书籍 CSS 改 body 边距时，翻到后面的页也不能错位。
    @MainActor func testOriginalWebViewColumnsAlignToPagesDespiteBookCSS() async throws {
        let loaded = expectation(description: "WebKit loaded")
        let delegate = LoadDelegate { loaded.fulfill() }
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        config.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 600), configuration: config)
        web.navigationDelegate = delegate
        let text = (1...400).map { "这是第\($0)句用来铺满多页的话。" }.joined()
        let css = "body.calibre{margin:0 5%;padding:0 12px;max-width:30em} body{margin:3em}"
        web.loadHTMLString(OriginalDocument.html("<body class=\"calibre\"><p>\(text)</p></body>", css: css), baseURL: nil)
        await fulfillment(of: [loaded], timeout: 20)
        try await Task.sleep(for: .milliseconds(300))
        _ = try await web.evaluateJavaScript(OriginalSpeechHighlight.script(text: text, range: nil, follow: false, color: "#dce8e1"), in: nil, contentWorld: .defaultClient)
        let lefts = try await web.evaluateJavaScript("Array.from(document.querySelector('p').getClientRects()).map(r => Math.round(r.left + scrollX))", in: nil, contentWorld: .page) as? [Int] ?? []
        XCTAssertGreaterThan(lefts.count, 3, "长文应排成多个横页")
        XCTAssertEqual(lefts, lefts.indices.map { $0 * 390 }, "每页起点应为整页宽的倍数")
        let width = try await web.evaluateJavaScript("document.documentElement.scrollWidth", in: nil, contentWorld: .page) as? Int ?? 0
        XCTAssertEqual(width % 390, 0, "总宽应为整页宽的倍数")
        withExtendedLifetime(delegate) {}
    }
}

@MainActor private final class LoadDelegate: NSObject, WKNavigationDelegate {
    let complete: () -> Void
    init(complete: @escaping () -> Void) { self.complete = complete }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { complete() }
}

final class ExtendedReadingTests: XCTestCase {
    @MainActor func testLongScrollingDocumentRestoresPositionAfterLayoutAndResize() {
        let chapter = Chapter(title: "Long", text: (1...400).map { "第\($0)句测试。" + String(repeating: "长段落与自动换行，", count: 12) + "结束。\n" }.joined())
        let source = NativeTypesetter.attributed(chapter, preferences: .init())
        let offset = (chapter.text as NSString).range(of: "第199句测试").location
        let view = ReaderScrollTextView(usingTextLayoutManager: false)
        view.textContainer.lineFragmentPadding = 0
        view.attributedText = source
        view.requestPosition(offset)
        // Request comes before SwiftUI supplies a nonzero frame.
        view.layoutIfNeeded()
        for width in [340.0, 290.0, 650.0] {
            view.frame = CGRect(x: 0, y: 0, width: width, height: 500)
            view.setNeedsLayout(); view.layoutIfNeeded()
            let glyph = view.layoutManager.glyphRange(forCharacterRange: NSRange(location: offset, length: 1), actualCharacterRange: nil)
            let rect = view.layoutManager.boundingRect(forGlyphRange: glyph, in: view.textContainer).offsetBy(dx: view.textContainerInset.left, dy: view.textContainerInset.top)
            XCTAssertTrue(view.bounds.intersects(rect), "Saved sentence must be visible after layout at width \(width)")
            XCTAssertGreaterThan(view.contentOffset.y, 1000)
        }
        let later = (chapter.text as NSString).range(of: "第300句测试").location
        view.requestPosition(later); view.layoutIfNeeded()
        let glyph = view.layoutManager.glyphRange(forCharacterRange: NSRange(location: later, length: 1), actualCharacterRange: nil)
        let rect = view.layoutManager.boundingRect(forGlyphRange: glyph, in: view.textContainer).offsetBy(dx: 0, dy: view.textContainerInset.top)
        XCTAssertTrue(view.bounds.intersects(rect))
    }
    @MainActor func testPDFImportRetainsPagesAndReadableText() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 400, height: 600))
        let data = renderer.pdfData { context in
            for index in 1...2 {
                context.beginPage()
                ("Page \(index). Read this text." as NSString).draw(at: CGPoint(x: 30, y: 30), withAttributes: [.font: UIFont.systemFont(ofSize: 20)])
            }
        }
        try data.write(to: url)
        let imported = try BookImporter.read(url).book
        XCTAssertEqual(imported.chapters.count, 2)
        XCTAssertTrue(imported.chapters[1].text.contains("Page 2"))
        XCTAssertEqual(imported.pdf, data)
    }
    func testMarkdownAndBackupFileImportAndInvalidJSON() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let markdown = base.appendingPathComponent("sample.md")
        try Data("# 第一章\n**正文**与[链接](https://example.com)。".utf8).write(to: markdown)
        let book = try BookImporter.read(markdown).book
        XCTAssertTrue(book.chapters[0].text.contains("正文与链接。"))
        // Markdown 的原书图文与正文同源：两种模式的高亮与进度一致。
        let document = book.chapters[0].fields["document"]?.object
        XCTAssertTrue(document?["html"]?.string?.contains("正文与链接。") == true)
        XCTAssertEqual(OriginalDocument.fromText("一 & <二>\n\n三"), "<p>一 &amp; &lt;二&gt;</p><p>三</p>")
        let backup = base.appendingPathComponent("backup.json")
        let progress = ReadingProgress(chapter: 0, position: 0, updatedAt: 999)
        try Integrity.encoder().encode(BackupPacket(book: book, progress: progress)).write(to: backup)
        let imported = try BookImporter.read(backup)
        XCTAssertEqual(imported.book, book); XCTAssertEqual(imported.progress, progress)
        try Data("{broken".utf8).write(to: backup)
        XCTAssertThrowsError(try BookImporter.read(backup))
    }
}

private final class ProgressCalls: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [[Int]] = []
    func add(_ done: Int, _ total: Int) { lock.lock(); stored.append([done, total]); lock.unlock() }
    var values: [[Int]] { lock.lock(); defer { lock.unlock() }; return stored }
}

private final class MemoryKeyValueStore: ProgressKeyValueStore {
    var values: [String: Any] = [:]
    var available = true
    func dictionary(forKey key: String) -> [String: Any]? { values[key] as? [String: Any] }
    func set(_ value: Any?, forKey key: String) { values[key] = value }
    func removeObject(forKey key: String) { values[key] = nil }
    var dictionaryRepresentation: [String: Any] { values }
    func synchronize() -> Bool { available }
}


// MARK: - 1.14 书库、书源、阅读与听书增强

import ZIPFoundation

extension NativeCoreTests {
    func testPalmDOCDecompressionHandlesLiteralsSpacesAndBackReferences() {
        // "abc" + 回溯 3 字节取 3 字节 + 「空格 + A」
        XCTAssertEqual(MobiReader.palmDOC([0x61, 0x62, 0x63, 0x80, 0x18, 0xC1]), Array("abcabc A".utf8))
        // 1…8 为原样字节段（多字节 UTF-8 走这里）
        let han = Array("书".utf8)
        XCTAssertEqual(MobiReader.palmDOC([UInt8(han.count)] + han), han)
    }

    func testMobiTrailingEntriesAreStripped() {
        // 多字节重叠 1 字节（低两位 0 → 1 字节）+ 一条 3 字节 TBS 记录（末字节 0x83）
        let record: [UInt8] = [0x41, 0x42, 0x00, 0xAA, 0xBB, 0x83]
        XCTAssertEqual(MobiReader.trailingSize(record, flags: 0b11), 4)
        XCTAssertEqual(MobiReader.trailingSize(record, flags: 0), 0)
    }

    func testMobiImportReadsTitleAuthorAndSplitsOnPageBreaks() throws {
        func be16(_ v: Int) -> [UInt8] { [UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)] }
        func be32(_ v: Int) -> [UInt8] { [UInt8(v >> 24 & 0xFF), UInt8(v >> 16 & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)] }
        let html = Array("<p>第一章正文。</p><mbp:pagebreak/><h1>第二回</h1><p>hello hello</p>".utf8)
        // PalmDOC 压缩：全部用 8 字节原样段编码
        var compressed: [UInt8] = []
        var i = 0
        while i < html.count { let n = min(8, html.count - i); compressed.append(UInt8(n)); compressed += html[i..<i + n]; i += n }
        let textRecord = compressed + [0x00, 0xAA, 0xBB, 0x83]
        let title = Array("测试书名".utf8), author = Array("鲁迅".utf8)
        let headerLength = 0xE8
        var r0 = [UInt8](repeating: 0, count: 16 + headerLength)
        r0.replaceSubrange(0..<2, with: be16(2))                 // PalmDOC 压缩
        r0.replaceSubrange(4..<8, with: be32(html.count))
        r0.replaceSubrange(8..<10, with: be16(1))                // 1 条正文记录
        r0.replaceSubrange(10..<12, with: be16(4096))
        r0.replaceSubrange(16..<20, with: Array("MOBI".utf8))
        r0.replaceSubrange(20..<24, with: be32(headerLength))
        r0.replaceSubrange(28..<32, with: be32(65001))           // UTF-8
        r0.replaceSubrange(0x6C..<0x70, with: be32(0xFFFF_FFFF))  // 没有图片
        r0.replaceSubrange(0x80..<0x84, with: be32(0x40))         // 有 EXTH
        r0.replaceSubrange(0xF2..<0xF4, with: be16(0b11))         // 尾部附加数据
        let exth = Array("EXTH".utf8) + be32(12 + 8 + author.count) + be32(1) + be32(100) + be32(8 + author.count) + author
        let nameOffset = r0.count + exth.count
        r0.replaceSubrange(0x54..<0x58, with: be32(nameOffset))
        r0.replaceSubrange(0x58..<0x5C, with: be32(title.count))
        r0 += exth + title + [0, 0]
        var file = [UInt8](repeating: 0, count: 78)
        file.replaceSubrange(60..<68, with: Array("BOOKMOBI".utf8))
        file.replaceSubrange(76..<78, with: be16(2))
        let first = 78 + 16 + 2
        file += be32(first) + be32(0) + be32(first + r0.count) + be32(1) + [0, 0]
        file += r0 + textRecord
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tingye-test.mobi")
        try Data(file).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let book = try BookImporter.read(url).book
        XCTAssertEqual(book.title, "测试书名")
        XCTAssertEqual(book.author, "鲁迅")
        XCTAssertEqual(book.format, "MOBI")
        XCTAssertEqual(book.chapters.count, 2)
        XCTAssertEqual(book.chapters[0].text.trimmingCharacters(in: .whitespacesAndNewlines), "第一章正文。")
        XCTAssertEqual(book.chapters[1].title, "第二回")
        XCTAssertTrue(book.chapters[1].text.contains("hello hello"))
    }

    func testMobiWithDRMIsRejected() throws {
        var file = [UInt8](repeating: 0, count: 78)
        file.replaceSubrange(60..<68, with: Array("BOOKMOBI".utf8))
        file[77] = 2
        file += [0, 0, 0, 96, 0, 0, 0, 0, 0, 0, 0, 112, 0, 0, 0, 1, 0, 0]
        var r0 = [UInt8](repeating: 0, count: 16); r0[1] = 2; r0[9] = 1; r0[13] = 2   // encryption = 2
        file += r0 + [0x41]
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tingye-drm.azw")
        try Data(file).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertThrowsError(try BookImporter.read(url)) { XCTAssertTrue($0.localizedDescription.contains("DRM")) }
    }

    func testComicZipImportsImagesInNaturalOrderAsPages() throws {
        let png = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 6)).pngData { context in UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 4, height: 6)) }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tingye-comic.cbz")
        try? FileManager.default.removeItem(at: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let archive = try Archive(url: url, accessMode: .create)
        for name in ["10.png", "2.png", "1.png", "__MACOSX/._1.png", "readme.txt"] {
            let data = name.hasSuffix(".txt") ? Data("hi".utf8) : png
            try archive.addEntry(with: name, type: .file, uncompressedSize: Int64(data.count)) { position, size in data.subdata(in: Int(position)..<Int(position) + size) }
        }
        let book = try BookImporter.read(url).book
        XCTAssertEqual(book.format, "CBZ")
        XCTAssertEqual(book.fields["comic"]?.bool, true)
        XCTAssertEqual(book.chapters.map(\.title), ["第 1 页", "第 2 页", "第 3 页"])
        XCTAssertNotNil(book.coverData)
        let entry = ShelfEntry(book: book)
        XCTAssertTrue(entry.isComic)
        XCTAssertEqual(entry.chapterCount, 3)
    }

    func testChineseConversionKeepsLengthSoSentenceCoordinatesStay() {
        let simplified = "简体中文，这里是书库与阅读进度。"
        let traditional = ChineseConvert.apply(simplified, "s2t")
        XCTAssertNotEqual(traditional, simplified)
        XCTAssertEqual(traditional.utf16.count, simplified.utf16.count)
        XCTAssertTrue(traditional.contains("簡體"))
        XCTAssertEqual(ChineseConvert.apply(traditional, "t2s"), simplified)
        XCTAssertEqual(ChineseConvert.apply(simplified, "none"), simplified)
    }

    func testDialogueRolesUseAttributionAroundQuotes() {
        let sentences = Sentence.split("天色已晚。\n他笑道：“你来了。”\n“快走！”\n她喊了一声。\n“谁在那里？”")
        XCTAssertEqual(sentences.map(\.text), ["天色已晚。", "他笑道：“你来了。”", "“快走！”", "她喊了一声。", "“谁在那里？”"])
        XCTAssertEqual(DialogueRoles.role(0, in: sentences), .narrator)
        XCTAssertEqual(DialogueRoles.role(1, in: sentences), .male)
        XCTAssertEqual(DialogueRoles.role(2, in: sentences), .female, "纯引语看后一句的说话提示")
        XCTAssertEqual(DialogueRoles.role(4, in: sentences), .narrator, "判断不出来时用旁白")
        XCTAssertEqual(DialogueRoles.attribution("他对她说"), .male, "最先出现的称谓是说话人")
        var options = VoiceOptions(provider: "system", model: "", voice: "narrator", rate: 1, key: "", groupID: "")
        XCTAssertEqual(options.forRole(.female).voice, "narrator", "未开启分角色时始终用旁白")
        options.roles = true; options.femaleVoice = "female"
        XCTAssertEqual(options.forRole(.female).voice, "female")
        XCTAssertEqual(options.forRole(.male).voice, "narrator", "没选男声时沿用旁白")
    }

    func testOPDSFeedParsesNavigationAcquisitionPagingAndSearch() {
        let xml = """
        <feed xmlns="http://www.w3.org/2005/Atom">
          <link rel="next" href="/opds/new?page=2" type="application/atom+xml;profile=opds-catalog"/>
          <link rel="search" href="/opds/search?q={searchTerms}" type="application/atom+xml"/>
          <entry><title>最新书籍</title><link rel="subsection" href="/opds/new" type="application/atom+xml;profile=opds-catalog;kind=acquisition"/></entry>
          <entry><title>故乡</title><author><name>鲁迅</name></author><summary>&lt;p&gt;小说&lt;/p&gt;</summary>
            <link rel="http://opds-spec.org/acquisition" href="/get/pdf/1" type="application/pdf"/>
            <link rel="http://opds-spec.org/acquisition" href="/get/epub/1" type="application/epub+zip"/>
            <link rel="http://opds-spec.org/image/thumbnail" href="/cover/1"/></entry>
        </feed>
        """
        let feed = OPDSFeed.parse(Data(xml.utf8), base: URL(string: "http://nas.local:8083/opds")!)
        XCTAssertEqual(feed.next?.absoluteString, "http://nas.local:8083/opds/new?page=2")
        XCTAssertEqual(feed.searchTemplate, "/opds/search?q={searchTerms}")
        XCTAssertEqual(feed.entries.count, 2)
        XCTAssertNil(feed.entries[0].acquisition)
        XCTAssertEqual(feed.entries[0].navigation?.absoluteString, "http://nas.local:8083/opds/new")
        XCTAssertEqual(feed.entries[1].author, "鲁迅")
        XCTAssertEqual(feed.entries[1].summary, "小说")
        XCTAssertEqual(feed.entries[1].acquisition?.fileExtension, "epub", "多个格式时优先 EPUB")
        XCTAssertEqual(feed.entries[1].thumbnail?.absoluteString, "http://nas.local:8083/cover/1")
        XCTAssertTrue(ImportableFile.accepts("书.AZW3"))
        XCTAssertFalse(ImportableFile.accepts("封面.jpg"))
    }

    func testGroupPathsAreNormalizedAndOldCatalogsStillDecode() throws {
        XCTAssertEqual(AppModel.normalizedGroup(" 科幻 / 阿西莫夫 /"), "科幻/阿西莫夫")
        XCTAssertEqual(AppModel.normalizedGroup("//"), "")
        // 1.13 及更早的书库目录没有分组、隐藏、划线、添加时间字段
        let book = Book(title: "春", format: "TXT", chapters: [Chapter(title: "一", text: "盼望着。东风来了。")])
        var entry = ShelfEntry(book: book)
        entry.group = "散文"; entry.hidden = true
        entry.highlights = [Highlight(chapter: 0, start: 0, end: 1, text: "盼望着。东风来了。", color: "green", style: "wavy", note: "好")]
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(entry)) as! [String: Any]
        let restored = try JSONDecoder().decode(ShelfEntry.self, from: JSONEncoder().encode(entry))
        XCTAssertEqual(restored.notes.first?.style, "wavy")
        XCTAssertTrue(restored.isHidden)
        for key in ["group", "hidden", "highlights", "addedAt"] { object[key] = nil }
        let old = try JSONDecoder().decode(ShelfEntry.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(old.group); XCTAssertFalse(old.isHidden); XCTAssertTrue(old.notes.isEmpty)
        // 跨端备份协议不含整理字段
        let packet = try JSONSerialization.jsonObject(with: JSONEncoder().encode(BackupPacket(book: book, progress: .init()))) as! [String: Any]
        XCTAssertNil(packet["highlights"]); XCTAssertNil(packet["group"])
    }

    func testHighlightMarksMapSentencesToCharacterRangesOnEachPage() {
        let text = "第一句。第二句。第三句。"
        let sentences = Sentence.split(text)
        let range = ReaderMark.range(start: 1, end: 2, in: sentences)
        XCTAssertEqual(range.map { (text as NSString).substring(with: $0) }, "第二句。第三句。")
        XCTAssertNil(ReaderMark.range(start: 2, end: 5, in: sentences))
        // 只给落在本页的部分加标记，坐标换成页内坐标
        let page = NSAttributedString(string: (text as NSString).substring(with: NSRange(location: 4, length: 4)))
        let marked = ReaderMark.apply([ReaderMark(range: range!, color: "yellow", kind: "underline")], to: page, pageRange: NSRange(location: 4, length: 4))
        var effective = NSRange()
        XCTAssertNotNil(marked.attribute(.tyMark, at: 0, effectiveRange: &effective))
        XCTAssertEqual(effective, NSRange(location: 0, length: 4))
        XCTAssertTrue(Highlight(chapter: 0, start: 1, end: 2, text: "").contains(chapter: 0, sentence: 2))
    }
}
