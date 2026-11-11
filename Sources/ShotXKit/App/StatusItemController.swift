import AppKit
import Observation

/// Menu-bar icon and its menu: one item per AppAction with its hotkey, plus Quit. While recording
/// the icon becomes a red record dot followed by the elapsed time, and the record items collapse
/// into a single "Stop Recording" item.
final class StatusItemController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let coordinator: AppCoordinator
    private let settings: Settings
    private var recordingSince: Date?
    private var timer: Timer?
    private weak var stopItem: NSMenuItem?

    init(coordinator: AppCoordinator, settings: Settings) {
        self.coordinator = coordinator
        self.settings = settings
        super.init()
        statusItem.menu = menu
        statusItem.button?.imagePosition = .imageLeading
        statusItem.button?.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        observe()
    }

    /// Rebuilds now and again whenever the hotkeys or the recording state change.
    private func observe() {
        withObservationTracking { refresh() } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
    }

    private func refresh() {
        let isRecording = coordinator.isRecording
        let hotKeys = settings.hotKeys
        if isRecording, timer == nil {
            recordingSince = Date()
            // Target/selector and `.common` mode: the time keeps counting while the menu is open.
            let timer = Timer(timeInterval: 1, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        } else if !isRecording {
            timer?.invalidate()
            timer = nil
            recordingSince = nil
        }

        let button = statusItem.button
        button?.image = NSImage(systemSymbolName: isRecording ? "record.circle.fill" : "camera.viewfinder",
                                accessibilityDescription: isRecording ? "shotX, recording" : "shotX")
        button?.contentTintColor = isRecording ? .systemRed : nil
        button?.title = ""

        menu.removeAllItems()
        for action in AppAction.allCases {
            if action == .recordArea || action == .ocr || action == .openSettings { menu.addItem(.separator()) }
            // While recording all three record actions mean "stop"; only the toggle item stays.
            if isRecording, action == .recordArea || action == .recordFullscreen { continue }
            let item = NSMenuItem(title: action.title, action: #selector(performAction(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = action.rawValue
            if let hotKey = hotKeys[action] {
                item.keyEquivalent = Self.keyEquivalent(for: hotKey)
                item.keyEquivalentModifierMask = Self.modifierMask(for: hotKey.modifiers)
            }
            if isRecording, action == .toggleRecording { stopItem = item }
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit shotX", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        tick()
    }

    /// Once per second while recording: elapsed time next to the icon and in the stop item.
    @objc private func tick() {
        guard let recordingSince else { return }
        let elapsed = Duration.seconds(Int(Date().timeIntervalSince(recordingSince)))
            .formatted(.time(pattern: .minuteSecond))
        statusItem.button?.title = elapsed
        stopItem?.title = "Stop Recording (\(elapsed))"
    }

    @objc private func performAction(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String, let action = AppAction(rawValue: name) else { return }
        coordinator.perform(action)
    }

    // MARK: Hotkey → menu key equivalent

    private static let specialKeys: [String: String] = [
        "Space": " ", "↩": "\r", "⇥": "\t", "⌫": "\u{8}", "⎋": "\u{1B}",
        "↑": "\u{F700}", "↓": "\u{F701}", "←": "\u{F702}", "→": "\u{F703}",
    ]

    /// Empty (the item then shows no shortcut) for keys without a character form.
    // ponytail: derived from `HotKey.displayString` because the key-name table is private to the frozen
    // Core; give `HotKey` a `keyEquivalent` of its own if Core is reopened.
    static func keyEquivalent(for hotKey: HotKey) -> String {
        let name = String(hotKey.displayString.drop { "⌃⌥⇧⌘".contains($0) })
        if let special = specialKeys[name] { return special }
        if name.count == 1 { return name.lowercased() }
        // F1…F12 → NSF1FunctionKey (0xF704) and up.
        if name.hasPrefix("F"), let number = UInt32(name.dropFirst()), let scalar = Unicode.Scalar(0xF703 + number) {
            return String(Character(scalar))
        }
        return ""
    }

    private static func modifierMask(for modifiers: HotKey.Modifiers) -> NSEvent.ModifierFlags {
        var mask: NSEvent.ModifierFlags = []
        if modifiers.contains(.control) { mask.insert(.control) }
        if modifiers.contains(.option) { mask.insert(.option) }
        if modifiers.contains(.shift) { mask.insert(.shift) }
        if modifiers.contains(.command) { mask.insert(.command) }
        return mask
    }
}
