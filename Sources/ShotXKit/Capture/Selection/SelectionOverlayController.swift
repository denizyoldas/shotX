import AppKit

/// Shows one see-through overlay panel per display over the live screen and lets the user pick an
/// area or a window. The snapshots passed in give display geometry and the loupe's pixels.
final class SelectionOverlayController {
    enum Mode: Sendable {
        case area, window
        /// Area that stays on screen to move / resize (corners) until Record or Enter; returns `.area`.
        case adjustableArea
    }

    private static let escapeKeyCode: UInt16 = 53
    private static let confirmKeyCodes: Set<UInt16> = [36, 76] // Return, keypad Enter

    /// Non-nil exactly while a selection is on screen; `finish` is its only resumer.
    private var continuation: CheckedContinuation<Selection?, Never>?
    private var panels: [NSPanel] = []
    private var keyMonitors: [Any] = []
    private var cursorHidden = false

    /// Returns nil when the user cancels (Esc, right click, stray click), when the awaiting task is
    /// cancelled, or when a selection is already in progress. `.area` mode returns `.area`, `.window` mode `.window`.
    func select(mode: Mode, snapshots: [DisplaySnapshot]) async -> Selection? {
        guard continuation == nil, !snapshots.isEmpty, let primaryHeight = NSScreen.screens.first?.frame.height else {
            return nil
        }
        let selection = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                if Task.isCancelled { return finish(nil) }
                show(mode: mode, snapshots: snapshots, primaryHeight: primaryHeight)
            }
        } onCancel: {
            // ponytail: not tied to this particular call; a cancel hop that lands after this selection
            // ended and another began would cancel that one. Add a generation token if that ever happens.
            Task { @MainActor in self.finish(nil) }
        }
        // Recording only needs the rect; captures and OCR need pixels from the moment of release.
        guard mode == .area, case .area(let rectPx, let opening)? = selection else { return selection }
        return .area(rectPx: rectPx, snapshot: await Self.liveSnapshot(replacing: opening))
    }

    /// The overlay shows the live screen, so the area's pixels are taken after the user lets go, not when
    /// the overlay opened. Falls back to the opening snapshot (logged) if the new capture fails.
    // ponytail: re-captures every display to get one (the ScreenCapturer seam has no per-display call),
    // and record-area pays it too; add a per-display capture if multi-display latency shows.
    private static func liveSnapshot(replacing opening: DisplaySnapshot) async -> DisplaySnapshot {
        do {
            if let live = try await ScreenCapturer.captureDisplays().first(where: { $0.displayID == opening.displayID }),
               live.image.width == opening.image.width, live.image.height == opening.image.height {
                return live
            }
            log.error("selection: display changed while selecting; using the opening snapshot")
        } catch {
            log.error("selection: live capture failed, using the opening snapshot: \(error.localizedDescription, privacy: .public)")
        }
        return opening
    }

    private func show(mode: Mode, snapshots: [DisplaySnapshot], primaryHeight: CGFloat) {
        let windows = mode == .window ? WindowList.onScreen() : []
        let mouseAppKit = NSEvent.mouseLocation
        for snapshot in snapshots {
            let frameAppKit = Geometry.rectAppKit(fromCG: snapshot.frameCG, primaryHeight: primaryHeight)
            let panel = SelectionPanel(contentRect: frameAppKit, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            panel.hidesOnDeactivate = false // NSPanel defaults to true, and shotX is normally not active
            panel.isReleasedWhenClosed = false
            panel.hasShadow = false
            panel.animationBehavior = .none
            panel.acceptsMouseMovedEvents = true
            // Live screen: the panel is see-through, only SelectionView's dimming and UI are drawn.
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.ignoresMouseEvents = false // explicit: transparent areas still take the clicks

            let view = SelectionView(mode: mode, snapshot: snapshot, windows: windows) { [weak self] in self?.finish($0) }
            view.onAdjustable = { [weak self] in self?.showPointer() }
            panel.contentView = view
            panel.setFrame(frameAppKit, display: true)
            panel.orderFrontRegardless()
            // Includes the top edge: on the top pixel row mouseLocation.y == frame.maxY, which `contains` excludes.
            if NSMouseInRect(mouseAppKit, frameAppKit, false) {
                panel.makeKey()
                view.adoptCurrentMouseLocation()
            }
            panels.append(panel)
        }

        // Local: works while one of the panels is key; every key is swallowed so nothing beeps.
        // Global: fallback for when key status was lost; only fires if the user granted input monitoring.
        let local = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == Self.escapeKeyCode { self?.finish(nil) }
            if Self.confirmKeyCodes.contains(event.keyCode) { self?.confirmAdjustedArea() }
            return nil
        }
        let global = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == Self.escapeKeyCode else { return }
            Task { @MainActor in self?.finish(nil) }
        }
        keyMonitors = [local, global].compactMap { $0 }

        if mode != .window {
            NSCursor.hide()
            cursorHidden = true
        }
    }

    private func showPointer() {
        guard cursorHidden else { return }
        NSCursor.unhide()
        cursorHidden = false
    }

    private func confirmAdjustedArea() {
        panels.lazy.compactMap { $0.contentView as? SelectionView }
            .first { $0.adjustedRectInView != nil }?
            .confirmAdjustedArea()
    }

    /// The single exit path: tears everything down and resumes the continuation exactly once.
    private func finish(_ selection: Selection?) {
        guard let continuation else { return }
        self.continuation = nil
        keyMonitors.forEach(NSEvent.removeMonitor)
        keyMonitors = []
        showPointer()
        panels.forEach { $0.close() }
        panels = []
        continuation.resume(returning: selection)
    }
}

/// Borderless panels refuse key status by default; the overlay needs it for Esc.
private final class SelectionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
