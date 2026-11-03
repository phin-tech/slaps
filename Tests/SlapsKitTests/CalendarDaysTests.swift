import Foundation
import Testing
@testable import SlapsKit

private let utc: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()

private func at(_ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
    utc.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
}

private func event(_ title: String, _ start: Date, _ end: Date, allDay: Bool = false) -> Meeting {
    Meeting(id: title, title: title, start: start, end: end, isAllDay: allDay)
}

@Test func busyMarksEachDayOfAnEvent() {
    let days = CalendarDays.busy([
        event("standup", at(3, 9), at(3, 9, 15)),
        event("offsite", at(10, 18), at(12, 10)),        // three days
        event("holiday", at(20), at(21), allDay: true),   // ends at the next midnight: one day
        event("marker", at(25, 12), at(25, 12)),          // no length
    ], calendar: utc)
    #expect(days == [at(3), at(10), at(11), at(12), at(20), at(25)])
}

@Test func agendaIsAllDayFirstThenByStart() {
    let items = CalendarDays.agenda([
        event("late", at(3, 16), at(3, 17)),
        event("early", at(3, 9), at(3, 10)),
        event("trip", at(2), at(5), allDay: true),
        event("tomorrow", at(4, 9), at(4, 10)),
        event("yesterday", at(2, 22), at(3)),             // ends at midnight: not today
        event("overnight", at(2, 23), at(3, 1)),
        event("marker", at(3, 12), at(3, 12)),
    ], on: at(3, 15), calendar: utc)
    #expect(items.map(\.title) == ["trip", "overnight", "early", "marker", "late"])
}
