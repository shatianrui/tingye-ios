import CoreGraphics
import Foundation
import ImageIO

// Run from the repository root. Read-only checks of the final AppIcon resources.
let directory = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "Tingye/Resources/Assets.xcassets/AppIcon.appiconset"
let files = ["AppIcon.png", "AppIcon-dark.png", "AppIcon-tinted.png"]
for name in files {
    let url = URL(fileURLWithPath: directory).appendingPathComponent(name)
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        fatalError("Cannot decode \(name)")
    }
    precondition(image.width == 1024 && image.height == 1024, "Incorrect icon size: \(name)")
    precondition([CGImageAlphaInfo.none, .noneSkipFirst, .noneSkipLast].contains(image.alphaInfo), "Unexpected alpha channel: \(name)")
    let rowBytes = image.width * 4
    var pixels = [UInt8](repeating: 0, count: rowBytes * image.height)
    pixels.withUnsafeMutableBytes { raw in
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let flags = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(data: raw.baseAddress, width: image.width, height: image.height,
                                      bitsPerComponent: 8, bytesPerRow: rowBytes,
                                      space: space, bitmapInfo: flags) else {
            fatalError("Cannot create validation context")
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }
    var maximumChannelSpread = 0
    for index in stride(from: 0, to: pixels.count, by: 4) {
        precondition(pixels[index + 3] == 255, "Transparent pixel in \(name)")
        if name == "AppIcon-tinted.png" {
            let r = Int(pixels[index]), g = Int(pixels[index + 1]), b = Int(pixels[index + 2])
            maximumChannelSpread = max(maximumChannelSpread, max(r, g, b) - min(r, g, b))
        }
    }
    if name == "AppIcon-tinted.png" {
        precondition(maximumChannelSpread <= 1, "Tinted input must be grayscale")
    }
    print("PASS \(name): 1024 × 1024, all pixels opaque" +
          (name == "AppIcon-tinted.png" ? ", grayscale channel spread = \(maximumChannelSpread)" : ""))
}
