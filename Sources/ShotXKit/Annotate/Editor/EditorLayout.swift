import CoreGraphics

/// Zoom-to-fit placement of the image inside the canvas, and the view-point <-> image-pixel
/// mapping that follows from it. Pure. The image is never enlarged past its point size.
nonisolated struct CanvasLayout: Equatable, Sendable {
    /// Pixels per point of the capture.
    let scale: CGFloat
    /// View points per image point (<= 1).
    let zoom: CGFloat
    /// Where the image is drawn: centred, letterboxed, origin on whole points.
    let imageRectInView: CGRect

    init(imageSizePx: CGSize, scale: CGFloat, viewSize: CGSize) {
        let width = imageSizePx.width / scale, height = imageSizePx.height / scale
        let fit = width > 0 && height > 0 ? min(viewSize.width / width, viewSize.height / height) : 1
        let zoom = max(0.01, min(1, fit))
        let size = CGSize(width: width * zoom, height: height * zoom)
        self.scale = scale
        self.zoom = zoom
        imageRectInView = CGRect(origin: CGPoint(x: ((viewSize.width - size.width) / 2).rounded(),
                                                 y: ((viewSize.height - size.height) / 2).rounded()), size: size)
    }

    /// Image pixels covered by one view point. Multiply view-point tolerances by this.
    var pxPerViewPoint: CGFloat { scale / zoom }

    func pointPx(fromInView pointInView: CGPoint) -> CGPoint {
        CGPoint(x: (pointInView.x - imageRectInView.minX) * pxPerViewPoint, y: (pointInView.y - imageRectInView.minY) * pxPerViewPoint)
    }

    func rectInView(fromPx rectPx: CGRect) -> CGRect {
        Geometry.rectInView(fromPx: rectPx, scale: pxPerViewPoint).offsetBy(dx: imageRectInView.minX, dy: imageRectInView.minY)
    }
}

nonisolated enum EditorTool: CaseIterable, Sendable {
    case select, arrow, rectangle, ellipse, line, freehand, text, highlight, blur, pixelate, counter, crop

    var title: String {
        switch self {
        case .select: "Select"
        case .arrow: "Arrow"
        case .rectangle: "Rectangle"
        case .ellipse: "Ellipse"
        case .line: "Line"
        case .freehand: "Freehand"
        case .text: "Text"
        case .highlight: "Highlight"
        case .blur: "Blur"
        case .pixelate: "Pixelate"
        case .counter: "Counter"
        case .crop: "Crop"
        }
    }

    /// SF Symbol name.
    var symbol: String {
        switch self {
        case .select: "cursorarrow"
        case .arrow: "arrow.up.right"
        case .rectangle: "rectangle"
        case .ellipse: "oval"
        case .line: "line.diagonal"
        case .freehand: "scribble"
        case .text: "textformat"
        case .highlight: "highlighter"
        case .blur: "drop.halffull"
        case .pixelate: "checkerboard.rectangle"
        case .counter: "1.circle"
        case .crop: "crop"
        }
    }

    /// The annotation a drag from `fromPx` to `toPx` creates; nil for tools that are not a
    /// two-point drag (select, freehand, text, counter, crop). Rects are left un-normalised.
    func kind(fromPx: CGPoint, toPx: CGPoint) -> Annotation.Kind? {
        let rectPx = CGRect(x: fromPx.x, y: fromPx.y, width: toPx.x - fromPx.x, height: toPx.y - fromPx.y)
        return switch self {
        case .arrow: .arrow(fromPx: fromPx, toPx: toPx)
        case .line: .line(fromPx: fromPx, toPx: toPx)
        case .rectangle: .rectangle(rectPx)
        case .ellipse: .ellipse(rectPx)
        case .highlight: .highlight(rectPx)
        case .blur: .blur(rectPx)
        case .pixelate: .pixelate(rectPx)
        case .select, .freehand, .text, .counter, .crop: nil
        }
    }
}
