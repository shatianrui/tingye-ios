import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// 听页图标 v8 · PureLibro 插画风格：奶油纸底 + 粗描边扁平书本 + 矢车菊蓝声波。
// 用法: swift render-app-icon-v8.swift <out.png> [dark|tinted]
let size = 1024
let out = URL(fileURLWithPath: CommandLine.arguments[1])
let mode = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "light"
let dark = mode == "dark", tinted = mode == "tinted"

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

let inkDark: UInt32 = tinted ? 0x3A3A40 : 0x23232B
let blue: UInt32 = tinted ? 0x3A3A40 : 0x4A7BE0
let blueSoft: UInt32 = tinted ? 0x3A3A40 : 0x93A0D4
let orange: UInt32 = tinted ? 0x3A3A40 : 0xF2A24B
let pageFill: UInt32 = tinted ? 0x3A3A40 : 0xFFFFFF

let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                    bitmapInfo: tinted ? CGImageAlphaInfo.premultipliedLast.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue)!
ctx.translateBy(x: 0, y: CGFloat(size)); ctx.scaleBy(x: 1, y: -1)

// 背景：浅色奶油纸 / 深色暖黑 / tinted 透明。
if tinted {
    ctx.clear(CGRect(x: 0, y: 0, width: size, height: size))
} else {
    let stops: [UInt32] = dark ? [0x232326, 0x1B1B1F, 0x131316] : [0xFBF7EC, 0xF8F3E6, 0xF1EADA]
    let bg = CGGradient(colorsSpace: space, colors: stops.map { rgb($0) } as CFArray, locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(bg, start: .zero, end: CGPoint(x: 0, y: size), options: [])
}

let spineTop = CGPoint(x: 512, y: 500), spineBottom = CGPoint(x: 512, y: 780)
let outer: CGFloat = 232, rise: CGFloat = 44, bow: CGFloat = 70

func page(_ side: CGFloat, offset: CGFloat = 0) -> CGPath {
    let p = CGMutablePath()
    let ox = 512 + side * (512 - outer)
    p.move(to: CGPoint(x: 512, y: spineTop.y + offset))
    p.addQuadCurve(to: CGPoint(x: ox, y: spineTop.y - rise + offset), control: CGPoint(x: 512 + side * 140, y: spineTop.y - bow + offset))
    p.addLine(to: CGPoint(x: ox, y: spineBottom.y - rise + offset))
    p.addQuadCurve(to: CGPoint(x: 512, y: spineBottom.y + offset), control: CGPoint(x: 512 + side * 140, y: spineBottom.y - bow + offset))
    p.closeSubpath()
    return p
}

// 蓝色封底：比书页大一圈的圆角矩形，从书页后面探出来。
let backCover = CGPath(roundedRect: CGRect(x: 238, y: 428, width: 548, height: 392), cornerWidth: 36, cornerHeight: 36, transform: nil)
ctx.addPath(backCover); ctx.setFillColor(rgb(blueSoft)); ctx.fillPath()
ctx.setLineWidth(13); ctx.setStrokeColor(rgb(inkDark)); ctx.addPath(backCover); ctx.strokePath()

// 橙色书签带：书脊下垂，先画被书页压住。
let ribbon = CGMutablePath()
ribbon.move(to: CGPoint(x: 486, y: 742))
ribbon.addLine(to: CGPoint(x: 538, y: 742))
ribbon.addLine(to: CGPoint(x: 538, y: 892))
ribbon.addLine(to: CGPoint(x: 512, y: 864))
ribbon.addLine(to: CGPoint(x: 486, y: 892))
ribbon.closeSubpath()
ctx.addPath(ribbon); ctx.setFillColor(rgb(orange)); ctx.fillPath()
ctx.setLineWidth(11); ctx.setStrokeColor(rgb(inkDark)); ctx.addPath(ribbon); ctx.strokePath()

// 书页：白底 + 粗描边（PureLibro 插画感的关键）。
for side in [-1.0, 1.0] as [CGFloat] {
    ctx.addPath(page(side)); ctx.setFillColor(rgb(pageFill)); ctx.fillPath()
}
ctx.setLineWidth(12); ctx.setStrokeColor(rgb(tinted ? 0x3A3A40 : (dark ? 0x0B0B0D : 0x23232B))); ctx.setLineJoin(.round)
for side in [-1.0, 1.0] as [CGFloat] {
    ctx.addPath(page(side)); ctx.strokePath()
}

// 页内文字行：沿页面弧度的深灰线。
ctx.setLineCap(.round); ctx.setLineWidth(13); ctx.setStrokeColor(rgb(inkDark, 0.22))
for side in [-1.0, 1.0] as [CGFloat] {
    for (i, dy) in [64.0, 112, 160].enumerated() {
        let short = i == 2
        let inner: CGFloat = short && side < 0 ? 120 : 48, outerInset: CGFloat = short && side > 0 ? 128 : 52
        let x0 = 512 + side * inner, x1 = 512 + side * (512 - outer - outerInset)
        let t0 = inner / (512 - outer), t1 = (512 - outer - outerInset) / (512 - outer)
        func y(_ t: CGFloat) -> CGFloat {
            let a = spineTop.y, c = spineTop.y - bow, b = spineTop.y - rise
            return (1 - t) * (1 - t) * a + 2 * (1 - t) * t * c + t * t * b + CGFloat(dy)
        }
        let line = CGMutablePath()
        line.move(to: CGPoint(x: x0, y: y(t0)))
        line.addQuadCurve(to: CGPoint(x: x1, y: y(t1)), control: CGPoint(x: (x0 + x1) / 2, y: y((t0 + t1) / 2) - 6))
        ctx.addPath(line); ctx.strokePath()
    }
}

// 书脊线。
ctx.setLineWidth(7); ctx.setStrokeColor(rgb(inkDark, 0.35))
ctx.move(to: spineTop); ctx.addLine(to: spineBottom); ctx.strokePath()

// 声波：矢车菊蓝，白描边让它在奶油底上更跳。
let heights: [CGFloat] = [60, 124, 188, 240, 188, 124, 60]
let barWidth: CGFloat = 34, gap: CGFloat = 26, center = CGPoint(x: 512, y: 310)
let total = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * gap
for (i, h) in heights.enumerated() {
    let x = center.x - total / 2 + CGFloat(i) * (barWidth + gap)
    let bar = CGPath(roundedRect: CGRect(x: x, y: center.y - h / 2, width: barWidth, height: h), cornerWidth: barWidth / 2, cornerHeight: barWidth / 2, transform: nil)
    ctx.addPath(bar); ctx.setFillColor(rgb(blue, i == 3 ? 1 : (i == 2 || i == 4 ? 0.85 : (i == 1 || i == 5 ? 0.65 : 0.45)))); ctx.fillPath()
    ctx.setLineWidth(4.5); ctx.setStrokeColor(rgb(inkDark, 0.85)); ctx.addPath(bar); ctx.strokePath()
}

let image = ctx.makeImage()!
let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
print("written", out.path)
