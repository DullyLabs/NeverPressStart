import Carbon

/// A global hot key via the Carbon Event Manager. Unlike event taps or global
/// monitors, RegisterEventHotKey needs no Accessibility or Input Monitoring permission.
@MainActor
final class HotKey {
    private let keyCode: UInt32
    private let modifiers: UInt32
    private let action: () -> Void
    // nonisolated(unsafe) so the nonisolated deinit can release them.
    private nonisolated(unsafe) var hotKeyRef: EventHotKeyRef?
    private nonisolated(unsafe) var handlerRef: EventHandlerRef?

    init(keyCode: Int, modifiers: Int = 0, action: @escaping () -> Void) {
        self.keyCode = UInt32(keyCode)
        self.modifiers = UInt32(modifiers)
        self.action = action
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }

    var isRegistered: Bool { hotKeyRef != nil }

    func register() {
        guard hotKeyRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            let hotKey = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
            MainActor.assumeIsolated { hotKey.action() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
        guard status == noErr else { return log("InstallEventHandler failed: \(status)") }

        let id = EventHotKeyID(signature: OSType(0x464F4355), id: 1)   // 'FOCU'
        let regStatus = RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
        if regStatus != noErr {
            log("RegisterEventHotKey failed: \(regStatus)")
            unregister()
        }
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        hotKeyRef = nil
        handlerRef = nil
    }
}
