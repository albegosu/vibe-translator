import Carbon.HIToolbox

/// System-wide shortcuts via Carbon's RegisterEventHotKey: works from a menu bar app
/// and, unlike event taps, needs no extra permission just to listen.
@MainActor
final class HotKeyCenter {
    enum Action: UInt32, CaseIterable {
        case translate = 1
        case restore = 2
        case translateSelection = 3
    }

    var onAction: ((Action) -> Void)?

    private var registered: [Action: EventHotKeyRef] = [:]
    private var handlerRef: EventHandlerRef?
    private static let signature: OSType = 0x5642_5452 // "VBTR"

    func install() {
        guard handlerRef == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                    nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
                )
                guard status == noErr, hotKeyID.signature == HotKeyCenter.signature,
                      let action = Action(rawValue: hotKeyID.id) else { return OSStatus(eventNotHandledErr) }
                let center = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
                // Carbon delivers hot key events on the main thread.
                MainActor.assumeIsolated { center.onAction?(action) }
                return noErr
            },
            1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handlerRef
        )
        assert(status == noErr, "InstallEventHandler failed: \(status)")
    }

    /// Returns `false` if the combination could not be registered (usually taken by another app).
    @discardableResult
    func register(_ shortcut: Shortcut?, for action: Action) -> Bool {
        unregister(action)
        guard let shortcut else { return true }
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(shortcut.keyCode), shortcut.carbonModifiers,
            EventHotKeyID(signature: Self.signature, id: action.rawValue),
            GetApplicationEventTarget(), 0, &ref
        )
        guard status == noErr, let ref else { return false }
        registered[action] = ref
        return true
    }

    func unregister(_ action: Action) {
        if let ref = registered.removeValue(forKey: action) {
            UnregisterEventHotKey(ref)
        }
    }

    func unregisterAll() {
        Action.allCases.forEach(unregister)
    }
}
