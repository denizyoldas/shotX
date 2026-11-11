import CoreGraphics
import CoreImage
import CoreText
import Foundation
import Synchronization

/// The only place annotations are drawn; the editor canvas and the export share it.
/// Everything here is `nonisolated` and thread-safe, so a large export can run off the main actor
/// (call `export` from a `@concurrent` function).
nonisolated enum AnnotationRenderer {
    /// Draws the whole base image and then every annotation, back to front. The crop is *not*
    /// applied (the editor shows the full image and draws its own crop overlay).
    ///
    /// **Context contract:** the caller sets up the CTM so that user space is the document's
    /// pixel space: origin at the image's top-left corner, y growing downwards, one unit = one
    /// base-image pixel. The image then occupies `(0, 0, sizePx.width, sizePx.height)`.
    /// - Flipped `NSView` showing the image at `zoom` view points per image point:
    ///   `context.scaleBy(x: zoom / document.scale, y: zoom / document.scale)` (after any translation).
    /// - Plain bottom-left bitmap context of the image's size:
    ///   `context.translateBy(x: 0, y: height); context.scaleBy(x: 1, y: -1)`.
    /// The graphics state is restored before returning.
    static func render(_ document: AnnotationDocument, into context: CGContext) {
        context.saveGState()
        defer { context.restoreGState() }
        drawUpright(document.baseImage, into: context)
        for annotation in document.annotations {
            context.saveGState()
            draw(annotation, document: document, into: context)
            context.restoreGState()
        }
    }

    /// Final image: base + annotations, cut to `cropRectPx` when set. Same pixel density and
    /// colour space as the base image. nil only if the bitmap cannot be allocated.
    static func export(_ document: AnnotationDocument) -> CGImage? {
        let frame = document.cropRectPx ?? CGRect(origin: .zero, size: document.sizePx)
        let baseSpace = document.baseImage.colorSpace
        guard let space = baseSpace?.model == .rgb ? baseSpace : CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: Int(frame.width), height: Int(frame.height), bitsPerComponent: 8,
                                      bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.translateBy(x: 0, y: frame.height)
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: -frame.minX, y: -frame.minY)
        render(document, into: context)
        return context.makeImage()
    }

    /// Drops the cached blurred / pixelated copies. Call when an editor window closes.
    static func clearCache() {
        effects.withLock { $0 = EffectCache() }
    }

    // MARK: Shapes

    private static func draw(_ annotation: Annotation, document: AnnotationDocument, into context: CGContext) {
        let style = annotation.style
        context.setStrokeColor(style.color)
        context.setFillColor(style.color)
        context.setLineWidth(style.lineWidthPx)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        switch annotation.kind {
        case .arrow(let from, let to):
            drawArrow(from: from, to: to, lineWidthPx: style.lineWidthPx, into: context)
        case .line(let from, let to):
            context.strokeLineSegments(between: [from, to])
        case .rectangle(let rect):
            context.setLineJoin(.miter)
            context.stroke(rect.standardized)
        case .ellipse(let rect):
            context.strokeEllipse(in: rect.standardized)
        case .freehand(let points):
            guard let first = points.first else { return }
            context.move(to: first)
            // A single point still draws a dot thanks to the round cap.
            for point in points.count > 1 ? points.dropFirst() : points[...] { context.addLine(to: point) }
            context.strokePath()
        case .highlight(let rect):
            context.setFillColor(style.color.copy(alpha: 0.4) ?? style.color)
            context.fill(rect.standardized)
        case .blur(let rect):
            drawEffect(.blur, in: rect.standardized, document: document, into: context)
        case .pixelate(let rect):
            drawEffect(.pixelate, in: rect.standardized, document: document, into: context)
        case .text(let string, let origin):
            let layout = textLayout(string, style: style, bold: false)
            for (index, line) in layout.lines.enumerated() {
                drawLine(line, baselinePx: CGPoint(x: origin.x, y: origin.y + layout.ascent + CGFloat(index) * layout.lineHeight), into: context)
            }
        case .counter(let center, let number):
            let r = annotation.counterRadiusPx
            context.fillEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))
            var badge = style
            badge.color = CGColor(gray: 1, alpha: 1)
            let layout = textLayout(String(number), style: badge, bold: true)
            guard let line = layout.lines.first else { return }
            drawLine(line, baselinePx: CGPoint(x: center.x - layout.size.width / 2, y: center.y + layout.capHeight / 2), into: context)
        }
    }

    /// Shaft plus a filled triangular head whose size follows the line width.
    private static func drawArrow(from: CGPoint, to: CGPoint, lineWidthPx: CGFloat, into context: CGContext) {
        let length = hypot(to.x - from.x, to.y - from.y)
        guard length > 0 else { return }
        let ux = (to.x - from.x) / length, uy = (to.y - from.y) / length
        let headLength = min(lineWidthPx * Annotation.arrowHeadLengthFactor, length)
        let halfWidth = lineWidthPx * Annotation.arrowHeadHalfWidthFactor
        let neck = CGPoint(x: to.x - ux * headLength, y: to.y - uy * headLength)
        context.strokeLineSegments(between: [from, neck])
        context.move(to: to)
        context.addLine(to: CGPoint(x: neck.x - uy * halfWidth, y: neck.y + ux * halfWidth))
        context.addLine(to: CGPoint(x: neck.x + uy * halfWidth, y: neck.y - ux * halfWidth))
        context.closePath()
        context.fillPath()
    }

    /// CoreGraphics draws images bottom-up; undo the caller's y-flip locally so they appear upright.
    private static func drawUpright(_ image: CGImage, into context: CGContext) {
        context.saveGState()
        context.translateBy(x: 0, y: CGFloat(image.height))
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        context.restoreGState()
    }

    // MARK: Text

    struct TextLayout {
        var lines: [CTLine]
        var size: CGSize
        var ascent: CGFloat
        var lineHeight: CGFloat
        var capHeight: CGFloat
    }

    /// Lays out `string` (split at `\n`) in the system font at `style.fontSizePx`.
    /// Also used by `Annotation.boundsPx`, so bounds always match what is drawn.
    static func textLayout(_ string: String, style: Annotation.Style, bold: Bool) -> TextLayout {
        let font = CTFontCreateUIFontForLanguage(bold ? .emphasizedSystem : .system, style.fontSizePx, nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, style.fontSizePx, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): style.color,
        ]
        let lines = string.split(separator: "\n", omittingEmptySubsequences: false).map {
            CTLineCreateWithAttributedString(NSAttributedString(string: String($0), attributes: attributes))
        }
        let ascent = CTFontGetAscent(font)
        let lineHeight = ascent + CTFontGetDescent(font) + CTFontGetLeading(font)
        let width = lines.map { CTLineGetTypographicBounds($0, nil, nil, nil) }.max() ?? 0
        return TextLayout(lines: lines, size: CGSize(width: width, height: lineHeight * CGFloat(lines.count)),
                          ascent: ascent, lineHeight: lineHeight, capHeight: CTFontGetCapHeight(font))
    }

    private static func drawLine(_ line: CTLine, baselinePx: CGPoint, into context: CGContext) {
        // User space is y-down; flip the glyphs back with the text matrix.
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        context.textPosition = baselinePx
        CTLineDraw(line, context)
    }

    // MARK: Blur / pixelate

    private enum Effect { case blur, pixelate }

    private struct EffectCache: Sendable {
        var base: CGImage?
        var scale: CGFloat = 0
        var blurred: CGImage?
        var pixelated: CGImage?
    }

    // ponytail: keeps a fully blurred and a fully pixelated copy of the last base image (each made
    // on first use), so up to ~2x the image's memory on top of the base, held until another image
    // is rendered or clearCache(). Upgrade path: filter only the union of the effect rects.
    private static let effects = Mutex(EffectCache())
    private static let ciContext = CIContext()

    /// Draws the effect copy of the *base image* clipped to `rect`. Annotations below the rect are
    /// covered, not blurred.
    private static func drawEffect(_ effect: Effect, in rect: CGRect, document: AnnotationDocument, into context: CGContext) {
        guard let image = effectImage(effect, base: document.baseImage, scale: document.scale) else {
            // Fail closed: a redaction that cannot be rendered must not leave the region readable.
            log.error("annotation effect image could not be created; covering the region instead")
            context.setFillColor(gray: 0.5, alpha: 1)
            context.fill(rect)
            return
        }
        context.clip(to: rect)
        drawUpright(image, into: context)
    }

    private static func effectImage(_ effect: Effect, base: CGImage, scale: CGFloat) -> CGImage? {
        effects.withLock { cache in
            if cache.base !== base || cache.scale != scale { cache = EffectCache(base: base, scale: scale) }
            if let cached = effect == .blur ? cache.blurred : cache.pixelated { return cached }
            let input = CIImage(cgImage: base)
            let clamped = input.clampedToExtent()
            let output = switch effect {
            case .blur: clamped.applyingGaussianBlur(sigma: 10 * scale)
            case .pixelate: clamped.applyingFilter("CIPixellate", parameters: [kCIInputScaleKey: 12 * scale, kCIInputCenterKey: CIVector(x: 0, y: 0)])
            }
            let image = ciContext.createCGImage(output, from: input.extent, format: .RGBA8, colorSpace: base.colorSpace)
            if effect == .blur { cache.blurred = image } else { cache.pixelated = image }
            return image
        }
    }
}
