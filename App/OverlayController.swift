import AppKit
import SlapsKit
import SwiftUI

/// The alert: a borderless panel over everything on every screen, in every Space and over full-screen apps; all of
/// each screen, or a banner across its top or bottom (`AlertStyle`).
@MainActor
final class OverlayController {
    private var panels: [NSPanel] = []
    private var style = AlertStyle.fullScreen
    private var screenObserver: NSObjectProtocol?

    init() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.panels.isEmpty else { return }
                self.hide()
                self.show(self.style)
            }
        }
    }

    var isShowing: Bool { !panels.isEmpty }

    func show(_ style: AlertStyle) {
        if !panels.isEmpty && style != self.style { hide() }
        guard panels.isEmpty else { return }
        self.style = style
        let main = NSScreen.main ?? NSScreen.screens.first
        for screen in NSScreen.screens {
            let frame = style.frame(screen: screen.frame, visible: screen.visibleFrame)
            // A banner doesn't activate Slaps when clicked, so whatever you're typing in keeps the keyboard.
            let mask: NSWindow.StyleMask = style.isBanner ? [.borderless, .nonactivatingPanel] : [.borderless]
            let panel = OverlayPanel(contentRect: frame, styleMask: mask, backing: .buffered, defer: false)
            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.title = "Slaps alert"
            // Kept out of screen sharing and recordings where macOS honours it, in case one starts mid-alert.
            panel.sharingType = .none
            panel.hasShadow = style.isBanner
            panel.contentView = NSHostingView(rootView: AlertView(model: .shared, isMainScreen: screen == main,
                                                                  style: style))
            panel.setFrame(frame, display: true)
            panels.append(panel)
            if screen == main && !style.isBanner {
                panel.makeKeyAndOrderFront(nil)   // the one that takes Return and Escape
            } else {
                panel.orderFrontRegardless()
            }
        }
        // Full screen takes the keyboard on purpose; a banner leaves it where it was (⌃⌥⌘J and ⌃⌥⌘D still work).
        if !style.isBanner { NSApp.activate() }
    }

    func hide() {
        for panel in panels { panel.orderOut(nil) }
        panels = []
    }
}

/// A borderless panel can't become key by itself, and then keyboard shortcuts wouldn't reach the alert.
private final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

struct AlertView: View {
    let model: AppModel
    let isMainScreen: Bool
    var style: AlertStyle = .fullScreen
    /// Keys do nothing for a moment after the alert appears: it takes the keyboard from whatever you were typing in,
    /// and a Return or Escape meant for that shouldn't join or dismiss a meeting you haven't seen yet.
    @State private var keysArmed = false

    var body: some View {
        let theme = model.palette
        ZStack {
            LinearGradient(colors: theme.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                .opacity(0.97)
                .ignoresSafeArea()
            if let first = model.alerting.first, style.isBanner {
                banner(first, theme: theme)
            } else if let first = model.alerting.first {
                VStack(spacing: 28) {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(countdown(for: first, now: context.date))
                            .font(.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundStyle(theme.accent)
                    }
                    Text(first.title)
                        .font(.system(size: isMainScreen ? 72 : 52, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .minimumScaleFactor(0.4)
                    Text(details(first))
                        .font(.title2)
                        .opacity(0.75)
                    if isMainScreen, let video = model.alertVideo {
                        AlertVideoView(video: video)
                            .frame(width: 640, height: 360)
                            .clipShape(.rect(cornerRadius: 12))
                    }
                    if model.alerting.count > 1 {
                        VStack(spacing: 6) {
                            Text("Also now").font(.headline).opacity(0.6)
                            ForEach(model.alerting.dropFirst()) { m in
                                HStack {
                                    Text("\(m.start.formatted(date: .omitted, time: .shortened))  \(m.title)")
                                    if m.link != nil {
                                        Button("Join") { model.join(m) }.buttonStyle(.link)
                                    }
                                }
                                .font(.title3)
                            }
                        }
                    }
                    if isMainScreen { buttons(first, theme: theme).padding(.top, 20) }
                }
                .foregroundStyle(theme.foreground)
                .padding(80)
                .frame(maxWidth: 1100)
            }
        }
        .task {
            try? await Task.sleep(for: .seconds(1.5))
            keysArmed = true
        }
    }

    private func key(_ shortcut: KeyboardShortcut?) -> KeyboardShortcut? { keysArmed ? shortcut : nil }

    /// The banner: everything in one row, the buttons at the end, and an accent line along the edge facing the
    /// rest of the screen.
    private func banner(_ first: Meeting, theme: Palette) -> some View {
        HStack(spacing: 32) {
            VStack(alignment: .leading, spacing: 6) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(countdown(for: first, now: context.date))
                        .font(.system(size: 22, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(theme.accent)
                }
                Text(first.title)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(details(first) + (model.alerting.count > 1 ? "  ·  and \(model.alerting.count - 1) more now" : ""))
                    .font(.title3)
                    .opacity(0.75)
                    .lineLimit(1)
            }
            Spacer(minLength: 24)
            if isMainScreen, let video = model.alertVideo {
                AlertVideoView(video: video)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(.rect(cornerRadius: 8))
                    .padding(.vertical, 18)
            }
            if isMainScreen { buttons(first, theme: theme) }
        }
        .foregroundStyle(theme.foreground)
        .padding(.horizontal, 48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: style == .top ? .bottom : .top) {
            Rectangle().fill(theme.accent).frame(height: 3)
        }
    }

    @ViewBuilder private func buttons(_ first: Meeting, theme: Palette) -> some View {
        HStack(spacing: 16) {
            if first.kind == .reminder {
                Button { model.complete(first) } label: {
                    Label("Mark Done", systemImage: "checkmark.circle.fill").frame(minWidth: 220)
                }
                .buttonStyle(AlertButtonStyle(fill: theme.accent, text: theme.onAccent))
                .keyboardShortcut(key(.defaultAction))
            } else if first.kind == .custom, first.link == nil, let url = first.url {
                // Not a call we know: say where it goes, since anyone can send one.
                Button { model.join(first) } label: {
                    Label("Open \(url.host ?? "Link")", systemImage: "arrow.up.right.square.fill").frame(minWidth: 220)
                }
                .buttonStyle(AlertButtonStyle(fill: theme.accent, text: theme.onAccent))
                .keyboardShortcut(key(.defaultAction))
            } else if let link = first.link {
                Button { model.join(first) } label: {
                    Label("Join \(link.service)", systemImage: "video.fill").frame(minWidth: 220)
                }
                .buttonStyle(AlertButtonStyle(fill: theme.accent, text: theme.onAccent))
                .keyboardShortcut(key(.defaultAction))
            }
            Menu("Snooze") {
                Button("1 minute") { model.snooze(model.alerting, until: Date().addingTimeInterval(60)) }
                Button("5 minutes") { model.snooze(model.alerting, until: Date().addingTimeInterval(300)) }
                if first.start > Date().addingTimeInterval(30) {
                    Button("Until it starts") { model.snooze(model.alerting, until: first.start) }
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .padding(.horizontal, 22).padding(.vertical, 12)
            .background(theme.foreground.opacity(0.15), in: .capsule)
            Button { model.dismiss(model.alerting) } label: {
                Text("Dismiss").frame(minWidth: 120)
            }
            .buttonStyle(AlertButtonStyle(fill: theme.foreground.opacity(0.15), text: theme.foreground))
            .keyboardShortcut(key(first.link == nil && first.url == nil && first.kind != .reminder ? .defaultAction : nil))
        }
        .font(.title3.weight(.semibold))
        // Escape always dismisses, even when Dismiss is the default button.
        .background(Button("") { model.dismiss(model.alerting) }.keyboardShortcut(key(.cancelAction)).hidden())
    }

    private func details(_ m: Meeting) -> String {
        if m.kind == .custom {
            let from = m.calendarTitle.isEmpty ? nil : "From \(m.calendarTitle)"
            return [m.notes, from].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "  ·  ")
        }
        if m.kind == .reminder {
            return ["Due \(m.start.formatted(date: .omitted, time: .shortened))", m.calendarTitle]
                .filter { !$0.isEmpty }.joined(separator: "  ·  ")
        }
        let time = "\(m.start.formatted(date: .omitted, time: .shortened)) – \(m.end.formatted(date: .omitted, time: .shortened))"
        return [time, m.calendarTitle, m.link == nil ? m.location : nil]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "  ·  ")
    }

    private func countdown(for m: Meeting, now: Date) -> String {
        let s = Int(m.start.timeIntervalSince(now).rounded())
        if m.kind == .reminder { return s > 0 ? String(format: "Reminder in %d:%02d", s / 60, s % 60) : "Reminder" }
        if BatteryWatch.isAlert(m) { return "Low battery" }
        if m.kind == .custom { return s > 0 ? String(format: "In %d:%02d", s / 60, s % 60) : "Now" }
        if s > 0 { return String(format: "Starts in %d:%02d", s / 60, s % 60) }
        if s > -60 { return "Starting now" }
        return "Started \(-s / 60) min ago"
    }
}

/// Bold, and the same whether or not the window is active: system styles fade in an inactive window, and an alert
/// should never look like it is.
private struct AlertButtonStyle: ButtonStyle {
    var fill: Color
    var text: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 22).padding(.vertical, 12)
            .foregroundStyle(text)
            .background(fill, in: .capsule)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(.capsule)
    }
}
