import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

// 听页 · v23「刊红」图标：时代杂志式红框封面。
// 刊红边框 + 白底（深色版墨底）+ 宋体特粗红「听」+ 右上 45° 角带 + 底部粗线与 TINGYE 字标。
// 几何沿用设计稿 300 单位网格（×1024/300），三变体均为 1024² RGB 无 alpha。
// swift Design/v23-time/icon/render-app-icon-v23.swift <输出目录>

let size = 1024
let k = CGFloat(size) / 300

func rgb(_ hex: UInt32) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

struct Variant { let file: String; let frame, field, glyph, sash, ink: UInt32 }
let variants = [
    Variant(file: "AppIcon.png", frame: 0xD6001C, field: 0xFFFFFF, glyph: 0xD6001C, sash: 0x111111, ink: 0x111111),
    Variant(file: "AppIcon-dark.png", frame: 0xD6001C, field: 0x111111, glyph: 0xD6001C, sash: 0xFFFFFF, ink: 0xFFFFFF),
    Variant(file: "AppIcon-tinted.png", frame: 0x8C8C8C, field: 0x0A0A0A, glyph: 0xFFFFFF, sash: 0x8C8C8C, ink: 0xBDBDBD),
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

func render(_ v: Variant, to url: URL) {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    let S = CGFloat(size)
    ctx.setFillColor(rgb(v.frame)); ctx.fill(CGRect(x: 0, y: 0, width: S, height: S))
    // 封面内芯：四边 30 单位红框
    let inset = 30 * k, fieldSide = 240 * k
    let field = CGRect(x: inset, y: inset, width: fieldSide, height: fieldSide)
    ctx.setFillColor(rgb(v.field)); ctx.fill(field)
    ctx.saveGState(); ctx.clip(to: field)
    // 右上角带：170×26，中心在内芯 (201, 35)，顺时针 45°
    ctx.saveGState()
    ctx.translateBy(x: inset + 201 * k, y: S - (inset + 35 * k))
    ctx.rotate(by: -.pi / 4)
    ctx.setFillColor(rgb(v.sash)); ctx.fill(CGRect(x: -85 * k, y: -13 * k, width: 170 * k, height: 26 * k))
    ctx.restoreGState()
    // 宋体特粗「听」：172 单位字号，基线在内芯 165
    draw(ctx, "听", font: font("STSongti-SC-Black", 172 * k), color: rgb(v.glyph), x: inset + 14 * k, baseline: inset + 165 * k)
    // 底部 3 单位粗线 + TINGYE 字标
    ctx.setFillColor(rgb(v.ink))
    ctx.fill(CGRect(x: inset + 16 * k, y: S - (inset + 197 * k), width: 208 * k, height: 3 * k))
    draw(ctx, "TINGYE", font: font("HelveticaNeue-CondensedBlack", 24 * k), color: rgb(v.ink), x: inset + 16 * k, baseline: inset + 222 * k, kern: 7.5 * k)
    ctx.restoreGState()
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(dest)
    print("rendered", url.path)
}

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Design/v23-time/icon/out")
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
for v in variants { render(v, to: out.appendingPathComponent(v.file)) }
