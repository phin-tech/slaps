import AppKit
import ServiceManagement
import SlapsKit
import SwiftUI

/// Opening at login, shared by the welcome window and Settings.
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ on: Bool) throws {
        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }
}

/// The welcome window: on first launch, and from Settings. An ordinary window of its own (not a SwiftUI scene), since
/// a menu bar app has no window to open it from at launch.
@MainActor
final class OnboardingController: NSObject, NSWindowDelegate {
    static let shared = OnboardingController()
    nonisolated static let doneKey = "onboarded"

    private var window: NSWindow?

    static var isDone: Bool { UserDefaults.standard.bool(forKey: doneKey) }

    /// Opens it, or brings it forward; `step` goes to that step (the debug driver's `onboarding <n>`).
    func show(step: Int? = nil) {
        if step != nil { window?.close() }
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 470),
                             styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.title = "Welcome to Slaps"
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.contentView = NSHostingView(rootView: OnboardingView(model: .shared, step: step ?? 0) { [weak self] in self?.finish() })
            w.center()
            window = w
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: Self.doneKey)
        window?.close()
    }

    /// Closing it with its close button counts as done too: it was seen, and Settings can bring it back. Quitting
    /// Slaps closes it without asking, and doesn't count.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        UserDefaults.standard.set(true, forKey: Self.doneKey)
        return true
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}


/// The welcome window's steps, as Typecase's Welcome is: a stepper across the top that shows where you are (and
/// which steps are done) and goes to any step clicked, the step itself, which slides in from the side it's on, and
/// Back and Next under it, Next being Done at the last. ← and → go between steps; Return is Next.
struct OnboardingView: View {
    @Bindable var model: AppModel
    let done: () -> Void
    @State private var step: Int
    @State private var forward = true
    @State private var openAtLogin = LoginItem.isEnabled
    @State private var loginError: String?
    @State private var triedAlert = false
    @State private var videoLink = ""
    @State private var cliInstalled = CommandLineLink.isInstalled
    @State private var cliTrouble: String?
    @FocusState private var focused: Bool

    init(model: AppModel, step: Int = 0, done: @escaping () -> Void) {
        self.model = model
        self.done = done
        _step = State(initialValue: step)
    }

    private enum Step: Int, CaseIterable {
        case calendars, alerts, reminders, video, keys, commandLine, start

        var title: String {
            switch self {
            case .calendars: "Calendars"
            case .alerts: "Alerts"
            case .reminders: "Reminders"
            case .video: "Video"
            case .keys: "Keys"
            case .commandLine: "Terminal"
            case .start: "Start"
            }
        }
    }

    private func isDone(_ step: Step) -> Bool {
        switch step {
        case .calendars: model.access == .granted
        case .alerts: triedAlert
        case .reminders: model.filter.includeReminders && model.remindersAccess == .granted
        case .video: model.playVideos && !VideoPicker.sources(model.videoLinks).isEmpty
        case .keys: false
        case .commandLine: cliInstalled
        case .start: openAtLogin
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Welcome to Slaps").font(.title2.weight(.bold))
                    Text("Before each meeting, Slaps fills your screen so you can't miss it.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 28)
            .padding(.top, 34)
            Stepper(titles: Step.allCases.map(\.title), at: step, done: Step.allCases.map(isDone)) { go(to: $0) }
                .padding(.horizontal, 20)
                .padding(.top, 20)
            ZStack {
                page(Step(rawValue: step) ?? .calendars)
                    .id(step)
                    .transition(.asymmetric(
                        insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                        removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .clipped()
            Divider()
            HStack {
                Label("Slaps lives in the menu bar", systemImage: "bell")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("Back") { go(to: step - 1) }
                    .disabled(step == 0)
                Button(step == Step.allCases.count - 1 ? "Done" : "Next") {
                    step == Step.allCases.count - 1 ? done() : go(to: step + 1)
                }
                .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
            .padding(.horizontal, 28)
            .padding(.vertical, 16)
        }
        .frame(width: 640, height: 470)
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onKeyPress(.leftArrow) { go(to: step - 1); return .handled }
        .onKeyPress(.rightArrow) { go(to: step + 1); return .handled }
        .onAppear { focused = true }
        // Back from System Settings with access granted, the steps should say so.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.fetch()
            openAtLogin = LoginItem.isEnabled
            cliInstalled = CommandLineLink.isInstalled
        }
    }

    private func go(to at: Int) {
        guard at != step, Step.allCases.indices.contains(at) else { return }
        forward = at > step
        withAnimation(.spring(duration: 0.35, bounce: 0.1)) { step = at }
        focused = true
    }

    @ViewBuilder private func page(_ step: Step) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            switch step {
            case .calendars:
                Heading("Let Slaps read your calendars",
                        "Everything in the Calendar app: iCloud, and Google or Microsoft accounts added in "
                        + "System Settings › Internet Accounts. Slaps only reads them.")
                switch model.access {
                case .granted: Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                case .notAsked: Button("Allow Calendar Access…") { model.requestAccess() }.buttonStyle(.borderedProminent)
                case .denied: Button("Open Privacy Settings…") { model.requestAccess() }
                }
            case .alerts:
                Heading("Choose when the alert goes up",
                        "It fills the screen, with a button to join the call. Settings has banners and a card at the "
                        + "side, if that's too much.")
                Picker("Show it", selection: $model.leadTime) {
                    Text("When it starts").tag(0.0)
                    ForEach([1, 2, 3, 5, 10, 15], id: \.self) { m in
                        Text("\(m) minute\(m == 1 ? "" : "s") before").tag(Double(m * 60))
                    }
                }
                .fixedSize()
                Button("Show a Test Alert") {
                    triedAlert = true
                    model.testAlert()
                }
                Text("Press Escape or Dismiss to close it.").font(.caption).foregroundStyle(.secondary)
            case .reminders:
                Heading("Reminders too?", "Reminders with a due time get an alert at that time, with a button to "
                        + "mark them done. Optional.")
                Toggle("Alert me for reminders with a due time", isOn: $model.filter.includeReminders)
                    .toggleStyle(.switch)
            case .video:
                Heading("A video instead of a chime?",
                        "Paste a YouTube video, playlist or channel and alerts play one, with sound. Add more, or "
                        + "random ones from ytroulette.com, in Settings › Video. Optional.")
                TextField("youtube.com/watch?v=…", text: $videoLink)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 320)
                    .onChange(of: videoLink) { _, link in
                        guard VideoSource(link: link) != nil else { return }
                        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
                        model.videoLinks = [trimmed] + model.videoLinks.filter { $0 != trimmed && !$0.isEmpty }
                        model.playVideos = true
                    }
                if isDone(.video) {
                    Label("Alerts will play a video", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                }
            case .keys:
                Heading("Keys worth knowing", "They work from any app. Change them in Settings › Shortcuts.")
                VStack(spacing: 8) {
                    ForEach(HotKeys.Action.allCases) { action in
                        HStack {
                            Text(action.title)
                            Spacer()
                            KeyCaps(model.shortcuts[action] ?? action.defaultShortcut)
                        }
                    }
                }
                .frame(maxWidth: 440)
                .opacity(model.hotKeysEnabled ? 1 : 0.5)
            case .commandLine:
                Heading("Alerts from scripts", "Put slaps on your PATH, and a script, a build or CI can put up an alert "
                        + "or leave a tab. Optional; Settings › Command Line has it too.")
                HStack {
                    Button(cliInstalled ? "Installed in ~/.local/bin" : "Install slaps in ~/.local/bin") {
                        cliTrouble = CommandLineLink.install()
                        cliInstalled = CommandLineLink.isInstalled
                    }
                    .disabled(cliInstalled)
                    if let cliTrouble { Text(cliTrouble).font(.caption).foregroundStyle(.red) }
                }
                ScriptedTerminal(script: .slaps).frame(height: 130)
            case .start:
                Heading("Open Slaps at login", loginError ?? "So it's there for the first meeting of the day.")
                Toggle("Open at login", isOn: $openAtLogin)
                    .toggleStyle(.switch)
                    .onChange(of: openAtLogin) { _, on in
                        do { try LoginItem.set(on); loginError = nil } catch {
                            loginError = error.localizedDescription
                            openAtLogin = LoginItem.isEnabled
                        }
                    }
                Text("Click the bell in the menu bar for what's next, to pause Slaps, and Settings.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 28)
        .padding(.top, 22)
    }
}

private struct Heading: View {
    let title: String
    let detail: String
    init(_ title: String, _ detail: String) { (self.title, self.detail) = (title, detail) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.title3.weight(.semibold))
            Text(detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A shortcut as keys, a cap to each, as gpui-kit's Kbd draws them.
private struct KeyCaps: View {
    let keys: [String]

    init(_ shortcut: Shortcut) {
        let m = shortcut.modifiers
        keys = [(Shortcut.Modifiers.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
            .filter { m.contains($0.0) }.map(\.1) + [shortcut.key]
    }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                Text(key)
                    .font(.callout.monospaced())
                    .frame(minWidth: 22, minHeight: 22)
                    .background(.quaternary, in: .rect(cornerRadius: 5))
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.separator))
            }
        }
    }
}

/// Where you are in the steps: a numbered dot for each, ticked when done, joined by a line; click one to go to it.
private struct Stepper: View {
    let titles: [String]
    let at: Int
    let done: [Bool]
    let go: (Int) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(titles.indices, id: \.self) { i in
                Button { go(i) } label: {
                    VStack(spacing: 6) {
                        ZStack {
                            Rectangle()
                                .fill(.separator)
                                .frame(height: 2)
                                .padding(.leading, i == 0 ? 60 : 0)
                                .padding(.trailing, i == titles.count - 1 ? 60 : 0)
                            Circle()
                                .fill(i == at ? Color.accentColor : done[i] ? .green : Color.secondary.opacity(0.2))
                                .frame(width: 24, height: 24)
                            if done[i] && i != at {
                                Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(.white)
                            } else {
                                Text("\(i + 1)").font(.callout.weight(.semibold))
                                    .foregroundStyle(i == at ? .white : .secondary)
                            }
                        }
                        Text(titles[i])
                            .font(.caption.weight(i == at ? .semibold : .regular))
                            .foregroundStyle(i == at ? .primary : .secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Step \(i + 1), \(titles[i])\(done[i] ? ", done" : "")")
                .accessibilityAddTraits(i == at ? .isSelected : [])
            }
        }
    }
}
