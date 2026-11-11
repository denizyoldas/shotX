import AppKit
import CoreText
import Testing
@testable import ShotXKit

struct OCRTests {
    /// White canvas with optional large black text, drawn with CoreText.
    private func makeImage(text: String?) throws -> CGImage {
        let context = try #require(CGContext(
            data: nil, width: 900, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(.white)
        context.fill(CGRect(x: 0, y: 0, width: 900, height: 200))
        if let text {
            let attributed = NSAttributedString(string: text, attributes: [
                .font: NSFont.systemFont(ofSize: 72), .foregroundColor: NSColor.black,
            ])
            context.textPosition = CGPoint(x: 40, y: 70)
            CTLineDraw(CTLineCreateWithAttributedString(attributed), context)
        }
        return try #require(context.makeImage())
    }

    @Test func recognizesRenderedText() async throws {
        let result = try await TextRecognizer.recognize(makeImage(text: "Hello World 12345"))
        let normalized = result.lowercased().filter { !$0.isWhitespace }
        #expect(normalized.contains("helloworld12345"), "got: \(result)")
    }

    @Test func blankImageGivesEmptyString() async throws {
        #expect(try await TextRecognizer.recognize(makeImage(text: nil)) == "")
    }
}
