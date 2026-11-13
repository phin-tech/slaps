import SlapsKit
import SwiftUI

/// The command line first: `slaps alert …` runs here and exits, before any of the app starts. Through the `slaps`
/// link everything is the command line, so a mistake is said rather than opening the app; the app's own binary takes
/// only the command words, since Launch Services starts it with arguments of its own.
@main
enum Main {
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let asSlaps = URL(fileURLWithPath: CommandLine.arguments.first ?? "").lastPathComponent == "slaps"
        if asSlaps {
            exit(CommandLineTool.run(arguments.isEmpty ? ["help"] : arguments))
        }
        if let first = arguments.first, SlapsCommandLine.commands.contains(first.lowercased()) {
            exit(CommandLineTool.run(arguments))
        }
        SlapsApp.main()
    }
}

/// `slaps` in a terminal: the app's own binary, through a link to it (Settings › General, or `just install-cli`).
enum CommandLineTool {
    static func run(_ arguments: [String]) -> Int32 {
        do {
            guard let url = try SlapsCommandLine.url(for: arguments) else {
                print(SlapsCommandLine.help)
                return 0
            }
            // To whichever Slaps macOS opens slaps:// URLs with, in the background, starting it if it isn't running.
            let open = Process()
            open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            open.arguments = ["-g", url.absoluteString]
            try open.run()
            open.waitUntilExit()
            guard open.terminationStatus == 0 else {
                FileHandle.standardError.write(Data("slaps: macOS couldn't open \(url.absoluteString)\n".utf8))
                return 1
            }
            return 0
        } catch {
            FileHandle.standardError.write(Data("slaps: \(error)\n".utf8))
            return 2
        }
    }
}

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
    /// Before launch finishes, so a slaps:// URL that launched Slaps isn't missed.
    func applicationWillFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated { URLCommands.install() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            #if DEBUG
            DebugDriver.startIfAsked()   // only when launched with DEBUG_SOCKET (`just debug-app`)
            #endif
            #if !APP_STORE
            UpdateChecker.shared.start()
            #endif
            AppModel.shared.start()
            #if DEBUG
            let demo = DemoData.isOn   // screenshots open the welcome window themselves
            #else
            let demo = false
            #endif
            if !OnboardingController.isDone && !demo { OnboardingController.shared.show() }
        }
    }
}
