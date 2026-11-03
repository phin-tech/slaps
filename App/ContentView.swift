import SlapsKit
import SwiftUI

/// The menu bar popover: a month calendar, the chosen day's agenda with Join buttons, and pausing.
struct ContentView: View {
    let model: AppModel
    @Environment(\.openSettings) private var openSettings
    @State private var selected = Calendar.current.startOfDay(for: Date())

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonthView(model: model, selected: $selected)
            Divider()
            if model.access != .granted {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Slaps needs your calendars").font(.headline)
                    Text("It only reads them, to know when to alert you.").font(.callout).foregroundStyle(.secondary)
                    Button(model.access == .notAsked ? "Allow Calendar Access" : "Open Privacy Settings…") {
                        model.requestAccess()
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                if model.isPaused, let until = model.pausedUntil {
                    HStack {
                        Label("Paused until \(until.formatted(date: .omitted, time: .shortened))", systemImage: "bell.slash")
                        Spacer()
                        Button("Resume") { model.resume() }
                    }
                    .padding(8)
                    .background(.yellow.opacity(0.2), in: .rect(cornerRadius: 6))
                }
                if !model.heldForSharing.isEmpty {
                    HStack {
                        Label("Held while you share your screen", systemImage: "rectangle.on.rectangle")
                        Spacer()
                        Button("Show Now") { model.showHeld() }
                    }
                    .padding(8)
                    .background(.orange.opacity(0.2), in: .rect(cornerRadius: 6))
                }
                Text(dayTitle).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                let items = model.agenda(for: selected)
                if items.isEmpty {
                    Text("Nothing on").foregroundStyle(.secondary).padding(.vertical, 4)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(items) { MeetingRow(meeting: $0, model: model) }
                        }
                    }
                    .frame(maxHeight: 280)
                    .fixedSize(horizontal: false, vertical: items.count <= 6)
                }
            }
            Divider()
            HStack {
                Menu("Pause") {
                    Button("For 30 minutes") { model.pause(for: 30 * 60) }
                    Button("For 1 hour") { model.pause(for: 3600) }
                    Button("For 2 hours") { model.pause(for: 2 * 3600) }
                    Button("Until tomorrow") { model.pauseUntilTomorrow() }
                }
                .fixedSize()
                Button("Test Alert") { model.testAlert() }
                Spacer()
                Button {
                    NSApp.activate()
                    openSettings()
                } label: { Image(systemName: "gearshape") }
                    .help("Settings")
                    .keyboardShortcut(",")
                Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
                    .help("Quit Slaps")
                    .keyboardShortcut("q")
            }
            .buttonStyle(.borderless)
        }
        .padding(12)
        .frame(width: 340)
        .onAppear {
            selected = Calendar.current.startOfDay(for: Date())
            model.fetch()
        }
    }

    private var dayTitle: String {
        let cal = Calendar.current
        let date = selected.formatted(.dateTime.weekday(.wide).month(.wide).day())
        if cal.isDateInToday(selected) { return "Today · \(date)" }
        if cal.isDateInTomorrow(selected) { return "Tomorrow · \(date)" }
        return date
    }
}

private struct MeetingRow: View {
    let meeting: Meeting
    let model: AppModel

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            if meeting.kind == .reminder {
                Button { model.complete(meeting) } label: { Image(systemName: "circle") }
                    .buttonStyle(.borderless)
                    .help("Mark done")
            }
            if meeting.kind == .event {
                RoundedRectangle(cornerRadius: 1.5).fill(color).frame(width: 3, height: 28)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(meeting.title).lineLimit(1)
                    if let badge { Text(badge).font(.caption2).foregroundStyle(.secondary) }
                }
                Text(when).font(.caption).foregroundStyle(.secondary)
            }
            .opacity(isOver ? 0.5 : 1)
            Spacer()
            if let link = meeting.link, meeting.kind == .event, !isOver {
                Button("Join") { model.join(meeting) }
                    .help("Join on \(link.service)")
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            if meeting.kind == .event && !isOver && !meeting.isAllDay { overrideMenu }
        }
    }

    private var isOver: Bool { meeting.kind == .event && meeting.end <= model.now }

    private var color: Color {
        model.calendars.first { $0.id == meeting.calendarID }?.color ?? .secondary
    }

    /// What's different about this one's alert.
    private var badge: String? {
        if meeting.kind == .event && !meeting.isAllDay && !isOver && !model.alerts(for: meeting) { return "🔕" }
        return switch model.overrides.override(for: meeting) {
        case .skip: "🔕"
        case .leadTime(let t): t == 0 ? "⏰ at start" : "⏰ \(Int(t / 60))m"
        case nil: nil
        }
    }

    private var overrideMenu: some View {
        Menu {
            Section(meeting.isRecurring ? "This occurrence" : "This event") { choices(.occurrence) }
            if meeting.isRecurring {
                Section("Every occurrence") { choices(.series) }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Alert options for this event")
    }

    @ViewBuilder private func choices(_ scope: Overrides.Scope) -> some View {
        let current = model.overrides.scope(for: meeting) == scope ? model.overrides.override(for: meeting) : nil
        choice("Usual alert", nil, scope, current)
        choice("No alert", .skip, scope, current)
        choice("When it starts", .leadTime(0), scope, current)
        ForEach([2, 5, 10, 15], id: \.self) { m in
            choice("\(m) minutes before", .leadTime(Double(m * 60)), scope, current)
        }
    }

    private func choice(_ title: String, _ o: AlertOverride?, _ scope: Overrides.Scope, _ current: AlertOverride?) -> some View {
        Button {
            model.setOverride(o, for: meeting, scope: scope)
        } label: {
            if o == current { Label(title, systemImage: "checkmark") } else { Text(title) }
        }
    }

    private var when: String {
        let time = meeting.start.formatted(date: .omitted, time: .shortened)
        let now = model.now
        let day = Calendar.current.isDateInToday(meeting.start) ? "" : "Tomorrow "
        if meeting.kind == .reminder {
            return meeting.start <= now ? "Overdue · \(meeting.calendarTitle)" : "Due \(day)\(time) · \(meeting.calendarTitle)"
        }
        let endTime = meeting.end.formatted(date: .omitted, time: .shortened)
        if meeting.isAllDay { return "All day · \(meeting.calendarTitle)" }
        if meeting.end <= now { return "\(time) – \(endTime)" }
        if meeting.start <= now { return "Now · until \(endTime)" }
        let minutes = Int(meeting.start.timeIntervalSince(now) / 60)
        return minutes < 60 ? "\(time) · in \(minutes + 1) min" : "\(time) – \(endTime) · \(meeting.calendarTitle)"
    }
}

/// The menu bar item: a bell, and how long until the next meeting once it's within the hour.
struct MenuBarLabel: View {
    let model: AppModel

    var body: some View {
        HStack(spacing: 3) {
            if model.showDateInMenuBar {
                Text(model.now.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
            }
            Image(systemName: model.isPaused ? "bell.slash" : (model.alerting.isEmpty && model.heldForSharing.isEmpty ? "bell" : "bell.and.waves.left.and.right"))
            if !model.isPaused, let next = model.next {
                let minutes = Int(next.start.timeIntervalSince(model.now) / 60) + 1
                if minutes <= 60 { Text("\(minutes)m") }
            }
        }
    }
}
