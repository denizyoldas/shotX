import AppKit
import SwiftUI

/// Pure key-press → shortcut logic, separated from the view so it can be tested.
nonisolated enum HotKeyRecording {
    enum Outcome: Equatable {
        case cancel, clear, rejected
        case conflict(AppAction)
        case set(HotKey)
    }

    private static let escapeKeyCode: UInt16 = 53
    private static let deleteKeyCodes: Set<UInt16> = [51, 117]

    /// `NSEvent.ModifierFlags` → Carbon mask; everything but ⌘⇧⌥⌃ is dropped.
    static func modifiers(from flags: NSEvent.ModifierFlags) -> HotKey.Modifiers {
        var modifiers: HotKey.Modifiers = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        return modifiers
    }

    /// A global shortcut needs ⌘, ⌃ or ⌥; plain and shift-only keys would hijack typing.
    static func isValid(_ modifiers: HotKey.Modifiers) -> Bool {
        !modifiers.isDisjoint(with: [.command, .control, .option])
    }

    /// The other action already using `hotKey`, if any.
    static func conflict(for hotKey: HotKey, excluding action: AppAction, in hotKeys: [AppAction: HotKey]) -> AppAction? {
        hotKeys.first { $0.key != action && $0.value == hotKey }?.key
    }

    /// What a key-down means while recording a shortcut for `action`.
    static func outcome(
        keyCode: UInt16, flags: NSEvent.ModifierFlags, action: AppAction, hotKeys: [AppAction: HotKey]
    ) -> Outcome {
        if keyCode == escapeKeyCode { return .cancel }
        let modifiers = modifiers(from: flags)
        guard isValid(modifiers) else {
            return deleteKeyCodes.contains(keyCode) ? .clear : .rejected
        }
        let hotKey = HotKey(keyCode: UInt32(keyCode), modifiers: modifiers)
        if let other = conflict(for: hotKey, excluding: action, in: hotKeys) { return .conflict(other) }
        return .set(hotKey)
    }
}

/// Shows one action's shortcut; click, then press the new combination.
struct HotKeyRecorderView: View {
    let settings: Settings
    let action: AppAction
    /// The action being recorded across all rows, so only one recorder is live at a time.
    @Binding var recording: AppAction?

    @State private var monitor: Any?
    @State private var conflict: AppAction?

    private var isRecording: Bool { recording == action }

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Button(isRecording ? "Press shortcut…" : settings.hotKeys[action]?.displayString ?? "None") {
                if isRecording { stop() } else { start() }
            }
            .frame(minWidth: 130, alignment: .trailing)
            .help("Click, then press a shortcut. Esc cancels, Delete clears.")
            if let conflict {
                Text("Already used by \(conflict.title)")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .onChange(of: recording) { if !isRecording { removeMonitor() } }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            if isRecording { stop() }
        }
        .onDisappear { if isRecording { stop() } else { removeMonitor() } }
    }

    private func start() {
        conflict = nil
        removeMonitor()
        recording = action
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event)
            return nil // swallow: the key press must not reach the form
        }
    }

    private func stop() {
        removeMonitor()
        if isRecording { recording = nil }
    }

    private func removeMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func handle(_ event: NSEvent) {
        let outcome = HotKeyRecording.outcome(
            keyCode: event.keyCode, flags: event.modifierFlags, action: action, hotKeys: settings.hotKeys)
        switch outcome {
        case .rejected:
            NSSound.beep()
            return // keep recording
        case .cancel:
            break
        case .clear:
            settings.setHotKey(nil, for: action)
        case .conflict(let other):
            conflict = other
        case .set(let hotKey):
            settings.setHotKey(hotKey, for: action)
        }
        stop()
    }
}
