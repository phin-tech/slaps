import Foundation

/// One occurrence of a calendar event, or a reminder with a due time, copied out of EventKit so the rules about it can
/// be tested without a calendar.
public struct Meeting: Identifiable, Hashable, Sendable {
    /// A calendar event, a reminder, or an alert another app asked for (`ExternalCommand`).
    public enum Kind: String, Hashable, Sendable { case event, reminder, custom }

    /// Unique per occurrence: a repeating event's occurrences share EventKit's identifier, so the start is part of it.
    public var id: String
    public var kind: Kind
    /// Shared by every occurrence of a repeating event (EventKit's identifier), for overrides that apply to them all.
    /// For a reminder, its calendar item identifier, which completing it needs.
    public var seriesID: String?
    /// One occurrence of a repeating event.
    public var isRecurring: Bool
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
    /// A reminder marked high priority.
    public var isHighPriority: Bool
    /// For an alert another app asked for: how much of the screen it takes, over the setting.
    public var style: AlertStyle?
    /// For an alert another app asked for: buttons that answer it, each opening that app's URL.
    public var actions: [ExternalAction]

    public init(id: String, kind: Kind = .event, seriesID: String? = nil, isRecurring: Bool = false, title: String,
                start: Date, end: Date, isAllDay: Bool = false, calendarID: String = "",
                calendarTitle: String = "", location: String? = nil, notes: String? = nil, url: URL? = nil,
                hasOtherAttendees: Bool = false, declined: Bool = false, cancelled: Bool = false,
                isHighPriority: Bool = false, style: AlertStyle? = nil, actions: [ExternalAction] = []) {
        self.style = style
        self.actions = actions
        self.id = id
        self.kind = kind
        self.seriesID = seriesID
        self.isRecurring = isRecurring
        self.isHighPriority = isHighPriority
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
