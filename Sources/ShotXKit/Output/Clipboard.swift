import AppKit

/// Pasteboard writes. The `to:` parameter exists for tests; production callers omit it.
enum Clipboard {
    /// Writes PNG and TIFF, both with DPI = 72 * scale so the image pastes at point size.
    static func copy(image: CGImage, scale: CGFloat, to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        do {
            pasteboard.setData(try ImageEncoder.data(image, scale: scale, type: .png), forType: .png)
            pasteboard.setData(try ImageEncoder.data(image, scale: scale, type: .tiff), forType: .tiff)
        } catch {
            // The frozen signature does not throw, so this is the only place the failure can surface.
            log.error("Clipboard.copy(image:) failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func copy(text: String, to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
