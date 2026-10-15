import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// 听页图标 v3 · Claude 风格：暖米白 + 赤陶珊瑚，沿用「书页声波」母题。
// 用法: swift render-app-icon-v3.swift <out-dir>
// 生成 icon-claude-ivory.png（米白底珊瑚书）/ icon-claude-ink.png（米白底墨书珊瑚声波）/ icon-claude-coral.png（珊瑚底米白书）三个候选。
let size = 1024
let outDir = CommandLine.arguments[1]

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

struct Palette {
    let bgTop: UInt32, bgMid: UInt32, bgBottom: UInt32   // 背景三段渐变
    let glowAlpha: CGFloat                               // 中心柔光强度
    let page: UInt32                                     // 书页
    let pageUnder: UInt32                                // 书页厚度层
    let pageLine: UInt32, pageLineAlpha: CGFloat         // 页内文字行
    let spine: UInt32                                    // 书脊折线
    let ribbon: UInt32                                   // 书签带
    let wave: UInt32                                     // 声波
    let waveOnPage: Bool                                 // 声波颜色是否与书页同色系（纸感底时声波用强调色）
    let shadow: UInt32, shadowAlpha: CGFloat
}

let variants: [String: Palette] = [
    // A · 米白底 + 赤陶书与声波（最贴近 Claude 观感）
    "claude-ivory": Palette(bgTop: 0xFCFBF7, bgMid: 0xF5F2E9, bgBottom: 0xECE8DB,
                            glowAlpha: 0.0, page: 0xD97757, pageUnder: 0xC05A3B,
                            pageLine: 0xFFFFFF, pageLineAlpha: 0.55, spine: 0xC05A3B,
                            ribbon: 0xD97757, wave: 0xD97757, waveOnPage: true,
                            shadow: 0xB5A98F, shadowAlpha: 0.45),
    // B · 米白底 + 墨书 + 珊瑚声波与书签
    "claude-ink": Palette(bgTop: 0xFCFBF7, bgMid: 0xF5F2E9, bgBottom: 0xECE8DB,
                          glowAlpha: 0.0, page: 0x26241F, pageUnder: 0x3A382F,
                          pageLine: 0xFFFFFF, pageLineAlpha: 0.50, spine: 0x3A382F,
                          ribbon: 0xD97757, wave: 0xD97757, waveOnPage: true,
                          shadow: 0xB5A98F, shadowAlpha: 0.45),
    // C · 赤陶底 + 米白书与声波
    "claude-coral": Palette(bgTop: 0xE28E6F, bgMid: 0xD97757, bgBottom: 0xBE5A3C,
                            glowAlpha: 0.12, page: 0xFCFBF7, pageUnder: 0xF0E3D8,
                            pageLine: 0xD97757, pageLineAlpha: 0.35, spine: 0xEBD8CB,
                            ribbon: 0xFCFBF7, wave: 0xFFFFFF, waveOnPage: false,
                            shadow: 0x7E3A24, shadowAlpha: 0.35),
]

func render(_ name: String, _ p: Palette) {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.translateBy(x: 0, y: CGFloat(size)); ctx.scaleBy(x: 1, y: -1)

    // 背景：竖向渐变，上浅下深。
    let bg = CGGradient(colorsSpace: space, colors: [rgb(p.bgTop), rgb(p.bgMid), rgb(p.bgBottom)] as CFArray, locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(bg, start: .zero, end: CGPoint(x: 0, y: size), options: [])
    if p.glowAlpha > 0 {
        let glow = CGGradient(colorsSpace: space, colors: [rgb(0xFFFFFF, p.glowAlpha), rgb(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 560), startRadius: 0, endCenter: CGPoint(x: 512, y: 560), endRadius: 460, options: [])
    }

    let spineTop = CGPoint(x: 512, y: 520), spineBottom = CGPoint(x: 512, y: 790)
    let outer: CGFloat = 228, rise: CGFloat = 44, bow: CGFloat = 70

    func page(_ side: CGFloat, offset: CGFloat = 0) -> CGPath {
        let path = CGMutablePath()
        let ox = 512 + side * (512 - outer)
        path.move(to: CGPoint(x: 512, y: spineTop.y + offset))
        path.addQuadCurve(to: CGPoint(x: ox, y: spineTop.y - rise + offset), control: CGPoint(x: 512 + side * 140, y: spineTop.y - bow + offset))
        path.addLine(to: CGPoint(x: ox, y: spineBottom.y - rise + offset))
        path.addQuadCurve(to: CGPoint(x: 512, y: spineBottom.y + offset), control: CGPoint(x: 512 + side * 140, y: spineBottom.y - bow + offset))
        path.closeSubpath()
        return path
    }

    // 书签带：从书脊下垂，先画，被书页压住。
    let ribbon = CGMutablePath()
    ribbon.move(to: CGPoint(x: 490, y: 760))
    ribbon.addLine(to: CGPoint(x: 534, y: 760))
    ribbon.addLine(to: CGPoint(x: 534, y: 900))
    ribbon.addLine(to: CGPoint(x: 512, y: 874))
    ribbon.addLine(to: CGPoint(x: 490, y: 900))
    ribbon.closeSubpath()
    ctx.addPath(ribbon); ctx.setFillColor(rgb(p.ribbon)); ctx.fillPath()

    // 书下投影。
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 18), blur: 40, color: rgb(p.shadow, p.shadowAlpha))
    for side in [-1.0, 1.0] as [CGFloat] { ctx.addPath(page(side, offset: 16)) }
    ctx.setFillColor(rgb(p.pageUnder)); ctx.fillPath()
    ctx.restoreGState()

    // 书页厚度（下层）与正页。
    for side in [-1.0, 1.0] as [CGFloat] {
        ctx.addPath(page(side, offset: 16)); ctx.setFillColor(rgb(p.pageUnder)); ctx.fillPath()
        ctx.addPath(page(side, offset: 8)); ctx.setFillColor(rgb(p.pageUnder)); ctx.fillPath()
        ctx.addPath(page(side)); ctx.setFillColor(rgb(p.page)); ctx.fillPath()
    }

    // 页内文字行：沿页面弧度。
    ctx.setLineCap(.round); ctx.setLineWidth(11)
    ctx.setStrokeColor(rgb(p.pageLine, p.pageLineAlpha))
    for side in [-1.0, 1.0] as [CGFloat] {
        for (i, dy) in [64.0, 112, 160, 208].enumerated() {
            let short = i == 3
            let inner: CGFloat = short && side < 0 ? 110 : 40, outerInset: CGFloat = short && side > 0 ? 120 : 44
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

    // 书脊折线。
    ctx.setLineWidth(5); ctx.setStrokeColor(rgb(p.spine))
    ctx.move(to: spineTop); ctx.addLine(to: spineBottom); ctx.strokePath()

    // 声波：书页上方升起，中间高两侧低。
    let heights: [CGFloat] = [64, 132, 196, 252, 196, 132, 64]
    let barWidth: CGFloat = 32, gap: CGFloat = 24, center = CGPoint(x: 512, y: 318)
    let total = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * gap
    for (i, h) in heights.enumerated() {
        let x = center.x - total / 2 + CGFloat(i) * (barWidth + gap)
        let bar = CGPath(roundedRect: CGRect(x: x, y: center.y - h / 2, width: barWidth, height: h), cornerWidth: barWidth / 2, cornerHeight: barWidth / 2, transform: nil)
        ctx.addPath(bar)
        let alpha: CGFloat = i == 3 ? 1 : (i == 2 || i == 4 ? 0.88 : (i == 1 || i == 5 ? 0.7 : 0.5))
        ctx.setFillColor(rgb(p.wave, alpha)); ctx.fillPath()
    }

    let image = ctx.makeImage()!
    let out = URL(fileURLWithPath: outDir).appendingPathComponent("icon-\(name).png")
    let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
    print("written", out.path)
}

for (name, palette) in variants { render(name, palette) }
