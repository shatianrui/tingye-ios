import SwiftUI
import UIKit
import CoreImage

/// App chrome has its own palette. ReaderPaper still owns the document canvas and text.
enum AppTheme: String, CaseIterable, Identifiable, Sendable {
    case oat, moss, night, silver

    static let storageKey = "app.theme"
    static let appearanceKey = "app.appearance"
    static let defaultTheme: Self = .oat
    static let defaultAppearance = "theme"

    init(storedValue: String) { self = Self(rawValue: storedValue) ?? Self.defaultTheme }
    var id: String { rawValue }

    var title: String {
        switch self {
        case .oat: "燕麦书房"
        case .moss: "苔庭"
        case .night: "蓝调夜航"
        case .silver: "银盐档案"
        }
    }

    var detail: String {
        switch self {
        case .oat: "暖纸、宋体与陶棕色"
        case .moss: "青绿、圆角与柔和分区"
        case .night: "深蓝、冷光与安静的阅读界面"
        case .silver: "银灰、方角与紧凑列表"
        }
    }

    var prefersDark: Bool { self == .night }
    var usesSerifHeadings: Bool { self == .oat || self == .night }
    var radius: CGFloat {
        switch self {
        case .oat: 10
        case .moss: 16
        case .night: 12
        case .silver: 3
        }
    }
    var heroRadius: CGFloat { self == .moss ? 24 : radius + 2 }
    var buttonRadius: CGFloat {
        switch self {
        case .oat: 5
        case .moss: 30
        case .night: 20
        case .silver: 3
        }
    }
    var radiusSmall: CGFloat { min(radius, 6) }
    var radiusField: CGFloat { min(radius, 12) }
    var radiusPill: CGFloat { buttonRadius }
    var transportRadius: CGFloat { self == .silver ? 12 : 40 }

    func coverRadius(_ width: CGFloat) -> CGFloat {
        self == .silver ? 0 : min(self == .moss ? 7 : 5, max(2, width * 0.035))
    }

    func display(_ size: CGFloat, relativeTo style: Font.TextStyle = .largeTitle) -> Font {
        if usesSerifHeadings { return Theme.serif(size, relativeTo: style) }
        return .system(style, design: .default).weight(.semibold)
    }

    func windowStyle(for appearance: String) -> UIUserInterfaceStyle {
        switch appearance {
        case "system": .unspecified
        case "light": .light
        case "dark": .dark
        default: prefersDark ? .dark : .light
        }
    }

    func palette(dark: Bool) -> ThemePalette {
        switch (self, dark) {
        case (.oat, false):
                .init(bg: 0xFBF4E7, surface: 0xFFF9EE, sunken: 0xF5EADC,
                      ink: 0x30251D, muted: 0x695749, line: 0xCDB89F,
                      accent: 0x8D422E, soft: 0xF3DFCF, onAccent: 0xFFF7ED,
                      danger: 0xA12E27, dangerSoft: 0xF7E4DD,
                      covers: .init(coral: 0xE8BDAA, sand: 0xE9CC99, cool: 0xD6BEA8))
        case (.oat, true):
                .init(bg: 0x30251F, surface: 0x3B2D24, sunken: 0x352821,
                      ink: 0xF9EADA, muted: 0xD3BFAB, line: 0x7C6455,
                      accent: 0xFFBA98, soft: 0x503628, onAccent: 0x402418,
                      danger: 0xFFB3A5, dangerSoft: 0x592F29,
                      covers: .init(coral: 0x774640, sand: 0x6B5131, cool: 0x645045))
        case (.moss, false):
                .init(bg: 0xEDF4ED, surface: 0xF8FCF7, sunken: 0xE2ECE3,
                      ink: 0x20352B, muted: 0x4D6656, line: 0xAFC4B5,
                      accent: 0x285F4B, soft: 0xD8E8DB, onAccent: 0xF5FFF7,
                      danger: 0x92392D, dangerSoft: 0xF5E3DC,
                      covers: .init(coral: 0xDCC1AA, sand: 0xCDD6A7, cool: 0xB6D2C1))
        case (.moss, true):
                .init(bg: 0x1B2B23, surface: 0x24372E, sunken: 0x203129,
                      ink: 0xE6F4E9, muted: 0xBAD4C3, line: 0x5F7D6B,
                      accent: 0xA3D8B8, soft: 0x314B3C, onAccent: 0x18392B,
                      danger: 0xFFB4AA, dangerSoft: 0x513130,
                      covers: .init(coral: 0x624A40, sand: 0x4A583C, cool: 0x355548))
        case (.night, false):
                .init(bg: 0xE8EEF9, surface: 0xF2F6FF, sunken: 0xE0E8F6,
                      ink: 0x21304E, muted: 0x526180, line: 0xA9B9D6,
                      accent: 0x344F90, soft: 0xDCE6FA, onAccent: 0xFFFFFF,
                      danger: 0xA12E47, dangerSoft: 0xF6E3EA,
                      covers: .init(coral: 0xD9C5DD, sand: 0xD8D6EA, cool: 0xB4C8E7))
        case (.night, true):
                .init(bg: 0x141F34, surface: 0x1C2B46, sunken: 0x18253C,
                      ink: 0xEDF1FF, muted: 0xB9C7E1, line: 0x526483,
                      accent: 0xAEC6FF, soft: 0x2A3A5D, onAccent: 0x15213A,
                      danger: 0xFFB4B5, dangerSoft: 0x502D42,
                      covers: .init(coral: 0x56415F, sand: 0x424D67, cool: 0x334C76))
        case (.silver, false):
                .init(bg: 0xF1F3F7, surface: 0xFBFCFF, sunken: 0xE8ECF2,
                      ink: 0x1B2432, muted: 0x505D70, line: 0xB4BECD,
                      accent: 0x354E83, soft: 0xE2E8F5, onAccent: 0xFFFFFF,
                      danger: 0xA33545, dangerSoft: 0xF8E6E9,
                      covers: .init(coral: 0xDBC7CF, sand: 0xDCD5C7, cool: 0xBFCBDE))
        case (.silver, true):
                .init(bg: 0x242934, surface: 0x303846, sunken: 0x292F3B,
                      ink: 0xEEF1F7, muted: 0xC5CCDB, line: 0x667287,
                      accent: 0xB4CAFF, soft: 0x414D66, onAccent: 0x202F53,
                      danger: 0xFFB1BD, dangerSoft: 0x562F42,
                      covers: .init(coral: 0x5D4956, sand: 0x555443, cool: 0x455670))
        }
    }

    private func color(_ key: KeyPath<ThemePalette, UInt32>) -> Color {
        let light = palette(dark: false)[keyPath: key]
        let dark = palette(dark: true)[keyPath: key]
        return Color(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    var bg: Color { color(\.bg) }
    var surface: Color { color(\.surface) }
    var surface2: Color { color(\.sunken) }
    var surfaceSunken: Color { color(\.sunken) }
    var ink: Color { color(\.ink) }
    var ink2: Color { color(\.muted) }
    var ink3: Color { color(\.muted) }
    var ink4: Color { color(\.muted) }
    var accent: Color { color(\.accent) }
    var onAccent: Color { color(\.onAccent) }
    var accentSoft: Color { color(\.soft) }
    var danger: Color { color(\.danger) }
    var dangerSoft: Color { color(\.dangerSoft) }
    var line: Color {
        Color(uiColor: UIColor { traits in
            let palette = palette(dark: traits.userInterfaceStyle == .dark)
            return UIColor(hex: traits.accessibilityContrast == .high ? palette.muted : palette.line)
        })
    }
    var lineField: Color { line }
    var onInk: Color { bg }
    var focus: Color { accent }
    var link: Color { accent }
    var marker: Color { accent }
    var readingHighlight: Color { accentSoft }
    var hero: Color { self == .silver ? surface : accentSoft }
    var heroInk: Color { ink }
    var wash: Color { accentSoft }
    var gold: Color { ink2 }
    var goldSoft: Color { surface2 }
    var warm: Color { surface2 }

    func coverColor(_ name: String) -> Color {
        Color(uiColor: coverUIColor(name))
    }

    func coverUIColor(_ name: String) -> UIColor {
        UIColor { traits in
            let covers = palette(dark: traits.userInterfaceStyle == .dark).covers
            switch name {
            case "red", "vermilion": return UIColor(hex: covers.coral)
            case "gold", "cream": return UIColor(hex: covers.sand)
            default: return UIColor(hex: covers.cool)
            }
        }
    }

}

struct ThemePalette: Sendable {
    struct Covers: Sendable {
        let coral, sand, cool: UInt32
    }

    let bg, surface, sunken: UInt32
    let ink, muted, line: UInt32
    let accent, soft, onAccent: UInt32
    let danger, dangerSoft: UInt32
    let covers: Covers
}

private struct AppThemeKey: EnvironmentKey {
    static let defaultValue = AppTheme.defaultTheme
}

extension EnvironmentValues {
    var appTheme: AppTheme {
        get { self[AppThemeKey.self] }
        set { self[AppThemeKey.self] = newValue }
    }
}

// Shared metrics and document typography.
enum Theme {
    static let space1: CGFloat = 4
    static let space2: CGFloat = 8
    static let space3: CGFloat = 12
    static let space4: CGFloat = 16
    static let space5: CGFloat = 24
    static let space6: CGFloat = 32
    static let space7: CGFloat = 48
    static let inset: CGFloat = 24
    static let insetCompact: CGFloat = 20
    static let cardInset: CGFloat = 20
    static let rowMinHeight: CGFloat = 52
    static let sectionSpacing = space6
    static let pageWidth: CGFloat = 720
    static let buttonHeight: CGFloat = 50
    static let iconButtonSize: CGFloat = 44
    static let hairline: CGFloat = 0.75
    static let progressHeight: CGFloat = 3
    static let sealDotSize: CGFloat = 6
    static let mastheadTracking: CGFloat = 2.2
    static let pressedOpacity = 0.88
    static let disabledOpacity = 0.4
    static let ruleHeavy: CGFloat = 3
    static let ruleMedium: CGFloat = 2
    static let rule: CGFloat = 1

    // MARK: - 动效

    static let pressSpring = Animation.spring(response: 0.32, dampingFraction: 0.86)
    static let pressAnimation = Animation.easeOut(duration: 0.2)
    static let smoothSpring = pressSpring

    // MARK: - 字体：界面使用系统字体；宋体用于书名、摘句与正文偏好

    static let serifName = "NotoSerifCJKsc-Regular"
    static func serif(_ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(serifName, size: size, relativeTo: style)
    }
    /// 界面字体：系统字体（真实字重、与 SF Symbols 基线对齐）。固定字号，不再随 relativeTo 缩放。
    static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
    /// Font 不承载 tracking；配合 .mastheadStyle() 应用完整眉题样式。
    static let masthead = Font.system(size: 12, weight: .semibold)
    static let kicker = masthead

    // Fixed fallbacks for document and system-owned renderers without a SwiftUI environment.
    static let wash = AppTheme.defaultTheme.wash

}

// MARK: - 层次：宣纸画布与安静的内容表面

extension View {
    func mastheadStyle(color: Color? = nil) -> some View {
        modifier(MastheadStyle(color: color))
    }
    /// 自定义系统字号也跟随 Dynamic Type；不要用固定字号再缩小文字来掩盖溢出。
    func scaledFont(_ size: CGFloat, weight: Font.Weight = .regular, width: Font.Width = .standard, relativeTo style: Font.TextStyle = .body) -> some View {
        modifier(ScaledSystemFont(size: size, weight: weight, width: width, style: style))
    }
    func respectReducedMotion() -> some View { modifier(ReducedMotionPolicy()) }
    func glassSurface(in shape: AnyShape, interactive: Bool = false) -> some View {
        modifier(ThemedSurface(shape: shape))
    }

    func glassCard(cornerRadius: CGFloat? = nil, interactive: Bool = false) -> some View {
        modifier(ThemedCard(cornerRadius: cornerRadius))
    }

    func columnRule(_ height: CGFloat = 1) -> some View {
        modifier(ThemedRule(height: height))
    }

    func softCardShadow() -> some View { modifier(SoftCardShadow()) }

    func floatingPanel(cornerRadius: CGFloat? = nil) -> some View {
        glassCard(cornerRadius: cornerRadius).modifier(FloatingPanelShadow())
    }

    func glassSurface(in shape: Capsule, interactive: Bool = false) -> some View {
        glassSurface(in: AnyShape(shape), interactive: interactive)
    }
    func glassSurface(in shape: RoundedRectangle, interactive: Bool = false) -> some View {
        glassSurface(in: AnyShape(shape), interactive: interactive)
    }
    func glassSurface(in shape: Rectangle, interactive: Bool = false) -> some View {
        glassSurface(in: AnyShape(shape), interactive: interactive)
    }
    func glassSurface(in shape: Circle, interactive: Bool = false) -> some View {
        glassSurface(in: AnyShape(shape), interactive: interactive)
    }

    /// v29 书房：已删除两层亚像素叠印的假粗体（糊字、读屏重复朗读）。保留为空操作，兼容既有调用点。
    func serifEmbolden(_ size: CGFloat) -> some View { self }
    /// 系统字体已有真实字重，特粗档不再叠印加粗，保持大标题干净。
    func serifHeavy(_ size: CGFloat) -> some View { self }

    func paperBackground() -> some View { modifier(ThemedBackground()) }

    func markerHighlight() -> some View { modifier(ThemedHighlight()) }
}

private struct MastheadStyle: ViewModifier {
    @Environment(\.appTheme) private var appTheme
    let color: Color?

    func body(content: Content) -> some View {
        content.font(Theme.masthead).tracking(Theme.mastheadTracking)
            .foregroundStyle(color ?? appTheme.ink3)
    }
}

private struct ThemedSurface: ViewModifier {
    @Environment(\.appTheme) private var appTheme
    let shape: AnyShape

    func body(content: Content) -> some View { content.background(appTheme.surface, in: shape) }
}

private struct ThemedCard: ViewModifier {
    @Environment(\.appTheme) private var appTheme
    let cornerRadius: CGFloat?

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius ?? appTheme.radius)
        content.background(appTheme.surface, in: shape)
            .overlay { shape.strokeBorder(appTheme.line, lineWidth: Theme.rule).allowsHitTesting(false) }
    }
}

private struct ThemedRule: ViewModifier {
    @Environment(\.appTheme) private var appTheme
    let height: CGFloat

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            Rectangle().fill(appTheme.line).frame(height: height)
                .accessibilityHidden(true).allowsHitTesting(false)
        }
    }
}

private struct ThemedBackground: ViewModifier {
    @Environment(\.appTheme) private var appTheme

    func body(content: Content) -> some View {
        content.background { appTheme.bg.ignoresSafeArea() }
            .toolbarBackground(appTheme.bg, for: .navigationBar)
    }
}

private struct ThemedHighlight: ViewModifier {
    @Environment(\.appTheme) private var appTheme

    func body(content: Content) -> some View {
        content.foregroundStyle(appTheme.ink)
            .padding(.leading, 20).padding(.trailing, 16)
            .padding(.vertical, 16)
            .background(appTheme.readingHighlight)
            .overlay(alignment: .leading) {
                Rectangle().fill(appTheme.accent).frame(width: 3).accessibilityHidden(true)
            }
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

// MARK: - 本地化

/// 运行时文字的本地化查找：组件收到的是普通字符串（标题、说明、提示、错误），
/// 用它在 Localizable.xcstrings 里查译文；找不到时原样返回中文。
func L(_ key: String) -> String { NSLocalizedString(key, comment: "") }

extension Locale {
    /// 与界面语言一致的区域格式（日期、星期），而不是固定的 zh_CN。
    static var app: Locale { Locale(identifier: Bundle.main.preferredLocalizations.first ?? "zh-Hans") }
}

// MARK: - Color 扩展

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 255)/255, green: Double((hex >> 8) & 255)/255, blue: Double(hex & 255)/255, opacity: 1)
    }
    static func dynamicLight(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(UIColor { traits in
            let color = UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
                return color
        })
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

/// 精装刊物卡硬朗纸面投影：日间 3pt 炭黑微影，夜间克制深影。
struct SoftCardShadow: ViewModifier {
    @Environment(\.appTheme) private var appTheme
    @Environment(\.colorScheme) private var colorScheme
    func body(content: Content) -> some View {
        let dark = colorScheme == .dark
        content.shadow(color: .black.opacity(dark ? 0.26 : 0.09),
                       radius: appTheme == .silver ? 0 : 8, x: 0, y: appTheme == .silver ? 1 : 3)
    }
}

private struct FloatingPanelShadow: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    func body(content: Content) -> some View {
        if colorScheme == .dark {
            content.shadow(color: .black.opacity(0.55), radius: 18, x: 0, y: 8)
        } else {
            content.shadow(color: Color(hex: 0x141413).opacity(0.14), radius: 20, x: 0, y: 8)
        }
    }
}

// MARK: - 状态标签组件

struct SealBadge: View {
    @Environment(\.appTheme) private var appTheme
    let text: String
    var color: Color? = nil
    var background: Color? = nil
    var filled: Bool = false
    var body: some View {
        HStack(spacing: Theme.space1) {
            Image(systemName: "ticket").accessibilityHidden(true)
            Text(L(text))
        }
        .font(Theme.sans(11, weight: .semibold))
        .foregroundStyle(color ?? appTheme.accent)
        .padding(.horizontal, Theme.space2)
        .padding(.vertical, Theme.space1)
        .background(background ?? appTheme.accentSoft, in: RoundedRectangle(cornerRadius: appTheme.radiusPill))
    }
}

// MARK: - 按钮（刊物微直角，浓墨主块 + 官方陶土焦点，主次分明）

/// 主按钮采用与界面外观对应的高对比实底。
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.appTheme) private var appTheme
    @Environment(\.isEnabled) private var isEnabled
    var height: CGFloat = Theme.buttonHeight
    var fill: Color? = nil
    var foreground: Color? = nil
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.sans(15, weight: .semibold))
            .fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(.center)
            .padding(.horizontal, Theme.space4).padding(.vertical, Theme.space3)
            .frame(maxWidth: .infinity, minHeight: height)
            .foregroundStyle(foreground ?? appTheme.onAccent)
            .background(fill ?? appTheme.accent, in: RoundedRectangle(cornerRadius: appTheme.buttonRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: appTheme.buttonRadius, style: .continuous)
                    .strokeBorder(appTheme.ink.opacity(0.18), lineWidth: Theme.hairline)
            }
            .modifier(PressFeedback(pressed: configuration.isPressed))
            .contentShape(RoundedRectangle(cornerRadius: appTheme.buttonRadius))
            .opacity(isEnabled ? 1 : Theme.disabledOpacity)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.appTheme) private var appTheme
    @Environment(\.isEnabled) private var isEnabled
    var height: CGFloat = Theme.buttonHeight
    var emphasized = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.sans(15, weight: .medium))
            .fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(.center)
            .padding(.horizontal, Theme.space4).padding(.vertical, Theme.space3)
            .frame(maxWidth: .infinity, minHeight: height)
            .foregroundStyle(emphasized ? appTheme.accent : appTheme.ink)
            .background(emphasized ? appTheme.accentSoft : appTheme.surface, in: RoundedRectangle(cornerRadius: appTheme.buttonRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: appTheme.buttonRadius, style: .continuous)
                    .strokeBorder(emphasized ? appTheme.accent : appTheme.ink.opacity(0.28), lineWidth: Theme.rule)
            }
            .modifier(PressFeedback(pressed: configuration.isPressed))
            .contentShape(RoundedRectangle(cornerRadius: appTheme.buttonRadius))
            .opacity(isEnabled ? 1 : Theme.disabledOpacity)
    }
}

/// 刊物筛选签：微直角矩形，选中态浓墨实底 + 顶部陶土细线提示，勾号提供形状状态通道。
struct ChipPillStyle: ButtonStyle {
    @Environment(\.appTheme) private var appTheme
    var selected: Bool
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: appTheme.buttonRadius, style: .continuous)
        HStack(spacing: Theme.space1) {
            if selected { Image(systemName: Icon.checkmark).font(.system(size: 12, weight: .bold)).accessibilityHidden(true) }
            configuration.label
        }
        .font(Theme.sans(14, weight: selected ? .semibold : .regular))
        .foregroundStyle(selected ? appTheme.onAccent : appTheme.ink)
        .padding(.horizontal, Theme.space3)
        .frame(minHeight: Theme.iconButtonSize)
        .background(selected ? appTheme.accent : appTheme.surface, in: shape)
        .overlay { shape.strokeBorder(selected ? appTheme.accent : appTheme.line, lineWidth: Theme.rule) }
        .contentShape(shape)
        .modifier(PressFeedback(pressed: configuration.isPressed))
        .opacity(isEnabled ? 1 : Theme.disabledOpacity)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// 无底无描边图标按钮，命中区至少 44pt。
struct CircleIconButton: View {
    @Environment(\.appTheme) private var appTheme
    let systemName: String
    let label: String
    var size: CGFloat = Theme.iconButtonSize
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            ThemeIcon(symbol: systemName, size: 20)
                .frame(width: size, height: size)
                .foregroundStyle(appTheme.ink2)
                .frame(minWidth: Theme.iconButtonSize, minHeight: Theme.iconButtonSize)
                .contentShape(RoundedRectangle(cornerRadius: appTheme.radius))
        }
        .buttonStyle(PressButtonStyle(scale: 0.92))
        .accessibilityLabel(label)
    }
}

/// 听书按钮内容：正在听这本书时换成跳动的声波和「正在听」，点了打开播放器而不是重新开始。
struct ListenLabel: View {
    let bookID: String
    @ObservedObject var player: SpeechPlayer
    var title = true
    private var on: Bool { player.book?.id == bookID && player.playing }
    var body: some View {
        HStack(spacing: Theme.space2) {
            Image(systemName: on ? Icon.listening : Icon.playback(false))
            if title { Text(on ? "正在听" : "听书") }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(on ? "打开播放器" : "开始听书")
    }
}

/// scale 参数仅保留源码兼容；v31 按压只改变透明度。
struct PressButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var scale: CGFloat = 0.96
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.modifier(PressFeedback(pressed: configuration.isPressed))
            .opacity(isEnabled ? 1 : Theme.disabledOpacity)
    }
}

private struct PressFeedback: ViewModifier {
    let pressed: Bool
    func body(content: Content) -> some View {
        content.opacity(pressed ? Theme.pressedOpacity : 1)
            .animation(Theme.pressAnimation, value: pressed)
            .respectReducedMotion()
    }
}

/// 触感反馈集中入口
enum Haptics {
    static func light() { if GeneralSettings.hapticsEnabled { UIImpactFeedbackGenerator(style: .light).impactOccurred() } }
    static func selection() { if GeneralSettings.hapticsEnabled { UISelectionFeedbackGenerator().selectionChanged() } }
}

// MARK: - 卡片、线与区块标题

/// 白卡、发丝线与柔影；内边距默认 20。
struct Card<Content: View>: View {
    var padding: CGFloat = Theme.cardInset
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard().softCardShadow()
    }
}

/// 设置项图标：墨色线性图标，陶土留给编号与眉题。
struct SettingsIcon: View {
    let systemName: String
    let color: Color
    var body: some View {
        ThemeIcon(symbol: systemName, size: 22, weight: .medium)
            .foregroundStyle(color)
            .frame(width: 32, height: 32)
            .accessibilityHidden(true)
    }
}

/// 设置行：单色图标 + 标题 + 可选副标题 / 值
struct SettingsRow: View {
    @Environment(\.appTheme) private var appTheme
    var icon: String? = nil
    var color: Color? = nil
    let title: String
    var value: String? = nil
    var subtitle: String? = nil
    var destructive = false
    var body: some View {
        HStack(spacing: Theme.space3) {
            if let icon {
                SettingsIcon(systemName: icon, color: destructive ? appTheme.danger : (color ?? appTheme.ink))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(L(title)).font(.subheadline.weight(.medium)).foregroundStyle(destructive ? appTheme.danger : appTheme.ink)
                if let subtitle { Text(L(subtitle)).font(.subheadline).foregroundStyle(appTheme.ink2).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: Theme.space2)
            if let value { Text(L(value)).font(.subheadline).foregroundStyle(appTheme.ink2).fixedSize(horizontal: false, vertical: true) }
        }
        .frame(minHeight: Theme.rowMinHeight)
        .contentShape(Rectangle())
    }
}

/// 行间发丝线
struct RowDivider: View {
    @Environment(\.appTheme) private var appTheme
    var inset: CGFloat = 0
    var body: some View {
        Rectangle().fill(appTheme.line).frame(height: Theme.hairline).padding(.leading, inset)
    }
}

/// 历史线条组件现在只绘制中性分隔线。
struct InkRule: View {
    @Environment(\.appTheme) private var appTheme
    var height: CGFloat = Theme.rule
    var color: Color? = nil
    var body: some View { Rectangle().fill(color ?? appTheme.line).frame(height: min(height, Theme.hairline)).accessibilityHidden(true) }
}

/// 刊物栏目标题：左侧陶土微章标记 + 宋体标题 + 延伸细墨线。
struct SectionTitle: View {
    @Environment(\.appTheme) private var appTheme
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
        HStack(alignment: .firstTextBaseline, spacing: Theme.space2) {
            if let number {
                Text(number).mastheadStyle(color: appTheme.accent)
            } else {
                Rectangle().fill(appTheme.accent).frame(width: 3, height: 14)
                    .offset(y: 1).accessibilityHidden(true)
            }
            Text(L(text)).font(appTheme.display(20, relativeTo: .title3)).foregroundStyle(appTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let badge { SealBadge(text: badge) }
            if rule { Rectangle().fill(appTheme.line).frame(height: 1).accessibilityHidden(true) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

struct PageMasthead: View {
    @Environment(\.appTheme) private var appTheme
    let title: String
    var subtitle: String? = nil
    var rule = true
    /// 报头左右眉题，如 `TINGYE / LIBRARY` / `8 BOOKS`。
    var kicker: String? = nil
    var issue: String? = nil
    var titleSize: CGFloat = 34
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.space2) {
            if rule { Rectangle().fill(appTheme.line).frame(height: Theme.hairline).accessibilityHidden(true) }
            if kicker != nil || issue != nil || actionTitle != nil {
                HStack {
                    if let kicker {
                        HStack(spacing: 6) {
                            Rectangle().fill(appTheme.accent).frame(width: 8, height: 8).accessibilityHidden(true)
                            Text(L(kicker).localUppercased).foregroundStyle(appTheme.accent)
                        }
                    }
                    Spacer()
                    if let issue { Text(L(issue).localUppercased).foregroundStyle(appTheme.ink2) }
                    if let actionTitle, let action { TextButton(actionTitle, action: action) }
                }
                .mastheadStyle()
            }
            Text(L(title))
                .font(appTheme.display(titleSize))
                .lineSpacing(titleSize * 0.16)
                .minimumScaleFactor(min(1, 24 / titleSize))
                .foregroundStyle(appTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: Theme.iconButtonSize, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            if let subtitle, !subtitle.isEmpty {
                Text(L(subtitle))
                    .font(Theme.sans(13))
                    .foregroundStyle(appTheme.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ProgressBar: View {
    @Environment(\.appTheme) private var appTheme
    var value: Double
    var track: Color? = nil
    var tint: Color? = nil
    var height: CGFloat = Theme.progressHeight
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(track ?? appTheme.surface2)
                Rectangle().fill(tint ?? appTheme.focus).frame(width: max(0, min(1, value)) * geo.size.width)
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel("进度")
        .accessibilityValue("\(Int((value * 100).rounded()))%")
    }
}

// MARK: - 书籍封面

/// 真实书封完整显示；占位封使用暖中性纸面与宋体 Regular。
struct BookCoverView: View {
    @Environment(\.appTheme) private var appTheme
    let title: String
    var color = "ink"
    var author = ""
    var image: UIImage? = nil
    var width: CGFloat = 98
    /// 书架网格中的 mono 序号（01、02…），nil 不显示。
    var index: Int? = nil
    init(title: String, color: String = "ink", author: String = "", data: Data? = nil, image: UIImage? = nil, width: CGFloat = 98, index: Int? = nil) {
        self.title = title; self.color = color; self.author = author; self.width = width
        self.image = image ?? data.flatMap(UIImage.init(data:))
        self.index = index
    }
    var body: some View {
        let fg = appTheme.ink
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFit().background(appTheme.surface2)
                    .transition(.opacity)
            } else if width < 52 {
                tinyPlaceholder(fg)
            } else {
                slipPlaceholder(fg)
            }
        }
        .animation(Theme.pressAnimation, value: image != nil)
        .respectReducedMotion()
        // 封面是固定比例的书籍图像；可缩放的完整书名由外部标题及无障碍标签提供。
        .dynamicTypeSize(.medium)
        .frame(width: width, height: width / 0.75)
        .accessibilityElement()
        .accessibilityLabel("《\(title)》封面")
    }
    private func coverTitleFont(_ size: CGFloat) -> Font {
        appTheme.usesSerifHeadings ? .custom(Theme.serifName, fixedSize: size) : .system(size: size, weight: .semibold)
    }

    private func tinyPlaceholder(_ fg: Color) -> some View {
        ZStack(alignment: .leading) {
            appTheme.coverColor(color)
            Text(L(title))
                .font(coverTitleFont(max(8, width * 0.17)))
                .foregroundStyle(fg)
                .lineLimit(3)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 4)
                .frame(width: width, height: width / 0.75, alignment: .center)
        }
    }
    private func slipPlaceholder(_ fg: Color) -> some View {
        let titleSize = min(24, max(11, width * 0.14))
        return ZStack(alignment: .leading) {
            appTheme.coverColor(color)
            Canvas { context, size in
                let band = CGRect(x: 0, y: size.height * 0.68, width: size.width, height: size.height * 0.32)
                context.fill(Path(band), with: .color(appTheme.onAccent))
                let inset = band.height * 0.19
                let line = CGRect(x: inset, y: band.minY + inset, width: band.width * 0.52, height: 2)
                switch appTheme {
                case .oat:
                    context.fill(Path(line), with: .color(appTheme.accent))
                case .moss, .night:
                    let diameter = band.height * 0.58
                    let circle = CGRect(x: band.maxX - diameter - inset, y: band.minY + inset,
                                        width: diameter, height: diameter)
                    context.fill(Path(ellipseIn: circle), with: .color(appTheme.accent))
                case .silver:
                    for row in 0..<3 {
                        context.fill(Path(line.offsetBy(dx: 0, dy: CGFloat(row) * 5)), with: .color(appTheme.accent))
                    }
                }
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(L(title))
                    .font(coverTitleFont(titleSize)).foregroundStyle(fg)
                    .lineLimit(width < 72 ? 2 : 3).minimumScaleFactor(0.72).multilineTextAlignment(.leading)
                if width >= 72 && !author.isEmpty {
                    Text(author).font(.system(size: max(8, width * 0.075)))
                        .foregroundStyle(fg).lineLimit(1)
                        .padding(.top, max(3, width * 0.04))
                }
            }
            .padding(.horizontal, max(5, width * 0.08))
            .frame(width: width, height: width / 0.75 * 0.68, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .top)
            if let index {
                Text(String(format: "%02d", index))
                    .font(Theme.sans(max(8, width * 0.075), weight: .semibold)).monospacedDigit()
                    .foregroundStyle(appTheme.accent)
                    .padding(.leading, width * 0.08)
                    .frame(height: width / 0.75 * 0.32)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .frame(width: width, height: width / 0.75)
    }
}

struct FlexibleCover: View {
    let title: String
    var color = "ink"
    var author = ""
    var image: UIImage?
    var index: Int? = nil
    var body: some View {
        Color.clear.aspectRatio(0.75, contentMode: .fit).overlay {
            GeometryReader { geo in BookCoverView(title: title, color: color, author: author, image: image, width: geo.size.width, index: index) }
        }
    }
}

/// 封面色块底：自带封面图时取平均色，否则用封面色板。用于详情与播放器的整块色头。
struct CoverBackdrop: View {
    @Environment(\.appTheme) private var appTheme
    let color: String
    var image: UIImage?
    var depth: CGFloat = 1
    @State private var average: UIColor?
    var body: some View {
        Group {
            if image != nil { Color(uiColor: average?.backgroundForWhiteText ?? UIColor(hex: 0x262626)) }
            else { appTheme.coverColor(color) }
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
    @Environment(\.appTheme) private var appTheme
    let text: String
    var body: some View {
        Label(text, systemImage: Icon.warning).font(.footnote).foregroundStyle(appTheme.danger)
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .leading) { Rectangle().fill(appTheme.danger).frame(width: 3) }
    }
}

enum Samples {
    static let books: [Book] = {
        guard let url = Bundle.main.url(forResource: "samples", withExtension: "json"), let data = try? Data(contentsOf: url), let books = try? JSONDecoder().decode([Book].self, from: data) else { return [] }
        return books
    }()
}

// MARK: - v31 共享组件

/// 可选顶部区域与内容共用唯一纸面入口，不承担导航或滚动行为。
struct PaperBackground<Header: View, Content: View>: View {
    @ViewBuilder var header: Header
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
            header
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .paperBackground()
    }
}

extension PaperBackground where Header == EmptyView {
    init(@ViewBuilder content: () -> Content) {
        self.header = EmptyView()
        self.content = content()
    }
}

typealias Masthead = PageMasthead
typealias PaperCard<Content: View> = Card<Content>
typealias ProgressLine = ProgressBar
typealias CoverView = BookCoverView

struct SectionHeader: View {
    @Environment(\.appTheme) private var appTheme
    let title: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.space2) {
            Rectangle().fill(appTheme.accent).frame(width: 3, height: 14)
                .offset(y: 1).accessibilityHidden(true)
            Text(L(title)).font(appTheme.display(20, relativeTo: .title3))
                .foregroundStyle(appTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Theme.space2)
            if let actionTitle, let action { TextButton(actionTitle, action: action) }
        }
    }
}

/// 通用无卡壳行；内容可用 HStack 组合图文，也可用现有 EditorialRow。
struct HairlineRow<Content: View>: View {
    var showsDivider = true
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) {
            content.frame(maxWidth: .infinity, minHeight: Theme.rowMinHeight, alignment: .leading)
            if showsDivider { RowDivider().accessibilityHidden(true) }
        }
    }
}

extension HairlineRow where Content == EditorialRow {
    init(title: String, detail: String? = nil, value: String? = nil,
         symbol: String? = nil, disclosure: Bool = false, showsDivider: Bool = true) {
        self.showsDivider = showsDivider
        self.content = EditorialRow(title: title, detail: detail, value: value,
                                    symbol: symbol, disclosure: disclosure)
    }
}

struct PrimaryButton: View {
    let title: String
    let action: () -> Void
    init(_ title: String, action: @escaping () -> Void) { self.title = title; self.action = action }
    var body: some View {
        Button(action: action) { Text(L(title)) }.buttonStyle(PrimaryButtonStyle())
    }
}

/// 调用方负责每屏至多一处陶土按钮；组件不修改动作或决定业务状态。
struct ClayButton: View {
    @Environment(\.appTheme) private var appTheme
    let title: String
    let action: () -> Void
    private var symbol: String? = nil
    private var loading = false
    init(_ title: String, action: @escaping () -> Void) { self.title = title; self.action = action }
    init(systemName: String, label: String, loading: Bool = false, action: @escaping () -> Void) {
        title = label; self.action = action; symbol = systemName; self.loading = loading
    }
    var body: some View {
        if let symbol {
            Button(action: action) {
                ZStack {
                    RoundedRectangle(cornerRadius: appTheme.transportRadius).fill(appTheme.accent)
                    if loading { ProgressView().tint(appTheme.onAccent) }
                    else { ThemeIcon(symbol: symbol, size: 28).foregroundStyle(appTheme.onAccent) }
                }
                .frame(width: Theme.space7 + Theme.space5, height: Theme.space7 + Theme.space5)
                .contentShape(RoundedRectangle(cornerRadius: appTheme.transportRadius))
            }
            .buttonStyle(PressButtonStyle()).accessibilityLabel(L(title))
        } else {
            Button(action: action) { Text(L(title)) }
                .buttonStyle(PrimaryButtonStyle(fill: appTheme.accent, foreground: appTheme.onAccent))
        }
    }
}

struct SecondaryButton: View {
    let title: String
    let action: () -> Void
    init(_ title: String, action: @escaping () -> Void) { self.title = title; self.action = action }
    var body: some View {
        Button(action: action) { Text(L(title)) }.buttonStyle(SecondaryButtonStyle())
    }
}

struct TextButtonStyle: ButtonStyle {
    @Environment(\.appTheme) private var appTheme
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(Theme.sans(15)).foregroundStyle(appTheme.accent)
            .frame(minHeight: Theme.iconButtonSize)
            .contentShape(Rectangle())
            .modifier(PressFeedback(pressed: configuration.isPressed))
            .opacity(isEnabled ? 1 : Theme.disabledOpacity)
    }
}

struct TextButton: View {
    let title: String
    let action: () -> Void
    init(_ title: String, action: @escaping () -> Void) { self.title = title; self.action = action }
    var body: some View {
        Button(action: action) { Text(L(title)) }.buttonStyle(TextButtonStyle())
    }
}

struct Chip: View {
    let title: String
    var selected = false
    let action: () -> Void
    var body: some View {
        Button(action: action) { Text(L(title)) }.buttonStyle(ChipPillStyle(selected: selected))
    }
}

/// 只将点击交给调用方；不内置选择、路由或持久化策略。
struct SegmentedBar<Option: Hashable>: View {
    @Environment(\.appTheme) private var appTheme
    let options: [Option]
    let selection: Option
    let title: (Option) -> String
    let onSelect: (Option) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: Theme.space1))
            : AnyLayout(HStackLayout(spacing: Theme.space1))
        layout {
            ForEach(options, id: \.self) { option in
                Button { onSelect(option) } label: {
                    HStack(spacing: Theme.space1) {
                        if option == selection {
                            Image(systemName: Icon.checkmark).accessibilityHidden(true)
                        }
                        Text(L(title(option))).fixedSize(horizontal: false, vertical: true)
                    }
                    .font(Theme.sans(13)).foregroundStyle(appTheme.ink)
                    .padding(.horizontal, Theme.space2)
                    .frame(maxWidth: .infinity, minHeight: Theme.iconButtonSize)
                    .background(option == selection ? appTheme.surface : .clear,
                                in: RoundedRectangle(cornerRadius: appTheme.radiusSmall))
                    .overlay {
                        if option == selection {
                            RoundedRectangle(cornerRadius: appTheme.radiusSmall)
                                .strokeBorder(appTheme.line, lineWidth: Theme.rule)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressButtonStyle())
                .accessibilityAddTraits(option == selection ? .isSelected : [])
            }
        }
        .padding(Theme.space1)
        .background(appTheme.surface2, in: RoundedRectangle(cornerRadius: appTheme.radiusField))
    }
}

struct SealDot: View {
    @Environment(\.appTheme) private var appTheme
    let text: String
    var body: some View {
        HStack(spacing: Theme.space1) {
            Circle().fill(appTheme.accent).frame(width: Theme.sealDotSize, height: Theme.sealDotSize)
                .accessibilityHidden(true)
            Text(L(text)).font(Theme.sans(11)).foregroundStyle(appTheme.accent)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct SheetTopShape: Shape {
    let radius: CGFloat
    func path(in rect: CGRect) -> Path {
        Path(UIBezierPath(roundedRect: rect, byRoundingCorners: [.topLeft, .topRight],
                          cornerRadii: CGSize(width: radius, height: radius)).cgPath)
    }
}

struct SheetChrome<Content: View>: View {
    @Environment(\.appTheme) private var appTheme
    let title: String
    var closeLabel = "关闭"
    let onClose: () -> Void
    var showsHeader = true
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: Theme.space4) {
            Capsule().fill(appTheme.line).frame(width: Theme.space6, height: Theme.space1)
                .accessibilityHidden(true)
            if showsHeader { HStack(spacing: Theme.space3) {
                Text(L(title)).font(appTheme.display(20, relativeTo: .title3)).foregroundStyle(appTheme.ink)
                    .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
                Spacer(minLength: Theme.space2)
                CircleIconButton(systemName: Icon.close, label: L(closeLabel), action: onClose)
            } }
            content
        }
        .padding(Theme.cardInset)
        .background(appTheme.surface, in: SheetTopShape(radius: appTheme.heroRadius))
        .overlay { SheetTopShape(radius: appTheme.heroRadius).stroke(appTheme.line, lineWidth: Theme.hairline).allowsHitTesting(false) }
        .clipShape(SheetTopShape(radius: appTheme.heroRadius))
        .modifier(FloatingPanelShadow())
    }
}

/// 空态、加载、错误沿用同一标题/说明语言；所有文案与重试动作由调用方传入。
struct EmptyState: View {
    @Environment(\.appTheme) private var appTheme
    enum State: Equatable { case empty, loading, error, success }
    let title: String
    let detail: String
    var state: State = .empty
    var badge: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var body: some View {
        VStack(spacing: Theme.space4) {
            if state == .loading { ProgressView().tint(appTheme.ink2) }
            if let badge {
                SealBadge(text: badge, color: state == .error ? appTheme.danger : appTheme.accent,
                          background: state == .error ? appTheme.dangerSoft : appTheme.accentSoft)
            }
            if state == .error {
                Image(systemName: Icon.warning).foregroundStyle(appTheme.danger).accessibilityHidden(true)
            }
            Text(L(title)).font(Theme.serif(22, relativeTo: .title2)).foregroundStyle(appTheme.ink)
                .padding(state == .error ? Theme.space2 : 0)
                .background(state == .error ? appTheme.dangerSoft : .clear,
                            in: RoundedRectangle(cornerRadius: appTheme.radiusSmall))
                .accessibilityAddTraits(.isHeader)
            Text(L(detail)).font(Theme.sans(14)).foregroundStyle(appTheme.ink3)
            if let actionTitle, let action { PrimaryButton(actionTitle, action: action) }
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
        .padding(Theme.cardInset)
    }
}

struct StatBlock: View {
    @Environment(\.appTheme) private var appTheme
    let value: String
    let label: String
    var size: CGFloat = 30
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.space2) {
            Text(value).font(appTheme.display(size)).monospacedDigit().foregroundStyle(appTheme.ink)
            Text(L(label)).mastheadStyle()
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 阅读纸色

enum ReaderPaper: String, CaseIterable, Identifiable {
    // 已保存的键继续指向最接近的纸色；white 对应陶土暖白。
    case paper, ancient, mist, sky, eink, blue, night, white

    static let storageKey = "reader.paper"
    static let alwaysLightKey = "study.paperAlwaysLight"
    static let defaultPaper: Self = .paper

    init(storedValue: String) { self = Self(rawValue: storedValue) ?? Self.defaultPaper }
    var id: String { rawValue }

    var name: String {
        switch self {
        case .paper: "米宣"
        case .ancient: "麦笺"
        case .mist: "松雾"
        case .sky: "云蓝"
        case .eink: "灰陶"
        case .blue: "海墨"
        case .night: "烛夜"
        case .white: "陶土纸"
        }
    }

    struct Palette: Equatable {
        let background: UInt32
        let foreground: UInt32
        let secondary: UInt32
        let highlight: UInt32
        let accent: UInt32
        let isDark: Bool
    }

    var dark: Bool { self == .blue || self == .night }

    /// 原生正文和 Readium 使用相同的纸面、文字与跟读颜色。
    func resolve(darkAppearance: Bool, alwaysLight: Bool) -> Palette {
        let isDark = dark || (darkAppearance && !alwaysLight)
        let values: (background: UInt32, foreground: UInt32, secondary: UInt32, highlight: UInt32, accent: UInt32) =
            switch (self, isDark) {
            case (.paper, false): (0xFBF6E9, 0x30271F, 0x665849, 0xEFE2CB, 0x94553D)
            case (.paper, true): (0x27231D, 0xF1E9D8, 0xC9BCA8, 0x493B2C, 0xE7AF90)
            case (.ancient, false): (0xF2E5CA, 0x372C20, 0x695640, 0xE5D1AB, 0x8C4D32)
            case (.ancient, true): (0x30271C, 0xF4E6C9, 0xD1BC98, 0x51412A, 0xEBAB82)
            case (.mist, false): (0xE3EEE4, 0x20362B, 0x4A6351, 0xCBDDCB, 0x386648)
            case (.mist, true): (0x222F28, 0xE2EFE6, 0xADC8B4, 0x374E3E, 0xA8D4AF)
            case (.sky, false): (0xE4ECF7, 0x25364A, 0x50637C, 0xCDDDF2, 0x405E92)
            case (.sky, true): (0x222D3E, 0xE5EEF9, 0xB3C4DF, 0x344968, 0xAFC9F5)
            case (.eink, false): (0xEAE7E3, 0x302D2C, 0x625958, 0xDCD6D3, 0x76534D)
            case (.eink, true): (0x292726, 0xEEE9E7, 0xC8BDB8, 0x443B38, 0xE3B2A9)
            case (.blue, _): (0x192A3A, 0xDAE7F3, 0xA1B6CB, 0x2D445D, 0x9DC1EC)
            case (.night, _): (0x201C19, 0xEADCCB, 0xC1AC97, 0x453326, 0xEFAD80)
            case (.white, false): (0xFAF9F5, 0x141413, 0x615B51, 0xF4DED3, 0xA6482B)
            case (.white, true): (0x26221F, 0xF4EEE7, 0xC8BDB0, 0x49342B, 0xEFA283)
            }
        return Palette(background: values.background, foreground: values.foreground, secondary: values.secondary,
                       highlight: values.highlight, accent: values.accent, isDark: isDark)
    }

    func uiColor(_ key: KeyPath<Palette, UInt32>) -> UIColor {
        UIColor { traits in
            let palette = resolve(darkAppearance: traits.userInterfaceStyle == .dark,
                                  alwaysLight: UserDefaults.standard.bool(forKey: Self.alwaysLightKey))
            return UIColor(hex: palette[keyPath: key])
        }
    }

    func color(_ key: KeyPath<Palette, UInt32>) -> Color {
        Color(uiColor: uiColor(key))
    }

    static let xuan = defaultPaper.color(\.background)
}

struct ReaderPreferences: Equatable {
    var fontSize: Double = 19
    var lineSpacing: Double = 11
    var font = "system"
    var paper = ReaderPaper.defaultPaper.rawValue
    var scrolling = false
    var paragraphSpacing: Double = 15
    var margin: Double = 24
    var indent = true
    var justified = true
    /// 字间距（pt）
    var letterSpacing: Double = 0
    /// 简繁转换：none / s2t（简→繁）/ t2s（繁→简）
    var convert = "none"
    var resolvedPaper: ReaderPaper.Palette? = nil
    var kind: ReaderPaper { ReaderPaper(storedValue: paper) }
    var background: Color { paperColor(\.background) }
    var foreground: Color { paperColor(\.foreground) }
    var secondary: Color { paperColor(\.secondary) }
    var accent: Color { paperColor(\.accent) }
    var highlight: UIColor { paperUIColor(\.highlight) }

    private func paperColor(_ key: KeyPath<ReaderPaper.Palette, UInt32>) -> Color {
        Color(uiColor: paperUIColor(key))
    }

    private func paperUIColor(_ key: KeyPath<ReaderPaper.Palette, UInt32>) -> UIColor {
        if let resolvedPaper { return UIColor(hex: resolvedPaper[keyPath: key]) }
        return kind.uiColor(key)
    }
    /// serif 思源宋体 / kai 霞鹜文楷 / hansans 思源黑体 / xixihei 霞鹜新晰黑 / system 系统字体 / custom:<PostScript 名> 导入的字体
    var uiFont: UIFont {
        if font == "system" { return .systemFont(ofSize: fontSize) }
        if font.hasPrefix("custom:") { return UIFont(name: String(font.dropFirst(7)), size: fontSize) ?? .systemFont(ofSize: fontSize) }
        return UIFont(name: ReaderPreferences.bundledFonts[font] ?? Theme.serifName, size: fontSize) ?? .systemFont(ofSize: fontSize)
    }
    /// 内置阅读字体键 → PostScript 名；字体文件随包携带，在 Info.plist 的 UIAppFonts 注册。
    static let bundledFonts: [String: String] = [
        "serif": "NotoSerifCJKsc-Regular",
        "kai": "LXGWWenKaiLite-Regular",
        "hansans": "NotoSansCJKsc-Regular",
        "xixihei": "LXGWNeoXiHei",
    ]
}

extension String {
    /// 眉题大写：ASCII 直接大写，中文原样（避免整串被 .uppercase 处理出意外）
    var localUppercased: String { self.map { $0.isASCII ? Character($0.uppercased()) : $0 }.reduce(into: "") { $0.append($1) } }
}

/// 既有 Icon 枚举提供符号映射，ThemeIcon 统一渲染 regular SF Symbols。
struct ThemeIcon: View {
    let symbol: String
    var size: CGFloat = 20
    /// 兼容旧参数；v31 符号线宽统一 regular。
    var weight: Font.Weight = .regular
    var body: some View {
        Image(systemName: symbol)
            .font(Theme.sans(size, weight: .regular))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}


// MARK: - Editorial interface components (never applied to publication DOM or text layout)

/// Shared introduction inside the scroll content: large text can scroll out of the way.
struct EditorialIntro: View {
    @Environment(\.appTheme) private var appTheme
    let title: String
    var detail: String? = nil
    var eyebrow: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.space2) {
            Rectangle().fill(appTheme.line).frame(height: Theme.hairline).accessibilityHidden(true)
            if let eyebrow {
                HStack(spacing: 6) {
                    Rectangle().fill(appTheme.accent).frame(width: 7, height: 7).accessibilityHidden(true)
                    Text(L(eyebrow).localUppercased).mastheadStyle(color: appTheme.accent).foregroundStyle(appTheme.accent)
                }
            }
            Text(L(title)).font(Theme.serif(28, relativeTo: .title)).foregroundStyle(appTheme.ink)
                .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
            if let detail {
                Text(L(detail)).font(Theme.sans(13)).foregroundStyle(appTheme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Rectangle().fill(appTheme.line).frame(height: 1).padding(.top, 6).accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
}

/// An adaptive navigation/action row; content stays readable rather than truncating values.
struct EditorialRow: View {
    @Environment(\.appTheme) private var appTheme
    let title: String
    var detail: String? = nil
    var value: String? = nil
    var symbol: String? = nil
    var disclosure = true
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        HStack(alignment: .center, spacing: Theme.space3) {
            if let symbol {
                ThemeIcon(symbol: symbol, size: 20).foregroundStyle(appTheme.ink2)
                    .frame(width: 28).accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: Theme.space1) {
                Text(L(title)).font(Theme.sans(16)).foregroundStyle(appTheme.ink)
                if let detail { Text(L(detail)).font(Theme.sans(13)).foregroundStyle(appTheme.ink2) }
                if typeSize.isAccessibilitySize, let value {
                    Text(L(value)).font(Theme.sans(13)).foregroundStyle(appTheme.accent)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            if !typeSize.isAccessibilitySize, let value {
                Text(L(value)).font(Theme.sans(13)).foregroundStyle(appTheme.ink2)
                    .fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.trailing)
            }
            if disclosure { ThemeIcon(symbol: Icon.disclosure, size: 13).foregroundStyle(appTheme.ink4) }
        }
        .padding(.vertical, Theme.space2).frame(minHeight: Theme.rowMinHeight).contentShape(Rectangle())
    }
}

struct PaperPanel: ViewModifier {
    @Environment(\.appTheme) private var appTheme
    var inset: CGFloat = Theme.cardInset
    @Environment(\.colorSchemeContrast) private var contrast
    func body(content: Content) -> some View {
        content.padding(inset).frame(maxWidth: .infinity, alignment: .leading)
            .background(appTheme.surface, in: RoundedRectangle(cornerRadius: appTheme.radius))
            .overlay { RoundedRectangle(cornerRadius: appTheme.radius).strokeBorder(appTheme.line, lineWidth: contrast == .increased ? Theme.ruleMedium : Theme.rule) }
            .softCardShadow()
    }
}

/// Status is conveyed with symbol + title + explanation, never color alone.
struct EditorialNotice: View {
    @Environment(\.appTheme) private var appTheme
    enum Kind: Equatable { case information, working, success, failure }
    let title: String
    var detail: String? = nil
    var kind: Kind = .information
    private var symbol: String {
        switch kind { case .information: "info.circle"; case .working: "clock"; case .success: "checkmark.circle"; case .failure: "exclamationmark.triangle" }
    }
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if kind == .working { ProgressView().padding(.top, 2) }
            else { Image(systemName: symbol).foregroundStyle(kind == .failure ? appTheme.danger : appTheme.accent).accessibilityHidden(true) }
            VStack(alignment: .leading, spacing: 6) {
                Text(L(title)).font(.subheadline.weight(.semibold))
                if let detail { Text(L(detail)).font(.subheadline).foregroundStyle(appTheme.ink2).textSelection(.enabled) }
            }.fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(appTheme.ink).modifier(PaperPanel())
        .accessibilityElement(children: .combine)
    }
}

extension View {
    func paperPanel(inset: CGFloat = Theme.cardInset) -> some View { modifier(PaperPanel(inset: inset)) }
    /// Consistent native list rhythm used by deeper settings and source browsers.
    func editorialList() -> some View { modifier(ThemedList()) }
}

private struct ThemedList: ViewModifier {
    @Environment(\.appTheme) private var appTheme

    func body(content: Content) -> some View {
        content.listStyle(.insetGrouped).listSectionSpacing(22)
            .scrollContentBackground(.hidden).background(appTheme.bg).tint(appTheme.accent)
            .toolbarBackground(appTheme.bg, for: .navigationBar)
            .environment(\.defaultMinListRowHeight, Theme.rowMinHeight)
    }
}
