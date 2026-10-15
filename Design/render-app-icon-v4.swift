import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// 听页图标 v4：赤陶底 + 象牙色翻开的书页，书脊上方两道声波（与 Design/redesign-v4/AppIcon.svg 同一几何）。
// 用法: swift render-app-icon-v4.swift <AppIcon.appiconset 目录>
// 生成 AppIcon.png（默认）、AppIcon-dark.png（深色）、AppIcon-tinted.png（着色，灰阶）。
let size = 1024
let outDir = CommandLine.arguments[1]

func rgb(_ hex: UInt32) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

/// SVG 坐标（y 向下）中的圆弧，经过顶点（-90°）从 a1 走到 a2。
func arc(_ path: CGMutablePath, center: CGPoint, radius: CGFloat, from a1: CGFloat, to a2: CGFloat) {
    let steps = 64
    for i in 0...steps {
        let a = a1 + (a2 - a1) * CGFloat(i) / CGFloat(steps)
        let p = CGPoint(x: center.x + radius * cos(a), y: center.y + radius * sin(a))
        i == 0 ? path.move(to: p) : path.addLine(to: p)
    }
}

/// 过两点 (50±half, y) 、向上鼓起的声波弧。
func wave(halfChord: CGFloat, y: CGFloat, radius: CGFloat) -> CGPath {
    let h = sqrt(radius * radius - halfChord * halfChord)
    let right = atan2(-h, halfChord)   // 右端点，约 -38°
    let path = CGMutablePath()
    arc(path, center: CGPoint(x: 50, y: y + h), radius: radius, from: -.pi - right, to: right)
    return path
}

func render(ground: UInt32, glyph: UInt32, name: String) throws {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.setFillColor(rgb(ground)); ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
    // 换成 SVG 的 y 向下坐标，再套用 translate(512 540) scale(9.2) translate(-50 -46)。
    ctx.translateBy(x: 0, y: CGFloat(size)); ctx.scaleBy(x: 1, y: -1)
    ctx.translateBy(x: 512, y: 540); ctx.scaleBy(x: 9.2, y: 9.2); ctx.translateBy(x: -50, y: -46)

    let left = CGMutablePath()
    left.move(to: CGPoint(x: 50, y: 76)); left.addCurve(to: CGPoint(x: 15, y: 72), control1: CGPoint(x: 40, y: 70), control2: CGPoint(x: 27, y: 69))
    left.addLine(to: CGPoint(x: 15, y: 36)); left.addCurve(to: CGPoint(x: 50, y: 40), control1: CGPoint(x: 27, y: 33), control2: CGPoint(x: 40, y: 34)); left.closeSubpath()
    var mirror = CGAffineTransform(translationX: 100, y: 0).scaledBy(x: -1, y: 1)
    let right = left.copy(using: &mirror)!
    ctx.setFillColor(rgb(glyph)); ctx.addPath(left); ctx.addPath(right); ctx.fillPath()

    ctx.setLineCap(.round)
    ctx.setStrokeColor(rgb(ground)); ctx.setLineWidth(2.4)
    ctx.move(to: CGPoint(x: 50, y: 41.5)); ctx.addLine(to: CGPoint(x: 50, y: 74.5)); ctx.strokePath()

    ctx.setStrokeColor(rgb(glyph)); ctx.setLineWidth(4.6)
    ctx.addPath(wave(halfChord: 7.5, y: 29, radius: 9.5)); ctx.strokePath()
    ctx.addPath(wave(halfChord: 14.5, y: 22, radius: 18)); ctx.strokePath()

    let url = URL(fileURLWithPath: outDir).appendingPathComponent(name)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    guard CGImageDestinationFinalize(dest) else { throw NSError(domain: "icon", code: 1) }
    print("wrote", url.path)
}

try render(ground: 0xD97757, glyph: 0xFAF9F5, name: "AppIcon.png")
try render(ground: 0x262420, glyph: 0xE08D70, name: "AppIcon-dark.png")
try render(ground: 0x000000, glyph: 0x9A9A9A, name: "AppIcon-tinted.png")
