// The selected GPT Image artwork is the source. No icon geometry is drawn here.
// Light is copied byte-for-byte. Dark uses an edge-connected background mask and
// tonal adaptation; tinted is neutral grayscale derived from that same artwork.
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let folder = root.appendingPathComponent("Design/icon-margin-gpt")
let output = folder.appendingPathComponent("final", isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let input = folder.appendingPathComponent("a-paper-echo-original.png")
guard let source = CGImageSourceCreateWithURL(input as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
      image.width == 1024, image.height == 1024 else { fatalError("Expected the selected 1024px artwork") }
let w = image.width, h = image.height, count = w * h
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.noneSkipLast.rawValue
let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space, bitmapInfo: bitmapInfo)!
context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
let original = Array(UnsafeBufferPointer(start: context.data!.assumingMemoryBound(to: UInt8.self), count: count * 4))

func luminance(_ r: Double, _ g: Double, _ b: Double) -> Double { 0.2126 * r + 0.7152 * g + 0.0722 * b }
func smooth(_ low: Double, _ high: Double, _ value: Double) -> Double {
    let t = min(1, max(0, (value - low) / (high - low)))
    return t * t * (3 - 2 * t)
}
func byte(_ value: Double) -> UInt8 { UInt8(min(255, max(0, value.rounded()))) }
func backgroundCandidate(_ p: Int) -> Bool {
    let i = p * 4
    let dr = Double(original[i]) - 247
    let dg = Double(original[i+1]) - 245
    let db = Double(original[i+2]) - 238
    return dr*dr + dg*dg + db*db <= 96
}

// Only background-colored pixels reachable from the canvas edge are selected.
// Similar warm tones enclosed inside the actual book are deliberately retained.
var background = [UInt8](repeating: 0, count: count)
var queue = [Int]()
queue.reserveCapacity(count)
func visit(_ p: Int) {
    if background[p] == 0 && backgroundCandidate(p) {
        background[p] = 1
        queue.append(p)
    }
}
for x in 0..<w { visit(x); visit((h-1)*w+x) }
for y in 0..<h { visit(y*w); visit(y*w+w-1) }
var cursor = 0
while cursor < queue.count {
    let p = queue[cursor]; cursor += 1
    let x = p % w, y = p / w
    if x > 0 { visit(p-1) }; if x+1 < w { visit(p+1) }
    if y > 0 { visit(p-w) }; if y+1 < h { visit(p+w) }
}
let backgroundCount = background.reduce(0, { $0 + Int($1) })
precondition(backgroundCount > count/2 && backgroundCount < count*4/5, "Unexpected segmentation; review the source rather than shipping a damaged mask")

// Standard raster-matte cleanup, not a newly drawn silhouette. Close tiny grain
// gaps, feather one pixel, and sample inward to remove the old ivory edge fringe.
func morphology(_ mask: [UInt8], radius: Int, expand: Bool) -> [UInt8] {
    var horizontal = mask, result = mask
    for y in 0..<h { for x in 0..<w {
        var value: UInt8 = expand ? 0 : 1
        for dx in -radius...radius {
            let sample = mask[y*w + min(w-1,max(0,x+dx))]
            value = expand ? max(value,sample) : min(value,sample)
        }
        horizontal[y*w+x] = value
    } }
    for y in 0..<h { for x in 0..<w {
        var value: UInt8 = expand ? 0 : 1
        for dy in -radius...radius {
            let sample = horizontal[min(h-1,max(0,y+dy))*w+x]
            value = expand ? max(value,sample) : min(value,sample)
        }
        result[y*w+x] = value
    } }
    return result
}
let foreground = background.map { 1 - $0 }
let closed = morphology(morphology(foreground, radius: 2, expand: true), radius: 2, expand: false)
let interior = morphology(closed, radius: 3, expand: false)
var alpha = [Double](repeating: 0, count: count)
let weights = [1,2,1]
for y in 1..<(h-1) { for x in 1..<(w-1) {
    var sum = 0
    for dy in -1...1 { for dx in -1...1 {
        sum += Int(closed[(y+dy)*w+x+dx]) * weights[dy+1] * weights[dx+1]
    } }
    alpha[y*w+x] = Double(sum)/16
} }

var dark = original
var tinted = original
for p in 0..<count {
    let i = p*4, coverage = alpha[p]
    var sourcePixel = p
    if coverage > 0 && interior[p] == 0 {
        let x = p%w, y = p/w
        var closest = Int.max
        for dy in -6...6 { for dx in -6...6 {
            let sx=x+dx, sy=y+dy, distance=dx*dx+dy*dy
            if sx>=0 && sx<w && sy>=0 && sy<h && distance<closest && interior[sy*w+sx] == 1 {
                sourcePixel=sy*w+sx; closest=distance
            }
        } }
    }
    let j=sourcePixel*4
    let r=Double(original[j]), g=Double(original[j+1]), b=Double(original[j+2])
    let light=luminance(r,g,b)
    let chroma=max(r,g,b)-min(r,g,b)
    let lift=(1-smooth(18,42,chroma))*(1-smooth(70,145,light))*58
    // Lift only the graphite cover; paper and terracotta keep their material.
    let foregroundColor=[r+lift,g+lift*1.08,b+lift]
    let originalLight=luminance(Double(original[i]),Double(original[i+1]),Double(original[i+2]))
    let grain=coverage == 0 ? min(1,max(-1,(originalLight-245)*0.28)) : 0
    let backdrop=[25+grain,27+grain,26+grain]
    let channels=(0..<3).map { coverage*foregroundColor[$0]+(1-coverage)*backdrop[$0] }
    dark[i]=byte(channels[0]); dark[i+1]=byte(channels[1]); dark[i+2]=byte(channels[2]); dark[i+3]=255
    let gray=byte(luminance(channels[0],channels[1],channels[2]))
    tinted[i]=gray; tinted[i+1]=gray; tinted[i+2]=gray; tinted[i+3]=255
}
func save(_ pixels: [UInt8], _ name: String) {
    let provider = CGDataProvider(data: Data(pixels) as CFData)!
    let outputImage = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32,
        bytesPerRow: w*4, space: space, bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
        provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
    let dest = CGImageDestinationCreateWithURL(output.appendingPathComponent(name) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, outputImage, nil)
    precondition(CGImageDestinationFinalize(dest))
}
try Data(contentsOf: input).write(to: output.appendingPathComponent("AppIcon.png"))
save(dark, "AppIcon-dark.png")
save(tinted, "AppIcon-tinted.png")
print("Background mask: \(backgroundCount)/\(count) pixels. Light copied verbatim; dark/tinted color-adapted from identical GPT artwork.")
