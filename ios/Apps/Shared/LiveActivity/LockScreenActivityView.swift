// LockScreenActivityView.swift
//
// The Lock Screen / banner presentation of the Live Activity (LockScreen.dc.html).
//
// Phases: logging (set label, - / + steppers, Log set), resting (ring, countdown, Next, -15 s / +15 s /
// Skip rest), rest over ("Go" + Log set) and complete ("All sets logged"; a tap opens the app through
// `.widgetURL`). While paused the clock and the rest are frozen and a "Paused" label replaces the running clock.
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
    /// Snapshot tests only (nil in production): the instant the views are drawn at.
    @Environment(\.activityStaticNow) private var staticNow

    var body: some View {
        let phase = state.displayPhase(isStale: isStale, staticNow: staticNow)
        VStack(alignment: .leading, spacing: ActivityTheme.Metrics.lockSectionSpacing) {
            LockScreenHeader(state: state, workoutName: workoutName)
            LockScreenContent(state: state, phase: phase)
        }
        .padding(.horizontal, ActivityTheme.Metrics.lockSideInset)
        .padding(.top, ActivityTheme.Metrics.lockTopInset)
        .padding(.bottom, ActivityTheme.Metrics.lockBottomInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .environment(\.colorScheme, .dark)
    }
}

// MARK: - Header

/// App badge, workout name, heart rate (when known) and the elapsed time (frozen with a "Paused" label when paused).
struct LockScreenHeader: View {
    let state: WorkoutSnapshot
    let workoutName: String

    var body: some View {
        HStack(spacing: 8) {
            ActivityAppBadge(size: ActivityTheme.Metrics.lockHeaderHeight, glyphSize: 14, cornerRadius: 7)
            Text(workoutName)
                .font(ActivityTheme.text(15, .semibold))
                .foregroundStyle(ActivityTheme.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 8)
            trailing
        }
        .frame(height: ActivityTheme.Metrics.lockHeaderHeight)
    }

    @ViewBuilder
    private var trailing: some View {
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

/// Every set is logged. Tapping the activity opens the app (`.widgetURL`), where the workout is finished.
struct LockCompleteContent: View {
    let state: WorkoutSnapshot

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(ActivityTheme.buttonGreen)
                ActivityGlyph(kind: .check, size: 22, lineWidth: 3.2, color: Color.white)
            }
            .frame(width: 44, height: 44)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("All sets logged")
                    .font(ActivityTheme.text(17, .semibold))
                    .foregroundStyle(ActivityTheme.textPrimary)
                    .lineLimit(1)
                Text(state.progressLine)
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
