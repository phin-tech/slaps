import Foundation

/// A YouTube video to play with an alert, from a link you pasted.
public struct YouTubeVideo: Equatable, Hashable, Sendable {
    /// The 11-character ID.
    public var id: String
    /// Where to start, in seconds, from a link's t= (or start=).
    public var start: Int

    public init(id: String, start: Int = 0) {
        self.id = id
        self.start = start
    }

    /// Reads youtube.com/watch?v=…, youtu.be/…, /shorts/…, /embed/…, /live/… and music.youtube.com links, with or
    /// without the scheme. Nil for anything else.
    public init?(link: String) {
        var text = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "https://" + text }
        guard let url = URLComponents(string: text), let host = url.host?.lowercased(),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        let bare = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        let path = url.path.split(separator: "/").map(String.init)
        let query = url.queryItems ?? []
        func value(_ name: String) -> String? { query.first { $0.name == name }?.value }
        var id: String?
        switch bare {
        case "youtu.be":
            id = path.first
        case "youtube.com", "m.youtube.com", "music.youtube.com", "youtube-nocookie.com":
            if path.first == "watch" {
                id = value("v")
            } else if path.count >= 2, ["shorts", "embed", "live", "v"].contains(path[0]) {
                id = path[1]
            }
        default:
            return nil
        }
        guard let id, Self.isID(id) else { return nil }
        self.id = id
        self.start = (value("t") ?? value("start")).map(Self.seconds) ?? 0
    }

    /// The embedded player, playing at once with its controls and nothing suggested after.
    public var embedURL: URL {
        var c = URLComponents(string: "https://www.youtube.com/embed/\(id)")!
        c.queryItems = [
            URLQueryItem(name: "autoplay", value: "1"),
            URLQueryItem(name: "playsinline", value: "1"),
            URLQueryItem(name: "rel", value: "0"),
        ] + (start > 0 ? [URLQueryItem(name: "start", value: String(start))] : [])
        return c.url!
    }

    /// One of the links that's a video, at random; nil when none is.
    public static func random(from links: [String]) -> YouTubeVideo? {
        links.compactMap(YouTubeVideo.init(link:)).randomElement()
    }

    private static func isID(_ s: String) -> Bool {
        s.count == 11 && s.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }

    /// "90", "90s", "1m30s", "1h2m3s".
    private static func seconds(_ s: String) -> Int {
        if let n = Int(s) { return max(0, n) }
        var total = 0, number = 0
        for ch in s {
            if let d = ch.wholeNumberValue { number = number * 10 + d; continue }
            switch ch {
            case "h": total += number * 3600
            case "m": total += number * 60
            case "s": total += number
            default: return 0
            }
            number = 0
        }
        return total + number
    }
}

/// One line of the video list: a video, or somewhere to pick one from.
public enum VideoSource: Equatable, Hashable, Sendable {
    case video(YouTubeVideo)
    /// youtube.com/playlist?list=…
    case playlist(String)
    /// youtube.com/channel/UC…
    case channel(String)
    /// youtube.com/@name.
    case handle(String)

    /// A video link wins over the playlist it was opened from (watch?v=…&list=…).
    public init?(link: String) {
        if let video = YouTubeVideo(link: link) {
            self = .video(video)
            return
        }
        var text = link.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.contains("://") { text = "https://" + text }
        guard let url = URLComponents(string: text), let host = url.host?.lowercased(),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        let bare = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        guard ["youtube.com", "m.youtube.com", "music.youtube.com"].contains(bare) else { return nil }
        let path = url.path.split(separator: "/").map(String.init)
        let safe = { (s: String) in !s.isEmpty && s.count <= 64 && s.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "-_.".contains($0)) } }
        if path.first == "playlist", let list = url.queryItems?.first(where: { $0.name == "list" })?.value, safe(list) {
            self = .playlist(list)
        } else if path.count >= 2, path[0] == "channel", path[1].hasPrefix("UC"), safe(path[1]) {
            self = .channel(path[1])
        } else if let first = path.first, first.hasPrefix("@"), safe(String(first.dropFirst())) {
            self = .handle(String(first.dropFirst()))
        } else {
            return nil
        }
    }

    /// The page that lists its videos: a playlist's first hundred or so, a channel's newest thirty. (YouTube's
    /// Atom feeds would be tidier, but it stopped serving playlists' and serves channels' only now and then.)
    public var pageURL: URL? {
        switch self {
        case .video: nil
        case .playlist(let id): URL(string: "https://www.youtube.com/playlist?list=\(id)")
        case .channel(let id): URL(string: "https://www.youtube.com/channel/\(id)/videos")
        case .handle(let name): URL(string: "https://www.youtube.com/@\(name)/videos")
        }
    }

    /// The videos a playlist's or channel's page lists, in its current layout or the one before, in order.
    public static func videos(inPage html: String) -> [YouTubeVideo] {
        var seen = Set<String>()
        let ids = matches(of: #""contentId":"([A-Za-z0-9_-]{11})","contentType":"LOCKUP_CONTENT_TYPE_VIDEO""#, in: html)
            + matches(of: #""(?:playlistVideoRenderer|videoRenderer)":\{"videoId":"([A-Za-z0-9_-]{11})""#, in: html)
        return ids.filter { seen.insert($0).inserted }.map { YouTubeVideo(id: $0) }
    }

    private static func matches(of pattern: String, in text: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        return re.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            Range($0.range(at: 1), in: text).map { String(text[$0]) }
        }
    }
}

/// ytroulette.com's random video. Not a published API: what its own page asks for, so it may change or go away.
public enum Roulette {
    public static let categories = ["funny", "music", "gaming", "sports", "trailers", "allyoutube"]

    public static func name(of category: String) -> String {
        category == "allyoutube" ? "Anything (unscreened)" : category.capitalized
    }

    public static func url(category: String, excluding: String? = nil) -> URL {
        var c = URLComponents(string: "https://ytroulette.com/scripts/get_random_video.php")!
        c.queryItems = [URLQueryItem(name: "category", value: category), URLQueryItem(name: "lang", value: "en")]
            + (excluding.map { [URLQueryItem(name: "exclude", value: $0)] } ?? [])
        return c.url!
    }

    /// {"success": true, "video": {"idvideo": "…"}}
    public static func video(in json: Data) -> YouTubeVideo? {
        guard let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              object["success"] as? Bool == true, let video = object["video"] as? [String: Any],
              let id = (video["idvideo"] ?? video["id"]) as? String else { return nil }
        return YouTubeVideo(link: "https://youtu.be/\(id)")
    }
}
