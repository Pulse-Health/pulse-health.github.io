// WatchCountersWidgets.swift
//
// WA-10 the small circulars of the face catalogue and their inline twins: the week streak (a flame and the number of weeks in a row that met
// the goal) and the sets of this week against the weekly target (a ring, the count and "SETS"). The split reminder of WA-10 is the inline
// family of the Next up widget.
// Compiled into the watchOS widget extension.

#if os(watchOS)
import SwiftUI
import WidgetKit
import PulseStrengthCore

// MARK: - Streak

struct StreakWatchWidget: Widget {
    static let kind = WatchWidgetTopic.streak.kind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: WatchProvider(topic: .streak)) { entry in
            StreakWatchView(entry: entry)
        }
        .configurationDisplayName("Week streak")
        .description("Weeks in a row that met your workout goal.")
        .supportedFamilies([.accessoryCircular, .accessoryInline])
    }
}

struct StreakWatchView: View {
    let entry: WatchEntry
    @Environment(\.widgetFamily) private var family

    private var weeks: Int { max(0, entry.snapshot.week.streakWeeks) }

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

    /// The flame over the number of weeks (the flame is grey while there is no streak).
    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(weeks > 0 ? WatchStyle.flame : WidgetTheme.inkSecondary)
                    .widgetAccentable()
                Text("\(weeks)")
                    .font(WidgetTheme.number(15))
                    .foregroundStyle(WidgetTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(weeks == 1 ? "Streak: 1 week in a row" : "Streak: \(weeks) weeks in a row")
    }

    private var inline: some View {
        WatchInlineText(
            long: WatchText.streak(weeks: weeks),
            medium: weeks > 0 ? "Streak \(weeks)w" : "No streak",
            short: "\(weeks)w",
            systemImage: "flame.fill"
        )
    }
}

// MARK: - Weekly sets

struct WeeklySetsWatchWidget: Widget {
    static let kind = WatchWidgetTopic.weeklySets.kind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: WatchProvider(topic: .weeklySets)) { entry in
            WeeklySetsWatchView(entry: entry)
        }
        .configurationDisplayName("Weekly sets")
        .description("Sets of the four big muscle groups this week against the target.")
        .supportedFamilies([.accessoryCircular, .accessoryInline])
    }
}

struct WeeklySetsWatchView: View {
    let entry: WatchEntry
    @Environment(\.widgetFamily) private var family

    private var sets: WeeklySetsSummary { entry.snapshot.weeklySets }

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

    /// A ring of sets against the target with the count and "SETS" in its middle.
    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            RingGauge(
                progress: WatchGauge.fraction(sets.totalSets, of: sets.totalTarget),
                lineWidth: 4,
                color: WidgetTheme.progress,
                track: WidgetTheme.track
            )
            .widgetAccentable()
            .padding(2)
            VStack(spacing: -1) {
                Text("\(sets.totalSets)")
                    .font(WidgetTheme.number(14))
                    .foregroundStyle(WidgetTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("SETS")
                    .font(WidgetTheme.text(8, .semibold))
                    .foregroundStyle(WidgetTheme.inkSecondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(sets.totalSets) of \(sets.totalTarget) sets this week")
    }

    private var inline: some View {
        WatchInlineText(
            long: "\(sets.totalSets) of \(sets.totalTarget) sets this week",
            medium: "\(sets.totalSets)/\(sets.totalTarget) sets",
            short: "\(sets.totalSets) sets",
            systemImage: "dumbbell.fill"
        )
    }
}
#endif
