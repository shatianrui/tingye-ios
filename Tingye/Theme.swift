import SwiftUI
import UIKit
import CoreImage
import ImageIO
import Pow

/// Decode only enough pixels for a cover/illustration preview, respecting EXIF orientation.
enum BookImage {
    static func thumbnail(_ data: Data, maxPixelSize: Int) -> UIImage? {
        guard maxPixelSize > 0,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

/// 听页 · 纸页与松绿。纸色承载内容，松绿标记行动；阅读纸色独立保存。
enum Theme {
    static let bg = dynamic(0xF6F3EB, 0x141C19)
    static let surface = dynamic(0xFFFDF7, 0x1D2924)
    static let surface2 = dynamic(0xECEDE4, 0x29382F)
    static let ink = dynamic(0x243A30, 0xF1F3EA)
    // 比设计色略深，保证暖纸、浅蓝卡片和次级表面上的小字达到 4.5:1。
    static let ink2 = dynamic(0x59675D, 0xB4C1B6)
    static let ink3 = ink2
    static let line = dynamic(0xDADFD3, 0x3D5044)
    static let rulePaint = line
    static let onInk = dynamic(0xFFFFFF, 0x14291F)
    static let cardEdge = line
    static let accent = dynamic(0x285C45, 0xA7D6B6)
    static let accentSoft = dynamic(0xE3EBDD, 0x2A4033)
    static let onAccent = dynamic(0xFFFFFF, 0x14291F)
    static let clay = accent
    static let onClay = onAccent
    static let link = accent
    static let marker = clay
    static let onMarker = onClay
    static let readingHighlight = accentSoft
    static let hero = accentSoft
    static let heroInk = ink
    static let forest = accent
    static let onForest = onAccent
    static let wash = clay.opacity(0.08)
    static let danger = dynamic(0xAE3D4E, 0xFF9FAD)
    static let warm = dynamic(0xEEE4CF, 0x3B3425)
    static let onWarm = dynamic(0x66502D, 0xE8D5AD)
    static let gold = onWarm
    static let goldSoft = warm
    static let jade = dynamic(0x237864, 0x78CDB2)
    static let jadeSoft = dynamic(0xEAF6EF, 0x1E3327)
    static let indigo = accent
    static let indigoSoft = accentSoft
    static let ochre = gold
    static let plum = accent
    static let amberOnDark = clay

    static let auroraGradient = LinearGradient(colors: [accent, accent], startPoint: .top, endPoint: .bottom)
    static let accentGradient = auroraGradient
    static let heroGradient = LinearGradient(colors: [hero, hero], startPoint: .top, endPoint: .bottom)
    static let heroButtonInk = ink

    static let inset: CGFloat = 24
    static let pageWidth: CGFloat = 720
    static let radius: CGFloat = 20
    static let heroRadius: CGFloat = 24
    static let radiusSmall: CGFloat = 8
    static let buttonRadius: CGFloat = 14
    static let buttonHeight: CGFloat = 50
    static let iconButtonSize: CGFloat = 44
    static let ruleHeavy: CGFloat = 3
    static let ruleMedium: CGFloat = 2
    static let rule: CGFloat = 1

    // MARK: - 动效

    static let pressSpring = Animation.spring(response: 0.28, dampingFraction: 0.72)
    static let smoothSpring = Animation.spring(response: 0.42, dampingFraction: 0.86)

    // MARK: - 字体：界面使用系统字体；宋体用于书名、摘句与正文偏好

    static let serifName = "NotoSerifCJKsc-Regular"
    static func serif(_ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(serifName, size: size, relativeTo: style)
    }
    static func serifSemibold(_ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(serifName, size: size, relativeTo: style).weight(.medium)
    }
    static func serifBold(_ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(serifName, size: size, relativeTo: style).weight(.semibold)
    }
    static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("NotoSansCJKsc-Regular", size: size, relativeTo: .body).weight(weight)
    }
    /// 栏目标签：黑体粗、宽字距（报纸的版面眉题），如「继续阅读」「最近在读」。
    static let masthead = Font.custom("NotoSansCJKsc-Regular", size: 12, relativeTo: .caption).weight(.medium)
    /// 统计大数字：无衬线粗体 + 等宽数字，不用宋体；调用方负责字号缩放。
    static func display(_ size: CGFloat, relativeTo style: Font.TextStyle = .largeTitle) -> Font {
        .custom("NotoSansCJKsc-Regular", size: size, relativeTo: style).weight(.semibold)
    }
    /// 栏目标签（同 masthead）。
    static let kicker = masthead
    /// 报刊标题：宋体粗，书名、页面标题、报头都用它。
    static func headline(_ size: CGFloat) -> Font { serifBold(size, relativeTo: .title) }

    // MARK: - 无图书籍的低饱和封面（真实书封始终优先）

    static func coverColor(_ color: String) -> Color { Color(uiColor: coverUIColor(color)) }
    /// 占位封使用浅灰纸色，随日夜切换；真实导入书封不反色。
    static func coverUIColor(_ color: String) -> UIColor {
        let papers: [UInt32] = [0xDCE7E2, 0xE2E8F4, 0xF2E5CF, 0xE6DFED, 0xF0DCD7]
        let light = papers[color.unicodeScalars.reduce(0) { $0 &+ Int($1.value) } % papers.count]
        return UIColor(hex: light)
    }
    static func coverForeground(_ color: String) -> Color { Color(hex: 0x17233A) }

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

// MARK: - 层次：宣纸画布与安静的内容表面

extension View {
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
            .overlay { RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(Theme.line, lineWidth: 1) }
    }

    /// 瑞士分栏：上方发丝线，内容直接落在纸面上。
    func columnRule(_ height: CGFloat = 1) -> some View {
        self.overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1).accessibilityHidden(true) }
            .padding(.top, 0)
    }

    func floatingPanel(cornerRadius: CGFloat = Theme.radius) -> some View {
        self
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(Theme.line, lineWidth: 1) }
            .shadow(color: Color.black.opacity(0.08), radius: 16, x: 0, y: 4)
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

    /// 内置思源宋体只有常规字重：标题用两层亚像素位移叠印加粗，得到报纸标题的粗宋分量。
    func serifEmbolden(_ size: CGFloat) -> some View { modifier(SerifEmbolden(amount: max(0.3, size * 0.026))) }
    /// 系统字体已有真实字重，特粗档不再叠印加粗，保持大标题干净。
    func serifHeavy(_ size: CGFloat) -> some View { self }

    func paperBackground() -> some View {
        self.background { Theme.bg.ignoresSafeArea() }
    }

    /// 跟读：淡靛蓝底与靛蓝竖条共同标记当前句，不只依赖颜色。
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
private struct SerifEmbolden: ViewModifier {
    let amount: CGFloat
    func body(content: Content) -> some View {
        content
            .overlay { content.offset(x: amount).accessibilityHidden(true).allowsHitTesting(false) }
            .overlay { content.offset(x: amount / 2, y: amount / 2).accessibilityHidden(true).allowsHitTesting(false) }
    }
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

struct SealBadge: View {
    let text: String
    var color: Color = Theme.accent
    var background: Color? = nil
    var filled: Bool = false
    var body: some View {
        Text(L(text))
            .font(.system(size: 10, weight: .bold)).tracking(0.8)
            .foregroundStyle(filled ? Theme.onClay : color)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(background ?? (filled ? Theme.clay : Theme.accentSoft), in: RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
    }
}

// MARK: - 按钮（温润圆角，主次明确）

/// 靛蓝圆角主操作、2pt 墨框次操作。
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var height: CGFloat = Theme.buttonHeight
    var fill: Color = Theme.clay
    var foreground: Color = Theme.onClay
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.bold))
            .fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 18).padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: height)
            .foregroundStyle(foreground)
            .background(fill, in: RoundedRectangle(cornerRadius: Theme.buttonRadius, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(Theme.pressSpring, value: configuration.isPressed)
            .conditionalEffect(.pushDown, condition: configuration.isPressed && !reduceMotion)
            .contentShape(RoundedRectangle(cornerRadius: Theme.buttonRadius))
            .opacity(isEnabled ? 1 : 0.4)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var height: CGFloat = Theme.buttonHeight
    var emphasized = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.bold))
            .fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 18).padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: height)
            .foregroundStyle(Theme.accent)
            .background(Theme.accentSoft.opacity(configuration.isPressed ? 0.75 : 1), in: RoundedRectangle(cornerRadius: Theme.buttonRadius, style: .continuous))
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

/// 直角筛选块：选中实心墨底，未选中 1px 描边。
struct ChipPillStyle: ButtonStyle {
    var selected: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(selected ? .bold : .regular))
            .foregroundStyle(selected ? Theme.onAccent : Theme.ink2)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(selected ? Theme.accent : Theme.surface2, in: Capsule())
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// 图标按钮：40pt 圆角 8，无描边，按压变浅灰底。
struct CircleIconButton: View {
    let systemName: String
    let label: String
    var size: CGFloat = Theme.iconButtonSize
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            ThemeIcon(symbol: systemName, size: 20, weight: .medium)
                .frame(width: size, height: size)
                .foregroundStyle(Theme.ink)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(RoundedRectangle(cornerRadius: Theme.radius))
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

/// 统一按压反馈：按调用方给的比例轻缩 + 微透明（整行卡片 0.99、图标按钮 0.92–0.94）；主按钮的 Pow 下陷见 PrimaryButtonStyle。
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
    static func light() { if GeneralSettings.hapticsEnabled { UIImpactFeedbackGenerator(style: .light).impactOccurred() } }
    static func selection() { if GeneralSettings.hapticsEnabled { UISelectionFeedbackGenerator().selectionChanged() } }
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

/// 设置项图标：墨色线性图标，靛蓝留给编号与眉题。
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
        HStack(spacing: 14) {
            if let icon {
                SettingsIcon(systemName: icon, color: destructive ? Theme.danger : color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(L(title)).font(.subheadline.weight(.medium)).foregroundStyle(destructive ? Theme.danger : Theme.ink)
                if let subtitle { Text(L(subtitle)).font(.caption).foregroundStyle(Theme.ink3).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 8)
            if let value { Text(L(value)).font(.caption).foregroundStyle(Theme.ink3).lineLimit(1) }
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

/// 纸质栏目标题：黑体粗宽字距眉题（可带编号），靛蓝。
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
            if let number { Text(number).font(Theme.masthead).foregroundStyle(Theme.accent) }
            Text(L(text)).font(Theme.sans(20, weight: .semibold)).foregroundStyle(Theme.ink)
            if let badge { SealBadge(text: badge) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// 各主页面共用的页眉：眉题行 + 宋体粗大标题 + 可选说明，支持 Dynamic Type。
struct PageMasthead: View {
    let title: String
    var subtitle: String? = nil
    var rule = true
    /// 报头左右眉题，如 `TINGYE / LIBRARY` / `8 BOOKS`。
    var kicker: String? = nil
    var issue: String? = nil
    /// 报头线只在独立报头（有眉题）时绘制；与按钮并排的报头由调用方画整行分隔线。
    private var hasKicker: Bool { kicker != nil || issue != nil }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if kicker != nil || issue != nil {
                HStack {
                    if let kicker { Text(L(kicker)).foregroundStyle(Theme.accent) }
                    Spacer()
                    if let issue { Text(L(issue)).foregroundStyle(Theme.ink2) }
                }
                .font(Theme.masthead)
                .accessibilityHidden(true)
            }
            Text(L(title))
                .font(Theme.sans(28, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .frame(minHeight: 44, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            if let subtitle, !subtitle.isEmpty {
                Text(L(subtitle))
                    .font(.footnote)
                    .foregroundStyle(Theme.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ProgressBar: View {
    var value: Double
    var track: Color = Theme.line
    var tint: Color = Theme.clay
    var height: CGFloat = 3
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

/// 真实书封完整显示；无图时使用纸质占位封：冷纸色 + 宋体粗书名 + 底部一道墨线。
/// 不论有无书封，外圈都是 1px 冷调发丝线与 10pt 圆角。
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        let fg = Theme.coverForeground(color)
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFit().background(Theme.surface2)
                    .transition(reduceMotion ? .opacity : .movingParts.blur(radius: 8))
            } else if width < 52 {
                tinyPlaceholder(fg)
            } else {
                slipPlaceholder(fg)
            }
        }
        .animation(.easeOut(duration: 0.35), value: image != nil)
        // 封面是固定比例的书籍图像；可缩放的完整书名由外部标题及无障碍标签提供。
        .dynamicTypeSize(.medium)
        .frame(width: width, height: width / 0.75)
        .clipShape(RoundedRectangle(cornerRadius: min(10, width * 0.09), style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: min(10, width * 0.09), style: .continuous).strokeBorder(Theme.ink.opacity(0.06), lineWidth: 0.5) }
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
        return ZStack(alignment: .leading) {
            Theme.coverColor(color)
            VStack(alignment: .leading, spacing: 0) {
                Text(L(title))
                    .font(Theme.serifBold(titleSize)).foregroundStyle(fg).serifEmbolden(titleSize)
                    .lineLimit(3).minimumScaleFactor(0.72).multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if width >= 72 && !author.isEmpty {
                    Text(author).font(.system(size: max(8, width * 0.075)))
                        .foregroundStyle(fg.opacity(0.75)).lineLimit(1)
                        .padding(.top, max(3, width * 0.04))
                }
                Spacer(minLength: 0)
                Rectangle().fill(fg).frame(height: 1).accessibilityHidden(true)
                if let index {
                    Text(String(format: "%02d", index))
                        .font(.system(size: max(8, width * 0.08), weight: .bold)).monospacedDigit()
                        .foregroundStyle(fg.opacity(0.75)).padding(.top, max(3, width * 0.04))
                }
            }
            .padding(.leading, max(8, width * 0.12))
            .padding(.trailing, max(8, width * 0.1))
            .padding(.vertical, max(9, width * 0.11))
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

// MARK: - 阅读偏好（七种中性阅读纸色）

enum ReaderPaper: String, CaseIterable, Identifiable {
    case paper, mist, ancient, eink, white, blue, night
    var id: String { rawValue }
    var name: String {
        ["paper": "默认", "mist": "雾灰", "ancient": "旧书", "eink": "浅灰", "white": "纯白", "blue": "深蓝", "night": "夜读"][rawValue] ?? rawValue
    }
    var swatch: Color {
        switch self {
        case .paper:   Color(hex: 0xF6F0E4)
        case .mist:    Color(hex: 0xE6EBF1)
        case .ancient: Color(hex: 0xF3E7D6)
        case .eink:    Color(hex: 0xF0F0F0)
        case .white:   Color(hex: 0xFFFFFF)
        case .blue:    Color(hex: 0x1A2C3A)
        case .night:   Color(hex: 0x101012)
        }
    }
    var dark: Bool { self == .blue || self == .night }
    static let xuan = Color.dynamicLight(0xF6F0E4, 0x1B2330)
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
        case .mist:    return Color(hex: 0x666666)
        case .ancient: return Color(hex: 0x6E5F4B)
        case .eink:    return Color(hex: 0x666666)
        case .white:   return Color(hex: 0x666666)
        case .blue:    return Color(hex: 0x8AA0B4)
        case .night:   return Color(hex: 0xA5A296)
        case .paper:   return ReaderPaper.xuanSecondary
        }
    }
    /// 原生分页与原书图文共用靛蓝跟读标记（铺底时取低透明度成淡靛蓝），纸色设置不变；深色纸用提亮的靛蓝。
    var highlightBand: UIColor {
        let followsAppearance = kind == .paper
        let darkPaper = kind.dark
        return UIColor { traits in
            (darkPaper || (followsAppearance && traits.userInterfaceStyle == .dark))
                ? UIColor(hex: 0x8DA7FF) : UIColor(hex: 0x315BEE)
        }
    }
    /// 连续滚动模式整句铺底：半透明靛蓝
    var highlight: UIColor {
        let band = highlightBand, darkPaper = kind.dark, followsAppearance = kind == .paper
        return UIColor { band.resolvedColor(with: $0).withAlphaComponent(darkPaper || (followsAppearance && $0.userInterfaceStyle == .dark) ? 0.26 : 0.14) }
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

/// 设计稿复用的矢量图标；状态型/未映射符号保留原生 SF Symbols。
struct ThemeIcon: View {
    let symbol: String
    var size: CGFloat = 20
    var weight: Font.Weight = .regular
    private static let assets: [String: String] = [
        "books.vertical": "books-vertical", "book": "book", "folder": "folder",
        "magnifyingglass": "magnifyingglass", "plus": "plus",
        "chevron.left": "chevron-left", "chevron.right": "chevron-right",
        "list.bullet": "list-bullet", "headphones": "headphones",
        "speaker.wave.2": "speaker-wave-2", "moon": "moon", "ellipsis": "ellipsis",
        "icloud": "icloud", "slider.horizontal.3": "slider-horizontal-3",
        "gearshape": "gearshape", "wifi": "wifi", "bookmark": "bookmark",
        "play.fill": "play-fill", "pause.fill": "pause-fill",
        "backward.end.fill": "backward-end-fill", "forward.end.fill": "forward-end-fill"
    ]
    var body: some View {
        Group {
            if let asset = Self.assets[symbol] {
                Image("TY-" + asset).resizable().renderingMode(.template).scaledToFit()
                    .padding(2)
            } else {
                Image(systemName: symbol).font(.system(size: round(size * 0.85), weight: weight))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
