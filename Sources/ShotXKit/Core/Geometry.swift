import CoreGraphics

/// Every coordinate conversion in the app. Pure: screen metrics are passed in.
///
/// Suffixes (mandatory everywhere):
/// - `AppKit`: global points, origin bottom-left of the primary display, y up (NSScreen, NSWindow, NSEvent.mouseLocation)
/// - `CG`: global points, origin top-left of the primary display, y down (ScreenCaptureKit, CGWindow, CGEvent)
/// - `InView`: points in a *flipped* view (origin top-left). A flipped view filling a display is display-local CG.
/// - `Px`: pixels in a CGImage, origin top-left.
nonisolated enum Geometry {
    // MARK: AppKit global <-> CG global. `primaryHeight` = height in points of NSScreen.screens[0].

    static func pointCG(fromAppKit pointAppKit: CGPoint, primaryHeight: CGFloat) -> CGPoint {
        CGPoint(x: pointAppKit.x, y: primaryHeight - pointAppKit.y)
    }

    static func pointAppKit(fromCG pointCG: CGPoint, primaryHeight: CGFloat) -> CGPoint {
        CGPoint(x: pointCG.x, y: primaryHeight - pointCG.y)
    }

    static func rectCG(fromAppKit rectAppKit: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rectAppKit.minX, y: primaryHeight - rectAppKit.maxY, width: rectAppKit.width, height: rectAppKit.height)
    }

    static func rectAppKit(fromCG rectCG: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rectCG.minX, y: primaryHeight - rectCG.maxY, width: rectCG.width, height: rectCG.height)
    }

    // MARK: CG global <-> display-local (points, origin top-left of that display)

    static func rectInDisplay(fromCG rectCG: CGRect, displayFrameCG: CGRect) -> CGRect {
        rectCG.offsetBy(dx: -displayFrameCG.minX, dy: -displayFrameCG.minY)
    }

    static func rectCG(fromInDisplay rectInDisplay: CGRect, displayFrameCG: CGRect) -> CGRect {
        rectInDisplay.offsetBy(dx: displayFrameCG.minX, dy: displayFrameCG.minY)
    }

    // MARK: View points <-> image pixels. `scale` = pixels per point.

    /// Edges are rounded to the nearest whole pixel, then the rect is clamped to the image.
    static func rectPx(fromInView rectInView: CGRect, scale: CGFloat, imageSizePx: CGSize) -> CGRect {
        let minXPx = (rectInView.minX * scale).rounded()
        let minYPx = (rectInView.minY * scale).rounded()
        let maxXPx = (rectInView.maxX * scale).rounded()
        let maxYPx = (rectInView.maxY * scale).rounded()
        let rectPx = CGRect(x: minXPx, y: minYPx, width: maxXPx - minXPx, height: maxYPx - minYPx)
        let clampedPx = rectPx.intersection(CGRect(origin: .zero, size: imageSizePx))
        return clampedPx.isNull ? .zero : clampedPx
    }

    static func rectInView(fromPx rectPx: CGRect, scale: CGFloat) -> CGRect {
        CGRect(x: rectPx.minX / scale, y: rectPx.minY / scale, width: rectPx.width / scale, height: rectPx.height / scale)
    }

    /// Pixel rect inside a display snapshot -> global CG points.
    static func rectCG(fromPx rectPx: CGRect, displayFrameCG: CGRect, scale: CGFloat) -> CGRect {
        rectCG(fromInDisplay: rectInView(fromPx: rectPx, scale: scale), displayFrameCG: displayFrameCG)
    }

    // MARK: Crop

    /// Crops to `rectPx` (top-left origin) clamped to the image. Nil when nothing is left.
    static func crop(_ image: CGImage, toPx rectPx: CGRect) -> CGImage? {
        let clampedPx = rectPx.integral.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard !clampedPx.isEmpty, let cropped = image.cropping(to: clampedPx) else { return nil }
        // `cropping` shares the whole source buffer; copy so a small crop (Quick Access card, pin,
        // editor) does not keep the full display snapshot alive. Same format, so pixels are unchanged.
        guard let space = cropped.colorSpace,
              let context = CGContext(data: nil, width: cropped.width, height: cropped.height,
                                      bitsPerComponent: cropped.bitsPerComponent, bytesPerRow: 0,
                                      space: space, bitmapInfo: cropped.bitmapInfo.rawValue)
        else { return cropped }
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: cropped.width, height: cropped.height))
        return context.makeImage() ?? cropped
    }
}
