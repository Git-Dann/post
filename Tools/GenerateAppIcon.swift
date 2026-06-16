// Renders the Post app icon (1024×1024 PNG) with CoreGraphics.
// Run: swift Tools/GenerateAppIcon.swift
import CoreGraphics
import ImageIO
import Foundation
import UniformTypeIdentifiers

let size = 1024
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
guard let ctx = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
    space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { fatalError("ctx") }

let rect = CGRect(x: 0, y: 0, width: size, height: size)

// Warm amber → orange diagonal gradient background.
let colors = [
    CGColor(srgbRed: 0.99, green: 0.78, blue: 0.28, alpha: 1),
    CGColor(srgbRed: 0.96, green: 0.46, blue: 0.13, alpha: 1)
] as CFArray
let gradient = CGGradient(colorsSpace: cs, colors: colors, locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])

// Soft highlight glow upper-right.
let glow = [
    CGColor(srgbRed: 1, green: 0.97, blue: 0.85, alpha: 0.55),
    CGColor(srgbRed: 1, green: 0.97, blue: 0.85, alpha: 0)
] as CFArray
let radial = CGGradient(colorsSpace: cs, colors: glow, locations: [0, 1])!
ctx.drawRadialGradient(radial,
    startCenter: CGPoint(x: size * 7 / 10, y: size * 7 / 10), startRadius: 0,
    endCenter: CGPoint(x: size * 7 / 10, y: size * 7 / 10), endRadius: CGFloat(size) * 0.55,
    options: [])

// White 8-point sparkle star, centered.
let center = CGPoint(x: size / 2, y: size / 2)
let outer = CGFloat(size) * 0.34
let inner = CGFloat(size) * 0.13
let points = 8
let path = CGMutablePath()
for i in 0..<(points * 2) {
    let r = i % 2 == 0 ? outer : inner
    let angle = (CGFloat(i) / CGFloat(points * 2)) * 2 * .pi - .pi / 2
    let p = CGPoint(x: center.x + cos(angle) * r, y: center.y + sin(angle) * r)
    if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
}
path.closeSubpath()

ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 40,
              color: CGColor(srgbRed: 0.5, green: 0.2, blue: 0, alpha: 0.35))
ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
ctx.addPath(path)
ctx.fillPath()

guard let image = ctx.makeImage() else { fatalError("image") }
let outURL = URL(fileURLWithPath: "App/Assets.xcassets/AppIcon.appiconset/icon-1024.png")
guard let dest = CGImageDestinationCreateWithURL(outURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    fatalError("dest")
}
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
print("Wrote \(outURL.path)")
