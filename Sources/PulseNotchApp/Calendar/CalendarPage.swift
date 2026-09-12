import PulseNotchCore
import SwiftUI

struct CalendarPage: View {
    @ObservedObject var model: CalendarFeatureModel
    let date: Date

    @State private var selectedDate = Date()
    @State private var showsAllEvents = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        Group {
            switch model.state {
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
    }

    private func calendarContent(_ schedule: CalendarEventSchedule) -> some View {
        let events = schedule.events(on: selectedDate)
        let initialEvents = Array(schedule.currentAndUpcoming(on: selectedDate, relativeTo: date).prefix(2))
        let visibleEvents = showsAllEvents ? events : initialEvents

        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedDate, format: .dateTime.month(.abbreviated))
                        .font(.title2.weight(.semibold))
                    Text(selectedDate, format: .dateTime.year())
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 64, alignment: .leading)

                HStack(spacing: 4) {
                    ForEach(weekDates, id: \.self) { day in
                        let isSelected = Calendar.autoupdatingCurrent.isDate(day, inSameDayAs: selectedDate)
                        Button {
                            selectedDate = day
                            showsAllEvents = false
                        } label: {
                            VStack(spacing: 5) {
                                Text(day, format: .dateTime.weekday(.narrow))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(day, format: .dateTime.day())
                                    .font(.callout.weight(isSelected ? .bold : .regular))
                                    .frame(width: 32, height: 32)
                                    .background(isSelected ? Color.accentColor : .clear, in: Circle())
                            }
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.trailing, 34)
            }

            if events.isEmpty {
                emptyState("No events on this day", image: "calendar.badge.checkmark")
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(visibleEvents) { event in eventRow(event) }
                        if !showsAllEvents && events.count > visibleEvents.count {
                            let remainingCount = events.count - visibleEvents.count
                            Button {
                                showsAllEvents = true
                            } label: {
                                HStack(spacing: 4) {
                                    Text(Self.moreEventsTitle(remainingCount: remainingCount))
                                    Image(systemName: "chevron.down")
                                }
                            }
                            .buttonStyle(.plain)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                            .accessibilityLabel("Show \(remainingCount) more events")
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func eventRow(_ event: CalendarEvent) -> some View {
        let color = Color(
            red: event.calendarColor.red,
            green: event.calendarColor.green,
            blue: event.calendarColor.blue,
            opacity: event.calendarColor.opacity
        )

        return HStack(spacing: 10) {
            Capsule().fill(color).frame(width: 3, height: 36).accessibilityHidden(true)
            Text(event.isAllDay ? "All-day" : event.startsAt.formatted(date: .omitted, time: .shortened))
                .font(.caption)
                .foregroundStyle(event.startsSoon(relativeTo: date) ? Color.orange : Color.white.opacity(0.55))
                .frame(width: 44, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(event.title).font(.callout.weight(.semibold)).lineLimit(1)
                HStack(spacing: 8) {
                    Text(event.calendarName).foregroundStyle(color)
                    if let location = event.location {
                        Label(location, systemImage: "mappin").foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .font(.caption2.weight(.medium))
                if let notes = event.notes {
                    Text(notes).font(.caption2).foregroundStyle(Color.white.opacity(0.4)).lineLimit(1)
                }
            }
            Spacer(minLength: 12)
            if let meetingURL = event.meetingURL {
                Button { openURL(meetingURL) } label: {
                    Image(systemName: "video.fill")
                        .frame(width: 26, height: 26)
                        .foregroundStyle(color)
                        .background(color.opacity(0.16), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Join \(event.title)")
            }
        }
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var weekDates: [Date] {
        let calendar = Calendar.autoupdatingCurrent
        guard let week = calendar.dateInterval(of: .weekOfYear, for: selectedDate) else { return [selectedDate] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: week.start) }
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
