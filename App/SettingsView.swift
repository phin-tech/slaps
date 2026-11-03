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
    #if !APP_STORE
    @AppStorage(UpdateChecker.betaKey) private var betaUpdates = UpdateChecker.runningBeta
    #endif

    var body: some View {
        Form {
            Section("Alert") {
                Picker("Show it", selection: $model.leadTime) {
                    Text("When the meeting starts").tag(0.0)
                    ForEach([1, 2, 3, 5, 10, 15], id: \.self) { m in
                        Text("\(m) minute\(m == 1 ? "" : "s") before").tag(Double(m * 60))
                    }
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
                Button("Show a Test Alert") { model.testAlert() }
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
            } footer: {
                Text("With slaps:// links, like open \"slaps://alert?title=Deploy%20done&in=5\", or AppleScript: "
                    + "tell application \"Slaps\" to show alert \"Deploy done\". See the README for the rest.")
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Section {
                Toggle("Keyboard shortcuts", isOn: $model.hotKeysEnabled)
                ForEach(HotKeys.Action.allCases) { action in
                    LabeledContent(action.title) {
                        Text(action.shortcut).monospaced().foregroundStyle(.secondary)
                    }
                    .opacity(model.hotKeysEnabled ? 1 : 0.5)
                }
            } footer: {
                Text("They work from any app.").foregroundStyle(.secondary)
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
