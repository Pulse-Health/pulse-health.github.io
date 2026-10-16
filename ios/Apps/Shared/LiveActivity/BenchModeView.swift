// BenchModeView.swift
//
// SB-02 Bench mode: the Live Activity when the iPhone stands in StandBy and the activity fills the screen
// (`EnvironmentValues.isActivityFullscreen`, iOS 17.2; WorkoutLockScreenContainer reads it). The layout is the large one of
// StandBy.dc.html, readable from two metres away: a 220 pt ring around a 64 pt countdown, "Next: set 4" over "80 kg × 6" in 28 pt, and
// the +15 s and Skip buttons; while logging, the weight and reps in 72 pt with a large Log set button.
//
// Everything is drawn on pure black. The ring is the system's circular timer (`ProgressView(timerInterval:)`, see ActivityRestRing),
// which draws its own stroke, so its thickness may differ from the 16 pt of the mock-up. Nothing here has run on a device.

#if os(iOS)
import AppIntents
import SwiftUI
import PulseStrengthCore

struct BenchModeView: View {
    let state: WorkoutSnapshot
    let phase: SnapshotPhase

    var body: some View {
        content
            .padding(.horizontal, 40)
            .padding(.vertical, 26)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ActivityTheme.benchBackground)
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .resting, .restOver:
            BenchRestContent(state: state, phase: phase)
        case .logging:
            BenchLoggingContent(state: state)
        case .complete:
            BenchCompleteContent(state: state)
        }
    }
}

// MARK: - Resting

/// The ring with the countdown on the left; the exercise, the next set and the buttons on the right.
struct BenchRestContent: View {
    let state: WorkoutSnapshot
    let phase: SnapshotPhase

    var body: some View {
        HStack(spacing: ActivityTheme.Metrics.benchColumnSpacing) {
            ActivityRestRing(
                state: state,
                phase: phase,
                diameter: ActivityTheme.Metrics.benchRingDiameter,
                lineWidth: ActivityTheme.Metrics.benchRingLineWidth,
                track: ActivityTheme.benchFill,
                centerFontSize: ActivityTheme.Metrics.benchCountdownSize,
                centerColor: state.isPaused ? ActivityTheme.paused : ActivityTheme.accent
            )
            VStack(alignment: .leading, spacing: 10) {
                headline
                next
                actions
                    .padding(.top, 6)
            }
        }
    }

    /// "Resting · Bench Press", or the record while its banner is up.
    @ViewBuilder
    private var headline: some View {
        if let moment = state.moment {
            Text("NEW RECORD \u{00B7} " + moment.exerciseName + " " + moment.workText)
                .font(ActivityTheme.text(17, .bold))
                .foregroundStyle(ActivityTheme.gold)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        } else {
            Text((phase == .restOver ? "Rest over" : "Resting") + " \u{00B7} " + state.exerciseName)
                .font(ActivityTheme.text(15))
                .foregroundStyle(ActivityTheme.benchSecondary)
                .lineLimit(1)
        }
    }

    /// "Next: set 4" over "80 kg × 6".
    private var next: some View {
        let lines = state.benchNext
        return VStack(alignment: .leading, spacing: 0) {
            Text(lines.title)
            if let detail = lines.detail {
                Text(detail)
            }
        }
        .font(ActivityTheme.text(28, .bold))
        .foregroundStyle(ActivityTheme.textPrimary)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var actions: some View {
        if phase == .restOver {
            if let intent = state.logSetIntent {
                ActivityLogButton(
                    intent: intent,
                    title: state.logTitle,
                    spokenTitle: state.logSpokenTitle,
                    height: ActivityTheme.Metrics.benchButtonHeight,
                    fillsWidth: true,
                    fontSize: 18
                )
            }
        } else {
            HStack(spacing: 8) {
                button(title: "+15 s", spoken: "Add 15 seconds", intent: AdjustRestIntent(seconds: 15))
                button(title: "Skip", spoken: "Skip rest", intent: SkipRestIntent())
            }
        }
    }

    private func button<Intent: AppIntent>(title: String, spoken: String, intent: Intent) -> some View {
        Button(intent: intent) {
            Text(title)
                .font(ActivityTheme.text(16, .semibold))
                .foregroundStyle(ActivityTheme.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: ActivityTheme.Metrics.benchButtonHeight)
                .background(ActivityTheme.benchFill, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(spoken)
    }
}

// MARK: - Logging

/// The exercise and the set, the weight and reps as large figures, and Log set.
struct BenchLoggingContent: View {
    let state: WorkoutSnapshot

    var body: some View {
        HStack(spacing: ActivityTheme.Metrics.benchColumnSpacing) {
            VStack(alignment: .leading, spacing: 6) {
                Text(state.exerciseName)
                    .font(ActivityTheme.text(28, .bold))
                    .foregroundStyle(ActivityTheme.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                Text(state.setLabel)
                    .font(ActivityTheme.text(17))
                    .foregroundStyle(ActivityTheme.benchSecondary)
                    .lineLimit(1)
                figures
                    .padding(.top, 4)
            }
            Spacer(minLength: 0)
            if let intent = state.logSetIntent {
                ActivityLogButton(
                    intent: intent,
                    title: state.logTitle,
                    spokenTitle: state.logSpokenTitle,
                    height: 64,
                    fillsWidth: false,
                    fontSize: 22
                )
            }
        }
    }

    /// "82.5 kg × 6 reps" with the figures in 72 pt; a bodyweight or timed exercise has no weight.
    private var figures: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if state.showsWeight {
                Text(state.weightText)
                    .font(ActivityTheme.number(72, .bold))
                    .foregroundStyle(ActivityTheme.textPrimary)
                Text("kg")
                    .font(ActivityTheme.text(24, .semibold))
                    .foregroundStyle(ActivityTheme.benchSecondary)
                Text("\u{00D7}")
                    .font(ActivityTheme.text(36))
                    .foregroundStyle(ActivityTheme.benchSecondary)
            }
            Text(state.repsText)
                .font(ActivityTheme.number(72, .bold))
                .foregroundStyle(ActivityTheme.textPrimary)
            Text(state.repsUnit)
                .font(ActivityTheme.text(24, .semibold))
                .foregroundStyle(ActivityTheme.benchSecondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            state.showsWeight
                ? state.weightText + " kilograms, " + state.repsText + " " + state.repsNoun
                : state.repsText + " " + state.repsNoun
        )
    }
}

// MARK: - Complete

/// Every set is logged, or the workout has none. A tap opens the app (`.widgetURL`).
struct BenchCompleteContent: View {
    let state: WorkoutSnapshot

    var body: some View {
        HStack(spacing: ActivityTheme.Metrics.benchColumnSpacing) {
            ZStack {
                Circle()
                    .fill(ActivityTheme.buttonGreen)
                if state.hasNoSets {
                    ActivityGlyph(kind: .barbell, size: 64, lineWidth: 2.4, color: Color.white)
                } else {
                    ActivityGlyph(kind: .check, size: 64, lineWidth: 3.2, color: Color.white)
                }
            }
            .frame(width: ActivityTheme.Metrics.benchRingDiameter, height: ActivityTheme.Metrics.benchRingDiameter)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(state.hasNoSets ? state.emptyTitle : "All sets logged")
                    .font(ActivityTheme.text(28, .bold))
                    .foregroundStyle(ActivityTheme.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                Text(state.hasNoSets ? state.emptyHint : state.progressLine)
                    .font(ActivityTheme.text(17))
                    .foregroundStyle(ActivityTheme.benchSecondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .accessibilityElement(children: .combine)
        }
    }
}
#endif
