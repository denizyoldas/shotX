import CoreGraphics
import Foundation

/// One drawn item of the annotation editor. A pure value: the editor changes an annotation by
/// building a modified copy and passing it to `AnnotationDocument.update(_:)`.
///
/// All geometry is in base-image pixels with a top-left origin (`Px`). Rects may be
/// un-normalised (negative width/height while dragging); every consumer standardises them.
nonisolated struct Annotation: Identifiable, Equatable, Sendable {
    nonisolated struct Style: Equatable, Sendable {
        var color: CGColor
        /// Stroke width for arrow, rectangle, ellipse, line and freehand.
        var lineWidthPx: CGFloat
        /// Font size for text; also sets the counter badge size.
        var fontSizePx: CGFloat

        /// Sensible defaults for an image captured at `scale` (red, 3 pt stroke, 16 pt font).
        static func standard(scale: CGFloat) -> Style {
            Style(color: CGColor(srgbRed: 1, green: 0.23, blue: 0.19, alpha: 1), lineWidthPx: 3 * scale, fontSizePx: 16 * scale)
        }
    }

    nonisolated enum Kind: Equatable, Sendable {
        /// Head at `toPx`.
        case arrow(fromPx: CGPoint, toPx: CGPoint)
        case rectangle(CGRect)
        case ellipse(CGRect)
        case line(fromPx: CGPoint, toPx: CGPoint)
        case freehand(pointsPx: [CGPoint])
        /// `originPx` is the top-left corner of the first line; `\n` starts a new line.
        case text(String, originPx: CGPoint)
        /// Semi-transparent marker rect in the style colour.
        case highlight(CGRect)
        case blur(CGRect)
        case pixelate(CGRect)
        /// Filled numbered badge. Take the number from `AnnotationDocument.nextCounterNumber`.
        case counter(centerPx: CGPoint, number: Int)
    }

    let id: UUID
    var kind: Kind
    var style: Style

    init(id: UUID = UUID(), kind: Kind, style: Style) {
        self.id = id
        self.kind = kind
        self.style = style
    }

    // Shared with AnnotationRenderer so bounds and drawing cannot drift apart.
    static let arrowHeadLengthFactor: CGFloat = 4
    static let arrowHeadHalfWidthFactor: CGFloat = 1.75
    var counterRadiusPx: CGFloat { style.fontSizePx * 0.9 }

    /// Smallest rect containing everything the renderer draws for this annotation
    /// (stroke width, arrow head and text extent included). Use it for the selection frame.
    var boundsPx: CGRect {
        let half = style.lineWidthPx / 2
        switch kind {
        case .arrow(let a, let b):
            let grow = max(half, style.lineWidthPx * Self.arrowHeadHalfWidthFactor)
            return Self.bounding([a, b]).insetBy(dx: -grow, dy: -grow)
        case .line(let a, let b):
            return Self.bounding([a, b]).insetBy(dx: -half, dy: -half)
        case .freehand(let points):
            return Self.bounding(points).insetBy(dx: -half, dy: -half)
        case .rectangle(let rect), .ellipse(let rect):
            return rect.standardized.insetBy(dx: -half, dy: -half)
        case .highlight(let rect), .blur(let rect), .pixelate(let rect):
            return rect.standardized
        case .text(let string, let origin):
            return CGRect(origin: origin, size: AnnotationRenderer.textLayout(string, style: style, bold: false).size)
        case .counter(let center, _):
            let r = counterRadiusPx
            return CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r)
        }
    }

    /// True when `pointPx` is on the annotation, within `tolerancePx` (pass a few view points
    /// converted to pixels). Stroked shapes hit only on their outline, so a rectangle drawn
    /// around something does not swallow clicks on what is inside it; filled kinds (text,
    /// highlight, blur, pixelate, counter) hit anywhere in `boundsPx`.
    /// Test the document's annotations back to front (`reversed()`) to pick the topmost.
    func hitTest(_ pointPx: CGPoint, tolerancePx: CGFloat = 4) -> Bool {
        let reach = tolerancePx + style.lineWidthPx / 2
        switch kind {
        case .arrow(let a, let b), .line(let a, let b):
            return Self.distance(pointPx, toSegment: a, b) <= reach
        case .freehand(let points):
            guard let first = points.first else { return false }
            if points.count == 1 { return Self.distance(pointPx, toSegment: first, first) <= reach }
            return zip(points, points.dropFirst()).contains { Self.distance(pointPx, toSegment: $0, $1) <= reach }
        case .rectangle(let rect):
            let r = rect.standardized
            return r.insetBy(dx: -reach, dy: -reach).contains(pointPx) && !r.insetBy(dx: reach, dy: reach).contains(pointPx)
        case .ellipse(let rect):
            let r = rect.standardized
            return Self.ellipse(r.insetBy(dx: -reach, dy: -reach), contains: pointPx)
                && !Self.ellipse(r.insetBy(dx: reach, dy: reach), contains: pointPx)
        case .text, .highlight, .blur, .pixelate, .counter:
            return boundsPx.insetBy(dx: -tolerancePx, dy: -tolerancePx).contains(pointPx)
        }
    }

    /// Copy translated by `deltaPx`; id and style are kept.
    func moved(by deltaPx: CGVector) -> Annotation {
        func shift(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x + deltaPx.dx, y: p.y + deltaPx.dy) }
        func shift(_ r: CGRect) -> CGRect { r.offsetBy(dx: deltaPx.dx, dy: deltaPx.dy) }
        var copy = self
        switch kind {
        case .arrow(let a, let b): copy.kind = .arrow(fromPx: shift(a), toPx: shift(b))
        case .line(let a, let b): copy.kind = .line(fromPx: shift(a), toPx: shift(b))
        case .freehand(let points): copy.kind = .freehand(pointsPx: points.map { shift($0) })
        case .rectangle(let rect): copy.kind = .rectangle(shift(rect))
        case .ellipse(let rect): copy.kind = .ellipse(shift(rect))
        case .highlight(let rect): copy.kind = .highlight(shift(rect))
        case .blur(let rect): copy.kind = .blur(shift(rect))
        case .pixelate(let rect): copy.kind = .pixelate(shift(rect))
        case .text(let string, let origin): copy.kind = .text(string, originPx: shift(origin))
        case .counter(let center, let number): copy.kind = .counter(centerPx: shift(center), number: number)
        }
        return copy
    }

    private static func bounding(_ points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .zero }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for p in points.dropFirst() {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private static func distance(_ p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        let t = lengthSquared == 0 ? 0 : max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }

    private static func ellipse(_ rect: CGRect, contains p: CGPoint) -> Bool {
        guard !rect.isNull, rect.width > 0, rect.height > 0 else { return false }
        let nx = (p.x - rect.midX) / (rect.width / 2), ny = (p.y - rect.midY) / (rect.height / 2)
        return nx * nx + ny * ny <= 1
    }
}
