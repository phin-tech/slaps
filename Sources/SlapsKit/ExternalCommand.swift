import Foundation

/// What another app can ask Slaps to do, by a `slaps://` URL or AppleScript.
///
///     slaps://alert?title=Deploy%20done                    an alert now
///     slaps://alert?title=Standup&in=5&link=https://…       in 5 minutes, with a link to open
///     slaps://alert?title=Call%20Mum&at=2026-11-03T18:00:00Z
///     slaps://pause?minutes=30        slaps://pause (an hour)        slaps://resume
///     slaps://dismiss                 slaps://join (the current or next meeting)
public enum ExternalCommand: Equatable, Sendable {
    case alert(ExternalAlert)
    case pause(TimeInterval)
    case resume
    case dismiss
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
            return .alert(try ExternalAlert(title: value("title") ?? "", at: date, link: value("link"),
                                            notes: value("notes"), source: value("source"), now: now))
        case "pause":
            guard let minutes = value("minutes") else { return .pause(3600) }
            guard let m = Double(minutes), m > 0 else { throw Failure("minutes= must be a positive number") }
            return .pause(m * 60)
        case "resume": return .resume
        case "dismiss": return .dismiss
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

/// An alert another app asked for. Checked here, so every way in gets the same rules.
public struct ExternalAlert: Equatable, Sendable {
    public var title: String
    public var at: Date
    /// Only http and https: an alert from anywhere mustn't be able to open other apps' URL schemes.
    public var link: URL?
    public var notes: String?
    /// Who asked, if they said ("Shortcuts", "deploy script"), shown on the alert.
    public var source: String?

    public init(title: String, at: Date, link: String? = nil, notes: String? = nil, source: String? = nil,
                now: Date) throws {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw ExternalCommand.Failure("an alert needs a title") }
        guard at < now.addingTimeInterval(7 * 24 * 3600) else {
            throw ExternalCommand.Failure("an alert can be at most a week ahead")
        }
        self.title = String(title.prefix(200))
        self.at = max(at, now.addingTimeInterval(-60))
        if let link {
            guard let url = URL(string: link), let s = url.scheme?.lowercased(), s == "https" || s == "http",
                  url.host?.isEmpty == false else {
                throw ExternalCommand.Failure("the link must be an http or https URL")
            }
            self.link = url
        }
        self.notes = notes.map { String($0.prefix(500)) }
        self.source = source.map { String($0.prefix(60)) }
    }

    /// As a Meeting, so it's scheduled, snoozed and shown like the rest.
    public func meeting(id: String) -> Meeting {
        Meeting(id: id, kind: .custom, title: title, start: at, end: at.addingTimeInterval(3600),
                calendarTitle: source ?? "Another app", notes: notes, url: link)
    }
}
