import Carbon.HIToolbox
import Foundation
import Testing
@testable import ShotXKit

@MainActor
struct SettingsTests {
    let suiteName = "shotx.tests.\(UUID().uuidString)"

    private func makeDefaults() throws -> UserDefaults {
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @Test func defaults() throws {
        let settings = Settings(defaults: try makeDefaults())
        #expect(settings.saveDirectory.lastPathComponent == "shotX")
        #expect(settings.imageFormat == .png)
        #expect(settings.copyAfterCapture && settings.saveAfterCapture && settings.showQuickAccess)
        #expect(settings.quickAccessSeconds == 10)
        #expect(settings.recordingFormat == .mp4)
        #expect(settings.recordingFPS == 30)
        #expect(!settings.recordMicrophone && !settings.recordSystemAudio)
        #expect(settings.gifFPS == 15 && settings.gifMaxWidth == 800)
        #expect(!settings.debugURLEnabled)
        #expect(settings.hotKeys == Settings.defaultHotKeys)
        #expect(settings.hotKeys[.openSettings] == nil)
    }

    @Test func defaultHotKeysAreDistinctAndAvoidSystemScreenshotKeys() {
        let keys = Array(Settings.defaultHotKeys.values)
        #expect(Set(keys).count == keys.count)
        let systemKeyCodes: Set<UInt32> = [UInt32(kVK_ANSI_3), UInt32(kVK_ANSI_4), UInt32(kVK_ANSI_5), UInt32(kVK_ANSI_6)]
        #expect(keys.allSatisfy { !systemKeyCodes.contains($0.keyCode) })
    }

    @Test func macOSScreenshotKeysAreShiftCommand345AndFitWithTheDefaults() {
        let keys = Settings.macOSScreenshotHotKeys
        #expect(keys[.captureFullscreen] == HotKey(keyCode: UInt32(kVK_ANSI_3), modifiers: [.command, .shift]))
        #expect(keys[.captureArea] == HotKey(keyCode: UInt32(kVK_ANSI_4), modifiers: [.command, .shift]))
        #expect(keys[.recordArea] == HotKey(keyCode: UInt32(kVK_ANSI_5), modifiers: [.command, .shift]))
        let merged = Array(Settings.defaultHotKeys.merging(keys) { $1 }.values)
        #expect(Set(merged).count == merged.count)
    }

    /// Table only: tests never switch macOS's shortcuts (`yield` / `restore` are app-only).
    @Test func systemScreenshotShortcutTableMatchesMacOSIDs() {
        let ids = SystemScreenshotShortcuts.symbolicIDs
        let shiftCommand: HotKey.Modifiers = [.command, .shift]
        #expect(ids[HotKey(keyCode: UInt32(kVK_ANSI_3), modifiers: shiftCommand)] == 28)
        #expect(ids[HotKey(keyCode: UInt32(kVK_ANSI_3), modifiers: shiftCommand.union(.control))] == 29)
        #expect(ids[HotKey(keyCode: UInt32(kVK_ANSI_4), modifiers: shiftCommand)] == 30)
        #expect(ids[HotKey(keyCode: UInt32(kVK_ANSI_4), modifiers: shiftCommand.union(.control))] == 31)
        #expect(ids[HotKey(keyCode: UInt32(kVK_ANSI_5), modifiers: shiftCommand)] == 184)
        // Every key the "Use ⇧⌘3 / ⇧⌘4 / ⇧⌘5" button assigns has a macOS shortcut to switch off.
        #expect(Settings.macOSScreenshotHotKeys.values.allSatisfy { ids[$0] != nil })
    }

    @Test func persistsThroughInjectedDefaults() throws {
        let defaults = try makeDefaults()
        let settings = Settings(defaults: defaults)
        settings.saveDirectory = URL(fileURLWithPath: "/tmp/shots", isDirectory: true)
        settings.imageFormat = .jpeg
        settings.copyAfterCapture = false
        settings.saveAfterCapture = false
        settings.showQuickAccess = false
        settings.quickAccessSeconds = 0
        settings.recordingFormat = .gif
        settings.recordingFPS = 60
        settings.recordMicrophone = true
        settings.recordSystemAudio = true
        settings.gifFPS = 10
        settings.gifMaxWidth = 480
        settings.setHotKey(HotKey(keyCode: 18, modifiers: [.command, .shift]), for: .captureArea)
        settings.setHotKey(nil, for: .ocr)
        defaults.set(true, forKey: "debugURL")

        let reloaded = Settings(defaults: defaults)
        #expect(reloaded.saveDirectory.path == "/tmp/shots")
        #expect(reloaded.imageFormat == .jpeg)
        #expect(!reloaded.copyAfterCapture && !reloaded.saveAfterCapture && !reloaded.showQuickAccess)
        #expect(reloaded.quickAccessSeconds == 0)
        #expect(reloaded.recordingFormat == .gif)
        #expect(reloaded.recordingFPS == 60)
        #expect(reloaded.recordMicrophone && reloaded.recordSystemAudio)
        #expect(reloaded.gifFPS == 10 && reloaded.gifMaxWidth == 480)
        #expect(reloaded.hotKeys[.captureArea] == HotKey(keyCode: 18, modifiers: [.command, .shift]))
        #expect(reloaded.hotKeys[.ocr] == nil)
        #expect(reloaded.hotKeys[.captureWindow] == Settings.defaultHotKeys[.captureWindow])
        #expect(reloaded.debugURLEnabled)
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func hotKeyDisplayString() {
        #expect(HotKey(keyCode: 0, modifiers: [.control, .option]).displayString == "⌃⌥A")
        #expect(HotKey(keyCode: 21, modifiers: [.command, .shift, .control, .option]).displayString == "⌃⌥⇧⌘4")
        #expect(HotKey(keyCode: 49, modifiers: .command).displayString == "⌘Space")
        #expect(HotKey(keyCode: 999, modifiers: []).displayString == "Key999")
    }

    @Test func hotKeyModifiersMatchCarbon() {
        #expect(HotKey.Modifiers.command.rawValue == UInt32(cmdKey))
        #expect(HotKey.Modifiers.shift.rawValue == UInt32(shiftKey))
        #expect(HotKey.Modifiers.option.rawValue == UInt32(optionKey))
        #expect(HotKey.Modifiers.control.rawValue == UInt32(controlKey))
        #expect(UInt32(kVK_ANSI_A) == 0 && UInt32(kVK_ANSI_W) == 13 && UInt32(kVK_ANSI_T) == 17)
    }
}
