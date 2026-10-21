import SwiftUI
import UIKit
import CoreImage

/// 听页 · 墨 Ink（v16 用户选定方向 B）。宣纸为底、墨色为文、朱砂为印。
/// 朱砂是全局唯一彩色强调：当前句、印章点、主按钮、选中态，除此之外不用。
/// 当前规范：Design/v16/b-ink/DESIGN.md。旧 v15 灰紫令牌不再是实现依据。
enum Theme {
    static let bg = dynamic(0xFAF7EF, 0x101012)
    static let surface = dynamic(0xFFFFFF, 0x1A1A1E)
    static let surface2 = dynamic(0xF1ECDF, 0x232329)
    static let ink = dynamic(0x1C1B18, 0xEFEDE6)
    static let ink2 = dynamic(0x6B6759, 0xA5A296)
    static let ink3 = dynamic(0x6B6759, 0xA5A296)
    static let line = dynamic(0xE6E0D0, 0x2C2C33)
    static let onInk = dynamic(0xFAF7EF, 0x1C1B18)
    static let cardEdge = line
    /// 朱砂只用于当前句、印章点、主按钮与选中态，不做大面积铺底。
    static let accent = dynamic(0xA63A2E, 0xD97B6C)
    static let accentSoft = dynamic(0xF3E4DE, 0x33221F)
    static let onAccent = dynamic(0xFFFFFF, 0x2A120C)
    static let marker = dynamic(0xE7C7BC, 0xD98A7A)
    static let onMarker = Color(hex: 0x1C1B18)
    static let readingHighlight = dynamic(0xF3E4DE, 0x33221F)
    static let forest = ink
    static let onForest = onInk
    static let wash = accent.opacity(0.12)
    static let danger = dynamic(0xAE3E48, 0xF0A5AD)
    /// 金仅用于「精排 / 精装」标识描边，不承载文字；日夜同值。
    static let gold = dynamic(0x9B7B4A, 0x9B7B4A)
    static let goldSoft = dynamic(0xF3EDDE, 0x373124)
    static let jade = dynamic(0x4B7563, 0x9EC9B1)
    static let jadeSoft = dynamic(0xE6EFE9, 0x27382F)
    static let indigo = dynamic(0x5E6592, 0xADB6E4)
    static let indigoSoft = dynamic(0xECECF5, 0x2C2D43)
    static let ochre = gold
    static let plum = accent
    static let amberOnDark = Color(hex: 0xDFC48E)

    static let auroraGradient = LinearGradient(colors: [accent, accent], startPoint: .top, endPoint: .bottom)
    static let accentGradient = auroraGradient

    static let inset: CGFloat = 26
    static let pageWidth: CGFloat = 720
    static let radius: CGFloat = 12
    static let radiusSmall: CGFloat = 10
    static let buttonRadius: CGFloat = 12
    static let buttonHeight: CGFloat = 48
    static let iconButtonSize: CGFloat = 44
    /// 兼容旧调用；不再使用粗黑刊头线。
    static let ruleHeavy: CGFloat = 0.5
    static let rule: CGFloat = 0.5

    // MARK: - 动效

    static let pressSpring = Animation.spring(response: 0.28, dampingFraction: 0.72)
    static let smoothSpring = Animation.spring(response: 0.42, dampingFraction: 0.86)

    // MARK: - 字体：界面使用系统字体；宋体仅供正文偏好与引用内容使用

    static let serifName = "NotoSerifCJKsc-Regular"
    static func serif(_ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(serifName, size: size, relativeTo: style)
    }
    static func serifSemibold(_ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(serifName, size: size, relativeTo: style).weight(.semibold)
    }
    static func serifBold(_ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(serifName, size: size, relativeTo: style).weight(.bold)
    }
    static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
    /// 统计大数字用宋体，不用压缩黑体或海报字重；调用方负责字号缩放。
    static func display(_ size: CGFloat, relativeTo style: Font.TextStyle = .largeTitle) -> Font {
        .custom(serifName, size: size, relativeTo: style).weight(.semibold)
    }
    /// 眉题：小号粗体、加字距。
    static let kicker = Font.caption2.weight(.semibold)
    static func headline(_ size: CGFloat) -> Font { .system(size: size, weight: .semibold) }

    // MARK: - 无图书籍的低饱和封面（真实书封始终优先）

    static func coverColor(_ color: String) -> Color { Color(uiColor: coverUIColor(color)) }
    /// 题签占位封：六组宣纸色调，随日夜切换纸色；真实导入书封不反色。
    static func coverUIColor(_ color: String) -> UIColor {
        func paper(_ light: UInt32, _ dark: UInt32) -> UIColor {
            UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) }
        }
        switch color {
        case "ochre", "gold", "cream": return paper(0xEFE7D2, 0x26231C)
        case "blue": return paper(0xDFE3DC, 0x20241F)
        case "red", "vermilion": return paper(0xEADFD3, 0x27211D)
        case "purple": return paper(0xE4DFD8, 0x242220)
        case "green": return paper(0xE2E5D4, 0x22251D)
        case "ink": return paper(0xE8E4D8, 0x23221E)
        default: return paper(0xEFE7D2, 0x26231C)
        }
    }
    /// 题签上的墨色，随日夜切换；每个色板均保证小字对比度。
    static func coverForeground(_ color: String) -> Color { dynamic(0x38342B, 0xE8E2D2) }

    /// 纯色色块（保留渐变签名，便于沿用调用处）。
    static func coverGradient(_ color: String) -> LinearGradient {
        LinearGradient(colors: [coverColor(color), coverColor(color)], startPoint: .top, endPoint: .bottom)
    }
    static func coverGradient(_ base: UIColor, depth: CGFloat = 1) -> LinearGradient {
        let c = Color(uiColor: base.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light)))
        return LinearGradient(colors: [c, c], startPoint: .top, endPoint: .bottom)
    }

    private static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
}

// MARK: - 层次：平面内容，柔和的操作表面

extension View {
    /// 自定义系统字号也跟随 Dynamic Type；不要用固定字号再缩小文字来掩盖溢出。
    func scaledFont(_ size: CGFloat, weight: Font.Weight = .regular, width: Font.Width = .standard, relativeTo style: Font.TextStyle = .body) -> some View {
        modifier(ScaledSystemFont(size: size, weight: weight, width: width, style: style))
    }
    func respectReducedMotion() -> some View { modifier(ReducedMotionPolicy()) }
    /// 沿用旧签名；轻量实底，不描粗边。
    func glassSurface(in shape: AnyShape, interactive: Bool = false) -> some View {
        self
            .background(Theme.surface2, in: shape)
    }

    /// 只有需要归组的表单使用浅表面，不给每块内容套框。
    func glassCard(cornerRadius: CGFloat = Theme.radius, interactive: Bool = false) -> some View {
        self
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    /// 浮动操作条用轻微投影与正文区分。
    func floatingPanel(cornerRadius: CGFloat = Theme.radius) -> some View {
        self
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 14, y: 4)
    }

    func glassSurface(in shape: Capsule, interactive: Bool = false) -> some View {
        glassSurface(in: AnyShape(shape), interactive: interactive)
    }
    func glassSurface(in shape: RoundedRectangle, interactive: Bool = false) -> some View {
        glassSurface(in: AnyShape(shape), interactive: interactive)
    }
    func glassSurface(in shape: Circle, interactive: Bool = false) -> some View {
        glassSurface(in: AnyShape(shape), interactive: interactive)
    }

    /// 纸底：整页纯色。
    func paperBackground() -> some View {
        self.background { Theme.bg.ignoresSafeArea() }
    }

    /// 当前句：墨色文字 + 2pt 朱砂下划线，不再用浅底色块。
    func markerHighlight() -> some View {
        self
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 2)
            .padding(.bottom, 3)
            .background(alignment: .bottom) { Rectangle().fill(Theme.accent).frame(height: 2) }
    }
}

private struct ScaledSystemFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    let weight: Font.Weight
    let width: Font.Width
    init(size: CGFloat, weight: Font.Weight, width: Font.Width, style: Font.TextStyle) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: style)
        self.weight = weight; self.width = width
    }
    func body(content: Content) -> some View { content.font(.system(size: size, weight: weight).width(width)) }
}
private struct ReducedMotionPolicy: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content.transaction { if reduceMotion { $0.animation = nil; $0.disablesAnimations = true } }
    }
}

// MARK: - Color 扩展

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 255)/255, green: Double((hex >> 8) & 255)/255, blue: Double(hex & 255)/255, opacity: 1)
    }
    static func dynamicLight(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 255)/255, green: CGFloat((hex >> 8) & 255)/255, blue: CGFloat(hex & 255)/255, alpha: 1)
    }
    var relativeLuminance: Double {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        func linear(_ v: CGFloat) -> Double { v <= 0.04045 ? Double(v / 12.92) : pow(Double((v + 0.055) / 1.055), 2.4) }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }
    func contrastRatio(with other: UIColor) -> Double {
        let a = relativeLuminance, b = other.relativeLuminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
    /// 自带封面图的平均色不可预测，详情页白字的底色必须保证对比度。
    var backgroundForWhiteText: UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        var result = UIColor(red: r, green: g, blue: b, alpha: 1)
        while result.contrastRatio(with: .white) < 4.5 {
            r *= 0.9; g *= 0.9; b *= 0.9
            result = UIColor(red: r, green: g, blue: b, alpha: 1)
        }
        return result
    }
    /// HSB 微调：封面平均色 → 更饱和的渐变两端。
    func adjusted(brightness: CGFloat, saturation: CGFloat) -> UIColor {
        var hue: CGFloat = 0, sat: CGFloat = 0, bri: CGFloat = 0, alpha: CGFloat = 0
        guard getHue(&hue, saturation: &sat, brightness: &bri, alpha: &alpha) else { return self }
        return UIColor(hue: hue, saturation: min(1, max(0.08, sat * saturation)), brightness: min(1, max(0, bri + brightness)), alpha: alpha)
    }
}

extension UIImage {
    /// 自带封面图的平均色：让渐变底与真实封面同色系。
    var averageColor: UIColor? {
        guard let input = CIImage(image: self) else { return nil }
        let extent = CIVector(x: input.extent.minX, y: input.extent.minY, z: input.extent.width, w: input.extent.height)
        guard let filter = CIFilter(name: "CIAreaAverage", parameters: [kCIInputImageKey: input, kCIInputExtentKey: extent]),
              let output = filter.outputImage else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        CIContext(options: [.workingColorSpace: kCFNull as Any]).render(output, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
        return UIColor(red: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255, blue: CGFloat(pixel[2]) / 255, alpha: 1)
    }
}

// MARK: - 图标（SF Symbol 命名集中）

/// 全 App 同一功能只用一个 SF Symbol，界面里不直接写符号名。
/// 状态型图标反映「当前状态」（如书签已加、书籍已隐藏、应用锁已开）；
/// 动作触发型图标反映「点击后执行的动作」（如日夜切换、播放/暂停、试听/停止）。
enum Icon {
    // 页签与导航
    static let today          = "sun.max"
    static let now            = "house"
    static let organize       = "checklist"
    static let shelf          = "books.vertical"
    static let discover       = "arrow.down.to.line"
    static let stats          = "chart.bar.xaxis"
    static let settings       = "slider.horizontal.3"
    static let profile        = "person.crop.circle"
    static let back           = "chevron.left"
    static let close          = "xmark"
    static let collapse       = "chevron.down"
    static let expandUp       = "chevron.up"
    static let disclosure     = "chevron.right"
    static let more           = "ellipsis"
    static let moreCircle     = "ellipsis.circle"
    static let openExternal   = "arrow.up.right"
    static let jumpHere       = "arrow.turn.down.right"

    // 阅读与排版
    static let read           = "book"
    static let emptyBook      = "book.closed"
    static let comics         = "photo.stack"
    static let contents       = "list.bullet"
    static let typography     = "textformat.size"
    static let moreTypography = "slider.horizontal.3"
    static let fonts          = "character"
    static let addFont        = "plus.circle.fill"
    static let original       = "photo.on.rectangle"
    static let illustration   = "photo"
    static let readingDirection = "book.pages"
    static let nextDirection  = "arrow.right"
    static let prevDirection  = "arrow.left"
    static let downDirection  = "arrow.down"
    static func bookmark(_ marked: Bool) -> String { marked ? "bookmark.fill" : "bookmark" }
    static let removeBookmark = "bookmark.slash"
    static func dayNight(isDark: Bool) -> String { isDark ? "sun.max" : "moon" }
    static let nightBadge     = "moon.fill"
    static let appearance     = "circle.lefthalf.filled"
    static let help           = "questionmark.circle"
    static let autoTurn       = "timer"

    // 标注与笔记
    static let highlight      = "highlighter"
    static let underlineStyle = "underline"
    static let wavyStyle      = "scribble"
    static let note           = "square.and.pencil"
    static let noteStat       = "pencil.line"
    static let edit           = "pencil"
    static let copy           = "doc.on.doc"
    static let quote          = "quote.opening"
    static let extendRange    = "arrow.left.and.right"
    static let extendBack     = "chevron.left.to.line"
    static let extendForward  = "chevron.right.to.line"

    // 听书与音频
    static let listen         = "headphones"
    static let listening      = "waveform"
    static let voice          = "waveform"
    static let speaker        = "speaker.wave.2"
    static let sleepTimer     = "timer"
    static let rate           = "gauge.with.dots.needle.50percent"
    static func playback(_ playing: Bool) -> String { playing ? "pause.fill" : "play.fill" }
    static func previewPlayback(_ previewing: Bool) -> String { previewing ? "stop.fill" : "play.fill" }
    static let stopListening  = "stop.circle"
    static let previousSentence = "backward.fill"
    static let nextSentence   = "forward.fill"
    static let previousChapter = "backward.end.fill"
    static let nextChapter    = "forward.end.fill"
    static let airplay        = "airplayaudio"

    // 书架、文件与书源
    static let search         = "magnifyingglass"
    static let clearText      = "xmark.circle.fill"
    static let add            = "plus"
    static let importFile     = "doc.badge.plus"
    static let downloadFile   = "arrow.down.to.line"
    static let share          = "square.and.arrow.up"
    static let folder         = "folder"
    static let folderFill     = "folder.fill"
    static let folderAdd      = "folder.badge.plus"
    static let folderRemove   = "folder.badge.minus"
    static let unfiled        = "tray"
    static let document       = "doc"
    static let wifi           = "wifi"
    static let server         = "externaldrive"
    static let catalog        = "books.vertical"
    static let grid           = "square.grid.2x2"
    static let list           = "list.bullet"
    static let filter         = "line.3.horizontal.decrease"
    static let sort           = "arrow.up.arrow.down"
    static let sortRecent     = "clock"
    static let sortTitle      = "textformat"
    static let sortAuthor     = "person"
    static let sortAdded      = "calendar"

    // 隐私与安全
    static func lock(_ locked: Bool = false) -> String { locked ? "lock.fill" : "lock" }
    static let hiddenBadge    = "eye.slash.fill"
    static func hiddenBook(_ hidden: Bool) -> String { hidden ? "eye.slash" : "eye" }
    static func visibilityAction(currentlyVisible: Bool) -> String { currentlyVisible ? "eye.slash" : "eye" }

    // 云端、同步与状态
    static let cloud          = "icloud"
    static let cloudSynced    = "checkmark.icloud"
    static let cloudDisconnected = "icloud.slash"
    static let cloudError     = "exclamationmark.icloud"
    static let syncPaused     = "pause.circle"
    static let refresh        = "arrow.clockwise"
    static let repair         = "wand.and.stars"
    static let delete         = "trash"
    static let checkmark      = "checkmark"
    static let markRead       = "checkmark.circle"
    static let markUnread     = "circle"
    static let stepInProgress = "circle.dotted.circle"
    static let stepFailed     = "exclamationmark.circle.fill"
    static let transferFailed = "exclamationmark.triangle.fill"
    static let transferCancelled = "xmark.circle"
    static func selection(_ selected: Bool) -> String { selected ? "checkmark.circle.fill" : "circle" }
    static let warning        = "exclamationmark.circle"
    static let info           = "info.circle"
    static let duration       = "clock"

    // 关于与说明
    static let version        = "info.circle"
    static let license        = "doc.text"
    static let privacy        = "hand.raised"
}

// MARK: - 状态标签组件

/// 状态标签：印章式小方块，朱砂浅底。
struct SealBadge: View {
    let text: String
    var color: Color = Theme.accent
    var background: Color? = nil
    var filled: Bool = false
    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(filled ? Theme.onAccent : color)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(background ?? (filled ? color : color.opacity(0.10)), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

// MARK: - 按钮（柔和胶囊，主次明确）

/// 主按钮：深灰紫底、浅色字；辅助操作不用粗线框。
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var height: CGFloat = Theme.buttonHeight
    var fill: Color = Theme.ink
    var foreground: Color = Theme.onInk
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 18).padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: height)
            .foregroundStyle(foreground)
            .background(fill, in: RoundedRectangle(cornerRadius: Theme.buttonRadius, style: .continuous))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(Theme.pressSpring, value: configuration.isPressed)
            .contentShape(RoundedRectangle(cornerRadius: Theme.buttonRadius))
            .opacity(isEnabled ? 1 : 0.4)
    }
}

/// 次要按钮：浅灰紫底色，无描边。
struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var height: CGFloat = Theme.buttonHeight
    var emphasized = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 18).padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: height)
            .foregroundStyle(emphasized ? Theme.accent : Theme.ink2)
            .background(configuration.isPressed ? Theme.line : Theme.surface2, in: RoundedRectangle(cornerRadius: Theme.buttonRadius, style: .continuous))
            .animation(Theme.pressSpring, value: configuration.isPressed)
            .contentShape(RoundedRectangle(cornerRadius: Theme.buttonRadius))
            .opacity(isEnabled ? 1 : 0.4)
    }
}

/// 历史签名兼容壳，避免给内容重复添加表面。
struct GlassSkin: ViewModifier {
    var interactive = false
    var shape: AnyShape = AnyShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    func body(content: Content) -> some View { content }
}

/// 筛选 / 分段：选中为朱砂字 + 2pt 下划线，不用底色块；保留字重差异，不仅依赖颜色。
struct ChipPillStyle: ButtonStyle {
    var selected: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(selected ? .semibold : .regular))
            .foregroundStyle(selected ? Theme.accent : Theme.ink3)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .overlay(alignment: .bottom) {
                if selected { Rectangle().fill(Theme.accent).frame(height: 2).padding(.horizontal, 10) }
            }
        .contentShape(Rectangle())
        .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// 圆形图标按钮：至少 44pt，柔和底色。
struct CircleIconButton: View {
    let systemName: String
    let label: String
    var size: CGFloat = Theme.iconButtonSize
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            ThemeIcon(symbol: systemName, size: 20, weight: .semibold)
                .frame(width: size, height: size)
                .foregroundStyle(Theme.ink)
                .background(Theme.surface2, in: Circle())
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressButtonStyle(scale: 0.92))
        .accessibilityLabel(label)
    }
}

/// 听书按钮内容：正在听这本书时换成跳动的声波和「正在听」，点了打开播放器而不是重新开始。
struct ListenLabel: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let bookID: String
    @ObservedObject var player: SpeechPlayer
    var title = true
    private var on: Bool { player.book?.id == bookID && player.playing }
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: on ? Icon.listening : Icon.playback(false))
                .symbolEffect(.variableColor.iterative, isActive: on && !reduceMotion)
            if title { Text(on ? "正在听" : "听书") }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(on ? "打开播放器" : "开始听书")
    }
}

/// 统一按压反馈：轻缩 + 微透明。
struct PressButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var scale: CGFloat = 0.96
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? scale : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(Theme.pressSpring, value: configuration.isPressed)
    }
}

/// 触感反馈集中入口
enum Haptics {
    static func light() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func selection() { UISelectionFeedbackGenerator().selectionChanged() }
}

// MARK: - 卡片、线与区块标题

/// 表单内容组：浅色面，无边框。
struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
    }
}

/// 设置项图标：单色线性图标，不再用彩色方块。
struct SettingsIcon: View {
    let systemName: String
    let color: Color
    var body: some View {
        ThemeIcon(symbol: systemName, size: 22, weight: .medium)
            .foregroundStyle(color == Theme.danger ? Theme.danger : Theme.ink)
            .frame(width: 28, height: 28)
            .accessibilityHidden(true)
    }
}

/// 设置行：单色图标 + 标题 + 可选副标题 / 值
struct SettingsRow: View {
    var icon: String? = nil
    var color: Color = Theme.ink
    let title: String
    var value: String? = nil
    var subtitle: String? = nil
    var destructive = false
    var body: some View {
        HStack(spacing: 14) {
            if let icon {
                SettingsIcon(systemName: icon, color: destructive ? Theme.danger : color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.medium)).foregroundStyle(destructive ? Theme.danger : Theme.ink)
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(Theme.ink3) }
            }
            Spacer(minLength: 8)
            if let value { Text(value).font(.caption).foregroundStyle(Theme.ink3).lineLimit(1) }
        }
        .contentShape(Rectangle())
    }
}

/// 行间发丝线
struct RowDivider: View {
    var inset: CGFloat = 0
    var body: some View {
        Rectangle().fill(Theme.line).frame(height: 0.5).padding(.leading, inset)
    }
}

/// 历史线条组件现在只绘制中性分隔线。
struct InkRule: View {
    var height: CGFloat = Theme.rule
    var color: Color = Theme.line
    var body: some View { Rectangle().fill(color).frame(height: min(height, 0.5)).accessibilityHidden(true) }
}

/// 轻量区块标题；number / rule 保留调用兼容，不再展示报刊编号和分栏线。
struct SectionTitle: View {
    let text: String
    var badge: String? = nil
    var number: String? = nil
    var rule = true
    init(text: String, badge: String? = nil, number: String? = nil, rule: Bool = true) {
        self.text = text; self.badge = badge; self.number = number; self.rule = rule
    }
    init(title: String, badge: String? = nil, number: String? = nil, rule: Bool = true) {
        self.text = title; self.badge = badge; self.number = number; self.rule = rule
    }
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(text).font(.headline.weight(.semibold)).foregroundStyle(Theme.ink)
            if let badge { SealBadge(text: badge) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// 各主页面共用的页眉：宋体大标题与一行说明。
struct PageMasthead: View {
    let title: String
    var subtitle: String? = nil
    var rule = true
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Theme.serifSemibold(34, relativeTo: .largeTitle))
                .foregroundStyle(Theme.ink)
                .frame(minHeight: 44, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(Theme.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 细圆角进度条；紫色只表示当前进度。
struct ProgressBar: View {
    var value: Double
    var track: Color = Theme.line
    var tint: Color = Theme.accent
    var height: CGFloat = 3
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(track)
                Rectangle().fill(tint).frame(width: max(0, min(1, value)) * geo.size.width)
            }
        }
        .frame(height: height)
        .clipShape(Capsule())
        .accessibilityElement()
        .accessibilityLabel("进度")
        .accessibilityValue("\(Int((value * 100).rounded()))%")
    }
}

// MARK: - 书籍封面

/// 真实书封完整显示；无图时使用线装书题签占位封（纸色随日夜切换），不伪造出版物图像。
struct BookCoverView: View {
    let title: String
    var color = "ink"
    var author = ""
    var image: UIImage? = nil
    var width: CGFloat = 98
    init(title: String, color: String = "ink", author: String = "", data: Data? = nil, image: UIImage? = nil, width: CGFloat = 98) {
        self.title = title; self.color = color; self.author = author; self.width = width
        self.image = image ?? data.flatMap(UIImage.init(data:))
    }
    /// 中文短名用竖排题签；长名 / 非中文退回横排，小尺寸简化。
    private var verticalTitle: Bool {
        let scalars = title.unicodeScalars
        guard !scalars.isEmpty, scalars.count <= 11 else { return false }
        let cjk = scalars.filter { (0x4E00...0x9FFF).contains($0.value) || "，。、《》".unicodeScalars.contains($0) }.count
        return Double(cjk) / Double(scalars.count) >= 0.6
    }
    var body: some View {
        let fg = Theme.coverForeground(color)
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFit().background(Theme.surface2)
            } else if width < 52 {
                tinyPlaceholder(fg)
            } else {
                slipPlaceholder(fg)
            }
        }
        .frame(width: width, height: width / 0.7)
        .clipShape(RoundedRectangle(cornerRadius: min(3, width * 0.04), style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: width * 0.045, x: 1, y: 3)
        .accessibilityElement()
        .accessibilityLabel("《\(title)》封面")
    }
    /// 小尺寸：书脊 + 横排书名，省略题签与印。
    private func tinyPlaceholder(_ fg: Color) -> some View {
        ZStack(alignment: .leading) {
            Theme.coverColor(color)
            Rectangle().fill(fg.opacity(0.10)).frame(width: max(2, width * 0.09))
            Text(title)
                .font(Theme.serif(max(8, width * 0.15)))
                .foregroundStyle(fg)
                .lineLimit(3)
                .minimumScaleFactor(0.7)
                .padding(.leading, max(4, width * 0.14)).padding(.trailing, 4)
                .frame(width: width, height: width / 0.7, alignment: .center)
        }
    }
    /// 题签封：左侧书脊色条，右上竖排（或横排）题签，题签下朱砂小印。
    private func slipPlaceholder(_ fg: Color) -> some View {
        let height = width / 0.7
        let spine = max(4, width * 0.09)
        let titleSize = min(26, max(11, width * 0.145))
        let seal = max(10, width * 0.15)
        return ZStack(alignment: .leading) {
            Theme.coverColor(color)
            Rectangle().fill(fg.opacity(0.10)).frame(width: spine)
            Rectangle().fill(fg.opacity(0.35)).frame(width: 0.5).padding(.leading, spine)
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                VStack(spacing: max(3, width * 0.045)) {
                    if verticalTitle {
                        Text(title.map(String.init).joined(separator: "\n"))
                            .font(Theme.serif(titleSize))
                            .lineSpacing(-titleSize * 0.12)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(fg)
                            .padding(.horizontal, titleSize * 0.34)
                            .padding(.vertical, titleSize * 0.44)
                            .background(fg.opacity(0.06), in: RoundedRectangle(cornerRadius: 2))
                            .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(fg.opacity(0.14), lineWidth: 0.5))
                    } else {
                        Text(title)
                            .font(Theme.serif(titleSize))
                            .foregroundStyle(fg)
                            .multilineTextAlignment(.center)
                            .lineLimit(4)
                            .minimumScaleFactor(0.75)
                            .padding(.horizontal, titleSize * 0.4)
                            .padding(.vertical, titleSize * 0.44)
                            .background(fg.opacity(0.06), in: RoundedRectangle(cornerRadius: 2))
                            .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(fg.opacity(0.14), lineWidth: 0.5))
                    }
                    Text("听")
                        .font(Theme.serif(seal * 0.62))
                        .foregroundStyle(Theme.onAccent)
                        .frame(width: seal, height: seal)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: seal * 0.22, style: .continuous))
                        .accessibilityHidden(true)
                    Spacer(minLength: 0)
                }
                .padding(.top, width * 0.14)
                Spacer(minLength: 0)
            }
            .padding(.leading, spine + max(2, width * 0.03))
            if width >= 72 && !author.isEmpty {
                Text(author)
                    .font(.system(size: max(8, width * 0.075)))
                    .foregroundStyle(fg.opacity(0.85))
                    .lineLimit(1)
                    .padding(.leading, spine + max(6, width * 0.06)).padding(.bottom, width * 0.08)
                    .frame(width: width, height: height, alignment: .bottomLeading)
            }
        }
        .frame(width: width, height: height)
    }
}

struct FlexibleCover: View {
    let title: String
    var color = "ink"
    var author = ""
    var image: UIImage?
    var body: some View {
        Color.clear.aspectRatio(0.7, contentMode: .fit).overlay {
            GeometryReader { geo in BookCoverView(title: title, color: color, author: author, image: image, width: geo.size.width) }
        }
    }
}

/// 封面色块底：自带封面图时取平均色，否则用封面色板。用于详情与播放器的整块色头。
struct CoverBackdrop: View {
    let color: String
    var image: UIImage?
    var depth: CGFloat = 1
    @State private var average: UIColor?
    var body: some View {
        Group {
            if image != nil { Color(uiColor: average?.backgroundForWhiteText ?? UIColor(hex: 0x272623)) }
            else { Theme.coverColor(color) }
        }
        .task(id: image.map(ObjectIdentifier.init)) {
            guard let image else { average = nil; return }
            let box = UncheckedImage(image: image)
            average = await Task.detached(priority: .utility) { box.image.averageColor }.value
        }
    }
    private struct UncheckedImage: @unchecked Sendable { let image: UIImage }
}

struct NoticeView: View {
    let text: String
    var body: some View {
        Label(text, systemImage: Icon.warning).font(.footnote).foregroundStyle(Theme.danger)
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .leading) { Rectangle().fill(Theme.danger).frame(width: 3) }
    }
}

enum Samples {
    static let books: [Book] = {
        guard let url = Bundle.main.url(forResource: "samples", withExtension: "json"), let data = try? Data(contentsOf: url), let books = try? JSONDecoder().decode([Book].self, from: data) else { return [] }
        return books
    }()
}

// MARK: - 阅读偏好（七种中性阅读纸色）

enum ReaderPaper: String, CaseIterable, Identifiable {
    case paper, mist, ancient, eink, white, blue, night
    var id: String { rawValue }
    var name: String {
        ["paper": "默认", "mist": "雾灰", "ancient": "旧书", "eink": "浅灰", "white": "纯白", "blue": "深蓝", "night": "夜读"][rawValue] ?? rawValue
    }
    var swatch: Color {
        switch self {
        case .paper:   Color(hex: 0xFAF7EF)
        case .mist:    Color(hex: 0xE6EBF1)
        case .ancient: Color(hex: 0xF3E7D6)
        case .eink:    Color(hex: 0xF0F0F0)
        case .white:   Color(hex: 0xFFFFFF)
        case .blue:    Color(hex: 0x1A2C3A)
        case .night:   Color(hex: 0x101012)
        }
    }
    var dark: Bool { self == .blue || self == .night }
    static let xuan = Theme.bg
    static let xuanSecondary = Theme.ink3
}

struct ReaderPreferences: Equatable {
    var fontSize: Double = 19
    var lineSpacing: Double = 11
    var font = "system"
    var paper = "paper"
    var scrolling = false
    var paragraphSpacing: Double = 15
    var margin: Double = 24
    var indent = true
    var justified = true
    /// 字间距（pt）
    var letterSpacing: Double = 0
    /// 简繁转换：none / s2t（简→繁）/ t2s（繁→简）
    var convert = "none"
    var kind: ReaderPaper { ReaderPaper(rawValue: paper) ?? .paper }
    /// 默认纸色跟随外观；用户选择的其他纸色保持原样。
    var background: Color { paper == "paper" ? ReaderPaper.xuan : kind.swatch }
    var foreground: Color {
        switch kind {
        case .mist:    return Color(hex: 0x14181F)
        case .ancient: return Color(hex: 0x2C2418)
        case .eink:    return Color(hex: 0x242424)
        case .white:   return Color(hex: 0x14181F)
        case .blue:    return Color(hex: 0xD5E4F0)
        case .night:   return Color(hex: 0xEFEDE6)
        case .paper:   return Theme.ink
        }
    }
    var secondary: Color {
        switch kind {
        case .mist:    return Color(hex: 0x5C6675)
        case .ancient: return Color(hex: 0x6E5F4B)
        case .eink:    return Color(hex: 0x666666)
        case .white:   return Color(hex: 0x5C6675)
        case .blue:    return Color(hex: 0x8AA0B4)
        case .night:   return Color(hex: 0xA5A296)
        case .paper:   return ReaderPaper.xuanSecondary
        }
    }
    /// 原生分页与原书图文共用朱砂跟读标记。
    var highlightBand: UIColor {
        if kind.dark { return UIColor(hex: 0xD97B6C) }
        if kind == .paper { return UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: 0xD97B6C) : UIColor(hex: 0xA63A2E) } }
        return UIColor(hex: 0xA63A2E)
    }
    /// 连续滚动模式整句铺底：低饱和半透明朱砂
    var highlight: UIColor {
        let band = highlightBand, darkPaper = kind.dark
        return UIColor { band.resolvedColor(with: $0).withAlphaComponent($0.userInterfaceStyle == .dark || darkPaper ? 0.20 : 0.14) }
    }
    /// serif 思源宋体 / kai 霞鹜文楷 / system 系统字体 / custom:<PostScript 名> 导入的字体
    var uiFont: UIFont {
        if font == "system" { return .systemFont(ofSize: fontSize) }
        if font.hasPrefix("custom:") { return UIFont(name: String(font.dropFirst(7)), size: fontSize) ?? .systemFont(ofSize: fontSize) }
        return UIFont(name: font == "kai" ? "LXGWWenKaiLite-Regular" : Theme.serifName, size: fontSize) ?? .systemFont(ofSize: fontSize)
    }
}

extension String {
    /// 眉题大写：ASCII 直接大写，中文原样（避免整串被 .uppercase 处理出意外）
    var localUppercased: String { self.map { $0.isASCII ? Character($0.uppercased()) : $0 }.reduce(into: "") { $0.append($1) } }
}

/// 统一使用原生 SF Symbols 渲染，保持字重、基线对齐与填充/描边状态切换的一致性。
struct ThemeIcon: View {
    let symbol: String
    var size: CGFloat = 20
    var weight: Font.Weight = .regular
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: round(size * 0.78), weight: weight))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
