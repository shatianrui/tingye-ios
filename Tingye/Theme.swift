import SwiftUI
import UIKit
import CoreImage

/// 听页 · 刊（Editorial）。纸白底、墨黑字、粗墨线分栏；每本书一块纯色封面；大号压缩体数字。
/// 颜色只有三种角色：墨（结构与主按钮）、信号红（每屏一个重点）、荧光黄（正在朗读）。
/// 设计稿：Figma「听页 · 刊 Editorial 重设计」，令牌与变量集合「听页 · 刊」一一对应。
enum Theme {
    static let bg = dynamic(0xF3F0E8, 0x141311)
    static let surface = dynamic(0xFFFFFF, 0x1E1D1A)
    static let surface2 = dynamic(0xE7E3D8, 0x2A2825)
    static let ink = dynamic(0x111111, 0xF3F0E8)
    static let ink2 = dynamic(0x4D4A44, 0xB9B4AA)
    static let ink3 = dynamic(0x6E6A62, 0x8F8A80)
    /// 发丝线：行与行之间。
    static let line = dynamic(0xD9D4C8, 0x33312D)
    /// 墨底上的字（日间纸色，夜间墨色）。
    static let onInk = dynamic(0xF3F0E8, 0x111111)
    static let cardEdge = line
    /// 信号红：每屏一个重点（主操作、选中、进度重点）。
    static let accent = dynamic(0xE63A1E, 0xFF5A3C)
    static let accentSoft = dynamic(0xFBE1DA, 0x3A1A13)
    static let onAccent = dynamic(0xFFFFFF, 0x141311)
    /// 荧光黄：正在朗读、摘句。上面的字永远是墨色。
    static let marker = dynamic(0xFFE24A, 0xE6C845)
    static let onMarker = Color(hex: 0x111111)
    static let forest = Color(hex: 0x111111)
    static let onForest = Color(hex: 0xF3F0E8)
    static let wash = accent.opacity(0.14)
    static let danger = dynamic(0xC4301B, 0xFF7A5C)
    static let gold = dynamic(0xB8860B, 0xF2C14E)
    static let goldSoft = dynamic(0xF6EBC9, 0x3A3120)
    static let jade = dynamic(0x1FA971, 0x4FD1A1)
    static let jadeSoft = dynamic(0xDDF2E8, 0x10291F)
    static let indigo = dynamic(0x2F55F2, 0x8FA5FF)
    static let indigoSoft = dynamic(0xE3E8FD, 0x1D2547)
    static let ochre = dynamic(0xE08A12, 0xF2A64C)
    static let plum = dynamic(0x7B4DFF, 0xB79BFF)
    static let amberOnDark = Color(hex: 0xFFE24A)

    static let auroraGradient = LinearGradient(colors: [accent, accent], startPoint: .top, endPoint: .bottom)
    static let accentGradient = auroraGradient

    static let inset: CGFloat = 20
    static let pageWidth: CGFloat = 720
    static let radius: CGFloat = 6
    static let radiusSmall: CGFloat = 6
    static let buttonRadius: CGFloat = 10
    static let buttonHeight: CGFloat = 48
    static let iconButtonSize: CGFloat = 44
    /// 刊头粗线与区块线。
    static let ruleHeavy: CGFloat = 3
    static let rule: CGFloat = 2

    // MARK: - 动效

    static let pressSpring = Animation.spring(response: 0.28, dampingFraction: 0.72)
    static let smoothSpring = Animation.spring(response: 0.42, dampingFraction: 0.86)

    // MARK: - 字体：书名与正文用思源宋体；界面用系统字体；数字用系统压缩黑体

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
    /// 大号数字：系统黑体压缩字宽（Figma 中以 Barlow Condensed Black 示意）。
    static func display(_ size: CGFloat, relativeTo style: Font.TextStyle = .largeTitle) -> Font {
        .system(size: size, weight: .black).width(.compressed)
    }
    /// 眉题：小号粗体、加字距。
    static let kicker = Font.system(size: 11, weight: .bold)
    /// 页标题与刊头：系统黑体。
    static func headline(_ size: CGFloat) -> Font { .system(size: size, weight: .black) }

    // MARK: - 封面色块（番茄 / 克莱因蓝 / 柠檬 / 薄荷 / 紫 / 墨）

    static func coverColor(_ color: String) -> Color { Color(uiColor: coverUIColor(color)) }
    static func coverUIColor(_ color: String) -> UIColor {
        switch color {
        case "ochre", "gold", "cream": UIColor(hex: 0xFFC933)
        case "blue": UIColor(hex: 0x2F55F2)
        case "red", "vermilion": UIColor(hex: 0xF2552C)
        case "purple": UIColor(hex: 0x7B4DFF)
        case "green": UIColor(hex: 0x1FA971)
        case "ink": UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: 0x2C2B28) : UIColor(hex: 0x1E1E1E) }
        default: UIColor(hex: 0xFFC933)
        }
    }
    /// 封面色块上的字：柠檬黄上用墨色，其余用白色。
    static func coverForeground(_ color: String) -> Color {
        ["ochre", "gold", "cream", ""].contains(color) || !["blue", "red", "vermilion", "purple", "green", "ink"].contains(color) ? Color(hex: 0x111111) : .white
    }

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

// MARK: - 层次：没有玻璃，只有纸、墨线和色块

extension View {
    /// 悬浮控件统一表面：纸色实底 + 1.5pt 墨线（不再用玻璃）。
    func glassSurface(in shape: AnyShape, interactive: Bool = false) -> some View {
        self
            .background(Theme.bg, in: shape)
            .overlay(shape.stroke(Theme.ink, lineWidth: 1.5))
    }

    /// 内容卡片：白纸（夜间炭灰）、6pt 小圆角、发丝边，无投影。
    func glassCard(cornerRadius: CGFloat = Theme.radius, interactive: Bool = false) -> some View {
        self
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
    }

    /// 浮在内容上的操作条：纸底 + 墨线框。
    func floatingPanel(cornerRadius: CGFloat = Theme.radius) -> some View {
        self
            .background(Theme.bg, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(Theme.ink, lineWidth: 1.5))
    }

    func glassSurface(in shape: Capsule, interactive: Bool = false) -> some View {
        glassSurface(in: AnyShape(RoundedRectangle(cornerRadius: Theme.buttonRadius, style: .continuous)), interactive: interactive)
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

    /// 荧光笔高亮：正在朗读的句子与摘句。
    func markerHighlight() -> some View {
        self
            .foregroundStyle(Theme.onMarker)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(Theme.marker)
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

/// 状态标签：信号红细框小字。
struct SealBadge: View {
    let text: String
    var color: Color = Theme.accent
    var background: Color? = nil
    var filled: Bool = false
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(filled ? Theme.onAccent : color)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(background ?? (filled ? color : Color.clear), in: RoundedRectangle(cornerRadius: 3))
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(filled || background != nil ? Color.clear : color, lineWidth: 1))
    }
}

// MARK: - 按钮（10pt 圆角矩形，不用胶囊）

/// 主按钮：墨底纸色字。传 `fill: Theme.accent, foreground: Theme.onAccent` 得到信号红强调按钮（每屏最多一个）。
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var height: CGFloat = Theme.buttonHeight
    var fill: Color = Theme.ink
    var foreground: Color = Theme.onInk
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .bold))
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, minHeight: height)
            .foregroundStyle(foreground)
            .background(fill, in: RoundedRectangle(cornerRadius: Theme.buttonRadius, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(Theme.pressSpring, value: configuration.isPressed)
            .contentShape(RoundedRectangle(cornerRadius: Theme.buttonRadius))
            .opacity(isEnabled ? 1 : 0.4)
    }
}

/// 次要按钮：1.5pt 墨线描边；emphasized 用信号红描边。
struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var height: CGFloat = Theme.buttonHeight
    var emphasized = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .bold))
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, minHeight: height)
            .foregroundStyle(emphasized ? Theme.accent : Theme.ink)
            .background(configuration.isPressed ? Theme.surface2 : Color.clear, in: RoundedRectangle(cornerRadius: Theme.buttonRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.buttonRadius, style: .continuous).strokeBorder(emphasized ? Theme.accent : Theme.ink, lineWidth: 1.5))
            .animation(Theme.pressSpring, value: configuration.isPressed)
            .contentShape(RoundedRectangle(cornerRadius: Theme.buttonRadius))
            .opacity(isEnabled ? 1 : 0.4)
    }
}

/// 旧版玻璃皮肤的兼容壳：刊版不用玻璃，原样返回。
struct GlassSkin: ViewModifier {
    var interactive = false
    var shape: AnyShape = AnyShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    func body(content: Content) -> some View { content }
}

/// 筛选 / 分段：选中为墨色粗体 + 信号红短横，未选为弱化灰字。
struct ChipPillStyle: ButtonStyle {
    var selected: Bool
    func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: 5) {
            configuration.label
                .font(.system(size: 15, weight: selected ? .bold : .medium))
                .lineLimit(1)
                .foregroundStyle(selected ? Theme.ink : Theme.ink3)
            Rectangle().fill(Theme.accent).frame(width: 22, height: 3).opacity(selected ? 1 : 0)
        }
        .padding(.horizontal, 4)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// 方形图标按钮：1.5pt 墨线框。
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
                .overlay(RoundedRectangle(cornerRadius: Theme.buttonRadius, style: .continuous).strokeBorder(Theme.ink, lineWidth: 1.5))
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
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
        HStack(spacing: 6) {
            Image(systemName: on ? Icon.listening : Icon.playback(false))
                .symbolEffect(.variableColor.iterative, isActive: on)
            if title { Text(on ? "正在听" : "听书") }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(on ? "打开播放器" : "开始听书")
    }
}

/// 统一按压反馈：轻缩 + 微透明。
struct PressButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.96
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
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

/// 内容卡：白纸、小圆角、发丝边。
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
                Text(title).font(.system(size: 15, weight: .medium)).foregroundStyle(destructive ? Theme.danger : Theme.ink)
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
        Rectangle().fill(Theme.line).frame(height: 1).padding(.leading, inset)
    }
}

/// 墨线：刊头 3pt、区块 2pt。
struct InkRule: View {
    var height: CGFloat = Theme.rule
    var color: Color = Theme.ink
    var body: some View { Rectangle().fill(color).frame(height: height).accessibilityHidden(true) }
}

/// 杂志式区块标题：2pt 墨线 + 信号红编号 + 粗黑标题，可带右侧链接。
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
        VStack(alignment: .leading, spacing: 10) {
            if rule { InkRule() }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                if let number {
                    Text(number).font(Theme.kicker).tracking(1.2).foregroundStyle(Theme.accent).monospacedDigit()
                }
                Text(text)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Theme.ink)
                if let badge { SealBadge(text: badge) }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// 各主页面共用的页眉：系统黑体大标题 + 一行说明 + 3pt 刊头线。
struct PageMasthead: View {
    let title: String
    var subtitle: String? = nil
    var rule = true
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Theme.headline(32))
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

/// 进度条：直角，墨色。
struct ProgressBar: View {
    var value: Double
    var track: Color = Theme.line
    var tint: Color = Theme.ink
    var height: CGFloat = 4
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(track)
                Rectangle().fill(tint).frame(width: max(0, min(1, value)) * geo.size.width)
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel("进度")
        .accessibilityValue("\(Int((value * 100).rounded()))%")
    }
}

// MARK: - 封面色块

/// 无图封面：纯色色块 + 细线眉题 + 宋体粗书名 + 作者。有封面图时整块替换为图片。
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
    var body: some View {
        let fg = Theme.coverForeground(color)
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ZStack(alignment: .topLeading) {
                    Theme.coverColor(color)
                    VStack(alignment: .leading, spacing: max(3, width * 0.05)) {
                        if width >= 72 {
                            Text("听页 · 文库")
                                .font(.system(size: max(6, width * 0.07), weight: .bold))
                                .tracking(0.8)
                                .foregroundStyle(fg.opacity(0.85))
                                .lineLimit(1)
                        }
                        if width >= 44 {
                            Rectangle().fill(fg.opacity(0.85)).frame(height: max(1, width * 0.013))
                        }
                        Text(title)
                            .font(Theme.serifBold(min(44, max(9, width * 0.23))))
                            .foregroundStyle(fg)
                            .lineLimit(width < 44 ? 2 : 3)
                            .minimumScaleFactor(0.6)
                        Spacer(minLength: 2)
                        if width >= 58 && !author.isEmpty {
                            Text(author)
                                .font(.system(size: max(8, width * 0.09)))
                                .foregroundStyle(fg.opacity(0.85))
                                .lineLimit(1)
                        }
                    }
                    .padding(width * 0.09)
                    .frame(width: width, height: width / 0.7, alignment: .topLeading)
                }
            }
        }
        .frame(width: width, height: width / 0.7)
        .clipShape(RoundedRectangle(cornerRadius: min(4, width * 0.04), style: .continuous))
        .accessibilityElement()
        .accessibilityLabel("《\(title)》封面")
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
            if let average { Color(uiColor: average.adjusted(brightness: -0.12, saturation: 1.1)) } else { Theme.coverColor(color) }
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
        ["paper": "刊纸", "mist": "雾灰", "ancient": "旧书", "eink": "浅灰", "white": "纯白", "blue": "深蓝", "night": "夜读"][rawValue] ?? rawValue
    }
    var swatch: Color {
        switch self {
        case .paper:   Color(hex: 0xF3F0E8)
        case .mist:    Color(hex: 0xE6EBF1)
        case .ancient: Color(hex: 0xF3E7D6)
        case .eink:    Color(hex: 0xF0F0F0)
        case .white:   Color(hex: 0xFFFFFF)
        case .blue:    Color(hex: 0x1A2C3A)
        case .night:   Color(hex: 0x141311)
        }
    }
    var dark: Bool { self == .blue || self == .night }
    static let xuan = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: 0x141311) : UIColor(hex: 0xF3F0E8) })
    static let xuanSecondary = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: 0x8F8A80) : UIColor(hex: 0x6E6A62) })
}

struct ReaderPreferences: Equatable {
    var fontSize: Double = 19
    var lineSpacing: Double = 11
    var font = "serif"
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
    /// 宣纸跟随 App 外观：浅色为暖宣纸，深色为石墨暖黑
    var background: Color { paper == "paper" ? ReaderPaper.xuan : kind.swatch }
    var foreground: Color {
        switch kind {
        case .mist:    return Color(hex: 0x14181F)
        case .ancient: return Color(hex: 0x2C2418)
        case .eink:    return Color(hex: 0x242424)
        case .white:   return Color(hex: 0x14181F)
        case .blue:    return Color(hex: 0xD5E4F0)
        case .night:   return Color(hex: 0xF3F0E8)
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
        case .night:   return Color(hex: 0x8F8A80)
        case .paper:   return ReaderPaper.xuanSecondary
        }
    }
    /// 朗读高亮的基色：荧光黄（深纸略暗）。
    /// 分页模式按行画「浅底 + 下划线」（CoreTextPageView），原书图文取半透明。
    var highlightBand: UIColor {
        if kind.dark { return UIColor(hex: 0xE6C845) }
        if kind == .paper { return UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: 0xE6C845) : UIColor(hex: 0xF5C800) } }
        return UIColor(hex: 0xF5C800)
    }
    /// 连续滚动模式整句铺底：荧光黄
    var highlight: UIColor {
        let band = highlightBand, darkPaper = kind.dark
        return UIColor { band.resolvedColor(with: $0).withAlphaComponent($0.userInterfaceStyle == .dark || darkPaper ? 0.26 : 0.55) }
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
