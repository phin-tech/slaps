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
}

extension UserDefaults {
    var alertFilter: AlertFilter {
        get {
            guard let data = data(forKey: PrefKey.filter) else { return AlertFilter() }
            return (try? JSONDecoder().decode(AlertFilter.self, from: data)) ?? AlertFilter()
        }
        set { set(try? JSONEncoder().encode(newValue), forKey: PrefKey.filter) }
    }

    var overrides: Overrides {
        get {
            guard let data = data(forKey: PrefKey.overrides) else { return Overrides() }
            return (try? JSONDecoder().decode(Overrides.self, from: data)) ?? Overrides()
        }
        set { set(try? JSONEncoder().encode(newValue), forKey: PrefKey.overrides) }
    }
}
