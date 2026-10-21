import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import AppKit

// 听页 · 青听图标（v16 定稿，方向 A「字」）：青松渐变底，宋体「听」立骨，字下三道声弧。
// swift Design/render-app-icon-v16.swift <output.png> [dark|tinted]
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

// MARK: 背景
if tinted {
    context.setFillColor(color(0x8A8A8A))
    context.fill(CGRect(x: 0, y: 0, width: size, height: size))
} else if dark {
    context.setFillColor(color(0x101512))
    context.fill(CGRect(x: 0, y: 0, width: size, height: size))
} else {
    let gradient = CGGradient(colorsSpace: space, colors: [color(0x49A87B), color(0x2E6B4F), color(0x163B2C)] as CFArray, locations: [0, 0.55, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 80, y: 944), end: CGPoint(x: 944, y: 80), options: [])
    let glow = CGGradient(colorsSpace: space, colors: [color(0xFFFFFF, 0.16), color(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
    context.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 902), startRadius: 0, endCenter: CGPoint(x: 512, y: 902), endRadius: 390, options: [])
}

// MARK: 宋体「听」立骨
let glyph: UInt32 = tinted ? 0xE8E8E8 : 0xFBF9F3
let font = NSFont(name: "Songti SC", size: 560) ?? NSFont.systemFont(ofSize: 560)
let str = NSAttributedString(string: "听", attributes: [.font: font, .foregroundColor: NSColor(cgColor: color(glyph))!])
let line = CTLineCreateWithAttributedString(str)
let b = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
context.saveGState()
context.textMatrix = .identity
context.translateBy(x: 512 - b.midX, y: 548 - b.midY)
CTLineDraw(line, context)
context.restoreGState()

// MARK: 字下三道声弧（夜间用浅青，其余纸白）
let arcHex: UInt32 = tinted ? 0xE8E8E8 : dark ? 0x8CC2A5 : 0xFBF9F3
context.setStrokeColor(color(arcHex))
context.setLineWidth(18)
context.setLineCap(.round)
for (i, r) in ([70.0, 120.0, 170.0] as [CGFloat]).enumerated() {
    context.setAlpha([0.9, 0.55, 0.3][i])
    context.addArc(center: CGPoint(x: 512, y: 208), radius: r, startAngle: .pi * 0.22, endAngle: .pi * 0.78, clockwise: false)
    context.strokePath()
}
context.setAlpha(1)

let image = context.makeImage()!
let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, image, nil)
CGImageDestinationFinalize(destination)
print(output.path)
