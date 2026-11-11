import AppKit
import SwiftUI

/// AppKit drag source (and hover tracker) that fills a Quick Access card.
/// AppKit rather than SwiftUI `.onDrag`/`.onHover`: both must work in a non-activating panel of an inactive app.
struct DragSourceView: NSViewRepresentable {
    let image: NSImage
    /// Called at drag start; nil cancels the drag (the caller has already reported why).
    let fileURL: () -> URL?
    let onHover: (Bool) -> Void
    /// Called after another app accepted the drop.
    let onDropped: () -> Void
    var onDragging: (Bool) -> Void = { _ in }

    func makeNSView(context: Context) -> SourceView {
        let view = SourceView()
        view.config = self
        return view
    }

    func updateNSView(_ view: SourceView, context: Context) {
        view.config = self
    }

    /// Largest rect with the aspect ratio of `size`, centred in `bounds`.
    nonisolated static func aspectFitRect(size: CGSize, in bounds: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0 else { return bounds }
        let scale = min(bounds.width / size.width, bounds.height / size.height)
        let fitted = CGSize(width: size.width * scale, height: size.height * scale)
        return CGRect(
            x: bounds.midX - fitted.width / 2, y: bounds.midY - fitted.height / 2,
            width: fitted.width, height: fitted.height
        )
    }

    final class SourceView: NSView, NSDraggingSource {
        static let dragThreshold: CGFloat = 3

        var config: DragSourceView?
        /// Set on mouse-down, cleared once a drag starts (or fails to), so one press starts at most one drag.
        private var mouseDownInView: CGPoint?

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil, trackingAreas.isEmpty else { return }
            addTrackingArea(NSTrackingArea(
                rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self
            ))
        }

        override func mouseEntered(with event: NSEvent) { config?.onHover(true) }
        override func mouseExited(with event: NSEvent) { config?.onHover(false) }

        override func mouseDown(with event: NSEvent) {
            mouseDownInView = convert(event.locationInWindow, from: nil)
        }

        override func mouseUp(with event: NSEvent) {
            mouseDownInView = nil
        }

        override func mouseDragged(with event: NSEvent) {
            guard let config, let start = mouseDownInView else { return }
            let pointInView = convert(event.locationInWindow, from: nil)
            guard hypot(pointInView.x - start.x, pointInView.y - start.y) > Self.dragThreshold else { return }
            mouseDownInView = nil
            guard let url = config.fileURL() else { return }

            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            item.setDraggingFrame(DragSourceView.aspectFitRect(size: config.image.size, in: bounds), contents: config.image)
            config.onDragging(true)
            beginDraggingSession(with: [item], event: event, source: self)
        }

        func draggingSession(
            _ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext
        ) -> NSDragOperation {
            context == .outsideApplication ? .copy : []
        }

        func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
            config?.onDragging(false)
            if !operation.isEmpty { config?.onDropped() }
        }
    }
}
