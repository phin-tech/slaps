import Foundation

/// A keyboard shortcut you set in Settings: a key, by its virtual key code, with modifiers.
public struct Shortcut: Codable, Hashable, Sendable {
    public struct Modifiers: OptionSet, Codable, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let control = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let shift = Modifiers(rawValue: 1 << 2)
        public static let command = Modifiers(rawValue: 1 << 3)
    }

    /// The virtual key code (`kVK_…`), which doesn't change with the keyboard layout.
    public var keyCode: UInt32
    public var modifiers: Modifiers
    /// What the key is called, as it was typed when recorded ("J", "F5", "→").
    public var key: String

    public init(keyCode: UInt32, modifiers: Modifiers, key: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.key = key
    }

    /// As the menus write it: ⌃⌥⇧⌘ then the key.
    public var display: String {
        var s = ""
        if modifiers.contains(.control) { s += "⌃" }
        if modifiers.contains(.option) { s += "⌥" }
        if modifiers.contains(.shift) { s += "⇧" }
        if modifiers.contains(.command) { s += "⌘" }
        return s + key
    }

    /// Whether it can be a shortcut that works from any app: it needs ⌃, ⌥ or ⌘, or it would take the key from
    /// everything you type.
    public var isUsable: Bool { !modifiers.isDisjoint(with: [.control, .option, .command]) && !key.isEmpty }
}
