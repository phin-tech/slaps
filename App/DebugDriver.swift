#if DEBUG
import AppKit
import SlapsKit

/// Drives a Debug build over a Unix socket so an agent can look at the real app without screen-recording or
/// accessibility permissions: the app renders its own windows to PNGs and chooses menu items itself.
/// `just debug-app` launches a build with `DEBUG_SOCKET` set; the client is `scripts/debug.py`.
///
/// One JSON request per line, one JSON reply per line. A request is `{"command": …}` plus the command's arguments;
/// a reply is `{"text": …}`, or `{"error": …}` when the command failed.
///
///     {"command": "ping"}
///     {"command": "windows"}                                  visible windows, front first: index, title, frame
///     {"command": "snapshot", "path": "/tmp/out.png", "window": 0}   (or "window": "a title")
///     {"command": "menu", "path": ["File", "New Window"]}     choose a main-menu item (or list a menu's items)
///     {"command": "alert", "reminder": false}                 put up a test alert (of a reminder)
///     {"command": "hotkeys"}                                  how many global shortcuts are registered
///     {"command": "sharing"}                                  whether screen sharing is detected
///     {"command": "dismiss"}                                  dismiss whatever alert is up
///     {"command": "quit"}
///
/// `"wait": seconds` in any request pauses that long before running it, so the app can settle after the last one.
@MainActor
final class DebugDriver {
    static let shared = DebugDriver()

    /// Listens on `DEBUG_SOCKET` if the app was launched with it set; otherwise does nothing.
    static func startIfAsked() {
        guard let path = ProcessInfo.processInfo.environment["DEBUG_SOCKET"], !path.isEmpty else { return }
        do {
            let fd = try DebugSocket.listen(at: path)
            Thread.detachNewThread { DebugSocket.serve(fd) }
        } catch {
            NSLog("Slaps debug driver: \(error)")
        }
    }

    /// Runs one request line and returns the reply line. The socket thread calls this on the main thread.
    func handle(_ line: Data) -> Data {
        let reply: [String: Any]
        do {
            guard let request = try JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let command = request["command"] as? String else { throw DebugError("a request is {\"command\": …}") }
            reply = ["text": try run(command, request)]
        } catch {
            reply = ["error": (error as? DebugError)?.message ?? "\(error)"]
        }
        return (try? JSONSerialization.data(withJSONObject: reply)) ?? Data("{}".utf8)
    }

    private func run(_ command: String, _ request: [String: Any]) throws -> String {
        switch command {
        case "ping":
            return "pong"
        case "windows":
            let lines = visibleWindows().enumerated().map { i, w in
                let f = w.frame
                return "\(i) \"\(w.title)\" \(Int(f.minX)),\(Int(f.minY)) \(Int(f.width))x\(Int(f.height))\(w.isKeyWindow ? " (key)" : "")"
            }
            return lines.isEmpty ? "no windows" : lines.joined(separator: "\n")
        case "snapshot":
            guard let path = request["path"] as? String else { throw DebugError("snapshot needs a path") }
            return try snapshot(window(request["window"]), to: URL(fileURLWithPath: path))
        case "menu":
            return try menu(request["path"] as? [String] ?? [])
        case "alert":
            AppModel.shared.testAlert(reminder: request["reminder"] as? Bool ?? false)
            return "test alert up"
        case "hotkeys":
            return "\(AppModel.shared.hotKeysRegistered) of \(HotKeys.Action.allCases.count) shortcuts registered"
        case "popover":
            // Clicks Slaps's menu bar item, as you would, to open (or close) the popover.
            for window in NSApp.windows where String(describing: type(of: window)).contains("StatusBar") {
                if let button = Self.firstButton(in: window.contentView) {
                    button.performClick(nil)
                    return "clicked the menu bar item"
                }
            }
            throw DebugError("no menu bar item")
        case "style":
            guard let name = request["style"] as? String, let style = AlertStyle(rawValue: name) else {
                throw DebugError("style is one of \(AlertStyle.allCases.map(\.rawValue))")
            }
            AppModel.shared.alertStyle = style
            return "alert style \(name)"
        case "theme":
            guard let name = request["theme"] as? String, let theme = Theme(rawValue: name) else {
                throw DebugError("theme is one of \(Theme.allCases.map(\.rawValue))")
            }
            AppModel.shared.theme = theme
            return "theme \(name)"
        case "onboarding":
            OnboardingController.shared.show()
            return "welcome window up"
        case "state":
            let m = AppModel.shared
            return "alerting: \(m.alerting.map(\.title)); upcoming: \(m.upcoming.count); paused: \(m.isPaused)"
        case "battery":
            // A made-up reading: battery <percent> [power], or battery real to go back to the real one.
            if request["real"] as? Bool == true {
                AppModel.shared.simulatedBattery = nil
                return "the real battery: \(BatteryMonitor.read().map { "\($0.percent)%, \($0.onPower ? "on power" : "on battery")" } ?? "none")"
            }
            guard let percent = request["percent"] as? Int else { throw DebugError("battery needs a percentage") }
            if request["enable"] as? Bool == true { AppModel.shared.batteryAlerts = true }
            AppModel.shared.simulatedBattery = BatteryReading(percent: percent, onPower: request["power"] as? Bool ?? false)
            return "battery \(percent)%\(request["power"] as? Bool == true ? " on power" : "")"
        case "sharing":
            return ScreenShare.isSharing() ? "sharing detected" : "not sharing"
        case "dismiss":
            AppModel.shared.dismiss(AppModel.shared.alerting)
            return "dismissed"
        case "quit":
            // Gone first, so a client started after this waits for the next copy instead of this one; the app
            // quits once this reply is on its way.
            if let path = ProcessInfo.processInfo.environment["DEBUG_SOCKET"] { unlink(path) }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(200))
                NSApp.terminate(nil)
            }
            return "quitting"
        default:
            throw DebugError("unknown command '\(command)' (ping, windows, snapshot, menu, alert, dismiss, popover, style, theme, onboarding, hotkeys, battery, sharing, state, quit)")
        }
    }

    private static func firstButton(in view: NSView?) -> NSButton? {
        guard let view else { return nil }
        if let button = view as? NSButton { return button }
        for sub in view.subviews { if let b = firstButton(in: sub) { return b } }
        return nil
    }

    private struct DebugError: Error {
        var message: String
        init(_ message: String) { self.message = message }
    }

    // MARK: Windows

    /// Visible windows, front to back; their index here is what `snapshot` takes.
    private func visibleWindows() -> [NSWindow] {
        // Not `orderedWindows`, which leaves out panels like the alert: the highest level first, then front to back.
        NSApp.windows.filter { $0.isVisible && $0.contentView != nil }
            .sorted { ($0.level.rawValue, -$0.orderedIndex) > ($1.level.rawValue, -$1.orderedIndex) }
    }

    /// A window by its index in `windows` (default 0), or by its title.
    private func window(_ which: Any?) throws -> NSWindow {
        let windows = visibleWindows()
        if let title = which as? String {
            guard let w = windows.first(where: { $0.title == title }) else {
                throw DebugError("no window titled '\(title)' (\(windows.map(\.title)))")
            }
            return w
        }
        let index = which as? Int ?? 0
        guard windows.indices.contains(index) else { throw DebugError("no window \(index) (\(windows.count) visible)") }
        return windows[index]
    }

    /// Draws the window into a bitmap the way printing does, so it needs no screen-recording permission and works
    /// while the app is in the background. The content view's superview is the frame view, so the title bar is in it.
    private func snapshot(_ window: NSWindow, to url: URL) throws -> String {
        guard let content = window.contentView else { throw DebugError("the window has no content") }
        let view = content.superview ?? content
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        // The window server's picture of the window, as it is on screen; an app may take its own windows' without
        // screen-recording permission. Failing that, the view drawn the way printing does, which leaves out some of
        // SwiftUI's shapes.
        let rep: NSBitmapImageRep
        // The alert keeps itself out of screen capture (sharingType = .none), so the window server's picture of it is
        // blank: draw that one instead.
        if window.sharingType != .none, let image = Self.windowServerImage(of: window) {
            rep = NSBitmapImageRep(cgImage: image)
        } else {
            guard let drawn = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw DebugError("could not make a bitmap") }
            view.cacheDisplay(in: view.bounds, to: drawn)
            rep = drawn
        }
        guard let png = rep.representation(using: .png, properties: [:]) else { throw DebugError("could not encode PNG") }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try png.write(to: url)
        return "wrote \(url.path) (\(rep.pixelsWide)x\(rep.pixelsHigh))"
    }

    /// CGWindowListCreateImage, which the SDK no longer lets code name (ScreenCaptureKit would need permission), looked
    /// up at run time. Debug builds only.
    private static func windowServerImage(of window: NSWindow) -> CGImage? {
        typealias Create = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") else { return nil }
        let create = unsafeBitCast(symbol, to: Create.self)
        // .optionIncludingWindow; .boundsIgnoreFraming | .bestResolution
        guard let image = create(.null, 1 << 3, UInt32(window.windowNumber), 1 << 0 | 1 << 3)?.takeRetainedValue(),
              image.width > 1 else { return nil }
        return image
    }

    // MARK: Menus

    /// Follows `path` through the main menu: an item at its end is chosen, as clicking it would; a menu is listed.
    private func menu(_ path: [String]) throws -> String {
        guard var menu = NSApp.mainMenu else { throw DebugError("no menu bar") }
        for (i, title) in path.enumerated() {
            menu.update()
            guard let item = menu.items.first(where: { $0.title == title }) else {
                throw DebugError("no '\(title)' in \(menu.items.map(\.title).filter { !$0.isEmpty })")
            }
            if let sub = item.submenu {
                menu = sub
                continue
            }
            guard i == path.count - 1 else { throw DebugError("'\(title)' is an item, not a menu") }
            guard item.isEnabled else { throw DebugError("'\(title)' is disabled") }
            guard let action = item.action, NSApp.sendAction(action, to: item.target, from: item) else {
                throw DebugError("'\(title)' did nothing")
            }
            return "chose \(path.joined(separator: " > "))"
        }
        menu.update()
        return menu.items.map { item in
            if item.isSeparatorItem { return "---" }
            let more = item.submenu != nil ? " >" : ""
            let off = item.isEnabled ? "" : "  (disabled)"
            let key = item.keyEquivalent.isEmpty ? "" : "  ⌘\(item.keyEquivalent)"
            return item.title + more + off + key
        }.joined(separator: "\n")
    }
}

/// The socket itself: plain BSD calls on a thread of its own, one connection at a time. Each request line is run
/// on the main thread, where AppKit lives.
private enum DebugSocket {
    struct Failure: Error, CustomStringConvertible {
        var description: String
    }

    static func listen(at path: String) throws -> Int32 {
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                                withIntermediateDirectories: true)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw Failure(description: "socket: \(String(cString: strerror(errno)))") }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
            close(fd)
            throw Failure(description: "socket path too long: \(path)")
        }
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
        unlink(path)   // a socket left behind by a copy that crashed
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, Darwin.listen(fd, 4) == 0 else {
            let message = String(cString: strerror(errno))
            close(fd)
            throw Failure(description: "can't listen on \(path): \(message)")
        }
        return fd
    }

    static func serve(_ fd: Int32) {
        while true {
            let client = accept(fd, nil, nil)
            guard client >= 0 else { continue }
            converse(client)
            close(client)
        }
    }

    /// Reads request lines until the client hangs up, answering each.
    private static func converse(_ client: Int32) {
        var pending = Data()
        var buffer = [UInt8](repeating: 0, count: 65536)
        while true {
            let n = read(client, &buffer, buffer.count)
            guard n > 0 else { return }
            pending.append(contentsOf: buffer[0..<n])
            while let newline = pending.firstIndex(of: UInt8(ascii: "\n")) {
                let line = Data(pending[pending.startIndex..<newline])
                pending = Data(pending[(newline + 1)...])
                guard !line.isEmpty else { continue }
                // Waiting here keeps the main thread free while the app settles.
                if let request = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                   let wait = request["wait"] as? Double, wait > 0 {
                    Thread.sleep(forTimeInterval: min(wait, 30))
                }
                let reply = DispatchQueue.main.sync { MainActor.assumeIsolated { DebugDriver.shared.handle(line) } }
                guard write(client, reply + Data("\n".utf8)) else { return }
            }
        }
    }

    private static func write(_ client: Int32, _ data: Data) -> Bool {
        data.withUnsafeBytes { raw in
            var sent = 0
            while sent < raw.count {
                let n = Darwin.write(client, raw.baseAddress! + sent, raw.count - sent)
                guard n > 0 else { return false }
                sent += n
            }
            return true
        }
    }
}
#endif
