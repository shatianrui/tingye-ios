import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import AppKit

// 听页 · 静蓝图标：开放书页与三道声波。
// swift Design/render-app-icon-v18.swift <output.png> [dark|tinted]
guard CommandLine.arguments.count > 1 else {
    print("Usage: swift Design/render-app-icon-v18.swift <output.png> [dark|tinted]")
    exit(1)
}
let output = URL(fileURLWithPath: CommandLine.arguments[1])
let mode = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "light"
let tinted = mode == "tinted"
let dark = mode == "dark"
let size = 1024

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: alpha)
}
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!

if tinted {
    context.setFillColor(color(0x8A8A8A))
    context.fill(CGRect(x: 0, y: 0, width: size, height: size))
} else if dark {
    context.setFillColor(color(0x111827))
    context.fill(CGRect(x: 0, y: 0, width: size, height: size))
    let glow = CGGradient(colorsSpace: space, colors: [color(0xA9B9FF, 0.12), color(0xA9B9FF, 0)] as CFArray, locations: [0, 1])!
    context.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 690), startRadius: 0, endCenter: CGPoint(x: 512, y: 690), endRadius: 510, options: [])
} else {
    context.setFillColor(color(0x3659C9))
    context.fill(CGRect(x: 0, y: 0, width: size, height: size))
    let gradient = CGGradient(colorsSpace: space, colors: [color(0x5B78DA), color(0x3659C9), color(0x243D8E)] as CFArray, locations: [0, 0.52, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 70, y: 954), end: CGPoint(x: 954, y: 70), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    let glow = CGGradient(colorsSpace: space, colors: [color(0xFFFFFF, 0.13), color(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
    context.drawRadialGradient(glow, startCenter: CGPoint(x: 420, y: 790), startRadius: 0, endCenter: CGPoint(x: 420, y: 790), endRadius: 500, options: [])
}

let page: UInt32 = tinted ? 0xE8E8E8 : dark ? 0xEEF1FF : 0xFBF8F1
let detail: UInt32 = tinted ? 0xC8C8C8 : dark ? 0xA9B9FF : 0xD9E1FA
let wave: UInt32 = tinted ? 0xE8E8E8 : dark ? 0xA9B9FF : 0xFBF8F1
context.setFillColor(color(page))

context.move(to: CGPoint(x: 198, y: 714))
context.addCurve(to: CGPoint(x: 512, y: 632), control1: CGPoint(x: 318, y: 742), control2: CGPoint(x: 424, y: 700))
context.addLine(to: CGPoint(x: 512, y: 326))
context.addCurve(to: CGPoint(x: 198, y: 402), control1: CGPoint(x: 418, y: 398), control2: CGPoint(x: 312, y: 430))
context.closePath()
context.fillPath()

context.move(to: CGPoint(x: 826, y: 714))
context.addCurve(to: CGPoint(x: 512, y: 632), control1: CGPoint(x: 706, y: 742), control2: CGPoint(x: 600, y: 700))
context.addLine(to: CGPoint(x: 512, y: 326))
context.addCurve(to: CGPoint(x: 826, y: 402), control1: CGPoint(x: 606, y: 398), control2: CGPoint(x: 712, y: 430))
context.closePath()
context.fillPath()

context.setStrokeColor(color(detail))
context.setLineWidth(16)
context.setLineCap(.round)
context.move(to: CGPoint(x: 512, y: 632))
context.addLine(to: CGPoint(x: 512, y: 326))
context.strokePath()

context.setStrokeColor(color(wave))
context.setLineWidth(27)
context.setLineCap(.round)
for (index, radius) in ([60.0, 108.0, 156.0] as [CGFloat]).enumerated() {
    context.setAlpha([1.0, 0.78, 0.52][index])
    context.addArc(center: CGPoint(x: 512, y: 132), radius: radius, startAngle: .pi * 0.22, endAngle: .pi * 0.78, clockwise: false)
    context.strokePath()
}
context.setAlpha(1)

let image = context.makeImage()!
let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, image, nil)
CGImageDestinationFinalize(destination)
print(output.path)
