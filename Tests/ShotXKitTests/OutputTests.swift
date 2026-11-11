import AppKit
import ImageIO
import Testing
@testable import ShotXKit

@MainActor
struct OutputTests {
    func makeImage(width: Int = 40, height: Int = 20) throws -> CGImage {
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try #require(context.makeImage())
    }

    /// Pixel width, pixel height and DPI as ImageIO reads them back.
    func metadata(_ data: Data) throws -> (width: Int, height: Int, dpiWidth: Double, dpiHeight: Double, type: String) {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        return (
            try #require(properties[kCGImagePropertyPixelWidth] as? Int),
            try #require(properties[kCGImagePropertyPixelHeight] as? Int),
            try #require(properties[kCGImagePropertyDPIWidth] as? Double),
            try #require(properties[kCGImagePropertyDPIHeight] as? Double),
            try #require(CGImageSourceGetType(source) as String?)
        )
    }

    @Test func jpegFlattensTransparencyOntoWhite() throws {
        let clear = try #require(CGContext(
            data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let data = try ImageEncoder.data(try #require(clear.makeImage()), scale: 1, format: .jpeg)
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        var pixel = [UInt8](repeating: 0, count: 4)
        let probe = try #require(CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                           space: CGColorSpaceCreateDeviceRGB(),
                                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        probe.draw(decoded, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        #expect(pixel[0] > 240 && pixel[1] > 240 && pixel[2] > 240)
    }

    @Test(arguments: [ImageFormat.png, .jpeg], [1.0, 2.0])
    func encoderKeepsPixelSizeAndWritesDPI(format: ImageFormat, scale: Double) throws {
        let data = try ImageEncoder.data(try makeImage(), scale: scale, format: format)
        let meta = try metadata(data)
        #expect(meta.width == 40)
        #expect(meta.height == 20)
        // PNG stores pixels per metre, so the value comes back a hair off 72 * scale.
        #expect(abs(meta.dpiWidth - 72 * scale) < 0.01)
        #expect(abs(meta.dpiHeight - 72 * scale) < 0.01)
        #expect(meta.type == (format == .png ? "public.png" : "public.jpeg"))
    }

    @Test func fileNameFollowsPatternAndAvoidsCollisions() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("shotx-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        // Built from local-time components because the name uses the user's time zone.
        let components = DateComponents(year: 2026, month: 3, day: 7, hour: 14, minute: 5, second: 9)
        let date = try #require(Calendar(identifier: .gregorian).date(from: components))

        let first = FileNaming.url(in: directory, date: date, ext: "png")
        #expect(first.lastPathComponent == "shotX 2026-03-07 at 14.05.09.png")
        #expect(first.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL)
        #expect(FileNaming.url(in: directory, date: date, ext: "png") == first)

        try Data().write(to: first)
        let second = FileNaming.url(in: directory, date: date, ext: "png")
        #expect(second.lastPathComponent == "shotX 2026-03-07 at 14.05.09 2.png")

        try Data().write(to: second)
        #expect(FileNaming.url(in: directory, date: date, ext: "png").lastPathComponent == "shotX 2026-03-07 at 14.05.09 3.png")
        // A different extension does not collide.
        #expect(FileNaming.url(in: directory, date: date, ext: "jpg").lastPathComponent == "shotX 2026-03-07 at 14.05.09.jpg")
    }

    @Test func clipboardRoundTripsImage() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("local.shotx.tests.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("stale", forType: .string)

        Clipboard.copy(image: try makeImage(), scale: 2, to: pasteboard)

        #expect(pasteboard.string(forType: .string) == nil)
        for type in [NSPasteboard.PasteboardType.png, .tiff] {
            let meta = try metadata(try #require(pasteboard.data(forType: type)))
            #expect(meta.width == 40)
            #expect(meta.height == 20)
            #expect(abs(meta.dpiWidth - 144) < 0.01)
        }
        // AppKit sees the point size, which is what makes it paste at the right size.
        let image = try #require(NSImage(pasteboard: pasteboard))
        #expect(abs(image.size.width - 20) < 0.01)
        #expect(abs(image.size.height - 10) < 0.01)
    }

    @Test func clipboardRoundTripsText() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("local.shotx.tests.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.setData(Data([1]), forType: .png)

        Clipboard.copy(text: "héllo\nwörld", to: pasteboard)

        #expect(pasteboard.string(forType: .string) == "héllo\nwörld")
        #expect(pasteboard.data(forType: .png) == nil)
    }
}
