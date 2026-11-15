import Foundation
import ReadiumNavigator

/// 所有单位换算集中在此；不读 UserDefaults，便于覆盖日夜/布局组合的纯函数测试。
enum ReadiumPreferencesBridge {
    static let cssBaseFontSize = 16.0
    static let basePageGutter = 24.0

    static func fontScale(_ points: Double) -> Double { points / cssBaseFontSize }
    /// 原生行框 = UIFont.lineHeight + lineSpacing；使用实际选用字体的 metrics。
    /// 传入 metrics 使映射保持纯函数，也避免把旧 WebKit 的 1.35 魔数当原生行高。
    static func lineHeight(fontSize: Double, lineSpacing: Double, fontLineHeight: Double) -> Double {
        max(1, (fontLineHeight + lineSpacing) / max(1, fontSize))
    }
    static func usesTwoColumns(_ prefs: ReaderPreferences, doublePage: Bool, viewportWidth: Double) -> Bool {
        doublePage && !prefs.scrolling && prefs.kind != .eink && viewportWidth > 650
    }
    static func preferences(_ prefs: ReaderPreferences, darkAppearance: Bool, alwaysLight: Bool,
                            doublePage: Bool, viewportWidth: Double, fixedLayout: Bool,
                            fontFamily: FontFamily, fontLineHeight: Double) -> EPUBPreferences {
        let palette = prefs.kind.resolve(darkAppearance: darkAppearance, alwaysLight: alwaysLight)
        let dual = usesTwoColumns(prefs, doublePage: doublePage, viewportWidth: viewportWidth)
        let background = ReadiumNavigator.Color(rawValue: Int(palette.background))
        // fixed-layout 不重排、不改字体和页内颜色；只设画布色和合成跨页。
        if fixedLayout {
            return EPUBPreferences(backgroundColor: background, spread: dual ? .always : .never)
        }
        return EPUBPreferences(
            backgroundColor: background,
            columnCount: dual ? .two : .one,
            fontFamily: fontFamily,
            fontSize: fontScale(prefs.fontSize),
            // 3.11.1 ReadiumCSS.update: letterSpacing -> CSSRemLength(value / 2)。
            // EPUBPreferences 会把负值钳制到 0；保留用户设置，EPUB 仅应用其支持的非负范围。
            letterSpacing: 2 * max(0, prefs.letterSpacing) / max(1, prefs.fontSize),
            lineHeight: lineHeight(fontSize: prefs.fontSize, lineSpacing: prefs.lineSpacing, fontLineHeight: fontLineHeight),
            pageMargins: prefs.margin / basePageGutter,
            paragraphIndent: prefs.indent ? 2 : 0,
            paragraphSpacing: prefs.paragraphSpacing / max(1, prefs.fontSize),
            publisherStyles: false,
            scroll: prefs.scrolling,
            textAlign: prefs.justified ? .justify : .start,
            textColor: ReadiumNavigator.Color(rawValue: Int(palette.foreground)),
            theme: palette.isDark ? .dark : .light
        )
    }
}
