import PulseNotchCore
import SwiftUI

struct NotchPreview: View {
    @ObservedObject var calendarModel: CalendarFeatureModel

    @State private var isExpanded = false
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
        .frame(width: 560, height: 260)
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
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                statusIndicator(at: date)

                if isExpanded {
                    Text("Next event")
                        .font(.headline)

                    Spacer(minLength: 20)

                    Image(systemName: "calendar")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }

            if isExpanded {
                Divider()

                expandedCalendarContent(at: date)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(
            width: isExpanded ? 420 : 190,
            height: isExpanded ? 138 : 42,
            alignment: .top
        )
        .background(.black, in: RoundedRectangle(cornerRadius: 18))
        .animation(
            reduceMotion ? nil : .snappy(duration: 0.25),
            value: isExpanded
        )
        .onHover { isExpanded = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Pulse Notch")
    }

    @ViewBuilder
    private func statusIndicator(at date: Date) -> some View {
        if case let .event(event) = calendarModel.state,
           event.startsSoon(relativeTo: date) {
            Image(systemName: "circle.fill")
                .foregroundStyle(.orange)
                .symbolEffect(
                    .pulse,
                    options: reduceMotion ? .nonRepeating : .repeating
                )
                .accessibilityLabel("Event starting within five minutes")
        } else {
            Image(systemName: "circle.fill")
                .foregroundStyle(.green)
                .accessibilityLabel("No event starting soon")
        }
    }

    @ViewBuilder
    private func expandedCalendarContent(at date: Date) -> some View {
        switch calendarModel.state {
        case .loading:
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("Loading next calendar event")
        case let .event(event):
            eventContent(event, at: date)
        case .noUpcomingEvent:
            emptyState(
                title: "No upcoming events",
                systemImage: "calendar.badge.checkmark"
            )
        case .accessDenied:
            emptyState(
                title: "Calendar access is off",
                systemImage: "calendar.badge.exclamationmark"
            )
        case .unavailable:
            emptyState(
                title: "Calendar is unavailable",
                systemImage: "exclamationmark.triangle"
            )
        }
    }

    private func eventContent(
        _ event: CalendarEvent,
        at date: Date
    ) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)

                Text(event.startsAt, format: .dateTime.weekday(.abbreviated)
                    .hour()
                    .minute())
                    .font(.caption)
                    .foregroundStyle(
                        event.startsSoon(relativeTo: date)
                            ? Color.orange
                            : Color.secondary
                    )
            }

            Spacer(minLength: 12)

            if let meetingURL = event.meetingURL {
                Button {
                    openURL(meetingURL)
                } label: {
                    Label("Join", systemImage: "video.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .accessibilityHint("Opens the meeting in your default browser")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
