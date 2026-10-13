#if os(watchOS)
import SwiftUI
import PulseStrengthCore

/// Shown after the phone ended a workout: duration, volume, sets and average heart rate, and a Done button.
@MainActor
struct WatchSummaryView: View {
    let summary: WatchEndedSummary
    let onDone: () -> Void

    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    private var palette: WatchPalette { WatchPalette(reduced: isLuminanceReduced) }

    private var volumeValue: String {
        WatchFormat.withUnit(summary.volumeText, "kg")
    }

    private var heartRateValue: String {
        WatchFormat.withUnit(summary.averageHeartRateText, "bpm")
    }

    /// "7/19" (the caption already says "Sets").
    private var setsValue: String {
        let suffix = " sets"
        if summary.setsText.hasSuffix(suffix) {
            return String(summary.setsText.dropLast(suffix.count))
        }
        return summary.setsText
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                titleBlock
                durationBlock
                statBlock(title: "Volume", value: volumeValue)
                statBlock(title: "Sets", value: setsValue)
                statBlock(title: "Avg Heart Rate", value: heartRateValue)
                doneButton
            }
            .padding(.horizontal, 10)
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Workout Complete")
                .font(WatchFont.text(14, .semibold))
                .foregroundStyle(palette.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(summary.workoutName)
                .font(WatchFont.text(12.5, .regular))
                .foregroundStyle(palette.secondary)
                .lineLimit(2)
        }
        .accessibilityElement(children: .combine)
    }

    private var durationBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(summary.durationText)
                .font(WatchFont.number(40, .bold))
                .tracking(-0.8)
                .foregroundStyle(palette.time)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text("Duration")
                .font(WatchFont.text(12.5, .regular))
                .foregroundStyle(palette.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func statBlock(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(WatchFont.number(20, .semibold))
                .foregroundStyle(palette.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(title)
                .font(WatchFont.text(12.5, .regular))
                .foregroundStyle(palette.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var doneButton: some View {
        Button(action: { onDone() }) {
            Text("Done")
                .font(WatchFont.text(15.5, .semibold))
                .foregroundStyle(isLuminanceReduced ? palette.accent : palette.onAccent)
        }
        .buttonStyle(
            WatchCapsuleButtonStyle(
                fill: isLuminanceReduced ? Color.clear : WatchTheme.green,
                outline: isLuminanceReduced ? palette.accent : Color.clear,
                outlineWidth: isLuminanceReduced ? 1.5 : 0,
                height: 43
            )
        )
        .padding(.top, 4)
    }
}
#endif
