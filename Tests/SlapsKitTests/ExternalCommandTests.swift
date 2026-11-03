import Foundation
import Testing
@testable import SlapsKit

private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

private func parse(_ s: String) throws -> ExternalCommand {
    try ExternalCommand.parse(URL(string: s)!, now: now)
}

private func alert(_ s: String) throws -> ExternalAlert {
    guard case .alert(let a) = try parse(s) else { throw ExternalCommand.Failure("not an alert") }
    return a
}

@Test func alertNowWithTitle() throws {
    let a = try alert("slaps://alert?title=Deploy%20done")
    #expect(a.title == "Deploy done")
    #expect(a.at == now)
    #expect(a.link == nil)
}

@Test func alertLaterWithLinkNotesAndSource() throws {
    let a = try alert("slaps://alert?title=Standup&in=5&link=https://zoom.us/j/1&notes=Bring%20numbers&source=Shortcuts")
    #expect(a.at == now.addingTimeInterval(300))
    #expect(a.link?.absoluteString == "https://zoom.us/j/1")
    #expect(a.notes == "Bring numbers")
    let m = a.meeting(id: "x")
    #expect(m.kind == .custom)
    #expect(m.calendarTitle == "Shortcuts")
    #expect(m.link?.service == "Zoom")
}

@Test func alertAtATime() throws {
    #expect(try alert("slaps://alert?title=Call&at=2026-05-10T06:00:00Z").at
            == ISO8601DateFormatter().date(from: "2026-05-10T06:00:00Z"))
    #expect(try alert("slaps:alert?title=Call").title == "Call")    // without the slashes
}

@Test(arguments: [
    "slaps://alert",                                       // no title
    "slaps://alert?title=%20%20",
    "slaps://alert?title=x&in=soon",
    "slaps://alert?title=x&in=-1",
    "slaps://alert?title=x&at=tomorrow",
    "slaps://alert?title=x&in=20000",                      // more than a week
    "slaps://alert?title=x&link=file:///etc/passwd",       // only web links
    "slaps://alert?title=x&link=zoommtg://zoom.us/join",
    "slaps://alert?title=x&link=https://",
    "slaps://pause?minutes=0",
    "slaps://explode",
    "https://example.com/alert?title=x",
])
func rejects(_ s: String) {
    #expect(throws: ExternalCommand.Failure.self) { try parse(s) }
}

@Test func otherCommands() throws {
    #expect(try parse("slaps://pause") == .pause(3600))
    #expect(try parse("slaps://pause?minutes=30") == .pause(1800))
    #expect(try parse("slaps://RESUME") == .resume)
    #expect(try parse("slaps://dismiss") == .dismiss)
    #expect(try parse("slaps://join") == .join)
}

@Test func customAlertsFireAtTheirTimeWhateverTheFilter() throws {
    var f = AlertFilter()
    f.requireLink = true
    f.ignoredTitleWords = ["deploy"]
    let m = try ExternalAlert(title: "Deploy", at: now.addingTimeInterval(120), now: now).meeting(id: "x")
    #expect(f.allows(m))
    #expect(AlertSchedule(leadTime: 600).fireDate(for: m, state: AlertState()) == m.start)
}
