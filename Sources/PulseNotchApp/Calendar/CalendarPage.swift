import PulseNotchCore
import SwiftUI

struct CalendarPage: View {
    @ObservedObject var model: CalendarFeatureModel
    let date: Date
    let testingSchedule: CalendarEventSchedule?

    @State private var selectedDate: Date
    @State private var showsAllEvents = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL

    init(model: CalendarFeatureModel, date: Date, testingSchedule: CalendarEventSchedule? = nil) {
        self.model = model
        self.date = date
        self.testingSchedule = testingSchedule
        _selectedDate = State(initialValue: date)
    }

    var body: some View {
        Group {
            switch testingSchedule.map(CalendarFeatureModel.State.loaded) ?? model.state {
            case .loading:
                placeholder { ProgressView().controlSize(.small) }
            case let .loaded(schedule):
                calendarContent(schedule)
            case .accessDenied:
                placeholder { emptyState("Calendar access is off", image: "calendar.badge.exclamationmark") }
            case .unavailable:
                placeholder { emptyState("Calendar is unavailable", image: "exclamationmark.triangle") }
            }
        }
        .onChange(of: Calendar.autoupdatingCurrent.startOfDay(for: date)) { previousDay, newDay in
            if Calendar.autoupdatingCurrent.isDate(selectedDate, inSameDayAs: previousDay) {
                selectedDate = newDay
                showsAllEvents = false
            }
        }
    }

    private func calendarContent(_ schedule: CalendarEventSchedule) -> some View {
        let events = schedule.events(on: selectedDate)
        let initialEvents = Array(schedule.currentAndUpcoming(on: selectedDate, relativeTo: date).prefix(2))
        let visibleEvents = showsAllEvents ? events : initialEvents

        return HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 10) {
                dayHeader
                agenda(events: events, visibleEvents: visibleEvents)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            MonthGrid(selectedDate: selectedDate) { day in
                withAnimation(reduceMotion ? nil : .smooth(duration: 0.2)) {
                    selectedDate = day
                    showsAllEvents = false
                }
            }
            .frame(width: 190, height: 160, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var dayHeader: some View {
        VStack(alignment: .leading, spacing: -2) {
            Text(selectedDate, format: .dateTime.weekday(.wide))
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .textCase(.uppercase)
                .foregroundStyle(.pink)
            Text(selectedDate, format: .dateTime.day())
                .font(.system(size: 42, weight: .medium, design: .rounded))
                .monospacedDigit()
        }
    }

    @ViewBuilder
    private func agenda(events: [CalendarEvent], visibleEvents: [CalendarEvent]) -> some View {
        if events.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text("No events").font(.title3.weight(.semibold))
                Text("This day is clear").font(.callout).foregroundStyle(.secondary)
            }
            .padding(.top, 12)
        } else if visibleEvents.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text("No upcoming events").font(.title3.weight(.semibold))
                Text("Show all to review earlier events").font(.callout).foregroundStyle(.secondary)
                Button("Show all events") { showsAllEvents = true }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.pink)
                    .padding(.top, 4)
            }
            .padding(.top, 12)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(visibleEvents) { event in eventCard(event) }
                    if !showsAllEvents && events.count > visibleEvents.count {
                        let remainingCount = events.count - visibleEvents.count
                        Button {
                            showsAllEvents = true
                        } label: {
                            Label(Self.moreEventsTitle(remainingCount: remainingCount), systemImage: "chevron.down")
                        }
                        .buttonStyle(.plain)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 3)
                        .accessibilityLabel("Show \(remainingCount) more events")
                    }
                }
            }
        }
    }

    private func eventCard(_ event: CalendarEvent) -> some View {
        let color = Color(
            red: event.calendarColor.red,
            green: event.calendarColor.green,
            blue: event.calendarColor.blue,
            opacity: event.calendarColor.opacity
        )

        return HStack(spacing: 8) {
            Capsule().fill(color).frame(width: 3).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title).font(.callout.weight(.bold)).lineLimit(1)
                Text(eventTime(event))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(color)
            }
            Spacer(minLength: 0)
            if let meetingURL = event.meetingURL {
                Button { openURL(meetingURL) } label: { Image(systemName: "video.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(color)
                    .accessibilityLabel("Join \(event.title)")
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 9))
        .accessibilityElement(children: .combine)
    }

    private func eventTime(_ event: CalendarEvent) -> String {
        guard !event.isAllDay else { return "All-day" }
        return "\(event.startsAt.formatted(date: .omitted, time: .shortened))–\(event.endsAt.formatted(date: .omitted, time: .shortened))"
    }

    static func moreEventsTitle(remainingCount: Int) -> String {
        "Show \(remainingCount) more events"
    }

    private func placeholder<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Calendar").font(.headline)
            Divider()
            content()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func emptyState(_ title: String, image: String) -> some View {
        Label(title, systemImage: image)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MonthGrid: View {
    let selectedDate: Date
    let onSelect: (Date) -> Void

    private let calendar = Calendar.autoupdatingCurrent

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(selectedDate, format: .dateTime.month(.wide))
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .textCase(.uppercase)
                .foregroundStyle(.pink)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 0) {
                ForEach(weekdaySymbols.indices, id: \.self) { index in
                    Text(weekdaySymbols[index])
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            VStack(spacing: 4) {
                ForEach(monthWeeks.indices, id: \.self) { index in
                    HStack(spacing: 0) {
                        ForEach(monthWeeks[index].indices, id: \.self) { dayIndex in
                            if let day = monthWeeks[index][dayIndex] {
                                dayCell(day)
                            } else {
                                Color.clear
                                    .frame(maxWidth: .infinity, minHeight: 20)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                }
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let isSelected = calendar.isDate(day, inSameDayAs: selectedDate)
        let isToday = calendar.isDateInToday(day)
        return Text(day, format: .dateTime.day())
            .font(.system(size: 11, weight: isSelected ? .bold : .medium, design: .monospaced))
            .monospacedDigit()
            .foregroundStyle(isSelected ? .white : (isToday ? .pink : .white))
            .frame(width: 20, height: 20)
            .background(isSelected ? Color.pink : .clear, in: Circle())
            .frame(maxWidth: .infinity)
            .frame(height: 20)
            .contentShape(Rectangle())
            .onTapGesture { onSelect(day) }
            .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
            .accessibilityAddTraits(.isButton)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityAction { onSelect(day) }
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        let start = calendar.firstWeekday - 1
        return Array(symbols[start...] + symbols[..<start])
    }

    private var monthDates: [Date?] {
        guard let month = calendar.dateInterval(of: .month, for: selectedDate) else { return [] }
        let firstWeekday = calendar.component(.weekday, from: month.start)
        let leadingDays = (firstWeekday - calendar.firstWeekday + 7) % 7
        let dayCount = calendar.range(of: .day, in: .month, for: selectedDate)?.count ?? 0
        return Array(repeating: nil, count: leadingDays)
            + (0..<dayCount).compactMap { calendar.date(byAdding: .day, value: $0, to: month.start) }
    }

    private var monthWeeks: [[Date?]] {
        stride(from: 0, to: monthDates.count, by: 7).map { start in
            let week = Array(monthDates[start..<min(start + 7, monthDates.count)])
            return week + Array(repeating: nil, count: 7 - week.count)
        }
    }

}
