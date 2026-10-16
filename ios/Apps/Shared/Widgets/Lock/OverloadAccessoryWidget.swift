// OverloadAccessoryWidget.swift
//
// LS-08 Overload target (accessoryRectangular): "TODAY'S TARGET", "Bench Press 4 × 6" and "82.5 kg · +2.5 vs last", from
// `snapshot.overload` (what to lift today to beat last time). When the weight stays the same the progress is in reps ("+1 rep vs last").
// A tap opens that exercise's detail; with no target it opens the Strength hub.

#if os(iOS)
import SwiftUI
import WidgetKit
import PulseStrengthCore

struct OverloadAccessoryWidget: Widget {
    static let kind = "health.pulse.strength.widget.overloadAccessory"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: SnapshotProvider()) { entry in
            OverloadAccessoryView(entry: entry)
        }
        .configurationDisplayName("Overload target")
        .description("What to lift today to beat your last session.")
        .supportedFamilies([.accessoryRectangular])
    }
}

struct OverloadAccessoryView: View {
    let entry: SnapshotEntry

    private var target: OverloadTarget? { entry.snapshot.overload }

    private var link: StrengthDeepLink {
        guard let target else { return .hub }
        return .exercise(id: target.exerciseID)
    }

    private var sentence: String {
        guard let target else { return "No target yet. Log a workout to see it." }
        return LockAccessoryText.overloadSentence(target)
    }

    var body: some View {
        LockAccessoryCard { lines }
            .lockContainerBackground()
            .widgetURL(link.url)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(sentence)
    }

    @ViewBuilder
    private var lines: some View {
        if let target {
            LockAccessoryLines(eyebrow: "TODAY'S TARGET", detail: LockAccessoryText.overloadDetail(target), detailFont: WidgetTheme.number(13, .regular)) {
                LockAccessoryHeadline(name: target.exerciseName, figure: LockAccessoryText.overloadFigure(target))
                    .widgetAccentable()
            }
        } else {
            LockAccessoryLines(eyebrow: "TODAY'S TARGET", detail: "Log a workout to see it", detailFont: WidgetTheme.text(12)) {
                LockAccessoryTitle(text: "No target yet")
            }
        }
    }
}
#endif
