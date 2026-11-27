import SwiftUI
import UIKit
import CoreImage

/// 四向可切换界面主题系统（默认暖纸）。正文七种阅读纸色（ReaderPaper）保持独立。
enum AppThemeDirection: String, CaseIterable, Identifiable, Sendable {
    case warmPaper      // 暖纸 Anthropic
    case nightInkGold   // 夜读墨金
    case editorial      // 杂志编辑
    case systemClear    // 清透系统

    static let storageKey = "app.uiDirection"

    var id: String { rawValue }

    static var current: AppThemeDirection {
        guard let raw = UserDefaults.standard.string(forKey: storageKey),
              let value = AppThemeDirection(rawValue: raw) else {
            return .warmPaper
        }
        return value
    }

    var title: String {
        switch self {
        case .warmPaper: return "暖纸"
        case .nightInkGold: return "夜读墨金"
        case .editorial: return "杂志编辑"
        case .systemClear: return "清透系统"
        }
    }

    var subtitle: String {
        switch self {
        case .warmPaper: return "象牙暖纸与陶土点缀，柔和留白"
        case .nightInkGold: return "沉静暖墨与青铜暖金，适合长夜阅读"
        case .editorial: return "硬朗微圆角、宽边距与鲜明报刊层级"
        case .systemClear: return "原生系统材料与清晰文字层级，极简克制"
        }
    }

    var accessibilityID: String { "theme.\(rawValue)" }
}

private struct ThemeDirectionEnvironmentKey: EnvironmentKey {
    static let defaultValue: AppThemeDirection = .warmPaper
}

extension EnvironmentValues {
    var themeDirection: AppThemeDirection {
        get { self[ThemeDirectionEnvironmentKey.self] }
        set { self[ThemeDirectionEnvironmentKey.self] = newValue }
    }
}

/// 不依赖全局状态的色板查询，供当前主题与外观页四向独立预览共用。
struct ThemePalette {
    let direction: AppThemeDirection
    let bg: Color
    let surface: Color
    let surface2: Color
    let surfaceSunken: Color
    let ink: Color
    let ink2: Color
    let ink3: Color
    let ink4: Color
    let line: Color
    let lineField: Color
    let accent: Color
    let accentSoft: Color
    let clay: Color
    let onClay: Color
    let danger: Color
    let dangerSoft: Color
    let shadowBase: Color

    var clayDeep: Color { accent }
    var claySoft: Color { accentSoft }
    var focus: Color { clay }
    var onInk: Color { bg }
    var onAccent: Color { bg }
    var marker: Color { clay }
    var onMarker: Color { onClay }
    var readingHighlight: Color { accentSoft }
    var hero: Color { accentSoft }
    var heroInk: Color { ink }

    func coverUIColor(_ color: String) -> UIColor {
        switch direction {
        case .warmPaper:
            switch color {
            case "red", "vermilion": return UIColor(hex: 0xF2DFD5)
            case "gold", "cream": return UIColor(hex: 0xEFE6D2)
            case "green": return UIColor(hex: 0xDEE6DE)
            case "blue", "purple": return UIColor(hex: 0xDFE4EC)
            default: return UIColor(hex: 0xECE9E0)
            }
        case .nightInkGold:
            switch color {
            case "red", "vermilion": return UIColor(hex: 0xEEDBD0)
            case "gold", "cream": return UIColor(hex: 0xEFE3C6)
            case "green": return UIColor(hex: 0xDCE3DA)
            case "blue", "purple": return UIColor(hex: 0xDEE2E8)
            default: return UIColor(hex: 0xEAE2D2)
            }
        case .editorial:
            switch color {
            case "red", "vermilion": return UIColor(hex: 0xEFE0DD)
            case "gold", "cream": return UIColor(hex: 0xECE5D5)
            case "green": return UIColor(hex: 0xDFE4DE)
            case "blue", "purple": return UIColor(hex: 0xE0E3E8)
            default: return UIColor(hex: 0xE6E2D8)
            }
        case .systemClear:
            switch color {
            case "red", "vermilion": return UIColor(hex: 0xF5E4E1)
            case "gold", "cream": return UIColor(hex: 0xF4ECD8)
            case "green": return UIColor(hex: 0xE3EFE7)
            case "blue", "purple": return UIColor(hex: 0xE4ECF7)
            default: return UIColor(hex: 0xEAECEF)
            }
        }
    }

    var coverForegroundHex: UInt32 {
        switch direction {
        case .warmPaper: return 0x141413
        case .nightInkGold: return 0x1A1712
        case .editorial: return 0x1C1B19
        case .systemClear: return 0x1C1C1E
        }
    }

    func coverForeground(_ color: String) -> Color {
        Color(hex: coverForegroundHex)
    }

    static func palette(for direction: AppThemeDirection) -> ThemePalette {
        switch direction {
        case .warmPaper:
            return ThemePalette(
                direction: .warmPaper,
                bg: dynamicHex(0xFAF9F5, 0x141413),
                surface: dynamicHex(0xFFFFFF, 0x1C1B19),
                surface2: dynamicHex(0xF0EEE6, 0x262522),
                surfaceSunken: dynamicHex(0xF3F1E9, 0x181715),
                ink: dynamicHex(0x141413, 0xFAF9F5),
                ink2: dynamicHex(0x3D3D3A, 0xD5D3CA),
                ink3: dynamicHex(0x595853, 0xABA89E),
                ink4: dynamicHex(0x87867F, 0x78756C),
                line: dynamicHex(0xE6E3D9, 0x2E2C29),
                lineField: dynamicField(0x141413, 0xFAF9F5),
                accent: dynamicHex(0xA6482B, 0xECA085),
                accentSoft: dynamicHex(0xF8ECE6, 0x2E201B),
                clay: dynamicHex(0xD97757, 0xD97757),
                onClay: dynamicHex(0x141413, 0x141413),
                danger: dynamicHex(0x9E2A2B, 0xF4A6A3),
                dangerSoft: dynamicHex(0xF9EAE8, 0x362020),
                shadowBase: dynamicHex(0x141413, 0x000000)
            )
        case .nightInkGold:
            return ThemePalette(
                direction: .nightInkGold,
                bg: dynamicHex(0xF4EFE4, 0x12110E),
                surface: dynamicHex(0xFFFBF3, 0x1C1A16),
                surface2: dynamicHex(0xEAE3D4, 0x26231E),
                surfaceSunken: dynamicHex(0xEDE7DA, 0x0E0D0B),
                ink: dynamicHex(0x1A1712, 0xF3EDE0),
                ink2: dynamicHex(0x3F3A32, 0xD4CCB8),
                ink3: dynamicHex(0x5C564C, 0xA89F8A),
                ink4: dynamicHex(0x7A7368, 0x7A7364),
                line: dynamicHex(0xDDD6C7, 0x3A362E),
                lineField: dynamicField(0x1A1712, 0xF3EDE0),
                accent: dynamicHex(0x7A5C16, 0xE8CC7A),
                accentSoft: dynamicHex(0xF3E6C4, 0x2A2418),
                clay: dynamicHex(0xC4A24A, 0xC4A24A),
                onClay: dynamicHex(0x1A1712, 0x12110E),
                danger: dynamicHex(0x9E2A2B, 0xF4A6A3),
                dangerSoft: dynamicHex(0xF9EAE8, 0x362020),
                shadowBase: dynamicHex(0x1A1712, 0x000000)
            )
        case .editorial:
            // 深色 clay 采用 0xC65E58（较 0xC45C56 微调 +2 RGB），确保配 0x141311 达到严格 WCAG AA ≥ 4.5:1（4.55:1）。
            return ThemePalette(
                direction: .editorial,
                bg: dynamicHex(0xF3F0E8, 0x141311),
                surface: dynamicHex(0xFFFDF8, 0x1E1D1A),
                surface2: dynamicHex(0xE8E4DA, 0x2A2925),
                surfaceSunken: dynamicHex(0xECE9E1, 0x10100E),
                ink: dynamicHex(0x1C1B19, 0xF4F0E6),
                ink2: dynamicHex(0x3A3935, 0xD4D0C4),
                ink3: dynamicHex(0x5A5852, 0xA8A49A),
                ink4: dynamicHex(0x7A7872, 0x7C786E),
                line: dynamicHex(0xD4D0C6, 0x3A3832),
                lineField: dynamicField(0x1C1B19, 0xF4F0E6),
                accent: dynamicHex(0x8F2D2A, 0xE8A09A),
                accentSoft: dynamicHex(0xF3E6E4, 0x2E1C1B),
                clay: dynamicHex(0x8F2D2A, 0xC65E58),
                onClay: dynamicHex(0xFFFDF8, 0x141311),
                danger: dynamicHex(0x9E2A2B, 0xF4A6A3),
                dangerSoft: dynamicHex(0xF9EAE8, 0x362020),
                shadowBase: dynamicHex(0x1C1B19, 0x000000)
            )
        case .systemClear:
            return ThemePalette(
                direction: .systemClear,
                bg: Color(uiColor: .systemBackground),
                surface: Color(uiColor: .secondarySystemBackground),
                surface2: Color(uiColor: .tertiarySystemBackground),
                surfaceSunken: Color(uiColor: .systemGroupedBackground),
                ink: Color(uiColor: .label),
                ink2: Color(uiColor: .secondaryLabel),
                ink3: dynamicHex(0x3A3A3C, 0xC7C7CC),
                ink4: Color(uiColor: .tertiaryLabel),
                line: Color(uiColor: .separator),
                lineField: Color(UIColor { traits in
                    UIColor.label.resolvedColor(with: traits)
                        .withAlphaComponent(traits.userInterfaceStyle == .dark ? 0.16 : 0.14)
                }),
                accent: dynamicHex(0x0B63CE, 0x64D2FF),
                accentSoft: dynamicHex(0xE8F1FC, 0x1A2A3D),
                clay: dynamicHex(0x0B63CE, 0x0A6CE2),
                onClay: dynamicHex(0xFFFFFF, 0xFFFFFF),
                danger: dynamicHex(0xD70015, 0xFF6961),
                dangerSoft: dynamicHex(0xFDECEC, 0x3A1C1C),
                shadowBase: dynamicHex(0x000000, 0x000000)
            )
        }
    }

    fileprivate static func dynamicHex(_ light: UInt32, _ dark: UInt32, highLight: UInt32? = nil, highDark: UInt32? = nil) -> Color {
        Color(UIColor { traits in
            let night = traits.userInterfaceStyle == .dark
            let value = traits.accessibilityContrast == .high
                ? (night ? highDark ?? dark : highLight ?? light) : (night ? dark : light)
            return UIColor(hex: value)
        })
    }

    fileprivate static func dynamicField(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(UIColor { traits in
            let night = traits.userInterfaceStyle == .dark
            return UIColor(hex: night ? dark : light).withAlphaComponent(night ? 0.16 : 0.14)
        })
    }
}

/// 不依赖全局状态的尺度与材料策略查询。
struct ThemeMetrics {
    let direction: AppThemeDirection
    let radius: CGFloat
    let heroRadius: CGFloat
    let buttonRadius: CGFloat
    let radiusField: CGFloat
    let radiusSmall: CGFloat
    let radiusPill: CGFloat
    let buttonRadiusSmall: CGFloat
    let inset: CGFloat
    let insetCompact: CGFloat
    let cardInset: CGFloat
    let sectionSpacing: CGFloat
    let hairline: CGFloat
    let rule: CGFloat
    let ruleMedium: CGFloat
    let ruleHeavy: CGFloat
    let progressHeight: CGFloat
    let mastheadTracking: CGFloat
    let usesMaterialChrome: Bool
    let usesSerifInterfaceTitles: Bool
    let headingScale: CGFloat
    let cardShadowRadius: CGFloat
    let cardShadowX: CGFloat
    let cardShadowY: CGFloat
    let cardShadowLightOpacity: Double
    let cardShadowDarkOpacity: Double
    let floatingShadowRadius: CGFloat
    let floatingShadowY: CGFloat
    let floatingShadowLightOpacity: Double
    let floatingShadowDarkOpacity: Double

    func coverRadius(_ width: CGFloat) -> CGFloat {
        switch direction {
        case .warmPaper: return min(10, max(4, width * 0.07))
        case .nightInkGold: return min(8, max(3, width * 0.05))
        case .editorial: return min(4, max(2, width * 0.03))
        case .systemClear: return min(12, max(6, width * 0.08))
        }
    }

    static func metrics(for direction: AppThemeDirection) -> ThemeMetrics {
        let pixel = 1.0 / max(1.0, UIScreen.main.scale)
        switch direction {
        case .warmPaper:
            return ThemeMetrics(
                direction: .warmPaper,
                radius: 18, heroRadius: 26, buttonRadius: 14, radiusField: 14,
                radiusSmall: 8, radiusPill: 999, buttonRadiusSmall: 10,
                inset: 24, insetCompact: 20, cardInset: 22, sectionSpacing: 32,
                hairline: 0.5, rule: 0.75, ruleMedium: 1.5, ruleHeavy: 2.5,
                progressHeight: 3.5, mastheadTracking: 1.4,
                usesMaterialChrome: false, usesSerifInterfaceTitles: true, headingScale: 1.0,
                cardShadowRadius: 18, cardShadowX: 0, cardShadowY: 5,
                cardShadowLightOpacity: 0.05, cardShadowDarkOpacity: 0.0,
                floatingShadowRadius: 22, floatingShadowY: 8,
                floatingShadowLightOpacity: 0.12, floatingShadowDarkOpacity: 0.48
            )
        case .nightInkGold:
            return ThemeMetrics(
                direction: .nightInkGold,
                radius: 12, heroRadius: 18, buttonRadius: 10, radiusField: 10,
                radiusSmall: 6, radiusPill: 999, buttonRadiusSmall: 8,
                inset: 24, insetCompact: 20, cardInset: 20, sectionSpacing: 32,
                hairline: 0.5, rule: 0.75, ruleMedium: 1.25, ruleHeavy: 2.0,
                progressHeight: 3.0, mastheadTracking: 1.6,
                usesMaterialChrome: false, usesSerifInterfaceTitles: true, headingScale: 1.0,
                cardShadowRadius: 12, cardShadowX: 0, cardShadowY: 4,
                cardShadowLightOpacity: 0.06, cardShadowDarkOpacity: 0.20,
                floatingShadowRadius: 16, floatingShadowY: 6,
                floatingShadowLightOpacity: 0.12, floatingShadowDarkOpacity: 0.45
            )
        case .editorial:
            return ThemeMetrics(
                direction: .editorial,
                radius: 4, heroRadius: 6, buttonRadius: 3, radiusField: 3,
                radiusSmall: 2, radiusPill: 4, buttonRadiusSmall: 3,
                inset: 32, insetCompact: 24, cardInset: 24, sectionSpacing: 40,
                hairline: 0.75, rule: 1.0, ruleMedium: 2.0, ruleHeavy: 3.0,
                progressHeight: 3.0, mastheadTracking: 2.8,
                usesMaterialChrome: false, usesSerifInterfaceTitles: true, headingScale: 1.08,
                cardShadowRadius: 0, cardShadowX: 2, cardShadowY: 2,
                cardShadowLightOpacity: 0.06, cardShadowDarkOpacity: 0.24,
                floatingShadowRadius: 0, floatingShadowY: 4,
                floatingShadowLightOpacity: 0.12, floatingShadowDarkOpacity: 0.42
            )
        case .systemClear:
            return ThemeMetrics(
                direction: .systemClear,
                radius: 12, heroRadius: 16, buttonRadius: 10, radiusField: 10,
                radiusSmall: 8, radiusPill: 999, buttonRadiusSmall: 8,
                inset: 20, insetCompact: 16, cardInset: 16, sectionSpacing: 24,
                hairline: pixel, rule: pixel, ruleMedium: 1.0, ruleHeavy: 2.0,
                progressHeight: 4.0, mastheadTracking: 0.4,
                usesMaterialChrome: true, usesSerifInterfaceTitles: false, headingScale: 0.94,
                cardShadowRadius: 8, cardShadowX: 0, cardShadowY: 2,
                cardShadowLightOpacity: 0.03, cardShadowDarkOpacity: 0.0,
                floatingShadowRadius: 16, floatingShadowY: 6,
                floatingShadowLightOpacity: 0.08, floatingShadowDarkOpacity: 0.36
            )
        }
    }
}

enum Theme {
    static var currentPalette: ThemePalette { ThemePalette.palette(for: AppThemeDirection.current) }
    static var currentMetrics: ThemeMetrics { ThemeMetrics.metrics(for: AppThemeDirection.current) }

    static var bg: Color { currentPalette.bg }
    static var surface: Color { currentPalette.surface }
    static var surface2: Color { currentPalette.surface2 }
    static var surfaceSunken: Color { currentPalette.surfaceSunken }
    static var ink: Color { currentPalette.ink }
    static var ink2: Color { currentPalette.ink2 }
    static var ink3: Color { currentPalette.ink3 }
    static var ink4: Color { currentPalette.ink4 }
    static var line: Color { currentPalette.line }
    static var lineField: Color { currentPalette.lineField }
    static var accent: Color { currentPalette.accent }
    static var clayDeep: Color { currentPalette.clayDeep }
    static var accentSoft: Color { currentPalette.accentSoft }
    static var claySoft: Color { currentPalette.claySoft }
    static var clay: Color { currentPalette.clay }
    static var onClay: Color { currentPalette.onClay }
    static var focus: Color { currentPalette.focus }
    static var danger: Color { currentPalette.danger }
    static var dangerSoft: Color { currentPalette.dangerSoft }

    // 语义别名：全部映射到当前色板，不残留任何硬编码色。
    static var rulePaint: Color { ink }
    static var cardEdge: Color { line }
    static var onInk: Color { currentPalette.onInk }
    static var onAccent: Color { currentPalette.onAccent }
    static var link: Color { accent }
    static var marker: Color { clay }
    static var onMarker: Color { onClay }
    static var readingHighlight: Color { accentSoft }
    static var hero: Color { accentSoft }
    static var heroInk: Color { ink }
    static var forest: Color { accent }
    static var onForest: Color { onAccent }
    static var wash: Color { accentSoft }
    static var warm: Color { surface2 }
    static var onWarm: Color { ink2 }
    static var gold: Color { onWarm }
    static var goldSoft: Color { warm }
    static var jade: Color { accent }
    static var jadeSoft: Color { accentSoft }
    static var indigo: Color { accent }
    static var indigoSoft: Color { accentSoft }
    static var ochre: Color { gold }
    static var plum: Color { accent }
    static var amberOnDark: Color { clay }

    static var auroraGradient: LinearGradient { LinearGradient(colors: [accent, accent], startPoint: .top, endPoint: .bottom) }
    static var accentGradient: LinearGradient { auroraGradient }
    static var heroGradient: LinearGradient { LinearGradient(colors: [hero, hero], startPoint: .top, endPoint: .bottom) }
    static var heroButtonInk: Color { ink }

    static let space1: CGFloat = 4
    static let space2: CGFloat = 8
    static let space3: CGFloat = 12
    static let space4: CGFloat = 16
    static let space5: CGFloat = 24
    static let space6: CGFloat = 32
    static let space7: CGFloat = 48
    static var inset: CGFloat { currentMetrics.inset }
    static var insetCompact: CGFloat { currentMetrics.insetCompact }
    static var cardInset: CGFloat { currentMetrics.cardInset }
    static let rowMinHeight: CGFloat = 52
    static var sectionSpacing: CGFloat { currentMetrics.sectionSpacing }
    static let pageWidth: CGFloat = 720
    static var radius: CGFloat { currentMetrics.radius }
    static var heroRadius: CGFloat { currentMetrics.heroRadius }
    static var buttonRadius: CGFloat { currentMetrics.buttonRadius }
    static var radiusField: CGFloat { currentMetrics.radiusField }
    static var radiusSmall: CGFloat { currentMetrics.radiusSmall }
    static var radiusPill: CGFloat { currentMetrics.radiusPill }
    static var buttonRadiusSmall: CGFloat { currentMetrics.buttonRadiusSmall }
    static func coverRadius(_ width: CGFloat) -> CGFloat { currentMetrics.coverRadius(width) }
    static let buttonHeight: CGFloat = 50
    static let iconButtonSize: CGFloat = 44
    static var hairline: CGFloat { currentMetrics.hairline }
    static var progressHeight: CGFloat { currentMetrics.progressHeight }
    static let sealDotSize: CGFloat = 6
    static var mastheadTracking: CGFloat { currentMetrics.mastheadTracking }
    static let pressedOpacity = 0.88
    static let disabledOpacity = 0.4
    static var ruleHeavy: CGFloat { currentMetrics.ruleHeavy }
    static var ruleMedium: CGFloat { currentMetrics.ruleMedium }
    static var rule: CGFloat { currentMetrics.rule }

    // MARK: - 动效

    static let pressSpring = Animation.spring(response: 0.32, dampingFraction: 0.86)
    static let pressAnimation = Animation.easeOut(duration: 0.2)
    static let smoothSpring = pressSpring

    // MARK: - 字体：书名与摘句用宋体；清透系统下界面标题用系统文字层级，杂志编辑下放大标题级差

    static let serifName = "NotoSerifCJKsc-Regular"
    static func serif(_ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(serifName, size: size, relativeTo: style)
    }
    /// 保留签名兼容调用点，与 serif 相同。
    static func serifSemibold(_ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        serif(size, relativeTo: style)
    }
    /// 同 serifSemibold，不再合成粗体；层级靠字号、留白与发丝线建立。
    static func serifBold(_ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        serif(size, relativeTo: style)
    }
    /// 界面标题：清透系统使用系统字体层级；其余三套使用宋体，且杂志编辑略放大标题级差。
    static func heading(_ size: CGFloat, relativeTo style: Font.TextStyle = .title3, weight: Font.Weight = .semibold) -> Font {
        let m = currentMetrics
        if !m.usesSerifInterfaceTitles {
            return .system(size: (size * m.headingScale).rounded(), weight: weight)
        }
        return serif((size * m.headingScale).rounded(), relativeTo: style)
    }
    /// 界面字体：系统字体（真实字重、与 SF Symbols 基线对齐）。固定字号，不再随 relativeTo 缩放。
    static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
    /// Font 不承载 tracking；配合 .mastheadStyle() 应用完整眉题样式。
    static var masthead: Font {
        switch AppThemeDirection.current {
        case .systemClear: return .system(size: 12, weight: .medium)
        case .editorial: return .system(size: 11.5, weight: .semibold)
        case .warmPaper, .nightInkGold: return .system(size: 12, weight: .semibold)
        }
    }
    /// 统计大数字：清透系统采用系统字体，其余方向沿用宋体 Regular；调用方配合 monospacedDigit()。
    static func display(_ size: CGFloat, relativeTo style: Font.TextStyle = .largeTitle) -> Font {
        let m = currentMetrics
        if !m.usesSerifInterfaceTitles {
            return .system(size: (size * m.headingScale).rounded(), weight: .semibold)
        }
        return serif((size * m.headingScale).rounded(), relativeTo: style)
    }
    /// 栏目标签（同 masthead）。
    static var kicker: Font { masthead }
    /// 页面标题。
    static func headline(_ size: CGFloat) -> Font { heading(size, relativeTo: .title) }

    // MARK: - 无图书籍的低饱和封面（真实书封始终优先）

    static func coverColor(_ color: String) -> Color { Color(uiColor: coverUIColor(color)) }
    static func coverUIColor(_ color: String) -> UIColor { currentPalette.coverUIColor(color) }
    static func coverForeground(_ color: String) -> Color { currentPalette.coverForeground(color) }

    /// 纯色色块（保留渐变签名，便于沿用调用处）。
    static func coverGradient(_ color: String) -> LinearGradient {
        LinearGradient(colors: [coverColor(color), coverColor(color)], startPoint: .top, endPoint: .bottom)
    }
    static func coverGradient(_ base: UIColor, depth: CGFloat = 1) -> LinearGradient {
        let c = Color(uiColor: base.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light)))
        return LinearGradient(colors: [c, c], startPoint: .top, endPoint: .bottom)
    }

    // MARK: - UIKit 导航栏、工具栏与标签栏外观同步

    @MainActor static func applyUIKitAppearance(for direction: AppThemeDirection = .current) {
        let palette = ThemePalette.palette(for: direction)
        let navStandard = UINavigationBarAppearance()
        let navScrollEdge = UINavigationBarAppearance()
        let toolbarAppearance = UIToolbarAppearance()
        let tabAppearance = UITabBarAppearance()

        if direction == .systemClear {
            navStandard.configureWithDefaultBackground()
            navStandard.backgroundEffect = UIBlurEffect(style: .systemChromeMaterial)
            navStandard.titleTextAttributes = [.foregroundColor: UIColor.label]
            navStandard.largeTitleTextAttributes = [.foregroundColor: UIColor.label]

            navScrollEdge.configureWithTransparentBackground()
            navScrollEdge.titleTextAttributes = [.foregroundColor: UIColor.label]
            navScrollEdge.largeTitleTextAttributes = [.foregroundColor: UIColor.label]

            toolbarAppearance.configureWithDefaultBackground()
            tabAppearance.configureWithDefaultBackground()
        } else {
            let bgColor = UIColor(palette.bg)
            let inkColor = UIColor(palette.ink)
            let lineColor = direction == .editorial ? UIColor(palette.line) : UIColor(palette.line).withAlphaComponent(0.65)

            navStandard.configureWithOpaqueBackground()
            navStandard.backgroundColor = bgColor
            navStandard.shadowColor = lineColor
            navStandard.titleTextAttributes = [.foregroundColor: inkColor]
            navStandard.largeTitleTextAttributes = [.foregroundColor: inkColor]

            navScrollEdge.configureWithOpaqueBackground()
            navScrollEdge.backgroundColor = bgColor
            navScrollEdge.shadowColor = direction == .editorial ? lineColor : .clear
            navScrollEdge.titleTextAttributes = [.foregroundColor: inkColor]
            navScrollEdge.largeTitleTextAttributes = [.foregroundColor: inkColor]

            toolbarAppearance.configureWithOpaqueBackground()
            toolbarAppearance.backgroundColor = bgColor
            toolbarAppearance.shadowColor = lineColor

            tabAppearance.configureWithOpaqueBackground()
            tabAppearance.backgroundColor = UIColor(palette.surface)
            tabAppearance.shadowColor = lineColor
        }

        UINavigationBar.appearance().standardAppearance = navStandard
        UINavigationBar.appearance().scrollEdgeAppearance = navScrollEdge
        UINavigationBar.appearance().compactAppearance = navStandard
        UIToolbar.appearance().standardAppearance = toolbarAppearance
        UIToolbar.appearance().scrollEdgeAppearance = toolbarAppearance
        UIToolbar.appearance().compactAppearance = toolbarAppearance
        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance

        let tint = UIColor(palette.clayDeep)
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows {
                window.tintColor = tint
                refreshControllerBars(window.rootViewController, navStandard: navStandard, navScrollEdge: navScrollEdge, toolbar: toolbarAppearance, tab: tabAppearance, tint: tint)
            }
        }
    }

    @MainActor private static func refreshControllerBars(
        _ controller: UIViewController?,
        navStandard: UINavigationBarAppearance,
        navScrollEdge: UINavigationBarAppearance,
        toolbar: UIToolbarAppearance,
        tab: UITabBarAppearance,
        tint: UIColor
    ) {
        guard let controller else { return }
        if let nav = controller as? UINavigationController {
            nav.navigationBar.standardAppearance = navStandard
            nav.navigationBar.scrollEdgeAppearance = navScrollEdge
            nav.navigationBar.compactAppearance = navStandard
            nav.navigationBar.tintColor = tint
            nav.navigationBar.setNeedsLayout()
            nav.toolbar.standardAppearance = toolbar
            nav.toolbar.scrollEdgeAppearance = toolbar
            nav.toolbar.compactAppearance = toolbar
            nav.toolbar.tintColor = tint
        }
        if let tabController = controller as? UITabBarController {
            tabController.tabBar.standardAppearance = tab
            tabController.tabBar.scrollEdgeAppearance = tab
            tabController.tabBar.tintColor = tint
            tabController.tabBar.setNeedsLayout()
        }
        for child in controller.children {
            refreshControllerBars(child, navStandard: navStandard, navScrollEdge: navScrollEdge, toolbar: toolbar, tab: tab, tint: tint)
        }
        if let presented = controller.presentedViewController {
            refreshControllerBars(presented, navStandard: navStandard, navScrollEdge: navScrollEdge, toolbar: toolbar, tab: tab, tint: tint)
        }
    }
}

// MARK: - 层次：纸面画布、系统材料与安静的内容表面

private struct GlassSurfaceModifier: ViewModifier {
    @Environment(\.themeDirection) private var direction
    let shape: AnyShape
    let interactive: Bool
    func body(content: Content) -> some View {
        let active = AppThemeDirection.current
        let _ = direction
        if active == .systemClear {
            content.background(interactive ? AnyShapeStyle(.thinMaterial) : AnyShapeStyle(.regularMaterial), in: shape)
        } else {
            content.background(Theme.surface, in: shape)
        }
    }
}

private struct GlassCardModifier: ViewModifier {
    @Environment(\.themeDirection) private var direction
    let cornerRadius: CGFloat?
    func body(content: Content) -> some View {
        let _ = direction
        let r = cornerRadius ?? Theme.radius
        let shape = RoundedRectangle(cornerRadius: r, style: .continuous)
        content
            .background(Theme.surface, in: shape)
            .overlay {
                shape.strokeBorder(
                    AppThemeDirection.current == .systemClear ? Theme.line.opacity(0.45) : Theme.line,
                    lineWidth: Theme.rule
                )
            }
    }
}

private struct FloatingPanelModifier: ViewModifier {
    @Environment(\.themeDirection) private var direction
    let cornerRadius: CGFloat?
    func body(content: Content) -> some View {
        let _ = direction
        let r = cornerRadius ?? Theme.radius
        let shape = RoundedRectangle(cornerRadius: r, style: .continuous)
        if AppThemeDirection.current == .systemClear {
            content
                .background(.regularMaterial, in: shape)
                .overlay { shape.strokeBorder(Theme.line.opacity(0.35), lineWidth: Theme.hairline) }
                .modifier(FloatingPanelShadow())
        } else {
            content
                .background(Theme.surface, in: shape)
                .overlay { shape.strokeBorder(Theme.line, lineWidth: Theme.rule) }
                .modifier(FloatingPanelShadow())
        }
    }
}

private struct PaperBackgroundModifier: ViewModifier {
    @Environment(\.themeDirection) private var direction
    func body(content: Content) -> some View {
        let _ = direction
        content.background { Theme.bg.ignoresSafeArea() }
    }
}

extension View {
    /// 完整眉题样式：字号与字距必须一起应用。
    func mastheadStyle(color: Color = Theme.ink3) -> some View {
        font(Theme.masthead).tracking(Theme.mastheadTracking).foregroundStyle(color)
    }
    /// 自定义系统字号也跟随 Dynamic Type；不要用固定字号再缩小文字来掩盖溢出。
    func scaledFont(_ size: CGFloat, weight: Font.Weight = .regular, width: Font.Width = .standard, relativeTo style: Font.TextStyle = .body) -> some View {
        modifier(ScaledSystemFont(size: size, weight: weight, width: width, style: style))
    }
    func respectReducedMotion() -> some View { modifier(ReducedMotionPolicy()) }
    func glassSurface(in shape: AnyShape, interactive: Bool = false) -> some View {
        modifier(GlassSurfaceModifier(shape: shape, interactive: interactive))
    }

    func glassCard(cornerRadius: CGFloat? = nil, interactive: Bool = false) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius))
    }

    /// 瑞士分栏：上方发丝线，内容直接落在纸面上。
    func columnRule(_ height: CGFloat = 1) -> some View {
        self.overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: min(height, Theme.rule)).accessibilityHidden(true) }
            .padding(.top, 0)
    }

    func softCardShadow() -> some View { modifier(SoftCardShadow()) }

    func floatingPanel(cornerRadius: CGFloat? = nil) -> some View {
        modifier(FloatingPanelModifier(cornerRadius: cornerRadius))
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

    /// 保留为空操作，兼容既有调用点。
    func serifEmbolden(_ size: CGFloat) -> some View { self }
    func serifHeavy(_ size: CGFloat) -> some View { self }

    func paperBackground() -> some View {
        modifier(PaperBackgroundModifier())
    }

    /// 跟读：强调淡底与实底竖条共同标记当前句，不只依赖颜色。
    func markerHighlight() -> some View {
        self
            .foregroundStyle(Theme.ink)
            .padding(.leading, 20).padding(.trailing, 16)
            .padding(.vertical, 16)
            .background(Theme.readingHighlight)
            .overlay(alignment: .leading) {
                Rectangle().fill(Theme.clay)
                    .frame(width: 4)
                    .accessibilityHidden(true)
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

/// 卡片阴影随当前方向的尺度与色板变化：暖纸柔和扩散，夜读克制沉静，杂志短促硬朗，清透极轻。
struct SoftCardShadow: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.themeDirection) private var direction
    func body(content: Content) -> some View {
        let _ = direction
        let p = Theme.currentPalette
        let m = Theme.currentMetrics
        let opacity = colorScheme == .dark ? m.cardShadowDarkOpacity : m.cardShadowLightOpacity
        if opacity <= 0 {
            content
        } else {
            content.shadow(color: p.shadowBase.opacity(opacity), radius: m.cardShadowRadius, x: m.cardShadowX, y: m.cardShadowY)
        }
    }
}

private struct FloatingPanelShadow: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.themeDirection) private var direction
    func body(content: Content) -> some View {
        let _ = direction
        let p = Theme.currentPalette
        let m = Theme.currentMetrics
        let opacity = colorScheme == .dark ? m.floatingShadowDarkOpacity : m.floatingShadowLightOpacity
        content.shadow(color: p.shadowBase.opacity(opacity), radius: m.floatingShadowRadius, x: 0, y: m.floatingShadowY)
    }
}

// MARK: - 状态标签组件

struct SealBadge: View {
    @Environment(\.themeDirection) private var direction
    let text: String
    var color: Color? = nil
    var background: Color? = nil
    var filled: Bool = false
    var body: some View {
        let _ = direction
        let clear = AppThemeDirection.current == .systemClear
        let fg = color ?? (filled ? Theme.onClay : Theme.accent)
        let bg = background ?? (filled ? Theme.clay : Theme.accentSoft)
        Text(L(text))
            .font(Theme.sans(11, weight: clear ? .medium : .semibold))
            .foregroundStyle(fg)
            .padding(.horizontal, Theme.space2)
            .padding(.vertical, clear ? 3 : Theme.space1)
            .background(bg, in: RoundedRectangle(cornerRadius: Theme.radiusPill, style: .continuous))
    }
}

// MARK: - 按钮（统一消费 Theme.clay / Theme.onClay 与当前方向圆角尺度）

/// 主按钮采用当前方向的主动作实底（clay + onClay）。
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.themeDirection) private var direction
    var height: CGFloat? = nil
    var fill: Color? = nil
    var foreground: Color? = nil
    func makeBody(configuration: Configuration) -> some View {
        let _ = direction
        let resolvedHeight = height ?? Theme.buttonHeight
        let resolvedFill = fill ?? Theme.clay
        let resolvedForeground = foreground ?? Theme.onClay
        let r = Theme.buttonRadius
        configuration.label
            .font(Theme.sans(15, weight: .semibold))
            .fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(.center)
            .padding(.horizontal, Theme.space4).padding(.vertical, Theme.space3)
            .frame(maxWidth: .infinity, minHeight: resolvedHeight)
            .foregroundStyle(resolvedForeground)
            .background(resolvedFill, in: RoundedRectangle(cornerRadius: r, style: .continuous))
            .overlay {
                if AppThemeDirection.current != .systemClear {
                    RoundedRectangle(cornerRadius: r, style: .continuous)
                        .strokeBorder(Theme.onClay.opacity(0.10), lineWidth: Theme.hairline)
                }
            }
            .modifier(PressFeedback(pressed: configuration.isPressed))
            .contentShape(RoundedRectangle(cornerRadius: r, style: .continuous))
            .opacity(isEnabled ? 1 : Theme.disabledOpacity)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.themeDirection) private var direction
    var height: CGFloat? = nil
    var emphasized = false
    func makeBody(configuration: Configuration) -> some View {
        let _ = direction
        let resolvedHeight = height ?? Theme.buttonHeight
        let r = Theme.buttonRadius
        configuration.label
            .font(Theme.sans(15, weight: .medium))
            .fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(.center)
            .padding(.horizontal, Theme.space4).padding(.vertical, Theme.space3)
            .frame(maxWidth: .infinity, minHeight: resolvedHeight)
            .foregroundStyle(emphasized ? Theme.accent : Theme.ink)
            .background(emphasized ? Theme.accentSoft : Theme.surface, in: RoundedRectangle(cornerRadius: r, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: r, style: .continuous)
                    .strokeBorder(emphasized ? Theme.clay : Theme.line, lineWidth: Theme.rule)
            }
            .modifier(PressFeedback(pressed: configuration.isPressed))
            .contentShape(RoundedRectangle(cornerRadius: r, style: .continuous))
            .opacity(isEnabled ? 1 : Theme.disabledOpacity)
    }
}

/// 历史签名兼容壳，避免给内容重复添加表面。
struct GlassSkin: ViewModifier {
    var interactive = false
    var shape: AnyShape = AnyShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    func body(content: Content) -> some View { content }
}

/// 筛选签：圆角随当前方向变化，勾号提供非颜色状态通道。
struct ChipPillStyle: ButtonStyle {
    var selected: Bool
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.themeDirection) private var direction
    func makeBody(configuration: Configuration) -> some View {
        let _ = direction
        let shape = RoundedRectangle(cornerRadius: Theme.buttonRadius, style: .continuous)
        HStack(spacing: Theme.space1) {
            if selected { Image(systemName: Icon.checkmark).font(.system(size: 12, weight: .bold)).accessibilityHidden(true) }
            configuration.label
        }
        .font(Theme.sans(14, weight: selected ? .semibold : .regular))
        .foregroundStyle(selected ? Theme.onInk : Theme.ink)
        .padding(.horizontal, Theme.space3)
        .frame(minHeight: Theme.iconButtonSize)
        .background(selected ? Theme.ink : Theme.surface, in: shape)
        .overlay { shape.strokeBorder(selected ? Theme.ink : Theme.line, lineWidth: Theme.rule) }
        .contentShape(shape)
        .modifier(PressFeedback(pressed: configuration.isPressed))
        .opacity(isEnabled ? 1 : Theme.disabledOpacity)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// 无底无描边图标按钮，命中区至少 44pt。
struct CircleIconButton: View {
    @Environment(\.themeDirection) private var direction
    let systemName: String
    let label: String
    var size: CGFloat = Theme.iconButtonSize
    let action: () -> Void
    var body: some View {
        let _ = direction
        Button(action: action) {
            ThemeIcon(symbol: systemName, size: 20)
                .frame(width: size, height: size)
                .foregroundStyle(Theme.ink2)
                .frame(minWidth: Theme.iconButtonSize, minHeight: Theme.iconButtonSize)
                .contentShape(RoundedRectangle(cornerRadius: Theme.radius))
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

/// scale 参数仅保留源码兼容；按压只改变透明度。
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

/// 内容卡片，内边距与圆角随当前方向切换。
struct Card<Content: View>: View {
    @Environment(\.themeDirection) private var direction
    var padding: CGFloat? = nil
    @ViewBuilder var content: Content
    var body: some View {
        let _ = direction
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(padding ?? Theme.cardInset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard().softCardShadow()
    }
}

/// 设置项图标：墨色线性图标。
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
    @Environment(\.themeDirection) private var direction
    var icon: String? = nil
    var color: Color? = nil
    let title: String
    var value: String? = nil
    var subtitle: String? = nil
    var destructive = false
    var body: some View {
        let _ = direction
        HStack(spacing: Theme.space3) {
            if let icon {
                SettingsIcon(systemName: icon, color: destructive ? Theme.danger : (color ?? Theme.ink))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(L(title)).font(.subheadline.weight(.medium)).foregroundStyle(destructive ? Theme.danger : Theme.ink)
                if let subtitle { Text(L(subtitle)).font(.subheadline).foregroundStyle(Theme.ink2).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: Theme.space2)
            if let value { Text(L(value)).font(.subheadline).foregroundStyle(Theme.ink2).fixedSize(horizontal: false, vertical: true) }
        }
        .frame(minHeight: Theme.rowMinHeight)
        .contentShape(Rectangle())
    }
}

/// 行间发丝线
struct RowDivider: View {
    @Environment(\.themeDirection) private var direction
    var inset: CGFloat = 0
    var body: some View {
        let _ = direction
        Rectangle().fill(Theme.line).frame(height: Theme.hairline).padding(.leading, inset)
    }
}

/// 中性分隔线，在清透系统下保持极细极淡。
struct InkRule: View {
    @Environment(\.themeDirection) private var direction
    var height: CGFloat? = nil
    var color: Color? = nil
    var body: some View {
        let _ = direction
        let clear = AppThemeDirection.current == .systemClear
        let resolvedColor = color ?? (clear ? Theme.line.opacity(0.55) : Theme.line)
        let resolvedHeight = clear ? Theme.hairline : min(height ?? Theme.rule, Theme.ruleMedium)
        Rectangle().fill(resolvedColor).frame(height: resolvedHeight).accessibilityHidden(true)
    }
}

/// 栏目标题：清透系统收起多余装饰并使用系统文字层级；其余三套保留左侧强调竖标与宋体层级。
struct SectionTitle: View {
    @Environment(\.themeDirection) private var direction
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
        let _ = direction
        let clear = AppThemeDirection.current == .systemClear
        HStack(alignment: .firstTextBaseline, spacing: Theme.space2) {
            if let number {
                Text(number).mastheadStyle(color: Theme.accent)
            } else if !clear {
                Rectangle().fill(Theme.clay).frame(width: Theme.ruleHeavy, height: 14)
                    .offset(y: 1).accessibilityHidden(true)
            }
            Text(L(text)).font(Theme.heading(20, relativeTo: .title3)).foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let badge { SealBadge(text: badge) }
            if rule && !clear {
                Rectangle().fill(Theme.line).frame(height: Theme.rule).accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// 页面报头：随当前方向切换栏线力度、眉题字距与标题字体策略。
struct PageMasthead: View {
    @Environment(\.themeDirection) private var direction
    let title: String
    var subtitle: String? = nil
    var rule = true
    var kicker: String? = nil
    var issue: String? = nil
    var titleSize: CGFloat = 34
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var body: some View {
        let _ = direction
        let active = AppThemeDirection.current
        VStack(alignment: .leading, spacing: Theme.space2) {
            if rule && active != .systemClear {
                Rectangle()
                    .fill(active == .editorial ? Theme.ink : Theme.line)
                    .frame(height: active == .editorial ? Theme.ruleMedium : Theme.rule)
                    .accessibilityHidden(true)
            }
            if kicker != nil || issue != nil || actionTitle != nil {
                HStack {
                    if let kicker {
                        HStack(spacing: 6) {
                            if active != .systemClear {
                                Rectangle().fill(Theme.clay).frame(width: 7, height: 7).accessibilityHidden(true)
                            }
                            Text(active == .systemClear ? L(kicker) : L(kicker).localUppercased)
                                .foregroundStyle(Theme.accent)
                        }
                    }
                    Spacer()
                    if let issue { Text(L(issue).localUppercased).foregroundStyle(Theme.ink2) }
                    if let actionTitle, let action { TextButton(actionTitle, action: action) }
                }
                .mastheadStyle()
            }
            Text(L(title))
                .font(Theme.heading(titleSize, relativeTo: .largeTitle, weight: .bold))
                .lineSpacing(titleSize * 0.14)
                .minimumScaleFactor(min(1, 24 / titleSize))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: Theme.iconButtonSize, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            if let subtitle, !subtitle.isEmpty {
                Text(L(subtitle))
                    .font(Theme.sans(13))
                    .foregroundStyle(Theme.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ProgressBar: View {
    @Environment(\.themeDirection) private var direction
    var value: Double
    var track: Color? = nil
    var tint: Color? = nil
    var height: CGFloat? = nil
    var body: some View {
        let _ = direction
        let resolvedTrack = track ?? Theme.surface2
        let resolvedTint = tint ?? Theme.focus
        let resolvedHeight = height ?? Theme.progressHeight
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(resolvedTrack)
                Rectangle().fill(resolvedTint).frame(width: max(0, min(1, value)) * geo.size.width)
            }
        }
        .frame(height: resolvedHeight)
        .clipShape(RoundedRectangle(cornerRadius: resolvedHeight / 2, style: .continuous))
        .accessibilityElement()
        .accessibilityLabel("进度")
        .accessibilityValue("\(Int((value * 100).rounded()))%")
    }
}

// MARK: - 书籍封面

/// 真实书封完整显示；占位封使用当前方向低饱和纸面与宋体书名，圆角随 coverRadius 变化。
struct BookCoverView: View {
    @Environment(\.themeDirection) private var direction
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
        let _ = direction
        let fg = Theme.coverForeground(color)
        let corner = Theme.coverRadius(width)
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFit().background(Theme.surface2)
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
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(Theme.line.opacity(0.6), lineWidth: Theme.hairline)
        }
        .accessibilityElement()
        .accessibilityLabel("《\(title)》封面")
    }
    private func tinyPlaceholder(_ fg: Color) -> some View {
        ZStack(alignment: .leading) {
            Theme.coverColor(color)
            Text(L(title))
                .font(Theme.serifBold(max(8, width * 0.17))).serifEmbolden(max(8, width * 0.17))
                .foregroundStyle(fg)
                .lineLimit(3)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 4)
                .frame(width: width, height: width / 0.75, alignment: .center)
        }
    }
    private func slipPlaceholder(_ fg: Color) -> some View {
        let titleSize = min(24, max(11, width * 0.14))
        let height = width / 0.75
        return ZStack(alignment: .topLeading) {
            Theme.coverColor(color)
            // 装帧书脊压线，安静克制，不喧宾夺主。
            Rectangle()
                .fill(fg.opacity(0.12))
                .frame(width: 1, height: height)
                .padding(.leading, max(5, width * 0.07))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Rectangle()
                    .fill(Theme.clay)
                    .frame(width: max(14, width * 0.22), height: 2)
                    .padding(.bottom, max(6, width * 0.07))
                    .accessibilityHidden(true)
                Text(L(title))
                    .font(Theme.serifBold(titleSize)).foregroundStyle(fg).serifEmbolden(titleSize)
                    .lineLimit(width < 72 ? 2 : 3).minimumScaleFactor(0.72).multilineTextAlignment(.leading)
                if width >= 72 && !author.isEmpty {
                    Text(author).font(.system(size: max(8, width * 0.075)))
                        .foregroundStyle(fg.opacity(0.82)).lineLimit(1)
                        .padding(.top, max(3, width * 0.04))
                }
                Spacer(minLength: 0)
                if let index {
                    Text(String(format: "%02d", index))
                        .font(Theme.sans(max(8, width * 0.075), weight: .semibold)).monospacedDigit()
                        .foregroundStyle(fg.opacity(0.72))
                }
            }
            .padding(.leading, max(9, width * 0.13))
            .padding(.trailing, max(6, width * 0.08))
            .padding(.vertical, max(8, width * 0.10))
            .frame(width: width, height: height, alignment: .topLeading)
        }
        .frame(width: width, height: height)
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
    let color: String
    var image: UIImage?
    var depth: CGFloat = 1
    @State private var average: UIColor?
    var body: some View {
        Group {
            if image != nil { Color(uiColor: average?.backgroundForWhiteText ?? UIColor(hex: 0x262626)) }
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
    @Environment(\.themeDirection) private var direction
    let text: String
    var body: some View {
        let _ = direction
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

// MARK: - 共享布局组件

/// 可选顶部区域与内容共用唯一纸面入口，不承担导航或滚动行为。
struct PaperBackground<Header: View, Content: View>: View {
    @Environment(\.themeDirection) private var direction
    @ViewBuilder var header: Header
    @ViewBuilder var content: Content
    var body: some View {
        let _ = direction
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
    @Environment(\.themeDirection) private var direction
    let title: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var body: some View {
        let _ = direction
        let clear = AppThemeDirection.current == .systemClear
        HStack(alignment: .firstTextBaseline, spacing: Theme.space2) {
            if !clear {
                Rectangle().fill(Theme.clay).frame(width: Theme.ruleHeavy, height: 14)
                    .offset(y: 1).accessibilityHidden(true)
            }
            Text(L(title)).font(Theme.heading(20, relativeTo: .title3))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Theme.space2)
            if let actionTitle, let action { TextButton(actionTitle, action: action) }
        }
    }
}

/// 通用无卡壳行；内容可用 HStack 组合图文，也可用现有 EditorialRow。
struct HairlineRow<Content: View>: View {
    @Environment(\.themeDirection) private var direction
    var showsDivider = true
    @ViewBuilder var content: Content
    var body: some View {
        let _ = direction
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

/// 调用方负责每屏至多一处主动作实底按钮；组件消费当前方向的 clay / onClay。
struct ClayButton: View {
    @Environment(\.themeDirection) private var direction
    let title: String
    let action: () -> Void
    private var symbol: String? = nil
    private var loading = false
    init(_ title: String, action: @escaping () -> Void) { self.title = title; self.action = action }
    init(systemName: String, label: String, loading: Bool = false, action: @escaping () -> Void) {
        title = label; self.action = action; symbol = systemName; self.loading = loading
    }
    var body: some View {
        let _ = direction
        if let symbol {
            Button(action: action) {
                ZStack {
                    Circle().fill(Theme.clay)
                    if loading { ProgressView().tint(Theme.onClay) }
                    else { ThemeIcon(symbol: symbol, size: 28).foregroundStyle(Theme.onClay) }
                }
                .frame(width: Theme.space7 + Theme.space5, height: Theme.space7 + Theme.space5)
                .contentShape(Circle())
            }
            .buttonStyle(PressButtonStyle()).accessibilityLabel(L(title))
        } else {
            Button(action: action) { Text(L(title)) }
                .buttonStyle(PrimaryButtonStyle(fill: Theme.clay, foreground: Theme.onClay))
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
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.themeDirection) private var direction
    func makeBody(configuration: Configuration) -> some View {
        let _ = direction
        configuration.label.font(Theme.sans(15)).foregroundStyle(Theme.accent)
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
    let options: [Option]
    let selection: Option
    let title: (Option) -> String
    let onSelect: (Option) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.themeDirection) private var direction
    var body: some View {
        let _ = direction
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
                    .font(Theme.sans(13, weight: option == selection ? .medium : .regular)).foregroundStyle(Theme.ink)
                    .padding(.horizontal, Theme.space2)
                    .frame(maxWidth: .infinity, minHeight: Theme.iconButtonSize)
                    .background(option == selection ? Theme.surface : .clear,
                                in: RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
                    .overlay {
                        if option == selection && AppThemeDirection.current != .systemClear {
                            RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                                .strokeBorder(Theme.line, lineWidth: Theme.rule)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressButtonStyle())
                .accessibilityAddTraits(option == selection ? .isSelected : [])
            }
        }
        .padding(Theme.space1)
        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: Theme.radiusField, style: .continuous))
    }
}

struct SealDot: View {
    @Environment(\.themeDirection) private var direction
    let text: String
    var body: some View {
        let _ = direction
        HStack(spacing: Theme.space1) {
            Circle().fill(Theme.clay).frame(width: Theme.sealDotSize, height: Theme.sealDotSize)
                .accessibilityHidden(true)
            Text(L(text)).font(Theme.sans(11)).foregroundStyle(Theme.accent)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct SheetTopShape: Shape {
    var radius: CGFloat
    func path(in rect: CGRect) -> Path {
        Path(UIBezierPath(roundedRect: rect, byRoundingCorners: [.topLeft, .topRight],
                          cornerRadii: CGSize(width: radius, height: radius)).cgPath)
    }
}

struct SheetChrome<Content: View>: View {
    @Environment(\.themeDirection) private var direction
    let title: String
    var closeLabel = "关闭"
    let onClose: () -> Void
    var showsHeader = true
    @ViewBuilder var content: Content
    var body: some View {
        let _ = direction
        let shape = SheetTopShape(radius: Theme.heroRadius)
        let clear = AppThemeDirection.current == .systemClear
        VStack(spacing: Theme.space4) {
            Capsule().fill(Theme.line).frame(width: Theme.space6, height: Theme.space1)
                .accessibilityHidden(true)
            if showsHeader { HStack(spacing: Theme.space3) {
                Text(L(title)).font(Theme.heading(20, relativeTo: .title3)).foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
                Spacer(minLength: Theme.space2)
                CircleIconButton(systemName: Icon.close, label: L(closeLabel), action: onClose)
            } }
            content
        }
        .padding(Theme.cardInset)
        .background(clear ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(Theme.surface), in: shape)
        .overlay {
            shape.stroke(clear ? Theme.line.opacity(0.35) : Theme.line, lineWidth: Theme.hairline)
                .allowsHitTesting(false)
        }
        .clipShape(shape)
        .modifier(FloatingPanelShadow())
    }
}

/// 空态、加载、错误沿用同一标题/说明语言；所有文案与重试动作由调用方传入。
struct EmptyState: View {
    @Environment(\.themeDirection) private var direction
    enum State: Equatable { case empty, loading, error, success }
    let title: String
    let detail: String
    var state: State = .empty
    var badge: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var body: some View {
        let _ = direction
        VStack(spacing: Theme.space4) {
            if state == .loading { ProgressView().tint(Theme.ink2) }
            if let badge {
                SealBadge(text: badge, color: state == .error ? Theme.danger : Theme.accent,
                          background: state == .error ? Theme.dangerSoft : Theme.accentSoft)
            }
            if state == .error {
                Image(systemName: Icon.warning).foregroundStyle(Theme.danger).accessibilityHidden(true)
            }
            Text(L(title)).font(Theme.heading(22, relativeTo: .title2)).foregroundStyle(Theme.ink)
                .padding(state == .error ? Theme.space2 : 0)
                .background(state == .error ? Theme.dangerSoft : .clear,
                            in: RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
                .accessibilityAddTraits(.isHeader)
            Text(L(detail)).font(Theme.sans(14)).foregroundStyle(Theme.ink3)
            if let actionTitle, let action { PrimaryButton(actionTitle, action: action) }
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
        .padding(Theme.cardInset)
    }
}

struct StatBlock: View {
    @Environment(\.themeDirection) private var direction
    let value: String
    let label: String
    var size: CGFloat = 30
    var body: some View {
        let _ = direction
        VStack(alignment: .leading, spacing: Theme.space2) {
            Text(value).font(Theme.display(size)).monospacedDigit().foregroundStyle(Theme.ink)
            Text(L(label)).mastheadStyle()
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 阅读偏好（七种中性阅读纸色）

enum ReaderPaper: String, CaseIterable, Identifiable {
    case paper, mist, ancient, eink, white, blue, night
    var id: String { rawValue }
    var name: String {
        ["paper": "默认", "mist": "雾灰", "ancient": "旧书", "eink": "浅灰", "white": "纯白", "blue": "深蓝", "night": "夜读"][rawValue] ?? rawValue
    }
    /// v31 §7：原生动态色和 Readium 快照共用同一决策。
    struct Palette: Equatable {
        let background: UInt32
        let foreground: UInt32
        let secondary: UInt32
        let isDark: Bool
        var highlight: UInt32 { isDark ? 0x2E201B : 0xF8ECE6 }
        var accent: UInt32 { isDark ? 0xECA085 : 0xA6482B }
    }
    func resolve(darkAppearance: Bool, alwaysLight: Bool) -> Palette {
        let night = darkAppearance && !alwaysLight
        let values: (UInt32, UInt32, UInt32)
        switch self {
        case .paper: values = night ? (0x131211, 0xF5F3EC, 0x9C988E) : (0xFAF9F5, 0x191817, 0x6B6960)
        case .mist: values = night ? (0x242522, 0xF5F3EC, 0x9C988E) : (0xECEDE8, 0x191817, 0x4A4741)
        case .ancient: values = night ? (0x29231D, 0xF5F3EC, 0x9C988E) : (0xF2ECE0, 0x191817, 0x4A4741)
        case .eink: values = night ? (0x1E1C1A, 0xF5F3EC, 0x9C988E) : (0xF1F0EB, 0x191817, 0x4A4741)
        case .white: values = night ? (0x131211, 0xF5F3EC, 0x9C988E) : (0xFFFFFF, 0x191817, 0x6B6960)
        case .blue: values = (0x242A2C, 0xF5F3EC, 0xC9C5BA)
        case .night: values = (0x131211, 0xF5F3EC, 0x9C988E)
        }
        return Palette(background: values.0, foreground: values.1, secondary: values.2, isDark: dark || night)
    }
    func color(_ key: KeyPath<Palette, UInt32>) -> Color {
        Color(UIColor { traits in
            UIColor(hex: self.resolve(darkAppearance: traits.userInterfaceStyle == .dark,
                                      alwaysLight: UserDefaults.standard.bool(forKey: "study.paperAlwaysLight"))[keyPath: key])
        })
    }
    var swatch: Color { color(\.background) }
    var dark: Bool { self == .blue || self == .night }
    /// 纸族动态色：随外观取日/夜成对值；「浅纸常亮」（study.paperAlwaysLight）开启时锁定日间值。
    static func paperColor(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(UIColor { traits in
            if UserDefaults.standard.bool(forKey: "study.paperAlwaysLight") { return UIColor(hex: light) }
            return UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
    static let xuan = ReaderPaper.paper.color(\.background)
    static let xuanSecondary = ReaderPaper.paper.color(\.secondary)
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
    var background: Color { kind.color(\.background) }
    var foreground: Color { kind.color(\.foreground) }
    var secondary: Color { kind.color(\.secondary) }
    /// 跟读浅底：取纸面外观对应的高亮色，只作填充带，不作竖线。
    var highlight: UIColor {
        let paper = kind
        return UIColor { traits in
            UIColor(hex: paper.resolve(darkAppearance: traits.userInterfaceStyle == .dark,
                                      alwaysLight: UserDefaults.standard.bool(forKey: "study.paperAlwaysLight")).highlight)
        }
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
    @Environment(\.themeDirection) private var direction
    let title: String
    var detail: String? = nil
    var eyebrow: String? = nil
    var body: some View {
        let _ = direction
        let active = AppThemeDirection.current
        VStack(alignment: .leading, spacing: Theme.space2) {
            if active != .systemClear {
                Rectangle()
                    .fill(active == .editorial ? Theme.ink : Theme.line)
                    .frame(height: active == .editorial ? Theme.ruleMedium : Theme.rule)
                    .accessibilityHidden(true)
            }
            if let eyebrow {
                HStack(spacing: 6) {
                    if active != .systemClear {
                        Rectangle().fill(Theme.clay).frame(width: 7, height: 7).accessibilityHidden(true)
                    }
                    Text(active == .systemClear ? L(eyebrow) : L(eyebrow).localUppercased)
                        .mastheadStyle(color: Theme.accent).foregroundStyle(Theme.accent)
                }
            }
            Text(L(title)).font(Theme.heading(28, relativeTo: .title, weight: .bold)).foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
            if let detail {
                Text(L(detail)).font(Theme.sans(13)).foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            InkRule().padding(.top, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
}

/// An adaptive navigation/action row; content stays readable rather than truncating values.
struct EditorialRow: View {
    @Environment(\.themeDirection) private var direction
    let title: String
    var detail: String? = nil
    var value: String? = nil
    var symbol: String? = nil
    var disclosure = true
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        let _ = direction
        HStack(alignment: .center, spacing: Theme.space3) {
            if let symbol {
                ThemeIcon(symbol: symbol, size: 20).foregroundStyle(Theme.ink2)
                    .frame(width: 28).accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: Theme.space1) {
                Text(L(title)).font(Theme.sans(16)).foregroundStyle(Theme.ink)
                if let detail { Text(L(detail)).font(Theme.sans(13)).foregroundStyle(Theme.ink2) }
                if typeSize.isAccessibilitySize, let value {
                    Text(L(value)).font(Theme.sans(13)).foregroundStyle(Theme.accent)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            if !typeSize.isAccessibilitySize, let value {
                Text(L(value)).font(Theme.sans(13)).foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.trailing)
            }
            if disclosure { ThemeIcon(symbol: Icon.disclosure, size: 13).foregroundStyle(Theme.ink4) }
        }
        .padding(.vertical, Theme.space2).frame(minHeight: Theme.rowMinHeight).contentShape(Rectangle())
    }
}

struct PaperPanel: ViewModifier {
    var inset: CGFloat? = nil
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.themeDirection) private var direction
    func body(content: Content) -> some View {
        let _ = direction
        let r = Theme.radius
        let clear = AppThemeDirection.current == .systemClear
        content.padding(inset ?? Theme.cardInset).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: r, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: r, style: .continuous)
                    .strokeBorder(clear ? Theme.line.opacity(0.45) : Theme.line,
                                  lineWidth: contrast == .increased ? Theme.ruleMedium : Theme.rule)
            }
            .softCardShadow()
    }
}

/// Status is conveyed with symbol + title + explanation, never color alone.
struct EditorialNotice: View {
    @Environment(\.themeDirection) private var direction
    enum Kind: Equatable { case information, working, success, failure }
    let title: String
    var detail: String? = nil
    var kind: Kind = .information
    private var symbol: String {
        switch kind { case .information: "info.circle"; case .working: "clock"; case .success: "checkmark.circle"; case .failure: "exclamationmark.triangle" }
    }
    var body: some View {
        let _ = direction
        HStack(alignment: .top, spacing: 12) {
            if kind == .working { ProgressView().padding(.top, 2) }
            else { Image(systemName: symbol).foregroundStyle(kind == .failure ? Theme.danger : Theme.accent).accessibilityHidden(true) }
            VStack(alignment: .leading, spacing: 6) {
                Text(L(title)).font(.subheadline.weight(.semibold))
                if let detail { Text(L(detail)).font(.subheadline).foregroundStyle(Theme.ink2).textSelection(.enabled) }
            }.fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(Theme.ink).modifier(PaperPanel())
        .accessibilityElement(children: .combine)
    }
}

private struct EditorialListModifier: ViewModifier {
    @Environment(\.themeDirection) private var direction
    func body(content: Content) -> some View {
        let _ = direction
        content.listStyle(.insetGrouped).listSectionSpacing(22)
            .scrollContentBackground(.hidden).background(Theme.bg).tint(Theme.accent)
            .environment(\.defaultMinListRowHeight, 52)
    }
}

extension View {
    func paperPanel(inset: CGFloat? = nil) -> some View { modifier(PaperPanel(inset: inset)) }
    /// Consistent native list rhythm used by deeper settings and source browsers.
    func editorialList() -> some View {
        modifier(EditorialListModifier())
    }
}
