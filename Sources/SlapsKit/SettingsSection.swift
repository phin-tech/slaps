/// A section of the Settings window: a line in its sidebar, and the page shown when it's chosen. The search box finds
/// a section by its name or its keywords, as Typecase's settings window does, not by the rows on its page.
public enum SettingsSection: String, CaseIterable, Identifiable, Sendable {
    case general
    case alerts
    case video
    case battery
    case calendars
    case filters
    case tabs
    case shortcuts
    case otherApps
    case commandLine
    case updates

    public var id: Self { self }

    public var name: String {
        switch self {
        case .general: "General"
        case .alerts: "Alerts"
        case .video: "Video"
        case .battery: "Battery"
        case .calendars: "Calendars"
        case .filters: "Filters"
        case .tabs: "Tabs"
        case .shortcuts: "Shortcuts"
        case .otherApps: "Other Apps"
        case .commandLine: "Command Line"
        case .updates: "Updates"
        }
    }

    /// An SF Symbol for the sidebar.
    public var symbol: String {
        switch self {
        case .general: "gearshape"
        case .alerts: "bell.badge"
        case .video: "play.rectangle"
        case .battery: "battery.25percent"
        case .calendars: "calendar"
        case .filters: "line.3.horizontal.decrease.circle"
        case .tabs: "rectangle.righthalf.inset.filled"
        case .shortcuts: "command"
        case .otherApps: "link"
        case .commandLine: "terminal"
        case .updates: "arrow.down.circle"
        }
    }

    /// A line under the section's name, at the top of its page.
    public var summary: String {
        switch self {
        case .general: "The menu bar, opening at login, and the welcome window."
        case .alerts: "When an alert goes up, how much of the screen it takes, and how it looks and sounds."
        case .video: "A YouTube video in the alert, in place of its sound."
        case .battery: "An alert when the battery runs low."
        case .calendars: "The calendars Slaps alerts you for."
        case .filters: "The events and reminders that get an alert."
        case .tabs: "Notices other apps leave on the edge of the screen."
        case .shortcuts: "Keys that work from any app."
        case .otherApps: "Scripts, Shortcuts and other apps putting up alerts and tabs."
        case .commandLine: "slaps in a terminal, for scripts and CI."
        case .updates: "New versions of Slaps, and betas."
        }
    }

    /// Words the search box finds the section by, besides its name.
    public var keywords: [String] {
        switch self {
        case .general: ["menu bar", "date", "login", "startup", "welcome", "onboarding"]
        case .alerts: ["lead time", "minutes before", "style", "full screen", "banner", "card", "sound", "theme",
                       "colour", "color", "test", "again", "screen sharing", "hold"]
        case .video: ["youtube", "playlist", "channel", "roulette", "music"]
        case .battery: ["power", "low", "charge", "percent"]
        case .calendars: ["account", "google", "microsoft", "exchange", "icloud", "access", "privacy"]
        case .filters: ["all-day", "declined", "attendees", "people", "call link", "reminders", "priority", "ignore",
                        "titles", "words"]
        case .tabs: ["edge", "position", "look", "size", "stack", "deadline", "screenshots", "recordings"]
        case .shortcuts: ["hotkeys", "keyboard", "keys", "join", "dismiss", "pause"]
        case .otherApps: ["applescript", "url", "slaps://", "shortcuts", "raycast", "external", "allow"]
        case .commandLine: ["cli", "terminal", "shell", "install", "path", "~/.local/bin", "slaps"]
        case .updates: ["beta", "sparkle", "version", "check"]
        }
    }

    /// The sections with a word in their name or keywords starting with each word of `query`, ignoring case, in
    /// sidebar order; all of `available` for an empty query. The start of a word, so "low" doesn't find "allow".
    public static func matching(_ query: String, in available: [SettingsSection] = allCases) -> [SettingsSection] {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return available }
        return available.filter { section in
            let own = ([section.name] + section.keywords).flatMap { $0.lowercased().split(whereSeparator: \.isWhitespace) }
            return words.allSatisfy { word in own.contains { $0.hasPrefix(word) } }
        }
    }
}
