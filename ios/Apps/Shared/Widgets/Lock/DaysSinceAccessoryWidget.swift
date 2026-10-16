// DaysSinceAccessoryWidget.swift
//
// LS-02 Days since training (accessoryCircular): "3d" over "SINCE", from `snapshot.week.daysSinceLastWorkout`. Without any workout the
// circle shows the dumbbell and "NONE YET" instead of a bare dash. A tap opens the Strength hub.

#if os(iOS)
import SwiftUI
import WidgetKit
import PulseStrengthCore

struct DaysSinceAccessoryWidget: Widget {
    static let kind = "health.pulse.strength.widget.daysSinceAccessory"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: SnapshotProvider()) { entry in
            DaysSinceAccessoryView(entry: entry)
        }
        .configurationDisplayName("Days since training")
        .description("How many days have passed since your last workout.")
        .supportedFamilies([.accessoryCircular])
    }
}

struct DaysSinceAccessoryView: View {
    let entry: SnapshotEntry

    private var days: Int? { entry.snapshot.week.daysSinceLastWorkout }

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            if let days {
                figure(days)
            } else {
                noWorkouts
            }
        }
        .lockContainerBackground()
        .widgetURL(StrengthDeepLink.hub.url)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(LockText.daysSinceSentence(days))
    }

    /// The count scales down for three digits ("120d") instead of touching the edge of the circle.
    private func figure(_ days: Int) -> some View {
        VStack(spacing: 0) {
            Text(WidgetText.daysShort(days))
                .font(WidgetTheme.number(26))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .widgetAccentable()
            Text("SINCE")
                .font(WidgetTheme.text(10, .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
    }

    private var noWorkouts: some View {
        VStack(spacing: 2) {
            Image(systemName: "dumbbell.fill")
                .font(.system(size: 22))
                .widgetAccentable()
            Text("NONE YET")
                .font(WidgetTheme.text(9, .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 8)
    }
}
#endif
