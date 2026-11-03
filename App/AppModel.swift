import AppKit
import Observation
import SlapsKit

/// Slaps's state: the meetings ahead, the settings, and which alerts are up. Checks the clock every few seconds and
/// puts up the overlay when a meeting is due.
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    @ObservationIgnored let calendar = CalendarSource()
    @ObservationIgnored private let overlay = OverlayController()
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private var lastFetch = Date.distantPast
    @ObservationIgnored private var started = false

    /// Every event occurrence from an hour ago to a day ahead, before filtering.
    private(set) var meetings: [Meeting] = []
    private(set) var calendars: [CalendarInfo] = []
    private(set) var access: CalendarSource.Access = .notAsked
    /// The clock as of the last tick, so views that count down redraw with it.
    private(set) var now = Date()
    /// The meetings on screen in the overlay.
    private(set) var alerting: [Meeting] = []
    private(set) var state = AlertState()
    /// A pretend meeting from Test Alert, which is never in the calendar.
    private var testMeeting: Meeting?

    var leadTime: TimeInterval { didSet { defaults.set(leadTime, forKey: PrefKey.leadTime); tick() } }
    var sound: String { didSet { defaults.set(sound, forKey: PrefKey.sound) } }
    var theme: Theme { didSet { defaults.set(theme.rawValue, forKey: PrefKey.theme) } }
    var filter: AlertFilter { didSet { defaults.alertFilter = filter; tick() } }
    private(set) var pausedUntil: Date? { didSet { defaults.set(pausedUntil, forKey: PrefKey.pausedUntil) } }

    private init() {
        leadTime = defaults.object(forKey: PrefKey.leadTime) as? Double ?? 60
        sound = defaults.string(forKey: PrefKey.sound) ?? "Glass"
        theme = defaults.string(forKey: PrefKey.theme).flatMap(Theme.init(rawValue:)) ?? .midnight
        filter = defaults.alertFilter
        pausedUntil = defaults.object(forKey: PrefKey.pausedUntil) as? Date
    }

    var schedule: AlertSchedule { AlertSchedule(leadTime: leadTime) }

    /// Meetings that pass the filter and haven't ended, soonest first.
    var upcoming: [Meeting] {
        meetings.filter { filter.allows($0) && $0.end > now }.sorted { $0.start < $1.start }
    }

    /// The next meeting that hasn't started yet.
    var next: Meeting? { upcoming.first { $0.start > now } }

    var isPaused: Bool { pausedUntil.map { $0 > now } ?? false }

    // MARK: Running

    func start() {
        guard !started else { return }
        started = true
        calendar.observeChanges { [weak self] in self?.fetch() }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil,
                                                          queue: .main) { _ in
            MainActor.assumeIsolated { AppModel.shared.fetch() }
        }
        Task {
            if calendar.access == .notAsked { _ = await calendar.requestAccess() }
            fetch()
            while !Task.isCancelled {
                tick()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    func requestAccess() {
        Task {
            if calendar.access == .notAsked {
                _ = await calendar.requestAccess()
            } else {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
            }
            fetch()
        }
    }

    /// Reads the calendars again.
    func fetch() {
        now = Date()
        access = calendar.access
        calendars = calendar.calendars()
        meetings = calendar.meetings(from: now.addingTimeInterval(-3600), to: now.addingTimeInterval(24 * 3600))
        state.keepOnly(Set(meetings.map(\.id)))
        lastFetch = now
        tick()
    }

    /// Puts up, changes or takes down the overlay to match the clock.
    func tick() {
        now = Date()
        if now.timeIntervalSince(lastFetch) > 5 * 60 { fetch(); return }
        if let until = pausedUntil, until <= now { pausedUntil = nil }
        var due = isPaused ? [] : schedule.due(upcoming, at: now, state: state)
        if let testMeeting { due.insert(testMeeting, at: 0) }
        guard due.map(\.id) != alerting.map(\.id) else { return }
        let isNew = !Set(due.map(\.id)).isSubset(of: Set(alerting.map(\.id)))
        alerting = due
        if alerting.isEmpty {
            overlay.hide()
        } else {
            overlay.show()
            if isNew { AlertSound.play(sound) }
        }
    }

    // MARK: Actions

    func join(_ meeting: Meeting) {
        if let url = meeting.link?.url { NSWorkspace.shared.open(url) }
        dismiss([meeting])
    }

    func dismiss(_ meetings: [Meeting]) {
        for m in meetings {
            if m.id == testMeeting?.id { testMeeting = nil } else { state.dismiss(m.id) }
        }
        tick()
    }

    func snooze(_ meetings: [Meeting], until date: Date) {
        for m in meetings {
            if m.id == testMeeting?.id { testMeeting = nil } else { state.snooze(m.id, until: date) }
        }
        tick()
    }

    func pause(for interval: TimeInterval) {
        pausedUntil = Date().addingTimeInterval(interval)
        tick()
    }

    func pauseUntilTomorrow() {
        pausedUntil = Calendar.current.startOfDay(for: Date().addingTimeInterval(24 * 3600))
        tick()
    }

    func resume() {
        pausedUntil = nil
        tick()
    }

    /// Puts up an alert for a meeting that isn't real, to see the theme and sound.
    func testAlert() {
        let start = Date().addingTimeInterval(leadTime)
        testMeeting = Meeting(id: "test-\(UUID())", title: "Test alert", start: start, end: start.addingTimeInterval(1800),
                              calendarTitle: "Slaps", location: "https://meet.google.com/abc-defg-hij")
        tick()
    }
}
