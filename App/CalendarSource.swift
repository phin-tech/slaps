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

    var access: Access {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: .granted
        case .notDetermined: .notAsked
        default: .denied
        }
    }

    /// Asks once; macOS remembers the answer, and later changes are made in System Settings.
    func requestAccess() async -> Bool {
        (try? await store.requestFullAccessToEvents()) ?? false
    }

    /// Calls `changed` whenever a calendar or event changes, here or in a synced account.
    func observeChanges(_ changed: @escaping @MainActor () -> Void) {
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { _ in
            MainActor.assumeIsolated { changed() }
        }
    }

    func calendars() -> [CalendarInfo] {
        guard access == .granted else { return [] }
        return store.calendars(for: .event)
            .map { CalendarInfo(id: $0.calendarIdentifier, title: $0.title, account: $0.source?.title ?? "Other",
                                color: Color(nsColor: $0.color)) }
            .sorted { ($0.account, $0.title) < ($1.account, $1.title) }
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
