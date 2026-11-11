import AppKit
import Carbon.HIToolbox
import Observation

/// Shows the document zoomed to fit and turns mouse and key events into document mutations.
/// Shapes are drawn only by `AnnotationRenderer`; this view adds its own chrome (selection
/// outline, crop overlay). Flipped, so `InView` is top-left based.
final class CanvasView: NSView, NSTextFieldDelegate {
    private enum Drag {
        /// Two-point shape of the current tool.
        case shape
        case freehand(pointsPx: [CGPoint])
        /// Moving this annotation (its state at mouse-down).
        case move(Annotation)
        case crop
    }

    /// Drags that never get farther than this from their start create nothing.
    private static let minimumDragInView: CGFloat = 3

    private let session: EditorSession
    private var drag: Drag?
    private var dragStartInView = CGPoint.zero
    private var dragReachInView: CGFloat = 0
    /// Copy of the document with the in-progress shape / move; committed on mouse-up (one undo step).
    private var preview: AnnotationDocument?
    private var cropPreviewPx: CGRect?
    private var textField: NSTextField?
    private var textOriginPx = CGPoint.zero

    init(session: EditorSession) {
        self.session = session
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    private var canvasLayout: CanvasLayout {
        CanvasLayout(imageSizePx: session.document.sizePx, scale: session.document.scale, viewSize: bounds.size)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        // Redraw whenever anything read while drawing (document, selection) changes.
        withObservationTracking {
            drawContent()
        } onChange: { [weak self] in
            Task { @MainActor in self?.needsDisplay = true }
        }
    }

    private func drawContent() {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()

        let layout = canvasLayout
        let document = preview ?? session.document
        let imageRectInView = layout.imageRectInView
        context.saveGState()
        context.clip(to: imageRectInView)
        context.translateBy(x: imageRectInView.minX, y: imageRectInView.minY)
        context.scaleBy(x: layout.zoom / document.scale, y: layout.zoom / document.scale)
        AnnotationRenderer.render(document, into: context)
        context.restoreGState()

        if let cropPx = cropPreviewPx ?? document.cropRectPx {
            let cropInView = layout.rectInView(fromPx: cropPx).intersection(imageRectInView)
            context.saveGState()
            context.addRect(imageRectInView)
            context.addRect(cropInView)
            context.setFillColor(CGColor(gray: 0, alpha: 0.55))
            context.fillPath(using: .evenOdd)
            context.setStrokeColor(CGColor(gray: 1, alpha: 0.9))
            context.setLineWidth(1)
            context.stroke(cropInView.insetBy(dx: 0.5, dy: 0.5))
            context.restoreGState()
        }

        if let id = session.selectedID, let selected = document.annotation(id: id) {
            context.saveGState()
            context.setStrokeColor(NSColor.controlAccentColor.cgColor)
            context.setLineWidth(1.5)
            context.setLineDash(phase: 0, lengths: [4, 3])
            context.stroke(layout.rectInView(fromPx: selected.boundsPx).insetBy(dx: -3, dy: -3))
            context.restoreGState()
        }
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)  // also commits an open text field
        let pointInView = convert(event.locationInWindow, from: nil)
        let layout = canvasLayout
        let pointPx = layout.pointPx(fromInView: pointInView)
        dragStartInView = pointInView
        dragReachInView = 0
        switch session.tool {
        case .select:
            let hit = session.document.annotations.reversed().first { $0.hitTest(pointPx, tolerancePx: 4 * layout.pxPerViewPoint) }
            session.selectedID = hit?.id
            drag = hit.map { .move($0) }
        case .text:
            if layout.imageRectInView.contains(pointInView) { beginText(atInView: pointInView, layout: layout) }
        case .counter:
            guard layout.imageRectInView.contains(pointInView) else { return }
            let number = session.document.nextCounterNumber
            session.document.add(Annotation(kind: .counter(centerPx: pointPx, number: number), style: session.style))
        case .crop:
            drag = .crop
        case .freehand:
            drag = .freehand(pointsPx: [pointPx])
        case .arrow, .rectangle, .ellipse, .line, .highlight, .blur, .pixelate:
            drag = .shape
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let drag else { return }
        let pointInView = convert(event.locationInWindow, from: nil)
        dragReachInView = max(dragReachInView, hypot(pointInView.x - dragStartInView.x, pointInView.y - dragStartInView.y))
        let layout = canvasLayout
        let startPx = layout.pointPx(fromInView: dragStartInView)
        let pointPx = layout.pointPx(fromInView: pointInView)
        var copy = session.document
        switch drag {
        case .shape:
            guard let kind = session.tool.kind(fromPx: startPx, toPx: pointPx) else { return }
            copy.add(Annotation(kind: kind, style: session.style))
        case .freehand(var pointsPx):
            pointsPx.append(pointPx)
            self.drag = .freehand(pointsPx: pointsPx)
            copy.add(Annotation(kind: .freehand(pointsPx: pointsPx), style: session.style))
        case .move(let original):
            copy.update(original.moved(by: CGVector(dx: pointPx.x - startPx.x, dy: pointPx.y - startPx.y)))
        case .crop:
            cropPreviewPx = CGRect(x: startPx.x, y: startPx.y, width: pointPx.x - startPx.x, height: pointPx.y - startPx.y).standardized
        }
        preview = copy
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            drag = nil
            preview = nil
            cropPreviewPx = nil
            needsDisplay = true
        }
        guard drag != nil, dragReachInView >= Self.minimumDragInView else { return }
        if let cropPreviewPx {
            session.document.setCrop(cropPreviewPx)
        } else if let preview {
            session.document = preview
        }
    }

    // MARK: Text entry

    // ponytail: single-line field of fixed width that does not follow a window resize; the
    // committed annotation does. Swap for an NSTextView overlay if multi-line entry is wanted.
    private func beginText(atInView pointInView: CGPoint, layout: CanvasLayout) {
        let field = NSTextField(frame: .zero)
        field.font = .systemFont(ofSize: session.style.fontSizePx / layout.pxPerViewPoint)
        field.textColor = NSColor(cgColor: session.style.color)
        field.placeholderString = "Text"
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.delegate = self
        field.sizeToFit()
        // The cell insets its text by 2 pt; shift so the first glyph sits on the click point,
        // where the renderer will draw it.
        field.frame = CGRect(x: pointInView.x - 2, y: pointInView.y,
                             width: max(60, layout.imageRectInView.maxX - pointInView.x), height: field.frame.height)
        addSubview(field)
        textField = field
        textOriginPx = layout.pointPx(fromInView: pointInView)
        window?.makeFirstResponder(field)
    }

    private func endText(commit: Bool) {
        guard let field = textField else { return }
        textField = nil  // first: removing the field ends editing again
        let string = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        field.removeFromSuperview()
        if commit, !string.isEmpty {
            session.document.add(Annotation(kind: .text(string, originPx: textOriginPx), style: session.style))
        }
        // Take the keyboard back once AppKit has finished its own first-responder change.
        Task { [weak self] in
            guard let self, textField == nil else { return }
            window?.makeFirstResponder(self)
        }
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        endText(commit: true)  // Return, Tab or focus loss
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard commandSelector == #selector(NSResponder.cancelOperation(_:)) else { return false }
        endText(commit: false)
        return true
    }

    // MARK: Keyboard (LSUIElement app: no main menu, so shortcuts are handled here)

    override func keyDown(with event: NSEvent) {
        // Mid-drag, mouseUp would commit a preview taken before this key's edit and undo it silently.
        guard drag == nil else { return }
        switch Int(event.keyCode) {
        case kVK_Delete, kVK_ForwardDelete:
            session.deleteSelection()
        case kVK_Escape:
            if session.tool == .crop { session.document.setCrop(nil) } else { session.selectedID = nil }
        default:
            super.keyDown(with: event)
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if textField != nil {
            // No Edit menu either: route the standard editing shortcuts to the field editor.
            let editing: [String: Selector] = [
                "x": #selector(NSText.cut(_:)), "c": #selector(NSText.copy(_:)),
                "v": #selector(NSText.paste(_:)), "a": #selector(NSText.selectAll(_:)),
            ]
            guard modifiers == .command, let selector = editing[key] else { return super.performKeyEquivalent(with: event) }
            return NSApp.sendAction(selector, to: nil, from: self)
        }
        guard drag == nil else { return super.performKeyEquivalent(with: event) }
        switch (key, modifiers) {
        case ("z", .command): session.document.undo()
        case ("z", [.command, .shift]): session.document.redo()
        case ("c", .command): session.copy()
        case ("s", .command): session.save()
        case ("w", .command): session.close()
        default: return super.performKeyEquivalent(with: event)
        }
        return true
    }
}
