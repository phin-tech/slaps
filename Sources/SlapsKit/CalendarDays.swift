import Foundation

/// Which days events fall on, for the month calendar and its agenda.
public enum CalendarDays {
    /// The start of every day that has part of an event on it. An event ending exactly at midnight doesn't mark the
    /// next day (all-day events end at the next midnight); one with no length marks its own day.
    public static func busy(_ meetings: [Meeting], calendar: Calendar = .current) -> Set<Date> {
        var days = Set<Date>()
        for m in meetings {
            var day = calendar.startOfDay(for: m.start)
            days.insert(day)
            // Capped, so an event years long can't stall the popover.
            for _ in 0..<62 {
                guard let next = calendar.date(byAdding: .day, value: 1, to: day), next < m.end else { break }
                day = next
                days.insert(day)
            }
        }
        return days
    }

    /// The events on `day`: all-day ones first, then by start, then title.
    public static func agenda(_ meetings: [Meeting], on day: Date, calendar: Calendar = .current) -> [Meeting] {
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        return meetings
            .filter { $0.start < end && ($0.end > start || ($0.end == $0.start && $0.start >= start)) }
            .sorted { ($0.isAllDay ? 0 : 1, $0.start, $0.title) < ($1.isAllDay ? 0 : 1, $1.start, $1.title) }
    }
}
