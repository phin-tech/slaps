import AppKit
import SlapsKit

/// `slaps://` URLs, from `open`, Shortcuts, Raycast or any app. Taken as an Apple event, so it works before (and
/// without) any window or SwiftUI scene that `onOpenURL` would need.
@MainActor
enum URLCommands {
    static func install() {
        NSAppleEventManager.shared().setEventHandler(
            Handler.shared, andSelector: #selector(Handler.handle(_:reply:)),
            forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
    }

    final class Handler: NSObject, Sendable {
        static let shared = Handler()

        @objc func handle(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
            guard let string = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
                  let url = URL(string: string) else { return }
            MainActor.assumeIsolated {
                do {
                    try AppModel.shared.perform(ExternalCommand.parse(url, now: Date()))
                } catch {
                    // A URL has no one to answer, so say why in the log (Console, or `log stream --process Slaps`).
                    NSLog("Slaps: ignored %@: %@", string, "\(error)")
                }
            }
        }
    }
}

// MARK: AppleScript
//
// The commands in Resources/Slaps.sdef. Cocoa scripting runs them on the main thread; a failure is returned to the
// script as an error.

/// show alert "Deploy done" [in minutes 5 | at date] [link "https://…"] [notes "…"] [from "…"] [id "…"] [style "banner"]
@objc(SlapsShowAlertCommand)
final class SlapsShowAlertCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        let args = evaluatedArguments ?? [:]
        let title = directParameter as? String ?? ""
        return run {
            let now = Date()
            var at = now
            if let date = args["date"] as? Date { at = date }
            else if let minutes = (args["minutes"] as? NSNumber)?.doubleValue { at = now.addingTimeInterval(minutes * 60) }
            let style = try (args["style"] as? String).map { name -> AlertStyle in
                guard let style = AlertStyle(external: name) else {
                    throw ExternalCommand.Failure("style is fullscreen, banner, top or bottom")
                }
                return style
            }
            return try .alert(ExternalAlert(title: title, at: at, link: args["link"] as? String,
                                            notes: args["notes"] as? String,
                                            source: args["source"] as? String ?? "AppleScript",
                                            key: args["key"] as? String, style: style, now: now))
        }
    }
}

/// pause alerts [for minutes 30]
@objc(SlapsPauseCommand)
final class SlapsPauseCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        let minutes = (evaluatedArguments?["minutes"] as? NSNumber)?.doubleValue
        return run {
            guard let minutes else { return .pause(3600) }
            guard minutes > 0 else { throw ExternalCommand.Failure("minutes must be more than 0") }
            return .pause(minutes * 60)
        }
    }
}

@objc(SlapsResumeCommand)
final class SlapsResumeCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? { run { .resume } }
}

/// dismiss alert [id "…"]: the one on screen, or the one sent with that id, up or not.
@objc(SlapsDismissCommand)
final class SlapsDismissCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        let key = evaluatedArguments?["key"] as? String
        return run {
            guard let key else { return .dismiss }
            return .withdraw(try ExternalAlert.checkedKey(key))
        }
    }
}

@objc(SlapsJoinCommand)
final class SlapsJoinCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? { run { .join } }
}

extension NSScriptCommand {
    /// Makes the command, performs it on the main actor, and turns a failure into the script's error. Only the
    /// command crosses to the main actor, not the NSScriptCommand.
    fileprivate func run(_ make: () throws -> ExternalCommand) -> Any? {
        let failure: String?
        do {
            let command = try make()
            failure = MainActor.assumeIsolated { () -> String? in
                do {
                    try AppModel.shared.perform(command)
                    return nil
                } catch {
                    return (error as? ExternalCommand.Failure)?.description ?? "\(error)"
                }
            }
        } catch {
            failure = (error as? ExternalCommand.Failure)?.description ?? "\(error)"
        }
        if let failure {
            scriptErrorNumber = errAEEventFailed
            scriptErrorString = failure
        }
        return nil
    }
}
