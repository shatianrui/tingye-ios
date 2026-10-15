import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// 听页 · 琉璃。澄蓝→紫极光渐变底，白色玻璃书页在左，三道声波在右，页角玻璃高光。
// swift Design/render-app-icon-v12.swift <output.png> [dark|tinted]
let output = URL(fileURLWithPath: CommandLine.arguments[1])
let mode = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "light"
let tinted = mode == "tinted"
let size = 1024

func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: alpha)
}
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
context.translateBy(x: 0, y: CGFloat(size))
context.scaleBy(x: 1, y: -1)

// MARK: 背景：极光渐变
let bgStops: [UInt32] = tinted ? [0x3A3A3C, 0x2A2A2C] : mode == "dark" ? [0x0B3D91, 0x1E2A6E, 0x35215E] : [0x0A5CFF, 0x4B6BFE, 0x7C5BF0]
let bgColors = bgStops.map { color($0) } as CFArray
let bgGradient = CGGradient(colorsSpace: space, colors: bgColors, locations: [0, 0.55, 1])!
context.drawLinearGradient(bgGradient, start: CGPoint(x: 0, y: CGFloat(size)), end: CGPoint(x: CGFloat(size), y: 0), options: [])

// 底部光晕，让玻璃页有「透光」感
if !tinted {
    let glow = CGGradient(colorsSpace: space, colors: [color(0x8B5CF6, alpha: 0.55), color(0x8B5CF6, alpha: 0)] as CFArray, locations: [0, 1])!
    context.drawRadialGradient(glow, startCenter: CGPoint(x: 860, y: 120), startRadius: 0, endCenter: CGPoint(x: 860, y: 120), endRadius: 620, options: [])
}

// MARK: 玻璃书页
let page = CGRect(x: 180, y: 176, width: 400, height: 672)
let pagePath = CGPath(roundedRect: page, cornerWidth: 46, cornerHeight: 46, transform: nil)

// 页底投影
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -26), blur: 60, color: color(0x000000, alpha: 0.38))
context.setFillColor(color(tinted ? 0xD9D9D9 : 0xFFFFFF, alpha: 0.94))
context.addPath(pagePath)
context.fillPath()
context.restoreGState()

// 玻璃高光：页面上部亮、下部微透
context.saveGState()
context.addPath(pagePath)
context.clip()
let pageGlass = CGGradient(colorsSpace: space, colors: [color(0xFFFFFF, alpha: 0.96), color(0xEAF1FF, alpha: 0.82)] as CFArray, locations: [0, 1])!
context.drawLinearGradient(pageGlass, start: CGPoint(x: 180, y: 848), end: CGPoint(x: 580, y: 176), options: [])
// 左上角强高光
let sheen = CGGradient(colorsSpace: space, colors: [color(0xFFFFFF, alpha: 0.9), color(0xFFFFFF, alpha: 0)] as CFArray, locations: [0, 1])!
context.drawLinearGradient(sheen, start: CGPoint(x: 210, y: 800), end: CGPoint(x: 420, y: 560), options: [])
// 书脊
context.setFillColor(color(tinted ? 0xBFBFBF : 0xC9D9F2, alpha: 0.85))
context.fill(CGRect(x: 180, y: 176, width: 26, height: 672))
context.restoreGState()

// 页边细线（玻璃内边）
context.setStrokeColor(color(tinted ? 0x9A9A9A : 0x7FA8E8, alpha: 0.55))
context.setLineWidth(5)
context.addPath(pagePath)
context.strokePath()

// 书页上的文字行
context.setStrokeColor(color(tinted ? 0x8A8A8A : 0x3D6FD9, alpha: 0.5))
context.setLineWidth(15)
context.setLineCap(.round)
for (i, y) in [CGFloat(356), CGFloat(424), CGFloat(492), CGFloat(560)].enumerated() {
    let inset: CGFloat = i == 3 ? 64 : 0
    context.move(to: CGPoint(x: 286, y: y))
    context.addLine(to: CGPoint(x: 516 - inset, y: y))
    context.strokePath()
}

// MARK: 声波
let waveColor = color(tinted ? 0xE8E8E8 : 0xFFFFFF, alpha: 0.96)
context.setStrokeColor(waveColor)
context.setLineWidth(30)
context.setLineCap(.round)
let origin = CGPoint(x: 716, y: 512)
for radius in [86, 172, 258] as [CGFloat] {
    context.addArc(center: origin, radius: radius, startAngle: -.pi / 3.1, endAngle: .pi / 3.1, clockwise: false)
    context.strokePath()
}
context.setFillColor(waveColor)
context.fillEllipse(in: CGRect(x: origin.x - 19, y: origin.y - 19, width: 38, height: 38))

let image = context.makeImage()!
let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, image, nil)
CGImageDestinationFinalize(destination)
print(output.path)
