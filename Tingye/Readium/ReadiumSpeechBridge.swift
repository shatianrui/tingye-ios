import Foundation
import ReadiumShared
import ReadiumNavigator

/// Shared sentence contract for EPUB reader → audio and player → reader.
/// Audio continues to consume Book.text; only the visual location is translated.
@MainActor
enum ReadiumSpeechBridge {
    static func sentence(book: Book, chapter: Int, position: Int) -> LocatorTarget {
        LocatorTarget(chapter: chapter, position: position,
                      anchor: Locator.anchor(in: book.chapters.indices.contains(chapter) ? Sentence.split(book.chapters[chapter].text) : [], at: position))
    }
    static func start(visible original: JSONValue?, chapter: Int, position: Int, bridge: LocatorBridge) async throws -> ReadingProgress {
        let target: LocatorTarget
        if let locator = StoredLocator.readium(original) {
            let result = try await bridge.reverse(locator, chapterHint: chapter)
            guard result.precise else { throw ReaderError.message("当前可见文字尚未精确定位，请选择正文后再听。") }
            target = result.target
        } else { target = sentence(book: bridge.book, chapter: chapter, position: position) }
        return ReadingProgress(chapter: target.chapter, position: target.position, anchor: target.anchor)
    }
    static func playback(chapter: Int, position: Int, bridge: LocatorBridge, mode: String) async throws -> (LocatorResult, ReadiumShared.Locator, Decoration?) {
        let result = try await bridge.resolve(sentence(book: bridge.book, chapter: chapter, position: position))
        guard let location = try await bridge.displayLocator(result.locator, mode: mode) else {
            throw ReaderError.message("朗读位置无法映射到 EPUB。")
        }
        let exact = result.precise ? try await bridge.displayLocator(result.locator, mode: mode, requireRange: true) : nil
        let decoration = exact.map { Decoration(id: "speech-current", locator: $0, style: ReadiumAnnotations.style(color: "clay", kind: "background")) }
        return (result, location, decoration)
    }
    /// Locator for the character currently being followed, so the visible page can move
    /// before the sentence ends.
    static func pageLocator(chapter: Int, offset: Int, bridge: LocatorBridge, mode: String) async throws -> (original: JSONValue?, display: ReadiumShared.Locator)? {
        guard bridge.book.chapters.indices.contains(chapter) else { return nil }
        let text = bridge.book.chapters[chapter].text as NSString
        guard offset >= 0, offset < text.length else { return nil }
        let rest = text.substring(from: offset)
        let length = rest.first.map { (String($0) as NSString).length } ?? 1
        let sentences = Sentence.split(bridge.book.chapters[chapter].text)
        let target = LocatorTarget(chapter: chapter, position: Sentence.index(at: offset, in: sentences),
                                   textRange: NSRange(location: offset, length: max(1, length)))
        let result = try await bridge.resolve(target)
        if let exact = try await bridge.displayLocator(result.locator, mode: mode, requireRange: true) {
            return (result.locator, exact)
        }
        guard let display = try await bridge.displayLocator(result.locator, mode: mode) else { return nil }
        return (result.locator, display)
    }
}
