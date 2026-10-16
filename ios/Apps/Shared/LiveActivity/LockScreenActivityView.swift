// LockScreenActivityView.swift
//
// The Lock Screen / banner presentation of the Live Activity (LockScreen.dc.html, LiveActivityNext.dc.html).
//
// Phases: logging (set label, - / + steppers, Log set), resting (ring, countdown, Next, -15 s / +15 s /
// Skip rest), rest over ("Go" + Log set) and complete ("All sets logged"; a tap opens the app through
// `.widgetURL`). While paused the clock and the rest are frozen and a "Paused" label replaces the running clock.
// A workout without any set (started empty) is `.complete` for the builder but has nothing logged: the card shows
// the barbell and "No exercises yet" with a hint instead of the check and "All sets logged".
//
// The live moments of the snapshot change the card (`WorkoutSnapshot.lockLayout`, first match wins; the cards are in
// LockScreenStates.swift): the finished workout (`finish`), a record just logged (`moment`), the coach tip while resting
// (`coachTip`), a superset or the plates while logging (`superset`, `plates`). In StandBy (`isFullscreen`) the large bench layout
// of BenchModeView.swift replaces the card.
//
// The system cuts a Live Activity off at about 160 pt, the mock-up is taller (about 230 pt in the logging
// phase), so the logging card puts "Log set" next to the exercise title instead of below the steppers. Every
// control, string and colour of the design is kept.

#if os(iOS)
import SwiftUI
import PulseStrengthCore

struct LockScreenActivityView: View {
    let state: WorkoutSnapshot
    let workoutName: String
    /// `ActivityViewContext.isStale`: the app sets `staleDate = restEndsAt`, so stale + resting means rest over.
    let isStale: Bool
    /// True when the activity fills the screen in StandBy (`EnvironmentValues.isActivityFullscreen`, iOS 17.2). It is a parameter
    /// and not read here because that environment value does not exist on iOS 17.0 and 17.1 and cannot be set by the tests:
    /// `WorkoutLockScreenContainer` reads it and passes it in.
    var isFullscreen: Bool = false
    /// Snapshot tests only (nil in production): the instant the views are drawn at.
    @Environment(\.activityStaticNow) private var staticNow

    var body: some View {
        let phase = state.displayPhase(isStale: isStale, staticNow: staticNow)
        Group {
            if isFullscreen && state.finish == nil {
                BenchModeView(state: state, phase: phase)
            } else {
                card(phase: phase)
            }
        }
        .environment(\.colorScheme, .dark)
    }

    private func card(phase: SnapshotPhase) -> some View {
        VStack(alignment: .leading, spacing: ActivityTheme.Metrics.lockSectionSpacing) {
            cardContent(phase: phase)
        }
        .padding(.horizontal, ActivityTheme.Metrics.lockSideInset)
        .padding(.top, ActivityTheme.Metrics.lockTopInset)
        .padding(.bottom, ActivityTheme.Metrics.lockBottomInset)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func cardContent(phase: SnapshotPhase) -> some View {
        switch state.lockLayout(phase: phase) {
        case .finish:
            if let finish = state.finish {
                LockFinishContent(finish: finish)
            }
        case .moment:
            LockScreenHeader(state: state, workoutName: workoutName)
            if let moment = state.moment {
                LockMomentContent(state: state, moment: moment, phase: phase)
            }
        case .coachTip:
            if let tip = state.coachTip {
                LockCoachTipContent(state: state, tip: tip, phase: phase)
            }
        case .superset:
            if let superset = state.superset {
                LockSupersetContent(state: state, superset: superset)
            }
        case .plates:
            LockScreenHeader(state: state, workoutName: workoutName, showsExercise: true)
            if let plates = state.plates {
                LockPlatesContent(state: state, plates: plates)
            }
        case .standard:
            LockScreenHeader(state: state, workoutName: workoutName)
            LockScreenContent(state: state, phase: phase)
        }
    }
}

// MARK: - Header

/// App badge, workout name, heart rate (when known) and the elapsed time (frozen with a "Paused" label when paused).
/// With `showsExercise` the exercise and the set replace the workout name: the plate row has taken the place of the exercise title
/// in the logging card, so the title moves up here.
struct LockScreenHeader: View {
    let state: WorkoutSnapshot
    let workoutName: String
    var showsExercise: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            ActivityAppBadge(size: ActivityTheme.Metrics.lockHeaderHeight, glyphSize: 15, cornerRadius: 7)
            title
            Spacer(minLength: 8)
            LockScreenStatus(state: state)
        }
        .frame(height: ActivityTheme.Metrics.lockHeaderHeight)
    }

    @ViewBuilder
    private var title: some View {
        if showsExercise {
            HStack(spacing: 5) {
                Text(state.exerciseName)
                    .font(ActivityTheme.text(15, .semibold))
                    .foregroundStyle(ActivityTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text("\u{00B7} " + state.setLabel)
                    .font(ActivityTheme.text(15))
                    .foregroundStyle(ActivityTheme.lockTextSecondary)
                    .lineLimit(1)
                    .fixedSize()
            }
        } else {
            Text(workoutName)
                .font(ActivityTheme.text(15, .semibold))
                .foregroundStyle(ActivityTheme.textPrimary)
                .lineLimit(1)
        }
    }
}

/// Heart rate (when known) and the elapsed clock, or the frozen clock with "Paused": the right end of every header.
struct LockScreenStatus: View {
    let state: WorkoutSnapshot

    var body: some View {
        HStack(spacing: 10) {
            if let bpm = state.heartRate {
                ActivityHeartRateLabel(bpm: bpm, size: 15, color: ActivityTheme.lockTextSecondary)
            }
            clock
        }
    }

    @ViewBuilder
    private var clock: some View {
        if state.isPaused {
            ActivityPausedLabel(size: 14, detail: state.frozenElapsedText)
        } else {
            ActivityElapsedText(state: state, size: 15, weight: .regular, color: ActivityTheme.lockTextSecondary)
        }
    }
}

// MARK: - Phase content

struct LockScreenContent: View {
    let state: WorkoutSnapshot
    let phase: SnapshotPhase

    var body: some View {
        switch phase {
        case .logging:
            LockLoggingContent(state: state)
        case .resting, .restOver:
            LockRestContent(state: state, phase: phase)
        case .complete:
            LockCompleteContent(state: state)
        }
    }
}

/// Exercise title (name and set label), "Log set", then the weight and reps steppers.
struct LockLoggingContent: View {
    let state: WorkoutSnapshot

    var body: some View {
        VStack(spacing: ActivityTheme.Metrics.lockRowSpacing) {
            HStack(spacing: 12) {
                titleBlock
                Spacer(minLength: 0)
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

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(state.exerciseName)
                .font(ActivityTheme.text(17, .semibold))
                .foregroundStyle(ActivityTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(state.setLabel)
                .font(ActivityTheme.text(14))
                .foregroundStyle(ActivityTheme.lockTextSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Ring with the countdown, exercise and "Next" text, then -15 s / +15 s / Skip rest (resting)
/// or "Log set" (rest over).
struct LockRestContent: View {
    let state: WorkoutSnapshot
    let phase: SnapshotPhase

    var body: some View {
        VStack(spacing: ActivityTheme.Metrics.lockRowSpacing) {
            HStack(spacing: 14) {
                ActivityRestRing(
                    state: state,
                    phase: phase,
                    diameter: ActivityTheme.Metrics.lockRingDiameter,
                    lineWidth: 6,
                    track: ActivityTheme.lockTrack,
                    centerFontSize: 16
                )
                textBlock
                Spacer(minLength: 0)
            }
            actions
        }
    }

    private var textBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(state.exerciseName)
                .font(ActivityTheme.text(17, .semibold))
                .foregroundStyle(ActivityTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(state.nextLine)
                .font(ActivityTheme.text(14))
                .foregroundStyle(ActivityTheme.lockTextSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            statusLine
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var statusLine: some View {
        if phase == .restOver {
            Text("Rest over")
                .font(ActivityTheme.text(12, .semibold))
                .foregroundStyle(ActivityTheme.accent)
                .lineLimit(1)
        } else {
            Text(state.restLine)
                .font(ActivityTheme.text(12))
                .foregroundStyle(ActivityTheme.lockTextTertiary)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var actions: some View {
        if phase == .restOver {
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
        } else {
            ActivityRestControls(
                surface: .lockScreen,
                skipTitle: "Skip rest",
                height: ActivityTheme.Metrics.lockRestButtonHeight
            )
        }
    }
}

/// Every set is logged (check, "All sets logged" and the totals), or there is no set at all (barbell, "No exercises yet"
/// and what to do). Tapping the activity opens the app (`.widgetURL`), where the workout is finished or filled.
struct LockCompleteContent: View {
    let state: WorkoutSnapshot

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(ActivityTheme.buttonGreen)
                if state.hasNoSets {
                    ActivityGlyph(kind: .barbell, size: 22, lineWidth: 2.4, color: Color.white)
                } else {
                    ActivityGlyph(kind: .check, size: 22, lineWidth: 3.2, color: Color.white)
                }
            }
            .frame(width: 44, height: 44)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(state.hasNoSets ? state.emptyTitle : "All sets logged")
                    .font(ActivityTheme.text(17, .semibold))
                    .foregroundStyle(ActivityTheme.textPrimary)
                    .lineLimit(1)
                Text(state.hasNoSets ? state.emptyHint : state.progressLine)
                    .font(ActivityTheme.text(14))
                    .foregroundStyle(ActivityTheme.lockTextSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
        }
    }
}
#endif
