import AppKit

/// Selection UI of one display: dim layer, selection / window highlight, crosshair, size label, loupe.
/// Flipped and display-sized, so `InView` == display-local CG. The live screen shows through the
/// see-through panel; the snapshot only feeds the loupe and the point → pixel mapping.
final class SelectionView: NSView {
    private static let loupeSide: CGFloat = 120
    private static let loupeOffset: CGFloat = 20

    private let mode: SelectionOverlayController.Mode
    private let snapshot: DisplaySnapshot
    private let windows: [WindowInfo]
    private let onFinish: (Selection?) -> Void
    private var cursorInView: CGPoint?
    private var dragStartInView: CGPoint?

    // `.adjustableArea`: the drawn area stays on screen to move / resize until Record or Enter.
    // ponytail: corner handles only, no edge handles or resize cursors; add them if corners feel limiting.
    private static let cornerTolerance: CGFloat = 10
    private static let recordButtonSize = CGSize(width: 96, height: 30)
    private(set) var adjustedRectInView: CGRect?
    private var grip: Grip?
    private var pointerShown = false
    /// Called once, when the area becomes adjustable: the system pointer is needed from then on.
    var onAdjustable: (() -> Void)?

    private enum Grip {
        case move(startRectInView: CGRect, startPointInView: CGPoint)
        case corner(fixedInView: CGPoint)
    }

    init(mode: SelectionOverlayController.Mode, snapshot: DisplaySnapshot, windows: [WindowInfo], onFinish: @escaping (Selection?) -> Void) {
        self.mode = mode
        self.snapshot = snapshot
        self.windows = windows
        self.onFinish = onFinish
        super.init(frame: CGRect(origin: .zero, size: snapshot.frameCG.size))
        autoresizingMask = [.width, .height]
        addTrackingArea(NSTrackingArea(
            rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self
        ))
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var imageSizePx: CGSize { CGSize(width: snapshot.image.width, height: snapshot.image.height) }

    /// Called once after the panel is on screen, for the display the mouse is already on.
    func adoptCurrentMouseLocation() {
        guard let window else { return }
        cursorInView = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        needsDisplay = true
    }

    // MARK: Mouse

    private func track(_ event: NSEvent) {
        cursorInView = SelectionMath.clamp(convert(event.locationInWindow, from: nil), to: bounds)
        needsDisplay = true
    }

    override func mouseEntered(with event: NSEvent) {
        window?.makeKey() // key follows the mouse so Esc reaches the app on every display
        track(event)
    }

    override func mouseExited(with event: NSEvent) {
        guard dragStartInView == nil, grip == nil else { return }
        cursorInView = nil
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) { track(event) }
    override func rightMouseDown(with event: NSEvent) { onFinish(nil) }

    override func mouseDragged(with event: NSEvent) {
        track(event)
        guard let grip, let cursorInView else { return }
        switch grip {
        case .move(let startRectInView, let startPointInView):
            let deltaInView = CGSize(width: cursorInView.x - startPointInView.x, height: cursorInView.y - startPointInView.y)
            adjustedRectInView = SelectionMath.moved(startRectInView, by: deltaInView, boundsInView: bounds)
        case .corner(let fixedInView):
            adjustedRectInView = SelectionMath.dragRectInView(from: fixedInView, to: cursorInView, boundsInView: bounds)
        }
    }

    override func mouseDown(with event: NSEvent) {
        track(event)
        guard let cursorInView else { return }
        guard let rectInView = adjustedRectInView else {
            if mode != .window { dragStartInView = cursorInView }
            return
        }
        if recordButtonRectInView(for: rectInView).contains(cursorInView) { return confirmAdjustedArea() }
        if let fixedInView = SelectionMath.fixedCorner(of: rectInView, grabbedAt: cursorInView, tolerance: Self.cornerTolerance) {
            grip = .corner(fixedInView: fixedInView)
        } else if rectInView.contains(cursorInView) {
            grip = .move(startRectInView: rectInView, startPointInView: cursorInView)
        } else {
            adjustedRectInView = nil // outside the area: draw a new one
            dragStartInView = cursorInView
        }
    }

    override func mouseUp(with event: NSEvent) {
        track(event)
        if grip != nil {
            grip = nil
            return
        }
        switch mode {
        case .window:
            onFinish(hoveredWindow.map { .window($0.id) })
        case .area, .adjustableArea:
            guard let dragStartInView, let cursorInView,
                  let rectPx = SelectionMath.areaRectPx(
                      from: dragStartInView, to: cursorInView, boundsInView: bounds,
                      scale: snapshot.scale, imageSizePx: imageSizePx
                  )
            else { return onFinish(nil) }
            guard mode == .adjustableArea else { return onFinish(.area(rectPx: rectPx, snapshot: snapshot)) }
            adjustedRectInView = SelectionMath.dragRectInView(from: dragStartInView, to: cursorInView, boundsInView: bounds)
            self.dragStartInView = nil
            if !pointerShown {
                pointerShown = true
                onAdjustable?()
            }
        }
    }

    /// Record button or Enter: hands over the adjusted area. No-op while none is drawn or it is too small.
    func confirmAdjustedArea() {
        guard let rectInView = adjustedRectInView,
              let rectPx = SelectionMath.areaRectPx(
                  from: rectInView.origin, to: CGPoint(x: rectInView.maxX, y: rectInView.maxY), boundsInView: bounds,
                  scale: snapshot.scale, imageSizePx: imageSizePx
              )
        else { return }
        onFinish(.area(rectPx: rectPx, snapshot: snapshot))
    }

    /// Below the area's right end; inside its bottom when there is no room below.
    private func recordButtonRectInView(for areaInView: CGRect) -> CGRect {
        let size = Self.recordButtonSize
        var originInView = CGPoint(x: areaInView.maxX - size.width, y: areaInView.maxY + 8)
        if originInView.y + size.height > bounds.maxY { originInView.y = areaInView.maxY - size.height - 8 }
        originInView.x = max(bounds.minX, min(originInView.x, bounds.maxX - size.width))
        return CGRect(origin: originInView, size: size)
    }

    // MARK: State -> geometry

    private var hoveredWindow: WindowInfo? {
        guard mode == .window, let cursorInView else { return nil }
        let pointCG = Geometry.rectCG(fromInDisplay: CGRect(origin: cursorInView, size: .zero), displayFrameCG: snapshot.frameCG).origin
        return WindowList.hitTest(pointCG, in: windows)
    }

    /// The undimmed rect: the drag so far, or the hovered window clipped to this display.
    private var clearRectInView: CGRect? {
        if let adjustedRectInView { return adjustedRectInView }
        if let dragStartInView, let cursorInView {
            return SelectionMath.dragRectInView(from: dragStartInView, to: cursorInView, boundsInView: bounds)
        }
        guard let hoveredWindow else { return nil }
        let rectInView = Geometry.rectInDisplay(fromCG: hoveredWindow.frameCG, displayFrameCG: snapshot.frameCG).intersection(bounds)
        return rectInView.isNull ? nil : rectInView
    }

    // MARK: Drawing

    // ponytail: the whole view is redrawn per mouse event (cheap fills, no image blit); switch to
    // setNeedsDisplay(_:) with dirty rects if a 5K/6K display shows crosshair lag.
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let clearInView = clearRectInView
        context.setFillColor(CGColor(gray: 0, alpha: 0.4))
        context.addRect(bounds)
        if let clearInView { context.addRect(clearInView) }
        context.fillPath(using: .evenOdd)
        if let clearInView {
            // Near-invisible, so the undimmed hole still hit-tests to the overlay, not the app below.
            context.setFillColor(CGColor(gray: 0, alpha: 0.004))
            context.fill(clearInView)
            context.setStrokeColor(mode == .window ? NSColor.controlAccentColor.cgColor : .white)
            context.setLineWidth(mode == .window ? 3 : 1)
            context.stroke(clearInView)
        }
        guard mode != .window else { return }
        if let adjustedRectInView {
            drawSizeLabel(for: adjustedRectInView)
            drawHandles(around: adjustedRectInView, in: context)
            drawRecordButton(for: adjustedRectInView)
            return
        }
        guard let cursorInView else { return }
        if !pointerShown { drawCrosshair(at: cursorInView, in: context) }
        if let clearInView, dragStartInView != nil { drawSizeLabel(for: clearInView) }
        if !pointerShown { drawLoupe(at: cursorInView, in: context) }
    }

    private func drawHandles(around areaInView: CGRect, in context: CGContext) {
        let side: CGFloat = 8
        for x in [areaInView.minX, areaInView.maxX] {
            for y in [areaInView.minY, areaInView.maxY] {
                let handleInView = CGRect(x: x - side / 2, y: y - side / 2, width: side, height: side)
                context.setFillColor(.white)
                context.fill(handleInView)
                context.setStrokeColor(CGColor(gray: 0, alpha: 0.5))
                context.setLineWidth(1)
                context.stroke(handleInView)
            }
        }
    }

    private func drawRecordButton(for areaInView: CGRect) {
        let buttonInView = recordButtonRectInView(for: areaInView)
        NSColor.systemRed.setFill()
        NSBezierPath(roundedRect: buttonInView, xRadius: buttonInView.height / 2, yRadius: buttonInView.height / 2).fill()
        let text = NSAttributedString(string: "● Record", attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.white,
        ])
        let textSize = text.size()
        text.draw(at: CGPoint(x: buttonInView.midX - textSize.width / 2, y: buttonInView.midY - textSize.height / 2))
    }

    /// A small cross at the pointer in place of the hidden system cursor; no screen-wide guide lines.
    private func drawCrosshair(at cursorInView: CGPoint, in context: CGContext) {
        let arm: CGFloat = 9
        // Dark halo under a white hairline, so it reads on any background.
        for (color, width) in [(CGColor(gray: 0, alpha: 0.5), CGFloat(3)), (CGColor.white, CGFloat(1))] {
            context.setStrokeColor(color)
            context.setLineWidth(width)
            context.move(to: CGPoint(x: cursorInView.x - arm, y: cursorInView.y))
            context.addLine(to: CGPoint(x: cursorInView.x + arm, y: cursorInView.y))
            context.move(to: CGPoint(x: cursorInView.x, y: cursorInView.y - arm))
            context.addLine(to: CGPoint(x: cursorInView.x, y: cursorInView.y + arm))
            context.strokePath()
        }
    }

    private func drawSizeLabel(for selectionInView: CGRect) {
        let rectPx = Geometry.rectPx(fromInView: selectionInView, scale: snapshot.scale, imageSizePx: imageSizePx)
        let text = NSAttributedString(string: SelectionMath.sizeLabel(rectPx: rectPx), attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
        ])
        let textSize = text.size()
        let padding: CGFloat = 5
        let boxSize = CGSize(width: textSize.width + 2 * padding, height: textSize.height + 2 * padding)
        // Below the selection's bottom-left; inside it when there is no room below.
        var boxOriginInView = CGPoint(x: selectionInView.minX, y: selectionInView.maxY + 6)
        if boxOriginInView.y + boxSize.height > bounds.maxY { boxOriginInView.y = selectionInView.maxY - boxSize.height - 6 }
        boxOriginInView.x = max(bounds.minX, min(boxOriginInView.x, bounds.maxX - boxSize.width))
        NSColor.black.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: CGRect(origin: boxOriginInView, size: boxSize), xRadius: 4, yRadius: 4).fill()
        text.draw(at: CGPoint(x: boxOriginInView.x + padding, y: boxOriginInView.y + padding))
    }

    private func drawLoupe(at cursorInView: CGPoint, in context: CGContext) {
        let loupeInView = CGRect(
            origin: SelectionMath.loupeOriginInView(
                cursorInView: cursorInView, side: Self.loupeSide, offset: Self.loupeOffset, boundsInView: bounds
            ),
            size: CGSize(width: Self.loupeSide, height: Self.loupeSide)
        )
        let sourcePx = SelectionMath.loupeSourceRectPx(cursorInView: cursorInView, scale: snapshot.scale, imageSizePx: imageSizePx)
        let pointsPerPx = Self.loupeSide / sourcePx.width

        context.saveGState()
        context.setFillColor(.black)
        context.fill(loupeInView)
        let visiblePx = sourcePx.intersection(CGRect(origin: .zero, size: imageSizePx))
        if !visiblePx.isEmpty, let pixels = snapshot.image.cropping(to: visiblePx) {
            let destInView = CGRect(
                x: loupeInView.minX + (visiblePx.minX - sourcePx.minX) * pointsPerPx,
                y: loupeInView.minY + (visiblePx.minY - sourcePx.minY) * pointsPerPx,
                width: visiblePx.width * pointsPerPx, height: visiblePx.height * pointsPerPx
            )
            context.interpolationQuality = .none
            // CGImages draw bottom-up; mirror around the destination rect in this flipped view.
            context.translateBy(x: 0, y: destInView.minY + destInView.maxY)
            context.scaleBy(x: 1, y: -1)
            context.draw(pixels, in: destInView)
        }
        context.restoreGState()

        context.setLineWidth(1)
        context.setStrokeColor(.white)
        context.stroke(loupeInView)
        let centerPixelInView = CGRect(
            x: loupeInView.midX - pointsPerPx / 2, y: loupeInView.midY - pointsPerPx / 2, width: pointsPerPx, height: pointsPerPx
        )
        context.setStrokeColor(.black)
        context.stroke(centerPixelInView.insetBy(dx: -1, dy: -1))
        context.setStrokeColor(.white)
        context.stroke(centerPixelInView)
    }
}
