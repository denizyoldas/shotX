import Carbon.HIToolbox
import Testing
@testable import ShotXKit

/// Real Carbon registrations in the test process. Combinations are ⌃⌥⇧⌘ + F-keys so they do not
/// collide with real shortcuts; every test unregisters. Serialized: registrations are process-global.
@MainActor
@Suite(.serialized)
struct HotKeyCenterTests {
    private let all: HotKey.Modifiers = [.control, .option, .shift, .command]

    private func key(_ code: Int) -> HotKey { HotKey(keyCode: UInt32(code), modifiers: all) }

    /// Sends a synthetic kEventHotKeyPressed through the application event target, i.e. through
    /// the installed C callback, exactly as Carbon does for a real key press.
    private func press(id: UInt32, signature: OSType = 0x7368_7458) throws {
        var event: EventRef?
        #expect(CreateEvent(nil, OSType(kEventClassKeyboard), UInt32(kEventHotKeyPressed), 0, 0, &event) == noErr)
        let created = try #require(event)
        defer { ReleaseEvent(created) }
        var hotKeyID = EventHotKeyID(signature: signature, id: id)
        #expect(SetEventParameter(
            created, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
            MemoryLayout<EventHotKeyID>.size, &hotKeyID) == noErr)
        SendEventToEventTarget(created, GetApplicationEventTarget())
    }

    @Test func registerUnregisterReRegisterDoesNotLeak() {
        let center = HotKeyCenter()
        defer { center.unregisterAll() }
        for _ in 0..<20 {
            #expect(center.register(key(kVK_F13), action: .captureArea))
            #expect(center.actions.count == 1)
            center.unregisterAll()
            #expect(center.actions.isEmpty)
        }
    }

    @Test func sameCombinationTwiceIsRefused() {
        let center = HotKeyCenter()
        defer { center.unregisterAll() }
        #expect(center.register(key(kVK_F14), action: .captureArea))
        #expect(!center.register(key(kVK_F14), action: .captureWindow))
        #expect(Array(center.actions.values) == [.captureArea])

        let other = HotKeyCenter()
        defer { other.unregisterAll() }
        #expect(!other.register(key(kVK_F14), action: .ocr))
    }

    @Test func deinitReleasesRegistrations() {
        do {
            let scoped = HotKeyCenter()
            #expect(scoped.register(key(kVK_F15), action: .ocr))
        }
        let center = HotKeyCenter()
        defer { center.unregisterAll() }
        #expect(center.register(key(kVK_F15), action: .ocr))
    }

    @Test func pressedIDMapsToAction() throws {
        let center = HotKeyCenter()
        defer { center.unregisterAll() }
        var fired: [AppAction] = []
        center.handler = { fired.append($0) }
        #expect(center.register(key(kVK_F16), action: .captureFullscreen))
        #expect(center.register(key(kVK_F17), action: .toggleRecording))
        let ids = Dictionary(uniqueKeysWithValues: center.actions.map { ($1, $0) })

        try press(id: try #require(ids[.toggleRecording]))
        try press(id: try #require(ids[.captureFullscreen]))
        try press(id: 9_999) // unknown id
        try press(id: try #require(ids[.captureFullscreen]), signature: 0x1234_5678) // foreign signature
        #expect(fired == [.toggleRecording, .captureFullscreen])

        center.unregisterAll()
        try press(id: try #require(ids[.toggleRecording]))
        #expect(fired.count == 2)
    }
}
