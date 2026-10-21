import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// 听页 · 青听「声 · 页」。青松渐变底上，打开的书页化作三道声弧 —— 阅读与听书同源。
// 设计稿：Figma「听页 Tingye · 重设计（UI + 图标）」02 · 应用图标。
// swift Design/render-app-icon-v14.swift <output.png> [dark|tinted]
let output = URL(fileURLWithPath: CommandLine.arguments[1])
let mode = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "light"
let tinted = mode == "tinted"
let dark = mode == "dark"
let size = 1024

func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: alpha)
}
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

// MARK: 背景：青松渐变（y 轴向上，起点为视觉左上）
if tinted {
    context.setFillColor(color(0x8A8A8A))
    context.fill(CGRect(x: 0, y: 0, width: size, height: size))
} else if dark {
    context.setFillColor(color(0x101512))
    context.fill(CGRect(x: 0, y: 0, width: size, height: size))
} else {
    let stops: [(UInt32, CGFloat)] = [(0x49A87B, 0), (0x2E6B4F, 0.55), (0x163B2C, 1)]
    let gradient = CGGradient(colorsSpace: space, colors: stops.map { color($0.0) } as CFArray, locations: stops.map { $0.1 })!
    context.drawLinearGradient(gradient, start: CGPoint(x: 80, y: 944), end: CGPoint(x: 944, y: 80), options: [])
    // 顶部柔光
    let glow = CGGradient(colorsSpace: space, colors: [color(0xFFFFFF, alpha: 0.16), color(0xFFFFFF, alpha: 0)] as CFArray, locations: [0, 1])!
    context.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 902), startRadius: 0, endCenter: CGPoint(x: 512, y: 902), endRadius: 390, options: [])
}

let glyph: UInt32 = tinted ? 0xE8E8E8 : 0xFBF9F3

// MARK: 声弧三道（书页之上，同心张开）
context.setStrokeColor(color(glyph))
context.setLineWidth(26)
context.setLineCap(.round)
for (i, radius) in ([210, 296, 382] as [CGFloat]).enumerated() {
    context.setAlpha([0.95, 0.62, 0.34][i])
    context.addArc(center: CGPoint(x: 512, y: 364), radius: radius, startAngle: .pi * 0.2, endAngle: .pi * 0.8, clockwise: false)
    context.strokePath()
}
context.setAlpha(1)

// MARK: 书页（打开的书，中缝向下垂坠）
let pages = CGMutablePath()
pages.move(to: CGPoint(x: 512, y: 360))
pages.addCurve(to: CGPoint(x: 252, y: 424), control1: CGPoint(x: 440, y: 424), control2: CGPoint(x: 344, y: 440))
pages.addLine(to: CGPoint(x: 252, y: 200))
pages.addCurve(to: CGPoint(x: 512, y: 136), control1: CGPoint(x: 344, y: 216), control2: CGPoint(x: 440, y: 200))
pages.addCurve(to: CGPoint(x: 772, y: 200), control1: CGPoint(x: 584, y: 200), control2: CGPoint(x: 680, y: 216))
pages.addLine(to: CGPoint(x: 772, y: 424))
pages.addCurve(to: CGPoint(x: 512, y: 360), control1: CGPoint(x: 680, y: 440), control2: CGPoint(x: 584, y: 424))
pages.closeSubpath()
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -12), blur: 30, color: color(0x000000, alpha: tinted ? 0.15 : 0.25))
context.setFillColor(color(glyph))
context.addPath(pages)
context.fillPath()
context.restoreGState()

// MARK: 书脊（青松 / 夜间浅青 / 着色灰）
let spineHex: UInt32 = tinted ? 0x8A8A8A : dark ? 0x8CC2A5 : 0x2E6B4F
context.setFillColor(color(spineHex))
context.addPath(CGPath(roundedRect: CGRect(x: 507, y: 132, width: 10, height: 236), cornerWidth: 5, cornerHeight: 5, transform: nil))
context.fillPath()

let image = context.makeImage()!
let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, image, nil)
CGImageDestinationFinalize(destination)
print(output.path)
