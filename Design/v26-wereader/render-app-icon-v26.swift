import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

// 听页 · v26「微信读书风格」图标：极简单色。
// 纯色底 + 居中苹方粗「听」，无描边、无印章、无声弧、无字标，留白克制。
// 几何沿用 300 单位网格（×1024/300），三变体均为 1024² RGB 无 alpha。
// swift Design/v26-wereader/render-app-icon-v26.swift <输出目录>

let size = 1024
let k = CGFloat(size) / 300

func rgb(_ hex: UInt32) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

struct Variant { let file: String, field, glyph: UInt32 }
let variants: [Variant] = [
    Variant(file: "AppIcon.png", field: 0xFFFFFF, glyph: 0x1F1F1F),
    Variant(file: "AppIcon-dark.png", field: 0x141414, glyph: 0xF5F5F5),
    Variant(file: "AppIcon-tinted.png", field: 0x0A0A0A, glyph: 0xFFFFFF),
]

/// 在 y 向下的设计稿坐标里画一行字：x 为左缘，baseline 为基线。
func draw(_ ctx: CGContext, _ text: String, font: CTFont, color: CGColor, x: CGFloat, baseline: CGFloat) {
    let attrs: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
    ]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
    ctx.textPosition = CGPoint(x: x, y: CGFloat(size) - baseline)
    CTLineDraw(line, ctx)
}

func render(_ v: Variant, to url: URL) {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    let S = CGFloat(size)
    // 纯色满版底
    ctx.setFillColor(rgb(v.field)); ctx.fill(CGRect(x: 0, y: 0, width: S, height: S))
    // 居中苹方粗「听」：160 单位字号
    let glyphFont = CTFontCreateWithName("PingFangSC-Semibold" as CFString, 160 * k, nil)
    draw(ctx, "听", font: glyphFont, color: rgb(v.glyph), x: 70 * k, baseline: 208 * k)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(dest)
    print("rendered", url.path)
}

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Design/v26-wereader/out")
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
for v in variants { render(v, to: out.appendingPathComponent(v.file)) }
