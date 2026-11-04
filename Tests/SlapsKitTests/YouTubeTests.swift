import Foundation
import Testing
@testable import SlapsKit

struct YouTubeTests {
    @Test(arguments: [
        "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
        "youtube.com/watch?v=dQw4w9WgXcQ&list=PL123",
        "https://m.youtube.com/watch?feature=share&v=dQw4w9WgXcQ",
        "https://youtu.be/dQw4w9WgXcQ",
        "https://youtu.be/dQw4w9WgXcQ?si=abc",
        "https://www.youtube.com/shorts/dQw4w9WgXcQ",
        "https://www.youtube.com/embed/dQw4w9WgXcQ",
        "https://www.youtube.com/live/dQw4w9WgXcQ",
        "https://music.youtube.com/watch?v=dQw4w9WgXcQ",
        "  https://youtu.be/dQw4w9WgXcQ  ",
    ])
    func readsLinks(_ link: String) {
        #expect(YouTubeVideo(link: link)?.id == "dQw4w9WgXcQ")
    }

    @Test(arguments: [
        "", "not a link", "https://vimeo.com/123456", "https://www.youtube.com/@channel",
        "https://www.youtube.com/watch?v=short", "https://youtu.be/", "javascript:alert(1)",
        "https://evil.example/watch?v=dQw4w9WgXcQ", "https://youtube.com.evil.example/watch?v=dQw4w9WgXcQ",
    ])
    func rejectsTheRest(_ link: String) {
        #expect(YouTubeVideo(link: link) == nil)
    }

    @Test func readsTheStartTime() {
        #expect(YouTubeVideo(link: "https://youtu.be/dQw4w9WgXcQ?t=43")?.start == 43)
        #expect(YouTubeVideo(link: "https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=1m30s")?.start == 90)
        #expect(YouTubeVideo(link: "https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=1h2m3s")?.start == 3723)
        #expect(YouTubeVideo(link: "https://www.youtube.com/watch?v=dQw4w9WgXcQ")?.start == 0)
    }

    @Test func embedsToAutoplay() {
        let url = YouTubeVideo(id: "dQw4w9WgXcQ", start: 90).embedURL.absoluteString
        #expect(url.hasPrefix("https://www.youtube.com/embed/dQw4w9WgXcQ?"))
        #expect(url.contains("autoplay=1") && url.contains("start=90"))
        #expect(!YouTubeVideo(id: "dQw4w9WgXcQ").embedURL.absoluteString.contains("start="))
    }

    @Test func picksOnlyFromVideos() {
        #expect(YouTubeVideo.random(from: []) == nil)
        #expect(YouTubeVideo.random(from: ["nope", ""]) == nil)
        #expect(YouTubeVideo.random(from: ["nope", "https://youtu.be/dQw4w9WgXcQ"])?.id == "dQw4w9WgXcQ")
    }
}

struct VideoSourceTests {
    @Test func readsEachKind() {
        #expect(VideoSource(link: "https://youtu.be/dQw4w9WgXcQ") == .video(YouTubeVideo(id: "dQw4w9WgXcQ")))
        #expect(VideoSource(link: "https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=PLabc") == .video(YouTubeVideo(id: "dQw4w9WgXcQ")))
        #expect(VideoSource(link: "https://www.youtube.com/playlist?list=PLFgquLnL59alCl_2TQvOiD5Vgm1hCaGSI") == .playlist("PLFgquLnL59alCl_2TQvOiD5Vgm1hCaGSI"))
        #expect(VideoSource(link: "youtube.com/channel/UCuAXFkgsw1L7xaCfnd5JJOw") == .channel("UCuAXFkgsw1L7xaCfnd5JJOw"))
        #expect(VideoSource(link: "https://www.youtube.com/@veritasium/videos") == .handle("veritasium"))
        #expect(VideoSource(link: "https://www.youtube.com/playlist?list=a/b") == nil)
        #expect(VideoSource(link: "https://example.com/@someone") == nil)
        #expect(VideoSource(link: "https://www.youtube.com/results?search_query=cats") == nil)
    }

    @Test func pages() {
        #expect(VideoSource.playlist("PL1").pageURL?.absoluteString == "https://www.youtube.com/playlist?list=PL1")
        #expect(VideoSource.channel("UC1").pageURL?.absoluteString == "https://www.youtube.com/channel/UC1/videos")
        #expect(VideoSource.handle("veritasium").pageURL?.absoluteString == "https://www.youtube.com/@veritasium/videos")
        #expect(VideoSource.video(YouTubeVideo(id: "dQw4w9WgXcQ")).pageURL == nil)
        let page = #"{"contentId":"FUHkTs-Ipfg","contentType":"LOCKUP_CONTENT_TYPE_VIDEO"},"#
            + #"{"contentId":"PLxyz123456","contentType":"LOCKUP_CONTENT_TYPE_PLAYLIST"},"#
            + #"{"playlistVideoRenderer":{"videoId":"pTn6Ewhb27k"}},{"videoRenderer":{"videoId":"bHIhgxav9LY"}},"#
            + #"{"contentId":"FUHkTs-Ipfg","contentType":"LOCKUP_CONTENT_TYPE_VIDEO"}"#
        #expect(VideoSource.videos(inPage: page).map(\.id) == ["FUHkTs-Ipfg", "pTn6Ewhb27k", "bHIhgxav9LY"])
        #expect(VideoSource.videos(inPage: "<html>no videos</html>").isEmpty)
    }

    @Test func readsRoulette() {
        let ok = Data(#"{"success":true,"video":{"idvideo":"qJgnwGVxPrg","title":"x"}}"#.utf8)
        #expect(Roulette.video(in: ok)?.id == "qJgnwGVxPrg")
        #expect(Roulette.video(in: Data(#"{"success":false}"#.utf8)) == nil)
        #expect(Roulette.video(in: Data(#"{"success":true,"video":{"idvideo":"../../x"}}"#.utf8)) == nil)
        #expect(Roulette.url(category: "funny", excluding: "abc").absoluteString.contains("category=funny"))
    }
}
