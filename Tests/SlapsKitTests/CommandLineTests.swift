import Foundation
import Testing
@testable import SlapsKit

private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

private func command(_ words: String...) throws -> ExternalCommand {
    let url = try #require(try SlapsCommandLine.url(for: words, now: now))
    return try ExternalCommand.parse(url, now: now)
}

@Test func anAlertFromTheCommandLineIsTheAlertAURLWouldBe() throws {
    guard case .alert(let a) = try command("alert", "Deploy done", "--in", "5", "--link", "https://ci.example.com/42",
                                           "--notes", "All green & fast") else {
        Issue.record("not an alert")
        return
    }
    #expect(a.title == "Deploy done")
    #expect(a.at == now.addingTimeInterval(300))
    #expect(a.link?.absoluteString == "https://ci.example.com/42")
    #expect(a.notes == "All green & fast", "an & stays in its value")
    #expect(a.source == "Terminal", "said to be from the Terminal unless --from says")
}

@Test func anAlertsButtonsAndCallbackComeThroughWhole() throws {
    guard case .alert(let a) = try command("alert", "Rotate the key?", "--id", "q3", "--style", "side",
                                           "--action", "Yes", "--action", "Not now",
                                           "--callback", "boiler-room://answer?question=3&answer={action}",
                                           "--from", "Boiler Room") else {
        Issue.record("not an alert")
        return
    }
    #expect(a.key == "q3")
    #expect(a.style == .side)
    #expect(a.source == "Boiler Room")
    #expect(a.actions.map(\.url.absoluteString)
            == ["boiler-room://answer?question=3&answer=Yes", "boiler-room://answer?question=3&answer=Not%20now"])
}

@Test func theOtherCommands() throws {
    #expect(try command("dismiss") == .dismiss)
    #expect(try command("dismiss", "--id", "q3") == .withdraw("q3"))
    #expect(try command("pause", "--minutes", "30") == .pause(1800))
    #expect(try command("pause") == .pause(3600))
    #expect(try command("resume") == .resume)
    #expect(try command("join") == .join)
    #expect(try SlapsCommandLine.url(for: ["help"]) == nil)
}

@Test(arguments: [
    ["alert"],                                          // no title
    ["alert", "--in", "5"],
    ["alert", "x", "--in"],                             // no value
    ["alert", "x", "--soon", "5"],                      // not an option
    ["alert", "x", "--link", "file:///etc/passwd"],     // the app's own rules
    ["alert", "x", "--action", "Yes"],                  // no callback
    ["alert", "x", "--action", "Yes, please", "--callback", "boiler-room://a?x={action}"],
    ["resume", "--minutes", "5"],
    ["explode"],
    [],
])
func refuses(_ words: [String]) {
    #expect(throws: SlapsCommandLine.Failure.self) { try SlapsCommandLine.url(for: words, now: now) }
}
