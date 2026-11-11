// Draws the shotX app icon and writes Support/AppIcon.icns.
// Run from the repo root: swift scripts/make-icon.swift [preview.png]
// With an argument it only writes a 512px preview PNG there.
import CoreGraphics
import Foundation
import ImageIO

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("make-icon: \(message)\n".utf8))
    exit(1)
}

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// Draws the icon on a 1024-unit canvas scaled to `px` pixels.
func render(px: Int) -> CGImage {
    let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    guard
        let ctx = CGContext(
            data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { fail("cannot create \(px)px context") }
    ctx.scaleBy(x: CGFloat(px) / 1024, y: CGFloat(px) / 1024)

    // Tile: 824pt rounded rect on the standard macOS icon grid, with a soft drop shadow.
    let tile = CGPath(
        roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824),
        cornerWidth: 186, cornerHeight: 186, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: rgb(0x000000, 0.35))
    ctx.addPath(tile)
    ctx.setFillColor(rgb(0x1B1F5E))
    ctx.fillPath()
    ctx.restoreGState()

    // Gradient: teal (top-left) to deep indigo (bottom-right).
    ctx.saveGState()
    ctx.addPath(tile)
    ctx.clip()
    let colors = [rgb(0x34E0C2), rgb(0x2F7BF0), rgb(0x2A1F7A)] as CFArray
    if let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 0.5, 1]) {
        ctx.drawLinearGradient(
            gradient, start: CGPoint(x: 180, y: 924), end: CGPoint(x: 844, y: 100), options: [])
    }
    ctx.restoreGState()

    // Motif: four selection-corner brackets framing a tilted warm square (the "shot").
    let lo: CGFloat = 290, hi: CGFloat = 734, arm: CGFloat = 130
    ctx.setStrokeColor(rgb(0xFFFFFF))
    ctx.setLineWidth(52)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    for (x, y, dx, dy) in [(lo, lo, arm, arm), (hi, lo, -arm, arm), (lo, hi, arm, -arm), (hi, hi, -arm, -arm)] {
        ctx.move(to: CGPoint(x: x + dx, y: y))
        ctx.addLine(to: CGPoint(x: x, y: y))
        ctx.addLine(to: CGPoint(x: x, y: y + dy))
    }
    ctx.strokePath()

    ctx.translateBy(x: 512, y: 512)
    ctx.rotate(by: .pi / 4)
    ctx.addPath(
        CGPath(
            roundedRect: CGRect(x: -78, y: -78, width: 156, height: 156),
            cornerWidth: 34, cornerHeight: 34, transform: nil))
    ctx.setFillColor(rgb(0xFFC94D))
    ctx.fillPath()

    guard let image = ctx.makeImage() else { fail("cannot render \(px)px image") }
    return image
}

func writePNG(_ image: CGImage, to url: URL) {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)
    else { fail("cannot write \(url.path)") }
    CGImageDestinationAddImage(dest, image, nil)
    if !CGImageDestinationFinalize(dest) { fail("cannot write \(url.path)") }
}

if CommandLine.arguments.count > 1 {
    writePNG(render(px: 512), to: URL(fileURLWithPath: CommandLine.arguments[1]))
    exit(0)
}

let fm = FileManager.default
let iconset = fm.temporaryDirectory.appendingPathComponent("shotX-\(getpid()).iconset")
defer { try? fm.removeItem(at: iconset) }
do {
    try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
    for points in [16, 32, 128, 256, 512] {
        writePNG(render(px: points), to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
        writePNG(render(px: points * 2), to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
    }
    let iconutil = Process()
    iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    iconutil.arguments = ["-c", "icns", iconset.path, "-o", "Support/AppIcon.icns"]
    try iconutil.run()
    iconutil.waitUntilExit()
    if iconutil.terminationStatus != 0 { fail("iconutil exited with \(iconutil.terminationStatus)") }
} catch {
    fail("\(error)")
}
print("wrote Support/AppIcon.icns")
