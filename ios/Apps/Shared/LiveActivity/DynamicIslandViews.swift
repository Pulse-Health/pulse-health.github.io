// DynamicIslandViews.swift
//
// The Dynamic Island presentations of the Live Activity (DynamicIsland.dc.html, LiveActivityNext.dc.html): compact leading /
// trailing, minimal and the expanded regions (leading, trailing, bottom).
//
// Compact (`WorkoutSnapshot.compactMode`, the priority of widgets/SPEC.md section 1): a record shows the trophy and a gold "PR"
// (LA-07); otherwise a rest shows the draining ring and the green countdown; otherwise a superset shows the current member's tag
// and the round, "A2" and "2/3" (LA-09); otherwise, while logging, the set dots (LA-08) and the heart rate (LA-10) or, without one,
// the elapsed time. Minimal: the trophy, the ring, the tag or the barbell. Expanded: header row beside the camera (badge + set
// label, heart rate / countdown) and the controls in the bottom region, which is kept to about 90 pt so the island stays within the
// system's expanded height; a record puts its banner there, a superset its rows beside a tall Log button, the plates sit under
// the exercise name, and the coach tip replaces the rest buttons. The columns beside the camera are only about 100 pt wide: their
// texts are short, split over two lines or scaled down, never cut off.
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
        switch state.compactMode(phase: phase) {
        case .record:
            IslandTrophy(size: 17)
        case .rest:
            ActivityRestRing(
                state: state,
                phase: phase,
                diameter: ActivityTheme.Metrics.compactRingDiameter,
                lineWidth: ActivityTheme.Metrics.compactRingLineWidth,
                track: ActivityTheme.compactTrack
            )
        case .superset:
            if let superset = state.superset {
                IslandSupersetTag(superset: superset, size: .compact)
            } else {
                barbell
            }
        case .logging:
            if let progress = state.setProgress {
                ActivitySetDots(done: progress.done, total: progress.total)
            } else {
                barbell
            }
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
        switch state.compactMode(phase: phase) {
        case .record:
            Text("PR")
                .font(ActivityTheme.number(14, .bold))
                .foregroundStyle(ActivityTheme.gold)
                .lineLimit(1)
                .accessibilityLabel("Personal record")
        case .rest:
            if phase == .restOver {
                Text("Go")
                    .font(ActivityTheme.number(14, .semibold))
                    .foregroundStyle(ActivityTheme.accent)
                    .lineLimit(1)
            } else {
                ActivityRestCountdownText(
                    state: state,
                    phase: phase,
                    size: 14,
                    weight: .semibold,
                    color: state.isPaused ? ActivityTheme.paused : ActivityTheme.accent,
                    alignment: .trailing
                )
            }
        case .superset:
            if let superset = state.superset {
                Text(superset.compactRound)
                    .font(ActivityTheme.number(14, .bold))
                    .foregroundStyle(ActivityTheme.blueText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .accessibilityLabel("Round " + String(superset.round) + " of " + String(superset.rounds))
            }
        case .logging:
            logging
        case .complete:
            elapsed
        }
    }

    /// The heart rate when the Watch reports one (LA-10); the elapsed clock without one, and the frozen amber clock while paused.
    @ViewBuilder
    private var logging: some View {
        if !state.isPaused, let bpm = state.heartRate {
            ActivityHeartRateLabel(
                bpm: bpm,
                size: 14,
                weight: .bold,
                heartSize: 14,
                color: ActivityTheme.textPrimary
            )
        } else {
            elapsed
        }
    }

    private var elapsed: some View {
        ActivityElapsedText(
            state: state,
            size: 14,
            weight: .semibold,
            color: state.isPaused ? ActivityTheme.paused : ActivityTheme.textPrimary,
            maxWidth: ActivityTheme.Metrics.compactSlotWidth
        )
    }
}

struct IslandMinimal: View {
    let state: WorkoutSnapshot
    let isStale: Bool
    /// Snapshot tests only (nil in production): the instant the views are drawn at.
    @Environment(\.activityStaticNow) private var staticNow

    var body: some View {
        let phase = state.displayPhase(isStale: isStale, staticNow: staticNow)
        switch state.compactMode(phase: phase) {
        case .record:
            IslandTrophy(size: 16)
        case .rest:
            ActivityRestRing(
                state: state,
                phase: phase,
                diameter: ActivityTheme.Metrics.compactRingDiameter,
                lineWidth: ActivityTheme.Metrics.compactRingLineWidth,
                track: ActivityTheme.compactTrack
            )
        case .superset:
            if let superset = state.superset {
                IslandSupersetTag(superset: superset, size: .minimal)
            } else {
                barbell
            }
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

/// The gold trophy of a record in the compact and minimal island.
struct IslandTrophy: View {
    var size: CGFloat

    var body: some View {
        Image(systemName: "trophy.fill")
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(ActivityTheme.gold)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("New personal record")
    }
}

/// LA-09: the tag of the member that is logged next ("A2") on a blue pill.
struct IslandSupersetTag: View {
    enum Size {
        case compact
        case minimal
    }

    let superset: SupersetBrief
    let size: Size

    var body: some View {
        Text(superset.compactTag)
            .font(ActivityTheme.number(size == .compact ? 12 : 11, .bold))
            .foregroundStyle(Color.white)
            .lineLimit(1)
            .padding(.horizontal, size == .compact ? 7 : 5)
            .frame(height: size == .compact ? 22 : 20)
            .background(ActivityTheme.blue, in: Capsule())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Superset " + superset.label + ", now " + superset.compactTag)
    }
}

// MARK: - Expanded: leading

/// App badge and the phase title ("Rest", "Set 4 of 5", ...).
///
/// The column beside the camera is only about 100 pt wide and the badge takes 36 of them, so what does not fit in one
/// line is split: a warm-up is "Set 1 of 5" with a small "Warm-up" under it, a paused rest "Rest" with a small amber
/// "Paused" (the countdown beside the camera is amber too), a superset "Round 2/3" over a small blue "Superset A", a record "PR"
/// over a small gold "New record" beside a gold trophy instead of the badge, and the long titles of a finished or empty workout drop
/// the badge. The title scales down (to 0.7) before it would be cut off.
struct IslandExpandedLeading: View {
    let state: WorkoutSnapshot
    let isStale: Bool
    /// Snapshot tests only (nil in production): the instant the views are drawn at.
    @Environment(\.activityStaticNow) private var staticNow

    private enum Badge {
        case app
        case record
        case hidden
    }

    private struct Heading {
        var title: String
        var caption: String? = nil
        var captionColor: Color = ActivityTheme.islandTextSecondary
        var badge: Badge = .app
    }

    private var heading: Heading {
        if state.moment != nil {
            return Heading(title: "PR", caption: "New record", captionColor: ActivityTheme.gold, badge: .record)
        }
        switch state.displayPhase(isStale: isStale, staticNow: staticNow) {
        case .resting:
            if state.isPaused {
                return Heading(title: "Rest", caption: "Paused", captionColor: ActivityTheme.paused)
            }
            return Heading(title: "Rest")
        case .restOver:
            return Heading(title: "Rest over")
        case .logging:
            if let superset = state.superset, !superset.members.isEmpty {
                return Heading(
                    title: "Round " + superset.compactRound,
                    caption: "Superset " + superset.label,
                    captionColor: ActivityTheme.blueText
                )
            }
            if state.isWarmupLabel {
                return Heading(title: state.setPositionLabel, caption: "Warm-up")
            }
            return Heading(title: state.setLabel)
        case .complete:
            return Heading(title: state.hasNoSets ? state.emptyTitle : "All sets logged", badge: .hidden)
        }
    }

    var body: some View {
        let shown = heading
        HStack(spacing: 8) {
            switch shown.badge {
            case .app:
                ActivityAppBadge(size: 28, glyphSize: 16, cornerRadius: 8)
            case .record:
                ActivityTrophyDisc(size: 28)
            case .hidden:
                EmptyView()
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
        if let moment = state.moment {
            IslandMomentBottom(state: state, moment: moment, phase: phase)
        } else {
            switch phase {
            case .logging:
                if let superset = state.superset, !superset.members.isEmpty {
                    IslandSupersetBottom(state: state, superset: superset)
                } else {
                    IslandLoggingBottom(state: state)
                }
            case .resting:
                if let tip = state.coachTip {
                    IslandCoachTipBottom(tip: tip)
                } else {
                    IslandRestBottom(state: state, isOver: false)
                }
            case .restOver:
                IslandRestBottom(state: state, isOver: true)
            case .complete:
                IslandCompleteBottom(state: state, workoutName: workoutName)
            }
        }
    }
}

/// Exercise name with "Log set", then the weight and reps steppers. A barbell exercise shows its plates under the name (LA-03).
struct IslandLoggingBottom: View {
    let state: WorkoutSnapshot

    var body: some View {
        VStack(spacing: ActivityTheme.Metrics.islandRowSpacing) {
            HStack(spacing: 10) {
                titleBlock
                Spacer(minLength: 0)
                if let intent = state.logSetIntent {
                    ActivityLogButton(
                        intent: intent,
                        title: state.logTitle,
                        spokenTitle: state.logSpokenTitle,
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

    @ViewBuilder
    private var titleBlock: some View {
        if let plates = state.plates {
            VStack(alignment: .leading, spacing: 2) {
                Text(state.exerciseName)
                    .font(ActivityTheme.text(15, .semibold))
                    .foregroundStyle(ActivityTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                HStack(spacing: 6) {
                    ActivityPlateStrip(perSide: plates.perSide, height: 14)
                    Text(plates.displaySummary + " " + plates.caption)
                        .font(ActivityTheme.number(12, .regular))
                        .foregroundStyle(ActivityTheme.islandTextSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(plates.spokenText)
            }
        } else {
            Text(state.exerciseName)
                .font(ActivityTheme.text(17, .semibold))
                .foregroundStyle(ActivityTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
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
                    title: state.logTitle,
                    spokenTitle: state.logSpokenTitle,
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

// MARK: - Expanded: live moments

/// LA-01: the compact gold banner, then the controls of the phase (4 + 44 + 6 + 38 = 92 pt resting, 94 pt logging).
struct IslandMomentBottom: View {
    let state: WorkoutSnapshot
    let moment: PRMoment
    let phase: SnapshotPhase

    var body: some View {
        VStack(spacing: ActivityTheme.Metrics.islandRowSpacing) {
            ActivityMomentBanner(moment: moment, surface: .island)
            line
        }
    }

    @ViewBuilder
    private var line: some View {
        switch phase {
        case .resting:
            ActivityRestControls(
                surface: .island,
                skipTitle: "Skip",
                height: ActivityTheme.Metrics.islandRestButtonHeight
            )
        case .restOver:
            if let intent = state.logSetIntent {
                ActivityLogButton(
                    intent: intent,
                    title: state.logTitle,
                    spokenTitle: state.logSpokenTitle,
                    height: ActivityTheme.Metrics.islandRestButtonHeight,
                    fillsWidth: true,
                    fontSize: 17
                )
            }
        case .logging:
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
                        title: state.logTitle,
                        spokenTitle: state.logSpokenTitle,
                        height: ActivityTheme.Metrics.islandLogButtonHeight,
                        fillsWidth: false,
                        fontSize: 15
                    )
                }
            }
        case .complete:
            Text(state.progressLine)
                .font(ActivityTheme.text(14))
                .foregroundStyle(ActivityTheme.islandTextSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// LA-02: the members of the superset (the current one ringed in blue) beside a Log button that names it ("Log A2").
struct IslandSupersetBottom: View {
    let state: WorkoutSnapshot
    let superset: SupersetBrief

    private var rows: ActivitySupersetRows {
        ActivitySupersetRows(members: superset.members, surface: .island)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            rows
            if let intent = state.logSetIntent {
                ActivityTallLogButton(
                    intent: intent,
                    title: state.logTitle,
                    spokenTitle: state.logSpokenTitle,
                    width: ActivityTheme.Metrics.islandSupersetButtonWidth,
                    height: max(rows.totalHeight, ActivityTheme.Metrics.islandControlHeight)
                )
            }
        }
    }
}

/// LA-04: the coach tip in one line over the suggested weight, the weight to keep and Skip (4 + 17 + 6 + 38 = 65 pt).
struct IslandCoachTipBottom: View {
    let tip: CoachTipBrief

    var body: some View {
        VStack(alignment: .leading, spacing: ActivityTheme.Metrics.islandRowSpacing) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("Coach:")
                    .font(ActivityTheme.text(14, .bold))
                    .foregroundStyle(ActivityTheme.done)
                    .fixedSize()
                Text(tip.bodyText)
                    .font(ActivityTheme.text(14))
                    .foregroundStyle(ActivityTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Coach tip. " + tip.bodyText)
            ActivityTipChoices(tip: tip, surface: .island, height: ActivityTheme.Metrics.islandRestButtonHeight)
        }
    }
}
#endif
