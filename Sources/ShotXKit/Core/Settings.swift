import Foundation
import Observation

/// User preferences, persisted in UserDefaults. Inject a suite in tests.
@Observable
final class Settings {
    @ObservationIgnored private let defaults: UserDefaults

    var saveDirectory: URL { didSet { defaults.set(saveDirectory.path, forKey: "saveDirectory") } }
    var imageFormat: ImageFormat { didSet { defaults.set(imageFormat.rawValue, forKey: "imageFormat") } }
    var copyAfterCapture: Bool { didSet { defaults.set(copyAfterCapture, forKey: "copyAfterCapture") } }
    var saveAfterCapture: Bool { didSet { defaults.set(saveAfterCapture, forKey: "saveAfterCapture") } }
    var showQuickAccess: Bool { didSet { defaults.set(showQuickAccess, forKey: "showQuickAccess") } }
    /// Seconds an untouched Quick Access card stays on screen; 0 keeps it until closed.
    var quickAccessSeconds: Int { didSet { defaults.set(quickAccessSeconds, forKey: "quickAccessSeconds") } }
    var recordingFormat: RecordingFormat { didSet { defaults.set(recordingFormat.rawValue, forKey: "recordingFormat") } }
    var recordingFPS: Int { didSet { defaults.set(recordingFPS, forKey: "recordingFPS") } }
    var recordMicrophone: Bool { didSet { defaults.set(recordMicrophone, forKey: "recordMicrophone") } }
    var recordSystemAudio: Bool { didSet { defaults.set(recordSystemAudio, forKey: "recordSystemAudio") } }
    var gifFPS: Int { didSet { defaults.set(gifFPS, forKey: "gifFPS") } }
    var gifMaxWidth: Int { didSet { defaults.set(gifMaxWidth, forKey: "gifMaxWidth") } }

    /// Actions without an entry have no shortcut. Mutate via `setHotKey(_:for:)` or assign.
    var hotKeys: [AppAction: HotKey] {
        didSet {
            let byName = Dictionary(uniqueKeysWithValues: hotKeys.map { ($0.key.rawValue, $0.value) })
            // Encoding a [String: struct of two integers] cannot fail; nil would only skip persistence.
            defaults.set(try? JSONEncoder().encode(byName), forKey: "hotKeys")
        }
    }

    /// `defaults write local.shotx.app debugURL -bool true` enables the `shotx://<AppAction>` scheme.
    var debugURLEnabled: Bool { defaults.bool(forKey: "debugURL") }

    // Chosen to avoid the system's ⌘⇧3/4/5/6 and common app shortcuts.
    static let defaultHotKeys: [AppAction: HotKey] = [
        .captureArea: HotKey(keyCode: 0, modifiers: [.control, .option]),               // ⌃⌥A
        .captureWindow: HotKey(keyCode: 13, modifiers: [.control, .option]),            // ⌃⌥W
        .captureFullscreen: HotKey(keyCode: 3, modifiers: [.control, .option]),         // ⌃⌥F
        .recordArea: HotKey(keyCode: 15, modifiers: [.control, .option]),               // ⌃⌥R
        .recordFullscreen: HotKey(keyCode: 15, modifiers: [.control, .option, .shift]), // ⌃⌥⇧R
        .toggleRecording: HotKey(keyCode: 1, modifiers: [.control, .option]),           // ⌃⌥S
        .ocr: HotKey(keyCode: 17, modifiers: [.control, .option]),                      // ⌃⌥T
    ]

    /// macOS's own screenshot keys. While shotX holds them, `SystemScreenshotShortcuts` switches
    /// macOS's versions off so only shotX fires.
    static let macOSScreenshotHotKeys: [AppAction: HotKey] = [
        .captureFullscreen: HotKey(keyCode: 20, modifiers: [.command, .shift]), // ⇧⌘3
        .captureArea: HotKey(keyCode: 21, modifiers: [.command, .shift]),       // ⇧⌘4
        .recordArea: HotKey(keyCode: 23, modifiers: [.command, .shift]),        // ⇧⌘5
    ]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        saveDirectory = defaults.string(forKey: "saveDirectory").map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? pictures.appendingPathComponent("shotX", isDirectory: true)
        imageFormat = defaults.string(forKey: "imageFormat").flatMap(ImageFormat.init) ?? .png
        copyAfterCapture = defaults.object(forKey: "copyAfterCapture") as? Bool ?? true
        saveAfterCapture = defaults.object(forKey: "saveAfterCapture") as? Bool ?? true
        showQuickAccess = defaults.object(forKey: "showQuickAccess") as? Bool ?? true
        quickAccessSeconds = defaults.object(forKey: "quickAccessSeconds") as? Int ?? 10
        recordingFormat = defaults.string(forKey: "recordingFormat").flatMap(RecordingFormat.init) ?? .mp4
        recordingFPS = defaults.object(forKey: "recordingFPS") as? Int ?? 30
        recordMicrophone = defaults.bool(forKey: "recordMicrophone")
        recordSystemAudio = defaults.bool(forKey: "recordSystemAudio")
        gifFPS = defaults.object(forKey: "gifFPS") as? Int ?? 15
        gifMaxWidth = defaults.object(forKey: "gifMaxWidth") as? Int ?? 800
        if let data = defaults.data(forKey: "hotKeys"),
           let byName = try? JSONDecoder().decode([String: HotKey].self, from: data) {
            hotKeys = Dictionary(uniqueKeysWithValues: byName.compactMap { name, key in
                AppAction(rawValue: name).map { ($0, key) }
            })
        } else {
            hotKeys = Self.defaultHotKeys
        }
    }

    /// Pass nil to clear the shortcut.
    func setHotKey(_ hotKey: HotKey?, for action: AppAction) {
        hotKeys[action] = hotKey
    }
}
