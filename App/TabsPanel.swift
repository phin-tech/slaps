import AppKit
import SlapsKit
import SwiftUI

/// What the Tabs on the edge are doing: which one is slid out, and whether they're being worked from the keyboard.
@MainActor
@Observable
final class TabsUI {
    /// The stack slid out into its card: a Tab's id, a group's (`TabStack.id`), or `TabsUI.more(slot)` for a "+N".
    var expanded: String?
    /// Clicked: it stays out until you click away.
    var pinned: String?
    /// The tabs shortcut: every Tab out, and the keyboard theirs until Escape.
    var focused = false
    /// The Tab the keyboard is on.
    var selection: String?

    static func more(_ slot: TabSlot) -> String { "+more:\(slot.rawValue)" }

    /// Where each stack is drawn, in its panel's content (top-left origin), by place and id: which one the mouse is
    /// on decides which is out.
    @ObservationIgnored var rowFrames: [TabSlot: [String: CGRect]] = [:]
}

/// The Tabs: a borderless panel for each place on the right (or left) edge of the main screen that has any (top,
/// middle, bottom), over ordinary windows and full-screen apps, which never takes the keyboard unless you ask with
/// the tabs shortcut. Each is sized to its Tabs, so the rest of the edge stays yours.
@MainActor
final class TabsController {
    let ui = TabsUI()
    private var panels: [TabSlot: TabsWindow] = [:]
    private var clickAway: Any?
    /// Follow the mouse wherever it goes: over another app (global) or over Slaps' own windows (local).
    private var mouseMonitors: [Any] = []
    private var screenObserver: NSObjectProtocol?
    private var refreshQueued = false

    /// Starts following the model: the panels come and go, and resize, as Tabs do.
    func start() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        let moves: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: moves, handler: { _ in
            MainActor.assumeIsolated { AppModel.shared.tabsController.trackMouse() }
        }) { mouseMonitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: moves, handler: { event in
            MainActor.assumeIsolated { AppModel.shared.tabsController.trackMouse() }
            return event
        }) { mouseMonitors.append(local) }
        refresh()
    }

    /// The Tabs, as they stand on the edge.
    var columns: [TabColumn] {
        AppModel.shared.tabBoard.columns(defaultSlot: AppModel.shared.tabPosition)
    }

    /// Puts each panel where its Tabs are, or takes it away; then watches for the next change.
    func refresh() {
        refreshQueued = false
        let model = AppModel.shared
        withObservationTracking {
            _ = model.tabBoard
            _ = model.tabsHidden
            _ = model.tabEdge
            _ = model.tabLook
            _ = model.tabSize
            _ = model.tabPile
            _ = model.tabPosition
            _ = model.tabsInScreenshots
            _ = ui.expanded
            _ = ui.focused
            _ = ui.selection
        } onChange: { [weak self] in
            // After the change lands, and once however many come together.
            Task { @MainActor in
                guard let self, !self.refreshQueued else { return }
                self.refreshQueued = true
                self.refresh()
            }
        }
        let columns = self.columns
        let ids = Set(columns.flatMap { c in (c.shown + c.more).map(\.id) + [TabsUI.more(c.slot)] })
        for slot in TabSlot.allCases { ui.rowFrames[slot] = ui.rowFrames[slot]?.filter { ids.contains($0.key) } }
        if let expanded = ui.expanded, !ids.contains(expanded) {
            ui.expanded = nil
            ui.pinned = nil
        }
        guard !columns.isEmpty, !model.tabsHidden, let screen = NSScreen.screens.first else {
            if ui.focused { endFocus() }
            for panel in panels.values { panel.orderOut(nil) }
            return
        }
        let visible = screen.visibleFrame.insetBy(dx: 0, dy: 12)
        let metrics = TabMetrics(model.tabSize, pile: model.tabPile)
        for slot in TabSlot.allCases {
            guard let column = columns.first(where: { $0.slot == slot }) else {
                panels[slot]?.orderOut(nil)
                continue
            }
            let panel = panels[slot] ?? makePanel(slot)
            // At the top or in the middle, the top stays where the collapsed column's would be, so a Tab sliding out
            // grows downwards and the one under the mouse doesn't move away from it; at the bottom, it grows upwards.
            let collapsedHeight = column.shown.reduce(0) { $0 + metrics.rowHeight(model.tabLook, stacked: $1.isGroup) }
                + (column.more.isEmpty ? 0 : metrics.rowHeight(model.tabLook))
                + CGFloat(max(0, column.shown.count + (column.more.isEmpty ? 0 : 1) - 1)) * metrics.spacing
            panel.edge = model.tabEdge
            panel.edgeX = model.tabEdge == .right ? screen.visibleFrame.maxX : screen.visibleFrame.minX
            panel.bounds = (visible.minY, visible.maxY)
            switch slot {
            case .top: panel.anchor = .top(visible.maxY)
            case .middle: panel.anchor = .top(min(visible.maxY, visible.midY + collapsedHeight / 2))
            case .bottom: panel.anchor = .bottom(visible.minY)
            }
            panel.allowsKey = ui.focused
            // Out of screenshots, recordings and screen sharing, unless you'd rather they showed.
            panel.sharingType = model.tabsInScreenshots ? .readOnly : .none
            // The SwiftUI content sizes the window as the Tabs change (asking it for a size straight after a change
            // can answer 0×0); this only puts it back against its edge and anchor.
            panel.setFrame(panel.frame, display: true)
            if !panel.isVisible { panel.orderFrontRegardless() }
        }
    }

    private func makePanel(_ slot: TabSlot) -> TabsWindow {
        let panel = TabsWindow(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
                               defer: false)
        // Over ordinary windows and full-screen apps, under an alert.
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.title = "Slaps tabs (\(slot.rawValue))"
        panel.sharingType = AppModel.shared.tabsInScreenshots ? .readOnly : .none
        panel.contentView = NSHostingView(rootView: TabsView(model: .shared, ui: ui, controller: self, slot: slot))
        panels[slot] = panel
        return panel
    }

    // MARK: Hover and click

    /// Slides out the stack under the mouse, and puts it back once the mouse is off it, by where the mouse is rather
    /// than by SwiftUI's hover: swapping a Tab for its card ends one hover and starts another, which made them flash,
    /// and an app that isn't active isn't always told a hover ended. A card that's out stays out while the mouse is on
    /// it, even where it covers the Tab below.
    func trackMouse() {
        guard !ui.focused, ui.pinned == nil else { return }
        let mouse = NSEvent.mouseLocation
        var under: String?
        for (slot, panel) in panels where panel.isVisible {
            let p = panel.convertPoint(fromScreen: mouse)
            let point = CGPoint(x: p.x, y: panel.frame.height - p.y)
            let frames = ui.rowFrames[slot] ?? [:]
            if let out = ui.expanded, let frame = frames[out], frame.insetBy(dx: -3, dy: -3).contains(point) { return }
            if under == nil { under = frames.first { $0.value.contains(point) }?.key }
        }
        guard ui.expanded != under else { return }
        // The card's outline is stale until SwiftUI lays the Tab out again; forget it, so the next move can't
        // slide it straight back out.
        if let out = ui.expanded { for slot in TabSlot.allCases { ui.rowFrames[slot]?[out] = nil } }
        ui.expanded = under
    }

    /// A click keeps a stack out until you click somewhere else.
    func pin(_ id: String) {
        ui.pinned = id
        ui.expanded = id
        if clickAway == nil {
            clickAway = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in
                MainActor.assumeIsolated { AppModel.shared.tabsController.unpin() }
            }
        }
    }

    func unpin() {
        if let clickAway { NSEvent.removeMonitor(clickAway) }
        clickAway = nil
        ui.pinned = nil
        ui.expanded = nil
    }

    // MARK: The keyboard

    /// Every Tab, in the order the keyboard steps through them: top to bottom of the edge.
    private var keyboardOrder: [(slot: TabSlot, tab: EdgeTab)] {
        columns.flatMap { c in c.tabs.map { (c.slot, $0) } }
    }

    /// The tabs shortcut: every Tab out, the first chosen, and the keyboard theirs until Escape. Again, to put them
    /// away.
    func toggleFocus() {
        if ui.focused { return endFocus() }
        let board = AppModel.shared.tabBoard
        guard !board.isEmpty, !AppModel.shared.tabsHidden else { return NSSound.beep() }
        unpin()
        ui.focused = true
        ui.selection = keyboardOrder.first?.tab.id
        refresh()
        keyToSelection()
    }

    /// The panel with the chosen Tab takes the keyboard.
    private func keyToSelection() {
        guard let slot = keyboardOrder.first(where: { $0.tab.id == ui.selection })?.slot else { return }
        panels[slot]?.makeKeyAndOrderFront(nil)
    }

    func endFocus() {
        ui.focused = false
        ui.selection = nil
        // Ordered out and back, so they give up the keyboard to whatever had it.
        for panel in panels.values where panel.isVisible || panel.allowsKey {
            panel.allowsKey = false
            panel.orderOut(nil)
        }
        refresh()
    }

    /// Up and down the Tabs from the keyboard, from one place on the edge to the next.
    func move(_ step: Int) {
        let order = keyboardOrder
        guard !order.isEmpty else { return }
        let i = order.firstIndex { $0.tab.id == ui.selection } ?? 0
        ui.selection = order[(i + step + order.count) % order.count].tab.id
        keyToSelection()
    }

    var selected: EdgeTab? { AppModel.shared.tabBoard.tabs.first { $0.id == ui.selection } }
}

/// Becomes key only when the tabs shortcut asks: otherwise clicking a Tab's buttons leaves the keyboard where it was.
/// Stays against its edge whatever resizes it: SwiftUI's content resizes a window from its top-left corner.
final class TabsWindow: NSPanel {
    var allowsKey = false
    /// The screen edge it stands against, and the x of that edge.
    var edge = TabEdge.right
    var edgeX: CGFloat?
    enum Anchor { case top(CGFloat), bottom(CGFloat) }
    /// The y its top or its bottom keeps.
    var anchor: Anchor?
    /// How low and high it can go: the screen, less the menu bar and the Dock.
    var bounds: (min: CGFloat, max: CGFloat) = (0, .greatestFiniteMagnitude)

    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        var r = frameRect
        if let edgeX { r.origin.x = edge == .right ? edgeX - r.width : edgeX }
        switch anchor {
        case .top(let y)?: r.origin.y = y - r.height
        case .bottom(let y)?: r.origin.y = y
        case nil: break
        }
        r.origin.y = min(max(bounds.min, r.origin.y), max(bounds.min, bounds.max - r.height))
        super.setFrame(r, display: flag)
    }
}

// MARK: The views

struct TabsView: View {
    let model: AppModel
    let ui: TabsUI
    let controller: TabsController
    /// The place on the edge this panel holds.
    let slot: TabSlot
    @FocusState private var keyboard: Bool

    private var edge: TabEdge { model.tabEdge }
    private var metrics: TabMetrics { TabMetrics(model.tabSize, pile: model.tabPile) }

    var body: some View {
        let column = controller.columns.first { $0.slot == slot }
        VStack(alignment: edge == .right ? .trailing : .leading, spacing: metrics.spacing) {
            if let column {
                if ui.focused {
                    // Every Tab on its own, groups too, for the keyboard to step through.
                    ForEach(column.tabs) { tab in
                        TabCard(tab: tab, model: model, controller: controller, edge: edge, metrics: metrics,
                                compact: ui.selection != tab.id, selected: ui.selection == tab.id)
                    }
                } else {
                    ForEach(column.shown) { stack in row(stack) }
                    if !column.more.isEmpty { moreRow(column.more) }
                }
            }
        }
        .padding(.vertical, ui.focused ? 8 : 0)
        .fixedSize()
        .focusable(ui.focused)
        .focusEffectDisabled()
        .focused($keyboard)
        .onKeyPress(.upArrow) { controller.move(-1); return .handled }
        .onKeyPress(.downArrow) { controller.move(1); return .handled }
        .onKeyPress(.escape) { controller.endFocus(); return .handled }
        .onKeyPress(.return) {
            if let tab = controller.selected { model.act(on: tab) }
            return .handled
        }
        .onKeyPress(keys: [.delete, .deleteForward]) { _ in
            if let tab = controller.selected {
                controller.move(1)
                model.dismissTab(tab)
            }
            return .handled
        }
        .onChange(of: ui.focused) { _, on in keyboard = on }
        .onAppear { keyboard = ui.focused }
    }

    @ViewBuilder private func row(_ stack: TabStack) -> some View {
        Group {
            if ui.expanded == stack.id {
                if stack.isGroup {
                    GroupCard(stack: stack, model: model, edge: edge, metrics: metrics)
                } else {
                    TabCard(tab: stack.first, model: model, controller: controller, edge: edge, metrics: metrics,
                            compact: false, selected: false)
                }
            } else {
                CollapsedTab(stack: stack, look: model.tabLook, edge: edge, metrics: metrics, now: model.now)
            }
        }
        .background(RowFrame(ui: ui, slot: slot, id: stack.id))
        .onTapGesture { controller.pin(stack.id) }
    }

    @ViewBuilder private func moreRow(_ more: [TabStack]) -> some View {
        let id = TabsUI.more(slot)
        let tabs = more.flatMap(\.tabs)
        Group {
            if ui.expanded == id {
                MoreCard(tabs: tabs, model: model, edge: edge, metrics: metrics)
            } else {
                Text("+\(tabs.count)")
                    .font(.system(size: metrics.labelFont, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: (model.tabLook == .labelled ? 44 : 30) * metrics.scale,
                           height: metrics.rowHeight(model.tabLook))
                    .background(Color(white: 0.25).opacity(0.92), in: EdgeShape(edge: edge, radius: 8))
            }
        }
        .background(RowFrame(ui: ui, slot: slot, id: id))
        .onTapGesture { controller.pin(id) }
    }
}

/// How big each part of a Tab is, Regular or Mini.
struct TabMetrics {
    var scale: CGFloat

    /// A group's Tabs piled askew behind it.
    var messy = false

    init(_ size: TabSize, pile: TabPile = .neat) {
        scale = size == .mini ? 0.72 : 1
        messy = pile == .messy
    }

    var mini: Bool { scale < 1 }
    var spacing: CGFloat { mini ? 4 : 6 }
    func rowHeight(_ look: TabLook, stacked: Bool = false) -> CGFloat {
        let height: CGFloat = switch look {
        case .icon: 30 * scale
        case .slim: 44 * scale
        case .labelled: 34 * scale
        }
        return height + (stacked ? stackDepth + pileTop : 0)
    }
    /// How far the Tabs behind a stack peek out below it.
    var stackDepth: CGFloat { (mini ? 2.5 : 3.5) * (messy ? 3 : 2) }
    /// Room above a messy pile for the corners that stick up.
    var pileTop: CGFloat { messy ? 6 * scale : 0 }
    var slimWidth: CGFloat { mini ? 6 : 10 }
    var labelFont: CGFloat { 12 * scale }
    var initial: CGFloat { 20 * scale }
    var labelWidth: CGFloat { 110 * scale }
    var cardWidth: CGFloat { mini ? 236 : 300 }
}

/// Notes where a Tab, or its card, is drawn.
private struct RowFrame: View {
    let ui: TabsUI
    let slot: TabSlot
    let id: String

    var body: some View {
        GeometryReader { g in
            Color.clear
                .onAppear { ui.rowFrames[slot, default: [:]][id] = g.frame(in: .global) }
                .onChange(of: g.frame(in: .global)) { _, frame in ui.rowFrames[slot, default: [:]][id] = frame }
        }
    }
}

/// A Tab's icon: an SF Symbol, in the Tab's text colour, or an app's own icon, by its bundle id; a dashed app for a
/// name that's neither (a symbol from a newer macOS, or an app that isn't installed).
struct TabIcon: View {
    let name: String
    let size: CGFloat
    let color: Color

    var body: some View {
        if NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil {
            Image(systemName: name)
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(color)
        } else if let image = Self.appIcon(name) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: size * 1.35, height: size * 1.35)
        } else {
            Image(systemName: "app.dashed")
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(color.opacity(0.7))
        }
    }

    @MainActor private static var appIcons: [String: NSImage] = [:]

    /// The icon of the app with this bundle id, if it's installed; looked up once.
    @MainActor static func appIcon(_ bundleID: String) -> NSImage? {
        if let icon = appIcons[bundleID] { return icon }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        appIcons[bundleID] = icon
        return icon
    }
}

/// Rounded on the side away from the screen's edge, square against it.
struct EdgeShape: Shape {
    var edge: TabEdge
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let r = RectangleCornerRadii(topLeading: edge == .right ? radius : 0, bottomLeading: edge == .right ? radius : 0,
                                     bottomTrailing: edge == .left ? radius : 0, topTrailing: edge == .left ? radius : 0)
        return UnevenRoundedRectangle(cornerRadii: r).path(in: rect)
    }
}

/// A Tab at rest: a square with its Source's initial, a sliver of its colour, or the initial and a few words, with
/// how near its deadline is. A group is the same with the Tabs behind it peeking out below, and how many.
struct CollapsedTab: View {
    let stack: TabStack
    let look: TabLook
    let edge: TabEdge
    let metrics: TabMetrics
    let now: Date

    var body: some View {
        let layers = stack.isGroup ? min(metrics.messy ? 3 : 2, stack.tabs.count - 1) : 0
        ZStack(alignment: .top) {
            // The Tabs behind, each a little lower and narrower, darker the further back; or, messy, askew.
            ForEach((0..<layers).reversed(), id: \.self) { i in
                let step = metrics.stackDepth / CGFloat(metrics.messy ? 3 : 2) * CGFloat(i + 1)
                let card = EdgeShape(edge: edge, radius: radius)
                    .fill(Color(stack.tint.darkened(0.14 * Double(i + 1))))
                if metrics.messy {
                    let tilt = Self.tilt(stack.tabs[i + 1].id)
                    card
                        .overlay(EdgeShape(edge: edge, radius: radius).stroke(.black.opacity(0.12), lineWidth: 0.5))
                        .rotationEffect(.degrees(tilt * maxTilt), anchor: edge == .right ? .trailing : .leading)
                        .offset(x: (edge == .right ? -1 : 1) * (tilt + 1) * 3, y: step)
                } else {
                    card
                        .padding(edge == .right ? .leading : .trailing, step * 1.5)
                        .offset(y: step)
                }
            }
            front
                .rotationEffect(.degrees(metrics.messy && stack.isGroup ? Self.tilt(stack.first.id) * 1.5 : 0),
                                anchor: edge == .right ? .trailing : .leading)
        }
        .padding(.top, stack.isGroup ? metrics.pileTop : 0)
        .padding(.bottom, stack.isGroup ? metrics.stackDepth : 0)
        // Room on the inner side for a messy pile's corners.
        .padding(edge == .right ? .leading : .trailing, stack.isGroup && metrics.messy ? 8 : 0)
        .help(stack.isGroup ? "\(stack.title): \(stack.tabs.count) from \(stack.sourceName)" : stack.first.title)
    }

    /// The most a card behind leans, in degrees: less on a wide Tab, whose far corner would swing further.
    private var maxTilt: Double { look == .labelled ? 4.5 : 13 }

    /// How a card leans, from -1 to 1: from its id, so a pile looks the same every time it's drawn.
    static func tilt(_ id: String) -> Double {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in id.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100_0000_01b3
        }
        let t = Double(hash % 2001) / 1000 - 1
        // Never quite straight, or it would look neat.
        return t < 0 ? min(t, -0.35) : max(t, 0.35)
    }

    private var radius: CGFloat {
        switch look {
        case .icon: 7 * metrics.scale
        case .slim: 4
        case .labelled: 8
        }
    }

    private var initial: String {
        String((stack.isGroup ? stack.title : stack.sourceName).prefix(1)).uppercased()
    }

    @ViewBuilder private var front: some View {
        let tint = Color(stack.tint)
        let text = Color(stack.tint.readableText)
        let progress = stack.first.progress(at: now)
        switch look {
        case .icon:
            // Its icon, or its Source's initial; a stack shows how many beside it, and its colour says who from.
            Group {
                if stack.isGroup {
                    HStack(spacing: 1) {
                        if let icon = stack.icon { TabIcon(name: icon, size: 10 * metrics.scale, color: text) }
                        Text("\(stack.tabs.count)")
                            .font(.system(size: (stack.icon == nil ? 13 : 11) * metrics.scale, weight: .heavy,
                                          design: .rounded).monospacedDigit())
                    }
                } else if let icon = stack.icon {
                    TabIcon(name: icon, size: 15 * metrics.scale, color: text)
                } else {
                    Text(initial).font(.system(size: 13 * metrics.scale, weight: .heavy, design: .rounded))
                }
            }
                .foregroundStyle(text)
                .frame(width: metrics.rowHeight(.icon) + (stack.isGroup && stack.icon != nil ? 6 * metrics.scale : 0),
                       height: metrics.rowHeight(.icon))
                .background(tint)
                .overlay(alignment: .bottom) { sliver(progress, text: text, height: 2.5) }
                .clipShape(EdgeShape(edge: edge, radius: radius))
        case .slim:
            ZStack(alignment: .bottom) {
                tint.opacity(0.55)
                // The sliver fills from the bottom toward the deadline; without one, the whole Tab is its colour.
                tint.frame(height: metrics.rowHeight(.slim) * (progress ?? 1))
            }
            .background(Color(stack.tint.darkened(0.3)))
            .frame(width: metrics.slimWidth, height: metrics.rowHeight(.slim))
            .clipShape(EdgeShape(edge: edge, radius: radius))
            .overlay(alignment: .center) {
                if stack.isOverdue(at: now) { Circle().fill(.white).frame(width: 4, height: 4) }
            }
        case .labelled:
            HStack(spacing: 7 * metrics.scale) {
                Group {
                    if let icon = stack.icon {
                        TabIcon(name: icon, size: 12 * metrics.scale, color: text)
                    } else {
                        Text(initial).font(.system(size: 11 * metrics.scale, weight: .heavy, design: .rounded))
                    }
                }
                .frame(width: metrics.initial, height: metrics.initial)
                .background(text.opacity(0.18), in: .circle)
                Text(stack.title)
                    .font(.system(size: metrics.labelFont, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: metrics.labelWidth, alignment: .leading)
                    .fixedSize(horizontal: true, vertical: false)
                if stack.isGroup { count(text: text, tint: tint) }
            }
            .foregroundStyle(text)
            .padding(.leading, (edge == .right ? 8 : 10) * metrics.scale)
            .padding(.trailing, (edge == .right ? 10 : 8) * metrics.scale)
            .frame(height: metrics.rowHeight(.labelled))
            .background(tint)
            .overlay(alignment: .bottom) { sliver(progress, text: text, height: 3) }
            .clipShape(EdgeShape(edge: edge, radius: radius))
        }
    }

    /// How many are in the stack.
    private func count(text: Color, tint: Color) -> some View {
        Text("\(stack.tabs.count)")
            .font(.system(size: 10 * metrics.scale, weight: .heavy, design: .rounded)
                .monospacedDigit())
            .foregroundStyle(tint)
            .padding(.horizontal, 5)
            .frame(minWidth: 16 * metrics.scale)
            .background(text, in: .capsule)
    }

    /// How near the deadline is, along the bottom, filling toward the screen's edge.
    @ViewBuilder private func sliver(_ progress: Double?, text: Color, height: CGFloat) -> some View {
        if let progress {
            GeometryReader { g in
                Rectangle().fill(text.opacity(0.85))
                    .frame(width: g.size.width * progress, height: height)
                    .frame(maxWidth: .infinity, maxHeight: .infinity,
                           alignment: edge == .right ? .bottomTrailing : .bottomLeading)
            }
        }
    }
}

/// A group slid out: each of its Tabs, nearest deadline first, with Open and Dismiss, and Dismiss All.
struct GroupCard: View {
    let stack: TabStack
    let model: AppModel
    let edge: TabEdge
    let metrics: TabMetrics

    var body: some View {
        let tint = Color(stack.tint)
        let text = Color(stack.tint.readableText)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        if let icon = stack.icon { TabIcon(name: icon, size: 11, color: text) }
                        Text(stack.sourceName).font(.caption.weight(.bold)).textCase(.uppercase).opacity(0.8)
                    }
                    Text("\(stack.title) · \(stack.tabs.count)")
                        .font(metrics.mini ? .callout.weight(.semibold) : .headline)
                }
                Spacer()
                Button("Dismiss All") { model.dismissTabs(stack.tabs) }
                    .buttonStyle(TabButtonStyle(fill: text.opacity(0.18), label: text, mini: metrics.mini))
                    .font(metrics.mini ? .caption.weight(.semibold) : .callout.weight(.semibold))
            }
            .padding(.horizontal, metrics.mini ? 10 : 12)
            .padding(.top, metrics.mini ? 7 : 10)
            .padding(.bottom, 8)
            let list = VStack(spacing: 4) {
                ForEach(stack.tabs) { tab in item(tab, text: text, tint: tint) }
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 6)
            // Five fit as they are; past that, they scroll.
            if stack.tabs.count > 5 {
                ScrollView { list }.frame(height: metrics.mini ? 220 : 260)
            } else {
                list
            }
        }
        .foregroundStyle(text)
        .frame(width: metrics.cardWidth, alignment: .leading)
        .background(tint.opacity(0.97))
        .clipShape(EdgeShape(edge: edge, radius: 10))
        .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
    }

    private func item(_ tab: EdgeTab, text: Color, tint: Color) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(tab.title).font(metrics.mini ? .caption.weight(.semibold) : .callout.weight(.semibold))
                    .lineLimit(1)
                Text(status(tab)).font(.caption2.monospacedDigit()).opacity(0.75).lineLimit(1)
            }
            Spacer(minLength: 4)
            if let url = tab.link {
                Button("Open") { model.openTab(tab) }
                    .buttonStyle(TabButtonStyle(fill: text, label: tint, mini: true))
                    .help(url.absoluteString)
            } else if let action = tab.actions.first {
                Button(action.title) { model.answer(action, onTab: tab) }
                    .buttonStyle(TabButtonStyle(fill: text, label: tint, mini: true))
            }
            Button { model.dismissTab(tab) } label: { Image(systemName: "xmark") }
                .buttonStyle(TabButtonStyle(fill: text.opacity(0.18), label: text, mini: true))
                .help("Dismiss")
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 8)
        .padding(.vertical, metrics.mini ? 5 : 7)
        .background(text.opacity(0.1), in: .rect(cornerRadius: 7))
    }

    private func status(_ tab: EdgeTab) -> String {
        if tab.stale { return "Overdue" }
        guard let deadline = tab.deadline else { return tab.notes ?? "No deadline" }
        if deadline <= model.now { return "Slapping" }
        let minutes = Int(deadline.timeIntervalSince(model.now) / 60)
        return minutes < 60 ? "Slaps in \(max(1, minutes)) min" : "Slaps at \(deadline.formatted(date: .omitted, time: .shortened))"
    }
}

/// A Tab slid out: who it's from, when it slaps, what it says, and its buttons.
struct TabCard: View {
    let tab: EdgeTab
    let model: AppModel
    let controller: TabsController
    let edge: TabEdge
    let metrics: TabMetrics
    /// One line, for the Tabs the keyboard isn't on.
    var compact = false
    var selected = false

    var body: some View {
        let tint = Color(tab.tint)
        let text = Color(tab.tint.readableText)
        VStack(alignment: .leading, spacing: compact ? 2 : 6) {
            HStack {
                HStack(spacing: 4) {
                    if let icon = tab.icon { TabIcon(name: icon, size: 11, color: text) }
                    Text(tab.sourceName).font(.caption.weight(.bold)).textCase(.uppercase).opacity(0.8)
                }
                Spacer()
                Text(status).font(.caption.monospacedDigit()).opacity(0.8)
            }
            Text(tab.title)
                .font(compact || metrics.mini ? .callout.weight(.semibold) : .headline)
                .lineLimit(compact ? 1 : 3)
                .fixedSize(horizontal: false, vertical: true)
            if !compact {
                if let notes = tab.notes, !notes.isEmpty {
                    Text(notes).font(metrics.mini ? .caption : .callout).opacity(0.85).lineLimit(4).fixedSize(horizontal: false, vertical: true)
                }
                buttons(text: text, tint: tint).padding(.top, 2)
                    .controlSize(metrics.mini ? .small : .regular)
            }
        }
        .foregroundStyle(text)
        .padding(.horizontal, metrics.mini ? 10 : 12)
        .padding(.top, metrics.mini ? 7 : 10)
        .padding(.bottom, compact ? 8 : (metrics.mini ? 9 : 12))
        .frame(width: metrics.cardWidth, alignment: .leading)
        .background(tint.opacity(0.97))
        .overlay(alignment: .bottom) {
            if let progress = tab.progress(at: model.now) {
                GeometryReader { g in
                    Rectangle().fill(text.opacity(0.85))
                        .frame(width: g.size.width * progress, height: 3)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                }
            }
        }
        .overlay {
            if selected { EdgeShape(edge: edge, radius: 10).stroke(text, lineWidth: 2) }
        }
        .clipShape(EdgeShape(edge: edge, radius: 10))
        .shadow(color: .black.opacity(compact ? 0 : 0.25), radius: 8, y: 2)
    }

    private var status: String {
        let now = model.now
        if tab.stale { return "Overdue" }
        guard let deadline = tab.deadline else { return "No deadline" }
        let minutes = Int(deadline.timeIntervalSince(now) / 60)
        if deadline <= now { return "Slapping" }
        if minutes < 1 { return "Slaps in under a minute" }
        if minutes < 60 { return "Slaps in \(minutes) min" }
        return "Slaps at \(deadline.formatted(date: .omitted, time: .shortened))"
    }

    @ViewBuilder private func buttons(text: Color, tint: Color) -> some View {
        HStack(spacing: 6) {
            if let url = tab.link {
                Button { model.openTab(tab) } label: {
                    Text(ExternalAlert.app(for: url).map { "Open in \($0)" } ?? "Open \(url.host ?? "Link")")
                        .lineLimit(1)
                }
                .buttonStyle(TabButtonStyle(fill: tab.actions.isEmpty ? text : text.opacity(0.18),
                                            label: tab.actions.isEmpty ? tint : text, mini: metrics.mini))
                .help(url.absoluteString)
            }
            ForEach(Array(tab.actions.enumerated()), id: \.offset) { i, action in
                Button(action.title) { model.answer(action, onTab: tab) }
                    .buttonStyle(TabButtonStyle(fill: i == 0 ? text : text.opacity(0.18), label: i == 0 ? tint : text,
                                                mini: metrics.mini))
            }
            Spacer(minLength: 0)
            Menu {
                Button("Dismiss All from \(tab.sourceName)") { model.dismissTabs(from: tab.sourceName) }
                Button("Dismiss All Tabs") { model.dismissAllTabs() }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .tint(text)
            Button("Dismiss") { model.dismissTab(tab) }
                .buttonStyle(TabButtonStyle(fill: text.opacity(0.18), label: text, mini: metrics.mini))
        }
        .font(metrics.mini ? .caption.weight(.semibold) : .callout.weight(.semibold))
    }
}

/// The Tabs that don't fit, listed when you hover over "+N".
struct MoreCard: View {
    let tabs: [EdgeTab]
    let model: AppModel
    let edge: TabEdge
    let metrics: TabMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(tabs.count) more").font(.caption.weight(.bold)).textCase(.uppercase).opacity(0.7)
                .padding([.horizontal, .top], 12).padding(.bottom, 6)
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(tabs) { tab in
                        HStack(spacing: 8) {
                            Circle().fill(Color(tab.tint)).frame(width: 9, height: 9)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(tab.title).font(.callout.weight(.semibold)).lineLimit(1)
                                Text(tab.sourceName).font(.caption).opacity(0.7)
                            }
                            Spacer(minLength: 4)
                            if tab.link != nil {
                                Button { model.openTab(tab) } label: { Image(systemName: "arrow.up.right.square") }
                                    .buttonStyle(.borderless)
                            }
                            Button { model.dismissTab(tab) } label: { Image(systemName: "xmark.circle.fill") }
                                .buttonStyle(.borderless)
                                .help("Dismiss")
                        }
                    }
                }
                .padding(.horizontal, 12)
            }
            .frame(height: min(CGFloat(tabs.count) * 40, 280))
            Button("Dismiss All Tabs") { model.dismissAllTabs() }
                .buttonStyle(.borderless)
                .font(.callout)
                .padding(12)
        }
        .foregroundStyle(.white)
        .frame(width: metrics.cardWidth, alignment: .leading)
        .background(Color(white: 0.18).opacity(0.97))
        .clipShape(EdgeShape(edge: edge, radius: 10))
    }
}

/// A capsule button that looks the same whether or not Slaps is active, as the alert's do.
struct TabButtonStyle: ButtonStyle {
    var fill: Color
    var label: Color
    var mini = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, mini ? 8 : 10).padding(.vertical, mini ? 3 : 5)
            .foregroundStyle(label)
            .background(fill, in: .capsule)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(.capsule)
    }
}
