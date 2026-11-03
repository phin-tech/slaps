import Carbon.HIToolbox

/// Keyboard shortcuts that work from any app. Carbon's hot keys need no Accessibility or Input Monitoring permission,
/// unlike watching every key press.
@MainActor
final class HotKeys {
    enum Action: UInt32, CaseIterable, Identifiable {
        case join = 1, dismiss, pause

        var id: Self { self }

        var title: String {
            switch self {
            case .join: "Join the current or next meeting"
            case .dismiss: "Dismiss the alert"
            case .pause: "Pause alerts for an hour, or resume"
            }
        }

        fileprivate var keyCode: Int {
            switch self {
            case .join: kVK_ANSI_J
            case .dismiss: kVK_ANSI_D
            case .pause: kVK_ANSI_P
            }
        }

        var shortcut: String {
            switch self {
            case .join: "⌃⌥⌘J"
            case .dismiss: "⌃⌥⌘D"
            case .pause: "⌃⌥⌘P"
            }
        }
    }

    private var refs: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private static var perform: ((Action) -> Void)?
    /// 'SLPS', so the events are recognisably ours.
    private static let signature: OSType = 0x534C_5053

    /// How many of the shortcuts macOS accepted; one another app already holds is refused.
    var registered: Int { refs.count }

    func enable(_ perform: @escaping (Action) -> Void) {
        disable()
        Self.perform = perform
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var key = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &key)
            guard status == noErr, key.signature == HotKeys.signature, let action = Action(rawValue: key.id) else {
                return OSStatus(eventNotHandledErr)
            }
            // Carbon delivers hot keys on the main thread.
            MainActor.assumeIsolated { HotKeys.perform?(action) }
            return noErr
        }, 1, &spec, nil, &handler)
        let modifiers = UInt32(controlKey | optionKey | cmdKey)
        for action in Action.allCases {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: Self.signature, id: action.rawValue)
            if RegisterEventHotKey(UInt32(action.keyCode), modifiers, id, GetApplicationEventTarget(), 0, &ref) == noErr,
               let ref {
                refs.append(ref)
            }
        }
    }

    func disable() {
        for ref in refs { UnregisterEventHotKey(ref) }
        refs = []
        if let handler { RemoveEventHandler(handler) }
        handler = nil
        Self.perform = nil
    }
}
