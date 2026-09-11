import PulseNotchCore
import SwiftUI

struct NotchPreview: View {
    private let calendarReminderLeadTime: TimeInterval = 10 * 60

    @ObservedObject var calendarModel: CalendarFeatureModel

    @State private var isExpanded = false
    @State private var selectedDate = Date()
    @State private var showsAllEvents = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 24) {
            TimelineView(.periodic(from: .now, by: 15)) { context in
                notch(at: context.date)
            }

            Text("Hover over the notch to preview its expanded state.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(32)
        .frame(width: 620, height: 360)
        .background(.regularMaterial)
        .task {
            while !Task.isCancelled {
                await calendarModel.refresh()

                do {
                    try await Task.sleep(for: .seconds(30))
                } catch {
                    return
                }
            }
        }
    }

    private func notch(at date: Date) -> some View {
        Group {
            if isExpanded {
                expandedCalendarContent(at: date)
            } else {
                collapsedIndicators(at: date)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(
            width: isExpanded ? 500 : 190,
            height: isExpanded ? 250 : 42,
            alignment: .top
        )
        .background(.black, in: RoundedRectangle(cornerRadius: 18))
        .animation(
            reduceMotion ? nil : .snappy(duration: 0.25),
            value: isExpanded
        )
        .onHover {
            isExpanded = $0
            if !$0 {
                showsAllEvents = false
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Pulse Notch")
    }

    private func collapsedIndicators(at date: Date) -> some View {
        HStack(spacing: 8) {
            if case let .loaded(schedule) = calendarModel.state,
               let event = schedule.next(after: date),
               event.startsSoon(
                   relativeTo: date,
                   threshold: calendarReminderLeadTime
               ) {
                Image(systemName: "calendar")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.orange)
                    .accessibilityLabel(
                        "Calendar event starting within ten minutes"
                    )
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func expandedCalendarContent(at date: Date) -> some View {
        switch calendarModel.state {
        case .loading:
            placeholder {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Loading next calendar event")
            }
        case let .loaded(schedule):
            calendarContent(schedule, at: date)
        case .accessDenied:
            placeholder {
                emptyState(
                    title: "Calendar access is off",
                    systemImage: "calendar.badge.exclamationmark"
                )
            }
        case .unavailable:
            placeholder {
                emptyState(
                    title: "Calendar is unavailable",
                    systemImage: "exclamationmark.triangle"
                )
            }
        }
    }

    private func calendarContent(
        _ schedule: CalendarEventSchedule,
        at date: Date
    ) -> some View {
        let events = schedule.events(on: selectedDate)
        let initialEvents = Array(
            schedule.currentAndUpcoming(
                on: selectedDate,
                relativeTo: date
            ).prefix(2)
        )
        let hiddenEventCount = events.count - initialEvents.count

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
                    ForEach(weekDates(containing: selectedDate), id: \.self) { day in
                        let isSelected = Calendar.autoupdatingCurrent.isDate(
                            day,
                            inSameDayAs: selectedDate
                        )

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
                                    .background(
                                        isSelected ? Color.accentColor : .clear,
                                        in: Circle()
                                    )
                            }
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
                .frame(maxWidth: .infinity)
            }

            if events.isEmpty {
                emptyState(
                    title: "No events on this day",
                    systemImage: "calendar.badge.checkmark"
                )
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    let visibleEvents = showsAllEvents ? events : initialEvents

                    if visibleEvents.isEmpty {
                        emptyState(
                            title: "No more events today",
                            systemImage: "calendar.badge.checkmark"
                        )
                    } else if showsAllEvents {
                        ScrollView(.vertical, showsIndicators: false) {
                            eventRows(visibleEvents, at: date)
                        }
                    } else {
                        eventRows(visibleEvents, at: date)
                    }

                    if hiddenEventCount > 0 {
                        Button {
                            withAnimation(
                                reduceMotion ? nil : .snappy(duration: 0.2)
                            ) {
                                showsAllEvents.toggle()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(
                                    showsAllEvents
                                        ? "Show upcoming"
                                        : "+\(hiddenEventCount) "
                                            + (hiddenEventCount == 1 ? "event" : "events")
                                )

                                Image(
                                    systemName: showsAllEvents
                                        ? "chevron.up"
                                        : "chevron.down"
                                )
                                .font(.caption2.weight(.semibold))
                            }
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(
                            showsAllEvents
                                ? "Shows only upcoming events"
                                : "Shows all events for this day"
                        )
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func eventRows(
        _ events: [CalendarEvent],
        at date: Date
    ) -> some View {
        LazyVStack(spacing: 0) {
            ForEach(events) { event in
                eventRow(event, at: date)
            }
        }
    }

    private func eventRow(
        _ event: CalendarEvent,
        at date: Date
    ) -> some View {
        let eventColor = Color(
            red: event.calendarColor.red,
            green: event.calendarColor.green,
            blue: event.calendarColor.blue,
            opacity: event.calendarColor.opacity
        )

        return HStack(spacing: 10) {
            Capsule()
                .fill(eventColor)
                .frame(width: 3, height: 36)
                .accessibilityHidden(true)

            Group {
                if event.isAllDay {
                    Text("All-day")
                } else {
                    Text(event.startsAt, format: .dateTime.hour().minute())
                        .monospacedDigit()
                }
            }
            .font(.caption)
            .foregroundStyle(
                event.startsSoon(relativeTo: date)
                    ? Color.orange
                    : Color.white.opacity(0.55)
            )
            .frame(width: 44, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                Text(event.title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(event.calendarName)
                        .foregroundStyle(eventColor)

                    if let location = event.location {
                        Label(location, systemImage: "mappin")
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .font(.caption2.weight(.medium))

                if let notes = event.notes {
                    Text(notes)
                        .font(.caption2)
                        .foregroundStyle(Color.white.opacity(0.4))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 12)

            if !event.isAllDay, event.isInProgress(relativeTo: date) {
                Image(systemName: "waveform")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(eventColor)
                    .symbolEffect(
                        .variableColor.iterative.reversing,
                        options: .repeating,
                        isActive: !reduceMotion
                    )
                    .accessibilityLabel("Event in progress")
            }

            if let meetingURL = event.meetingURL {
                Button {
                    openURL(meetingURL)
                } label: {
                    Image(systemName: "video.fill")
                        .frame(width: 26, height: 26)
                        .foregroundStyle(eventColor)
                        .background(eventColor.opacity(0.16), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Join \(event.title)")
                .accessibilityHint(
                    "Opens the meeting in your default browser"
                )
            }
        }
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func weekDates(containing date: Date) -> [Date] {
        let calendar = Calendar.autoupdatingCurrent
        guard let week = calendar.dateInterval(of: .weekOfYear, for: date) else {
            return [date]
        }

        return (0..<7).compactMap {
            calendar.date(byAdding: .day, value: $0, to: week.start)
        }
    }

    private func placeholder<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Calendar")
                    .font(.headline)

                Spacer()

                Image(systemName: "calendar")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }

            Divider()

            content()
        }
    }

    private func emptyState(
        title: String,
        systemImage: String
    ) -> some View {
        Label(title, systemImage: systemImage)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
