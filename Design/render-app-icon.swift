import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// 听页图标：青瓷底 · 宣纸双页书 · 书脊上升起声波 · 朱红书签带。
let size = 1024
let out = URL(fileURLWithPath: CommandLine.arguments[1])

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
// 以左上为原点绘制。
ctx.translateBy(x: 0, y: CGFloat(size)); ctx.scaleBy(x: 1, y: -1)

// 背景：青瓷竖向渐变，上浅下深。
let bg = CGGradient(colorsSpace: space, colors: [rgb(0x3F7564), rgb(0x2F5D50), rgb(0x22463C)] as CFArray, locations: [0, 0.55, 1])!
ctx.drawLinearGradient(bg, start: .zero, end: CGPoint(x: 0, y: size), options: [])
// 中心柔光，让书页更醒目。
let glow = CGGradient(colorsSpace: space, colors: [rgb(0xFFFFFF, 0.10), rgb(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 560), startRadius: 0, endCenter: CGPoint(x: 512, y: 560), endRadius: 460, options: [])

let spineTop = CGPoint(x: 512, y: 520), spineBottom = CGPoint(x: 512, y: 790)
let outer: CGFloat = 228          // 页面外缘到中线的距离 = 512 - 228
let rise: CGFloat = 44            // 外角比书脊高出的量
let bow: CGFloat = 70             // 页面上下缘向上拱起的量

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

// 朱红书签带：从书脊下垂，先画，被书页压住。
let ribbon = CGMutablePath()
ribbon.move(to: CGPoint(x: 490, y: 760))
ribbon.addLine(to: CGPoint(x: 534, y: 760))
ribbon.addLine(to: CGPoint(x: 534, y: 900))
ribbon.addLine(to: CGPoint(x: 512, y: 874))
ribbon.addLine(to: CGPoint(x: 490, y: 900))
ribbon.closeSubpath()
ctx.addPath(ribbon); ctx.setFillColor(rgb(0xB5452F)); ctx.fillPath()

// 书下投影。
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: 18), blur: 40, color: rgb(0x0E201B, 0.45))
for side in [-1.0, 1.0] as [CGFloat] { ctx.addPath(page(side, offset: 16)) }
ctx.setFillColor(rgb(0xD8D0BF)); ctx.fillPath()
ctx.restoreGState()

// 书页厚度（下层）与正页。
for side in [-1.0, 1.0] as [CGFloat] {
    ctx.addPath(page(side, offset: 16)); ctx.setFillColor(rgb(0xD8D0BF)); ctx.fillPath()
    ctx.addPath(page(side, offset: 8)); ctx.setFillColor(rgb(0xE6DFD0)); ctx.fillPath()
    ctx.addPath(page(side)); ctx.setFillColor(rgb(0xF4F1EA)); ctx.fillPath()
}

// 页内文字行：沿页面弧度。
ctx.setLineCap(.round); ctx.setLineWidth(11)
ctx.setStrokeColor(rgb(0x2F5D50, 0.28))
for side in [-1.0, 1.0] as [CGFloat] {
    for (i, dy) in [64.0, 112, 160, 208].enumerated() {
        // 段末短行：左页在靠书脊一侧收尾，右页在外侧收尾（横排从左往右读）。
        let short = i == 3
        let inner: CGFloat = short && side < 0 ? 110 : 40, outerInset: CGFloat = short && side > 0 ? 120 : 44
        let x0 = 512 + side * inner, x1 = 512 + side * (512 - outer - outerInset)
        let t0 = inner / (512 - outer), t1 = (512 - outer - outerInset) / (512 - outer)
        // 与上缘同形的二次曲线上取点。
        func y(_ t: CGFloat) -> CGFloat {
            let a = spineTop.y, c = spineTop.y - bow, b = spineTop.y - rise
            let ty = (1 - t) * (1 - t) * a + 2 * (1 - t) * t * c + t * t * b
            return ty + CGFloat(dy)
        }
        let line = CGMutablePath()
        line.move(to: CGPoint(x: x0, y: y(t0)))
        line.addQuadCurve(to: CGPoint(x: x1, y: y(t1)), control: CGPoint(x: (x0 + x1) / 2, y: y((t0 + t1) / 2) - 6))
        ctx.addPath(line); ctx.strokePath()
    }
}

// 书脊折线。
ctx.setLineWidth(5); ctx.setStrokeColor(rgb(0xC9C0AD))
ctx.move(to: spineTop); ctx.addLine(to: spineBottom); ctx.strokePath()

// 声波：书页上方升起的一段音频波形，中间高两侧低。
let heights: [CGFloat] = [64, 132, 196, 252, 196, 132, 64]
let barWidth: CGFloat = 32, gap: CGFloat = 24, center = CGPoint(x: 512, y: 318)
let total = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * gap
for (i, h) in heights.enumerated() {
    let x = center.x - total / 2 + CGFloat(i) * (barWidth + gap)
    let bar = CGPath(roundedRect: CGRect(x: x, y: center.y - h / 2, width: barWidth, height: h), cornerWidth: barWidth / 2, cornerHeight: barWidth / 2, transform: nil)
    ctx.addPath(bar); ctx.setFillColor(rgb(0xF4F1EA, i == 3 ? 1 : (i == 2 || i == 4 ? 0.88 : (i == 1 || i == 5 ? 0.7 : 0.5)))); ctx.fillPath()
}

let image = ctx.makeImage()!
let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
