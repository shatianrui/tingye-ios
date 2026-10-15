import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// 听页图标 v9 · 「书卷 · 听页」温润宣纸 + 青瓷书封 + 朱砂书签与印章 + 朱金声波。
// 用法: swift Design/render-app-icon-v9.swift <out.png> [dark|tinted]
let size = 1024
let out = URL(fileURLWithPath: CommandLine.arguments[1])
let mode = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "light"
let dark = mode == "dark", tinted = mode == "tinted"

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: a
    )
}

let inkDark: UInt32 = tinted ? 0x3A3A40 : (dark ? 0x0C0B09 : 0x1F1C18)
let vermilion: UInt32 = tinted ? 0x3A3A40 : (dark ? 0xE26D55 : 0xB83B28)
let gold: UInt32 = tinted ? 0x3A3A40 : (dark ? 0xD4AF6A : 0xC69649)
let jadeCover: UInt32 = tinted ? 0x3A3A40 : (dark ? 0x355E4E : 0x3B6E5C)
let pageStackFill: UInt32 = tinted ? 0x3A3A40 : (dark ? 0xD9D0C1 : 0xEDE4D3)
let pageFill: UInt32 = tinted ? 0x3A3A40 : (dark ? 0xF5EFE4 : 0xFFFDF8)

let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(
    data: nil,
    width: size,
    height: size,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: space,
    bitmapInfo: tinted ? CGImageAlphaInfo.premultipliedLast.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue
)!
ctx.translateBy(x: 0, y: CGFloat(size))
ctx.scaleBy(x: 1, y: -1)

// 1. 背景：浅色温润宣纸 / 深色沉香乌木 / tinted 透明
if tinted {
    ctx.clear(CGRect(x: 0, y: 0, width: size, height: size))
} else {
    let stops: [UInt32] = dark ? [0x221F1A, 0x171512, 0x0F0E0C] : [0xFCF8F0, 0xF5EFE2, 0xEAE0CE]
    let bg = CGGradient(colorsSpace: space, colors: stops.map { rgb($0) } as CFArray, locations: [0, 0.58, 1])!
    ctx.drawLinearGradient(bg, start: .zero, end: CGPoint(x: 0, y: size), options: [])

    // 中心温润光晕（朱砂与赤金柔光）
    let glowColors = [rgb(vermilion, dark ? 0.22 : 0.11), rgb(gold, dark ? 0.09 : 0.05), rgb(vermilion, 0)] as CFArray
    let glow = CGGradient(colorsSpace: space, colors: glowColors, locations: [0, 0.55, 1])!
    ctx.drawRadialGradient(
        glow,
        startCenter: CGPoint(x: 512, y: 410),
        startRadius: 0,
        endCenter: CGPoint(x: 512, y: 450),
        endRadius: 440,
        options: []
    )
}

let spineTop = CGPoint(x: 512, y: 512)
let spineBottom = CGPoint(x: 512, y: 786)
let outer: CGFloat = 228
let rise: CGFloat = 46
let bow: CGFloat = 72

func page(_ side: CGFloat, offset: CGFloat = 0, insetX: CGFloat = 0) -> CGPath {
    let p = CGMutablePath()
    let ox = 512 + side * (512 - outer - insetX)
    p.move(to: CGPoint(x: 512, y: spineTop.y + offset))
    p.addQuadCurve(
        to: CGPoint(x: ox, y: spineTop.y - rise + offset),
        control: CGPoint(x: 512 + side * 142, y: spineTop.y - bow + offset)
    )
    p.addLine(to: CGPoint(x: ox, y: spineBottom.y - rise + offset))
    p.addQuadCurve(
        to: CGPoint(x: 512, y: spineBottom.y + offset),
        control: CGPoint(x: 512 + side * 142, y: spineBottom.y - bow + offset)
    )
    p.closeSubpath()
    return p
}

// 2. 青瓷色封底：比书页大一圈的圆角矩形，带赤金内嵌细线
let backCoverRect = CGRect(x: 230, y: 436, width: 564, height: 394)
let backCover = CGPath(roundedRect: backCoverRect, cornerWidth: 38, cornerHeight: 38, transform: nil)
ctx.addPath(backCover)
ctx.setFillColor(rgb(jadeCover))
ctx.fillPath()

if !tinted {
    let goldInset = CGPath(roundedRect: backCoverRect.insetBy(dx: 14, dy: 14), cornerWidth: 26, cornerHeight: 26, transform: nil)
    ctx.setLineWidth(3.5)
    ctx.setStrokeColor(rgb(gold, 0.55))
    ctx.addPath(goldInset)
    ctx.strokePath()
}

ctx.setLineWidth(13)
ctx.setStrokeColor(rgb(inkDark))
ctx.addPath(backCover)
ctx.strokePath()

// 3. 朱砂书签带：从书脊垂下，带中轴金线
let ribbon = CGMutablePath()
ribbon.move(to: CGPoint(x: 486, y: 746))
ribbon.addLine(to: CGPoint(x: 538, y: 746))
ribbon.addLine(to: CGPoint(x: 538, y: 904))
ribbon.addLine(to: CGPoint(x: 512, y: 874))
ribbon.addLine(to: CGPoint(x: 486, y: 904))
ribbon.closeSubpath()
ctx.addPath(ribbon)
ctx.setFillColor(rgb(vermilion))
ctx.fillPath()

if !tinted {
    ctx.setLineWidth(3)
    ctx.setStrokeColor(rgb(gold, 0.75))
    ctx.move(to: CGPoint(x: 512, y: 754))
    ctx.addLine(to: CGPoint(x: 512, y: 866))
    ctx.strokePath()
}

ctx.setLineWidth(11)
ctx.setStrokeColor(rgb(inkDark))
ctx.addPath(ribbon)
ctx.strokePath()

// 4. 底层叠页（表现书卷厚度）
if !tinted {
    for side in [-1.0, 1.0] as [CGFloat] {
        let lowerPage = page(side, offset: 14, insetX: -4)
        ctx.addPath(lowerPage)
        ctx.setFillColor(rgb(pageStackFill))
        ctx.fillPath()
        ctx.setLineWidth(10)
        ctx.setStrokeColor(rgb(inkDark))
        ctx.addPath(lowerPage)
        ctx.strokePath()
    }
}

// 5. 顶层翻开书页：温润宣纸白 + 浓墨描边
for side in [-1.0, 1.0] as [CGFloat] {
    ctx.addPath(page(side))
    ctx.setFillColor(rgb(pageFill))
    ctx.fillPath()
}
ctx.setLineWidth(12)
ctx.setStrokeColor(rgb(inkDark))
ctx.setLineJoin(.round)
for side in [-1.0, 1.0] as [CGFloat] {
    ctx.addPath(page(side))
    ctx.strokePath()
}

// 6. 页内文字行与右下角朱文小印章
ctx.setLineCap(.round)
ctx.setLineWidth(12)
ctx.setStrokeColor(rgb(inkDark, 0.22))
for side in [-1.0, 1.0] as [CGFloat] {
    for (i, dy) in [64.0, 112.0, 160.0].enumerated() {
        let short = i == 2
        let inner: CGFloat = short && side < 0 ? 118 : 48
        let outerInset: CGFloat = short && side > 0 ? 136 : 52
        let x0 = 512 + side * inner
        let x1 = 512 + side * (512 - outer - outerInset)
        let t0 = inner / (512 - outer)
        let t1 = (512 - outer - outerInset) / (512 - outer)
        func y(_ t: CGFloat) -> CGFloat {
            let a = spineTop.y, c = spineTop.y - bow, b = spineTop.y - rise
            return (1 - t) * (1 - t) * a + 2 * (1 - t) * t * c + t * t * b + CGFloat(dy)
        }
        let line = CGMutablePath()
        line.move(to: CGPoint(x: x0, y: y(t0)))
        line.addQuadCurve(to: CGPoint(x: x1, y: y(t1)), control: CGPoint(x: (x0 + x1) / 2, y: y((t0 + t1) / 2) - 6))
        ctx.addPath(line)
        ctx.strokePath()
    }
}

// 右页右下角微缩朱砂藏书印（篆书框纹意象）
if !tinted {
    let sealRect = CGRect(x: 684, y: 626, width: 38, height: 38)
    let sealPath = CGPath(roundedRect: sealRect, cornerWidth: 7, cornerHeight: 7, transform: nil)
    ctx.addPath(sealPath)
    ctx.setFillColor(rgb(vermilion, 0.92))
    ctx.fillPath()

    let sealInner = CGPath(roundedRect: sealRect.insetBy(dx: 5, dy: 5), cornerWidth: 3, cornerHeight: 3, transform: nil)
    ctx.setLineWidth(2)
    ctx.setStrokeColor(rgb(pageFill, 0.88))
    ctx.addPath(sealInner)
    ctx.strokePath()

    ctx.move(to: CGPoint(x: 703, y: 632))
    ctx.addLine(to: CGPoint(x: 703, y: 658))
    ctx.move(to: CGPoint(x: 694, y: 642))
    ctx.addLine(to: CGPoint(x: 712, y: 642))
    ctx.move(to: CGPoint(x: 696, y: 650))
    ctx.addLine(to: CGPoint(x: 710, y: 650))
    ctx.strokePath()
}

// 7. 书脊中缝线
ctx.setLineWidth(7)
ctx.setStrokeColor(rgb(inkDark, 0.38))
ctx.move(to: spineTop)
ctx.addLine(to: spineBottom)
ctx.strokePath()

// 8. 声波余韵弧线（环绕声波外围的细金弧）
let waveCenter = CGPoint(x: 512, y: 282)
if !tinted {
    ctx.setLineWidth(4.5)
    ctx.setStrokeColor(rgb(gold, dark ? 0.38 : 0.45))
    ctx.setLineCap(.round)
    let leftArc = CGMutablePath()
    leftArc.addArc(center: waveCenter, radius: 246, startAngle: .pi * 0.87, endAngle: .pi * 1.13, clockwise: false)
    ctx.addPath(leftArc)
    ctx.strokePath()

    let rightArc = CGMutablePath()
    rightArc.addArc(center: waveCenter, radius: 246, startAngle: -.pi * 0.13, endAngle: .pi * 0.13, clockwise: false)
    ctx.addPath(rightArc)
    ctx.strokePath()
}

// 9. 声波：朱砂印泥红与赤金交织，浓墨描边
let heights: [CGFloat] = [62, 124, 184, 232, 184, 124, 62]
let barWidth: CGFloat = 34
let gap: CGFloat = 26
let total = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * gap

for (i, h) in heights.enumerated() {
    let x = waveCenter.x - total / 2 + CGFloat(i) * (barWidth + gap)
    let barRect = CGRect(x: x, y: waveCenter.y - h / 2, width: barWidth, height: h)
    let bar = CGPath(roundedRect: barRect, cornerWidth: barWidth / 2, cornerHeight: barWidth / 2, transform: nil)

    ctx.saveGState()
    ctx.addPath(bar)
    ctx.clip()

    if tinted {
        let alpha: CGFloat = i == 3 ? 1.0 : (i == 2 || i == 4 ? 0.85 : (i == 1 || i == 5 ? 0.68 : 0.50))
        ctx.setFillColor(rgb(vermilion, alpha))
        ctx.fill(barRect)
    } else {
        let isCenter = i == 3
        let isMid = i == 2 || i == 4
        let topHex = isCenter ? vermilion : (isMid ? vermilion : gold)
        let botHex = isCenter ? (dark ? 0xC84B35 : 0x962B1B) : gold
        let alpha: CGFloat = isCenter ? 1.0 : (isMid ? 0.92 : (i == 1 || i == 5 ? 0.82 : 0.68))
        let barGrad = CGGradient(
            colorsSpace: space,
            colors: [rgb(topHex, alpha), rgb(botHex, alpha)] as CFArray,
            locations: [0, 1]
        )!
        ctx.drawLinearGradient(
            barGrad,
            start: CGPoint(x: barRect.midX, y: barRect.minY),
            end: CGPoint(x: barRect.midX, y: barRect.maxY),
            options: []
        )
    }
    ctx.restoreGState()

    ctx.setLineWidth(5)
    ctx.setStrokeColor(rgb(inkDark, 0.88))
    ctx.addPath(bar)
    ctx.strokePath()
}

let image = ctx.makeImage()!
let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
print("written", out.path)
