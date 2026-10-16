// LockScreenStates.swift
//
// The Lock Screen cards of the live moments (widgets/SPEC.md LA-01...LA-05, mock-ups in LiveActivityNext.dc.html). Each view is the
// content of the card inside the insets that LockScreenActivityView adds (10 pt above, 12 pt below, 16 pt either side); the sums
// that keep every card within the system's 160 pt are in `ActivityTheme.Metrics`.
//
// Decisions the mock-ups leave open:
// * Record (LA-01): the banner is followed by a compact line (countdown and "Next" while resting, the exercise and Log set while
//   logging), without -15 s / +15 s / Skip or steppers: the moment lasts four seconds, and the mock-up shows no buttons either.
// * Superset (LA-02): the Log button stands beside the rows and is as tall as they are, so two or three members fit the budget;
//   with the full-width button of the mock-up the card would be 194 pt.
// * Plates (LA-03): the plate row takes the title's place beside Log set and the exercise moves into the header, so the steppers stay.
//   A superset wins over the plates when both are present (the superset card has no room for them).
// * Coach tip (LA-04): "Keep 80" is plain text, see `ActivityTipChoices`; a Skip button is added because the card replaces the rest row.
// * Finish (LA-05): no "Share summary" button (the app has no such action); a tap opens the Strength hub (WorkoutLiveActivity).

#if os(iOS)
import SwiftUI
import PulseStrengthCore

// MARK: - LA-01 record

/// The gold banner above a compact version of the rest or logging content.
struct LockMomentContent: View {
    let state: WorkoutSnapshot
    let moment: PRMoment
    let phase: SnapshotPhase

    var body: some View {
        VStack(spacing: ActivityTheme.Metrics.lockRowSpacing) {
            ActivityMomentBanner(moment: moment, surface: .lockScreen)
            line
        }
    }

    @ViewBuilder
    private var line: some View {
        switch phase {
        case .resting:
            restLine
        case .restOver:
            if let intent = state.logSetIntent {
                ActivityLogButton(
                    intent: intent,
                    title: state.logTitle,
                    spokenTitle: state.logSpokenTitle,
                    height: ActivityTheme.Metrics.lockRestButtonHeight,
                    fillsWidth: true,
                    fontSize: 17
                )
            }
        case .logging:
            loggingLine
        case .complete:
            completeLine
        }
    }

    /// "1:40  Next · Set 4 · 82.5 kg × 6 / Rest · 2:30"
    private var restLine: some View {
        HStack(spacing: 12) {
            ActivityRestCountdownText(
                state: state,
                phase: phase,
                size: 26,
                weight: .bold,
                color: state.isPaused ? ActivityTheme.paused : ActivityTheme.accent,
                alignment: .leading
            )
            VStack(alignment: .leading, spacing: 0) {
                Text(state.nextLine)
                    .font(ActivityTheme.text(14))
                    .foregroundStyle(ActivityTheme.lockTextSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(state.restLine)
                    .font(ActivityTheme.text(12))
                    .foregroundStyle(ActivityTheme.lockTextTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(height: ActivityTheme.Metrics.lockMomentLineHeight)
        .accessibilityElement(children: .combine)
    }

    /// The exercise and the set, with Log set beside them (no rest timer runs, so the next set is waiting).
    private var loggingLine: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text(state.exerciseName)
                    .font(ActivityTheme.text(15, .semibold))
                    .foregroundStyle(ActivityTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(state.setLabel)
                    .font(ActivityTheme.text(13))
                    .foregroundStyle(ActivityTheme.lockTextSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            if let intent = state.logSetIntent {
                ActivityLogButton(
                    intent: intent,
                    title: state.logTitle,
                    spokenTitle: state.logSpokenTitle,
                    height: ActivityTheme.Metrics.lockRestButtonHeight,
                    fillsWidth: false,
                    fontSize: 17
                )
            }
        }
        .frame(height: ActivityTheme.Metrics.lockRestButtonHeight)
    }

    /// The record was the last set.
    private var completeLine: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(ActivityTheme.buttonGreen)
                ActivityGlyph(kind: .check, size: 16, lineWidth: 3.2, color: Color.white)
            }
            .frame(width: 32, height: 32)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text("All sets logged")
                    .font(ActivityTheme.text(15, .semibold))
                    .foregroundStyle(ActivityTheme.textPrimary)
                    .lineLimit(1)
                Text(state.progressLine)
                    .font(ActivityTheme.text(13))
                    .foregroundStyle(ActivityTheme.lockTextSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
        }
        .frame(height: ActivityTheme.Metrics.lockMomentLineHeight)
    }
}

// MARK: - LA-02 superset

/// "Superset A · round 2/3" with the clock, the members as rows (the current one ringed in blue) and the Log button ("Log A2").
struct LockSupersetContent: View {
    let state: WorkoutSnapshot
    let superset: SupersetBrief

    private var rows: ActivitySupersetRows {
        ActivitySupersetRows(members: superset.members, surface: .lockScreen)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ActivityTheme.Metrics.lockSectionSpacing) {
            header
            HStack(alignment: .top, spacing: 8) {
                rows
                if let intent = state.logSetIntent {
                    ActivityTallLogButton(
                        intent: intent,
                        title: state.logTitle,
                        spokenTitle: state.logSpokenTitle,
                        width: ActivityTheme.Metrics.lockSupersetButtonWidth,
                        height: rows.totalHeight
                    )
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(superset.chipText)
                .font(ActivityTheme.text(13, .bold))
                .foregroundStyle(ActivityTheme.blueText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 10)
                .frame(height: ActivityTheme.Metrics.lockHeaderHeight)
                .background(ActivityTheme.blueChipFill, in: Capsule())
                .accessibilityLabel(superset.spokenChip)
            Spacer(minLength: 8)
            LockScreenStatus(state: state)
        }
        .frame(height: ActivityTheme.Metrics.lockHeaderHeight)
    }
}

// MARK: - LA-03 plates

/// The plate row beside Log set, then the steppers. The exercise and the set are in the header (`showsExercise`).
struct LockPlatesContent: View {
    let state: WorkoutSnapshot
    let plates: PlateBrief

    var body: some View {
        VStack(spacing: ActivityTheme.Metrics.lockRowSpacing) {
            HStack(spacing: 12) {
                ActivityPlateRow(plates: plates, height: ActivityTheme.Metrics.lockControlHeight)
                if let intent = state.logSetIntent {
                    ActivityLogButton(
                        intent: intent,
                        title: state.logTitle,
                        spokenTitle: state.logSpokenTitle,
                        height: ActivityTheme.Metrics.lockControlHeight,
                        fillsWidth: false,
                        fontSize: 17
                    )
                }
            }
            ActivitySteppers(
                state: state,
                surface: .lockScreen,
                height: ActivityTheme.Metrics.lockControlHeight
            )
        }
    }
}

// MARK: - LA-04 coach tip

/// The countdown with the question ("Felt easy?"), the tip, and the answer: the suggested weight as a button, the weight to keep.
struct LockCoachTipContent: View {
    let state: WorkoutSnapshot
    let tip: CoachTipBrief
    let phase: SnapshotPhase

    var body: some View {
        VStack(spacing: ActivityTheme.Metrics.lockRowSpacing) {
            top
            tipText
            ActivityTipChoices(tip: tip, surface: .lockScreen, height: ActivityTheme.Metrics.lockTipChoiceHeight)
        }
    }

    private var top: some View {
        HStack(spacing: 12) {
            ActivityRestCountdownText(
                state: state,
                phase: phase,
                size: 28,
                weight: .bold,
                color: state.isPaused ? ActivityTheme.paused : ActivityTheme.accent,
                alignment: .leading
            )
            VStack(alignment: .leading, spacing: 0) {
                Text(tip.title)
                    .font(ActivityTheme.text(15, .semibold))
                    .foregroundStyle(ActivityTheme.textPrimary)
                    .lineLimit(1)
                Text(tip.subtitle)
                    .font(ActivityTheme.text(13))
                    .foregroundStyle(ActivityTheme.lockTextSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        .frame(height: ActivityTheme.Metrics.lockTipTopHeight)
        .accessibilityElement(children: .combine)
    }

    /// "Coach: add 2.5 kg for set 3 to stay at 1–2 RIR." The label hangs beside the text, so a second line aligns with the first.
    private var tipText: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("Coach:")
                .font(ActivityTheme.text(14, .bold))
                .foregroundStyle(ActivityTheme.done)
                .fixedSize()
            Text(tip.bodyText)
                .font(ActivityTheme.text(14))
                .foregroundStyle(ActivityTheme.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.9)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, ActivityTheme.Metrics.lockTipPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ActivityTheme.tipFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Coach tip. " + tip.bodyText)
    }
}

// MARK: - LA-05 finish

/// The finished workout: its name, "Saved to Health" when it is, and four tiles (minutes, sets, tonnes, records).
struct LockFinishContent: View {
    let finish: FinishBrief

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            HStack(spacing: 6) {
                tile(value: String(finish.durationMinutes), label: "min", isRecord: false)
                tile(value: String(finish.sets), label: "sets", isRecord: false)
                tile(value: finish.volumeText, label: "tonnes", isRecord: false)
                tile(value: String(finish.personalRecordCount), label: finish.recordLabel, isRecord: finish.personalRecordCount > 0)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(finish.spokenText)
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(ActivityTheme.buttonGreen)
                ActivityGlyph(kind: .check, size: 16, lineWidth: 3.2, color: Color.white)
            }
            .frame(width: ActivityTheme.Metrics.lockFinishBadge, height: ActivityTheme.Metrics.lockFinishBadge)
            VStack(alignment: .leading, spacing: 0) {
                Text(finish.title)
                    .font(ActivityTheme.text(15, .semibold))
                    .foregroundStyle(ActivityTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if finish.savedToHealth {
                    Text("Saved to Health")
                        .font(ActivityTheme.text(13))
                        .foregroundStyle(ActivityTheme.lockTextSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// A tile: the figure over its unit. The record tile is gold, its label says PR as well.
    private func tile(value: String, label: String, isRecord: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(ActivityTheme.number(18, .bold))
                .foregroundStyle(isRecord ? ActivityTheme.gold : ActivityTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(ActivityTheme.text(11))
                .foregroundStyle(isRecord ? ActivityTheme.gold : ActivityTheme.lockTextSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: ActivityTheme.Metrics.lockTileHeight)
        .background(isRecord ? ActivityTheme.goldFill : ActivityTheme.lockTileFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
#endif
