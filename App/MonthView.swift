import SlapsKit
import SwiftUI

/// A month at a time, with a dot under each day that has something on, for the menu bar popover. Picking a day shows
/// its agenda below.
struct MonthView: View {
    let model: AppModel
    @Binding var selected: Date
    @State private var month: Date

    private var calendar: Calendar { .current }

    init(model: AppModel, selected: Binding<Date>) {
        self.model = model
        _selected = selected
        _month = State(initialValue: Calendar.current.dateInterval(of: .month, for: selected.wrappedValue)!.start)
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(month.formatted(.dateTime.month(.wide).year())).font(.headline)
                Spacer()
                Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                    .help("Previous month")
                Button("Today") {
                    selected = calendar.startOfDay(for: Date())
                    month = calendar.dateInterval(of: .month, for: selected)!.start
                }
                .disabled(calendar.isDateInToday(selected) && calendar.isDate(month, equalTo: Date(), toGranularity: .month))
                Button { shift(1) } label: { Image(systemName: "chevron.right") }
                    .help("Next month")
            }
            .buttonStyle(.borderless)
            let busy = model.busyDays(around: month)
            Grid(horizontalSpacing: 0, verticalSpacing: 2) {
                GridRow {
                    ForEach(weekdaySymbols, id: \.self) { symbol in
                        Text(symbol).font(.caption2.weight(.medium)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                    }
                }
                ForEach(0..<6, id: \.self) { row in
                    GridRow {
                        ForEach(0..<7, id: \.self) { column in
                            let day = gridDays[row * 7 + column]
                            DayCell(day: day,
                                    inMonth: calendar.isDate(day, equalTo: month, toGranularity: .month),
                                    isToday: calendar.isDateInToday(day),
                                    isSelected: calendar.isDate(day, inSameDayAs: selected),
                                    isBusy: busy.contains(day))
                                .onTapGesture { selected = day }
                        }
                    }
                }
            }
        }
        .onChange(of: selected) { _, day in
            if !calendar.isDate(day, equalTo: month, toGranularity: .month) {
                month = calendar.dateInterval(of: .month, for: day)!.start
            }
        }
    }

    private func shift(_ months: Int) {
        month = calendar.date(byAdding: .month, value: months, to: month)!
    }

    /// Very short weekday names, starting on the locale's first day of the week.
    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    /// Six weeks from the start of the week the month starts in, each day at its start.
    private var gridDays: [Date] {
        let offset = (calendar.component(.weekday, from: month) - calendar.firstWeekday + 7) % 7
        let start = calendar.date(byAdding: .day, value: -offset, to: month)!
        return (0..<42).map { calendar.date(byAdding: .day, value: $0, to: start)! }
    }
}

private struct DayCell: View {
    let day: Date
    let inMonth: Bool
    let isToday: Bool
    let isSelected: Bool
    let isBusy: Bool

    var body: some View {
        VStack(spacing: 1) {
            Text(day.formatted(.dateTime.day()))
                .font(.callout.monospacedDigit().weight(isToday ? .bold : .regular))
                .foregroundStyle(isSelected ? Color.white : isToday ? Color.accentColor : inMonth ? Color.primary : Color.secondary)
                .frame(width: 26, height: 22)
                .background {
                    if isSelected { Circle().fill(isToday ? Color.accentColor : Color.secondary) }
                }
            Circle()
                .fill(isBusy ? Color.secondary : Color.clear)
                .frame(width: 4, height: 4)
        }
        .frame(maxWidth: .infinity)
        .opacity(inMonth ? 1 : 0.5)
        .contentShape(.rect)
    }
}
