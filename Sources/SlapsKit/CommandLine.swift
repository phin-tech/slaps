import Foundation

/// `slaps` on the command line: each command is a `slaps://` URL, checked here with the same rules the app applies
/// (`ExternalCommand.parse`), so a mistake is said in the terminal rather than only in the app's log.
///
///     slaps alert "Deploy done" --in 5 --link https://ci.example.com --from CI
///     slaps alert "Rotate the key?" --id q3 --style side --action Yes --action No \
///         --callback 'boiler-room://answer?question=3&answer={action}'
///     slaps tab "Reply to Bob" --deadline 30 --color teal --from Mail --id bob
///     slaps dismiss [--id q3]      slaps pause [--minutes 30]      slaps resume      slaps join
public enum SlapsCommandLine {
    /// The words the app's binary answers as a command line rather than opening the app.
    public static let commands: Set<String> = ["alert", "tab", "dismiss", "pause", "resume", "join", "help", "--help", "-h"]

    public static let help = """
        slaps: put up a Slaps alert or tab, or pause, resume or dismiss them, from a terminal or a script.

        Usage:
          slaps alert <title> [--in <minutes> | --at <time>] [--link <url>] [--notes <text>] [--from <who>]
                              [--id <id>] [--style fullscreen|banner|top|bottom|side]
                              [--action <words>]... [--callback <url with {action}>]
          slaps tab <title> [--deadline <minutes> | <time> | never] [--color <name or #RRGGBB>]
                            [--position top|middle|bottom] [--group <name>]
                            [--icon <SF Symbol name or app bundle id>]
                            [--link <url>] [--notes <text>] [--from <who>] [--id <id>]
                            [--action <words>]... [--callback <url with {action}>]
          slaps dismiss [--id <id>]     the alert on screen, or the alert or tab sent with that id
          slaps pause [--minutes <n>]   an hour unless told
          slaps resume
          slaps join                    the alert's call, or a meeting under way or within 10 minutes

        --at takes ISO 8601 (2026-11-03T18:00, local, or with a zone). An alert sent again with the same --id takes
        the old one's place, and a tab or alert shares its --id with the other. A tab stays on the edge of the
        screen until dismissed; past its --deadline (Settings' default, none unless set) it goes up full screen.
        Tabs from one --from with the same --group stack up as one; --position picks the place on the edge.
        Colours: red, orange, yellow, green, mint, teal, cyan, blue, indigo, purple, pink, brown, gray. Each --action is a button that opens --callback with its words in place of {action}.
        Slaps has to allow other apps (Settings › General › Allow Other Apps).
        """

    public struct Failure: Error, Equatable, CustomStringConvertible {
        public var description: String
        public init(_ description: String) { self.description = description }
    }

    /// The `slaps://` URL `arguments` (without the program's name) ask for, checked as the app would; nil for help.
    public static func url(for arguments: [String], now: Date = Date()) throws -> URL? {
        guard let command = arguments.first?.lowercased() else { throw Failure("say what to do; slaps help lists it") }
        var rest = Array(arguments.dropFirst())
        var items: [URLQueryItem] = []
        var actions: [String] = []

        /// Takes `--name value` pairs, by the URL key each becomes; anything else is a mistake.
        func options(_ known: [String: String]) throws {
            while let flag = rest.first {
                rest.removeFirst()
                guard let key = known[flag] else { throw Failure("\(command) doesn't take \(flag)") }
                guard let value = rest.first, !value.hasPrefix("--") else { throw Failure("\(flag) needs a value") }
                rest.removeFirst()
                if key == "actions" { actions.append(value) } else { items.append(URLQueryItem(name: key, value: value)) }
            }
        }

        switch command {
        case "help", "--help", "-h":
            return nil
        case "alert", "tab":
            guard let title = rest.first, !title.hasPrefix("--") else { throw Failure("\(command) needs a title") }
            rest.removeFirst()
            items.append(URLQueryItem(name: "title", value: title))
            var known = ["--link": "link", "--notes": "notes", "--from": "source", "--id": "id",
                         "--action": "actions", "--callback": "callback"]
            if command == "alert" {
                known.merge(["--in": "in", "--at": "at", "--style": "style"]) { a, _ in a }
            } else {
                known.merge(["--deadline": "deadline", "--color": "color", "--colour": "color",
                             "--position": "position", "--group": "group", "--icon": "icon"]) { a, _ in a }
            }
            try options(known)
            if !items.contains(where: { $0.name == "source" }) {
                items.append(URLQueryItem(name: "source", value: "Terminal"))
            }
            if actions.contains(where: { $0.contains(",") }) {
                throw Failure("an --action can't have a comma in it")
            }
            if !actions.isEmpty { items.append(URLQueryItem(name: "actions", value: actions.joined(separator: ","))) }
        case "dismiss":
            try options(["--id": "id"])
        case "pause":
            try options(["--minutes": "minutes"])
        case "resume", "join":
            try options([:])
        default:
            throw Failure("there's no command \(command); slaps help lists them")
        }
        var components = URLComponents()
        components.scheme = ExternalCommand.scheme
        components.host = command
        components.queryItems = items.isEmpty ? nil : items
        // Every value is encoded whole, `&` and `=` too, so a callback URL stays one value.
        components.percentEncodedQuery = items.isEmpty ? nil : items.map { item in
            "\(item.name)=\(item.value?.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")"
        }.joined(separator: "&")
        guard let url = components.url else { throw Failure("that can't be made into a slaps:// URL") }
        do {
            _ = try ExternalCommand.parse(url, now: now)
        } catch let failure as ExternalCommand.Failure {
            throw Failure(failure.description)
        }
        return url
    }
}
