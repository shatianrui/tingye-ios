import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

// 听页 · v25「墨青 · 靛蓝书卷」图标：蓝印线描式封面。
// 靛蓝满版底 + 宣纸发丝线内框 + 宋体特粗宣纸「听」+ 右上三道蓝印声弧 + 左下铜金印章（听）+ TINGYE 字标。
// 几何沿用 300 单位网格（×1024/300），三变体均为 1024² RGB 无 alpha。
// swift Design/v25-moqing/render-app-icon-v25.swift <输出目录>

let size = 1024
let k = CGFloat(size) / 300

func rgb(_ hex: UInt32) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

struct Variant { let file: String, field, frame, glyph, seal, sealInk, ink: UInt32 }
let variants: [Variant] = [
    Variant(file: "AppIcon.png", field: 0x2C4A6E, frame: 0xF7F5F0, glyph: 0xF7F5F0, seal: 0x96703A, sealInk: 0xF7F5F0, ink: 0xF7F5F0),
    Variant(file: "AppIcon-dark.png", field: 0x10151C, frame: 0x2E3947, glyph: 0x8FB0D1, seal: 0xC89B62, sealInk: 0x10151C, ink: 0xE3E7EC),
    Variant(file: "AppIcon-tinted.png", field: 0x0A0A0A, frame: 0x8C8C8C, glyph: 0xFFFFFF, seal: 0xE5E5E5, sealInk: 0x0A0A0A, ink: 0xBDBDBD),
]

func font(_ name: String, _ px: CGFloat) -> CTFont {
    let url = URL(fileURLWithPath: "/System/Library/Fonts/Supplemental/Songti.ttc") as CFURL
    if name.hasPrefix("STSongti"), let descs = CTFontManagerCreateFontDescriptorsFromURL(url) as? [CTFontDescriptor],
       let d = descs.first(where: { (CTFontDescriptorCopyAttribute($0, kCTFontNameAttribute) as? String) == name }) {
        return CTFontCreateWithFontDescriptor(d, px, nil)
    }
    return CTFontCreateWithName(name as CFString, px, nil)
}

/// 在 y 向下的设计稿坐标里画一行字：x 为左缘，baseline 为基线。
func draw(_ ctx: CGContext, _ text: String, font: CTFont, color: CGColor, x: CGFloat, baseline: CGFloat, kern: CGFloat = 0) {
    let attrs: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        NSAttributedString.Key(kCTKernAttributeName as String): kern,
    ]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
    ctx.textPosition = CGPoint(x: x, y: CGFloat(size) - baseline)
    CTLineDraw(line, ctx)
}

/// 设计稿坐标（y 向下）里的圆弧；转换为 CGContext 的 y 向上坐标。
func arc(_ ctx: CGContext, center: CGPoint, radius: CGFloat, from a0: CGFloat, to a1: CGFloat, color: CGColor, width: CGFloat) {
    let c = CGPoint(x: center.x, y: CGFloat(size) - center.y)
    ctx.setStrokeColor(color)
    ctx.setLineWidth(width)
    ctx.setLineCap(.round)
    ctx.addArc(center: c, radius: radius, startAngle: a0, endAngle: a1, clockwise: false)
    ctx.strokePath()
}

func render(_ v: Variant, to url: URL) {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    let S = CGFloat(size)
    // 靛蓝满版底
    ctx.setFillColor(rgb(v.field)); ctx.fill(CGRect(x: 0, y: 0, width: S, height: S))
    // 宣纸发丝线内框（蓝印线描）
    let inset = 20 * k
    ctx.setStrokeColor(rgb(v.frame)); ctx.setLineWidth(1.5 * k)
    ctx.stroke(CGRect(x: inset, y: inset, width: S - inset * 2, height: S - inset * 2))
    // 右上三道蓝印声弧：自「听」字右上角发出
    let center = CGPoint(x: 212 * k, y: 86 * k)
    for r in [18, 30, 42] { arc(ctx, center: center, radius: CGFloat(r) * k, from: -.pi / 18, to: 8 * .pi / 18, color: rgb(v.glyph), width: 3.5 * k) }
    // 宋体特粗「听」：150 单位字号，基线 196
    draw(ctx, "听", font: font("STSongti-SC-Black", 150 * k), color: rgb(v.glyph), x: 42 * k, baseline: 196 * k)
    // 左下铜金印章：42 单位见方，内嵌白文「听」
    let sealRect = CGRect(x: 42 * k, y: S - 262 * k, width: 42 * k, height: 42 * k)
    ctx.setFillColor(rgb(v.seal)); ctx.fill(sealRect)
    draw(ctx, "听", font: font("STSongti-SC-Black", 28 * k), color: rgb(v.sealInk), x: 49 * k, baseline: 251 * k)
    // TINGYE 字标
    draw(ctx, "TINGYE", font: font("HelveticaNeue-CondensedBlack", 24 * k), color: rgb(v.ink), x: 150 * k, baseline: 252 * k, kern: 7.5 * k)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(dest)
    print("rendered", url.path)
}

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Design/v25-moqing/out")
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
for v in variants { render(v, to: out.appendingPathComponent(v.file)) }
