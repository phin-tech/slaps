import AppKit
import Observation
import SlapsKit

/// Slaps's state: the meetings and reminders ahead, the settings, and which alerts are up. Checks the clock every few
/// seconds and puts up the overlay when something is due.
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    @ObservationIgnored let calendar = CalendarSource()
    @ObservationIgnored private let overlay = OverlayController()
    @ObservationIgnored private let hotKeys = HotKeys()
    @ObservationIgnored let tabsController = TabsController()
    /// The settings. A demo copy (`just screenshots`) keeps its own, so it can't change yours.
    @ObservationIgnored private let defaults: UserDefaults = {
        #if DEBUG
        if DemoData.isOn { return UserDefaults(suiteName: "tech.phin.slaps.demo")! }
        #endif
        return .standard
    }()
    @ObservationIgnored private var lastFetch = Date.distantPast
    @ObservationIgnored private var started = false

    /// Every event occurrence from an hour ago to a day ahead, and reminders due then, before filtering.
    private(set) var meetings: [Meeting] = []
    private(set) var calendars: [CalendarInfo] = []
    private(set) var access: CalendarSource.Access = .notAsked
    private(set) var remindersAccess: CalendarSource.Access = .notAsked
    /// The clock as of the last tick, so views that count down redraw with it.
    private(set) var now = Date()
    /// The meetings on screen in the overlay.
    private(set) var alerting: [Meeting] = []
    /// Due, but held back because the screen is being shared.
    private(set) var heldForSharing: [Meeting] = []
    private(set) var state = AlertState()
    /// Held alerts you asked to see anyway.
    @ObservationIgnored private var shownDespiteSharing: Set<String> = []
    /// Events the calendar popover has read, unfiltered, by the month they were read for (with a week either side).
    @ObservationIgnored private var monthCache: [Date: [Meeting]] = [:]
    /// Alerts other apps asked for (`slaps://alert`, AppleScript), until they're over. Not kept across a quit.
    private(set) var customAlerts: [Meeting] = []
    /// The Tabs on the edge of the screen (`TabsPanel.swift`), kept across a quit.
    private(set) var tabBoard: TabBoard { didSet { saveTabs() } }
    /// Tabs escalated into the Slap that's up, by the Slap's id, so snoozing it puts the Tab back.
    @ObservationIgnored private var escalated: [String: EdgeTab] = [:] { didSet { saveTabs() } }
    /// Tabs are hidden while you share your screen (with Hold Alerts While I Share My Screen).
    private(set) var tabsHidden = false
    var tabEdge: TabEdge { didSet { defaults.set(tabEdge.rawValue, forKey: PrefKey.tabEdge) } }
    var tabLook: TabLook { didSet { defaults.set(tabLook.rawValue, forKey: PrefKey.tabLook) } }
    var tabSize: TabSize { didSet { defaults.set(tabSize.rawValue, forKey: PrefKey.tabSize) } }
    var tabPile: TabPile { didSet { defaults.set(tabPile.rawValue, forKey: PrefKey.tabPile) } }
    var tabPosition: TabPosition { didSet { defaults.set(tabPosition.rawValue, forKey: PrefKey.tabPosition) } }
    /// Tabs show in screenshots and recordings; otherwise they're kept out, as alerts are.
    var tabsInScreenshots: Bool { didSet { defaults.set(tabsInScreenshots, forKey: PrefKey.tabsInScreenshots) } }
    /// The Deadline for Tabs whose sender gave none, in seconds; 0 for none, the default.
    var tabDeadline: TimeInterval { didSet { defaults.set(tabDeadline, forKey: PrefKey.tabDeadline) } }
    /// The keyboard shortcuts, as you've set them.
    var shortcuts: [HotKeys.Action: Shortcut] {
        didSet {
            defaults.shortcuts = Dictionary(uniqueKeysWithValues: shortcuts.map { ($0.key.key, $0.value) })
            updateHotKeys()
        }
    }
    /// A pretend meeting from Test Alert, which is never in the calendar.
    private var testMeeting: Meeting?

    var leadTime: TimeInterval { didSet { defaults.set(leadTime, forKey: PrefKey.leadTime); tick() } }
    var sound: String { didSet { defaults.set(sound, forKey: PrefKey.sound) } }
    /// Dismissing before the start brings the alert back when the meeting starts.
    var againAtStart: Bool { didSet { defaults.set(againAtStart, forKey: PrefKey.againAtStart) } }
    var theme: Theme { didSet { defaults.set(theme.rawValue, forKey: PrefKey.theme) } }
    /// The Custom theme's colours.
    var customBackground: ThemeColor { didSet { defaults.set(customBackground.hex, forKey: PrefKey.customBackground) } }
    var customAccent: ThemeColor { didSet { defaults.set(customAccent.hex, forKey: PrefKey.customAccent) } }

    /// What alerts are drawn in.
    var palette: Palette {
        theme == .custom ? Palette(background: customBackground, accent: customAccent) : Palette(theme)
    }

    var alertStyle: AlertStyle {
        didSet {
            defaults.set(alertStyle.rawValue, forKey: PrefKey.alertStyle)
            if !alerting.isEmpty { overlay.show(shownStyle) }   // an alert that's up changes shape
        }
    }
    var showDateInMenuBar: Bool { didSet { defaults.set(showDateInMenuBar, forKey: PrefKey.showDate) } }
    var filter: AlertFilter {
        didSet {
            defaults.alertFilter = filter
            if filter.includeReminders && !oldValue.includeReminders { askForReminders() } else { tick() }
        }
    }
    /// Whether other apps may use slaps:// and AppleScript.
    var allowExternal: Bool { didSet { defaults.set(allowExternal, forKey: PrefKey.allowExternal) } }
    var pauseWhileSharing: Bool { didSet { defaults.set(pauseWhileSharing, forKey: PrefKey.pauseWhileSharing); tick() } }
    var hotKeysEnabled: Bool {
        didSet {
            defaults.set(hotKeysEnabled, forKey: PrefKey.hotKeys)
            updateHotKeys()
        }
    }
    private(set) var overrides: Overrides { didSet { defaults.overrides = overrides } }
    private(set) var pausedUntil: Date? { didSet { defaults.set(pausedUntil, forKey: PrefKey.pausedUntil) } }
    /// An alert when the battery runs down to `batteryLevel` percent, off power.
    var batteryAlerts: Bool {
        didSet {
            defaults.set(batteryAlerts, forKey: PrefKey.batteryAlerts)
            batteryWatch = BatteryWatch(level: batteryLevel)
            checkBattery()
        }
    }
    var batteryLevel: Int {
        didSet {
            defaults.set(batteryLevel, forKey: PrefKey.batteryLevel)
            batteryWatch.level = batteryLevel
            checkBattery()
        }
    }
    @ObservationIgnored private var batteryWatch: BatteryWatch
    /// Play one of `videoLinks`, at random, in each alert.
    var playVideos: Bool { didSet { defaults.set(playVideos, forKey: PrefKey.playVideos); prepareVideo() } }
    /// YouTube links, as pasted: videos, playlists and channels. The rest are skipped.
    var videoLinks: [String] { didSet { defaults.set(videoLinks, forKey: PrefKey.videoLinks); prepareVideo() } }
    var videoMode: VideoMode { didSet { defaults.set(videoMode.rawValue, forKey: PrefKey.videoMode); prepareVideo() } }
    /// ytroulette's category (Roulette.categories).
    var rouletteCategory: String {
        didSet { defaults.set(rouletteCategory, forKey: PrefKey.rouletteCategory); prepareVideo() }
    }
    @ObservationIgnored private let videoPicker = VideoPicker()
    private var videoSettings: VideoPicker.Settings {
        VideoPicker.Settings(links: videoLinks, mode: videoMode, category: rouletteCategory)
    }
    /// The video the alert that's up is playing, picked when it went up.
    private(set) var alertVideo: YouTubeVideo?
    #if DEBUG
    /// A made-up reading from the debug driver (`just debug battery 15`), in place of the real battery.
    @ObservationIgnored var simulatedBattery: BatteryReading? { didSet { checkBattery() } }
    #endif

    private init() {
        leadTime = defaults.object(forKey: PrefKey.leadTime) as? Double ?? 60
        sound = defaults.string(forKey: PrefKey.sound) ?? "Glass"
        againAtStart = defaults.bool(forKey: PrefKey.againAtStart)
        theme = defaults.string(forKey: PrefKey.theme).flatMap(Theme.init(rawValue:)) ?? .midnight
        customBackground = defaults.string(forKey: PrefKey.customBackground).flatMap(ThemeColor.init(hex:))
            ?? ThemeColor(hex: "#B3261E")!
        customAccent = defaults.string(forKey: PrefKey.customAccent).flatMap(ThemeColor.init(hex:)) ?? ThemeColor(hex: "#FFD60A")!
        alertStyle = defaults.string(forKey: PrefKey.alertStyle).flatMap(AlertStyle.init(rawValue:)) ?? .fullScreen
        showDateInMenuBar = defaults.bool(forKey: PrefKey.showDate)
        filter = defaults.alertFilter
        pauseWhileSharing = defaults.object(forKey: PrefKey.pauseWhileSharing) as? Bool ?? true
        allowExternal = defaults.object(forKey: PrefKey.allowExternal) as? Bool ?? true
        hotKeysEnabled = defaults.object(forKey: PrefKey.hotKeys) as? Bool ?? true
        overrides = defaults.overrides
        pausedUntil = defaults.object(forKey: PrefKey.pausedUntil) as? Date
        batteryAlerts = defaults.bool(forKey: PrefKey.batteryAlerts)
        let level = defaults.object(forKey: PrefKey.batteryLevel) as? Int ?? 20
        batteryLevel = level
        batteryWatch = BatteryWatch(level: level)
        playVideos = defaults.bool(forKey: PrefKey.playVideos)
        videoLinks = defaults.stringArray(forKey: PrefKey.videoLinks) ?? []
        videoMode = defaults.string(forKey: PrefKey.videoMode).flatMap(VideoMode.init(rawValue:)) ?? .links
        rouletteCategory = defaults.string(forKey: PrefKey.rouletteCategory)
            .flatMap { Roulette.categories.contains($0) ? $0 : nil } ?? "funny"
        // Tabs whose deadline passed while Slaps wasn't running come back looking overdue, without a Slap.
        tabBoard = defaults.tabs.restored(at: Date())
        tabEdge = defaults.string(forKey: PrefKey.tabEdge).flatMap(TabEdge.init(rawValue:)) ?? .right
        tabLook = defaults.string(forKey: PrefKey.tabLook).flatMap(TabLook.init(rawValue:)) ?? .icon
        tabSize = defaults.string(forKey: PrefKey.tabSize).flatMap(TabSize.init(rawValue:)) ?? .regular
        tabPile = defaults.string(forKey: PrefKey.tabPile).flatMap(TabPile.init(rawValue:)) ?? .neat
        tabPosition = defaults.string(forKey: PrefKey.tabPosition).flatMap(TabPosition.init(rawValue:)) ?? .middle
        tabsInScreenshots = defaults.bool(forKey: PrefKey.tabsInScreenshots)
        tabDeadline = defaults.object(forKey: PrefKey.tabDeadline) as? Double ?? 0
        let saved = defaults.shortcuts
        shortcuts = Dictionary(uniqueKeysWithValues: HotKeys.Action.allCases.map {
            ($0, saved[$0.key] ?? $0.defaultShortcut)
        })
    }

    var schedule: AlertSchedule { AlertSchedule(leadTime: leadTime) }

    /// The style of the alert that's up: its own, if the app that sent it asked for one, or the setting.
    var shownStyle: AlertStyle { alerting.first?.style ?? alertStyle }

    /// Meetings and reminders that pass the filter and haven't ended, soonest first. A reminder stays until it's done.
    var upcoming: [Meeting] {
        (meetings + customAlerts).filter { m in
            filter.allows(m) && (m.kind == .reminder ? true : m.end > now)
        }
        .sorted { $0.start < $1.start }
    }

    /// The next meeting that hasn't started yet.
    var next: Meeting? { upcoming.first { $0.kind == .event && $0.start > now } }

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
        updateHotKeys()
        tabsController.start()
        BatteryMonitor.observe { AppModel.shared.checkBattery() }
        checkBattery()
        prepareVideo()
        Task {
            // The first time, the welcome window asks, with an explanation; after that, ask if still unanswered.
            if OnboardingController.isDone && calendar.access == .notAsked { _ = await calendar.requestAccess() }
            if filter.includeReminders && calendar.remindersAccess == .notAsked { _ = await calendar.requestRemindersAccess() }
            fetch()
            while !Task.isCancelled {
                tick()
                try? await Task.sleep(for: .seconds(untilNextTick))
            }
        }
    }

    func requestAccess() {
        Task {
            if calendar.access == .notAsked {
                _ = await calendar.requestAccess()
            } else {
                openPrivacySettings("Privacy_Calendars")
            }
            fetch()
        }
    }

    /// Asks for Reminders the first time they're switched on; afterwards, Settings shows where to allow it.
    func askForReminders() {
        Task {
            if calendar.remindersAccess == .notAsked {
                _ = await calendar.requestRemindersAccess()
            } else if calendar.remindersAccess == .denied {
                openPrivacySettings("Privacy_Reminders")
            }
            fetch()
        }
    }

    private func openPrivacySettings(_ pane: String) {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!)
    }

    /// Reads the calendars and reminders again.
    func fetch() {
        now = Date()
        access = calendar.access
        remindersAccess = calendar.remindersAccess
        calendars = calendar.calendars()
        monthCache = [:]
        let events = calendar.meetings(from: now.addingTimeInterval(-3600), to: now.addingTimeInterval(24 * 3600))
        meetings = events + meetings.filter { $0.kind == .reminder }
        lastFetch = now
        overrides.prune(before: now)
        let keep = Set(customAlerts.map(\.id))
        tick()
        guard filter.includeReminders else {
            meetings = events
            state.keepOnly(Set(meetings.map(\.id)).union(keep))
            return
        }
        Task {
            let reminders = await calendar.reminders(from: now.addingTimeInterval(-3600), to: now.addingTimeInterval(24 * 3600))
            meetings = events + reminders
            state.keepOnly(Set(meetings.map(\.id)).union(customAlerts.map(\.id)))
            tick()
        }
    }

    /// Every 5 seconds, or sooner when an alert is due before then, so it goes up on time.
    private var untilNextTick: TimeInterval {
        let next = [schedule.nextFire(upcoming, after: now, state: state, overrides: overrides),
                    tabBoard.nextDeadline(after: now)].compactMap { $0 }.min()
        return min(5, max(0.1, (next ?? .distantFuture).timeIntervalSince(Date())))
    }

    /// Puts up, changes or takes down the overlay to match the clock.
    func tick() {
        now = Date()
        if now.timeIntervalSince(lastFetch) > 5 * 60 { fetch(); return }
        if let until = pausedUntil, until <= now { pausedUntil = nil }
        customAlerts.removeAll { $0.end <= now || state.dismissed.contains($0.id) }
        // A Slap that's been answered, or has run its hour, is done with its Tab.
        if escalated.keys.contains(where: { id in !customAlerts.contains { $0.id == id } }) {
            escalated = escalated.filter { id, _ in customAlerts.contains { $0.id == id } }
        }
        // Asked at most once a tick, and only when it matters: the window list isn't free.
        var sharingNow: Bool?
        func sharing() -> Bool {
            if let sharingNow { return sharingNow }
            let s = pauseWhileSharing && ScreenShare.isSharing()
            sharingNow = s
            return s
        }
        var due = isPaused ? [] : schedule.due(upcoming, at: now, state: state, overrides: overrides)
        // A Tab past its deadline escalates once nothing else is up or due, so Slaps go up one at a time and a
        // meeting goes first; not while paused or sharing, when it waits on the edge with its sliver full.
        if due.isEmpty, alerting.isEmpty, testMeeting == nil, !isPaused,
           let tab = tabBoard.nextToEscalate(at: now), !sharing() {
            escalate(tab)
            due = schedule.due(upcoming, at: now, state: state, overrides: overrides)
        }
        let hideTabs = !tabBoard.isEmpty && sharing()
        if hideTabs != tabsHidden { tabsHidden = hideTabs }
        // Held back while sharing; the menu bar shows they're waiting, and they go up when sharing stops.
        if !due.isEmpty, alerting.isEmpty, shownDespiteSharing.isDisjoint(with: due.map(\.id)), sharing() {
            heldForSharing = due
            due = []
        } else {
            heldForSharing = []
        }
        if let testMeeting { due.insert(testMeeting, at: 0) }
        guard due.map(\.id) != alerting.map(\.id) else { return }
        let isNew = !Set(due.map(\.id)).isSubset(of: Set(alerting.map(\.id)))
        alerting = due
        if alerting.isEmpty {
            alertVideo = nil
            overlay.hide()
        } else {
            if isNew { alertVideo = playVideos ? videoPicker.take(videoSettings) : nil }
            overlay.show(shownStyle)
            if isNew && alertVideo == nil { AlertSound.play(sound) }   // a video brings its own
        }
    }

    // MARK: The calendar popover

    /// Events around the month starting at `month`, read once per fetch.
    private func events(around month: Date) -> [Meeting] {
        if let cached = monthCache[month] { return cached }
        let cal = Calendar.current
        let start = cal.date(byAdding: .day, value: -7, to: month)!
        let end = cal.date(byAdding: .day, value: 45, to: month)!
        let events = calendar.meetings(from: start, to: end)
        monthCache[month] = events
        return events
    }

    /// What the calendar shows: events in calendars that are switched on. Those that won't alert are still shown.
    private func shows(_ m: Meeting) -> Bool {
        !m.cancelled && !filter.excludedCalendarIDs.contains(m.calendarID)
    }

    /// The starts of the days around `month` that have something on.
    func busyDays(around month: Date) -> Set<Date> {
        CalendarDays.busy(events(around: month).filter(shows))
    }

    /// The day's events, all-day ones first, and on today its reminders.
    func agenda(for day: Date) -> [Meeting] {
        let month = Calendar.current.dateInterval(of: .month, for: day)!.start
        var items = events(around: month).filter(shows)
        if Calendar.current.isDateInToday(day) { items += upcoming.filter { $0.kind == .reminder } }
        return CalendarDays.agenda(items, on: day)
    }

    /// Whether `meeting` will get an alert at all, by the filter and its override.
    func alerts(for meeting: Meeting) -> Bool {
        filter.allows(meeting) && overrides.override(for: meeting) != .skip
    }

    /// Gets the next alert's video ready, from the network if need be, so the alert doesn't wait for it.
    private func prepareVideo() {
        if playVideos { videoPicker.refill(videoSettings) }
    }

    // MARK: Battery

    /// Puts up the low-battery alert, or takes it down once the Mac is plugged in.
    func checkBattery() {
        guard batteryAlerts else {
            customAlerts.removeAll(where: BatteryWatch.isAlert)
            return tick()
        }
        var reading = BatteryMonitor.read()
        #if DEBUG
        if let simulatedBattery { reading = simulatedBattery }
        #endif
        switch batteryWatch.update(reading) {
        case .none: return
        case .clear:
            guard customAlerts.contains(where: BatteryWatch.isAlert) else { return }
            customAlerts.removeAll(where: BatteryWatch.isAlert)
        case .warn:
            guard let reading else { return }
            customAlerts.removeAll(where: BatteryWatch.isAlert)
            customAlerts.append(BatteryWatch.alert(for: reading, at: Date()))
        }
        tick()
    }

    // MARK: Other apps

    /// Runs a command from another app. Throws, with a message for the caller, when it can't.
    func perform(_ command: ExternalCommand) throws {
        guard allowExternal else {
            throw ExternalCommand.Failure("Other apps can't control Slaps: Settings › General › Allow Other Apps")
        }
        switch command {
        case .alert(let alert):
            // Sent again with the same id, it takes the old one's place, and goes up even if that one was dismissed.
            // Tabs share the ids, so it takes a Tab's place too.
            if let key = alert.key { tabBoard.remove(key) }
            let id = alert.key.map { ExternalAlert.meetingID(key: $0) } ?? "custom-\(UUID().uuidString)"
            escalated[id] = nil
            customAlerts.removeAll { $0.id == id }
            state.forget(id)
            customAlerts.append(alert.meeting(id: id))
            tick()
        case .tab(let sent):
            let tab = sent.tab(at: Date(), defaultDeadline: tabDeadline > 0 ? tabDeadline : nil)
            // In place of an alert, or a Slap, sent with the same id.
            customAlerts.removeAll { $0.id == tab.slapID }
            escalated[tab.slapID] = nil
            tabBoard.add(tab)
            tick()
        case .withdraw(let key):
            // An alert or a Tab, wherever it is: on the edge, up as a Slap, or still to come.
            let id = ExternalAlert.meetingID(key: key)
            customAlerts.removeAll { $0.id == id }
            escalated[id] = nil
            tabBoard.remove(key)
            tick()
        case .pause(let interval): pause(for: interval)
        case .resume: resume()
        case .dismiss: dismiss(alerting)
        case .join: joinCurrentOrNext()
        }
    }

    /// Takes back an alert another app asked for, before it goes up.
    func cancel(_ custom: Meeting) {
        customAlerts.removeAll { $0.id == custom.id }
        tick()
    }

    // MARK: Actions

    func join(_ meeting: Meeting) {
        if let url = meeting.link?.url ?? (meeting.kind == .custom ? meeting.url : nil) { NSWorkspace.shared.open(url) }
        finish([meeting])
    }

    /// Opens an alert's link and leaves the alert up, for one whose answer comes after: open the page, then Done.
    func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    /// One of an alert's buttons from another app: opens that app's URL with the answer, and it's done.
    func answer(_ action: ExternalAction, on meeting: Meeting) {
        NSWorkspace.shared.open(action.url)
        finish([meeting])
    }

    /// The shortcut's Join: the alert that's up, or else a meeting under way or starting within 10 minutes.
    func joinCurrentOrNext() {
        let candidates = alerting + upcoming.filter { $0.kind == .event && $0.start < now.addingTimeInterval(600) }
        if let m = candidates.first(where: { $0.link != nil }) {
            join(m)
        } else {
            NSSound.beep()
        }
    }

    /// Puts up the alerts held back for screen sharing.
    func showHeld() {
        shownDespiteSharing.formUnion(heldForSharing.map(\.id))
        tick()
    }

    func complete(_ reminder: Meeting) {
        if let id = reminder.seriesID, reminder.kind == .reminder {
            calendar.complete(reminder: id)
            meetings.removeAll { $0.id == reminder.id }
        }
        finish([reminder])
    }

    /// Dismiss: done with them, or (with Alert Again When It Starts) back at their start.
    func dismiss(_ meetings: [Meeting]) {
        let now = Date()
        for m in meetings {
            if m.id == testMeeting?.id {
                testMeeting = nil
            } else if let again = schedule.dismissal(of: m, at: now, againAtStart: againAtStart) {
                state.snooze(m.id, until: again)
            } else {
                state.dismiss(m.id)
            }
        }
        tick()
    }

    /// Done with them, whatever the settings: they've been joined or completed.
    private func finish(_ meetings: [Meeting]) {
        for m in meetings {
            if m.id == testMeeting?.id { testMeeting = nil } else { state.dismiss(m.id) }
        }
        tick()
    }

    func snooze(_ meetings: [Meeting], until date: Date) {
        for m in meetings {
            if m.id == testMeeting?.id {
                testMeeting = nil
            } else if let tab = escalated.removeValue(forKey: m.id) {
                // A Slap from a Tab goes back on the edge, to slap again when the snooze is up.
                customAlerts.removeAll { $0.id == m.id }
                tabBoard.add(tab.snoozed(at: Date(), until: date))
            } else {
                state.snooze(m.id, until: date)
            }
        }
        tick()
    }

    // MARK: Tabs

    /// Takes a Tab off the edge and puts it up as a Slap.
    private func escalate(_ tab: EdgeTab) {
        tabBoard.remove(tab.id)
        let slap = tab.slap(at: now)
        customAlerts.removeAll { $0.id == slap.id }
        state.forget(slap.id)
        escalated[slap.id] = tab
        customAlerts.append(slap)
    }

    private func saveTabs() {
        defaults.tabs = TabBoard(tabBoard.tabs + escalated.values)
    }

    func dismissTab(_ tab: EdgeTab) {
        tabBoard.remove(tab.id)
        tick()
    }

    func dismissTabs(from source: String) {
        tabBoard.removeAll(from: source)
        tick()
    }

    /// A stack's Tabs, all at once.
    func dismissTabs(_ tabs: [EdgeTab]) {
        for tab in tabs { tabBoard.remove(tab.id) }
        tick()
    }

    func dismissAllTabs() {
        tabBoard.removeAll()
        tick()
    }

    /// Opens a Tab's link. With answers to give, it stays, to answer after; otherwise that's it done.
    func openTab(_ tab: EdgeTab) {
        guard let url = tab.link else { return }
        NSWorkspace.shared.open(url)
        if tab.actions.isEmpty { dismissTab(tab) }
    }

    func answer(_ action: ExternalAction, onTab tab: EdgeTab) {
        NSWorkspace.shared.open(action.url)
        dismissTab(tab)
    }

    /// Return on a Tab, from the keyboard: its first answer, else its link, else Dismiss.
    func act(on tab: EdgeTab) {
        if let action = tab.actions.first { answer(action, onTab: tab) }
        else if tab.link != nil { openTab(tab) }
        else { dismissTab(tab) }
    }

    func setOverride(_ override: AlertOverride?, for meeting: Meeting, scope: Overrides.Scope) {
        overrides.set(override, for: meeting, scope: scope)
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
    func testAlert(reminder: Bool = false) {
        let start = Date().addingTimeInterval(reminder ? 0 : leadTime)
        testMeeting = reminder
            ? Meeting(id: "test-\(UUID())", kind: .reminder, title: "Water the plants", start: start,
                      end: start.addingTimeInterval(3600), calendarTitle: "Reminders")
            : Meeting(id: "test-\(UUID())", title: "Test alert", start: start, end: start.addingTimeInterval(1800),
                      calendarTitle: "Slaps", location: "https://meet.google.com/abc-defg-hij")
        tick()
    }

    var hotKeysRegistered: Int { hotKeys.registered }

    /// Whether macOS took this shortcut; another app may hold it.
    func isRegistered(_ action: HotKeys.Action) -> Bool { hotKeys.isRegistered(action) }

    private func updateHotKeys() {
        guard hotKeysEnabled else { return hotKeys.disable() }
        hotKeys.enable(shortcuts) { [weak self] action in
            guard let self else { return }
            switch action {
            case .join: joinCurrentOrNext()
            case .dismiss: dismiss(alerting)
            case .pause: isPaused ? resume() : pause(for: 3600)
            case .tabs: tabsController.toggleFocus()
            }
        }
    }
}
