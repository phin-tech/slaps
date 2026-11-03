import EventKit
import SlapsKit
import SwiftUI

/// A calendar, for Settings' list.
struct CalendarInfo: Identifiable, Hashable {
    var id: String
    var title: String
    var account: String
    var color: Color
}

/// Every calendar the Mac knows about, through EventKit: iCloud, and Google, Exchange or Microsoft 365 accounts
/// added in System Settings › Internet Accounts. No sign-in of Slaps's own.
@MainActor
final class CalendarSource {
    enum Access { case notAsked, granted, denied }

    private let store = EKEventStore()

    var access: Access { Self.access(.event) }
    var remindersAccess: Access { Self.access(.reminder) }

    private static func access(_ type: EKEntityType) -> Access {
        switch EKEventStore.authorizationStatus(for: type) {
        case .fullAccess: .granted
        case .notDetermined: .notAsked
        default: .denied
        }
    }

    /// Asks once; macOS remembers the answer, and later changes are made in System Settings.
    func requestAccess() async -> Bool {
        (try? await store.requestFullAccessToEvents()) ?? false
    }

    func requestRemindersAccess() async -> Bool {
        (try? await store.requestFullAccessToReminders()) ?? false
    }

    /// Calls `changed` whenever a calendar or event changes, here or in a synced account.
    func observeChanges(_ changed: @escaping @MainActor () -> Void) {
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { _ in
            MainActor.assumeIsolated { changed() }
        }
    }

    /// The calendars, then (with access) the reminder lists, each under its account.
    func calendars() -> [CalendarInfo] {
        var all: [CalendarInfo] = []
        if access == .granted {
            all += store.calendars(for: .event).map { info($0, account: $0.source?.title ?? "Other") }
        }
        if remindersAccess == .granted {
            all += store.calendars(for: .reminder).map { info($0, account: "Reminders · \($0.source?.title ?? "Other")") }
        }
        return all.sorted { ($0.account, $0.title) < ($1.account, $1.title) }
    }

    private func info(_ c: EKCalendar, account: String) -> CalendarInfo {
        CalendarInfo(id: c.calendarIdentifier, title: c.title, account: account, color: Color(nsColor: c.color))
    }

    /// Unfinished reminders due in `start..<end` at a time of day (one due on a day, with no time, gets no alert).
    func reminders(from start: Date, to end: Date) async -> [Meeting] {
        guard remindersAccess == .granted else { return [] }
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: start, ending: end, calendars: nil)
        return await withCheckedContinuation { done in
            store.fetchReminders(matching: predicate) { reminders in
                done.resume(returning: (reminders ?? []).compactMap(Self.reminderItem))
            }
        }
    }

    /// Marks a reminder done, as ticking it in Reminders would.
    func complete(reminder id: String) {
        guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else { return }
        reminder.isCompleted = true
        try? store.save(reminder, commit: true)
    }

    private nonisolated static func reminderItem(_ r: EKReminder) -> Meeting? {
        guard let components = r.dueDateComponents, components.hour != nil,
              let due = Calendar.current.date(from: components) else { return nil }
        return Meeting(
            id: "reminder:\(r.calendarItemIdentifier)@\(Int(due.timeIntervalSince1970))",
            kind: .reminder,
            seriesID: r.calendarItemIdentifier,
            title: r.title?.isEmpty == false ? r.title! : "Untitled reminder",
            start: due,
            end: due.addingTimeInterval(3600),   // how long a snooze can push it
            calendarID: r.calendar?.calendarIdentifier ?? "",
            calendarTitle: r.calendar?.title ?? "Reminders",
            notes: r.hasNotes ? r.notes : nil,
            url: r.url,
            isHighPriority: r.priority >= 1 && r.priority <= 4)   // EventKit: 1–4 high, 5 medium, 6–9 low
    }

    /// Every event occurrence overlapping `start..<end`.
    func meetings(from start: Date, to end: Date) -> [Meeting] {
        guard access == .granted else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate).map(Self.meeting)
    }

    private static func meeting(_ e: EKEvent) -> Meeting {
        let attendees = e.attendees ?? []
        return Meeting(
            id: "\(e.eventIdentifier ?? e.calendarItemIdentifier)@\(Int(e.startDate.timeIntervalSince1970))",
            seriesID: e.eventIdentifier,
            isRecurring: e.hasRecurrenceRules,
            title: e.title?.isEmpty == false ? e.title! : "Untitled event",
            start: e.startDate,
            end: e.endDate,
            isAllDay: e.isAllDay,
            calendarID: e.calendar?.calendarIdentifier ?? "",
            calendarTitle: e.calendar?.title ?? "",
            location: e.location,
            notes: e.hasNotes ? e.notes : nil,
            url: e.url,
            hasOtherAttendees: attendees.contains { !$0.isCurrentUser },
            declined: attendees.contains { $0.isCurrentUser && $0.participantStatus == .declined },
            cancelled: e.status == .canceled)
    }
}
