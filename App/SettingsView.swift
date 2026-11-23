import ServiceManagement
import SlapsKit
import SwiftUI

/// Settings, as Typecase's settings window is: a sidebar of sections with a search box over them, and the chosen
/// section's page beside it, under its name and a line saying what it's for. The search finds sections by name and
/// keywords (`SettingsSection.matching`).
struct SettingsView: View {
    let model: AppModel
    @AppStorage("settingsSection") private var chosen: SettingsSection = .general
    @State private var search = ""

    /// The sections this Mac has: Battery only with a battery, Updates only outside the App Store.
    static var available: [SettingsSection] {
        SettingsSection.allCases.filter { section in
            switch section {
            case .battery: BatteryMonitor.hasBattery
            #if APP_STORE
            case .updates: false
            #endif
            default: true
            }
        }
    }

    private var shown: [SettingsSection] { SettingsSection.matching(search, in: Self.available) }

    var body: some View {
        // A sidebar of its own rather than a NavigationSplitView, whose column width a Settings scene doesn't keep.
        HStack(spacing: 0) {
            VStack(spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search", text: $search)
                        .textFieldStyle(.plain)
                        .onSubmit { if let first = shown.first { chosen = first } }
                    if !search.isEmpty {
                        Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                            .help("Clear")
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 7))
                .padding(.horizontal, 10)
                .padding(.top, 10)
                List(selection: Binding(get: { chosen }, set: { if let s = $0 { chosen = s } })) {
                    ForEach(shown) { section in
                        Label(section.name, systemImage: section.symbol).tag(section)
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .overlay {
                    if shown.isEmpty {
                        Text("No section has “\(search)”").font(.callout).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center).padding()
                    }
                }
            }
            .frame(width: 210)
            .background(.background.secondary)
            Divider()
            SettingsPage(section: chosen, model: model)
                .id(chosen)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: search) { if !shown.isEmpty && !shown.contains(chosen) { chosen = shown[0] } }
        .navigationTitle(chosen.name)
        .frame(minWidth: 700, idealWidth: 740, minHeight: 480, idealHeight: 560)
        .onAppear {
            if !Self.available.contains(chosen) { chosen = .general }
            model.fetch()
        }
    }
}

/// A section's page: its name and summary, then its rows.
private struct SettingsPage: View {
    let section: SettingsSection
    let model: AppModel

    var body: some View {
        Form {
            Section {
            } header: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(section.name).font(.title2.weight(.semibold)).foregroundStyle(.primary)
                    Text(section.summary).font(.callout).foregroundStyle(.secondary)
                }
                .textCase(nil)
                .padding(.bottom, 14)
            }
            switch section {
            case .general: GeneralSettings(model: model)
            case .alerts: AlertSettings(model: model)
            case .video: VideoSettings(model: model)
            case .battery: BatterySettings(model: model)
            case .calendars: CalendarSettings(model: model)
            case .filters: FilterSettings(model: model)
            case .tabs: TabSettings(model: model)
            case .shortcuts: ShortcutSettings(model: model)
            case .otherApps: OtherAppSettings(model: model)
            case .commandLine: CommandLineSettings()
            case .updates: UpdateSettings()
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Pages

private struct GeneralSettings: View {
    @Bindable var model: AppModel
    @State private var openAtLogin = LoginItem.isEnabled
    @State private var loginError: String?

    var body: some View {
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
        }
        Section {
            LabeledContent("Welcome window") {
                Button("Show It Again") { OnboardingController.shared.show() }
            }
        } footer: {
            Text("The steps from the first launch: calendar access, when alerts go up, and the rest.")
                .foregroundStyle(.secondary)
        }
    }
}

private struct AlertSettings: View {
    @Bindable var model: AppModel

    var body: some View {
        Section("When") {
            Picker("Show it", selection: $model.leadTime) {
                Text("When the meeting starts").tag(0.0)
                ForEach([1, 2, 3, 5, 10, 15], id: \.self) { m in
                    Text("\(m) minute\(m == 1 ? "" : "s") before").tag(Double(m * 60))
                }
            }
            Toggle("If I dismiss it early, alert again when it starts", isOn: $model.againAtStart)
                .disabled(model.leadTime == 0)
        }
        Section("Look and sound") {
            Picker("Style", selection: $model.alertStyle) {
                ForEach(AlertStyle.allCases) { Text($0.name).tag($0) }
            }
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
            LabeledContent("See it") {
                Button("Show a Test Alert") { model.testAlert() }
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
    }
}

private struct VideoSettings: View {
    @Bindable var model: AppModel

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
            }
        } footer: {
            Text("It plays in the alert, with sound, in place of the alert sound, and stops when you dismiss it.")
                .foregroundStyle(.secondary)
        }
        if model.playVideos {
            Section {
                TextEditor(text: Binding(
                    get: { model.videoLinks.joined(separator: "\n") },
                    set: { model.videoLinks = $0.components(separatedBy: .newlines) }))
                    .font(.callout.monospaced())
                    .frame(height: 120)
            } header: {
                Text("Your links")
            } footer: {
                Text(linksSummary).foregroundStyle(.secondary)
            }
        }
    }
}

private struct BatterySettings: View {
    @Bindable var model: AppModel

    var body: some View {
        Section {
            Toggle("Alert me when the battery is low", isOn: $model.batteryAlerts)
            Picker("At", selection: $model.batteryLevel) {
                ForEach([5, 10, 15, 20, 25, 30, 40, 50], id: \.self) { Text("\($0)%").tag($0) }
            }
            .disabled(!model.batteryAlerts)
        } footer: {
            Text("Once each time it runs down to that level on battery, in the alert style and theme. "
                + "Plugging in takes it away.")
                .foregroundStyle(.secondary)
        }
    }
}

private struct TabSettings: View {
    @Bindable var model: AppModel

    var body: some View {
        Section("Where") {
            Picker("Edge", selection: $model.tabEdge) {
                ForEach(TabEdge.allCases) { Text($0.name).tag($0) }
            }
            Picker("Position", selection: $model.tabPosition) {
                ForEach(TabPosition.allCases) { Text($0.name).tag($0) }
            }
            Picker("Stacks", selection: $model.tabPile) {
                ForEach(TabPile.allCases) { Text($0.name).tag($0) }
            }
        }
        Section("Look") {
            Picker("Look", selection: $model.tabLook) {
                ForEach(TabLook.allCases) { Text($0.name).tag($0) }
            }
            Picker("Size", selection: $model.tabSize) {
                ForEach(TabSize.allCases) { Text($0.name).tag($0) }
            }
            Toggle("Show tabs in screenshots and recordings", isOn: $model.tabsInScreenshots)
        }
        Section {
            Picker("Unless the sender says, slap me", selection: $model.tabDeadline) {
                Text("Never").tag(0.0)
                ForEach([15, 30, 60, 120, 240, 480], id: \.self) { m in
                    Text(m < 60 ? "\(m) minutes after it arrives" : "\(m / 60) hour\(m == 60 ? "" : "s") after it arrives")
                        .tag(Double(m * 60))
                }
            }
        } header: {
            Text("Deadline")
        } footer: {
            Text("Other apps can leave a tab on the edge of the main screen (slaps tab \"Reply to Bob\" --deadline 30). "
                + "It stays until you dismiss it; past its deadline it goes up full screen. Hover to slide one out.")
                .foregroundStyle(.secondary)
        }
    }
}

private struct ShortcutSettings: View {
    @Bindable var model: AppModel

    var body: some View {
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
    }
}

private struct OtherAppSettings: View {
    @Bindable var model: AppModel

    var body: some View {
        Section {
            Toggle("Allow other apps to put up alerts and pause Slaps", isOn: $model.allowExternal)
        } footer: {
            Text("Turned off, slaps:// links, AppleScript and the command line are all refused.")
                .foregroundStyle(.secondary)
        }
        Section("A slaps:// link") {
            Example("open -g \"slaps://alert?title=Deploy%20done&in=5\"")
        }
        Section("AppleScript") {
            Example("tell application \"Slaps\" to show alert \"Deploy done\"")
        }
    }
}

private struct CommandLineSettings: View {
    @State private var installed = CommandLineLink.isInstalled
    @State private var trouble: String?

    var body: some View {
        Section {
            LabeledContent("slaps") {
                Button(installed ? "Installed in ~/.local/bin" : "Install in ~/.local/bin") {
                    trouble = CommandLineLink.install()
                    installed = CommandLineLink.isInstalled
                }
                .disabled(installed)
            }
            if let trouble {
                Text(trouble).foregroundStyle(.red)
            }
        } footer: {
            Text("A link to Slaps's own binary, so it's updated with the app. It says what's wrong in the terminal, "
                + "where a slaps:// link only notes it in the log. Other apps have to be allowed (Other Apps).")
                .foregroundStyle(.secondary)
        }
        Section {
            ScriptedTerminal(script: .slaps)
                .frame(height: 240)
        } header: {
            Text("How it's used")
        } footer: {
            Text("slaps help lists the rest.").foregroundStyle(.secondary)
        }
    }
}

#if !APP_STORE
private struct UpdateSettings: View {
    @AppStorage(UpdateChecker.betaKey) private var betaUpdates = UpdateChecker.runningBeta

    var body: some View {
        Section {
            Toggle("Check for updates automatically", isOn: Binding(
                get: { UpdateChecker.shared.automaticChecks },
                set: { UpdateChecker.shared.automaticChecks = $0 }))
            Toggle("Get beta versions", isOn: $betaUpdates)
            LabeledContent("Slaps \(SlapsVersion.current)") {
                Button("Check Now") { UpdateChecker.shared.checkForUpdates() }
            }
        } footer: {
            Text("Once a day, Slaps asks GitHub for a newer release, and offers to install it and relaunch. "
                + "Betas come out before a release and may have rough edges; when the release ships, you move on to it.")
                .foregroundStyle(.secondary)
        }
    }
}
#else
private struct UpdateSettings: View {
    var body: some View { EmptyView() }
}
#endif

/// Something to type or paste, in a monospaced face, that can be selected and copied.
private struct Example: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        HStack {
            Text(text).font(.callout.monospaced()).textSelection(.enabled)
            Spacer()
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help("Copy")
        }
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
}

private struct FilterSettings: View {
    @Bindable var model: AppModel
    @State private var words = ""

    var body: some View {
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
                // On the field itself, so it's filled before anything typed in it can save over the list.
                .onAppear { words = model.filter.ignoredTitleWords.joined(separator: ", ") }
        } footer: {
            Text("Separate words with commas. Case doesn't matter.").foregroundStyle(.secondary)
        }
    }

    private func save() {
        let list = words.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if list != model.filter.ignoredTitleWords { model.filter.ignoredTitleWords = list }
    }
}
