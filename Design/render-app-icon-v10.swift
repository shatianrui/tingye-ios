import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// 听页 · 纸间书房。可编辑的原生矢量图标源，系统负责圆角遮罩。
// swift Design/render-app-icon-v10.swift <output.png> [dark|tinted]
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
let background: UInt32 = tinted ? 0x161616 : mode == "dark" ? 0x142F26 : 0x234D3F
let paper: UInt32 = tinted ? 0xF3F3F3 : 0xF4F1E4
let sage: UInt32 = tinted ? 0xB8B8B8 : 0xB6C9AA
context.setFillColor(color(background))
context.fill(CGRect(x: 0, y: 0, width: size, height: size))
// An open page; a generous silhouette that remains legible on a home screen.
let page = CGMutablePath()
page.move(to: CGPoint(x: 235, y: 272))
page.addCurve(to: CGPoint(x: 490, y: 325), control1: CGPoint(x: 326, y: 258), control2: CGPoint(x: 424, y: 279))
page.addLine(to: CGPoint(x: 490, y: 747))
page.addCurve(to: CGPoint(x: 235, y: 694), control1: CGPoint(x: 416, y: 701), control2: CGPoint(x: 326, y: 679))
page.addQuadCurve(to: CGPoint(x: 218, y: 678), control: CGPoint(x: 218, y: 696))
page.addLine(to: CGPoint(x: 218, y: 291))
page.addQuadCurve(to: CGPoint(x: 235, y: 272), control: CGPoint(x: 218, y: 274))
page.closeSubpath()
context.setFillColor(color(paper)); context.addPath(page); context.fillPath()
// Printed lines follow the curve of the leaf.
context.setLineWidth(12); context.setLineCap(.round)
context.setStrokeColor(color(background, alpha: 0.25))
for y: CGFloat in [379, 435, 491] {
    context.move(to: CGPoint(x: 278, y: y))
    context.addQuadCurve(to: CGPoint(x: 425, y: y + 22), control: CGPoint(x: 351, y: y - 3))
    context.strokePath()
}
// The opposite page becomes a voice. Four strokes keep a book-like outer contour.
for (index, rect) in [
    CGRect(x: 535, y: 325, width: 48, height: 422),
    CGRect(x: 609, y: 294, width: 48, height: 420),
    CGRect(x: 683, y: 276, width: 48, height: 420),
    CGRect(x: 757, y: 349, width: 48, height: 272)
].enumerated() {
    context.setFillColor(color(index < 2 ? paper : sage))
    context.addPath(CGPath(roundedRect: rect, cornerWidth: 24, cornerHeight: 24, transform: nil))
    context.fillPath()
}
let image = context.makeImage()!
let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, image, nil)
CGImageDestinationFinalize(destination)
print(output.path)
