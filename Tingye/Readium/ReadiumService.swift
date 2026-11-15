import Foundation
import ReadiumShared
import ReadiumStreamer

/// Unit 1 exposes parsing for tests only. The app's reading router remains unchanged.
@MainActor
final class ReadiumService {
    enum OpenError: LocalizedError {
        case invalidFile, notEPUB, restricted, emptyReadingOrder
        case retrieve(String), parse(String)
        var errorDescription: String? {
            switch self {
            case .invalidFile: return "Publication 文件不存在或路径无效。"
            case .notEPUB: return "Publication 必须是 EPUB。"
            case .restricted: return "EPUB 受 DRM 限制，无法读取。"
            case .emptyReadingOrder: return "EPUB 没有可阅读的章节。"
            case .retrieve(let reason): return "EPUB 文件读取失败：\(reason)"
            case .parse(let reason): return "EPUB 解析失败：\(reason)"
            }
        }
    }
    private let retriever = AssetRetriever(httpClient: DefaultHTTPClient())
    private let opener = PublicationOpener(parser: EPUBParser())

    func open(_ url: URL) async throws -> Publication {
        try Task.checkCancellation()
        guard url.isFileURL, FileManager.default.isReadableFile(atPath: url.path), let file = FileURL(url: url) else {
            throw OpenError.invalidFile
        }
        let asset: Asset
        switch await retriever.retrieve(url: file) {
        case .success(let value): asset = value
        case .failure(let error): throw OpenError.retrieve(String(describing: error))
        }
        guard asset.format.conformsTo(.epub) else { throw OpenError.notEPUB }
        try Task.checkCancellation()
        let publication: Publication
        switch await opener.open(asset: asset, allowUserInteraction: false) {
        case .success(let value): publication = value
        case .failure(let error): throw OpenError.parse(String(describing: error))
        }
        try Task.checkCancellation()
        guard publication.conforms(to: .epub) else { throw OpenError.notEPUB }
        guard !publication.isRestricted else { throw OpenError.restricted }
        guard !publication.readingOrder.isEmpty else { throw OpenError.emptyReadingOrder }
        return publication
    }
}
