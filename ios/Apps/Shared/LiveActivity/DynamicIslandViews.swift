// DynamicIslandViews.swift
//
// The Dynamic Island presentations of the Live Activity (DynamicIsland.dc.html): compact leading /
// trailing, minimal and the expanded regions (leading, trailing, bottom).
//
// Compact: resting shows the draining ring and the green countdown, otherwise the barbell and the elapsed
// time. Minimal: the ring (resting / rest over) or the barbell. Expanded: header row beside the camera
// (badge + set label, heart rate / countdown) and the controls in the bottom region, which is kept to about
// 88 pt so the island stays within the system's expanded height.
//
// All views take the raw snapshot plus `isStale` and derive the phase themselves (stale + resting = rest over).

#if os(iOS)
import SwiftUI
import PulseStrengthCore

// MARK: - Compact and minimal

struct IslandCompactLeading: View {
    let state: WorkoutSnapshot
    let isStale: Bool
    /// Snapshot tests only (nil in production): the instant the views are drawn at.
    @Environment(\.activityStaticNow) private var staticNow

    var body: some View {
        let phase = state.displayPhase(isStale: isStale, staticNow: staticNow)
        switch phase {
        case .resting, .restOver:
            ActivityRestRing(
                state: state,
                phase: phase,
                diameter: ActivityTheme.Metrics.compactRingDiameter,
                lineWidth: ActivityTheme.Metrics.compactRingLineWidth,
                track: ActivityTheme.compactTrack
            )
        case .logging:
            ActivityGlyph(kind: .barbell, size: 20, lineWidth: 2.2, color: ActivityTheme.accent)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Strength workout")
        case .complete:
            ActivityGlyph(kind: .check, size: 18, lineWidth: 2.8, color: ActivityTheme.accent)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("All sets logged")
        }
    }
}

struct IslandCompactTrailing: View {
    let state: WorkoutSnapshot
    let isStale: Bool
    /// Snapshot tests only (nil in production): the instant the views are drawn at.
    @Environment(\.activityStaticNow) private var staticNow

    var body: some View {
        let phase = state.displayPhase(isStale: isStale, staticNow: staticNow)
        switch phase {
        case .resting:
            ActivityRestCountdownText(
                state: state,
                phase: phase,
                size: 14,
                weight: .semibold,
                color: state.isPaused ? ActivityTheme.paused : ActivityTheme.accent,
                alignment: .trailing
            )
        case .restOver:
            Text("Go")
                .font(ActivityTheme.number(14, .semibold))
                .foregroundStyle(ActivityTheme.accent)
                .lineLimit(1)
        case .logging, .complete:
            ActivityElapsedText(
                state: state,
                size: 14,
                weight: .semibold,
                color: state.isPaused ? ActivityTheme.paused : ActivityTheme.textPrimary
            )
        }
    }
}

struct IslandMinimal: View {
    let state: WorkoutSnapshot
    let isStale: Bool
    /// Snapshot tests only (nil in production): the instant the views are drawn at.
    @Environment(\.activityStaticNow) private var staticNow

    var body: some View {
        let phase = state.displayPhase(isStale: isStale, staticNow: staticNow)
        switch phase {
        case .resting, .restOver:
            ActivityRestRing(
                state: state,
                phase: phase,
                diameter: ActivityTheme.Metrics.compactRingDiameter,
                lineWidth: ActivityTheme.Metrics.compactRingLineWidth,
                track: ActivityTheme.compactTrack
            )
        case .logging:
            ActivityGlyph(kind: .barbell, size: 18, lineWidth: 2.2, color: ActivityTheme.accent)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Strength workout")
        case .complete:
            ActivityGlyph(kind: .check, size: 16, lineWidth: 2.8, color: ActivityTheme.accent)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("All sets logged")
        }
    }
}

// MARK: - Expanded: leading

/// App badge and the phase title ("Rest", "Set 4 of 5", ...).
struct IslandExpandedLeading: View {
    let state: WorkoutSnapshot
    let isStale: Bool
    /// Snapshot tests only (nil in production): the instant the views are drawn at.
    @Environment(\.activityStaticNow) private var staticNow

    private var title: String {
        switch state.displayPhase(isStale: isStale, staticNow: staticNow) {
        case .resting: return state.isPaused ? "Rest \u{00B7} paused" : "Rest"
        case .restOver: return "Rest over"
        case .logging: return state.setLabel
        case .complete: return "All sets logged"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            ActivityAppBadge(size: 28, glyphSize: 16, cornerRadius: 8)
            Text(title)
                .font(ActivityTheme.text(15, .semibold))
                .foregroundStyle(ActivityTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

// MARK: - Expanded: trailing

/// The big green countdown while resting ("Go" when over); otherwise the heart rate, or the elapsed time
/// when there is no heart rate, or the frozen clock with a "Paused" label.
struct IslandExpandedTrailing: View {
    let state: WorkoutSnapshot
    let isStale: Bool
    /// Snapshot tests only (nil in production): the instant the views are drawn at.
    @Environment(\.activityStaticNow) private var staticNow

    var body: some View {
        let phase = state.displayPhase(isStale: isStale, staticNow: staticNow)
        switch phase {
        case .resting, .restOver:
            ActivityRestCountdownText(
                state: state,
                phase: phase,
                size: 34,
                weight: .bold,
                color: state.isPaused ? ActivityTheme.paused : ActivityTheme.accent,
                alignment: .trailing,
                tracking: -0.5
            )
        case .logging, .complete:
            clock
        }
    }

    @ViewBuilder
    private var clock: some View {
        if state.isPaused {
            ActivityPausedLabel(size: 15, detail: state.frozenElapsedText)
        } else if let bpm = state.heartRate {
            ActivityHeartRateLabel(bpm: bpm, size: 15, color: ActivityTheme.islandTextSecondary)
        } else {
            ActivityElapsedText(state: state, size: 15, weight: .regular, color: ActivityTheme.islandTextSecondary)
        }
    }
}

// MARK: - Expanded: bottom

/// Controls and text below the camera row.
struct IslandExpandedBottom: View {
    let state: WorkoutSnapshot
    let workoutName: String
    let isStale: Bool
    /// Snapshot tests only (nil in production): the instant the views are drawn at.
    @Environment(\.activityStaticNow) private var staticNow

    var body: some View {
        let phase = state.displayPhase(isStale: isStale, staticNow: staticNow)
        content(for: phase)
            .padding(.top, ActivityTheme.Metrics.islandBottomTopInset)
    }

    @ViewBuilder
    private func content(for phase: SnapshotPhase) -> some View {
        switch phase {
        case .logging:
            IslandLoggingBottom(state: state)
        case .resting:
            IslandRestBottom(state: state, isOver: false)
        case .restOver:
            IslandRestBottom(state: state, isOver: true)
        case .complete:
            IslandCompleteBottom(state: state, workoutName: workoutName)
        }
    }
}

/// Exercise name with "Log set", then the weight and reps steppers.
struct IslandLoggingBottom: View {
    let state: WorkoutSnapshot

    var body: some View {
        VStack(spacing: ActivityTheme.Metrics.islandRowSpacing) {
            HStack(spacing: 10) {
                Text(state.exerciseName)
                    .font(ActivityTheme.text(17, .semibold))
                    .foregroundStyle(ActivityTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                if let intent = state.logSetIntent {
                    ActivityLogButton(
                        intent: intent,
                        height: ActivityTheme.Metrics.islandLogButtonHeight,
                        fillsWidth: false,
                        fontSize: 15
                    )
                }
            }
            ActivitySteppers(
                state: state,
                surface: .island,
                height: ActivityTheme.Metrics.islandControlHeight
            )
        }
    }
}

/// Exercise name and "Next" line, then -15 s / +15 s / Skip (resting) or "Log set" (rest over).
struct IslandRestBottom: View {
    let state: WorkoutSnapshot
    let isOver: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(state.exerciseName)
                    .font(ActivityTheme.text(17, .semibold))
                    .foregroundStyle(ActivityTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(state.nextLine)
                    .font(ActivityTheme.text(14))
                    .foregroundStyle(ActivityTheme.islandTextSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            actions
        }
    }

    @ViewBuilder
    private var actions: some View {
        if isOver {
            if let intent = state.logSetIntent {
                ActivityLogButton(
                    intent: intent,
                    height: ActivityTheme.Metrics.islandRestButtonHeight,
                    fillsWidth: true,
                    fontSize: 17
                )
            }
        } else {
            ActivityRestControls(
                surface: .island,
                skipTitle: "Skip",
                height: ActivityTheme.Metrics.islandRestButtonHeight
            )
        }
    }
}

/// Every set is logged: workout name and totals. Tapping the island opens the app (`.widgetURL`).
struct IslandCompleteBottom: View {
    let state: WorkoutSnapshot
    let workoutName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(workoutName)
                .font(ActivityTheme.text(17, .semibold))
                .foregroundStyle(ActivityTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(state.progressLine)
                .font(ActivityTheme.text(14))
                .foregroundStyle(ActivityTheme.islandTextSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
#endif
