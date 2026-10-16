// NextUpWatchWidget.swift
//
// WA-01 next up (rectangular), WA-03 Smart Stack: Next up, WA-07 corner gauge with today's split and the inline split reminder of WA-10.
//   * Rectangular: the dark green card of Watch.dc.html. In the Smart Stack it floats up around the usual training hour (see
//     WatchTimelinePlan); on a face it is a complication, where a tap opens the Watch app, which is what the Start button does as well.
//   * Corner: the split in capitals ("PUSH") with a gauge along the bezel that fills as the days since that split was last trained go by.
//   * Inline: "Push day · last 5 days ago", shortened to what fits.
// The Start button runs `WatchStartNextIntent`, which opens the Watch app: starting a workout is the iPhone's job, the Watch only mirrors it.
// Compiled into the watchOS widget extension.

#if os(watchOS)
import SwiftUI
import WidgetKit
import PulseStrengthCore

struct NextUpWatchWidget: Widget {
    static let kind = WatchWidgetTopic.nextUp.kind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: WatchProvider(topic: .nextUp)) { entry in
            NextUpWatchView(entry: entry)
        }
        .configurationDisplayName("Next up")
        .description("The workout to do next, with a Start button.")
        .supportedFamilies([.accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}

struct NextUpWatchView: View {
    let entry: WatchEntry
    @Environment(\.widgetFamily) private var environmentFamily
    /// Set by the snapshot tests: `widgetFamily` is read-only in the environment, so a renderer cannot choose the layout through it.
    var familyOverride: WidgetFamily?
    private var family: WidgetFamily { familyOverride ?? environmentFamily }

    private var next: NextUpSummary? { entry.snapshot.nextUp }

    var body: some View {
        content
            .widgetURL(StrengthDeepLink.startNext.url)
            .widgetBackground(family == .accessoryRectangular ? WatchStyle.greenCard : Color.clear)
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryInline: inline
        case .accessoryCorner: corner
        default: rectangular
        }
    }

    // MARK: Rectangular

    @ViewBuilder
    private var rectangular: some View {
        if let next {
            HStack(spacing: 6) {
                WatchRectMessage(
                    eyebrow: "NEXT UP",
                    title: next.name,
                    detail: WatchText.nextUpMeta(exerciseCount: next.exerciseCount, minutes: next.estimatedMinutes)
                )
                WatchIntentButton(intent: WatchStartNextIntent()) {
                    WatchRoundButtonLabel(systemImage: "play.fill", title: nil, fill: WidgetTheme.green, foreground: WidgetTheme.onGreen)
                }
                .widgetAccentable()
                .accessibilityLabel("Start \(next.name)")
            }
        } else {
            WatchRectMessage(eyebrow: "NEXT UP", title: "No workout yet", detail: "Add a template on your iPhone")
        }
    }

    // MARK: Corner

    private var corner: some View {
        Text(next.map { WatchText.cornerSplit($0.splitLabel) } ?? "–")
            .font(WidgetTheme.number(15, .bold))
            .foregroundStyle(WidgetTheme.green)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .widgetAccentable()
            .widgetLabel {
                Gauge(value: WatchGauge.splitRecovery(daysSince: next?.daysSince), in: 0...1) {
                    Text("Days since")
                }
                .tint(WidgetTheme.progress)
                .widgetAccentable()
            }
            .accessibilityLabel(cornerSpoken)
    }

    private var cornerSpoken: String {
        guard let next else { return "No workout planned" }
        return "\(next.splitLabel), \(WatchText.lastTrained(days: next.daysSince))"
    }

    // MARK: Inline

    @ViewBuilder
    private var inline: some View {
        if let next {
            let wording = WatchText.splitReminder(label: next.splitLabel, days: next.daysSince)
            WatchInlineText(long: wording[0], medium: wording[1], short: wording[2], systemImage: "dumbbell.fill")
        } else {
            WatchInlineText(long: "No workout planned", medium: "No workout", short: "Pulse", systemImage: "dumbbell.fill")
        }
    }
}
#endif
