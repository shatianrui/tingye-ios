import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Preserve Figma's pixel geometry; strip only the redundant alpha channel for App Store validation.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let folder = root.appendingPathComponent("Design/v19-margin")
let output = root.appendingPathComponent("Tingye/Resources/Assets.xcassets/AppIcon.appiconset")
for (mode, filename) in [("light", "AppIcon.png"), ("dark", "AppIcon-dark.png"), ("tinted", "AppIcon-tinted.png")] {
    let input = folder.appendingPathComponent("AppIcon-\(mode)-figma.png")
    guard let source = CGImageSourceCreateWithURL(input as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil), image.width == 1024, image.height == 1024,
          let context = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0,
              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
        fatalError("Invalid 1024px Figma export: \(input.path)")
    }
    context.draw(image, in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
    guard let opaque = context.makeImage(),
          let dest = CGImageDestinationCreateWithURL(output.appendingPathComponent(filename) as CFURL, UTType.png.identifier as CFString, 1, nil) else { fatalError("Unable to export icon") }
    CGImageDestinationAddImage(dest, opaque, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("Unable to finish icon") }
    print("\(filename): 1024 × 1024, opaque RGB; exact Figma export")
}
