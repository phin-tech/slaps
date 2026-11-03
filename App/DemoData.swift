#if DEBUG
import SlapsKit
import SwiftUI

/// A made-up day for screenshots (`just screenshots`): a Debug build launched with SLAPS_DEMO=1 shows these instead
/// of reading the calendar, so no one's real meetings end up in the README. Times are relative to launch, so there's
/// always one about to start.
enum DemoData {
    static let isOn = ProcessInfo.processInfo.environment["SLAPS_DEMO"] != nil

    static let calendars = [
        CalendarInfo(id: "work", title: "Work", account: "Google", color: .blue),
        CalendarInfo(id: "team", title: "Team", account: "Google", color: .purple),
        CalendarInfo(id: "home", title: "Home", account: "iCloud", color: .green),
    ]

    private static let launch = Date()

    static let meetings: [Meeting] = {
        let cal = Calendar.current
        let today = cal.startOfDay(for: launch)
        func at(_ offset: TimeInterval) -> Date { launch.addingTimeInterval(offset) }
        func day(_ d: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            cal.date(bySettingHour: hour, minute: minute, second: 0, of: cal.date(byAdding: .day, value: d, to: today)!)!
        }
        func m(_ id: String, _ title: String, _ start: Date, minutes: Double, cal calendar: String,
               link: String? = nil, people: Bool = true, recurring: Bool = false, allDay: Bool = false) -> Meeting {
            let info = calendars.first { $0.id == calendar }!
            return Meeting(id: id, seriesID: id, isRecurring: recurring, title: title, start: start,
                           end: allDay ? cal.date(byAdding: .day, value: 1, to: start)! : start.addingTimeInterval(minutes * 60),
                           isAllDay: allDay, calendarID: info.id, calendarTitle: info.title, location: link,
                           hasOtherAttendees: people)
        }
        return [
            m("release", "Release week", today, minutes: 0, cal: "team", allDay: true),
            m("standup", "Team standup", at(-3 * 3600), minutes: 15, cal: "team",
              link: "https://meet.google.com/abc-defg-hij", recurring: true),
            m("review", "Design review: onboarding", at(55), minutes: 45, cal: "work",
              link: "https://us02web.zoom.us/j/81234567890"),
            m("lunch", "Lunch", at(2 * 3600), minutes: 60, cal: "home", people: false),
            m("oneonone", "1:1 with Alex", at(3 * 3600), minutes: 30, cal: "work",
              link: "https://teams.microsoft.com/l/meetup-join/19%3ameeting_demo", recurring: true),
            m("planning", "Sprint planning", at(5 * 3600), minutes: 60, cal: "team",
              link: "https://meet.google.com/xyz-abcd-efg"),
            m("dentist", "Dentist", day(1, 9, 30), minutes: 45, cal: "home", people: false),
            m("allhands", "All hands", day(2, 16), minutes: 60, cal: "work", link: "https://us02web.zoom.us/j/8100000"),
            m("retro", "Retro", day(4, 15), minutes: 45, cal: "team", link: "https://meet.google.com/rty-uiop-asd"),
            m("offsite", "Offsite", day(8, 9), minutes: 8 * 60, cal: "work"),
            m("dinner", "Dinner with Sam", day(10, 19), minutes: 120, cal: "home", people: false),
            m("quarterly", "Quarterly review", day(15, 11), minutes: 90, cal: "work", link: "https://us02web.zoom.us/j/8200000"),
        ]
    }()

    static func meetings(from start: Date, to end: Date) -> [Meeting] {
        meetings.filter { $0.start < end && $0.end > start }
    }
}
#endif
