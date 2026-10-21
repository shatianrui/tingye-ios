// Create an inspection contact sheet from actual screenshots, never a UI mockup.
// Usage: swift contact-sheet.swift output.jpg image.png "caption" [image.png "caption" ...]
import Foundation
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

let args = Array(CommandLine.arguments.dropFirst())
guard args.count >= 3, args.count % 2 == 1 else { fatalError("output.jpg image caption ...") }
let count = (args.count - 1) / 2
let columns = min(3, count), rows = (count + columns - 1) / columns
let width = columns * 390, height = rows * 874
let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
    bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
context.setFillColor(CGColor(gray: 0.9, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: width, height: height))
context.interpolationQuality = .high
for i in 0..<count {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: args[i * 2 + 1]) as CFURL, nil),
          let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 2048
          ] as CFDictionary) else { fatalError("Missing screenshot") }
    let x = CGFloat(i % columns * 390), top = CGFloat(height - i / columns * 874)
    let label = NSAttributedString(string: args[i * 2 + 2], attributes: [
        NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, 13, nil),
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1)
    ])
    context.textPosition = CGPoint(x: x + 10, y: top - 20)
    CTLineDraw(CTLineCreateWithAttributedString(label), context)
    let scale = min(390 / CGFloat(image.width), 844 / CGFloat(image.height))
    let w = CGFloat(image.width) * scale, h = CGFloat(image.height) * scale
    context.draw(image, in: CGRect(x: x + (390 - w) / 2, y: top - 30 - h, width: w, height: h))
}
let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: args[0]) as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, context.makeImage()!, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
guard CGImageDestinationFinalize(destination) else { fatalError("Could not export contact sheet") }
print(args[0])
