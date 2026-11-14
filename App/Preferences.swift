import AppKit
import SlapsKit
import SwiftUI

/// The alert's look.
enum Theme: String, CaseIterable, Identifiable {
    case midnight, ember, forest, paper
    /// Colours you pick in Settings (`AppModel.customBackground`, `customAccent`).
    case custom

    var id: Self { self }

    var name: String {
        switch self {
        case .midnight: "Midnight"
        case .ember: "Ember"
        case .forest: "Forest"
        case .paper: "Paper"
        case .custom: "Custom"
        }
    }

    var colors: [Color] {
        switch self {
        case .midnight: [Color(red: 0.05, green: 0.07, blue: 0.20), Color(red: 0.16, green: 0.10, blue: 0.38)]
        case .ember: [Color(red: 0.45, green: 0.05, blue: 0.08), Color(red: 0.93, green: 0.36, blue: 0.10)]
        case .forest: [Color(red: 0.02, green: 0.18, blue: 0.12), Color(red: 0.10, green: 0.42, blue: 0.30)]
        case .paper, .custom: [Color(white: 0.97), Color(red: 0.93, green: 0.91, blue: 0.86)]
        }
    }

    var foreground: Color { self == .paper ? Color(white: 0.1) : .white }
    var accent: Color {
        switch self {
        case .midnight: Color(red: 0.45, green: 0.55, blue: 1.0)
        case .ember: Color(red: 1.0, green: 0.85, blue: 0.3)
        case .forest: Color(red: 0.55, green: 0.95, blue: 0.6)
        case .paper, .custom: Color(red: 0.85, green: 0.2, blue: 0.15)
        }
    }

    /// The text on the accent: the Join button's label.
    var onAccent: Color { self == .paper ? .white : .black }
}

/// What an alert is drawn in: a theme's colours, or the custom ones.
struct Palette {
    var colors: [Color]
    var foreground: Color
    var accent: Color
    var onAccent: Color

    init(_ theme: Theme) {
        colors = theme.colors
        foreground = theme.foreground
        accent = theme.accent
        onAccent = theme.onAccent
    }

    /// A gradient from the background to a darker shade of it, with text and button labels that read on them.
    init(background: ThemeColor, accent: ThemeColor) {
        colors = [Color(background), Color(background.darkened(0.3))]
        foreground = Color(background.readableText)
        self.accent = Color(accent)
        onAccent = Color(accent.readableText)
    }
}

extension Color {
    init(_ c: ThemeColor) { self.init(.sRGB, red: c.red, green: c.green, blue: c.blue) }
}

extension ThemeColor {
    /// From a colour picked in a ColorPicker, in sRGB.
    init(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .black
        self.init(red: ns.redComponent, green: ns.greenComponent, blue: ns.blueComponent)
    }
}

/// The sounds an alert can play: macOS's own, in /System/Library/Sounds.
enum AlertSound {
    static let none = "None"
    static let all = [none, "Glass", "Hero", "Ping", "Submarine", "Sosumi", "Funk", "Basso", "Blow", "Bottle", "Frog",
                      "Morse", "Pop", "Purr", "Tink"]

    static func play(_ name: String) {
        guard name != none else { return }
        NSSound(named: NSSound.Name(name))?.play()
    }
}

/// Where the settings live in UserDefaults.
enum PrefKey {
    static let leadTime = "leadTime"
    static let sound = "sound"
    static let theme = "theme"
    static let filter = "filter"
    static let pausedUntil = "pausedUntil"
    static let pauseWhileSharing = "pauseWhileSharing"
    static let hotKeys = "hotKeys"
    static let overrides = "overrides"
    static let showDate = "showDateInMenuBar"
    static let againAtStart = "againAtStart"
    static let allowExternal = "allowExternal"
    static let alertStyle = "alertStyle"
    static let customBackground = "customBackground"
    static let customAccent = "customAccent"
    static let batteryAlerts = "batteryAlerts"
    static let batteryLevel = "batteryLevel"
    static let playVideos = "playVideos"
    static let videoLinks = "videoLinks"
    static let videoMode = "videoMode"
    static let rouletteCategory = "rouletteCategory"
    static let tabs = "tabs"
    static let tabEdge = "tabEdge"
    static let tabLook = "tabLook"
    static let tabDeadline = "tabDeadline"
    static let tabSize = "tabSize"
    static let tabPosition = "tabPosition"
    static let tabsInScreenshots = "tabsInScreenshots"
    static let tabPile = "tabPile"
    static let shortcuts = "shortcuts"
}

/// Which edge of the main screen Tabs stand on.
enum TabEdge: String, CaseIterable, Identifiable {
    case right, left
    var id: Self { self }
    var name: String { self == .right ? "Right" : "Left" }
}

/// Where on their edge Tabs stand, unless their sender says.
typealias TabPosition = TabSlot

extension TabSlot: Identifiable {
    public var id: Self { self }
    var name: String { rawValue.capitalized }
}

/// How a group's Tabs pile up behind it: squared off, or askew like a pile of paper.
enum TabPile: String, CaseIterable, Identifiable {
    case neat, messy
    var id: Self { self }
    var name: String { rawValue.capitalized }
}

/// How big Tabs are, collapsed and slid out.
enum TabSize: String, CaseIterable, Identifiable {
    case regular, mini
    var id: Self { self }
    var name: String { rawValue.capitalized }
}

/// How a Tab looks until you hover over it.
enum TabLook: String, CaseIterable, Identifiable {
    /// A thin coloured sliver.
    /// A small square with the Source's initial.
    case icon
    case slim
    /// The Source's initial and a few words of the title.
    case labelled
    var id: Self { self }
    var name: String {
        switch self {
        case .icon: "Icon"
        case .slim: "Slim"
        case .labelled: "Wide"
        }
    }
}

extension UserDefaults {
    var alertFilter: AlertFilter {
        get {
            guard let data = data(forKey: PrefKey.filter) else { return AlertFilter() }
            return (try? JSONDecoder().decode(AlertFilter.self, from: data)) ?? AlertFilter()
        }
        set { set(try? JSONEncoder().encode(newValue), forKey: PrefKey.filter) }
    }

    /// The Tabs up, and any escalated into a Slap, kept across a quit.
    var tabs: TabBoard {
        get {
            guard let data = data(forKey: PrefKey.tabs) else { return TabBoard() }
            return (try? JSONDecoder().decode(TabBoard.self, from: data)) ?? TabBoard()
        }
        set { set(try? JSONEncoder().encode(newValue), forKey: PrefKey.tabs) }
    }

    /// Shortcuts you changed, by `HotKeys.Action.key`; the rest are their defaults.
    var shortcuts: [String: Shortcut] {
        get {
            guard let data = data(forKey: PrefKey.shortcuts) else { return [:] }
            return (try? JSONDecoder().decode([String: Shortcut].self, from: data)) ?? [:]
        }
        set { set(try? JSONEncoder().encode(newValue), forKey: PrefKey.shortcuts) }
    }

    var overrides: Overrides {
        get {
            guard let data = data(forKey: PrefKey.overrides) else { return Overrides() }
            return (try? JSONDecoder().decode(Overrides.self, from: data)) ?? Overrides()
        }
        set { set(try? JSONEncoder().encode(newValue), forKey: PrefKey.overrides) }
    }
}
