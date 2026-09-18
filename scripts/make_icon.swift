// Draws the app icon into Client/macos/Resources/AppIcon.iconset (make icon). The "O" of Overhead, which is also a
// pair of headphones: a gradient ring and two ear cups on a dark squircle. Designed on a 100-unit grid and drawn
// at every size (not scaled down), into Apple's macOS icon template: the body is 824/1024 of the canvas, centred,
// with a soft shadow.
import AppKit

let coral = CGColor(srgbRed: 1.00, green: 0.54, blue: 0.36, alpha: 1)
let pink = CGColor(srgbRed: 0.91, green: 0.27, blue: 0.49, alpha: 1)
let violet = CGColor(srgbRed: 0.48, green: 0.25, blue: 0.89, alpha: 1)
let backgroundTop = CGColor(srgbRed: 0.165, green: 0.149, blue: 0.192, alpha: 1)
let backgroundBottom = CGColor(srgbRed: 0.067, green: 0.063, blue: 0.082, alpha: 1)
let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

// The mark, in the 100-unit grid (y down): the ring, then the ear cups. Each piece is filled on its own: filled
// together, their overlaps would cancel out.
let markPieces: [CGPath] = [
    CGPath(ellipseIn: CGRect(x: 26, y: 26, width: 48, height: 48), transform: nil)
        .copy(strokingWithWidth: 9, lineCap: .butt, lineJoin: .miter, miterLimit: 10),
    CGPath(roundedRect: CGRect(x: 16, y: 40, width: 13, height: 22), cornerWidth: 6.5, cornerHeight: 6.5, transform: nil),
    CGPath(roundedRect: CGRect(x: 71, y: 40, width: 13, height: 22), cornerWidth: 6.5, cornerHeight: 6.5, transform: nil),
]

func render(_ pixels: Int, to url: URL) throws {
    let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                            space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let canvas = CGFloat(pixels)
    let body = canvas * 824 / 1024
    let origin = (canvas - body) / 2
    context.translateBy(x: origin, y: origin + body)
    context.scaleBy(x: body / 100, y: -body / 100)

    let squircle = CGPath(roundedRect: CGRect(x: 0, y: 0, width: 100, height: 100),
                          cornerWidth: 22.5, cornerHeight: 22.5, transform: nil)
    if pixels >= 64 {  // at the smallest sizes a shadow only blurs the edge
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -1.2), blur: 2.4, color: CGColor(gray: 0, alpha: 0.35))
        context.addPath(squircle)
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fillPath()
        context.restoreGState()
    }

    context.saveGState()
    context.addPath(squircle)
    context.clip()
    let background = CGGradient(colorsSpace: sRGB, colors: [backgroundTop, backgroundBottom] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(background, start: .zero, end: CGPoint(x: 0, y: 100), options: [])
    context.restoreGState()

    let warm = CGGradient(colorsSpace: sRGB, colors: [coral, pink, violet] as CFArray, locations: [0, 0.55, 1])!
    for piece in markPieces {
        context.saveGState()
        context.addPath(piece)
        context.clip()
        context.drawLinearGradient(warm, start: CGPoint(x: 16, y: 26), end: CGPoint(x: 84, y: 74), options: [])
        context.restoreGState()
    }

    let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
}

let folder = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset")
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    try render(size, to: folder.appendingPathComponent("icon_\(size)x\(size).png"))
    try render(size * 2, to: folder.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
print("Icon -> \(folder.path)")
