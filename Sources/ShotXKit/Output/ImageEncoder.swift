import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// ImageIO encoding. `scale` sets DPI metadata (72 * scale) so Retina captures open and paste at point size.
nonisolated enum ImageEncoder {
    static let jpegQuality = 0.9

    struct EncodingFailed: LocalizedError {
        var type: UTType
        var errorDescription: String? { "Could not encode the image as \(type.localizedDescription ?? type.identifier)." }
    }

    static func data(_ image: CGImage, scale: CGFloat, format: ImageFormat) throws -> Data {
        try data(image, scale: scale, type: format == .png ? .png : .jpeg)
    }

    /// Also used by `Clipboard` for TIFF.
    static func data(_ image: CGImage, scale: CGFloat, type: UTType) throws -> Data {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil) else {
            throw EncodingFailed(type: type)
        }
        let dpi = 72 * Double(scale)
        var properties: [CFString: Any] = [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi]
        if type == .jpeg {
            properties[kCGImageDestinationLossyCompressionQuality] = jpegQuality
            // JPEG has no alpha: transparent pixels (window captures, their shadow) become white, not black.
            properties[kCGImageDestinationBackgroundColor] = CGColor(gray: 1, alpha: 1)
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw EncodingFailed(type: type) }
        return output as Data
    }
}
