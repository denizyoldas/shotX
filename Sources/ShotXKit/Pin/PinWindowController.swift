import AppKit

/// Floats captures above all windows. One controller owns any number of pin panels.
final class PinWindowController {
    private var panels: [NSPanel] = []

    func pin(_ capture: CapturedImage) {
        let sizePt = CGSize(width: CGFloat(capture.image.width) / capture.scale, height: CGFloat(capture.image.height) / capture.scale)
        guard sizePt.width > 0, sizePt.height > 0 else { return }

        // Anchor = centre of where it was captured, else the mouse.
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let capturedAppKit = capture.frameCG.map { Geometry.rectAppKit(fromCG: $0, primaryHeight: primaryHeight) }
        let anchorAppKit = capturedAppKit.map { CGPoint(x: $0.midX, y: $0.midY) } ?? NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(anchorAppKit) } ?? NSScreen.main
        let boundsAppKit = screen?.visibleFrame ?? CGRect(origin: .zero, size: sizePt)
        let frameAppKit = Self.frameAppKit(sizePt: sizePt, anchorAppKit: anchorAppKit, boundsAppKit: boundsAppKit)

        let panel = NSPanel(contentRect: frameAppKit, styleMask: [.borderless, .nonactivatingPanel, .resizable], backing: .buffered, defer: false)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // Window captures are transparent around the window (shadow included); no backdrop behind them.
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentAspectRatio = sizePt
        let minScale = min(1, PinView.minSidePt / min(sizePt.width, sizePt.height))
        panel.contentMinSize = CGSize(width: sizePt.width * minScale, height: sizePt.height * minScale)

        let view = PinView(capture: capture)
        view.onClose = { [weak self, weak panel] in self?.panels.removeAll { $0 === panel } }
        panel.contentView = view
        panels.append(panel)
        panel.orderFrontRegardless()
    }

    /// `sizePt` centred on the anchor, shrunk (aspect kept) to fit `boundsAppKit`, then shifted fully inside it.
    nonisolated static func frameAppKit(sizePt: CGSize, anchorAppKit: CGPoint, boundsAppKit: CGRect) -> CGRect {
        let fit = min(1, boundsAppKit.width / sizePt.width, boundsAppKit.height / sizePt.height)
        let size = CGSize(width: sizePt.width * fit, height: sizePt.height * fit)
        let x = min(max(anchorAppKit.x - size.width / 2, boundsAppKit.minX), boundsAppKit.maxX - size.width)
        let y = min(max(anchorAppKit.y - size.height / 2, boundsAppKit.minY), boundsAppKit.maxY - size.height)
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }
}

/// Content view of one pin panel: shows the image and handles drag, scroll-opacity, menu and close.
private final class PinView: NSView {
    static let minSidePt: CGFloat = 48
    static let opacityRange: ClosedRange<CGFloat> = 0.2...1

    var onClose: (() -> Void)?
    private let capture: CapturedImage

    init(capture: CapturedImage) {
        self.capture = capture
        super.init(frame: .zero)
        wantsLayer = true

        let menu = NSMenu()
        menu.addItem(item("Copy", #selector(copyImage)))
        menu.addItem(item("Save…", #selector(saveImage)))
        menu.addItem(.separator())
        for percent in [100, 75, 50, 25] {
            let preset = item("Opacity \(percent)%", #selector(setOpacity(_:)))
            preset.tag = percent
            menu.addItem(preset)
        }
        menu.addItem(.separator())
        menu.addItem(item("Close", #selector(closePin)))
        self.menu = menu
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() { layer?.contents = capture.image }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { closePin() } else { window?.performDrag(with: event) }
    }

    override func scrollWheel(with event: NSEvent) {
        guard let window else { return }
        let step: CGFloat = event.hasPreciseScrollingDeltas ? 0.005 : 0.05
        let alpha = window.alphaValue + event.scrollingDeltaY * step
        window.alphaValue = min(max(alpha, Self.opacityRange.lowerBound), Self.opacityRange.upperBound)
    }

    @objc private func copyImage() {
        Clipboard.copy(image: capture.image, scale: capture.scale)
    }

    @objc private func saveImage() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.png]
        savePanel.nameFieldStringValue = FileNaming.url(in: FileManager.default.temporaryDirectory, date: Date(), ext: "png").lastPathComponent
        NSApp.activate()
        guard savePanel.runModal() == .OK, let url = savePanel.url else { return }
        do {
            try ImageEncoder.data(capture.image, scale: capture.scale, format: .png).write(to: url)
        } catch {
            log.error("Pin save failed: \(error.localizedDescription, privacy: .public)")
            NSAlert(error: error).runModal()
        }
    }

    @objc private func setOpacity(_ sender: NSMenuItem) {
        window?.alphaValue = CGFloat(sender.tag) / 100
    }

    @objc private func closePin() {
        window?.close()
        onClose?()
    }
}
