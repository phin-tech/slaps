import Foundation
import SlapsKit

/// Where alert videos come from.
enum VideoMode: String, CaseIterable, Identifiable {
    /// The links in Settings: videos, playlists and channels.
    case links
    /// A random one from ytroulette.com.
    case roulette

    var id: String { rawValue }
    var name: String {
        switch self {
        case .links: "My links"
        case .roulette: "ytroulette.com"
        }
    }
}

/// Picks the next alert's video ahead of time, so an alert never waits on the network: playlists and channels are
/// read from their pages (and kept for a few hours), and ytroulette is asked in advance. When nothing is ready, a
/// video link from the list plays instead, or else the alert sound.
@MainActor
final class VideoPicker {
    struct Settings: Equatable {
        var links: [String]
        var mode: VideoMode
        var category: String
    }

    private var ready: (video: YouTubeVideo, for: Settings)?
    private var refilling: Task<Void, Never>?
    /// The videos each playlist or channel listed, and when.
    private var pages: [VideoSource: (videos: [YouTubeVideo], read: Date)] = [:]
    private var last: YouTubeVideo?

    private static let pageLife: TimeInterval = 6 * 3600
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        return URLSession(configuration: config)
    }()

    /// The video for an alert going up now, then starts on the next one.
    func take(_ settings: Settings) -> YouTubeVideo? {
        let pick = ready.flatMap { $0.for == settings ? $0.video : nil } ?? directPick(settings.links)
        ready = nil
        last = pick
        refill(settings)
        return pick
    }

    /// Gets the next video ready (again, if the settings changed).
    func refill(_ settings: Settings) {
        refilling?.cancel()
        refilling = Task {
            guard let video = await next(settings), !Task.isCancelled else { return }
            ready = (video, settings)
        }
    }

    /// Which of the links are something to pick from.
    static func sources(_ links: [String]) -> [VideoSource] { links.compactMap(VideoSource.init(link:)) }

    private func directPick(_ links: [String]) -> YouTubeVideo? {
        Self.sources(links).compactMap { if case .video(let v) = $0 { v } else { nil } }.randomElement()
    }

    private func next(_ settings: Settings) async -> YouTubeVideo? {
        switch settings.mode {
        case .roulette:
            if let video = await roulette(settings.category) { return video }
            return await fromLinks(settings.links)
        case .links:
            return await fromLinks(settings.links)
        }
    }

    /// Every video the links lead to, one at random, avoiding the one just played when there's a choice.
    private func fromLinks(_ links: [String]) async -> YouTubeVideo? {
        var pool: [YouTubeVideo] = []
        for source in Self.sources(links) {
            if case .video(let v) = source { pool.append(v) } else { pool += await videos(in: source) }
        }
        let fresh = pool.filter { $0 != last }
        return (fresh.isEmpty ? pool : fresh).randomElement()
    }

    private func videos(in source: VideoSource) async -> [YouTubeVideo] {
        if let cached = pages[source], Date().timeIntervalSince(cached.read) < Self.pageLife { return cached.videos }
        guard let url = source.pageURL, let html = await get(url) else { return pages[source]?.videos ?? [] }
        let videos = VideoSource.videos(inPage: html)
        guard !videos.isEmpty else { return pages[source]?.videos ?? [] }   // a page it can't read keeps the last
        pages[source] = (videos, Date())
        return videos
    }

    private func roulette(_ category: String) async -> YouTubeVideo? {
        var request = URLRequest(url: Roulette.url(category: category, excluding: last?.id))
        request.setValue("https://ytroulette.com/", forHTTPHeaderField: "Referer")
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return Roulette.video(in: data)
    }

    private func get(_ url: URL) async -> String? {
        var request = URLRequest(url: url)
        request.setValue("en-US,en", forHTTPHeaderField: "Accept-Language")
        // YouTube's pages differ for clients it doesn't recognise; this is Safari's.
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) "
            + "Version/18.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
