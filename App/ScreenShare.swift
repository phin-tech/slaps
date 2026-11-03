import AppKit
import CoreGraphics

/// Guesses whether you're sharing your screen in a call, so an alert doesn't go up in front of everyone watching.
///
/// macOS has no API for "the screen is being shared", and other apps' window titles need screen-recording permission.
/// What every app can see is who owns each window, its level and its size. Zoom, Teams, Webex and Slack draw a coloured
/// border around a shared screen: a window above ordinary ones, the size of the whole display. That is what this
/// looks for. A screen shared from a browser tab (Google Meet) draws no such border, so it is not detected; use Pause
/// for those.
enum ScreenShare {
    /// Owner names as the window server reports them.
    static let apps: Set<String> = [
        "zoom.us", "Microsoft Teams", "Microsoft Teams (work or school)", "Microsoft Teams classic", "Webex",
        "Cisco Webex Meetings", "Slack", "Around", "Tuple", "Discord", "Pop", "Whereby",
    ]

    static func isSharing() -> Bool {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                       kCGNullWindowID) as? [[String: Any]] else { return false }
        let displays = NSScreen.screens.map(\.frame.size)
        return windows.contains { w in
            guard let owner = w[kCGWindowOwnerName as String] as? String, apps.contains(owner),
                  let layer = w[kCGWindowLayer as String] as? Int, layer > 0,
                  let bounds = w[kCGWindowBounds as String],
                  let rect = CGRect(dictionaryRepresentation: bounds as! CFDictionary) else { return false }
            return displays.contains { abs($0.width - rect.width) < 8 && abs($0.height - rect.height) < 8 }
        }
    }
}
