import SwiftUI

/// 根入口唯一的格式判据。不以 document、资源、文件扩展名推测格式。
enum ReaderRouter {
    enum Destination: Equatable { case comic, native, epub }
    static func destination(for book: Book) -> Destination {
        if book.fields["comic"]?.bool == true { return .comic }
        if book.pdf != nil { return .native }
        if book.format.uppercased() == "EPUB" { return .epub }
        return .native
    }
}

struct RoutedReaderView: View {
    let book: Book
    @EnvironmentObject private var model: AppModel
    @ViewBuilder var body: some View {
        switch ReaderRouter.destination(for: book) {
        case .comic: ComicReaderView(book: book)
        case .native: ReaderView(book: book, player: model.player)
        case .epub: ReadiumReaderView(book: book)
        }
    }
}
