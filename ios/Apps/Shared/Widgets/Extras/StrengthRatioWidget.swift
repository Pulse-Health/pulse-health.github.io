// StrengthRatioWidget.swift
//
// WI-07 Strength ratio (systemSmall). The estimated 1RM of the first main lift (bench, squat, deadlift, overhead press) divided by
// bodyweight, big, with a bar toward the goal ratio of that lift. Bodyweight comes from Health; without it the widget asks for it and
// still shows the estimated 1RM. A tap opens the lift.

#if os(iOS)
import SwiftUI
import WidgetKit
import PulseStrengthCore

struct StrengthRatioWidget: Widget {
    static let kind = "health.pulse.strength.widget.strengthRatio"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: SnapshotProvider()) { entry in
            StrengthRatioView(entry: entry)
        }
        .configurationDisplayName("Strength ratio")
        .description("Your estimated one-rep max against bodyweight for a main lift, with a bar toward the goal.")
        .supportedFamilies([.systemSmall])
    }
}

struct StrengthRatioView: View {
    let entry: SnapshotEntry

    private var lift: StrengthRatio? { entry.snapshot.strengthRatio }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .widgetCardBackground()
            .widgetURL(lift.map { StrengthDeepLink.exercise(id: $0.exerciseID).url } ?? StrengthDeepLink.hub.url)
    }

    @ViewBuilder
    private var content: some View {
        if let lift {
            if let bodyweight = lift.bodyweightKg, bodyweight > 0, let value = ratio(of: lift, bodyweight: bodyweight) {
                populated(lift, bodyweight: bodyweight, value: value)
            } else {
                needsBodyweight(lift)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ExtrasEyebrow(title: "Strength ratio")
                ExtrasEmptyState(
                    systemImage: "scalemass.fill",
                    title: "No main lift yet",
                    message: "Log bench, squat, deadlift or overhead press to see it against your bodyweight."
                )
            }
        }
    }

    /// The ratio the builder computed, or the same division when the field is missing.
    private func ratio(of lift: StrengthRatio, bodyweight: Double) -> Double? {
        if let ratio = lift.ratio { return ratio }
        return lift.estimated1RM > 0 ? lift.estimated1RM / bodyweight : nil
    }

    private func ratioText(_ value: Double) -> String {
        NumberText.kg(value) + "\u{00D7}"
    }

    private func populated(_ lift: StrengthRatio, bodyweight: Double, value: Double) -> some View {
        let fraction = lift.goalRatio > 0 ? min(1, max(0, value / lift.goalRatio)) : 0
        let reached = lift.goalRatio > 0 && value >= lift.goalRatio
        let goalLine = "Goal \(ratioText(lift.goalRatio))" + (reached ? " reached" : "") + " \u{00B7} " + WidgetText.kg(bodyweight)
        return VStack(alignment: .leading, spacing: 0) {
            ExtrasEyebrow(title: lift.exerciseName + " / bodyweight", lines: 2)
            Spacer(minLength: 4)
            Text(ratioText(value))
                .font(WidgetTheme.number(36))
                .foregroundStyle(WidgetTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Spacer(minLength: 6)
            VStack(alignment: .leading, spacing: 4) {
                BarMeter(fraction: fraction, color: WidgetTheme.green, height: 8)
                    .widgetAccentable()
                Text(goalLine)
                    .font(WidgetTheme.text(12))
                    .foregroundStyle(WidgetTheme.inkSecondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(lift, bodyweight: bodyweight, value: value, reached: reached))
    }

    private func spoken(_ lift: StrengthRatio, bodyweight: Double, value: Double, reached: Bool) -> String {
        var text = "\(lift.exerciseName) estimated one-rep max is \(NumberText.kg(value)) times your bodyweight of "
        text += "\(NumberText.kg(bodyweight)) kilograms. The goal is \(NumberText.kg(lift.goalRatio)) times"
        text += reached ? ", and you have reached it." : "."
        return text
    }

    private func needsBodyweight(_ lift: StrengthRatio) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ExtrasEyebrow(title: lift.exerciseName + " / bodyweight", lines: 2)
            Spacer(minLength: 6)
            Text("Add your bodyweight in Health")
                .font(WidgetTheme.text(15, .semibold))
                .foregroundStyle(WidgetTheme.ink)
                .lineLimit(3)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            Text("Estimated 1RM " + WidgetText.kg(lift.estimated1RM))
                .font(WidgetTheme.text(12))
                .foregroundStyle(WidgetTheme.inkSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(lift.exerciseName) against bodyweight. Add your bodyweight in Health to see the ratio. Estimated one-rep max \(NumberText.kg(lift.estimated1RM)) kilograms."
        )
    }
}
#endif
