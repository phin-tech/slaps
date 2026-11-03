import Foundation
import Testing
@testable import SlapsKit

private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

private func meeting(_ id: String = "m", startsIn minutes: Double = 10, lasts: Double = 30, title: String = "Standup",
                     _ edit: (inout Meeting) -> Void = { _ in }) -> Meeting {
    let start = t0.addingTimeInterval(minutes * 60)
    var m = Meeting(id: id, title: title, start: start, end: start.addingTimeInterval(lasts * 60), calendarID: "work")
    edit(&m)
    return m
}

// MARK: Links

@Test(arguments: [
    ("Join: https://us02web.zoom.us/j/123456789?pwd=abc.", "Zoom", "https://us02web.zoom.us/j/123456789?pwd=abc"),
    ("https://meet.google.com/abc-defg-hij", "Google Meet", "https://meet.google.com/abc-defg-hij"),
    ("<https://teams.microsoft.com/l/meetup-join/19%3ameeting_x%40thread.v2/0?context=%7b%7d>", "Microsoft Teams",
     "https://teams.microsoft.com/l/meetup-join/19%3ameeting_x%40thread.v2/0?context=%7b%7d"),
    ("(https://acme.webex.com/meet/sam)", "Webex", "https://acme.webex.com/meet/sam"),
    ("call https://facetime.apple.com/join#v=1&p=xyz", "FaceTime", "https://facetime.apple.com/join#v=1&p=xyz"),
])
func findsLinks(text: String, service: String, url: String) {
    let link = MeetingLink.find(in: text)
    #expect(link?.service == service)
    #expect(link?.url.absoluteString == url)
}

@Test func ignoresOrdinaryLinks() {
    #expect(MeetingLink.find(in: "Agenda: https://docs.google.com/document/d/1") == nil)
    #expect(MeetingLink.find(in: "") == nil)
}

@Test func takesTheEarliestLinkInText() {
    let text = "Dial in https://meet.google.com/abc-defg-hij or https://zoom.us/j/1"
    #expect(MeetingLink.find(in: text)?.service == "Google Meet")
}

@Test func prefersTheURLFieldThenLocationThenNotes() {
    let m = meeting {
        $0.notes = "https://zoom.us/j/1"
        $0.location = "https://meet.google.com/abc-defg-hij"
    }
    #expect(m.link?.service == "Google Meet")
    var n = m
    n.location = "Room 4"
    #expect(n.link?.service == "Zoom")
}

// MARK: Filter

@Test func filterDefaults() {
    let f = AlertFilter()
    #expect(f.allows(meeting()))
    #expect(!f.allows(meeting { $0.isAllDay = true }))
    #expect(!f.allows(meeting { $0.declined = true }))
    #expect(!f.allows(meeting { $0.cancelled = true }))
}

@Test func filterOptions() {
    var f = AlertFilter()
    f.excludedCalendarIDs = ["work"]
    #expect(!f.allows(meeting()))
    f = AlertFilter()
    f.requireOtherAttendees = true
    #expect(!f.allows(meeting()))
    #expect(f.allows(meeting { $0.hasOtherAttendees = true }))
    f = AlertFilter()
    f.requireLink = true
    #expect(!f.allows(meeting()))
    #expect(f.allows(meeting { $0.location = "https://zoom.us/j/9" }))
    f = AlertFilter()
    f.ignoredTitleWords = [" lunch ", ""]
    #expect(!f.allows(meeting(title: "Team LUNCH")))
    #expect(f.allows(meeting(title: "Launch review")))
}

@Test func filterDecodesOlderSettings() throws {
    let f = try JSONDecoder().decode(AlertFilter.self, from: Data(#"{"includeAllDay": true}"#.utf8))
    #expect(f.includeAllDay)
    #expect(f.ignoredTitleWords.isEmpty)
}

// MARK: Schedule

@Test func firesLeadTimeBeforeStart() {
    let s = AlertSchedule(leadTime: 120)
    let m = meeting(startsIn: 10)
    #expect(s.fireDate(for: m, state: AlertState()) == m.start.addingTimeInterval(-120))
    #expect(s.due([m], at: t0, state: AlertState()).isEmpty)
    #expect(s.due([m], at: t0.addingTimeInterval(8 * 60), state: AlertState()) == [m])
    #expect(s.nextFire([m], after: t0, state: AlertState()) == t0.addingTimeInterval(8 * 60))
}

@Test func stillAlertsJustAfterStartButNotLongAfter() {
    let s = AlertSchedule(leadTime: 60, grace: 300)
    let m = meeting(startsIn: -4)
    #expect(s.due([m], at: t0, state: AlertState()) == [m])
    let old = meeting(startsIn: -6)
    #expect(s.due([old], at: t0, state: AlertState()).isEmpty)
    #expect(s.nextFire([meeting(startsIn: -40)], after: t0, state: AlertState()) == nil)
}

@Test func dismissedNeverFiresAgain() {
    let s = AlertSchedule()
    let m = meeting(startsIn: 0)
    var state = AlertState()
    state.dismiss(m.id)
    #expect(s.due([m], at: t0, state: state).isEmpty)
    #expect(s.nextFire([m], after: t0, state: state) == nil)
}

@Test func snoozeFiresLaterEvenPastGrace() {
    let s = AlertSchedule(grace: 60)
    let m = meeting(startsIn: 0, lasts: 30)
    var state = AlertState()
    state.snooze(m.id, until: t0.addingTimeInterval(10 * 60))
    #expect(s.due([m], at: t0.addingTimeInterval(5 * 60), state: state).isEmpty)
    #expect(s.due([m], at: t0.addingTimeInterval(10 * 60), state: state) == [m])
    #expect(s.due([m], at: t0.addingTimeInterval(31 * 60), state: state).isEmpty)
    state.snooze(m.id, until: t0.addingTimeInterval(40 * 60))   // past the end
    #expect(s.fireDate(for: m, state: state) == nil)
}

@Test func dueIsInStartOrder() {
    let s = AlertSchedule(leadTime: 600)
    let a = meeting("a", startsIn: 5), b = meeting("b", startsIn: 1)
    #expect(s.due([a, b], at: t0, state: AlertState()).map(\.id) == ["b", "a"])
}

@Test func stateForgetsMeetingsThatAreGone() {
    var state = AlertState()
    state.dismiss("a")
    state.snooze("b", until: t0)
    state.keepOnly(["b"])
    #expect(state.dismissed.isEmpty)
    #expect(state.snoozed.keys.sorted() == ["b"])
}

// MARK: Reminders

@Test func remindersOnlyWhenAskedFor() {
    var f = AlertFilter()
    let r = meeting { $0.kind = .reminder }
    #expect(!f.allows(r))
    f.includeReminders = true
    f.requireLink = true                 // event-only rules don't apply to reminders
    f.requireOtherAttendees = true
    #expect(f.allows(r))
    f.onlyHighPriorityReminders = true
    #expect(!f.allows(r))
    #expect(f.allows(meeting { $0.kind = .reminder; $0.isHighPriority = true }))
    f.excludedCalendarIDs = ["work"]     // a reminder list switched off
    #expect(!f.allows(meeting { $0.kind = .reminder; $0.isHighPriority = true }))
}

@Test func remindersFireAtTheirDueTime() {
    let s = AlertSchedule(leadTime: 600)
    let r = meeting(startsIn: 10) { $0.kind = .reminder }
    #expect(s.fireDate(for: r, state: AlertState()) == r.start)
}

// MARK: Overrides

@Test func overrideSkipsOrChangesLeadTime() {
    let s = AlertSchedule(leadTime: 60)
    let m = meeting(startsIn: 10) { $0.seriesID = "weekly" }
    var o = Overrides()
    o.set(.skip, for: m, scope: .occurrence)
    #expect(s.fireDate(for: m, state: AlertState(), overrides: o) == nil)
    o.set(.leadTime(300), for: m, scope: .occurrence)
    #expect(s.fireDate(for: m, state: AlertState(), overrides: o) == m.start.addingTimeInterval(-300))
    #expect(o.scope(for: m) == .occurrence)
}

@Test func seriesOverrideCoversOtherOccurrences() {
    let a = meeting("a", startsIn: 10) { $0.seriesID = "weekly" }
    let b = meeting("b", startsIn: 10_080) { $0.seriesID = "weekly" }
    var o = Overrides()
    o.set(.skip, for: a, scope: .occurrence)
    o.set(.leadTime(600), for: a, scope: .series)   // replaces a's own
    #expect(o.override(for: a) == .leadTime(600))
    #expect(o.override(for: b) == .leadTime(600))
    o.set(.skip, for: b, scope: .occurrence)          // one occurrence differs from the series
    #expect(o.override(for: b) == .skip)
    o.set(nil, for: a, scope: .series)
    #expect(o.override(for: a) == nil)
    #expect(o.override(for: b) == .skip)
}

@Test func overrideWithoutSeriesFallsBackToOccurrence() {
    let m = meeting()
    var o = Overrides()
    o.set(.skip, for: m, scope: .series)
    #expect(o.scope(for: m) == .occurrence)
}

@Test func overridesOfPastOccurrencesAreForgotten() throws {
    let m = meeting(startsIn: 0, lasts: 30)
    var o = Overrides()
    o.set(.skip, for: m, scope: .occurrence)
    o.prune(before: t0.addingTimeInterval(29 * 60))
    #expect(o.override(for: m) == .skip)
    o.prune(before: t0.addingTimeInterval(31 * 60))
    #expect(o.override(for: m) == nil)
    let round = try JSONDecoder().decode(Overrides.self, from: JSONEncoder().encode(o))
    #expect(round == o)
}

@Test func dismissingEarlyCanAlertAgainAtStart() {
    let s = AlertSchedule(leadTime: 600)
    let m = meeting(startsIn: 10)
    #expect(s.dismissal(of: m, at: t0, againAtStart: false) == nil)
    #expect(s.dismissal(of: m, at: t0, againAtStart: true) == m.start)
    #expect(s.dismissal(of: m, at: m.start.addingTimeInterval(-20), againAtStart: true) == nil)   // nearly started
    #expect(s.dismissal(of: meeting(startsIn: 10) { $0.kind = .reminder }, at: t0, againAtStart: true) == nil)
    var state = AlertState()                                     // the app snoozes until then
    state.snooze(m.id, until: m.start)
    #expect(s.due([m], at: m.start, state: state) == [m])
}
