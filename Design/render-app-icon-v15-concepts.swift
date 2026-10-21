import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import AppKit

// 听页 · 图标候选集（v15）。swift Design/render-app-icon-v15-concepts.swift <outdir>
// A 字：宋体「听」立骨；B 题签：宣纸竖签 + 青松印；C 山月：月下书脊极简；D 折页：页角化作播放三角
let outdir = CommandLine.arguments[1]
let size = 1024
func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: alpha)
}
let space = CGColorSpace(name: CGColorSpace.sRGB)!

func makeContext() -> CGContext {
    CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}
func save(_ ctx: CGContext, _ name: String) {
    let url = URL(fileURLWithPath: outdir).appendingPathComponent(name)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(dest)
    print(url.path)
}
func pineGradient(_ ctx: CGContext) {
    let g = CGGradient(colorsSpace: space, colors: [color(0x49A87B), color(0x2E6B4F), color(0x163B2C)] as CFArray, locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: 80, y: 944), end: CGPoint(x: 944, y: 80), options: [])
    let glow = CGGradient(colorsSpace: space, colors: [color(0xFFFFFF, 0.16), color(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 902), startRadius: 0, endCenter: CGPoint(x: 512, y: 902), endRadius: 390, options: [])
}
func drawText(_ ctx: CGContext, _ s: String, _ fontName: String, _ fontSize: CGFloat, _ c: CGColor, center: CGPoint) {
    let font = NSFont(name: fontName, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor(cgColor: c)!]
    let str = NSAttributedString(string: s, attributes: attrs)
    let bounds = str.boundingRect(with: CGSize(width: 2000, height: 2000), options: [.usesLineFragmentOrigin])
    let line = CTLineCreateWithAttributedString(str)
    let b = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
    ctx.saveGState()
    ctx.textMatrix = .identity
    ctx.translateBy(x: center.x - b.midX, y: center.y - b.midY)
    CTLineDraw(line, ctx)
    ctx.restoreGState()
    _ = bounds
}

// ============ A · 字：青松底 + 宋体「听」============
do {
    let ctx = makeContext()
    pineGradient(ctx)
    drawText(ctx, "听", "Songti SC", 560, color(0xFBF9F3), center: CGPoint(x: 512, y: 548))
    // 脚下三道细声弧
    ctx.setStrokeColor(color(0xFBF9F3))
    ctx.setLineWidth(18)
    ctx.setLineCap(.round)
    for (i, r) in ([70.0, 120.0, 170.0] as [CGFloat]).enumerated() {
        ctx.setAlpha([0.9, 0.55, 0.3][i])
        ctx.addArc(center: CGPoint(x: 512, y: 208), radius: r, startAngle: .pi * 0.22, endAngle: .pi * 0.78, clockwise: false)
        ctx.strokePath()
    }
    ctx.setAlpha(1)
    save(ctx, "icon-A-zi.png")
}

// ============ B · 题签：宣纸底 + 竖排「听页」+ 青松小印 ============
do {
    let ctx = makeContext()
    ctx.setFillColor(color(0xF7F4EC))
    ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
    // 纸纹：四角淡晕
    let shade = CGGradient(colorsSpace: space, colors: [color(0x2E6B4F, 0.07), color(0x2E6B4F, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(shade, startCenter: CGPoint(x: 512, y: 0), startRadius: 0, endCenter: CGPoint(x: 512, y: 0), endRadius: 720, options: [])
    // 左书脊
    ctx.setFillColor(color(0x1C1F1C, 0.08)); ctx.fill(CGRect(x: 0, y: 0, width: 96, height: size))
    ctx.setFillColor(color(0x1C1F1C, 0.35)); ctx.fill(CGRect(x: 96, y: 0, width: 4, height: size))
    // 题签框
    let slip = CGRect(x: 560, y: 300, width: 240, height: 480)
    ctx.setFillColor(color(0xFFFFFF, 0.55)); ctx.fill(slip)
    ctx.setStrokeColor(color(0x3B3A33, 0.28)); ctx.setLineWidth(5); ctx.stroke(slip.insetBy(dx: -14, dy: -14))
    drawText(ctx, "听", "Songti SC", 168, color(0x1C1F1C), center: CGPoint(x: 680, y: 660))
    drawText(ctx, "页", "Songti SC", 168, color(0x1C1F1C), center: CGPoint(x: 680, y: 470))
    // 青松小印
    let seal = CGRect(x: 640, y: 320, width: 80, height: 80)
    ctx.setFillColor(color(0x2E6B4F))
    ctx.addPath(CGPath(roundedRect: seal, cornerWidth: 14, cornerHeight: 14, transform: nil)); ctx.fillPath()
    drawText(ctx, "印", "Songti SC", 44, color(0xF7F4EC), center: CGPoint(x: 680, y: 360))
    save(ctx, "icon-B-tiqian.png")
}

// ============ C · 山月：夜松底 + 圆月 + 书脊山形 ============
do {
    let ctx = makeContext()
    let g = CGGradient(colorsSpace: space, colors: [color(0x1D4A38), color(0x0E2A1F)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: 512, y: 1024), end: CGPoint(x: 512, y: 0), options: [])
    // 月
    ctx.setFillColor(color(0xF5F1E4))
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 0), blur: 60, color: color(0xF5F1E4, 0.45))
    ctx.fillEllipse(in: CGRect(x: 512 - 130, y: 620 - 130 + 160, width: 260, height: 260))
    ctx.restoreGState()
    // 山形书脊：三本高低书
    ctx.setFillColor(color(0x49A87B))
    for (x, h) in ([(312.0, 200.0), (472.0, 300.0), (632.0, 160.0)] as [(CGFloat, CGFloat)]) {
        ctx.addPath(CGPath(roundedRect: CGRect(x: x, y: 190, width: 120, height: h), cornerWidth: 16, cornerHeight: 16, transform: nil)); ctx.fillPath()
    }
    ctx.setFillColor(color(0xF5F1E4))
    for (x, h) in ([(312.0, 200.0), (472.0, 300.0), (632.0, 160.0)] as [(CGFloat, CGFloat)]) {
        ctx.fill(CGRect(x: x + 52, y: 190 + h - 60, width: 16, height: 40))
    }
    save(ctx, "icon-C-moon.png")
}

// ============ D · 折页：纸页圆角块，右上角折起成播放三角 ============
do {
    let ctx = makeContext()
    pineGradient(ctx)
    // 纸页
    let page = CGRect(x: 272, y: 272, width: 480, height: 560)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -16), blur: 40, color: color(0x000000, 0.25))
    ctx.setFillColor(color(0xFBF9F3))
    ctx.addPath(CGPath(roundedRect: page, cornerWidth: 48, cornerHeight: 48, transform: nil))
    ctx.fillPath()
    ctx.restoreGState()
    // 文字行
    ctx.setStrokeColor(color(0x3B3A33, 0.35)); ctx.setLineWidth(15); ctx.setLineCap(.round)
    for (i, y) in ([CGFloat(640), CGFloat(572), CGFloat(504), CGFloat(436)].enumerated()) {
        let inset: CGFloat = i == 3 ? 110 : 0
        ctx.move(to: CGPoint(x: 352, y: y)); ctx.addLine(to: CGPoint(x: 672 - inset, y: y)); ctx.strokePath()
    }
    // 播放三角（青松）
    let tri = CGMutablePath()
    tri.move(to: CGPoint(x: 478, y: 268)); tri.addLine(to: CGPoint(x: 478, y: 388)); tri.addLine(to: CGPoint(x: 592, y: 328)); tri.closeSubpath()
    ctx.setFillColor(color(0x2E6B4F)); ctx.addPath(tri); ctx.fillPath()
    save(ctx, "icon-D-fold.png")
}
