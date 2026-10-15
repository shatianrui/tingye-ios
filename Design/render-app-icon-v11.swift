import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// 听页 · 青页。一页书在左，右侧三道湖青声波。系统负责圆角遮罩。
// swift Design/render-app-icon-v11.swift <output.png> [dark|tinted]
let output = URL(fileURLWithPath: CommandLine.arguments[1])
let mode = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "light"
let tinted = mode == "tinted"
let size = 1024
func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: alpha)
}
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
context.translateBy(x: 0, y: CGFloat(size))
context.scaleBy(x: 1, y: -1)

let background: UInt32 = tinted ? 0x161616 : mode == "dark" ? 0x0B1C26 : 0x16445C
let paper: UInt32 = tinted ? 0xF2F2F2 : 0xF4F7FA
let spine: UInt32 = tinted ? 0xC8C8C8 : 0xD5E4EE
let voice: UInt32 = tinted ? 0xE4E4E4 : 0x8EC4E0
let rule: UInt32 = tinted ? 0x8A8A8A : 0x1B6B93

context.setFillColor(color(background))
context.fill(CGRect(x: 0, y: 0, width: size, height: size))

let page = CGRect(x: 196, y: 188, width: 392, height: 648)
let pagePath = CGPath(roundedRect: page, cornerWidth: 44, cornerHeight: 44, transform: nil)
context.setFillColor(color(paper))
context.addPath(pagePath)
context.fillPath()

let spineRect = CGRect(x: 196, y: 188, width: 28, height: 648)
context.saveGState()
context.addPath(pagePath)
context.clip()
context.setFillColor(color(spine))
context.fill(spineRect)
context.restoreGState()

context.setStrokeColor(color(rule, alpha: tinted ? 0.55 : 0.38))
context.setLineWidth(16)
context.setLineCap(.round)
for y in [360, 430, 500, 570] as [CGFloat] {
    context.move(to: CGPoint(x: 286, y: y))
    context.addLine(to: CGPoint(x: 520, y: y))
    context.strokePath()
}

context.setStrokeColor(color(voice))
context.setLineWidth(30)
context.setLineCap(.round)
let origin = CGPoint(x: 688, y: 512)
for radius in [86, 168, 250] as [CGFloat] {
    context.addArc(center: origin, radius: radius, startAngle: -.pi / 3.1, endAngle: .pi / 3.1, clockwise: false)
    context.strokePath()
}
context.setFillColor(color(voice))
context.fillEllipse(in: CGRect(x: origin.x - 18, y: origin.y - 18, width: 36, height: 36))

let image = context.makeImage()!
let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, image, nil)
CGImageDestinationFinalize(destination)
print(output.path)
