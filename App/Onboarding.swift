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

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 600),
                             styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.title = "Welcome to Slaps"
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.contentView = NSHostingView(rootView: OnboardingView(model: .shared) { [weak self] in self?.finish() })
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

struct OnboardingView: View {
    @Bindable var model: AppModel
    let done: () -> Void
    @State private var openAtLogin = LoginItem.isEnabled
    @State private var loginError: String?
    @State private var triedAlert = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable().frame(width: 88, height: 88)
                Text("Welcome to Slaps").font(.largeTitle.weight(.bold))
                Text("Before each meeting, Slaps fills your screen so you can't miss it, with a button to join the call.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 380)
            }
            .padding(.top, 36)
            .padding(.bottom, 24)

            VStack(spacing: 0) {
                Step(number: 1, done: model.access == .granted, title: "Let Slaps read your calendars",
                     detail: "Everything in the Calendar app: iCloud, and Google or Microsoft accounts added in "
                        + "System Settings › Internet Accounts. Slaps only reads them.") {
                    switch model.access {
                    case .granted: Label("Allowed", systemImage: "checkmark").foregroundStyle(.green)
                    case .notAsked: Button("Allow…") { model.requestAccess() }.buttonStyle(.borderedProminent)
                    case .denied: Button("Open Privacy Settings…") { model.requestAccess() }
                    }
                }
                Divider().padding(.leading, 52)
                Step(number: 2, done: true, title: "Choose when the alert goes up") {
                    Picker("", selection: $model.leadTime) {
                        Text("When it starts").tag(0.0)
                        ForEach([1, 2, 3, 5, 10, 15], id: \.self) { m in
                            Text("\(m) min before").tag(Double(m * 60))
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                Divider().padding(.leading, 52)
                Step(number: 3, done: model.filter.includeReminders && model.remindersAccess == .granted,
                     title: "Reminders too?", detail: "Reminders with a due time get an alert at that time. Optional.") {
                    Toggle("", isOn: $model.filter.includeReminders).labelsHidden().toggleStyle(.switch)
                }
                Divider().padding(.leading, 52)
                Step(number: 4, done: openAtLogin, title: "Open Slaps at login",
                     detail: loginError ?? "So it's there for the first meeting of the day.") {
                    Toggle("", isOn: $openAtLogin).labelsHidden().toggleStyle(.switch)
                        .onChange(of: openAtLogin) { _, on in
                            do { try LoginItem.set(on); loginError = nil } catch {
                                loginError = error.localizedDescription
                                openAtLogin = LoginItem.isEnabled
                            }
                        }
                }
                Divider().padding(.leading, 52)
                Step(number: 5, done: triedAlert, title: "See what an alert looks like",
                     detail: "Press Escape or Dismiss to close it.") {
                    Button("Show a Test Alert") {
                        triedAlert = true
                        model.testAlert()
                    }
                }
            }
            .padding(.vertical, 4)
            .background(.background.secondary, in: .rect(cornerRadius: 10))
            .padding(.horizontal, 28)

            Spacer(minLength: 16)
            HStack(alignment: .center) {
                Label("Slaps lives in the menu bar", systemImage: "bell")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("Get Started", action: done)
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
        }
        .frame(width: 520, height: 600)
        // Back from System Settings with access granted, the checklist should say so.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.fetch()
            openAtLogin = LoginItem.isEnabled
        }
    }
}

private struct Step<Accessory: View>: View {
    let number: Int
    let done: Bool
    let title: String
    var detail: String?
    @ViewBuilder let accessory: Accessory

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle().fill(done ? Color.green : Color.secondary.opacity(0.2))
                if done {
                    Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(.white)
                } else {
                    Text("\(number)").font(.callout.weight(.semibold)).foregroundStyle(.secondary)
                }
            }
            .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium))
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            accessory
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}
