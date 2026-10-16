// WeeklyGoalAccessoryWidget.swift
//
// LS-01 Weekly goal gauge (accessoryCircular) and LS-09 inline weekly goal (accessoryInline). The data is `snapshot.week`, the same as the
// Home Screen's WeeklyGoalWidget, drawn the way the Lock Screen wants it: one colour, the system's own plate, the gauge as the accented
// element. A tap opens the Strength hub.

#if os(iOS)
import SwiftUI
import WidgetKit
import PulseStrengthCore

struct WeeklyGoalAccessoryWidget: Widget {
    static let kind = "health.pulse.strength.widget.weeklyGoalAccessory"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: SnapshotProvider()) { entry in
            WeeklyGoalAccessoryView(entry: entry)
        }
        .configurationDisplayName("Weekly goal")
        .description("Workouts finished this week against your goal, as a gauge or as a line above the clock.")
        .supportedFamilies([.accessoryCircular, .accessoryInline])
    }
}

struct WeeklyGoalAccessoryView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    private var week: WeekSummary { entry.snapshot.week }

    /// The ring is full at the goal; a week beyond it keeps the ring full while the centre still shows the real count ("5/4").
    private var gaugeLimit: Double { Double(max(week.goal, 1)) }
    private var gaugeValue: Double { min(Double(max(week.completed, 0)), gaugeLimit) }

    var body: some View {
        content
            .lockContainerBackground()
            .widgetURL(StrengthDeepLink.hub.url)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(LockAccessoryText.weekSentence(week))
    }

    @ViewBuilder
    private var content: some View {
        if family == .accessoryInline {
            Label(LockAccessoryText.weekLine(week), systemImage: "dumbbell.fill")
        } else {
            ZStack {
                AccessoryWidgetBackground()
                gauge
            }
        }
    }

    /// With no workout this week the ring is empty and the centre reads "0/4".
    private var gauge: some View {
        Gauge(value: gaugeValue, in: 0...gaugeLimit) {
            Text("Workouts")
        } currentValueLabel: {
            Text(LockAccessoryText.goalFraction(week))
                .font(WidgetTheme.number(17))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .widgetAccentable()
    }
}
#endif
