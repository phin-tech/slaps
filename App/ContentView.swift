import SlapsKit
import SwiftUI

/// The menu bar popover: what's coming up, with Join buttons, and pausing.
struct ContentView: View {
    let model: AppModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.access != .granted {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Slaps needs your calendars").font(.headline)
                    Text("It only reads them, to know when to alert you.").font(.callout).foregroundStyle(.secondary)
                    Button(model.access == .notAsked ? "Allow Calendar Access" : "Open Privacy Settings…") {
                        model.requestAccess()
                    }
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
                let meetings = Array(model.upcoming.prefix(8))
                if meetings.isEmpty {
                    Text("Nothing in the next 24 hours").foregroundStyle(.secondary).padding(.vertical, 8)
                } else {
                    ForEach(meetings) { MeetingRow(meeting: $0, model: model) }
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
        .onAppear { model.fetch() }
    }
}

private struct MeetingRow: View {
    let meeting: Meeting
    let model: AppModel

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(meeting.title).lineLimit(1)
                Text(when).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let link = meeting.link {
                Button("Join") { model.join(meeting) }
                    .help("Join on \(link.service)")
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
    }

    private var when: String {
        let time = meeting.start.formatted(date: .omitted, time: .shortened)
        let now = model.now
        if meeting.start <= now { return "Now · until \(meeting.end.formatted(date: .omitted, time: .shortened))" }
        let minutes = Int(meeting.start.timeIntervalSince(now) / 60)
        let day = Calendar.current.isDateInToday(meeting.start) ? "" : "Tomorrow "
        return minutes < 60 ? "\(time) · in \(minutes + 1) min" : "\(day)\(time) · \(meeting.calendarTitle)"
    }
}

/// The menu bar item: a bell, and how long until the next meeting once it's within the hour.
struct MenuBarLabel: View {
    let model: AppModel

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: model.isPaused ? "bell.slash" : (model.alerting.isEmpty ? "bell" : "bell.and.waves.left.and.right"))
            if !model.isPaused, let next = model.next {
                let minutes = Int(next.start.timeIntervalSince(model.now) / 60) + 1
                if minutes <= 60 { Text("\(minutes)m") }
            }
        }
    }
}
