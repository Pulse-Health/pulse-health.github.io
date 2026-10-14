// DynamicIslandViews.swift
//
// The Dynamic Island presentations of the Live Activity (DynamicIsland.dc.html): compact leading /
// trailing, minimal and the expanded regions (leading, trailing, bottom).
//
// Compact: resting shows the draining ring and the green countdown, otherwise the barbell and the elapsed
// time. Minimal: the ring (resting / rest over) or the barbell. Expanded: header row beside the camera
// (badge + set label, heart rate / countdown) and the controls in the bottom region, which is kept to about
// 90 pt so the island stays within the system's expanded height. The columns beside the camera are only about
// 100 pt wide: their texts are short, split over two lines or scaled down, never cut off.
//
// A workout without any set (started empty, or everything removed) is `.complete` for the builder but has
// nothing logged: it shows the barbell and "No exercises yet" instead of the check and "All sets logged".
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
            barbell
        case .complete:
            if state.hasNoSets {
                barbell
            } else {
                ActivityGlyph(kind: .check, size: 18, lineWidth: 2.8, color: ActivityTheme.accent)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("All sets logged")
            }
        }
    }

    private var barbell: some View {
        ActivityGlyph(kind: .barbell, size: 20, lineWidth: 2.2, color: ActivityTheme.accent)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Strength workout")
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
                color: state.isPaused ? ActivityTheme.paused : ActivityTheme.textPrimary,
                maxWidth: ActivityTheme.Metrics.compactSlotWidth
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
            barbell
        case .complete:
            if state.hasNoSets {
                barbell
            } else {
                ActivityGlyph(kind: .check, size: 16, lineWidth: 2.8, color: ActivityTheme.accent)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("All sets logged")
            }
        }
    }

    private var barbell: some View {
        ActivityGlyph(kind: .barbell, size: 18, lineWidth: 2.2, color: ActivityTheme.accent)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Strength workout")
    }
}

// MARK: - Expanded: leading

/// App badge and the phase title ("Rest", "Set 4 of 5", ...).
///
/// The column beside the camera is only about 100 pt wide and the badge takes 36 of them, so what does not fit in one
/// line is split: a warm-up is "Set 1 of 5" with a small "Warm-up" under it, a paused rest "Rest" with a small amber
/// "Paused" (the countdown beside the camera is amber too), and the long titles of a finished or empty workout drop the
/// badge. The title scales down (to 0.7) before it would be cut off.
struct IslandExpandedLeading: View {
    let state: WorkoutSnapshot
    let isStale: Bool
    /// Snapshot tests only (nil in production): the instant the views are drawn at.
    @Environment(\.activityStaticNow) private var staticNow

    private struct Heading {
        var title: String
        var caption: String? = nil
        var captionColor: Color = ActivityTheme.islandTextSecondary
        var showsBadge: Bool = true
    }

    private var heading: Heading {
        switch state.displayPhase(isStale: isStale, staticNow: staticNow) {
        case .resting:
            if state.isPaused {
                return Heading(title: "Rest", caption: "Paused", captionColor: ActivityTheme.paused)
            }
            return Heading(title: "Rest")
        case .restOver:
            return Heading(title: "Rest over")
        case .logging:
            if state.isWarmupLabel {
                return Heading(title: state.setPositionLabel, caption: "Warm-up")
            }
            return Heading(title: state.setLabel)
        case .complete:
            return Heading(title: state.hasNoSets ? state.emptyTitle : "All sets logged", showsBadge: false)
        }
    }

    var body: some View {
        let shown = heading
        HStack(spacing: 8) {
            if shown.showsBadge {
                ActivityAppBadge(size: 28, glyphSize: 16, cornerRadius: 8)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(shown.title)
                    .font(ActivityTheme.text(15, .semibold))
                    .foregroundStyle(ActivityTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let caption = shown.caption {
                    Text(caption)
                        .font(ActivityTheme.text(11, .semibold))
                        .foregroundStyle(shown.captionColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .accessibilityElement(children: .combine)
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
            ActivityPausedLabel(size: 15, detail: state.frozenElapsedText, stacked: true)
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

/// Every set is logged: workout name and totals; a workout without sets: its name and what to do about it.
/// Tapping the island opens the app (`.widgetURL`).
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
            Text(state.hasNoSets ? state.emptyHint : state.progressLine)
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
