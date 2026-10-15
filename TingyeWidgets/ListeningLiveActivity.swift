import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// 听书实时活动：锁屏卡片与灵动岛。配色沿用 App：深石底、浅色字、湖青听书进度。
struct ListeningLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ListeningAttributes.self) { context in
            LockScreenListening(context: context)
                .activityBackgroundTint(Palette.paper)
                .activitySystemActionForegroundColor(Palette.ink)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    MiniCover(title: context.attributes.title, hex: context.attributes.coverHex, size: 46)
                        .padding(.leading, 2)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    PlayButton(playing: context.state.playing, size: 44, fill: Palette.clayOnDark, glyph: .black)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.title)
                            .font(.system(size: 15, weight: .semibold, design: .serif))
                            .lineLimit(1)
                        Text(chapterLine(context))
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 10) {
                        Text(context.state.sentence)
                            .font(.system(size: 14, design: .serif))
                            .foregroundStyle(.white.opacity(0.9))
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        HStack(spacing: 14) {
                            SkipButton(intent: PreviousSentenceIntent(), systemName: "backward.end.fill", label: "上一句", tint: .white)
                            ProgressLine(value: context.state.progress, track: .white.opacity(0.18), fill: Palette.clayOnDark)
                            SkipButton(intent: NextSentenceIntent(), systemName: "forward.end.fill", label: "下一句", tint: .white)
                        }
                    }
                    .padding(.top, 4)
                }
            } compactLeading: {
                Image(systemName: context.state.playing ? "waveform" : "pause.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.clayOnDark)
                    .symbolEffect(.variableColor.iterative, isActive: context.state.playing)
                    .accessibilityLabel(context.state.playing ? "正在听书" : "已暂停")
            } compactTrailing: {
                ProgressRing(value: context.state.progress, size: 16)
            } minimal: {
                ProgressRing(value: context.state.progress, size: 16)
            }
            .keylineTint(Palette.clayOnDark)
        }
    }
    private func chapterLine(_ context: ActivityViewContext<ListeningAttributes>) -> String {
        "第 \(context.state.chapter + 1) / \(max(1, context.state.chapterCount)) 章 · \(context.state.chapterTitle)"
    }
}

/// 锁屏卡片：立体书封、书名与听书状态、正在朗读的句子、进度与控制。
private struct LockScreenListening: View {
    let context: ActivityViewContext<ListeningAttributes>
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                MiniCover(title: context.attributes.title, hex: context.attributes.coverHex, size: 54)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(context.attributes.title)
                            .font(.system(size: 16, weight: .bold, design: .serif))
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(context.state.playing ? "正在听" : "已暂停")
                            .font(.system(size: 10, weight: .bold, design: .serif))
                            .foregroundStyle(Palette.clay)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Palette.clay.opacity(0.12), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .strokeBorder(Palette.clay.opacity(0.32), lineWidth: 0.7)
                            }
                    }
                    Text("第 \(context.state.chapter + 1) / \(max(1, context.state.chapterCount)) 章 · \(context.state.chapterTitle)")
                        .font(.system(size: 12, design: .serif))
                        .foregroundStyle(Palette.ink2)
                        .lineLimit(1)
                    HStack(alignment: .top, spacing: 8) {
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Palette.clay, Palette.gold],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: 2.5)
                        Text(context.state.sentence)
                            .font(.system(size: 13, design: .serif))
                            .foregroundStyle(Palette.ink)
                            .lineLimit(2)
                    }
                    .padding(.top, 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 14) {
                ProgressLine(value: context.state.progress, track: Palette.line, fill: Palette.clay)
                SkipButton(intent: PreviousSentenceIntent(), systemName: "backward.end.fill", label: "上一句", tint: Palette.ink)
                PlayButton(playing: context.state.playing, size: 38, fill: Palette.clay, glyph: Palette.paper)
                SkipButton(intent: NextSentenceIntent(), systemName: "forward.end.fill", label: "下一句", tint: Palette.ink)
            }
        }
        .padding(16)
    }
}

/// 沿用纸面封面的简洁字形，保持锁屏对比度。
private struct MiniCover: View {
    let title: String
    let hex: String
    let size: CGFloat
    var body: some View {
        Text(String(title.prefix(1)))
            .font(.system(size: size * 0.44, weight: .medium, design: .serif))
            .foregroundStyle(Palette.ink)
            .frame(width: size, height: size)
            .background(Palette.line, in: RoundedRectangle(cornerRadius: 8))
            .accessibilityHidden(true)
    }
}

private struct PlayButton: View {
    let playing: Bool
    let size: CGFloat
    let fill: Color
    let glyph: Color
    var body: some View {
        Button(intent: ToggleListeningIntent()) {
            WidgetIcon(symbol: playing ? "pause.fill" : "play.fill", size: size * 0.5)
                .foregroundStyle(glyph)
                .frame(width: size, height: size)
                .background(fill, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(playing ? "暂停" : "继续听")
    }
}

private struct SkipButton<I: AppIntent>: View {
    let intent: I
    let systemName: String
    let label: String
    let tint: Color
    var body: some View {
        Button(intent: intent) {
            WidgetIcon(symbol: systemName, size: 20)
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

private struct ProgressLine: View {
    let value: Double
    let track: Color
    let fill: Color
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule().fill(fill).frame(width: max(4, min(1, max(0, value)) * geo.size.width))
            }
        }
        .frame(height: 4)
        .accessibilityElement()
        .accessibilityLabel("本章进度")
        .accessibilityValue("\(Int((value * 100).rounded()))%")
    }
}

private struct ProgressRing: View {
    let value: Double
    let size: CGFloat
    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.2), lineWidth: 2.5)
            Circle().trim(from: 0, to: min(1, max(0.02, value)))
                .stroke(Palette.clayOnDark, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
        .accessibilityLabel("本章进度 \(Int((value * 100).rounded()))%")
    }
}

/// 与 App 主题一致的颜色（刊版的墨、纸、信号红与荧光黄）；锁屏卡片使用墨色底。
private enum Palette {
    static let paper = dynamic(0x111111, 0x111111)
    static let ink = dynamic(0xF3F0E8, 0xF3F0E8)
    static let ink2 = dynamic(0xB9B4AA, 0xB9B4AA)
    static let line = dynamic(0x33312D, 0x33312D)
    /// 信号红：播放按钮
    static let clay = dynamic(0xFF5A3C, 0xFF5A3C)
    /// 荧光黄：听书进度
    static let gold = dynamic(0xFFE24A, 0xFFE24A)
    /// 深色背景（灵动岛）上的强调
    static let clayOnDark = Color(red: 0xFF / 255, green: 0x5A / 255, blue: 0x3C / 255)
    private static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(rgb: dark) : UIColor(rgb: light) })
    }
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(red: CGFloat((rgb >> 16) & 255) / 255, green: CGFloat((rgb >> 8) & 255) / 255, blue: CGFloat(rgb & 255) / 255, alpha: 1)
    }
}

private extension Color {
    init?(hexString: String) {
        let raw = hexString.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard raw.count == 6, let value = UInt32(raw, radix: 16) else { return nil }
        self.init(UIColor(rgb: value))
    }
}

private struct WidgetIcon: View {
    /// The extension is embedded in the application that owns the shared catalog.
    private static let applicationBundle: Bundle = {
        var url = Bundle.main.bundleURL
        for _ in 0..<6 {
            if url.pathExtension == "app", let bundle = Bundle(url: url) { return bundle }
            url.deleteLastPathComponent()
        }
        return .main
    }()
    let symbol: String
    let size: CGFloat
    var body: some View {
        Image("TY-" + symbol.replacingOccurrences(of: ".", with: "-"), bundle: Self.applicationBundle)
            .renderingMode(.template).resizable().scaledToFit()
            .frame(width: size, height: size)
    }
}
