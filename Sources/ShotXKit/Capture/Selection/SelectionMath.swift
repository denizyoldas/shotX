import CoreGraphics

/// Pure drag / label / loupe math for the selection overlay (unit-tested; no AppKit).
nonisolated enum SelectionMath {
    /// A drag shorter than this (points) is a stray click and cancels.
    static let minimumDrag: CGFloat = 3
    /// Snapshot pixels shown across the loupe. Odd, so there is a centre pixel.
    static let loupeSidePx: CGFloat = 15

    static func clamp(_ pointInView: CGPoint, to boundsInView: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(pointInView.x, boundsInView.minX), boundsInView.maxX),
            y: min(max(pointInView.y, boundsInView.minY), boundsInView.maxY)
        )
    }

    /// Rect spanned by a drag in any direction, with both ends clamped to the view.
    static func dragRectInView(from startInView: CGPoint, to currentInView: CGPoint, boundsInView: CGRect) -> CGRect {
        let aInView = clamp(startInView, to: boundsInView)
        let bInView = clamp(currentInView, to: boundsInView)
        return CGRect(
            x: min(aInView.x, bInView.x), y: min(aInView.y, bInView.y),
            width: abs(aInView.x - bInView.x), height: abs(aInView.y - bInView.y)
        )
    }

    static func isDrag(from startInView: CGPoint, to endInView: CGPoint) -> Bool {
        hypot(endInView.x - startInView.x, endInView.y - startInView.y) >= minimumDrag
    }

    /// Final pixel rect of a finished drag; nil when it is under the threshold or covers no pixel.
    static func areaRectPx(
        from startInView: CGPoint, to endInView: CGPoint, boundsInView: CGRect, scale: CGFloat, imageSizePx: CGSize
    ) -> CGRect? {
        guard isDrag(from: startInView, to: endInView) else { return nil }
        let rectInView = dragRectInView(from: startInView, to: endInView, boundsInView: boundsInView)
        let rectPx = Geometry.rectPx(fromInView: rectInView, scale: scale, imageSizePx: imageSizePx)
        return rectPx.isEmpty ? nil : rectPx
    }

    /// `rectInView` shifted by `deltaInView`, kept whole inside the view (size unchanged).
    static func moved(_ rectInView: CGRect, by deltaInView: CGSize, boundsInView: CGRect) -> CGRect {
        CGRect(
            x: min(max(rectInView.minX + deltaInView.width, boundsInView.minX), boundsInView.maxX - rectInView.width),
            y: min(max(rectInView.minY + deltaInView.height, boundsInView.minY), boundsInView.maxY - rectInView.height),
            width: rectInView.width, height: rectInView.height
        )
    }

    /// When the point is within `tolerance` of a corner, the opposite corner (the one that stays put
    /// while that corner is dragged). Nil away from the corners.
    static func fixedCorner(of rectInView: CGRect, grabbedAt pointInView: CGPoint, tolerance: CGFloat) -> CGPoint? {
        let xs = [rectInView.minX, rectInView.maxX], ys = [rectInView.minY, rectInView.maxY]
        for (xIndex, x) in xs.enumerated() {
            for (yIndex, y) in ys.enumerated() where abs(pointInView.x - x) <= tolerance && abs(pointInView.y - y) <= tolerance {
                return CGPoint(x: xs[1 - xIndex], y: ys[1 - yIndex])
            }
        }
        return nil
    }

    /// "W × H" in pixels of the result.
    static func sizeLabel(rectPx: CGRect) -> String {
        "\(Int(rectPx.width)) × \(Int(rectPx.height))"
    }

    /// `loupeSidePx` square centred on the pixel under the cursor. May extend past the image edge.
    static func loupeSourceRectPx(cursorInView: CGPoint, scale: CGFloat, imageSizePx: CGSize) -> CGRect {
        let centerXPx = min(max((cursorInView.x * scale).rounded(.down), 0), imageSizePx.width - 1)
        let centerYPx = min(max((cursorInView.y * scale).rounded(.down), 0), imageSizePx.height - 1)
        let halfPx = (loupeSidePx - 1) / 2
        return CGRect(x: centerXPx - halfPx, y: centerYPx - halfPx, width: loupeSidePx, height: loupeSidePx)
    }

    /// Loupe goes below-right of the cursor and flips to the other side at the view's edges.
    static func loupeOriginInView(cursorInView: CGPoint, side: CGFloat, offset: CGFloat, boundsInView: CGRect) -> CGPoint {
        var originInView = CGPoint(x: cursorInView.x + offset, y: cursorInView.y + offset)
        if originInView.x + side > boundsInView.maxX { originInView.x = cursorInView.x - offset - side }
        if originInView.y + side > boundsInView.maxY { originInView.y = cursorInView.y - offset - side }
        return originInView
    }
}
