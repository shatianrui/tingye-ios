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
}
