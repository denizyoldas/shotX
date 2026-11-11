import Carbon.HIToolbox

/// Global hotkeys via Carbon `RegisterEventHotKey` (needs no Accessibility permission).
final class HotKeyCenter {
    /// Called on the main actor when a registered hotkey is pressed.
    var handler: ((AppAction) -> Void)?

    /// Carbon hotkey id → action, for the live registrations.
    private(set) var actions: [UInt32: AppAction] = [:]
    private var refs: [EventHotKeyRef] = []
    private var eventHandler: EventHandlerRef?
    private var nextID: UInt32 = 1

    private static let signature: OSType = 0x7368_7458 // 'shtX'

    isolated deinit {
        unregisterAll()
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }

    /// False when the system refuses the combination (already taken).
    @discardableResult
    func register(_ hotKey: HotKey, action: AppAction) -> Bool {
        guard installEventHandlerIfNeeded() else { return false }
        let id = nextID
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            hotKey.keyCode, hotKey.modifiers.rawValue, EventHotKeyID(signature: Self.signature, id: id),
            GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else {
            log.error("hotkey \(hotKey.displayString, privacy: .public) refused, OSStatus \(status)")
            return false
        }
        nextID += 1
        refs.append(ref)
        actions[id] = action
        return true
    }

    func unregisterAll() {
        for ref in refs {
            let status = UnregisterEventHotKey(ref)
            if status != noErr { log.error("UnregisterEventHotKey failed, OSStatus \(status)") }
        }
        refs.removeAll()
        actions.removeAll()
    }

    private func installEventHandlerIfNeeded() -> Bool {
        if eventHandler != nil { return true }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        // Unretained is safe: deinit removes the handler before `self` goes away.
        let status = InstallEventHandler(
            GetApplicationEventTarget(), Self.hotKeyPressed, 1, &spec,
            Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
        if status != noErr { log.error("InstallEventHandler failed, OSStatus \(status)") }
        return status == noErr
    }

    private func dispatch(id: UInt32) {
        guard let action = actions[id] else { return }
        handler?(action)
    }

    /// C callback. Carbon delivers application-target events on the main thread; `assumeIsolated`
    /// states that and traps (instead of racing) should it ever be wrong.
    private static let hotKeyPressed: EventHandlerUPP = { _, event, userData in
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
            MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
        guard status == noErr, hotKeyID.signature == signature else { return OSStatus(eventNotHandledErr) }
        // The raw pointer is not Sendable; its address is, and it is only dereferenced on the main actor.
        let address = UInt(bitPattern: userData)
        let id = hotKeyID.id
        MainActor.assumeIsolated {
            guard let pointer = UnsafeRawPointer(bitPattern: address) else { return }
            Unmanaged<HotKeyCenter>.fromOpaque(pointer).takeUnretainedValue().dispatch(id: id)
        }
        return noErr
    }
}
