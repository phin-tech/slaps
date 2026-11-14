import Foundation
import Testing
@testable import SlapsKit

private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

private func tab(_ id: String, sent: TimeInterval = 0, deadline: TimeInterval? = nil, source: String? = nil) -> EdgeTab {
    EdgeTab(id: id, title: id, source: source, sent: now.addingTimeInterval(sent),
            deadline: deadline.map { now.addingTimeInterval($0) })
}

@Test func aTabFromAURLHasItsDeadlineColourAndButtons() throws {
    let url = URL(string: "slaps://tab?title=Reply%20to%20Bob&deadline=30&color=teal&source=Mail&id=bob"
                  + "&actions=Done&callback=boiler-room%3A%2F%2Fanswer%3Fa%3D%7Baction%7D")!
    guard case .tab(let t) = try ExternalCommand.parse(url, now: now) else {
        Issue.record("not a tab")
        return
    }
    #expect(t.title == "Reply to Bob")
    #expect(t.deadline == .after(1800))
    #expect(t.color == TabColors.parse("teal"))
    #expect(t.key == "bob")
    #expect(t.actions.map(\.url.absoluteString) == ["boiler-room://answer?a=Done"])
    let edge = t.tab(at: now, defaultDeadline: nil)
    #expect(edge.id == "bob")
    #expect(edge.deadline == now.addingTimeInterval(1800))
    #expect(edge.slapID == ExternalAlert.meetingID(key: "bob"), "its Slap shares the id space with alerts")
}

@Test func aTabWithoutADeadlineTakesTheSettingsUnlessItSaysNever() throws {
    let plain = try ExternalTab(title: "FYI", now: now)
    #expect(plain.tab(at: now, defaultDeadline: nil).deadline == nil, "the setting's default is none")
    #expect(plain.tab(at: now, defaultDeadline: 3600).deadline == now.addingTimeInterval(3600))
    let never = try ExternalTab(title: "FYI", deadline: .never, now: now)
    #expect(never.tab(at: now, defaultDeadline: 3600).deadline == nil)
}

@Test func deadlinesAreMinutesTimesOrNever() throws {
    #expect(try TabDeadline(external: "15") == .after(900))
    #expect(try TabDeadline(external: "never") == .never)
    #expect(try TabDeadline(external: "2026-11-03T18:00:00Z") == .at(ISO8601DateFormatter().date(from: "2026-11-03T18:00:00Z")!))
    #expect(throws: ExternalCommand.Failure.self) { try TabDeadline(external: "soon") }
    #expect(throws: ExternalCommand.Failure.self) { try ExternalTab(title: "x", deadline: .after(8 * 24 * 3600), now: now) }
}

@Test func aTabIsCheckedLikeAnAlert() {
    #expect(throws: ExternalCommand.Failure("a tab needs a title")) { try ExternalTab(title: "  ", now: now) }
    #expect(throws: ExternalCommand.Failure.self) { try ExternalTab(title: "x", link: "file:///etc/passwd", now: now) }
    #expect(throws: ExternalCommand.Failure.self) { try ExternalTab(title: "x", color: "plaid", now: now) }
    #expect(throws: ExternalCommand.Failure.self) {
        try ExternalTab(title: "x", actions: ["Yes"], callback: "https://example.com/no-placeholder", now: now)
    }
}

@Test func theCommandLineSendsATab() throws {
    let url = try #require(try SlapsCommandLine.url(for: ["tab", "Reply to Bob", "--deadline", "30", "--color", "#FF0000",
                                                          "--id", "bob"], now: now))
    guard case .tab(let t) = try ExternalCommand.parse(url, now: now) else {
        Issue.record("not a tab")
        return
    }
    #expect(t.source == "Terminal")
    #expect(t.color == ThemeColor(hex: "#FF0000"))
    #expect(throws: SlapsCommandLine.Failure.self) { try SlapsCommandLine.url(for: ["tab", "x", "--style", "side"]) }
    #expect(throws: SlapsCommandLine.Failure.self) { try SlapsCommandLine.url(for: ["alert", "x", "--deadline", "5"]) }
}

@Test func tabsStandNearestDeadlineFirstThenNewest() {
    let board = TabBoard([tab("old-no-deadline", sent: -600), tab("late", deadline: 3600), tab("soon", deadline: 60),
                          tab("new-no-deadline", sent: -10)])
    #expect(board.tabs.map(\.id) == ["soon", "late", "new-no-deadline", "old-no-deadline"])
}

@Test func sendingTheSameIdAgainReplacesTheTab() {
    var board = TabBoard([tab("bob", deadline: 60)])
    board.add(tab("bob", deadline: 600))
    #expect(board.tabs.count == 1)
    #expect(board.tabs[0].deadline == now.addingTimeInterval(600))
}

@Test func pastEightTheRestGatherUnderOne() {
    let columns = TabBoard((1...10).map { tab("t\($0)", sent: Double($0)) }).columns(defaultSlot: .middle)
    #expect(columns.count == 1)
    #expect(columns[0].shown.count == 7)
    #expect(columns[0].more.count == 3)
    #expect(TabBoard((1...8).map { tab("t\($0)") }).columns(defaultSlot: .middle)[0].more.isEmpty, "eight fit")
}

@Test func tabsStandWhereTheyAskOrWhereTheSettingSays() {
    var top = tab("ci")
    top.position = .top
    let columns = TabBoard([top, tab("plain")]).columns(defaultSlot: .bottom)
    #expect(columns.map(\.slot) == [.top, .bottom])
    #expect(columns[0].shown.map(\.id) == ["ci"])
    #expect(columns[1].shown.map(\.id) == ["plain"])
}

@Test func withTabsInMoreThanOnePlaceFiveFitInEach() {
    var tabs = (1...7).map { tab("t\($0)", sent: Double($0)) }
    tabs[0].position = .top
    let columns = TabBoard(tabs).columns(defaultSlot: .middle)
    #expect(columns[1].shown.count == 4)
    #expect(columns[1].more.count == 2)
}

@Test func aGroupFromOneSourceStacksUp() {
    func review(_ n: Int, deadline: TimeInterval? = nil, source: String = "GitHub") -> EdgeTab {
        var t = tab("pr\(n)", sent: Double(n), deadline: deadline, source: source)
        t.group = "reviews"
        return t
    }
    let board = TabBoard([review(1), review(2, deadline: 600), review(3), tab("other"), review(4, source: "GitLab")])
    let stacks = board.columns(defaultSlot: .middle)[0].shown
    let github = stacks.first { $0.isGroup && $0.sourceName == "GitHub" }!
    #expect(github.tabs.map(\.id) == ["pr2", "pr3", "pr1"], "nearest deadline first, then newest")
    #expect(github.title == "Reviews")
    #expect(stacks.count == 3, "GitLab's reviews are a stack of their own, and the other Tab stands alone")
}

@Test func aStackStandsWhereItsNewestTabAsked() {
    var old = tab("a", sent: 0)
    old.group = "g"
    old.position = .top
    var new = tab("b", sent: 10)
    new.group = "g"
    new.position = .bottom
    #expect(TabBoard([old, new]).columns(defaultSlot: .middle).map(\.slot) == [.bottom])
}

@Test func aTabSaysWhereAndWhichGroup() throws {
    let url = URL(string: "slaps://tab?title=Review%20412&position=top&group=reviews")!
    guard case .tab(let t) = try ExternalCommand.parse(url, now: now) else {
        Issue.record("not a tab")
        return
    }
    #expect(t.position == .top)
    #expect(t.group == "reviews")
    #expect(throws: ExternalCommand.Failure.self) {
        try ExternalCommand.parse(URL(string: "slaps://tab?title=x&position=left")!, now: now)
    }
    let cli = try #require(try SlapsCommandLine.url(for: ["tab", "Review", "--position", "bottom", "--group", "reviews"],
                                                    now: now))
    guard case .tab(let c) = try ExternalCommand.parse(cli, now: now) else { return }
    #expect(c.tab(at: now, defaultDeadline: nil).position == .bottom)
}

@Test func theOldestDeadlineEscalatesFirstAndStaleOnesNever() {
    var board = TabBoard([tab("a", deadline: -10), tab("b", deadline: -100), tab("c", deadline: 100), tab("d")])
    #expect(board.nextToEscalate(at: now)?.id == "b")
    board.remove("b")
    #expect(board.nextToEscalate(at: now)?.id == "a")
    board.remove("a")
    #expect(board.nextToEscalate(at: now) == nil)
    #expect(board.nextDeadline(after: now) == now.addingTimeInterval(100))
}

@Test func tabsOverdueAtLaunchComeBackStaleNotAsSlaps() {
    let board = TabBoard([tab("missed", sent: -7200, deadline: -3600), tab("later", deadline: 600)]).restored(at: now)
    let missed = board.tabs.first { $0.id == "missed" }!
    #expect(missed.stale)
    #expect(missed.progress(at: now) == 1, "its sliver is full")
    #expect(!board.tabs.first { $0.id == "later" }!.stale)
    #expect(board.nextToEscalate(at: now.addingTimeInterval(3600))?.id == "later")
}

@Test func theSliverFillsTowardTheDeadline() {
    let t = tab("t", sent: -300, deadline: 300)
    #expect(t.progress(at: now) == 0.5)
    #expect(tab("t").progress(at: now) == nil)
    #expect(t.progress(at: now.addingTimeInterval(900)) == 1)
}

@Test func snoozingASlapPutsItBackWithANewDeadline() {
    let t = tab("t", sent: -600, deadline: -1).snoozed(at: now, until: now.addingTimeInterval(300))
    #expect(t.deadline == now.addingTimeInterval(300))
    #expect(t.progress(at: now) == 0)
    #expect(!t.isOverdue(at: now))
}

@Test func theSlapIsFullScreenWhateverTheSetting() {
    let slap = tab("t", source: "CI").slap(at: now)
    #expect(slap.style == .fullScreen)
    #expect(slap.kind == .custom)
    #expect(slap.calendarTitle == "CI")
}

@Test func aSourceKeepsItsColour() {
    #expect(TabColors.forSource("CI") == TabColors.forSource("ci"))
    #expect(tab("t", source: "CI").tint == TabColors.forSource("CI"))
    var picked = tab("t", source: "CI")
    picked.color = TabColors.parse("pink")
    #expect(picked.tint == TabColors.parse("pink"))
}

@Test func dismissAllFromASource() {
    var board = TabBoard([tab("a", source: "CI"), tab("b", source: "CI"), tab("c", source: "Mail"), tab("d")])
    board.removeAll(from: "CI")
    #expect(board.tabs.map(\.id).sorted() == ["c", "d"])
    board.removeAll(from: "Another app")
    #expect(board.tabs.map(\.id) == ["c"])
}

@Test func tabsSurviveBeingWrittenDown() throws {
    var t = tab("t", deadline: 60, source: "CI")
    t.color = ThemeColor(hex: "#123456")
    t.actions = [ExternalAction(title: "Yes", url: URL(string: "https://example.com/yes")!)]
    let board = TabBoard([t])
    let back = try JSONDecoder().decode(TabBoard.self, from: JSONEncoder().encode(board))
    #expect(back == board)
}

@Test func shortcutsReadAsTheMenusWriteThem() {
    let s = Shortcut(keyCode: 17, modifiers: [.command, .control, .option], key: "T")
    #expect(s.display == "⌃⌥⌘T")
    #expect(s.isUsable)
    #expect(!Shortcut(keyCode: 17, modifiers: [.shift], key: "T").isUsable, "it would take the key from typing")
}

@Test func aTabCanHaveAnIconButNotAPath() throws {
    let url = URL(string: "slaps://tab?title=x&icon=com.github.GitHubClient")!
    guard case .tab(let t) = try ExternalCommand.parse(url, now: now) else { return }
    #expect(t.tab(at: now, defaultDeadline: nil).icon == "com.github.GitHubClient")
    #expect(throws: ExternalCommand.Failure.self) { try ExternalTab(title: "x", icon: "/etc/passwd", now: now) }
    #expect(throws: ExternalCommand.Failure.self) { try ExternalTab(title: "x", icon: "https://x.example/a.png", now: now) }
    var a = tab("a", sent: 0)
    a.group = "g"
    a.icon = "star"
    var b = tab("b", sent: 10)
    b.group = "g"
    #expect(TabBoard([a, b]).columns(defaultSlot: .middle)[0].shown[0].icon == "star",
            "a stack takes the newest icon there is")
}
