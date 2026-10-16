// FormCueWidget.swift
//
// WI-04 Form cue (systemSmall). One coaching cue of today's first lift (`formCue`); the builder rotates the cue by day of the year. A tap
// opens that exercise. Without a cue (no workout planned, or none of its exercises has cues) the widget says how to get one.

#if os(iOS)
import SwiftUI
import WidgetKit
import PulseStrengthCore

struct FormCueWidget: Widget {
    static let kind = "health.pulse.strength.widget.formCue"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: SnapshotProvider()) { entry in
            FormCueView(entry: entry)
        }
        .configurationDisplayName("Form cue")
        .description("One coaching cue for the first lift of your next workout.")
        .supportedFamilies([.systemSmall])
    }
}

struct FormCueView: View {
    let entry: SnapshotEntry

    private var formCue: FormCue? { entry.snapshot.formCue }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .widgetCardBackground()
            .widgetURL(formCue.map { StrengthDeepLink.exercise(id: $0.exerciseID).url } ?? StrengthDeepLink.hub.url)
    }

    @ViewBuilder
    private var content: some View {
        if let cue = formCue {
            populated(cue)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ExtrasEyebrow(title: "Form cue", color: WidgetTheme.blueText)
                ExtrasEmptyState(
                    systemImage: "lightbulb.fill",
                    title: "No cue yet",
                    message: "Save a workout in Pulse Strength and its first lift shows a cue here."
                )
            }
        }
    }

    private func populated(_ cue: FormCue) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                ExtrasEyebrow(title: "Form cue", color: WidgetTheme.blueText)
                Text(cue.exerciseName)
                    .font(WidgetTheme.text(12, .semibold))
                    .foregroundStyle(WidgetTheme.inkSecondary)
                    .lineLimit(1)
            }
            Text(cue.cue)
                .font(WidgetTheme.text(17, .bold))
                .foregroundStyle(WidgetTheme.ink)
                .lineLimit(4)
                .minimumScaleFactor(0.6)
                .frame(maxHeight: .infinity, alignment: .topLeading)
            Text(position(of: cue))
                .font(WidgetTheme.text(12))
                .foregroundStyle(WidgetTheme.inkSecondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Form cue for \(cue.exerciseName): \(cue.cue) \(position(of: cue)).")
    }

    /// "1 of 4 cues".
    private func position(of cue: FormCue) -> String {
        "\(cue.index) of \(cue.count) " + (cue.count == 1 ? "cue" : "cues")
    }
}
#endif
