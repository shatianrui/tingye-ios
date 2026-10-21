// Presentation only: arranges GPT-generated pixels and applies preview corner masks.
// Does not draw, trace, recolor, or replace the generated icon artwork.
import Foundation
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

let directory = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Design/icon-margin-gpt", isDirectory: true)
let width = 1400, height = 1020
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
context.interpolationQuality = .high

func color(_ hex: UInt32) -> CGColor {
    CGColor(colorSpace: space, components: [CGFloat((hex >> 16) & 255) / 255, CGFloat((hex >> 8) & 255) / 255, CGFloat(hex & 255) / 255, 1])!
}
func rect(_ x: CGFloat, _ top: CGFloat, _ w: CGFloat, _ h: CGFloat, _ fill: UInt32) {
    context.setFillColor(color(fill))
    context.fill(CGRect(x: x, y: CGFloat(height) - top - h, width: w, height: h))
}
func text(_ value: String, x: CGFloat, top: CGFloat, size: CGFloat, weight: String = "Regular", fill: UInt32 = 0x292D29) {
    let font = CTFontCreateWithName("PingFangSC-\(weight)" as CFString, size, nil)
    let attrs: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): color(fill)
    ]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: value, attributes: attrs))
    context.textMatrix = .identity
    context.textPosition = CGPoint(x: x, y: CGFloat(height) - top - CTFontGetAscent(font))
    CTLineDraw(line, context)
}
func readImage(_ name: String) -> CGImage {
    let source = CGImageSourceCreateWithURL(directory.appendingPathComponent(name) as CFURL, nil)!
    return CGImageSourceCreateImageAtIndex(source, 0, nil)!
}
func icon(_ image: CGImage, x: CGFloat, top: CGFloat, size: CGFloat) {
    context.saveGState()
    let box = CGRect(x: x, y: CGFloat(height) - top - size, width: size, height: size)
    context.addPath(CGPath(roundedRect: box, cornerWidth: size * 0.22, cornerHeight: size * 0.22, transform: nil))
    context.clip()
    context.draw(image, in: box)
    context.restoreGState()
}

let a = readImage("a-paper-echo-original.png")
let b = readImage("b-night-pages-original.png")
rect(0, 0, CGFloat(width), CGFloat(height), 0xF6F3EC)
text("听页 · 新图标候选", x: 64, top: 42, size: 42, weight: "Semibold")
text("OpenAI GPT Image  /  暖纸 · 石墨 · 陶橙", x: 66, top: 104, size: 21, fill: 0x62665D)
rect(64, 150, 1272, 1, 0xDEDCD2)

for (index, image) in [a, b].enumerated() {
    let left: CGFloat = index == 0 ? 64 : 728
    text(index == 0 ? "A  纸间回声" : "B  静夜翻页", x: left, top: 178, size: 30, weight: "Semibold")
    text(index == 0 ? "暖纸底 / 石墨书脊 / 陶橙翻页" : "石墨底 / 暖白书页 / 轻折纸质感", x: left, top: 226, size: 20, fill: 0x62665D)
    icon(image, x: left + 48, top: 276, size: 512)
    text("缩小识别预览", x: left, top: 823, size: 19, fill: 0x62665D)
    for (sizeIndex, size) in [CGFloat(60), 48, 32].enumerated() {
        let x = left + 196 + CGFloat(sizeIndex) * 118
        icon(image, x: x, top: 817 + (60 - size) / 2, size: size)
        text("\(Int(size)) px", x: x, top: 889, size: 16, fill: 0x62665D)
    }
}
rect(64, 934, 1272, 1, 0xDEDCD2)
text("原始候选对比；110 已采用 A。原图 RGB 无透明通道；圆角仅为展示，两款不是日夜变体。", x: 64, top: 958, size: 18, fill: 0x62665D)
let output = directory.appendingPathComponent("comparison.png")
let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, context.makeImage()!, nil)
precondition(CGImageDestinationFinalize(destination))
print(output.path)
