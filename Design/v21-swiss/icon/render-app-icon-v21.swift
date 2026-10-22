import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import AppKit

// 听页 · v21 瑞士网格图标候选：与 v21 界面同源（苏黎世白 / 近黑墨 / 信号蓝 #0057FF / 无渐变无装饰圆角）。
// 候选：
//   turning-light  官方「翻页成声」白底蓝符号（icon-board 变体 A）
//   turning-blue   官方「翻页成声」蓝底白符号（icon-board PRIMARY · 变体 B）
//   turning-dark   官方「翻页成声」墨底亮蓝符号（icon-board 变体 C，可兼作深色图标）
//   ticks-light    「刻度」白底：v21 播放器进度轨母题，已播刻度信号蓝
//   ticks-blue     「刻度」蓝底
//   type-light     「字标」白底：PingFang  Semibold「听」+ 信号蓝方块 + mono 眉题
// swift Design/v21-swiss/icon/render-app-icon-v21.swift            # 渲染全部候选到 out/
// swift Design/v21-swiss/icon/render-app-icon-v21.swift <concept> <output.png>

let size = 1024
let blue = #colorLiteral(red: 0, green: 0.341, blue: 1, alpha: 1).cgColor          // #0057FF
let blueBright = #colorLiteral(red: 0.302, green: 0.486, blue: 0.996, alpha: 1).cgColor // #4D7CFE
let ink = #colorLiteral(red: 0.094, green: 0.094, blue: 0.106, alpha: 1).cgColor  // #18181B
let paper = #colorLiteral(red: 1, green: 1, blue: 1, alpha: 1).cgColor            // #FFFFFF
let night = #colorLiteral(red: 0.043, green: 0.043, blue: 0.047, alpha: 1).cgColor // #0B0B0C
let tickGrey = #colorLiteral(red: 0.894, green: 0.894, blue: 0.906, alpha: 1).cgColor // #E4E4E7
let tickGreyDark = #colorLiteral(red: 0.23, green: 0.23, blue: 0.26, alpha: 1).cgColor

func makeContext() -> CGContext {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    // 位图上下文为 y 向上坐标（y=0 在成品 PNG 底部）；文字基线同样在 y 向上空间。
    return CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                     space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
}

/// 按 SVG 习惯的 y 向下值给出对应坐标（便于对照 icon-board 的 64 网格 ×16）
func Y(_ yDown: Double) -> CGFloat { CGFloat(size) - CGFloat(yDown) }

func save(_ ctx: CGContext, to url: URL) {
    let image = ctx.makeImage()!
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
    print("rendered", url.path)
}

// 官方符号（64 单位网格 ×16）：翻开的书页化成三道声弧
func drawTurningPage(_ ctx: CGContext, symbol: CGColor) {
    let s: CGFloat = 16
    ctx.setFillColor(symbol)
    ctx.move(to: CGPoint(x: 9 * s, y: Y(17.5 * 16)))
    ctx.addLine(to: CGPoint(x: 30 * s, y: Y(23.5 * 16)))
    ctx.addLine(to: CGPoint(x: 30 * s, y: Y(50 * 16)))
    ctx.addLine(to: CGPoint(x: 9 * s, y: Y(43.5 * 16)))
    ctx.closePath()
    ctx.fillPath()
    ctx.setStrokeColor(symbol)
    ctx.setLineWidth(3.5 * s)
    ctx.setLineCap(.round)
    for r in [10.0, 16.0, 22.0] as [Double] {
        let center = CGPoint(x: 30 * s, y: Y(50 * 16))
        let radius = CGFloat(r) * s
        let path = CGMutablePath()
        let steps = 40
        for i in 0...steps {
            // y 向下设计稿中 θ ∈ [-75°, -15°]；换算到 y 向上为 [15°, 75°]
            let theta = (15.0 + 60.0 * Double(i) / Double(steps)) * .pi / 180
            let point = CGPoint(x: center.x + radius * CGFloat(cos(theta)), y: center.y + radius * CGFloat(sin(theta)))
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        ctx.addPath(path)
        ctx.strokePath()
    }
}

// 「刻度」：播放器进度轨母题，11 根刻度，前 6 根已播（高、信号蓝/白），其余未播（矮、灰）
func drawTicks(_ ctx: CGContext, background: CGColor, done: CGColor, todo: CGColor) {
    ctx.setFillColor(background)
    ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
    let count = 11
    let tickW: CGFloat = 30
    let gap: CGFloat = 54
    let total = CGFloat(count) * tickW + CGFloat(count - 1) * gap
    let startX = (CGFloat(size) - total) / 2
    let midY = CGFloat(size) / 2
    for i in 0..<count {
        let played = i < 6
        let h: CGFloat = played ? 380 : 150
        ctx.setFillColor(played ? done : todo)
        let rect = CGRect(x: startX + CGFloat(i) * (tickW + gap), y: midY - h / 2, width: tickW, height: h)
        ctx.fill(rect)
    }
}

// 「字标」：瑞士排版——超大无衬线「听」、信号蓝方块句号、mono 眉题
func drawType(_ ctx: CGContext, background: CGColor, foreground: CGColor, accent: CGColor) {
    ctx.setFillColor(background)
    ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
    // 眉题：mono 大写 + 宽字距，左上（基线 y=104）
    let masthead = "TINGYE — 听页"
    let mono = CTFontCreateWithName("Menlo-Bold" as CFString, 34, nil)
    let mastheadAttr = NSAttributedString(string: masthead, attributes: [
        .font: mono, .foregroundColor: foreground, .kern: 10
    ])
    drawText(mastheadAttr, in: ctx, at: CGPoint(x: 72, y: Y(104)))
    // 眉题下的粗墨线
    ctx.setFillColor(foreground)
    ctx.fill(CGRect(x: 72, y: Y(146), width: CGFloat(size - 144), height: 6))
    // 主字「听」：PingFang Semibold，基线处字形约占画面 317–850（y 向下设计值）
    let font = CTFontCreateWithName("PingFangSC-Semibold" as CFString, 620, nil)
    let ting = NSAttributedString(string: "听", attributes: [.font: font, .foregroundColor: foreground])
    drawText(ting, in: ctx, at: CGPoint(x: 40, y: Y(850)))
    // 信号蓝方块「句号」，对齐字基线右侧
    ctx.setFillColor(accent)
    ctx.fill(CGRect(x: 810, y: Y(862), width: 120, height: 120))
    // 底部署名
    let footer = "READ · LISTEN — NO.21"
    let footerAttr = NSAttributedString(string: footer, attributes: [
        .font: CTFontCreateWithName("Menlo-Bold" as CFString, 30, nil), .foregroundColor: accent, .kern: 6
    ])
    drawText(footerAttr, in: ctx, at: CGPoint(x: 72, y: Y(966)))
}

// 在 y 向下坐标系里画文字：textPosition 即基线起点，字形向上伸出
func drawText(_ text: NSAttributedString, in ctx: CGContext, at point: CGPoint) {
    ctx.saveGState()
    let line = CTLineCreateWithAttributedString(text)
    ctx.textPosition = point
    CTLineDraw(line, ctx)
    ctx.restoreGState()
}

func render(_ concept: String, to url: URL) {
    let ctx = makeContext()
    switch concept {
    case "turning-light":
        ctx.setFillColor(paper); ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
        drawTurningPage(ctx, symbol: blue)
    case "turning-blue":
        ctx.setFillColor(blue); ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
        drawTurningPage(ctx, symbol: paper)
    case "turning-dark":
        ctx.setFillColor(night); ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
        drawTurningPage(ctx, symbol: blueBright)
    case "ticks-light":
        drawTicks(ctx, background: paper, done: blue, todo: tickGrey)
    case "ticks-blue":
        drawTicks(ctx, background: blue, done: paper, todo: #colorLiteral(red: 1, green: 1, blue: 1, alpha: 0.35).cgColor)
    case "type-light":
        drawType(ctx, background: paper, foreground: ink, accent: blue)
    case "turning-tinted":
        // 着色变体：灰阶（着色模式下系统再叠加色调）
        ctx.setFillColor(#colorLiteral(red: 0.541, green: 0.541, blue: 0.541, alpha: 1).cgColor) // #8A8A8A
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
        drawTurningPage(ctx, symbol: #colorLiteral(red: 0.91, green: 0.91, blue: 0.91, alpha: 1).cgColor) // #E8E8E8
    default:
        print("unknown concept:", concept); exit(1)
    }
    save(ctx, to: url)
}

let folder = URL(fileURLWithPath: "Design/v21-swiss/icon/out", isDirectory: true)
let concepts = ["turning-light", "turning-blue", "turning-dark", "ticks-light", "ticks-blue", "type-light"]
if CommandLine.arguments.count > 2, CommandLine.arguments[1] == "final" {
    // 最终三变体：直接写入 AppIcon.appiconset（日间 A 白底 / 深色 C 墨底亮蓝 / 着色灰阶）
    let set = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
    render("turning-light", to: set.appendingPathComponent("AppIcon.png"))
    render("turning-dark", to: set.appendingPathComponent("AppIcon-dark.png"))
    render("turning-tinted", to: set.appendingPathComponent("AppIcon-tinted.png"))
} else if CommandLine.arguments.count > 2 {
    render(CommandLine.arguments[1], to: URL(fileURLWithPath: CommandLine.arguments[2]))
} else {
    for name in concepts { render(name, to: folder.appendingPathComponent("v21-" + name + ".png")) }
}
