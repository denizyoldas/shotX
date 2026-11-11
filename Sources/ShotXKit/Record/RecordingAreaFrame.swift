import AppKit

/// While an area is being recorded: dims the rest of that display and outlines the area, like the
/// system recorder. Click-through, and never in the video (the stream excludes shotX's own windows).
final class RecordingAreaFrame {
    private var panel: NSPanel?

    func show(areaCG: CGRect, displayFrameCG: CGRect) {
        hide()
        guard let primaryHeight = NSScreen.screens.first?.frame.height else { return }
        let frameAppKit = Geometry.rectAppKit(fromCG: displayFrameCG, primaryHeight: primaryHeight)
        let panel = NSPanel(contentRect: frameAppKit, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating // below the menu bar, so its Stop item stays undimmed
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = true // the user keeps working while recording
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.contentView = AreaFrameView(areaInView: Geometry.rectInDisplay(fromCG: areaCG, displayFrameCG: displayFrameCG))
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func hide() {
        panel?.close()
        panel = nil
    }
}

/// Flipped and display-sized, so `InView` == display-local CG.
private final class AreaFrameView: NSView {
    private let areaInView: CGRect

    init(areaInView: CGRect) {
        self.areaInView = areaInView
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.setFillColor(CGColor(gray: 0, alpha: 0.4))
        context.addRect(bounds)
        context.addRect(areaInView)
        context.fillPath(using: .evenOdd)
        context.setStrokeColor(.white)
        context.setLineWidth(1)
        context.stroke(areaInView.insetBy(dx: -0.5, dy: -0.5)) // just outside the recorded pixels
    }
}
