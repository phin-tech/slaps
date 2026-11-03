import Foundation

/// A different rule for one event, or for every occurrence of a repeating one.
public enum AlertOverride: Codable, Hashable, Sendable {
    /// No alert.
    case skip
    /// An alert this long before the start, instead of the usual lead time.
    case leadTime(TimeInterval)
}

/// The overrides set from the menu, kept in the settings.
public struct Overrides: Codable, Equatable, Sendable {
    public enum Scope: Sendable { case occurrence, series }

    /// An override of one occurrence, with when it stops mattering (the meeting's end), so it can be forgotten.
    public struct Entry: Codable, Equatable, Sendable {
        public var override: AlertOverride
        public var expires: Date
    }

    public private(set) var occurrences: [String: Entry] = [:]
    public private(set) var series: [String: AlertOverride] = [:]

    public init() {}

    /// The occurrence's own override wins over its series'.
    public func override(for meeting: Meeting) -> AlertOverride? {
        occurrences[meeting.id]?.override ?? meeting.seriesID.flatMap { series[$0] }
    }

    /// The scope the meeting's override was set at, if it has one.
    public func scope(for meeting: Meeting) -> Scope? {
        if occurrences[meeting.id] != nil { return .occurrence }
        if let s = meeting.seriesID, series[s] != nil { return .series }
        return nil
    }

    /// Sets, or with nil clears, the override of `meeting` alone or of its whole series. Clearing the series also
    /// clears this occurrence's own, so the meeting is back to the usual rule.
    public mutating func set(_ override: AlertOverride?, for meeting: Meeting, scope: Scope) {
        switch scope {
        case .occurrence:
            occurrences[meeting.id] = override.map { Entry(override: $0, expires: meeting.end) }
        case .series:
            guard let s = meeting.seriesID else {
                return set(override, for: meeting, scope: .occurrence)
            }
            series[s] = override
            occurrences[meeting.id] = nil
        }
    }

    /// Forgets overrides of occurrences that are over. Series overrides stay until cleared.
    public mutating func prune(before now: Date) {
        occurrences = occurrences.filter { $0.value.expires > now }
    }
}
