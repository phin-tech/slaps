import ServiceManagement
import SlapsKit
import SwiftUI

struct SettingsView: View {
    let model: AppModel

    var body: some View {
        TabView {
            GeneralSettings(model: model).tabItem { Label("General", systemImage: "gearshape") }
            CalendarSettings(model: model).tabItem { Label("Calendars", systemImage: "calendar") }
            FilterSettings(model: model).tabItem { Label("Filters", systemImage: "line.3.horizontal.decrease.circle") }
        }
        .frame(width: 480)
        .onAppear { model.fetch() }
    }
}

private struct GeneralSettings: View {
    @Bindable var model: AppModel
    @State private var openAtLogin = LoginItem.isEnabled
    @State private var loginError: String?
    @State private var cliInstalled = CommandLineLink.isInstalled
    @State private var cliTrouble: String?
    #if !APP_STORE
    @AppStorage(UpdateChecker.betaKey) private var betaUpdates = UpdateChecker.runningBeta
    #endif

    private var linksSummary: String {
        let sources = VideoPicker.sources(model.videoLinks)
        guard !sources.isEmpty else { return "Paste YouTube videos, playlists or channels, one a line." }
        let videos = sources.filter { if case .video = $0 { true } else { false } }.count
        let lists = sources.count - videos
        var parts: [String] = []
        if videos > 0 { parts.append("\(videos) video\(videos == 1 ? "" : "s")") }
        if lists > 0 { parts.append("\(lists) playlist\(lists == 1 ? "" : "s") or channel\(lists == 1 ? "" : "s") (their newest videos)") }
        return parts.joined(separator: " and ") + " to pick from."
    }

    var body: some View {
        Form {
            Section("Alert") {
                Picker("Show it", selection: $model.leadTime) {
                    Text("When the meeting starts").tag(0.0)
                    ForEach([1, 2, 3, 5, 10, 15], id: \.self) { m in
                        Text("\(m) minute\(m == 1 ? "" : "s") before").tag(Double(m * 60))
                    }
                }
                Picker("Style", selection: $model.alertStyle) {
                    ForEach(AlertStyle.allCases) { Text($0.name).tag($0) }
                }
                Toggle("If I dismiss it early, alert again when it starts", isOn: $model.againAtStart)
                    .disabled(model.leadTime == 0)
                Picker("Sound", selection: $model.sound) {
                    ForEach(AlertSound.all, id: \.self) { Text($0) }
                }
                .onChange(of: model.sound) { _, name in AlertSound.play(name) }
                Picker("Theme", selection: $model.theme) {
                    ForEach(Theme.allCases) { Text($0.name).tag($0) }
                }
                if model.theme == .custom {
                    ColorPicker("Background", selection: Binding(
                        get: { Color(model.customBackground) }, set: { model.customBackground = ThemeColor($0) }),
                        supportsOpacity: false)
                    ColorPicker("Accent: the countdown and the Join button", selection: Binding(
                        get: { Color(model.customAccent) }, set: { model.customAccent = ThemeColor($0) }),
                        supportsOpacity: false)
                }
                Button("Show a Test Alert") { model.testAlert() }
            }
            Section {
                Toggle("Play a random YouTube video with each alert", isOn: $model.playVideos)
                if model.playVideos {
                    Picker("From", selection: $model.videoMode) {
                        ForEach(VideoMode.allCases) { Text($0.name).tag($0) }
                    }
                    if model.videoMode == .roulette {
                        Picker("Category", selection: $model.rouletteCategory) {
                            ForEach(Roulette.categories, id: \.self) { Text(Roulette.name(of: $0)).tag($0) }
                        }
                        Text("A random video from ytroulette.com, fetched ahead of time. Nobody checks what it "
                            + "picks, so anything can turn up, more so under Anything. If it doesn't answer, one "
                            + "from your links below plays instead.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    TextEditor(text: Binding(
                        get: { model.videoLinks.joined(separator: "\n") },
                        set: { model.videoLinks = $0.components(separatedBy: .newlines) }))
                        .font(.callout.monospaced())
                        .frame(height: 90)
                    Text(linksSummary).font(.caption).foregroundStyle(.secondary)
                }
            } footer: {
                Text("It plays in the alert, with sound, in place of the alert sound, and stops when you dismiss it.")
                    .foregroundStyle(.secondary)
            }
            if BatteryMonitor.hasBattery {
                Section {
                    Toggle("Alert me when the battery is low", isOn: $model.batteryAlerts)
                    Picker("At", selection: $model.batteryLevel) {
                        ForEach([5, 10, 15, 20, 25, 30, 40, 50], id: \.self) { Text("\($0)%").tag($0) }
                    }
                    .disabled(!model.batteryAlerts)
                } footer: {
                    Text("Once each time it runs down to that level on battery, in the style and theme above. "
                        + "Plugging in takes it away.")
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                Toggle("Hold alerts while I share my screen", isOn: $model.pauseWhileSharing)
            } footer: {
                Text("Slaps spots the border Zoom, Teams, Webex and Slack draw around a shared screen, and keeps the "
                    + "alert back until sharing stops; the menu bar bell rings meanwhile. Sharing from a browser tab "
                    + "(Google Meet) isn't detected, so pause Slaps for those.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Allow other apps to put up alerts and pause Slaps", isOn: $model.allowExternal)
                LabeledContent("Command line") {
                    Button(cliInstalled ? "Installed in ~/.local/bin" : "Install slaps in ~/.local/bin") {
                        cliTrouble = CommandLineLink.install()
                        cliInstalled = CommandLineLink.isInstalled
                    }
                    .disabled(cliInstalled)
                }
                if let cliTrouble {
                    Text(cliTrouble).foregroundStyle(.red)
                }
            } footer: {
                Text("With slaps:// links, like open \"slaps://alert?title=Deploy%20done&in=5\", AppleScript: "
                    + "tell application \"Slaps\" to show alert \"Deploy done\", or the command line: "
                    + "slaps alert \"Deploy done\" --in 5 (slaps help lists the rest).")
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Section {
                Picker("Edge", selection: $model.tabEdge) {
                    ForEach(TabEdge.allCases) { Text($0.name).tag($0) }
                }
                Picker("Position", selection: $model.tabPosition) {
                    ForEach(TabPosition.allCases) { Text($0.name).tag($0) }
                }
                Picker("Look", selection: $model.tabLook) {
                    ForEach(TabLook.allCases) { Text($0.name).tag($0) }
                }
                Picker("Size", selection: $model.tabSize) {
                    ForEach(TabSize.allCases) { Text($0.name).tag($0) }
                }
                Picker("Stacks", selection: $model.tabPile) {
                    ForEach(TabPile.allCases) { Text($0.name).tag($0) }
                }
                Toggle("Show tabs in screenshots and recordings", isOn: $model.tabsInScreenshots)
                Picker("Unless the sender says, slap me", selection: $model.tabDeadline) {
                    Text("Never").tag(0.0)
                    ForEach([15, 30, 60, 120, 240, 480], id: \.self) { m in
                        Text(m < 60 ? "\(m) minutes after it arrives" : "\(m / 60) hour\(m == 60 ? "" : "s") after it arrives")
                            .tag(Double(m * 60))
                    }
                }
            } header: {
                Text("Tabs")
            } footer: {
                Text("Other apps can leave a tab on the edge of the main screen (slaps tab \"Reply to Bob\" --deadline 30). "
                    + "It stays until you dismiss it; past its deadline it goes up full screen. Hover to slide one out.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Keyboard shortcuts", isOn: $model.hotKeysEnabled)
                ForEach(HotKeys.Action.allCases) { action in
                    LabeledContent(action.title) {
                        ShortcutRecorder(model: model, action: action)
                    }
                    .disabled(!model.hotKeysEnabled)
                }
            } footer: {
                Text("They work from any app. Click one, then press the keys you want; it needs ⌃, ⌥ or ⌘.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Show the date in the menu bar", isOn: $model.showDateInMenuBar)
                Toggle("Open Slaps at login", isOn: $openAtLogin)
                    .onChange(of: openAtLogin) { _, on in
                        do {
                            try LoginItem.set(on)
                            loginError = nil
                        } catch {
                            loginError = error.localizedDescription
                        }
                    }
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.red) }
                Button("Show the Welcome Window") { OnboardingController.shared.show() }
            }
            #if !APP_STORE
            Section {
                Toggle("Check for updates automatically", isOn: Binding(
                    get: { UpdateChecker.shared.automaticChecks },
                    set: { UpdateChecker.shared.automaticChecks = $0 }))
                Toggle("Get beta versions", isOn: $betaUpdates)
                Button("Check Now") { UpdateChecker.shared.checkForUpdates() }
            } header: {
                Text("Updates")
            } footer: {
                Text("Once a day, Slaps asks GitHub for a newer release, and offers to install it and relaunch. "
                    + "Betas come out before a release and may have rough edges; when the release ships, you move on to it.")
                    .foregroundStyle(.secondary)
            }
            #endif
        }
        .formStyle(.grouped)
    }
}

/// A shortcut, which you click and then press the keys you want in its place; Escape gives up, and ↺ goes back to
/// the one it came with.
private struct ShortcutRecorder: View {
    @Bindable var model: AppModel
    let action: HotKeys.Action
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        let shortcut = model.shortcuts[action] ?? action.defaultShortcut
        HStack(spacing: 4) {
            Button(recording ? "Press keys…" : shortcut.display) { recording ? stop() : record() }
                .monospaced()
                .frame(minWidth: 90)
            if shortcut != action.defaultShortcut {
                Button { model.shortcuts[action] = action.defaultShortcut } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.borderless)
                .help("Back to \(action.defaultShortcut.display)")
            }
            if model.hotKeysEnabled && !model.isRegistered(action) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                    .help("Another app has this shortcut")
            }
        }
        .onDisappear(perform: stop)
    }

    private func record() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 && event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
                stop()   // Escape alone: never mind
                return nil
            }
            let shortcut = Shortcut(event)
            guard shortcut.isUsable else {
                NSSound.beep()
                return nil
            }
            // One shortcut can't do two things: one that had it takes this one's old shortcut, so they swap.
            let old = model.shortcuts[action] ?? action.defaultShortcut
            for other in HotKeys.Action.allCases where other != action && model.shortcuts[other] == shortcut {
                model.shortcuts[other] = old
            }
            model.shortcuts[action] = shortcut
            stop()
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

private struct CalendarSettings: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            if model.access != .granted {
                Section {
                    Text("Slaps can't read your calendars yet.")
                    Button(model.access == .notAsked ? "Allow Calendar Access" : "Open Privacy Settings…") {
                        model.requestAccess()
                    }
                }
            }
            ForEach(Dictionary(grouping: model.calendars, by: \.account).sorted { $0.key < $1.key }, id: \.key) { account, calendars in
                Section(account) {
                    ForEach(calendars) { cal in
                        Toggle(isOn: Binding(
                            get: { !model.filter.excludedCalendarIDs.contains(cal.id) },
                            set: { on in
                                if on { model.filter.excludedCalendarIDs.remove(cal.id) }
                                else { model.filter.excludedCalendarIDs.insert(cal.id) }
                            })) {
                            HStack {
                                Circle().fill(cal.color).frame(width: 10, height: 10)
                                Text(cal.title)
                            }
                        }
                    }
                }
            }
            Section {
                Text("Slaps reads the calendars in macOS's Calendar app. To add Google, Microsoft 365 or Exchange, "
                    + "add the account in System Settings › Internet Accounts.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(minHeight: 360)
    }
}

private struct FilterSettings: View {
    @Bindable var model: AppModel
    @State private var words = ""

    var body: some View {
        Form {
            Section("Alert for") {
                Toggle("All-day events", isOn: $model.filter.includeAllDay)
                Toggle("Events I declined", isOn: $model.filter.includeDeclined)
                Toggle("Only events with other people", isOn: $model.filter.requireOtherAttendees)
                Toggle("Only events with a video call link", isOn: $model.filter.requireLink)
            }
            Section {
                Toggle("Reminders with a due time", isOn: $model.filter.includeReminders)
                Toggle("Only high-priority reminders", isOn: $model.filter.onlyHighPriorityReminders)
                    .disabled(!model.filter.includeReminders)
                if model.filter.includeReminders && model.remindersAccess == .denied {
                    Button("Allow Reminders Access in Privacy Settings…") { model.askForReminders() }
                }
            } header: {
                Text("Reminders")
            } footer: {
                Text("A reminder's alert goes up at its due time, with a button to mark it done.")
                    .foregroundStyle(.secondary)
            }
            Section {
                TextField("Ignore titles containing", text: $words, prompt: Text("Lunch, Focus, OOO"))
                    .onSubmit(save)
                    .onChange(of: words) { save() }
            } footer: {
                Text("Separate words with commas. Case doesn't matter.").foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { words = model.filter.ignoredTitleWords.joined(separator: ", ") }
    }

    private func save() {
        let list = words.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if list != model.filter.ignoredTitleWords { model.filter.ignoredTitleWords = list }
    }
}
