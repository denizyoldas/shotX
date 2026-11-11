import AppKit
import QuickLookThumbnailing
import SwiftUI

/// Floating corner previews of recent captures: one small panel per card, stacked upward from the
/// bottom-left corner of the screen the capture came from.
final class QuickAccessController {
    enum Item {
        /// URL is nil when save-after-capture is off.
        case image(CapturedImage, URL?)
        case recording(URL)
    }

    static let maxCards = 5
    static let margin: CGFloat = 16
    static let spacing: CGFloat = 10

    /// Set by AppCoordinator; called when the user picks Annotate / Pin on an image item.
    var onAnnotate: ((CapturedImage) -> Void)?
    var onPin: ((CapturedImage) -> Void)?

    // ponytail: the NSScreen is resolved once at show time; re-resolve by display ID on
    // didChangeScreenParameters if cards must follow display reconfiguration.
    private var entries: [(card: QuickAccessCard, panel: NSPanel, screen: NSScreen)] = []
    private var sharingPicker: NSSharingServicePicker?
    private var sharingDelegate: QuickAccessSharingDelegate?

    /// `closingAfter`: how long an untouched card stays; nil keeps it until the user closes it.
    func show(_ item: Item, closingAfter idleDelay: Duration? = .seconds(10)) {
        guard let screen = Self.screen(for: item) else {
            log.error("QuickAccess: no screen to show the card on")
            return
        }
        let card = QuickAccessCard(item: item, thumbnail: Self.placeholderThumbnail(for: item), idleDelay: idleDelay)
        let panel = makePanel(for: card)
        entries.append((card, panel, screen))
        if entries.count > Self.maxCards { dismiss(entries[0].card) }
        let capacity = Self.cardCapacity(visibleFrameAppKit: screen.visibleFrame)
        while entries.filter({ $0.screen === screen }).count > capacity {
            guard let oldest = entries.first(where: { $0.screen === screen }) else { break }
            dismiss(oldest.card)
        }
        layout()

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.animator().alphaValue = 1

        if case .recording(let url) = item {
            Task {
                if let frame = await Self.movieThumbnail(url) { card.thumbnail = NSImage(cgImage: frame, size: .zero) }
            }
        }
    }

    /// Frame of the `index`-th card (0 = oldest, at the bottom) on a screen.
    static func cardFrameAppKit(index: Int, visibleFrameAppKit: CGRect) -> CGRect {
        let size = QuickAccessView.cardSize
        return CGRect(
            x: visibleFrameAppKit.minX + margin,
            y: visibleFrameAppKit.minY + margin + CGFloat(index) * (size.height + spacing),
            width: size.width, height: size.height
        )
    }

    /// Larger cards still fit above the Dock on shorter displays.
    static func cardCapacity(visibleFrameAppKit: CGRect) -> Int {
        let availableHeight = max(0, visibleFrameAppKit.height - 2 * margin)
        return max(1, min(maxCards, Int((availableHeight + spacing) / (QuickAccessView.cardSize.height + spacing))))
    }

    // MARK: Panels

    private func makePanel(for card: QuickAccessCard) -> NSPanel {
        let panel = NSPanel(
            contentRect: CGRect(origin: .zero, size: QuickAccessView.cardSize),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.contentView = FirstMouseHostingView(rootView: QuickAccessView(
            card: card,
            dragFileURL: { [weak self] in self?.dragURL(for: card) },
            onAction: { [weak self] in self?.perform($0, on: card) }
        ))
        return panel
    }

    private func layout() {
        var countByScreen: [ObjectIdentifier: Int] = [:]
        for entry in entries {
            let index = countByScreen[ObjectIdentifier(entry.screen), default: 0]
            countByScreen[ObjectIdentifier(entry.screen)] = index + 1
            let frameAppKit = Self.cardFrameAppKit(index: index, visibleFrameAppKit: entry.screen.visibleFrame)
            entry.panel.setFrame(frameAppKit, display: true)
        }
    }

    private func dismiss(_ card: QuickAccessCard) {
        guard let index = entries.firstIndex(where: { $0.card === card }) else { return }
        let entry = entries.remove(at: index)
        entry.panel.orderOut(nil)
        entry.panel.contentView = nil // Release the SwiftUI view and cancel its dismissal task.
        layout()
    }

    private static func screen(for item: Item) -> NSScreen? {
        let screens = NSScreen.screens
        if case .image(let capture, _) = item {
            let screenNumber = NSDeviceDescriptionKey("NSScreenNumber")
            if let id = capture.displayID,
               let match = screens.first(where: { $0.deviceDescription[screenNumber] as? CGDirectDisplayID == id }) {
                return match
            }
            if let frameCG = capture.frameCG, let primary = screens.first {
                let frameAppKit = Geometry.rectAppKit(fromCG: frameCG, primaryHeight: primary.frame.height)
                let centerAppKit = CGPoint(x: frameAppKit.midX, y: frameAppKit.midY)
                if let match = screens.first(where: { $0.frame.contains(centerAppKit) }) { return match }
            }
        }
        let mouseAppKit = NSEvent.mouseLocation
        return screens.first { $0.frame.contains(mouseAppKit) } ?? NSScreen.main
    }

    // MARK: Thumbnails

    private static func placeholderThumbnail(for item: Item) -> NSImage {
        switch item {
        case .image(let capture, _):
            NSImage(cgImage: capture.image, size: .zero)
        case .recording(let url):
            NSWorkspace.shared.icon(forFile: url.path)
        }
    }

    /// Quick Look handles both MP4 and GIF. Nil (logged) leaves the file icon in place.
    @concurrent nonisolated private static func movieThumbnail(_ url: URL) async -> CGImage? {
        let request = QLThumbnailGenerator.Request(
            fileAt: url, size: CGSize(width: 400, height: 260), scale: 1, representationTypes: .thumbnail
        )
        do {
            return try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).cgImage
        } catch {
            log.error("QuickAccess: thumbnail failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: Actions (UI-event entry points: errors are logged and alerted here)

    private func perform(_ action: QuickAccessAction, on card: QuickAccessCard) {
        card.idleID = UUID()
        do {
            switch (action, card.item) {
            case (.close, _):
                dismiss(card)
            case (.copy, .image(let capture, _)):
                Clipboard.copy(image: capture.image, scale: capture.scale)
                guard NSPasteboard.general.availableType(from: [.png, .tiff]) != nil else {
                    throw CopyError.failed
                }
                card.copyFeedbackID = UUID()
            case (.copy, .recording(let url)):
                NSPasteboard.general.clearContents()
                guard NSPasteboard.general.writeObjects([url as NSURL]) else { throw CopyError.failed }
                card.copyFeedbackID = UUID()
            case (.save, .image(let capture, nil)):
                card.isPresentingAction = true
                defer {
                    card.isPresentingAction = false
                    card.idleID = UUID()
                }
                try save(capture, card: card)
            case (.save, .image(_, let url?)), (.save, .recording(let url)):
                NSWorkspace.shared.activateFileViewerSelecting([url])
                dismiss(card)
            case (.share, _):
                share(card)
            case (.annotate, .image(let capture, _)):
                onAnnotate?(capture)
                dismiss(card)
            case (.pin, .image(let capture, _)):
                onPin?(capture)
                dismiss(card)
            case (.annotate, .recording), (.pin, .recording):
                break // the view offers neither for recordings
            }
        } catch {
            card.isPresentingAction = true
            report(error)
            card.isPresentingAction = false
            card.idleID = UUID()
        }
    }

    private func share(_ card: QuickAccessCard) {
        guard let view = entries.first(where: { $0.card === card })?.panel.contentView else { return }
        sharingDelegate?.onFinish()
        let items: [Any]
        if let url = card.fileURL {
            items = [url]
        } else {
            items = [card.thumbnail]
        }
        let picker = NSSharingServicePicker(items: items)
        card.isPresentingAction = true
        let delegate = QuickAccessSharingDelegate { [weak card] in
            card?.isPresentingAction = false
            card?.idleID = UUID()
        }
        picker.delegate = delegate
        sharingDelegate = delegate
        sharingPicker = picker
        let anchorInView = CGRect(
            x: view.bounds.maxX - 40,
            y: view.isFlipped ? view.bounds.maxY - 40 : view.bounds.minY + 12,
            width: 28, height: 28
        )
        picker.show(relativeTo: anchorInView, of: view, preferredEdge: .maxX)
    }

    private func save(_ capture: CapturedImage, card: QuickAccessCard) throws {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.png]
        savePanel.nameFieldStringValue = Self.temporaryPNGURL().lastPathComponent
        NSApp.activate()
        guard savePanel.runModal() == .OK, let url = savePanel.url else { return }
        try ImageEncoder.data(capture.image, scale: capture.scale, format: .png).write(to: url, options: .atomic)
        card.item = .image(capture, url)
        dismiss(card)
    }

    /// File to hand to a drag: the saved file, or a temporary PNG written on first use.
    private func dragURL(for card: QuickAccessCard) -> URL? {
        if let url = card.fileURL ?? card.dragTempURL { return url }
        guard case .image(let capture, _) = card.item else { return nil }
        do {
            // ponytail: encodes on the main thread at drag start (a brief hitch on 5K captures) and leaves
            // the file for the OS to purge; pre-encode off-main when the card appears if that is felt.
            let url = Self.temporaryPNGURL()
            try ImageEncoder.data(capture.image, scale: capture.scale, format: .png).write(to: url, options: .atomic)
            card.dragTempURL = url
            return url
        } catch {
            report(error)
            return nil
        }
    }

    private static func temporaryPNGURL() -> URL {
        FileNaming.url(in: FileManager.default.temporaryDirectory, date: Date(), ext: ImageFormat.png.fileExtension)
    }

    private func report(_ error: Error) {
        log.error("QuickAccess: \(error.localizedDescription, privacy: .public)")
        NSApp.activate()
        NSAlert(error: error).runModal()
    }

    private enum CopyError: LocalizedError {
        case failed

        var errorDescription: String? { "The capture could not be copied to the clipboard." }
    }
}

/// Keep the card alive while the native sharing chooser is in use, including cancellation.
private final class QuickAccessSharingDelegate: NSObject, NSSharingServicePickerDelegate {
    let onFinish: () -> Void

    init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }

    func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, didChoose service: NSSharingService?) {
        onFinish()
    }
}

/// Lets the first click on a card in the (never key) panel reach the SwiftUI buttons.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
