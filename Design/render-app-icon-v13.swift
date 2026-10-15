import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// 听页 · 墨夜。墨黑底上一团琥珀光晕，暖白书页在左，三道琥珀声波向右漾开。
// swift Design/render-app-icon-v13.swift <output.png> [dark|tinted]
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
context.translateBy(x: 0, y: CGFloat(size))
context.scaleBy(x: 1, y: -1)

// MARK: 背景：墨黑渐变
let bgStops: [UInt32] = tinted ? [0x2C2C2E, 0x1C1C1E] : dark ? [0x000000, 0x0B0B0D] : [0x1D1C21, 0x09090B]
let bgGradient = CGGradient(colorsSpace: space, colors: bgStops.map { color($0) } as CFArray, locations: [0, 1])!
context.drawLinearGradient(bgGradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: CGFloat(size)), options: [])

// 琥珀光晕：从声波处散开，像夜里的一盏灯
if !tinted {
    let glow = CGGradient(colorsSpace: space, colors: [color(0xFFB547, alpha: dark ? 0.34 : 0.42), color(0xFF8A3D, alpha: 0.10), color(0xFF8A3D, alpha: 0)] as CFArray, locations: [0, 0.5, 1])!
    context.drawRadialGradient(glow, startCenter: CGPoint(x: 640, y: 520), startRadius: 0, endCenter: CGPoint(x: 640, y: 520), endRadius: 560, options: [])
}

// MARK: 书页
let page = CGRect(x: 196, y: 208, width: 372, height: 608)
let pagePath = CGPath(roundedRect: page, cornerWidth: 40, cornerHeight: 40, transform: nil)
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: 28), blur: 70, color: color(0x000000, alpha: 0.6))
context.setFillColor(color(tinted ? 0xE5E5E5 : dark ? 0xE9E5DD : 0xF5F1EA))
context.addPath(pagePath)
context.fillPath()
context.restoreGState()

// 书脊与页面暖光
context.saveGState()
context.addPath(pagePath)
context.clip()
let warm = CGGradient(colorsSpace: space, colors: [color(0xFFFFFF, alpha: 0), color(tinted ? 0xCCCCCC : 0xFFD9A0, alpha: 0.35)] as CFArray, locations: [0, 1])!
context.drawLinearGradient(warm, start: CGPoint(x: 196, y: 512), end: CGPoint(x: 568, y: 512), options: [])
context.setFillColor(color(tinted ? 0xB0B0B0 : 0xD8CFC0))
context.fill(CGRect(x: 196, y: 208, width: 24, height: 608))
context.restoreGState()

// 文字行
context.setStrokeColor(color(tinted ? 0x8A8A8A : 0x3A352E, alpha: 0.55))
context.setLineWidth(16)
context.setLineCap(.round)
for (i, y) in [CGFloat(380), CGFloat(448), CGFloat(516), CGFloat(584), CGFloat(652)].enumerated() {
    let inset: CGFloat = i == 4 ? 90 : 0
    context.move(to: CGPoint(x: 280, y: y))
    context.addLine(to: CGPoint(x: 500 - inset, y: y))
    context.strokePath()
}
// 正在朗读的一行：琥珀
context.setStrokeColor(color(tinted ? 0x5A5A5A : 0xE08A12))
context.move(to: CGPoint(x: 280, y: 516))
context.addLine(to: CGPoint(x: 500, y: 516))
context.strokePath()

// MARK: 声波
let waveColor = color(tinted ? 0xF0F0F0 : 0xFFB547)
context.setStrokeColor(waveColor)
context.setLineWidth(30)
context.setLineCap(.round)
let origin = CGPoint(x: 612, y: 516)
for (i, radius) in ([92, 176, 260] as [CGFloat]).enumerated() {
    context.setAlpha(1 - CGFloat(i) * 0.22)
    context.addArc(center: origin, radius: radius, startAngle: -.pi / 3.2, endAngle: .pi / 3.2, clockwise: false)
    context.strokePath()
}
context.setAlpha(1)

let image = context.makeImage()!
let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, image, nil)
CGImageDestinationFinalize(destination)
print(output.path)
