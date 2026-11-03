import Foundation

/// A video-call link found in an event, and the service it belongs to.
public struct MeetingLink: Hashable, Sendable {
    public var service: String
    public var url: URL

    public init(service: String, url: URL) {
        self.service = service
        self.url = url
    }

    /// The services recognised, most specific first. Each pattern matches a whole join URL; anything that ends a URL
    /// in an invitation's text (whitespace, quotes, angle brackets) is outside `[^\s<>"']`.
    static let services: [(name: String, pattern: String)] = [
        ("Zoom", #"https://(?:[\w-]+\.)?zoom(?:gov)?\.(?:us|com)/(?:j|my|w|s|wc/join)/[^\s<>"']+"#),
        ("Google Meet", #"https://meet\.google\.com/[a-z]{3,}-[a-z]{4,}-[a-z]{3,}(?:\?[^\s<>"']*)?"#),
        ("Microsoft Teams", #"https://teams\.(?:microsoft|live)\.com/(?:l/meetup-join|meet|v2/\?meetingjoin)[^\s<>"']+"#),
        ("Webex", #"https://(?:[\w-]+\.)?webex\.com/(?:meet|join|[\w-]+/j\.php|wbxmjs/joinservice)[^\s<>"']*"#),
        ("FaceTime", #"https://facetime\.apple\.com/join[^\s<>"']+"#),
        ("Slack Huddle", #"https://app\.slack\.com/huddle/[^\s<>"']+"#),
        ("Whereby", #"https://(?:[\w-]+\.)?whereby\.com/[^\s<>"']+"#),
        ("Jitsi", #"https://meet\.jit\.si/[^\s<>"']+"#),
        ("Amazon Chime", #"https://chime\.aws/\d+"#),
        ("GoTo Meeting", #"https://(?:global\.gotomeeting\.com/join|meet\.goto\.com)/[^\s<>"']+"#),
        ("Around", #"https://(?:meet\.)?around\.co/[^\s<>"']+"#),
        ("Discord", #"https://discord\.(?:gg|com/channels)/[^\s<>"']+"#),
        ("Tuple", #"https://tuple\.app/c/[^\s<>"']+"#),
        ("Gather", #"https://app\.gather\.town/app/[^\s<>"']+"#),
        ("Riverside", #"https://riverside\.fm/studio/[^\s<>"']+"#),
        ("Skype", #"https://join\.skype\.com/[^\s<>"']+"#),
        ("Pop", #"https://pop\.com/j/[^\s<>"']+"#),
        ("Zoho Meeting", #"https://meeting\.zoho\.(?:com|eu|in)/[^\s<>"']+"#),
        ("BlueJeans", #"https://(?:[\w-]+\.)?bluejeans\.com/\d+[^\s<>"']*"#),
    ]

    private static let compiled: [(name: String, regex: NSRegularExpression)] = services.map {
        ($0.name, try! NSRegularExpression(pattern: $0.pattern, options: [.caseInsensitive]))
    }

    /// The first call link in `text`: the one that comes first in the text, whatever the service.
    public static func find(in text: String) -> MeetingLink? {
        let range = NSRange(text.startIndex..., in: text)
        var best: (location: Int, link: MeetingLink)?
        for (name, regex) in compiled {
            guard let match = regex.firstMatch(in: text, range: range),
                  let r = Range(match.range, in: text) else { continue }
            if let best, best.location <= match.range.location { continue }
            guard let url = URL(string: trimmed(String(text[r]))) else { continue }
            best = (match.range.location, MeetingLink(service: name, url: url))
        }
        return best?.link
    }

    /// The first call link in the first of `fields` that has one.
    public static func first(in fields: [String?]) -> MeetingLink? {
        for case let field? in fields {
            if let link = find(in: field) { return link }
        }
        return nil
    }

    /// Prose punctuation that follows a link without being part of it ("join at https://…/123.").
    private static func trimmed(_ s: String) -> String {
        var s = Substring(s)
        while let last = s.last, ".,;:!?)]}".contains(last) {
            // Keep a closing parenthesis that closes one in the URL.
            if last == ")" && s.filter({ $0 == "(" }).count >= s.filter({ $0 == ")" }).count { break }
            s = s.dropLast()
        }
        return String(s)
    }
}
