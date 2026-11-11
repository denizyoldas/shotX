import Foundation

/// macOS's own screenshot shortcuts ("symbolic hot keys"). While shotX holds one of their key
/// combinations, macOS's is switched off so only shotX fires; it comes back when shotX lets go of
/// the key or quits. A shortcut the user switched off in System Settings is never switched back on.
// ponytail: private SkyLight calls resolved at run time; if they disappear, both apps fire again and
// the user turns macOS's off in System Settings › Keyboard › Keyboard Shortcuts › Screenshots.
enum SystemScreenshotShortcuts {
    /// shotX key combination → macOS symbolic hot key ID.
    static let symbolicIDs: [HotKey: Int32] = [
        HotKey(keyCode: 20, modifiers: [.command, .shift]): 28,           // ⇧⌘3 save screen
        HotKey(keyCode: 20, modifiers: [.command, .shift, .control]): 29, // ⌃⇧⌘3 copy screen
        HotKey(keyCode: 21, modifiers: [.command, .shift]): 30,           // ⇧⌘4 save area
        HotKey(keyCode: 21, modifiers: [.command, .shift, .control]): 31, // ⌃⇧⌘4 copy area
        HotKey(keyCode: 23, modifiers: [.command, .shift]): 184,          // ⇧⌘5 screenshot options
    ]

    /// IDs shotX switched off. Persisted, so a launch after a kill (`make run`, crash) can hand them back.
    private static let disabledKey = "systemShortcutsDisabledByShotX"

    /// Switches macOS's shortcut off for every taken key, and back on for keys shotX no longer holds.
    static func yield(to taken: Set<HotKey>) {
        guard let api else { return }
        let defaults = UserDefaults.standard
        var disabled = Set((defaults.array(forKey: disabledKey) as? [Int]).map { $0.map(Int32.init) } ?? [])
        for (hotKey, id) in symbolicIDs {
            let isOn = api.isEnabled(id)
            if taken.contains(hotKey) {
                // Off but not by us means the user turned it off: leave it, and never turn it back on.
                if isOn, set(id, enabled: false, api) { disabled.insert(id) }
            } else if disabled.contains(id), isOn || set(id, enabled: true, api) {
                disabled.remove(id)
            }
        }
        defaults.set(disabled.map(Int.init), forKey: disabledKey)
    }

    /// On quit: hands back every shortcut shotX switched off.
    static func restore() {
        yield(to: [])
    }

    // MARK: SkyLight

    private typealias SetEnabled = @convention(c) (Int32, Bool) -> Int32 // CGError, 0 = success
    private typealias IsEnabled = @convention(c) (Int32) -> Bool

    private static let api: (setEnabled: SetEnabled, isEnabled: IsEnabled)? = {
        let rtldDefault = UnsafeMutableRawPointer(bitPattern: -2) // RTLD_DEFAULT
        guard let setEnabled = dlsym(rtldDefault, "CGSSetSymbolicHotKeyEnabled"),
              let isEnabled = dlsym(rtldDefault, "CGSIsSymbolicHotKeyEnabled") else {
            log.error("system screenshot shortcuts: SkyLight calls not found; macOS's shortcuts stay on")
            return nil
        }
        return (unsafeBitCast(setEnabled, to: SetEnabled.self), unsafeBitCast(isEnabled, to: IsEnabled.self))
    }()

    private static func set(_ id: Int32, enabled: Bool, _ api: (setEnabled: SetEnabled, isEnabled: IsEnabled)) -> Bool {
        let error = api.setEnabled(id, enabled)
        if error != 0 {
            log.error("system screenshot shortcut \(id, privacy: .public): enabled=\(enabled, privacy: .public) failed (\(error, privacy: .public))")
        }
        return error == 0
    }
}
