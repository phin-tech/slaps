import SlapsKit
import SwiftUI
import WebKit

/// A YouTube video playing in the alert, with sound, from the moment it's up. Goes when the alert does.
struct AlertVideoView: NSViewRepresentable {
    let video: YouTubeVideo

    /// The one on screen, for the debug driver to ask whether it's playing.
    @MainActor static weak var current: WKWebView?

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []   // an alarm that waits for a click isn't one
        config.websiteDataStore = .nonPersistent()             // nothing of YouTube's kept between alerts
        let web = WKWebView(frame: .zero, configuration: config)
        web.setValue(false, forKey: "drawsBackground")
        load(video, in: web)
        Self.current = web
        return web
    }

    func updateNSView(_ web: WKWebView, context: Context) {
        if web.url?.path.hasSuffix(video.id) != true { load(video, in: web) }
    }

    static func dismantleNSView(_ web: WKWebView, coordinator: ()) {
        web.pauseAllMediaPlayback()
        web.loadHTMLString("", baseURL: nil)
    }

    private func load(_ video: YouTubeVideo, in web: WKWebView) {
        var request = URLRequest(url: video.embedURL)
        // YouTube's player refuses to play (error 153) for a page with no referrer, which an app's request is.
        request.setValue("https://github.com/phin-tech/slaps", forHTTPHeaderField: "Referer")
        web.load(request)
    }
}
