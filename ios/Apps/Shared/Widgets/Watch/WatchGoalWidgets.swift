// WatchGoalWidgets.swift
//
// The small face complications of WA-01 and WA-07: the weekly goal (circular ring, corner gauge, inline text), the days since the last
// workout (circular, inline) and the Start button of the face set (circular). They read `WidgetSnapshot.week` and `nextUp` only.
// Compiled into the watchOS widget extension.

#if os(watchOS)
import SwiftUI
import WidgetKit
import PulseStrengthCore

// MARK: - Weekly goal

struct WeeklyGoalWatchWidget: Widget {
    static let kind = WatchWidgetTopic.goal.kind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: WatchProvider(topic: .goal)) { entry in
            WeeklyGoalWatchView(entry: entry)
        }
        .configurationDisplayName("Weekly goal")
        .description("Workouts finished this week against your goal.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryInline])
    }
}

struct WeeklyGoalWatchView: View {
    let entry: WatchEntry
    @Environment(\.widgetFamily) private var environmentFamily
    /// Set by the snapshot tests: `widgetFamily` is read-only in the environment, so a renderer cannot choose the layout through it.
    var familyOverride: WidgetFamily?
    private var family: WidgetFamily { familyOverride ?? environmentFamily }

    private var week: WeekSummary { entry.snapshot.week }
    private var goal: Int { max(1, week.goal) }
    private var progress: Double { WatchGauge.fraction(week.completed, of: goal) }
    private var spoken: String { "\(week.completed) of \(goal) workouts this week" }

    var body: some View {
        content
            .widgetURL(StrengthDeepLink.hub.url)
            .widgetBackground(Color.clear)
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryCorner: corner
        case .accessoryInline: inline
        default: circular
        }
    }

    /// The ring of the face set: the count in its middle ("3/4").
    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            RingGauge(progress: progress, lineWidth: 4.5, color: WidgetTheme.progress, track: WidgetTheme.track)
                .widgetAccentable()
                .padding(2)
            Text("\(week.completed)/\(goal)")
                .font(WidgetTheme.number(13))
                .foregroundStyle(WidgetTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    /// The count in the corner with a gauge along the bezel (WA-07).
    private var corner: some View {
        Text("\(week.completed)/\(goal)")
            .font(WidgetTheme.number(15, .bold))
            .foregroundStyle(WidgetTheme.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .widgetLabel {
                Gauge(value: Double(min(week.completed, goal)), in: 0...Double(goal)) {
                    Text("Goal")
                }
                .tint(WidgetTheme.progress)
                .widgetAccentable()
            }
            .accessibilityLabel(spoken)
    }

    private var inline: some View {
        WatchInlineText(
            long: "\(week.completed) of \(goal) workouts this week",
            medium: "\(week.completed)/\(goal) workouts this week",
            short: "\(week.completed)/\(goal) workouts",
            systemImage: "dumbbell.fill"
        )
    }
}

// MARK: - Days since

struct DaysSinceWatchWidget: Widget {
    static let kind = WatchWidgetTopic.daysSince.kind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: WatchProvider(topic: .daysSince)) { entry in
            DaysSinceWatchView(entry: entry)
        }
        .configurationDisplayName("Days since training")
        .description("How many days ago you last finished a workout.")
        .supportedFamilies([.accessoryCircular, .accessoryInline])
    }
}

struct DaysSinceWatchView: View {
    let entry: WatchEntry
    @Environment(\.widgetFamily) private var environmentFamily
    /// Set by the snapshot tests: `widgetFamily` is read-only in the environment, so a renderer cannot choose the layout through it.
    var familyOverride: WidgetFamily?
    private var family: WidgetFamily { familyOverride ?? environmentFamily }

    private var days: Int? { entry.snapshot.week.daysSinceLastWorkout }

    var body: some View {
        content
            .widgetURL(StrengthDeepLink.hub.url)
            .widgetBackground(Color.clear)
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryInline: inline
        default: circular
        }
    }

    /// "3d" over "ago" ("0d" over "today"; "–" for a person who has not trained yet).
    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Text(WatchText.daysShort(days))
                    .font(WidgetTheme.number(17))
                    .foregroundStyle(WidgetTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .widgetAccentable()
                Text(caption)
                    .font(WidgetTheme.text(9, .semibold))
                    .foregroundStyle(WidgetTheme.inkSecondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private var caption: String {
        guard let days else { return "none" }
        return days <= 0 ? "today" : "ago"
    }

    private var spoken: String {
        guard let days else { return "No workouts yet" }
        switch days {
        case ...0: return "You trained today"
        case 1: return "1 day since your last workout"
        default: return "\(days) days since your last workout"
        }
    }

    private var inline: some View {
        WatchInlineText(
            long: WatchText.lastWorkout(days: days),
            medium: days.map { "Workout " + WatchText.lastTrainedShort(days: $0) } ?? "No workouts",
            short: WatchText.daysShort(days),
            systemImage: "dumbbell.fill"
        )
    }
}

// MARK: - Start

struct StartWatchWidget: Widget {
    static let kind = WatchWidgetTopic.start.kind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: WatchProvider(topic: .start)) { entry in
            StartWatchView(entry: entry)
        }
        .configurationDisplayName("Start")
        .description("Opens Pulse Strength for the next workout.")
        .supportedFamilies([.accessoryCircular])
    }
}

struct StartWatchView: View {
    let entry: WatchEntry

    private var spoken: String {
        guard let next = entry.snapshot.nextUp else { return "Open Pulse Strength" }
        return "Start \(next.name)"
    }

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            Image(systemName: "play.fill")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(WidgetTheme.green)
                .widgetAccentable()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .widgetURL(StrengthDeepLink.startNext.url)
        .widgetBackground(Color.clear)
    }
}
#endif
