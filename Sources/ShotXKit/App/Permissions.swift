import AppKit
import AVFoundation

enum Permissions {
    /// True when Screen Recording is granted. Otherwise triggers the system prompt (first time
    /// only) and shows an alert offering System Settings; the caller should just stop.
    static func ensureScreenCapture() -> Bool {
        if CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() { return true }
        log.error("screen capture permission missing")
        let alert = NSAlert()
        alert.messageText = "shotX needs Screen Recording permission"
        alert.informativeText = "Enable shotX under Privacy & Security → Screen Recording, then relaunch shotX."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
        return false
    }

    /// Prompts on first use.
    static func ensureMicrophone() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }
}
