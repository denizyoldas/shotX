import AppKit
import Testing
@testable import ShotXKit

@MainActor
struct SettingsUITests {
    private let hotKeys = Settings.defaultHotKeys
    private let areaKey = HotKey(keyCode: 0, modifiers: [.control, .option]) // ⌃⌥A, default for captureArea

    @Test func convertsModifierFlagsToCarbonMask() {
        #expect(HotKeyRecording.modifiers(from: []).rawValue == 0)
        #expect(HotKeyRecording.modifiers(from: .command).rawValue == 0x100)
        #expect(HotKeyRecording.modifiers(from: .shift).rawValue == 0x200)
        #expect(HotKeyRecording.modifiers(from: .option).rawValue == 0x800)
        #expect(HotKeyRecording.modifiers(from: .control).rawValue == 0x1000)
        #expect(HotKeyRecording.modifiers(from: [.command, .shift, .option, .control]).rawValue == 0x1B00)
        // Caps lock, fn and numeric-pad flags are not part of a shortcut.
        #expect(HotKeyRecording.modifiers(from: [.control, .capsLock, .function, .numericPad]) == .control)
    }

    @Test func requiresCommandControlOrOption() {
        #expect(!HotKeyRecording.isValid([]))
        #expect(!HotKeyRecording.isValid(.shift))
        #expect(HotKeyRecording.isValid(.command))
        #expect(HotKeyRecording.isValid(.control))
        #expect(HotKeyRecording.isValid([.option, .shift]))
    }

    @Test func findsConflictWithOtherActionOnly() {
        #expect(HotKeyRecording.conflict(for: areaKey, excluding: .ocr, in: hotKeys) == .captureArea)
        #expect(HotKeyRecording.conflict(for: areaKey, excluding: .captureArea, in: hotKeys) == nil)
        // Same key, different modifiers is a different shortcut.
        let shifted = HotKey(keyCode: 0, modifiers: [.control, .option, .shift])
        #expect(HotKeyRecording.conflict(for: shifted, excluding: .ocr, in: hotKeys) == nil)
    }

    @Test func mapsKeyPressToOutcome() {
        func outcome(_ keyCode: UInt16, _ flags: NSEvent.ModifierFlags) -> HotKeyRecording.Outcome {
            HotKeyRecording.outcome(keyCode: keyCode, flags: flags, action: .ocr, hotKeys: hotKeys)
        }
        #expect(outcome(53, []) == .cancel)
        #expect(outcome(51, []) == .clear)
        #expect(outcome(0, []) == .rejected)
        #expect(outcome(0, .shift) == .rejected)
        #expect(outcome(0, [.control, .option]) == .conflict(.captureArea))
        #expect(outcome(11, [.command, .shift]) == .set(HotKey(keyCode: 11, modifiers: [.command, .shift])))
        // Delete with a real modifier is an ordinary shortcut, not "clear".
        #expect(outcome(51, .command) == .set(HotKey(keyCode: 51, modifiers: .command)))
    }
}
