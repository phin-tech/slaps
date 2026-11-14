import Foundation

// Tabs: lasting, low-key notices pinned to the edge of the screen until dismissed, which escalate into a Slap (a
// full-screen Alert) once past their Deadline. Not Alerts: docs/adr/0001-tabs-are-not-alerts.md. The type is
// `EdgeTab`, since SwiftUI has a `Tab` of its own.

/// When a Tab escalates, as its sender asked.
public enum TabDeadline: Equatable, Sendable {
    /// The default in Settings, which is none unless you set one.
    case setting
    /// Never, whatever the setting says.
    case never
    case at(Date)
    /// So many seconds after it's sent.
    case after(TimeInterval)

    /// As another app writes it: minutes (`30`), a time (ISO 8601, as for an alert's `at`), or `never`.
    public init(external text: String) throws {
        let t = text.trimmingCharacters(in: .whitespaces).lowercased()
        if t == "never" || t == "none" {
            self = .never
        } else if let minutes = Double(t) {
            guard minutes >= 0 else { throw ExternalCommand.Failure("deadline= can't be negative") }
            self = .after(minutes * 60)
        } else if let date = ExternalCommand.parseDate(text.trimmingCharacters(in: .whitespaces)) {
            self = .at(date)
        } else {
            throw ExternalCommand.Failure("deadline= is minutes, an ISO 8601 time, or never")
        }
    }
}

/// Where on the edge a Tab stands: its sender's choice, or the setting.
public enum TabSlot: String, CaseIterable, Codable, Sendable, Identifiable {
    case top, middle, bottom

    public var id: Self { self }

    /// As another app writes it.
    public init(external text: String) throws {
        guard let slot = TabSlot(rawValue: text.trimmingCharacters(in: .whitespaces).lowercased()) else {
            throw ExternalCommand.Failure("position= is top, middle or bottom")
        }
        self = slot
    }
}

/// A Tab another app asked for, checked here so every way in gets the same rules as an alert.
public struct ExternalTab: Equatable, Sendable {
    public var title: String
    public var deadline: TabDeadline
    public var link: URL?
    public var notes: String?
    public var source: String?
    /// Its sender's name for it, shared with alerts: another Tab or alert with the same takes its place.
    public var key: String?
    public var color: ThemeColor?
    public var actions: [ExternalAction] = []
    public var position: TabSlot?
    /// Tabs from the same Source with the same group stack up as one ("reviews").
    public var group: String?
    /// An SF Symbol's name, or an app's bundle id for its icon.
    public var icon: String?

    /// `color` is a name (`TabColors.named`) or a hex colour; `actions` and `callback` as for an alert.
    public init(title: String, deadline: TabDeadline = .setting, link: String? = nil, notes: String? = nil,
                source: String? = nil, key: String? = nil, color: String? = nil, actions: [String] = [],
                callback: String? = nil, position: TabSlot? = nil, group: String? = nil, icon: String? = nil,
                now: Date) throws {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw ExternalCommand.Failure("a tab needs a title") }
        let week: TimeInterval = 7 * 24 * 3600
        let tooFar = switch deadline {
        case .at(let date): date > now.addingTimeInterval(week)
        case .after(let t): t > week
        case .setting, .never: false
        }
        guard !tooFar else { throw ExternalCommand.Failure("a tab's deadline can be at most a week ahead") }
        self.title = String(title.prefix(200))
        self.deadline = deadline
        if let link { self.link = try ExternalAlert.allowed(link, "link") }
        self.notes = notes.map { String($0.prefix(500)) }
        self.source = source.map { String($0.prefix(60)) }
        self.key = try key.map(ExternalAlert.checkedKey)
        if let color {
            guard let c = TabColors.parse(color) else {
                throw ExternalCommand.Failure("color= is a name (\(TabColors.names.joined(separator: ", "))) or #RRGGBB")
            }
            self.color = c
        }
        self.actions = try ExternalAlert.checkedActions(actions, callback: callback, what: "a tab")
        self.position = position
        self.group = group.map { String($0.trimmingCharacters(in: .whitespaces).prefix(40)) }.flatMap { $0.isEmpty ? nil : $0 }
        self.icon = try icon.map(Self.checkedIcon)
    }

    /// An `icon=` as given, or why it can't be one: a symbol's name or a bundle id, so letters, digits, `.`, `_` and
    /// `-`. Never a path or a URL: anyone can send a Tab, so it can't make Slaps read files or fetch pictures.
    static func checkedIcon(_ icon: String) throws -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        guard !icon.isEmpty, icon.count <= 100, icon.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            throw ExternalCommand.Failure("icon= is an SF Symbol's name or an app's bundle id")
        }
        return icon
    }

    /// The Tab, sent at `now`; `defaultDeadline` is the setting's, for a sender who didn't say.
    public func tab(at now: Date, defaultDeadline: TimeInterval?) -> EdgeTab {
        let due: Date? = switch deadline {
        case .setting: defaultDeadline.map { now.addingTimeInterval($0) }
        case .never: nil
        case .at(let date): max(date, now)
        case .after(let t): now.addingTimeInterval(t)
        }
        return EdgeTab(id: key ?? UUID().uuidString, title: title, notes: notes, source: source, link: link,
                       actions: actions, color: color, sent: now, deadline: due, position: position, group: group,
                       icon: icon)
    }
}

/// A Tab: what it says, who sent it, and when it escalates.
public struct EdgeTab: Identifiable, Hashable, Codable, Sendable {
    /// Its sender's `id`, or one of its own. Shared with alerts: its Slap is `ExternalAlert.meetingID(key: id)`.
    public var id: String
    public var title: String
    public var notes: String?
    public var source: String?
    public var link: URL?
    public var actions: [ExternalAction]
    /// The sender's colour, if it picked one; otherwise its Source's.
    public var color: ThemeColor?
    public var sent: Date
    /// When it escalates; nil for never.
    public var deadline: Date?
    /// Its deadline passed while Slaps wasn't running: it comes back looking overdue, but doesn't slap you.
    public var stale = false
    /// Where on the edge its sender wants it; the setting's, if nil.
    public var position: TabSlot?
    /// The stack it joins, with others from its Source in the same group.
    public var group: String?
    /// An SF Symbol's name, or an app's bundle id for its icon.
    public var icon: String?

    public init(id: String, title: String, notes: String? = nil, source: String? = nil, link: URL? = nil,
                actions: [ExternalAction] = [], color: ThemeColor? = nil, sent: Date, deadline: Date? = nil,
                stale: Bool = false, position: TabSlot? = nil, group: String? = nil, icon: String? = nil) {
        self.icon = icon
        self.position = position
        self.group = group
        self.id = id
        self.title = title
        self.notes = notes
        self.source = source
        self.link = link
        self.actions = actions
        self.color = color
        self.sent = sent
        self.deadline = deadline
        self.stale = stale
    }

    /// The name its Source goes by, for grouping and colour: as sent, or "Another app".
    public var sourceName: String { source?.isEmpty == false ? source! : "Another app" }

    /// What it's drawn in.
    public var tint: ThemeColor { color ?? TabColors.forSource(sourceName) }

    /// How far it is from sent to its deadline, 0 to 1; nil without a deadline. Full once overdue or stale.
    public func progress(at now: Date) -> Double? {
        guard let deadline else { return stale ? 1 : nil }
        if stale { return 1 }
        let span = deadline.timeIntervalSince(sent)
        guard span > 0 else { return 1 }
        return min(1, max(0, now.timeIntervalSince(sent) / span))
    }

    public func isOverdue(at now: Date) -> Bool { stale || (deadline.map { $0 <= now } ?? false) }

    /// The id of the Slap it escalates into, the same as an alert sent with its id.
    public var slapID: String { ExternalAlert.meetingID(key: id) }

    /// Its Slap: an alert from another app, full screen whatever the style setting says.
    public func slap(at now: Date) -> Meeting {
        Meeting(id: slapID, kind: .custom, title: title, start: now, end: now.addingTimeInterval(3600),
                calendarTitle: sourceName, notes: notes, url: link, style: .fullScreen, actions: actions)
    }
}

/// Every Tab up, in the order they stand on the edge.
public struct TabBoard: Equatable, Codable, Sendable {
    /// How many stand in a stack of Tabs on the edge, with only one in use; the rest are gathered under one "+N".
    public static let shown = 8
    /// The same, with Tabs in more than one place, so three still fit on a laptop's screen.
    public static let shownWhenShared = 5

    public private(set) var tabs: [EdgeTab] = []

    public init(_ tabs: [EdgeTab] = []) {
        self.tabs = []
        for tab in tabs { add(tab) }
    }

    public var isEmpty: Bool { tabs.isEmpty }

    /// Puts it up, in place of any with the same id.
    public mutating func add(_ tab: EdgeTab) {
        tabs.removeAll { $0.id == tab.id }
        tabs.append(tab)
        tabs.sort(by: Self.order)
    }

    /// Takes it down, returning it if it was up.
    @discardableResult
    public mutating func remove(_ id: String) -> EdgeTab? {
        guard let i = tabs.firstIndex(where: { $0.id == id }) else { return nil }
        return tabs.remove(at: i)
    }

    /// Dismiss all from this Source.
    public mutating func removeAll(from sourceName: String) {
        tabs.removeAll { $0.sourceName == sourceName }
    }

    public mutating func removeAll() { tabs = [] }

    /// Nearest deadline first, then the ones without, each newest first.
    static func order(_ a: EdgeTab, _ b: EdgeTab) -> Bool {
        switch (a.deadline, b.deadline) {
        case let (x?, y?) where x != y: x < y
        case (_?, nil): true
        case (nil, _?): false
        default: a.sent > b.sent
        }
    }

    /// How the Tabs stand on the edge: in the places they asked for (`defaultSlot` if they didn't), top to bottom,
    /// grouped ones stacked up, and past what fits, gathered under "+N".
    public func columns(defaultSlot: TabSlot) -> [TabColumn] {
        // Stacks: one per Tab, or one per Source and group. `tabs` is already in order, so each stack's first is its
        // nearest deadline, and stacks come in the order of their first.
        var stacks: [TabStack] = []
        var index: [String: Int] = [:]
        for tab in tabs {
            let id = tab.group.map { TabStack.id(source: tab.sourceName, group: $0) } ?? tab.id
            if let i = index[id] {
                stacks[i].tabs.append(tab)
            } else {
                index[id] = stacks.count
                stacks.append(TabStack(id: id, group: tab.group, tabs: [tab]))
            }
        }
        let bySlot = Dictionary(grouping: stacks) { $0.slot(default: defaultSlot) }
        let cap = bySlot.count > 1 ? Self.shownWhenShared : Self.shown
        return TabSlot.allCases.compactMap { slot in
            guard let stacks = bySlot[slot], !stacks.isEmpty else { return nil }
            // They fit; with more, the last place is the "+N" Tab.
            guard stacks.count > cap else { return TabColumn(slot: slot, shown: stacks, more: []) }
            return TabColumn(slot: slot, shown: Array(stacks.prefix(cap - 1)), more: Array(stacks.dropFirst(cap - 1)))
        }
    }

    /// The Tab to escalate at `now`: past its deadline, oldest deadline first. Stale ones never escalate.
    public func nextToEscalate(at now: Date) -> EdgeTab? {
        tabs.filter { !$0.stale && ($0.deadline.map { $0 <= now } ?? false) }
            .min { $0.deadline! < $1.deadline! }
    }

    /// As read back at launch: Tabs whose deadline passed while Slaps wasn't running come back stale.
    public func restored(at now: Date) -> TabBoard {
        TabBoard(tabs.map { tab in
            var tab = tab
            if tab.isOverdue(at: now) { tab.stale = true }
            return tab
        })
    }

    /// The next time a Tab escalates after `now`, for scheduling a wake-up.
    public func nextDeadline(after now: Date) -> Date? {
        tabs.filter { !$0.stale }.compactMap(\.deadline).filter { $0 > now }.min()
    }
}

/// One place on the edge: a Tab, or a group of them from one Source stacked up.
public struct TabStack: Identifiable, Equatable, Sendable {
    public var id: String
    /// The group's name, for a stack; nil for a Tab on its own.
    public var group: String?
    /// Nearest deadline first.
    public var tabs: [EdgeTab]

    static func id(source: String, group: String) -> String { "group:\(source.lowercased())/\(group.lowercased())" }

    public var isGroup: Bool { group != nil }
    /// The Tab it shows: its nearest deadline.
    public var first: EdgeTab { tabs[0] }
    public var sourceName: String { first.sourceName }
    public var tint: ThemeColor { first.tint }
    /// Its newest Tab's icon that has one.
    public var icon: String? { tabs.sorted { $0.sent > $1.sent }.lazy.compactMap(\.icon).first }
    /// What its collapsed Tab says: the group's name, capitalised, or the Tab's title.
    public var title: String {
        guard let group else { return first.title }
        return group.prefix(1).uppercased() + group.dropFirst()
    }

    /// Where it stands: where its newest Tab asked to, or `default`.
    public func slot(default slot: TabSlot) -> TabSlot {
        tabs.max { $0.sent < $1.sent }?.position ?? slot
    }

    public func isOverdue(at now: Date) -> Bool { tabs.contains { $0.isOverdue(at: now) } }
}

/// The stacks in one place on the edge, top to bottom.
public struct TabColumn: Equatable, Sendable {
    public var slot: TabSlot
    public var shown: [TabStack]
    /// Gathered under "+N".
    public var more: [TabStack]

    /// Each Tab in it, in order, for the keyboard to step through.
    public var tabs: [EdgeTab] { (shown + more).flatMap(\.tabs) }
}

extension EdgeTab {
    /// A Slap snoozed: back on the edge as a Tab, its deadline the snooze away.
    public func snoozed(at now: Date, until: Date) -> EdgeTab {
        var tab = self
        tab.sent = now
        tab.deadline = until
        tab.stale = false
        return tab
    }
}

/// The colours Tabs come in: one per Source unless the sender picks one.
public enum TabColors {
    /// The colours a sender can name, and Sources are given.
    public static let named: [(name: String, color: ThemeColor)] = [
        ("red", ThemeColor(hex: "#E5484D")!), ("orange", ThemeColor(hex: "#F76B15")!),
        ("yellow", ThemeColor(hex: "#FFC53D")!), ("green", ThemeColor(hex: "#30A46C")!),
        ("mint", ThemeColor(hex: "#3DD9B0")!), ("teal", ThemeColor(hex: "#12A594")!),
        ("cyan", ThemeColor(hex: "#00A2C7")!), ("blue", ThemeColor(hex: "#0090FF")!),
        ("indigo", ThemeColor(hex: "#3E63DD")!), ("purple", ThemeColor(hex: "#8E4EC6")!),
        ("pink", ThemeColor(hex: "#D6409F")!), ("brown", ThemeColor(hex: "#AD7F58")!),
        ("gray", ThemeColor(hex: "#8B8D98")!),
    ]

    public static var names: [String] { named.map(\.name) }

    /// A name from `named` (`grey` too) or a hex colour.
    public static func parse(_ text: String) -> ThemeColor? {
        let t = text.trimmingCharacters(in: .whitespaces).lowercased()
        if let c = named.first(where: { $0.name == (t == "grey" ? "gray" : t) }) { return c.color }
        return ThemeColor(hex: t)
    }

    /// The same colour for the same Source every time, ignoring case: FNV-1a, not Swift's hashing, which changes
    /// with each launch. Gray is left for senders who ask for it.
    public static func forSource(_ name: String) -> ThemeColor {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in name.lowercased().utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100_0000_01b3
        }
        let colors = named.dropLast()
        return colors[colors.startIndex + Int(hash % UInt64(colors.count))].color
    }
}
