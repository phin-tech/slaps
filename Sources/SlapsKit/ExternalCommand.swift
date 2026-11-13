import Foundation

/// What another app can ask Slaps to do, by a `slaps://` URL or AppleScript.
///
///     slaps://alert?title=Deploy%20done                    an alert now
///     slaps://alert?title=Standup&in=5&link=https://…       in 5 minutes, with a link to open
///     slaps://alert?title=Call%20Mum&at=2026-11-03T18:00:00Z
///     slaps://alert?title=Rotate%20the%20key%3F&id=q3&style=banner&actions=Yes,No
///         &callback=boiler-room%3A%2F%2Fanswer%3Fquestion%3D3%26answer%3D%7Baction%7D
///         (the callback encoded as one value: boiler-room://answer?question=3&answer={action})
///     slaps://pause?minutes=30        slaps://pause (an hour)        slaps://resume
///     slaps://dismiss                 slaps://dismiss?id=q3 (only that one, up or not)
///     slaps://join (the current or next meeting)
public enum ExternalCommand: Equatable, Sendable {
    case alert(ExternalAlert)
    case pause(TimeInterval)
    case resume
    case dismiss
    /// Takes back the alert another app sent with this `id`, whether it's up or still to come.
    case withdraw(String)
    case join

    public struct Failure: Error, Equatable, CustomStringConvertible {
        public var description: String
        public init(_ description: String) { self.description = description }
    }

    public static let scheme = "slaps"

    /// Reads a `slaps://` URL. Times are relative to `now`.
    public static func parse(_ url: URL, now: Date) throws -> ExternalCommand {
        guard url.scheme?.lowercased() == scheme else { throw Failure("not a slaps:// URL") }
        // slaps://alert?… has the command as the host; slaps:alert?… as the path.
        let name = (url.host ?? url.path).trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ key: String) -> String? {
            items.first { $0.name.lowercased() == key }?.value.flatMap { $0.isEmpty ? nil : $0 }
        }
        switch name {
        case "alert":
            var date = now
            if let at = value("at") {
                guard let d = parseDate(at) else { throw Failure("at= must be an ISO 8601 time, like 2026-11-03T18:00:00Z") }
                date = d
            } else if let minutes = value("in") {
                guard let m = Double(minutes), m >= 0 else { throw Failure("in= must be a number of minutes") }
                date = now.addingTimeInterval(m * 60)
            }
            let style = try value("style").map { name -> AlertStyle in
                guard let style = AlertStyle(external: name) else {
                    throw Failure("style= is fullscreen, banner, top, bottom or side")
                }
                return style
            }
            let actions = value("actions").map {
                $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            } ?? []
            return .alert(try ExternalAlert(title: value("title") ?? "", at: date, link: value("link"),
                                            notes: value("notes"), source: value("source"), key: value("id"),
                                            style: style, actions: actions, callback: value("callback"), now: now))
        case "pause":
            guard let minutes = value("minutes") else { return .pause(3600) }
            guard let m = Double(minutes), m > 0 else { throw Failure("minutes= must be a positive number") }
            return .pause(m * 60)
        case "resume": return .resume
        case "dismiss":
            guard let id = value("id") else { return .dismiss }
            return .withdraw(try ExternalAlert.checkedKey(id))
        case "join": return .join
        default:
            throw Failure("unknown command '\(name)' (alert, pause, resume, dismiss, join)")
        }
    }

    private static func parseDate(_ s: String) -> Date? {
        let full = ISO8601DateFormatter()
        if let d = full.date(from: s) { return d }
        full.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = full.date(from: s) { return d }
        // A time without a zone is local time.
        let local = DateFormatter()
        local.locale = Locale(identifier: "en_US_POSIX")
        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm"] {
            local.dateFormat = format
            if let d = local.date(from: s) { return d }
        }
        return nil
    }
}

/// A button on an alert from another app: its words, and the URL it opens, which answers that app.
public struct ExternalAction: Hashable, Sendable {
    public var title: String
    public var url: URL

    public init(title: String, url: URL) {
        self.title = title
        self.url = url
    }
}

extension AlertStyle {
    /// As another app names it: `fullscreen`, `banner` (the top), `top`, `bottom` or `side` (a card).
    public init?(external name: String) {
        switch name.lowercased() {
        case "fullscreen", "full-screen", "full": self = .fullScreen
        case "banner", "top": self = .top
        case "bottom": self = .bottom
        case "side", "card": self = .side
        default: return nil
        }
    }
}

/// An alert another app asked for. Checked here, so every way in gets the same rules.
public struct ExternalAlert: Equatable, Sendable {
    /// Apps whose URLs an alert's link and buttons may open, by scheme, with the name a button gives them. Anyone can
    /// send an alert, so its buttons can't open just any app's URL; an app is added here when it answers alerts.
    public static let apps: [String: String] = ["boiler-room": "Boiler Room"]
    /// At most this many answer buttons, which fit beside Snooze and Dismiss.
    public static let mostActions = 3

    /// Which app a URL opens, by the name its button gives it, if it's one of [`apps`].
    public static func app(for url: URL) -> String? {
        url.scheme.flatMap { apps[$0.lowercased()] }
    }

    /// A URL an alert may open: a web page, or one of [`apps`].
    static func allowed(_ text: String, _ what: String) throws -> URL {
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased() else {
            throw ExternalCommand.Failure("the \(what) isn't a URL")
        }
        if scheme == "https" || scheme == "http" {
            guard url.host?.isEmpty == false else { throw ExternalCommand.Failure("the \(what) has no site") }
            return url
        }
        guard apps[scheme] != nil else {
            let names = (["http", "https"] + apps.keys.sorted()).joined(separator: ", ")
            throw ExternalCommand.Failure("the \(what) must be one of \(names)")
        }
        return url
    }

    /// An `id=` as given, or why it can't be one: letters, digits, `.`, `_` and `-`, up to 64.
    public static func checkedKey(_ key: String) throws -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        guard !key.isEmpty, key.count <= 64, key.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            throw ExternalCommand.Failure("id= is letters, digits, . _ and -, up to 64")
        }
        return key
    }

    /// The `Meeting.id` of the alert sent with `id=key`.
    public static func meetingID(key: String) -> String { "custom-\(key)" }

    public var title: String
    public var at: Date
    /// Only http and https: an alert from anywhere mustn't be able to open other apps' URL schemes.
    public var link: URL?
    public var notes: String?
    /// Who asked, if they said ("Shortcuts", "deploy script"), shown on the alert.
    public var source: String?
    /// Its sender's name for it: another with the same takes its place, and `dismiss?id=` takes it back.
    public var key: String?
    /// How much of the screen it takes, over the setting.
    public var style: AlertStyle?
    public var actions: [ExternalAction] = []

    /// `actions` are the buttons' words; `callback` the URL each opens, with `{action}` standing for its words.
    public init(title: String, at: Date, link: String? = nil, notes: String? = nil, source: String? = nil,
                key: String? = nil, style: AlertStyle? = nil, actions: [String] = [], callback: String? = nil,
                now: Date) throws {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw ExternalCommand.Failure("an alert needs a title") }
        guard at < now.addingTimeInterval(7 * 24 * 3600) else {
            throw ExternalCommand.Failure("an alert can be at most a week ahead")
        }
        self.title = String(title.prefix(200))
        self.at = max(at, now.addingTimeInterval(-60))
        if let link { self.link = try Self.allowed(link, "link") }
        self.notes = notes.map { String($0.prefix(500)) }
        self.source = source.map { String($0.prefix(60)) }
        self.key = try key.map(Self.checkedKey)
        self.style = style
        let words = actions.map { String($0.prefix(30)) }.filter { !$0.isEmpty }
        guard words.count <= Self.mostActions else {
            throw ExternalCommand.Failure("an alert has at most \(Self.mostActions) actions")
        }
        if !words.isEmpty {
            guard let callback else { throw ExternalCommand.Failure("actions= needs a callback= URL to open") }
            guard callback.contains("{action}") else {
                throw ExternalCommand.Failure("callback= has {action} where the chosen action goes")
            }
            self.actions = try words.map { word in
                let filled = word.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? word
                return ExternalAction(title: word,
                                      url: try Self.allowed(callback.replacingOccurrences(of: "{action}", with: filled),
                                                            "callback"))
            }
        }
    }

    /// As a Meeting, so it's scheduled, snoozed and shown like the rest.
    public func meeting(id: String) -> Meeting {
        Meeting(id: id, kind: .custom, title: title, start: at, end: at.addingTimeInterval(3600),
                calendarTitle: source ?? "Another app", notes: notes, url: link, style: style, actions: actions)
    }
}
