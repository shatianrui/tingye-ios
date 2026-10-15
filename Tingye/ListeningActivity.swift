import Foundation
#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
import ActivityKit
import AppIntents

/// 听书实时活动（锁屏与灵动岛）。App 与小组件扩展共用此文件。
/// 静态部分随书不变；动态部分随朗读推进更新，整体需小于 4 KB，所以只带文字与数字，不带图片。
struct ListeningAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var chapterTitle: String
        /// 正在读的句子（截短）
        var sentence: String
        var chapter: Int
        var chapterCount: Int
        /// 本章进度 0...1
        var progress: Double
        var playing: Bool
    }
    var bookID: String
    var title: String
    var author: String
    /// 书封底色（如 "#3E434C"）：实时活动不便携带图片，用书封色块 + 书名首字代替封面。
    var coverHex: String
}

/// 实时活动上的按钮在 App 进程内执行，由 App 启动时注册的处理器转给播放器。
enum PlaybackRemote {
    enum Action: String { case toggle, next, previous }
    @MainActor static var handler: ((Action) -> Void)?
}

struct ToggleListeningIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "播放或暂停听书"
    static var isDiscoverable = false
    @MainActor func perform() async throws -> some IntentResult { PlaybackRemote.handler?(.toggle); return .result() }
}

struct NextSentenceIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "下一句"
    static var isDiscoverable = false
    @MainActor func perform() async throws -> some IntentResult { PlaybackRemote.handler?(.next); return .result() }
}

struct PreviousSentenceIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "上一句"
    static var isDiscoverable = false
    @MainActor func perform() async throws -> some IntentResult { PlaybackRemote.handler?(.previous); return .result() }
}
#endif
