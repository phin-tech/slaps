import Foundation

/// One occurrence of a calendar event, copied out of EventKit so the rules about it can be tested without a calendar.
public struct Meeting: Identifiable, Hashable, Sendable {
    /// Unique per occurrence: a repeating event's occurrences share EventKit's identifier, so the start is part of it.
    public var id: String
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var calendarID: String
    public var calendarTitle: String
    public var location: String?
    public var notes: String?
    public var url: URL?
    /// Someone besides you is invited.
    public var hasOtherAttendees: Bool
    /// You said no.
    public var declined: Bool
    public var cancelled: Bool

    public init(id: String, title: String, start: Date, end: Date, isAllDay: Bool = false, calendarID: String = "",
                calendarTitle: String = "", location: String? = nil, notes: String? = nil, url: URL? = nil,
                hasOtherAttendees: Bool = false, declined: Bool = false, cancelled: Bool = false) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.calendarID = calendarID
        self.calendarTitle = calendarTitle
        self.location = location
        self.notes = notes
        self.url = url
        self.hasOtherAttendees = hasOtherAttendees
        self.declined = declined
        self.cancelled = cancelled
    }

    /// The video call to join, from the event's URL, then its location, then its notes.
    public var link: MeetingLink? {
        MeetingLink.first(in: [url?.absoluteString, location, notes])
    }
}
