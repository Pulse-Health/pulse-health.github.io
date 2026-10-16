// WeeklySetsAccessoryWidget.swift
//
// LS-06 Volume progress (accessoryRectangular): "Sets this week" with the count, a meter of the weekly target and "11 to go · legs lagging",
// from `snapshot.weeklySets`. Before the first set of the week the meter is empty and the last line says so. A tap opens the Strength hub.

#if os(iOS)
import SwiftUI
import WidgetKit
import PulseStrengthCore

struct WeeklySetsAccessoryWidget: Widget {
    static let kind = "health.pulse.strength.widget.weeklySetsAccessory"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: SnapshotProvider()) { entry in
            WeeklySetsAccessoryView(entry: entry)
        }
        .configurationDisplayName("Volume progress")
        .description("Sets finished this week against the weekly target, and the muscle group that is lagging.")
        .supportedFamilies([.accessoryRectangular])
    }
}

struct WeeklySetsAccessoryView: View {
    let entry: SnapshotEntry

    private var sets: WeeklySetsSummary { entry.snapshot.weeklySets }

    var body: some View {
        LockAccessoryCard {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("Sets this week")
                        .font(WidgetTheme.text(13, .bold))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(String(sets.totalSets))
                        .font(WidgetTheme.number(13))
                }
                BarMeter(fraction: LockAccessoryText.setsFraction(sets), color: .primary, track: Color.primary.opacity(0.3), height: 8)
                    .widgetAccentable()
                Text(LockAccessoryText.setsDetail(sets))
                    .font(WidgetTheme.text(12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .lockContainerBackground()
        .widgetURL(StrengthDeepLink.hub.url)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(LockAccessoryText.setsSentence(sets))
    }
}
#endif
