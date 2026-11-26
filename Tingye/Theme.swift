import SwiftUI
import UIKit
import CoreImage

/// 听页界面「暖纸 · Warm Paper」：象牙暖纸 `#FAF9F5`、深暖炭墨 `#141413`、克制陶土 `#D97757`。
/// 大量留白、柔和圆角与极淡发丝线建立安静、编辑感强的阅读空间。
/// 正文七种纸色的底与字独立保留，不跟界面一起变色。
enum Theme {
    /// 象牙暖纸 / 夜间深暖炭画布
    static let bg = dynamic(0xFAF9F5, 0x141413)
    /// 干净白卡面 / 夜间柔和深炭卡面
    static let surface = dynamic(0xFFFFFF, 0x1C1B19)
    /// 暖沙次级面 / 夜间抬升深炭面
    static let surface2 = dynamic(0xF0EEE6, 0x262522)
    static let surfaceSunken = dynamic(0xF3F1E9, 0x181715)
    /// 深炭墨正文 / 夜间象牙白字
    static let ink = dynamic(0x141413, 0xFAF9F5)
    static let ink2 = dynamic(0x3D3D3A, 0xD5D3CA)
    static let ink3 = dynamic(0x595853, 0xABA89E)
    static let ink4 = dynamic(0x87867F, 0x78756C)
    /// 极淡发丝线，不抢视线
    static let line = dynamic(0xE6E3D9, 0x2E2C29)
    static let lineField = Color(UIColor { traits in
        UIColor(hex: traits.userInterfaceStyle == .dark ? 0xFAF9F5 : 0x141413)
            .withAlphaComponent(traits.userInterfaceStyle == .dark ? 0.16 : 0.14)
    })
    /// 陶土强调体系：小字采用满足 WCAG AA (≥4.5:1) 的深陶土/亮陶土，主动作采用 Crail `#D97757`，每屏至多一处陶土实面。
    static let accent = dynamic(0xA6482B, 0xECA085)
    static let clayDeep = accent
    static let accentSoft = dynamic(0xF8ECE6, 0x2E201B)
    static let claySoft = accentSoft
    static let clay = dynamic(0xD97757, 0xD97757)
    static let onClay = dynamic(0x141413, 0x141413)
    static let focus = clay
    static let danger = dynamic(0x9E2A2B, 0xF4A6A3)
    static let dangerSoft = dynamic(0xF9EAE8, 0x362020)

    // 语义别名：浓墨主动作面与官方陶土焦点各司其职。
    static let rulePaint = ink
    static let cardEdge = line
    static let onInk = bg
    static let onAccent = bg
    static let link = accent
    static let marker = clay
    static let onMarker = onClay
    static let readingHighlight = accentSoft
    static let hero = accentSoft
    static let heroInk = ink
    static let forest = accent
    static let onForest = onAccent
    static let wash = accentSoft
    static let warm = surface2
    static let onWarm = ink2
    static let gold = onWarm
    static let goldSoft = warm
    static let jade = accent
    static let jadeSoft = accentSoft
    static let indigo = accent
    static let indigoSoft = accentSoft
    static let ochre = gold
    static let plum = accent
    static let amberOnDark = clay

    static let auroraGradient = LinearGradient(colors: [accent, accent], startPoint: .top, endPoint: .bottom)
    static let accentGradient = auroraGradient
    static let heroGradient = LinearGradient(colors: [hero, hero], startPoint: .top, endPoint: .bottom)
    static let heroButtonInk = ink

    static let space1: CGFloat = 4
    static let space2: CGFloat = 8
    static let space3: CGFloat = 12
    static let space4: CGFloat = 16
    static let space5: CGFloat = 24
    static let space6: CGFloat = 32
    static let space7: CGFloat = 48
    static let inset: CGFloat = 24
    static let insetCompact: CGFloat = 20
    static let cardInset: CGFloat = 22
    static let rowMinHeight: CGFloat = 52
    static let sectionSpacing = space6
    static let pageWidth: CGFloat = 720
    /// 柔和圆角：卡片 18、大面板/英雄卡 26、按钮与输入框 14、小标签 8、胶囊全圆。
    static let radius: CGFloat = 18
    static let heroRadius: CGFloat = 26
    static let buttonRadius: CGFloat = 14
    static let radiusField: CGFloat = 14
    static let radiusSmall: CGFloat = 8
    static let radiusPill: CGFloat = 999
    static let buttonRadiusSmall: CGFloat = 10
    static func coverRadius(_ width: CGFloat) -> CGFloat { min(10, max(4, width * 0.07)) }
    static let buttonHeight: CGFloat = 50
    static let iconButtonSize: CGFloat = 44
    static let hairline: CGFloat = 0.5
    static let progressHeight: CGFloat = 3.5
    static let sealDotSize: CGFloat = 6
    static let mastheadTracking: CGFloat = 1.4
    static let pressedOpacity = 0.88
    static let disabledOpacity = 0.4
    static let ruleHeavy: CGFloat = 2.5
    static let ruleMedium: CGFloat = 1.5
    static let rule: CGFloat = 0.75

    // MARK: - 动效

    static let pressSpring = Animation.spring(response: 0.32, dampingFraction: 0.86)
    static let pressAnimation = Animation.easeOut(duration: 0.2)
    static let smoothSpring = pressSpring

    // MARK: - 字体：界面使用系统字体；宋体用于书名、摘句与正文偏好

    static let serifName = "NotoSerifCJKsc-Regular"
    static func serif(_ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(serifName, size: size, relativeTo: style)
    }
    /// v29：宋体只有 Regular，取消合成字重；保留签名兼容调用点，与 serif 相同。
    static func serifSemibold(_ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        serif(size, relativeTo: style)
    }
    /// v29：同 serifSemibold，不再合成粗体；层级靠字号、留白与发丝线建立。
    static func serifBold(_ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        serif(size, relativeTo: style)
    }
    /// 界面字体：系统字体（真实字重、与 SF Symbols 基线对齐）。固定字号，不再随 relativeTo 缩放。
    static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
    /// Font 不承载 tracking；配合 .mastheadStyle() 应用完整眉题样式。
    static let masthead = Font.system(size: 12, weight: .semibold)
    /// 统计数字沿用宋体 Regular；调用方使用 monospacedDigit() 对齐数位。
    static func display(_ size: CGFloat, relativeTo style: Font.TextStyle = .largeTitle) -> Font {
        serif(size, relativeTo: style)
    }
    /// 栏目标签（同 masthead）。
    static let kicker = masthead
    /// 报刊标题：宋体 Regular，书名、页面标题、报头都用它。
    static func headline(_ size: CGFloat) -> Font { serifBold(size, relativeTo: .title) }

    // MARK: - 无图书籍的低饱和封面（真实书封始终优先）

    static func coverColor(_ color: String) -> Color { Color(uiColor: coverUIColor(color)) }
    /// 占位封使用浅灰纸色，随日夜切换；真实导入书封不反色。
    static func coverUIColor(_ color: String) -> UIColor {
        UIColor(surfaceSunken)
    }
    static func coverForeground(_ color: String) -> Color { ink }

    /// 纯色色块（保留渐变签名，便于沿用调用处）。
    static func coverGradient(_ color: String) -> LinearGradient {
        LinearGradient(colors: [coverColor(color), coverColor(color)], startPoint: .top, endPoint: .bottom)
    }
    static func coverGradient(_ base: UIColor, depth: CGFloat = 1) -> LinearGradient {
        let c = Color(uiColor: base.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light)))
        return LinearGradient(colors: [c, c], startPoint: .top, endPoint: .bottom)
    }

    private static func dynamic(_ light: UInt32, _ dark: UInt32, highLight: UInt32? = nil, highDark: UInt32? = nil) -> Color {
        Color(UIColor { traits in
            let night = traits.userInterfaceStyle == .dark
            let value = traits.accessibilityContrast == .high
                ? (night ? highDark ?? dark : highLight ?? light) : (night ? dark : light)
            return UIColor(hex: value)
        })
    }
}

// MARK: - 层次：宣纸画布与安静的内容表面

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
        self.background(Theme.surface, in: shape)
    }

    func glassCard(cornerRadius: CGFloat = Theme.radius, interactive: Bool = false) -> some View {
        self
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(Theme.line, lineWidth: Theme.rule) }
    }

    /// 瑞士分栏：上方发丝线，内容直接落在纸面上。
    func columnRule(_ height: CGFloat = 1) -> some View {
        self.overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1).accessibilityHidden(true) }
            .padding(.top, 0)
    }

    /// v31 静息卡：日间黑 3% / 24 / y6，夜间不渲染阴影。
    func softCardShadow() -> some View { modifier(SoftCardShadow()) }

    func floatingPanel(cornerRadius: CGFloat = Theme.radius) -> some View {
        self
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(Theme.line, lineWidth: Theme.rule) }
            .modifier(FloatingPanelShadow())
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

    func paperBackground() -> some View {
        self.background { Theme.bg.ignoresSafeArea() }
    }

    /// 跟读：淡陶土底与陶土竖条共同标记当前句，不只依赖颜色。
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

/// 极克制的静息卡柔影：日间仅黑 3% 轻浮，夜间不渲染阴影、仅靠发丝线区分层次。
struct SoftCardShadow: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    func body(content: Content) -> some View {
        if colorScheme == .dark {
            content
        } else {
            content.shadow(color: Color(hex: 0x141413).opacity(0.035), radius: 20, x: 0, y: 6)
        }
    }
}

private struct FloatingPanelShadow: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    func body(content: Content) -> some View {
        if colorScheme == .dark {
            content.shadow(color: .black.opacity(0.32), radius: 20, x: 0, y: 8)
        } else {
            content.shadow(color: Color(hex: 0x141413).opacity(0.07), radius: 24, x: 0, y: 8)
        }
    }
}

// MARK: - 状态标签组件

struct SealBadge: View {
    let text: String
    var color: Color = Theme.ink3
    var background: Color? = nil
    /// 保留旧参数兼容；采用柔和胶囊标签，弱化边框装饰。
    var filled: Bool = false
    var body: some View {
        Text(L(text))
            .font(Theme.sans(11, weight: .medium))
            .tracking(0.3)
            .foregroundStyle(color)
            .padding(.horizontal, Theme.space3)
            .padding(.vertical, Theme.space1)
            .background(background ?? Theme.surface2, in: Capsule())
    }
}

// MARK: - 按钮（柔和圆角，克制主次）

/// 主操作采用深炭墨实底 `#141413` 配象牙白字（夜间反转象牙实底配炭墨字）；柔和 14pt 圆角。
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var height: CGFloat = Theme.buttonHeight
    var fill: Color = Theme.ink
    var foreground: Color = Theme.onInk
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.sans(15, weight: .medium))
            .fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(.center)
            .padding(.horizontal, Theme.space4).padding(.vertical, Theme.space3)
            .frame(maxWidth: .infinity, minHeight: height)
            .foregroundStyle(foreground)
            .background(fill, in: RoundedRectangle(cornerRadius: Theme.buttonRadius, style: .continuous))
            .modifier(PressFeedback(pressed: configuration.isPressed))
            .contentShape(RoundedRectangle(cornerRadius: Theme.buttonRadius, style: .continuous))
            .opacity(isEnabled ? 1 : Theme.disabledOpacity)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
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
            .foregroundStyle(emphasized ? Theme.accent : Theme.ink)
            .background(emphasized ? Theme.accentSoft : Theme.surface, in: RoundedRectangle(cornerRadius: Theme.buttonRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.buttonRadius, style: .continuous)
                    .strokeBorder(emphasized ? Theme.clay.opacity(0.6) : Theme.line, lineWidth: Theme.rule)
            }
            .modifier(PressFeedback(pressed: configuration.isPressed))
            .contentShape(RoundedRectangle(cornerRadius: Theme.buttonRadius, style: .continuous))
            .opacity(isEnabled ? 1 : Theme.disabledOpacity)
    }
}

/// 历史签名兼容壳，避免给内容重复添加表面。
struct GlassSkin: ViewModifier {
    var interactive = false
    var shape: AnyShape = AnyShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    func body(content: Content) -> some View { content }
}

/// 柔和胶囊筛选签：选中态深炭墨实底配象牙字与对勾，未选态干净白面与极淡发丝线。
struct ChipPillStyle: ButtonStyle {
    var selected: Bool
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        let shape = Capsule()
        HStack(spacing: Theme.space1) {
            if selected { Image(systemName: Icon.checkmark).font(.system(size: 11, weight: .semibold)).accessibilityHidden(true) }
            configuration.label
        }
        .font(Theme.sans(14, weight: selected ? .medium : .regular))
        .foregroundStyle(selected ? Theme.bg : Theme.ink2)
        .padding(.horizontal, Theme.space4)
        .frame(minHeight: Theme.iconButtonSize)
        .background(selected ? Theme.ink : Theme.surface, in: shape)
        .overlay { shape.strokeBorder(selected ? Color.clear : Theme.line, lineWidth: Theme.rule) }
        .contentShape(shape)
        .modifier(PressFeedback(pressed: configuration.isPressed))
        .opacity(isEnabled ? 1 : Theme.disabledOpacity)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// 无底无描边图标按钮，命中区至少 44pt。
struct CircleIconButton: View {
    let systemName: String
    let label: String
    var size: CGFloat = Theme.iconButtonSize
    let action: () -> Void
    var body: some View {
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

/// 白卡、发丝线与柔影；内边距默认 22，圆角默认 18。
struct Card<Content: View>: View {
    var padding: CGFloat = Theme.cardInset
    var cornerRadius: CGFloat = Theme.radius
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(cornerRadius: cornerRadius).softCardShadow()
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
    var icon: String? = nil
    var color: Color = Theme.ink
    let title: String
    var value: String? = nil
    var subtitle: String? = nil
    var destructive = false
    var body: some View {
        HStack(spacing: Theme.space3) {
            if let icon {
                SettingsIcon(systemName: icon, color: destructive ? Theme.danger : color)
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
    var inset: CGFloat = 0
    var body: some View {
        Rectangle().fill(Theme.line).frame(height: Theme.hairline).padding(.leading, inset)
    }
}

/// 历史线条组件现在只绘制中性分隔线。
struct InkRule: View {
    var height: CGFloat = Theme.rule
    var color: Color = Theme.line
    var body: some View { Rectangle().fill(color).frame(height: min(height, Theme.hairline)).accessibilityHidden(true) }
}

/// 区块标题：安静的宋体层级，靠留白建立节奏，不加多余色条与粗线。
struct SectionTitle: View {
    let text: String
    var badge: String? = nil
    var number: String? = nil
    var rule = false
    init(text: String, badge: String? = nil, number: String? = nil, rule: Bool = false) {
        self.text = text; self.badge = badge; self.number = number; self.rule = rule
    }
    init(title: String, badge: String? = nil, number: String? = nil, rule: Bool = false) {
        self.text = title; self.badge = badge; self.number = number; self.rule = rule
    }
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.space2) {
            if let number {
                Text(number).mastheadStyle(color: Theme.ink3)
            }
            Text(L(text)).font(Theme.serif(20, relativeTo: .title3)).foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let badge { SealBadge(text: badge) }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// 开阔暖纸页眉：极简眉题、宋体主标题与克制副行，去报头粗线与装饰色块。
struct PageMasthead: View {
    let title: String
    var subtitle: String? = nil
    /// 保留参数兼容调用点；新设计不绘制粗顶线。
    var rule = false
    var kicker: String? = nil
    var issue: String? = nil
    var titleSize: CGFloat = 34
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.space2) {
            if kicker != nil || issue != nil || actionTitle != nil {
                HStack(alignment: .center) {
                    if let kicker {
                        Text(L(kicker).localUppercased).foregroundStyle(Theme.ink3)
                    }
                    Spacer()
                    if let issue { Text(L(issue).localUppercased).foregroundStyle(Theme.ink3) }
                    if let actionTitle, let action { TextButton(actionTitle, action: action) }
                }
                .mastheadStyle()
            }
            Text(L(title))
                .font(Theme.serif(titleSize, relativeTo: .largeTitle))
                .lineSpacing(titleSize * 0.18)
                .minimumScaleFactor(min(1, 24 / titleSize))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: Theme.iconButtonSize, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            if let subtitle, !subtitle.isEmpty {
                Text(L(subtitle))
                    .font(Theme.sans(14))
                    .lineSpacing(3)
                    .foregroundStyle(Theme.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ProgressBar: View {
    var value: Double
    var track: Color = Theme.surface2
    var tint: Color = Theme.clay
    var height: CGFloat = Theme.progressHeight
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule().fill(tint).frame(width: max(0, min(1, value)) * geo.size.width)
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
        let fg = Theme.coverForeground(color)
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
        .clipShape(RoundedRectangle(cornerRadius: Theme.coverRadius(width), style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: Theme.coverRadius(width), style: .continuous).strokeBorder(Theme.line, lineWidth: Theme.hairline) }
        .overlay {
            RoundedRectangle(cornerRadius: Theme.coverRadius(width), style: .continuous)
                .inset(by: Theme.hairline)
                .strokeBorder(Color.white.opacity(0.35), lineWidth: Theme.rule)
                .allowsHitTesting(false)
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
        let titleSize = min(22, max(11, width * 0.14))
        return ZStack(alignment: .leading) {
            Theme.coverColor(color)
            VStack(alignment: .leading, spacing: 0) {
                Text(L(title))
                    .font(Theme.serif(titleSize)).foregroundStyle(fg)
                    .lineLimit(3).minimumScaleFactor(0.72).multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if width >= 72 && !author.isEmpty {
                    Text(author).font(.system(size: max(8, width * 0.075)))
                        .foregroundStyle(Theme.ink3).lineLimit(1)
                        .padding(.top, max(4, width * 0.05))
                }
                Spacer(minLength: 0)
                Rectangle().fill(Theme.line).frame(height: Theme.hairline).accessibilityHidden(true)
                if let index {
                    Text(String(format: "%02d", index))
                        .font(Theme.sans(max(8, width * 0.075), weight: .medium)).monospacedDigit()
                        .foregroundStyle(Theme.ink3).padding(.top, max(3, width * 0.04))
                }
            }
            .padding(.horizontal, max(9, width * 0.12))
            .padding(.vertical, max(11, width * 0.13))
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
    let title: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.space2) {
            Text(L(title)).font(Theme.serif(20, relativeTo: .title3))
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
    func makeBody(configuration: Configuration) -> some View {
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
    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: Theme.space1))
            : AnyLayout(HStackLayout(spacing: Theme.space1))
        layout {
            ForEach(options, id: \.self) { option in
                Button { onSelect(option) } label: {
                    HStack(spacing: Theme.space1) {
                        if option == selection {
                            Image(systemName: Icon.checkmark).font(.system(size: 11, weight: .semibold)).accessibilityHidden(true)
                        }
                        Text(L(title(option))).fixedSize(horizontal: false, vertical: true)
                    }
                    .font(Theme.sans(13, weight: option == selection ? .medium : .regular))
                    .foregroundStyle(option == selection ? Theme.ink : Theme.ink3)
                    .padding(.horizontal, Theme.space2)
                    .frame(maxWidth: .infinity, minHeight: Theme.iconButtonSize)
                    .background(option == selection ? Theme.surface : .clear,
                                in: RoundedRectangle(cornerRadius: Theme.buttonRadiusSmall, style: .continuous))
                    .overlay {
                        if option == selection {
                            RoundedRectangle(cornerRadius: Theme.buttonRadiusSmall, style: .continuous)
                                .strokeBorder(Theme.line, lineWidth: Theme.hairline)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressButtonStyle())
                .accessibilityAddTraits(option == selection ? .isSelected : [])
            }
        }
        .padding(Theme.space1)
        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: Theme.buttonRadius, style: .continuous))
    }
}

struct SealDot: View {
    let text: String
    var body: some View {
        HStack(spacing: Theme.space1) {
            Circle().fill(Theme.clay).frame(width: Theme.sealDotSize, height: Theme.sealDotSize)
                .accessibilityHidden(true)
            Text(L(text)).font(Theme.sans(11)).foregroundStyle(Theme.accent)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct SheetTopShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path(UIBezierPath(roundedRect: rect, byRoundingCorners: [.topLeft, .topRight],
                          cornerRadii: CGSize(width: Theme.heroRadius, height: Theme.heroRadius)).cgPath)
    }
}

struct SheetChrome<Content: View>: View {
    let title: String
    var closeLabel = "关闭"
    let onClose: () -> Void
    var showsHeader = true
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: Theme.space4) {
            Capsule().fill(Theme.line).frame(width: Theme.space6, height: Theme.space1)
                .accessibilityHidden(true)
            if showsHeader { HStack(spacing: Theme.space3) {
                Text(L(title)).font(Theme.serif(20, relativeTo: .title3)).foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
                Spacer(minLength: Theme.space2)
                CircleIconButton(systemName: Icon.close, label: L(closeLabel), action: onClose)
            } }
            content
        }
        .padding(Theme.cardInset)
        .background(Theme.surface, in: SheetTopShape())
        .overlay { SheetTopShape().stroke(Theme.line, lineWidth: Theme.hairline).allowsHitTesting(false) }
        .clipShape(SheetTopShape())
        .modifier(FloatingPanelShadow())
    }
}

/// 空态、加载、错误沿用同一标题/说明语言；所有文案与重试动作由调用方传入。
struct EmptyState: View {
    enum State: Equatable { case empty, loading, error, success }
    let title: String
    let detail: String
    var state: State = .empty
    var badge: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var body: some View {
        VStack(spacing: Theme.space4) {
            if state == .loading { ProgressView().tint(Theme.ink2) }
            if let badge {
                SealBadge(text: badge, color: state == .error ? Theme.danger : Theme.accent,
                          background: state == .error ? Theme.dangerSoft : Theme.accentSoft)
            }
            if state == .error {
                Image(systemName: Icon.warning).foregroundStyle(Theme.danger).accessibilityHidden(true)
            }
            Text(L(title)).font(Theme.serif(22, relativeTo: .title2)).foregroundStyle(Theme.ink)
                .padding(state == .error ? Theme.space2 : 0)
                .background(state == .error ? Theme.dangerSoft : .clear,
                            in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
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
    let value: String
    let label: String
    var size: CGFloat = 30
    var body: some View {
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
    let title: String
    var detail: String? = nil
    var eyebrow: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.space2) {
            if let eyebrow {
                Text(L(eyebrow).localUppercased).mastheadStyle(color: Theme.ink3)
            }
            Text(L(title)).font(Theme.serif(26, relativeTo: .title)).foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
            if let detail {
                Text(L(detail)).font(Theme.sans(14)).lineSpacing(3).foregroundStyle(Theme.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Theme.space2)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
}

/// An adaptive navigation/action row; content stays readable rather than truncating values.
struct EditorialRow: View {
    let title: String
    var detail: String? = nil
    var value: String? = nil
    var symbol: String? = nil
    var disclosure = true
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
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
    var inset: CGFloat = Theme.cardInset
    @Environment(\.colorSchemeContrast) private var contrast
    func body(content: Content) -> some View {
        content.padding(inset).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).strokeBorder(Theme.line, lineWidth: contrast == .increased ? Theme.ruleMedium : Theme.rule) }
            .softCardShadow()
    }
}

/// Status is conveyed with symbol + title + explanation, never color alone.
struct EditorialNotice: View {
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

extension View {
    func paperPanel(inset: CGFloat = Theme.cardInset) -> some View { modifier(PaperPanel(inset: inset)) }
    /// Consistent native list rhythm used by deeper settings and source browsers.
    func editorialList() -> some View {
        self.listStyle(.insetGrouped).listSectionSpacing(22)
            .scrollContentBackground(.hidden).background(Theme.bg).tint(Theme.accent)
            .environment(\.defaultMinListRowHeight, 52)
    }
}
