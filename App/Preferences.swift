import AppKit
import SlapsKit
import SwiftUI

/// The alert's look.
enum Theme: String, CaseIterable, Identifiable {
    case midnight, ember, forest, paper

    var id: Self { self }

    var name: String {
        switch self {
        case .midnight: "Midnight"
        case .ember: "Ember"
        case .forest: "Forest"
        case .paper: "Paper"
        }
    }

    var colors: [Color] {
        switch self {
        case .midnight: [Color(red: 0.05, green: 0.07, blue: 0.20), Color(red: 0.16, green: 0.10, blue: 0.38)]
        case .ember: [Color(red: 0.45, green: 0.05, blue: 0.08), Color(red: 0.93, green: 0.36, blue: 0.10)]
        case .forest: [Color(red: 0.02, green: 0.18, blue: 0.12), Color(red: 0.10, green: 0.42, blue: 0.30)]
        case .paper: [Color(white: 0.97), Color(red: 0.93, green: 0.91, blue: 0.86)]
        }
    }

    var foreground: Color { self == .paper ? Color(white: 0.1) : .white }
    var accent: Color {
        switch self {
        case .midnight: Color(red: 0.45, green: 0.55, blue: 1.0)
        case .ember: Color(red: 1.0, green: 0.85, blue: 0.3)
        case .forest: Color(red: 0.55, green: 0.95, blue: 0.6)
        case .paper: Color(red: 0.85, green: 0.2, blue: 0.15)
        }
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
}

extension UserDefaults {
    var alertFilter: AlertFilter {
        get {
            guard let data = data(forKey: PrefKey.filter) else { return AlertFilter() }
            return (try? JSONDecoder().decode(AlertFilter.self, from: data)) ?? AlertFilter()
        }
        set { set(try? JSONEncoder().encode(newValue), forKey: PrefKey.filter) }
    }
}
