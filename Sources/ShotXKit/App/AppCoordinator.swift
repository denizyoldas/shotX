import AppKit
import Observation

/// The only place features are wired together. Menu, hotkeys and the debug URL all call
/// `perform(_:)`; features never call each other. Errors end here: logged, one alert.
final class AppCoordinator {
    private let settings: Settings
    private let overlay = SelectionOverlayController()
    private let quickAccess = QuickAccessController()
    private let editor = EditorWindowController()
    private let pins = PinWindowController()
    private let recorder = Recorder()
    private let hotKeys = HotKeyCenter()
    private let settingsWindow: SettingsWindowController
    private var isBusy = false
    private var isStopping = false
    private var hotKeysSuspended = false

    /// Observable (it reads the `@Observable` recorder); the status item tracks it.
    var isRecording: Bool { recorder.isRecording }

    init(settings: Settings) {
        self.settings = settings
        settingsWindow = SettingsWindowController(settings: settings)
        quickAccess.onAnnotate = { [editor] in editor.open($0) }
        quickAccess.onPin = { [pins] in pins.pin($0) }
        hotKeys.handler = { [weak self] in self?.perform($0) }
        recorder.onExternalStop = { [weak self] movieURL in
            self?.launch { [weak self] in try await self?.deliverRecording(movieURL) }
        }
        // Carbon would consume a registered combination before the shortcut recorder sees it.
        settingsWindow.onShortcutRecordingChanged = { [weak self] isRecordingShortcut in
            self?.hotKeysSuspended = isRecordingShortcut
            self?.applyHotKeys()
        }
        observeHotKeys()
    }

    func perform(_ action: AppAction) {
        log.info("perform \(action.rawValue, privacy: .public)")
        // While recording, every record action means "stop". It bypasses the busy gate so that it
        // is never swallowed by another flow (e.g. a selection overlay that is still open).
        if recorder.isRecording, [.recordArea, .recordFullscreen, .toggleRecording].contains(action) {
            return stopRecording()
        }
        begin(action.rawValue) { [weak self] in try await self?.run(action) }
    }

    /// Smoke-only (`shotx://capture-area`): captures a global CG rect without the overlay.
    func debugCaptureArea(rectCG: CGRect) {
        log.info("perform capture-area")
        begin("capture-area") { [weak self] in try await self?.captureArea(rectCG) }
    }

    /// One flow at a time; a new one is ignored while another is in progress.
    private func begin(_ name: String, _ flow: @escaping @MainActor () async throws -> Void) {
        guard !isBusy else {
            log.info("busy, ignored \(name, privacy: .public)")
            return
        }
        isBusy = true
        launch { [weak self] in
            defer { self?.isBusy = false }
            try await flow()
        }
    }

    // MARK: Flows

    private func run(_ action: AppAction) async throws {
        switch action {
        case .captureArea, .captureWindow:
            guard let selection = try await select(action == .captureArea ? .area : .window) else { return }
            try deliver(try await image(for: selection))
        case .captureFullscreen:
            guard Permissions.ensureScreenCapture() else { return }
            let snapshots = try await ScreenCapturer.captureDisplays()
            let displayID = displayUnderMouse()
            guard let snapshot = snapshots.first(where: { $0.displayID == displayID }) ?? snapshots.first else {
                throw ShotXError.noDisplay
            }
            try deliver(CapturedImage(image: snapshot.image, scale: snapshot.scale,
                                      displayID: snapshot.displayID, frameCG: snapshot.frameCG))
        case .ocr:
            guard let selection = try await select(.area) else { return }
            let text = try await TextRecognizer.recognize(try await image(for: selection).image)
            guard text.contains(where: { !$0.isWhitespace }) else {
                log.info("ocr: no text found, clipboard left untouched")
                NSSound.beep()
                return
            }
            Clipboard.copy(text: text)
        case .recordArea:
            guard case .area(let rectPx, let snapshot)? = try await select(.adjustableArea) else { return }
            let rectCG = Geometry.rectCG(fromPx: rectPx, displayFrameCG: snapshot.frameCG, scale: snapshot.scale)
            try await startRecording(.area(rectCG: rectCG, displayID: snapshot.displayID))
        case .recordFullscreen, .toggleRecording:
            guard Permissions.ensureScreenCapture() else { return }
            try await startRecording(.display(displayUnderMouse()))
        case .openSettings:
            settingsWindow.show()
        }
    }

    /// Permission → freeze all displays → overlay. Nil when cancelled or permission is missing.
    /// The overlay closes its panels before it returns, so a following live window capture is clean.
    private func select(_ mode: SelectionOverlayController.Mode) async throws -> Selection? {
        guard Permissions.ensureScreenCapture() else { return nil }
        let snapshots = try await ScreenCapturer.captureDisplays()
        return await overlay.select(mode: mode, snapshots: snapshots)
    }

    private func image(for selection: Selection) async throws -> CapturedImage {
        switch selection {
        case .area(let rectPx, let snapshot):
            guard let cropped = Geometry.crop(snapshot.image, toPx: rectPx) else { throw ShotXError.cropFailed }
            let rectCG = Geometry.rectCG(fromPx: rectPx, displayFrameCG: snapshot.frameCG, scale: snapshot.scale)
            return CapturedImage(image: cropped, scale: snapshot.scale, displayID: snapshot.displayID, frameCG: rectCG)
        case .window(let id):
            return try await ScreenCapturer.captureWindow(id)
        }
    }

    /// The rect must lie inside one display; anything else is logged and dropped (the URL is a trust boundary).
    private func captureArea(_ rectCG: CGRect) async throws {
        guard Permissions.ensureScreenCapture() else { return }
        let snapshots = try await ScreenCapturer.captureDisplays()
        guard let snapshot = snapshots.first(where: { $0.frameCG.contains(rectCG) }) else {
            log.error("capture-area: \(String(describing: rectCG), privacy: .public) is not inside one display")
            return
        }
        let rectInDisplay = Geometry.rectInDisplay(fromCG: rectCG, displayFrameCG: snapshot.frameCG)
        let imageSizePx = CGSize(width: snapshot.image.width, height: snapshot.image.height)
        let rectPx = Geometry.rectPx(fromInView: rectInDisplay, scale: snapshot.scale, imageSizePx: imageSizePx)
        try deliver(try await image(for: .area(rectPx: rectPx, snapshot: snapshot)))
    }

    /// Post-capture pipeline: save, copy, quick access — each per settings. A failed save is reported
    /// after the rest has run, so the capture still reaches the clipboard and a card (Save… from there).
    private func deliver(_ capture: CapturedImage) throws {
        var fileURL: URL?
        var saveError: (any Error)?
        if settings.saveAfterCapture {
            do {
                // ponytail: encodes on the main thread (~100 ms for a 5K PNG); move off-main if it janks.
                let data = try ImageEncoder.data(capture.image, scale: capture.scale, format: settings.imageFormat)
                let url = try nextFileURL(ext: settings.imageFormat.fileExtension)
                try data.write(to: url, options: .atomic)
                fileURL = url
            } catch {
                saveError = error
            }
        }
        if settings.copyAfterCapture { Clipboard.copy(image: capture.image, scale: capture.scale) }
        showQuickAccess(.image(capture, fileURL))
        if let saveError { throw saveError }
    }

    private func showQuickAccess(_ item: QuickAccessController.Item) {
        guard settings.showQuickAccess else { return }
        let seconds = settings.quickAccessSeconds
        quickAccess.show(item, closingAfter: seconds > 0 ? .seconds(seconds) : nil)
    }

    private func startRecording(_ target: RecordingTarget) async throws {
        if settings.recordMicrophone, !(await Permissions.ensureMicrophone()) { throw ShotXError.microphoneDenied }
        try await recorder.start(target, options: RecordingOptions(
            fps: settings.recordingFPS,
            captureMicrophone: settings.recordMicrophone,
            captureSystemAudio: settings.recordSystemAudio))
    }

    /// Own flow, outside the busy gate. `isStopping` only spans `Recorder.stop()`: a repeated request
    /// while the file is finalized is dropped, yet a new recording can be stopped during a GIF export.
    private func stopRecording() {
        Task { await finishRecording() }
    }

    /// Stops and delivers the recording. Quit awaits it too, so a running recording is not lost.
    func finishRecording() async {
        guard recorder.isRecording, !isStopping else {
            log.info("no recording to stop, or already stopping")
            return
        }
        isStopping = true
        await handled { [self] in try await deliverRecording(try await stoppedMovie()) }
    }

    private func stoppedMovie() async throws -> URL {
        defer { isStopping = false }
        return try await recorder.stop()
    }

    /// Moves (MP4) or converts (GIF) the recorder's temporary movie into the save directory.
    private func deliverRecording(_ movieURL: URL) async throws {
        let format = settings.recordingFormat
        let url = try nextFileURL(ext: format.fileExtension)
        switch format {
        case .mp4:
            try FileManager.default.moveItem(at: movieURL, to: url)
        case .gif:
            do {
                try await GIFExporter.export(movie: movieURL, to: url, fps: settings.gifFPS, maxWidth: settings.gifMaxWidth)
            } catch {
                // Keep the recording: the MP4 goes to the save folder instead of staying in $TMPDIR.
                try? FileManager.default.removeItem(at: url)  // a partial GIF, if any; absence is fine
                try FileManager.default.moveItem(at: movieURL, to: try nextFileURL(ext: RecordingFormat.mp4.fileExtension))
                throw error
            }
            try FileManager.default.removeItem(at: movieURL)
        }
        showQuickAccess(.recording(url))
    }

    // MARK: Helpers

    private func nextFileURL(ext: String) throws -> URL {
        try FileManager.default.createDirectory(at: settings.saveDirectory, withIntermediateDirectories: true)
        return FileNaming.url(in: settings.saveDirectory, date: Date(), ext: ext)
    }

    private func displayUnderMouse() -> CGDirectDisplayID {
        var displayID = CGMainDisplayID()
        var count: UInt32 = 0
        if let mouseCG = CGEvent(source: nil)?.location {
            CGGetDisplaysWithPoint(mouseCG, 1, &displayID, &count)
        }
        return displayID
    }

    /// Applies the hotkeys now and again whenever `Settings.hotKeys` changes.
    private func observeHotKeys() {
        withObservationTracking { applyHotKeys() } onChange: { [weak self] in
            Task { @MainActor in self?.observeHotKeys() }
        }
    }

    /// Registers nothing while a shortcut is being recorded in Settings; macOS's screenshot shortcuts
    /// are left as they are meanwhile, so a key shotX held still reaches the recorder.
    private func applyHotKeys() {
        let current = settings.hotKeys  // read first: this is the access `observeHotKeys` tracks
        hotKeys.unregisterAll()
        guard !hotKeysSuspended else { return }
        var taken: Set<HotKey> = []
        for (action, hotKey) in current {
            if hotKeys.register(hotKey, action: action) {
                taken.insert(hotKey)
            } else {
                log.error("hotkey \(hotKey.displayString, privacy: .public) for \(action.rawValue, privacy: .public) is taken")
            }
        }
        // Only shotX may fire on a key it holds: macOS's own screenshot shortcut for it is switched off.
        SystemScreenshotShortcuts.yield(to: taken)
    }

    /// On quit: macOS gets back the screenshot shortcuts shotX switched off.
    func releaseSystemShortcuts() {
        SystemScreenshotShortcuts.restore()
    }

    /// Runs a flow in its own task.
    private func launch(_ flow: @escaping @MainActor () async throws -> Void) {
        Task { await handled(flow) }
    }

    /// The single place errors are logged and shown.
    private func handled(_ flow: @MainActor () async throws -> Void) async {
        do {
            try await flow()
        } catch {
            log.error("\(error.localizedDescription, privacy: .public)")
            let alert = NSAlert(error: error)
            // shotX is LSUIElement and usually not the active app, and activation is only a
            // request: the alert also floats so it is visible above other apps' windows.
            alert.window.level = .floating
            NSApp.activate()
            alert.runModal()
        }
    }
}
