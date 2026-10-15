import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// 听页图标 v7 ·「一页成声」（Design/v7-yiye）：左边一页书，右边的书页化成四道声波——读听一体。
// 用法: swift render-app-icon-v7.swift <out-dir>
// 生成 AppIcon.png（靛蓝底 + 宣纸白书页与声波）/ AppIcon-dark.png（暖黑底 + 提亮靛蓝）/ AppIcon-tinted.png（灰阶，供系统着色）。
let size = 1024
let outDir = CommandLine.arguments[1]

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

struct Palette {
    let bgTop: UInt32, bgBottom: UInt32
    let ink: UInt32            // 书页与声波
    let line: UInt32, lineAlpha: CGFloat
    let shadowAlpha: CGFloat
}

let variants: [String: Palette] = [
    "AppIcon": Palette(bgTop: 0x3A5B92, bgBottom: 0x22385E, ink: 0xF5F4F0, line: 0x2F4C7D, lineAlpha: 0.32, shadowAlpha: 0.28),
    "AppIcon-dark": Palette(bgTop: 0x1C1C1A, bgBottom: 0x0F0F0E, ink: 0x9DB4E0, line: 0x0F0F0E, lineAlpha: 0.45, shadowAlpha: 0.5),
    "AppIcon-tinted": Palette(bgTop: 0x1A1A1A, bgBottom: 0x000000, ink: 0xDADADA, line: 0x000000, lineAlpha: 0.4, shadowAlpha: 0.0),
]

for (name, p) in variants {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // 使用 SVG 坐标（y 向下），整组向左平移 20 使图形居中
    ctx.translateBy(x: 0, y: CGFloat(size)); ctx.scaleBy(x: 1, y: -1)

    let gradient = CGGradient(colorsSpace: space, colors: [rgb(p.bgTop), rgb(p.bgBottom)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: CGFloat(size)), options: [])

    ctx.translateBy(x: -20, y: 0)
    if p.shadowAlpha > 0 {
        ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 40, color: rgb(0x000000, p.shadowAlpha))
    }
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)

    // 左页：书脊在右，外缘微弯
    let page = CGMutablePath()
    page.move(to: CGPoint(x: 512, y: 300))
    page.addCurve(to: CGPoint(x: 220, y: 262), control1: CGPoint(x: 430, y: 250), control2: CGPoint(x: 300, y: 240))
    page.addLine(to: CGPoint(x: 220, y: 742))
    page.addCurve(to: CGPoint(x: 512, y: 780), control1: CGPoint(x: 300, y: 720), control2: CGPoint(x: 430, y: 730))
    page.closeSubpath()
    ctx.addPath(page); ctx.setFillColor(rgb(p.ink)); ctx.fillPath()

    // 右页化成声波：四道圆头竖条，由高到低渐隐
    let bars: [(x: CGFloat, y: CGFloat, h: CGFloat, a: CGFloat)] = [(560, 420, 200, 1), (640, 340, 360, 1), (720, 400, 240, 0.8), (800, 460, 120, 0.55)]
    for bar in bars {
        let rect = CGRect(x: bar.x, y: bar.y, width: 44, height: bar.h)
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 22, cornerHeight: 22, transform: nil))
        ctx.setFillColor(rgb(p.ink, bar.a)); ctx.fillPath()
    }
    ctx.endTransparencyLayer()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)

    // 页内文字行
    ctx.setStrokeColor(rgb(p.line, p.lineAlpha)); ctx.setLineWidth(22); ctx.setLineCap(.round)
    for (y, w) in [(CGFloat(380), CGFloat(150)), (450, 150), (520, 150), (590, 110)] {
        ctx.move(to: CGPoint(x: 290, y: y)); ctx.addLine(to: CGPoint(x: 290 + w, y: y))
    }
    ctx.strokePath()

    let image = ctx.makeImage()!
    let out = URL(fileURLWithPath: outDir).appendingPathComponent("\(name).png")
    let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
    print("wrote \(out.path)")
}
