import SwiftUI

@main
struct SlapsApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        MenuBarExtra {
            ContentView(model: .shared)
        } label: {
            MenuBarLabel(model: .shared)
        }
        .menuBarExtraStyle(.window)
        Settings {
            SettingsView(model: .shared)
        }
    }
}

/// Starts the clock at launch, not when the menu is first opened.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            #if DEBUG
            DebugDriver.startIfAsked()   // only when launched with DEBUG_SOCKET (`just debug-app`)
            #endif
            #if !APP_STORE
            UpdateChecker.shared.start()
            #endif
            AppModel.shared.start()
        }
    }
}
