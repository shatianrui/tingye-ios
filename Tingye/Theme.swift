import SwiftUI
import UIKit
import CoreImage

/// 听页「澄读」：雾白画布、墨黑文字与清透蓝，内容优先的现代极简界面。
/// 正文七种纸色的底与字独立保留，不跟界面一起变色。
enum Theme {
    static let bg = dynamic(0xF4F6F8, 0x0E1216)
    static let surface = dynamic(0xFFFFFF, 0x171C22)
    static let surface2 = dynamic(0xE7ECF2, 0x232A33)
    static let surfaceSunken = dynamic(0xEEF2F6, 0x12181F)
    static let ink = dynamic(0x12161C, 0xF3F6F9)
    static let ink2 = dynamic(0x3A4553, 0xC3CEDA)
    static let ink3 = dynamic(0x465264, 0xB4C0CE)
    static let ink4 = dynamic(0x8B95A3, 0x6E7A88)
    static let line = dynamic(0xC3CCD6, 0x3A4450)
    static let lineField = Color(UIColor { traits in
        UIColor(hex: traits.userInterfaceStyle == .dark ? 0xF3F6F9 : 0x12161C)
            .withAlphaComponent(traits.userInterfaceStyle == .dark ? 0.16 : 0.14)
    })
    /// 文字强调与实色动作共享澄蓝；日夜模式分别保证文字和控件对比度。
    static let accent = dynamic(0x163E73, 0xA9C9F2)
    static let clayDeep = accent
    static let accentSoft = dynamic(0xE3EDF8, 0x1A2C44)
    static let claySoft = accentSoft
    static let clay = dynamic(0x163E73, 0x8FB6E6)
    static let onClay = dynamic(0xFFFFFF, 0x0E1622)
    static let focus = clay
    static let danger = dynamic(0x9B2C3C, 0xF5B3BC)
    static let dangerSoft = dynamic(0xF4E8EA, 0x3A2428)

    // 历史符号保留为 v31 语义别名，不再引入独立色板。
    static let rulePaint = line
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
    static let inset: CGFloat = 20
    static let insetCompact: CGFloat = 16
    static let cardInset: CGFloat = 20
    static let rowMinHeight: CGFloat = 52
    static let sectionSpacing = space5
    static let pageWidth: CGFloat = 760
    static let radius: CGFloat = 20
    static let heroRadius: CGFloat = 28
    static let buttonRadius: CGFloat = 14
    static let radiusField: CGFloat = 14
    static let radiusSmall: CGFloat = 10
    /// 全圆胶囊的兼容数值；组件实际使用 Capsule()。
    static let radiusPill: CGFloat = 9999
    static let buttonRadiusSmall = radiusSmall
    static func coverRadius(_ width: CGFloat) -> CGFloat { min(8, width * 0.06) }
    static let buttonHeight: CGFloat = 50
    static let iconButtonSize: CGFloat = 44
    static let hairline: CGFloat = 0.5
    static let progressHeight: CGFloat = 3
    static let sealDotSize: CGFloat = 6
    static let mastheadTracking: CGFloat = 2.0
    static let pressedOpacity = 0.88
    static let disabledOpacity = 0.4
    static let ruleHeavy: CGFloat = 3
    static let ruleMedium: CGFloat = 2
    static let rule: CGFloat = 1

    // MARK: - 动效

    static let pressSpring = Animation.spring(response: 0.32, dampingFraction: 0.86)
    static let pressAnimation = Animation.easeOut(duration: 0.2)
    static let smoothSpring = pressSpring

    // MARK: - 字体：系统字体建立清晰层级；宋体仅保留给正文偏好和文学摘句

    static let serifName = "NotoSerifCJKsc-Regular"
    static func serif(_ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(serifName, size: size, relativeTo: style)
    }
    static func serifSemibold(_ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        serif(size, relativeTo: style)
    }
    static func serifBold(_ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        serif(size, relativeTo: style)
    }
    static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
    static let masthead = Font.system(size: 12, weight: .semibold)
    static func display(_ size: CGFloat, relativeTo style: Font.TextStyle = .largeTitle) -> Font {
        .system(size: size, weight: .semibold, design: .rounded)
    }
    static let kicker = masthead
    static func headline(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold)
    }

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

    fileprivate static func dynamic(_ light: UInt32, _ dark: UInt32, highLight: UInt32? = nil, highDark: UInt32? = nil) -> Color {
        Color(UIColor { traits in
            let night = traits.userInterfaceStyle == .dark
            let value = traits.accessibilityContrast == .high
                ? (night ? highDark ?? dark : highLight ?? light) : (night ? dark : light)
            return UIColor(hex: value)
        })
    }
}

// MARK: - 澄读设计令牌与全界面组件

/// 应用界面语义色。正文继续从 ReaderPaper 独立解析颜色。
enum IndexTheme {
    static let canvas = Theme.dynamic(0xF5F7FA, 0x0B0F14)
    static let surface = Theme.dynamic(0xFFFFFF, 0x141A21)
    static let wash = Theme.dynamic(0xEAF1FB, 0x182A43)
    static let ink = Theme.dynamic(0x101418, 0xF2F5F7, highLight: 0x000000, highDark: 0xFFFFFF)
    static let muted = Theme.dynamic(0x465464, 0xAEBAC6, highLight: 0x101418, highDark: 0xF2F5F7)
    static let accent = Theme.dynamic(0x245FD1, 0x9ABDFF, highLight: 0x17479F, highDark: 0xC4D8FF)
    static let onAccent = Theme.dynamic(0xFFFFFF, 0x071426)
    static let edge = Theme.dynamic(0x68788A, 0x8294A8, highLight: 0x101418, highDark: 0xF2F5F7)
    static let rule = Theme.dynamic(0xDCE3EA, 0x2C3946, highLight: 0x68788A, highDark: 0x8294A8)
    static let danger = Theme.dynamic(0xA1283A, 0xFFB4BE, highLight: 0x7E1427, highDark: 0xFFD3D9)
    static let dangerWash = Theme.dynamic(0xFBEAED, 0x3A2028)
    static let warning = Theme.dynamic(0x805000, 0xFFD38A, highLight: 0x573500, highDark: 0xFFE4B8)

    static let controlRadius: CGFloat = 14
    static let panelRadius: CGFloat = 22
    static let coverRadius: CGFloat = 8
    static let actionHeight: CGFloat = 50
    static let press = Animation.easeOut(duration: 0.16)
    static let transition = Animation.easeInOut(duration: 0.22)

    /// 统一使用系统字体的真实字重和 Dynamic Type，不再把界面标题做成报刊宋体。
    static func editorial(_ size: CGFloat, relativeTo style: Font.TextStyle) -> Font {
        .system(style, weight: size >= 28 ? .bold : .semibold)
    }
}

struct IndexRule: View {
    var body: some View {
        Rectangle().fill(IndexTheme.rule).frame(height: Theme.hairline)
            .allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct IndexActionLabel: View {
    let title: LocalizedStringKey
    var symbol: String? = nil

    var body: some View {
        HStack(spacing: Theme.space2) {
            if let symbol { ThemeIcon(symbol: symbol, size: 16).accessibilityHidden(true) }
            Text(title).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct IndexToolLabel: View {
    let title: LocalizedStringKey
    let symbol: String
    var active = false

    var body: some View {
        VStack(spacing: Theme.space1) {
            ThemeIcon(symbol: symbol, size: 19).accessibilityHidden(true)
            Text(title).font(.caption.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(.center)
        .foregroundStyle(active ? IndexTheme.accent : IndexTheme.ink)
        .padding(.horizontal, Theme.space1).padding(.vertical, Theme.space1)
        .frame(maxWidth: .infinity, minHeight: Theme.rowMinHeight)
        .background(active ? IndexTheme.wash : .clear, in: RoundedRectangle(cornerRadius: IndexTheme.controlRadius))
        .contentShape(Rectangle())
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

struct IndexHeading: View {
    let title: Text
    var detail: Text? = nil
    var large = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.space1) {
            title.font(IndexTheme.editorial(large ? 30 : 21, relativeTo: large ? .largeTitle : .title3))
                .foregroundStyle(IndexTheme.ink)
                .accessibilityAddTraits(.isHeader)
            if let detail {
                detail.font(.subheadline).foregroundStyle(IndexTheme.muted)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct IndexStatus: View {
    enum Kind: Equatable { case empty, loading, failure, success }

    let kind: Kind
    let title: Text
    var detail: Text? = nil

    var body: some View {
        HStack(alignment: .top, spacing: Theme.space3) {
            switch kind {
            case .loading: ProgressView().tint(IndexTheme.accent).accessibilityHidden(true)
            case .failure: ThemeIcon(symbol: Icon.warning).foregroundStyle(IndexTheme.danger).accessibilityHidden(true)
            case .success: ThemeIcon(symbol: Icon.markRead).foregroundStyle(IndexTheme.accent).accessibilityHidden(true)
            case .empty: EmptyView()
            }
            VStack(alignment: .leading, spacing: Theme.space1) {
                title.font(.headline).foregroundStyle(kind == .failure ? IndexTheme.danger : IndexTheme.ink)
                if let detail { detail.font(.subheadline).foregroundStyle(IndexTheme.muted) }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.space3)
        .indexPanel(fill: kind == .failure ? IndexTheme.dangerWash : IndexTheme.wash)
        .accessibilityElement(children: .combine)
    }
}

struct IndexRowLabel: View {
    let title: Text
    var detail: Text? = nil
    var symbol: String? = nil
    var disclosure = false

    var body: some View {
        HStack(spacing: Theme.space3) {
            if let symbol {
                ThemeIcon(symbol: symbol, size: 18).foregroundStyle(IndexTheme.accent)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: Theme.space1) {
                title.font(.body.weight(.medium)).foregroundStyle(IndexTheme.ink)
                if let detail { detail.font(.caption).foregroundStyle(IndexTheme.muted) }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            if disclosure {
                ThemeIcon(symbol: Icon.disclosure, size: 12).foregroundStyle(IndexTheme.muted)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, Theme.space2)
        .frame(minHeight: Theme.rowMinHeight)
        .contentShape(Rectangle())
    }
}

struct IndexPage<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.space4) { content }
                .padding(.horizontal, Theme.space4).padding(.vertical, Theme.space4)
                .frame(maxWidth: Theme.pageWidth).frame(maxWidth: .infinity)
        }
        .background(IndexTheme.canvas.ignoresSafeArea())
        .foregroundStyle(IndexTheme.ink)
    }
}

struct IndexMetric: View {
    let value: Text
    let label: Text
    var large = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.space1) {
            label.font(.caption).foregroundStyle(IndexTheme.muted)
            value.font(IndexTheme.editorial(large ? 34 : 22, relativeTo: large ? .largeTitle : .title2))
                .monospacedDigit().foregroundStyle(IndexTheme.ink)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct IndexBottomBar<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            IndexRule()
            content.padding(.horizontal, Theme.space4).padding(.vertical, Theme.space2)
                .frame(maxWidth: Theme.pageWidth).frame(maxWidth: .infinity)
        }
        .background(IndexTheme.surface)
    }
}

struct IndexScopePicker<Option: Hashable>: View {
    let options: [Option]
    let selection: Option
    let title: (Option) -> Text
    let onSelect: (Option) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.space1))
            : AnyLayout(HStackLayout(spacing: Theme.space1))
        layout {
            ForEach(options, id: \.self) { option in
                Button { onSelect(option) } label: {
                    title(option)
                        .font(.subheadline.weight(option == selection ? .semibold : .medium))
                        .foregroundStyle(option == selection ? IndexTheme.accent : IndexTheme.muted)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, Theme.space2).padding(.vertical, Theme.space1)
                        .frame(maxWidth: .infinity, minHeight: Theme.iconButtonSize)
                        .background(option == selection ? IndexTheme.surface : .clear,
                                    in: RoundedRectangle(cornerRadius: IndexTheme.controlRadius - 4, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressButtonStyle())
                .accessibilityAddTraits(option == selection ? .isSelected : [])
            }
        }
        .padding(Theme.space1)
        .background(IndexTheme.wash, in: RoundedRectangle(cornerRadius: IndexTheme.controlRadius, style: .continuous))
    }
}

struct IndexActionStyle: ButtonStyle {
    enum Role: Equatable { case primary, secondary, plain }

    var role: Role = .plain
    var expands = false
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: IndexTheme.controlRadius)
        let primary = role == .primary
        let outlined = role == .secondary
        let fill: Color = primary ? IndexTheme.accent : (outlined ? IndexTheme.surface : .clear)
        let opacity = configuration.isPressed ? Theme.pressedOpacity : 1
        return configuration.label
            .font(.subheadline.weight(.semibold))
            .multilineTextAlignment(.center)
            .padding(.horizontal, Theme.space3)
            .padding(.vertical, Theme.space1)
            .frame(minWidth: Theme.iconButtonSize, maxWidth: expands ? .infinity : nil,
                   minHeight: primary ? IndexTheme.actionHeight : Theme.iconButtonSize)
            .foregroundStyle(primary ? IndexTheme.onAccent : (outlined ? IndexTheme.ink : IndexTheme.accent))
            .background(fill, in: shape)
            .overlay {
                if outlined {
                    shape.strokeBorder(IndexTheme.rule, lineWidth: Theme.rule).allowsHitTesting(false)
                }
            }
            .contentShape(shape)
            .opacity(enabled ? opacity : Theme.disabledOpacity)
            .animation(IndexTheme.press, value: configuration.isPressed)
            .respectReducedMotion()
    }
}

extension View {
    func indexList() -> some View {
        listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(IndexTheme.canvas.ignoresSafeArea())
            .tint(IndexTheme.accent)
    }

    func indexPanel(fill: Color = IndexTheme.surface) -> some View {
        let shape = RoundedRectangle(cornerRadius: IndexTheme.panelRadius, style: .continuous)
        return background(fill, in: shape)
            .overlay { shape.strokeBorder(IndexTheme.rule, lineWidth: Theme.hairline).allowsHitTesting(false) }
            .softCardShadow()
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

/// 夜间直接返回内容，描边由卡片/浮层表面负责。
struct SoftCardShadow: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    func body(content: Content) -> some View {
        if colorScheme == .dark { content }
        else { content.shadow(color: .black.opacity(0.03), radius: 24, x: 0, y: 6) }
    }
}

private struct FloatingPanelShadow: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    func body(content: Content) -> some View {
        if colorScheme == .dark { content }
        else { content.shadow(color: .black.opacity(0.06), radius: 20, x: 0, y: 8) }
    }
}

// MARK: - 状态标签组件

struct SealBadge: View {
    let text: String
    var color: Color = Theme.accent
    var background: Color? = nil
    /// 保留旧参数兼容；v31 状态签统一淡底。
    var filled: Bool = false
    var body: some View {
        Text(L(text))
            .font(Theme.sans(11))
            .foregroundStyle(color)
            .padding(.horizontal, Theme.space2)
            .padding(.vertical, Theme.space1)
            .background(background ?? Theme.accentSoft, in: RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
    }
}

// MARK: - 按钮（温润圆角，主次明确）

/// 主操作是窗蓝实底。日间用深窗蓝配浅字，夜间用浅窗蓝配深字。
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var height: CGFloat = Theme.buttonHeight
    var fill: Color = Theme.accent
    var foreground: Color = Theme.onAccent
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
            .contentShape(RoundedRectangle(cornerRadius: Theme.buttonRadius))
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
            .foregroundStyle(Theme.ink)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.buttonRadius, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: Theme.buttonRadius).strokeBorder(Theme.line, lineWidth: Theme.rule) }
            .modifier(PressFeedback(pressed: configuration.isPressed))
            .contentShape(RoundedRectangle(cornerRadius: Theme.buttonRadius))
            .opacity(isEnabled ? 1 : Theme.disabledOpacity)
    }
}

/// 历史签名兼容壳，避免给内容重复添加表面。
struct GlassSkin: ViewModifier {
    var interactive = false
    var shape: AnyShape = AnyShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    func body(content: Content) -> some View { content }
}

/// 胶囊选中墨底纸字，未选卡面与发丝线；勾号提供形状状态通道。
struct ChipPillStyle: ButtonStyle {
    var selected: Bool
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Theme.space1) {
            if selected { Image(systemName: Icon.checkmark).accessibilityHidden(true) }
            configuration.label
        }
        .font(Theme.sans(15, weight: .medium))
        .foregroundStyle(selected ? Theme.accent : Theme.ink2)
        .padding(.horizontal, Theme.space3)
        .frame(minHeight: Theme.iconButtonSize)
        .background(selected ? Theme.accentSoft : Theme.surface, in: Capsule())
        .overlay { Capsule().strokeBorder(selected ? Color.clear : Theme.line, lineWidth: Theme.rule) }
        .contentShape(Capsule())
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
        ThemeIcon(symbol: systemName, size: 20, weight: .medium)
            .foregroundStyle(color)
            .frame(width: 36, height: 36)
            .background(Theme.surface2, in: RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
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

/// 纸质栏目标题：宽字距眉题（可带编号），陶土。
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
        HStack(alignment: .firstTextBaseline, spacing: Theme.space2) {
            if let number { Text(number).mastheadStyle().foregroundStyle(Theme.accent) }
            Text(L(text)).font(.title3.weight(.semibold)).foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let badge { SealBadge(text: badge) }
            if rule { Rectangle().fill(Theme.line).frame(height: 1).accessibilityHidden(true) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// 兼容既有调用点的 Masthead 外观。
struct PageMasthead: View {
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
            if kicker != nil || issue != nil || actionTitle != nil {
                HStack {
                    if let kicker { Text(L(kicker)).foregroundStyle(Theme.accent) }
                    Spacer()
                    if let issue { Text(L(issue)).foregroundStyle(Theme.ink2) }
                    if let actionTitle, let action { TextButton(actionTitle, action: action) }
                }
                .mastheadStyle()
            }
            Text(L(title))
                .scaledFont(titleSize, weight: .bold, relativeTo: .largeTitle)
                .lineSpacing(titleSize * 0.2)
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
    var value: Double
    var track: Color = Theme.line
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
    var usesIndexPalette = false
    init(title: String, color: String = "ink", author: String = "", data: Data? = nil, image: UIImage? = nil,
         width: CGFloat = 98, usesIndexPalette: Bool = false) {
        self.title = title; self.color = color; self.author = author; self.width = width
        self.image = image ?? data.flatMap(UIImage.init(data:))
        self.usesIndexPalette = usesIndexPalette
    }
    private var paper: Color { usesIndexPalette ? IndexTheme.wash : Theme.coverColor(color) }
    var body: some View {
        let fg = usesIndexPalette ? IndexTheme.ink : Theme.coverForeground(color)
        let radius = usesIndexPalette ? IndexTheme.coverRadius : Theme.coverRadius(width)
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFit().background(usesIndexPalette ? IndexTheme.wash : Theme.surface2)
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
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: radius)
                .strokeBorder(usesIndexPalette ? IndexTheme.rule : Theme.line, lineWidth: Theme.hairline)
                .allowsHitTesting(false)
        }
        .overlay {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .inset(by: Theme.hairline)
                .strokeBorder(Color.white.opacity(0.35), lineWidth: Theme.rule)
                .allowsHitTesting(false)
        }
        .accessibilityElement()
        .accessibilityLabel("《\(title)》封面")
    }
    private func tinyPlaceholder(_ fg: Color) -> some View {
        ZStack(alignment: .leading) {
            paper
            Text(L(title))
                .font(.system(size: max(8, width * 0.17), weight: .semibold)).serifEmbolden(max(8, width * 0.17))
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
            paper
            VStack(alignment: .leading, spacing: 0) {
                Text(L(title))
                    .font(.system(size: titleSize, weight: .semibold)).foregroundStyle(fg).serifEmbolden(titleSize)
                    .lineLimit(3).minimumScaleFactor(0.72).multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if width >= 72 && !author.isEmpty {
                    Text(author).font(.system(size: max(8, width * 0.075)))
                        .foregroundStyle(fg.opacity(0.75)).lineLimit(1)
                        .padding(.top, max(3, width * 0.04))
                }
                Spacer(minLength: 0)
                Rectangle().fill(fg).frame(height: 1).accessibilityHidden(true)
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
    var usesIndexPalette = false
    var body: some View {
        Color.clear.aspectRatio(0.75, contentMode: .fit).overlay {
            GeometryReader { geo in
                BookCoverView(title: title, color: color, author: author, image: image,
                              width: geo.size.width, usesIndexPalette: usesIndexPalette)
            }
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
        HStack(alignment: .firstTextBaseline, spacing: Theme.space3) {
            Text(L(title)).font(.title3.weight(.semibold))
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
                            Image(systemName: Icon.checkmark).accessibilityHidden(true)
                        }
                        Text(L(title(option))).fixedSize(horizontal: false, vertical: true)
                    }
                    .font(Theme.sans(13)).foregroundStyle(Theme.ink)
                    .padding(.horizontal, Theme.space2)
                    .frame(maxWidth: .infinity, minHeight: Theme.iconButtonSize)
                    .background(option == selection ? Theme.surface : .clear,
                                in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
                    .overlay {
                        if option == selection {
                            RoundedRectangle(cornerRadius: Theme.radiusSmall)
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
        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: Theme.radiusField))
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
                Text(L(title)).font(.title3.weight(.semibold)).foregroundStyle(Theme.ink)
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
            Text(L(title)).font(.title2.weight(.semibold)).foregroundStyle(Theme.ink)
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
        var highlight: UInt32 { isDark ? 0x1A2C44 : 0xE3EDF8 }
        var accent: UInt32 { isDark ? 0xA9C9F2 : 0x163E73 }
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
                Text(L(eyebrow)).mastheadStyle(color: Theme.accent).foregroundStyle(Theme.accent)
            }
            Text(L(title)).scaledFont(28, weight: .bold, relativeTo: .title).foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
            if let detail {
                Text(L(detail)).font(Theme.sans(13)).foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Rectangle().fill(Theme.line).frame(height: 1).padding(.top, 6).accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
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
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius))
            .overlay { RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.line, lineWidth: contrast == .increased ? Theme.ruleMedium : Theme.rule) }
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
