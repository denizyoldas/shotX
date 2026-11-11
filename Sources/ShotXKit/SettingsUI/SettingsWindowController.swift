import AppKit
import SwiftUI

final class SettingsWindowController {
    private let settings: Settings
    private var window: NSWindow?

    /// True while the Shortcuts tab waits for a key press. The coordinator suspends the global
    /// hotkeys meanwhile, because Carbon would consume a registered combination first.
    var onShortcutRecordingChanged: ((Bool) -> Void)?

    init(settings: Settings) {
        self.settings = settings
    }

    /// Shows (or brings forward) the single settings window.
    func show() {
        let window = self.window ?? makeWindow()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let hosting = NSHostingController(rootView: SettingsView(settings: settings) { [weak self] in
            self?.onShortcutRecordingChanged?($0)
        })
        let window = NSWindow(contentViewController: hosting)
        window.title = "shotX Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(hosting.view.fittingSize)
        window.center()
        self.window = window
        return window
    }
}
