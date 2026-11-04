import Foundation

/// The Mac's internal battery, as IOKit reports it.
public struct BatteryReading: Equatable, Sendable {
    /// 0 to 100.
    public var percent: Int
    /// Plugged in, whether or not it's charging.
    public var onPower: Bool

    public init(percent: Int, onPower: Bool) {
        self.percent = percent
        self.onPower = onPower
    }
}

/// When to warn that the battery is low: once each time it runs down to the level, on battery. Plugging in, or
/// changing the level, lets it warn again.
public struct BatteryWatch: Equatable, Sendable {
    public enum Change: Equatable, Sendable {
        case none
        /// Put up the alert.
        case warn
        /// Plugged in: take down an alert that's up.
        case clear
    }

    /// Warn at this percentage or below.
    public var level: Int {
        didSet { if level != oldValue { armed = true } }
    }
    public private(set) var armed = true

    public init(level: Int) {
        self.level = level
    }

    /// What to do about a new reading. Nil (no battery, or IOKit didn't say) changes nothing.
    public mutating func update(_ reading: BatteryReading?) -> Change {
        guard let reading else { return .none }
        if reading.onPower {
            armed = true
            return .clear
        }
        guard armed, reading.percent <= level else { return .none }
        armed = false
        return .warn
    }

    /// The alert, as a Meeting, so it's shown, snoozed and dismissed like the rest.
    public static func alert(for reading: BatteryReading, at now: Date) -> Meeting {
        Meeting(id: "battery-\(Int(now.timeIntervalSince1970))", kind: .custom, title: "Battery at \(reading.percent)%",
                start: now, end: now.addingTimeInterval(3600), calendarTitle: "",
                notes: "Plug in your Mac")
    }

    public static func isAlert(_ meeting: Meeting) -> Bool {
        meeting.kind == .custom && meeting.id.hasPrefix("battery-")
    }
}
