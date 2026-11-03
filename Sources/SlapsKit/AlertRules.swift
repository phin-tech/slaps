import Foundation

/// Which meetings get an alert at all.
public struct AlertFilter: Codable, Equatable, Sendable {
    /// Calendars switched off in Settings.
    public var excludedCalendarIDs: Set<String> = []
    public var includeAllDay = false
    public var includeDeclined = false
    /// Skip events only you are in (focus blocks, reminders to yourself).
    public var requireOtherAttendees = false
    /// Skip events without a call link.
    public var requireLink = false
    /// Skip events whose title contains any of these, ignoring case ("Lunch", "OOO").
    public var ignoredTitleWords: [String] = []
    /// Alert for reminders with a due time, at that time.
    public var includeReminders = false
    /// Of those, only the ones marked high priority.
    public var onlyHighPriorityReminders = false

    public init() {}

    public func allows(_ meeting: Meeting) -> Bool {
        if meeting.cancelled { return false }
        if excludedCalendarIDs.contains(meeting.calendarID) { return false }
        if meeting.kind == .reminder {
            return includeReminders && (meeting.isHighPriority || !onlyHighPriorityReminders) && !ignoredTitle(meeting)
        }
        if meeting.isAllDay && !includeAllDay { return false }
        if meeting.declined && !includeDeclined { return false }
        if requireOtherAttendees && !meeting.hasOtherAttendees { return false }
        if requireLink && meeting.link == nil { return false }
        return !ignoredTitle(meeting)
    }

    private func ignoredTitle(_ meeting: Meeting) -> Bool {
        let title = meeting.title.lowercased()
        return ignoredTitleWords.contains { word in
            let w = word.trimmingCharacters(in: .whitespaces).lowercased()
            return !w.isEmpty && title.contains(w)
        }
    }

    // Decoding fills keys a newer version added with their defaults, so saved settings survive an update.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AlertFilter()
        excludedCalendarIDs = try c.decodeIfPresent(Set<String>.self, forKey: .excludedCalendarIDs) ?? d.excludedCalendarIDs
        includeAllDay = try c.decodeIfPresent(Bool.self, forKey: .includeAllDay) ?? d.includeAllDay
        includeDeclined = try c.decodeIfPresent(Bool.self, forKey: .includeDeclined) ?? d.includeDeclined
        requireOtherAttendees = try c.decodeIfPresent(Bool.self, forKey: .requireOtherAttendees) ?? d.requireOtherAttendees
        requireLink = try c.decodeIfPresent(Bool.self, forKey: .requireLink) ?? d.requireLink
        ignoredTitleWords = try c.decodeIfPresent([String].self, forKey: .ignoredTitleWords) ?? d.ignoredTitleWords
        includeReminders = try c.decodeIfPresent(Bool.self, forKey: .includeReminders) ?? d.includeReminders
        onlyHighPriorityReminders = try c.decodeIfPresent(Bool.self, forKey: .onlyHighPriorityReminders)
            ?? d.onlyHighPriorityReminders
    }
}

/// What has happened to each alert: dismissed, or snoozed until when. Keyed by `Meeting.id`.
public struct AlertState: Equatable, Sendable {
    public private(set) var dismissed: Set<String> = []
    public private(set) var snoozed: [String: Date] = [:]

    public init() {}

    public mutating func dismiss(_ id: String) {
        dismissed.insert(id)
        snoozed[id] = nil
    }

    public mutating func snooze(_ id: String, until: Date) {
        snoozed[id] = until
    }

    /// Forgets meetings that are no longer in the calendar window, so the state doesn't grow forever.
    public mutating func keepOnly(_ ids: Set<String>) {
        dismissed.formIntersection(ids)
        snoozed = snoozed.filter { ids.contains($0.key) }
    }
}

/// When alerts fire. Pure: the app passes in the clock.
public struct AlertSchedule: Equatable, Sendable {
    /// How long before the start the alert goes up.
    public var leadTime: TimeInterval
    /// How long after the start a meeting that was never alerted still gets one (the Mac was asleep, or Slaps was
    /// just launched). Past this it is left alone.
    public var grace: TimeInterval

    public init(leadTime: TimeInterval = 60, grace: TimeInterval = 5 * 60) {
        self.leadTime = leadTime
        self.grace = grace
    }

    /// When `meeting`'s alert goes up (possibly in the past), or nil if it never does: dismissed, snoozed past its end,
    /// or a lead time so negative it would fire after the grace period.
    public func fireDate(for meeting: Meeting, state: AlertState, overrides: Overrides = Overrides()) -> Date? {
        if state.dismissed.contains(meeting.id) { return nil }
        if let until = state.snoozed[meeting.id] {
            return until < meeting.end ? until : nil
        }
        let lead: TimeInterval
        switch overrides.override(for: meeting) {
        case .skip: return nil
        case .leadTime(let t): lead = t
        case nil: lead = meeting.kind == .reminder ? 0 : leadTime   // a reminder is due at its time
        }
        let latest = min(meeting.start.addingTimeInterval(grace), meeting.end)
        let fire = meeting.start.addingTimeInterval(-lead)
        return fire < latest ? fire : nil
    }

    /// The meetings whose alert should be showing at `now`, earliest start first.
    public func due(_ meetings: [Meeting], at now: Date, state: AlertState,
                    overrides: Overrides = Overrides()) -> [Meeting] {
        meetings.filter { m in
            guard let fire = fireDate(for: m, state: state, overrides: overrides), fire <= now else { return false }
            let latest = state.snoozed[m.id] != nil ? m.end : min(m.start.addingTimeInterval(grace), m.end)
            return now < latest
        }
        .sorted { ($0.start, $0.title) < ($1.start, $1.title) }
    }

    /// The next time an alert goes up after `now`, for scheduling a wake-up.
    public func nextFire(_ meetings: [Meeting], after now: Date, state: AlertState,
                         overrides: Overrides = Overrides()) -> Date? {
        meetings.compactMap { fireDate(for: $0, state: state, overrides: overrides) }.filter { $0 > now }.min()
    }
}
