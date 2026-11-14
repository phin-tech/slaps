import AppKit
import Carbon.HIToolbox
import SlapsKit

/// Keyboard shortcuts that work from any app. Carbon's hot keys need no Accessibility or Input Monitoring permission,
/// unlike watching every key press. Each can be changed in Settings › General (`AppModel.shortcuts`).
@MainActor
final class HotKeys {
    enum Action: UInt32, CaseIterable, Identifiable {
        case join = 1, dismiss, pause, tabs

        var id: Self { self }

        /// Its name in the settings.
        var key: String {
            switch self {
            case .join: "join"
            case .dismiss: "dismiss"
            case .pause: "pause"
            case .tabs: "tabs"
            }
        }

        var title: String {
            switch self {
            case .join: "Join the current or next meeting"
            case .dismiss: "Dismiss the alert"
            case .pause: "Pause alerts for an hour, or resume"
            case .tabs: "Open the tabs, to work them from the keyboard"
            }
        }

        /// ⌃⌥⌘ and a letter, until you change it.
        var defaultShortcut: Shortcut {
            let (code, key) = switch self {
            case .join: (kVK_ANSI_J, "J")
            case .dismiss: (kVK_ANSI_D, "D")
            case .pause: (kVK_ANSI_P, "P")
            case .tabs: (kVK_ANSI_T, "T")
            }
            return Shortcut(keyCode: UInt32(code), modifiers: [.control, .option, .command], key: key)
        }
    }

    private var refs: [Action: EventHotKeyRef] = [:]
    private var handler: EventHandlerRef?
    private static var perform: ((Action) -> Void)?
    /// 'SLPS', so the events are recognisably ours.
    private static let signature: OSType = 0x534C_5053

    /// How many of the shortcuts macOS accepted; one another app already holds is refused.
    var registered: Int { refs.count }

    /// Whether macOS accepted this one.
    func isRegistered(_ action: Action) -> Bool { refs[action] != nil }

    func enable(_ shortcuts: [Action: Shortcut], _ perform: @escaping (Action) -> Void) {
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
        for action in Action.allCases {
            let shortcut = shortcuts[action] ?? action.defaultShortcut
            guard shortcut.isUsable else { continue }
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: Self.signature, id: action.rawValue)
            if RegisterEventHotKey(shortcut.keyCode, Self.carbon(shortcut.modifiers), id, GetApplicationEventTarget(), 0,
                                   &ref) == noErr, let ref {
                refs[action] = ref
            }
        }
    }

    func disable() {
        for ref in refs.values { UnregisterEventHotKey(ref) }
        refs = [:]
        if let handler { RemoveEventHandler(handler) }
        handler = nil
        Self.perform = nil
    }

    private static func carbon(_ m: Shortcut.Modifiers) -> UInt32 {
        var flags = 0
        if m.contains(.control) { flags |= controlKey }
        if m.contains(.option) { flags |= optionKey }
        if m.contains(.shift) { flags |= shiftKey }
        if m.contains(.command) { flags |= cmdKey }
        return UInt32(flags)
    }
}

extension Shortcut {
    /// The shortcut a key press makes, as the recorder in Settings takes it.
    init(_ event: NSEvent) {
        let flags = event.modifierFlags
        var m: Modifiers = []
        if flags.contains(.control) { m.insert(.control) }
        if flags.contains(.option) { m.insert(.option) }
        if flags.contains(.shift) { m.insert(.shift) }
        if flags.contains(.command) { m.insert(.command) }
        self.init(keyCode: UInt32(event.keyCode), modifiers: m, key: Self.name(of: event))
    }

    private static func name(of event: NSEvent) -> String {
        switch Int(event.keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Delete: return "⌫"
        case kVK_ForwardDelete: return "⌦"
        case kVK_Escape: return "⎋"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_Home: return "↖"
        case kVK_End: return "↘"
        case kVK_PageUp: return "⇞"
        case kVK_PageDown: return "⇟"
        default:
            // Function keys' codes aren't in order, so look them up.
            if let n = functionKeys.firstIndex(of: Int(event.keyCode)) { return "F\(n + 1)" }
            return (event.charactersIgnoringModifiers ?? "").uppercased()
        }
    }

    private static let functionKeys = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
                                       kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19,
                                       kVK_F20]
}
