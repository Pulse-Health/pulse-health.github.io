// ActivityComponents.swift
//
// Building blocks shared by the Lock Screen Live Activity and the Dynamic Island: app badge, glyphs,
// heart rate, running / frozen timers, rest ring, steppers, "Log set" button, rest buttons and the
// "Paused" label. Compiled into the widget extension next to Apps/Shared/Intents/StrengthIntents.swift.
//
// Live Activity rules these components follow:
// * Only timer-driven views animate in a Live Activity (`Text(timerInterval:)`, `Text(_:style: .timer)`,
//   `ProgressView(timerInterval:)`). Everything else is a snapshot that changes when the app updates the activity.
// * While the workout is paused nothing live is drawn: the frozen values from the snapshot are used.
// * Timer texts are greedy in width, so each one gets a fixed-width frame.

#if os(iOS)
import AppIntents
import SwiftUI
import PulseStrengthCore

// MARK: - Snapshot helpers

extension WorkoutSnapshot {
    /// The phase to draw. The app sets `staleDate = restEndsAt` while a rest runs, so a stale activity
    /// that was resting means the rest is over. A paused workout never has a running rest.
    func displayPhase(isStale: Bool, now: Date = Date()) -> SnapshotPhase {
        guard phase == .resting, !isPaused else { return phase }
        if isStale { return .restOver }
        if let end = restEndsAt, end <= now { return .restOver }
        return .resting
    }

    /// `displayPhase(isStale:now:)` at `staticNow` when the snapshot tests fix the clock (`\.activityStaticNow`),
    /// otherwise at the current time, exactly as before.
    func displayPhase(isStale: Bool, staticNow: Date?) -> SnapshotPhase {
        displayPhase(isStale: isStale, now: staticNow ?? Date())
    }

    /// `restStartedAt ... restEndsAt` for the system timer views; nil when the dates are missing or inverted.
    var restInterval: ClosedRange<Date>? {
        guard let end = restEndsAt else { return nil }
        let start = restStartedAt ?? end.addingTimeInterval(-Double(max(restTotalSeconds, 0)))
        guard start < end else { return nil }
        return start...end
    }

    /// Seconds left on the frozen rest (paused workout).
    var frozenRestSeconds: Int {
        max(0, restFrozenRemaining ?? 0)
    }

    /// Portion (0...1) of the rest that is left while paused.
    var frozenRestFraction: Double {
        guard restTotalSeconds > 0 else { return 0 }
        return min(1, max(0, Double(frozenRestSeconds) / Double(restTotalSeconds)))
    }

    /// "1:12" for the frozen rest.
    var frozenRestText: String {
        NumberText.clock(seconds: frozenRestSeconds)
    }

    /// "24:18" for the frozen elapsed time.
    var frozenElapsedText: String {
        NumberText.clock(seconds: elapsedWhenPaused)
    }

    /// The "Log set" intent for the target set; nil when there is no pending set.
    var logSetIntent: LogSetIntent? {
        guard let exerciseID = targetExerciseID, let setID = targetSetID else { return nil }
        return LogSetIntent(exerciseID: exerciseID.uuidString, setID: setID.uuidString)
    }

    /// "Next · Set 4 · 82.5 kg × 6"
    var nextLine: String {
        "Next · " + nextSetText
    }

    /// "Rest · 2:30", or "Rest · paused" while the workout is paused.
    var restLine: String {
        if isPaused { return "Rest · paused" }
        return "Rest · " + NumberText.rest(seconds: restTotalSeconds)
    }

    /// "12 of 12 sets · 4,980 kg"
    var progressLine: String {
        "\(loggedSets) of \(totalSets) sets · \(volumeText) kg"
    }

    /// Noun for VoiceOver on the reps stepper.
    var repsNoun: String {
        repsUnit == "sec" ? "seconds" : "reps"
    }

    /// True when the workout has no set at all (started empty, or every exercise or set was removed). The builder reports
    /// `.complete` for it, because there is no pending set, but nothing was logged: the views must not say "All sets logged".
    var hasNoSets: Bool {
        totalSets == 0
    }

    /// "No exercises yet" for a workout without exercises, "No sets yet" for one whose exercises have no set left.
    var emptyTitle: String {
        exerciseCount == 0 ? "No exercises yet" : "No sets yet"
    }

    /// What to do about an empty workout.
    var emptyHint: String {
        exerciseCount == 0 ? "Add exercises in Pulse Strength" : "Add sets in Pulse Strength"
    }

    /// True when the target set is a warm-up (`setLabel` is "Warm-up · Set 1 of 5").
    var isWarmupLabel: Bool {
        setLabel.hasPrefix(warmupLabelPrefix)
    }

    /// `setLabel` without the warm-up prefix: "Set 1 of 5" for "Warm-up · Set 1 of 5". Narrow places (the island's
    /// leading column) show "Warm-up" on a line of its own.
    var setPositionLabel: String {
        guard isWarmupLabel else { return setLabel }
        return String(setLabel.dropFirst(warmupLabelPrefix.count))
    }
}

/// What `SnapshotBuilder` puts in front of the position of a warm-up set.
private let warmupLabelPrefix = "Warm-up \u{00B7} "

// MARK: - Glyphs

/// The few line icons of the design (24 pt grid, round caps), drawn as shapes so they match the mock-up exactly.
struct ActivityGlyphShape: Shape {
    enum Kind {
        case barbell
        case minus
        case plus
        case check
    }

    var kind: Kind

    func path(in rect: CGRect) -> Path {
        let unit = min(rect.width, rect.height) / 24
        let originX = rect.midX - 12 * unit
        let originY = rect.midY - 12 * unit
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: originX + x * unit, y: originY + y * unit)
        }
        var p = Path()
        switch kind {
        case .barbell:
            p.move(to: point(6.5, 7))
            p.addLine(to: point(6.5, 17))
            p.move(to: point(17.5, 7))
            p.addLine(to: point(17.5, 17))
            p.move(to: point(3.5, 9.5))
            p.addLine(to: point(3.5, 14.5))
            p.move(to: point(20.5, 9.5))
            p.addLine(to: point(20.5, 14.5))
            p.move(to: point(6.5, 12))
            p.addLine(to: point(17.5, 12))
        case .minus:
            p.move(to: point(5, 12))
            p.addLine(to: point(19, 12))
        case .plus:
            p.move(to: point(12, 5))
            p.addLine(to: point(12, 19))
            p.move(to: point(5, 12))
            p.addLine(to: point(19, 12))
        case .check:
            p.move(to: point(5, 12.5))
            p.addLine(to: point(9.5, 17))
            p.addLine(to: point(19, 7.5))
        }
        return p
    }
}

/// A stroked glyph. `lineWidth` is in units of the 24 pt design grid and scales with `size`.
struct ActivityGlyph: View {
    let kind: ActivityGlyphShape.Kind
    var size: CGFloat
    var lineWidth: CGFloat
    var color: Color

    var body: some View {
        ActivityGlyphShape(kind: kind)
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth * size / 24, lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
    }
}

/// The green rounded-square app badge with the barbell (26 pt on the Lock Screen, 28 pt in the island).
struct ActivityAppBadge: View {
    var size: CGFloat
    var glyphSize: CGFloat
    var cornerRadius: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(ActivityTheme.buttonGreen)
            ActivityGlyph(kind: .barbell, size: glyphSize, lineWidth: 2.4, color: Color.white)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Heart rate

/// Red heart and the bpm value.
struct ActivityHeartRateLabel: View {
    let bpm: Int
    var size: CGFloat = 15
    var weight: Font.Weight = .regular
    /// Size of the heart glyph (12 pt beside the 15 pt figure of the header, 14 pt in the compact island).
    var heartSize: CGFloat = 12
    var color: Color

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "heart.fill")
                .font(.system(size: heartSize))
                .foregroundStyle(ActivityTheme.heart)
            Text(String(bpm))
                .font(ActivityTheme.number(size, weight))
                .foregroundStyle(color)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Heart rate \(bpm) beats per minute")
    }
}

// MARK: - Paused label

/// "Paused" with a pause glyph, optionally followed by the frozen clock ("Paused · 24:18").
/// With `stacked` (and a `detail`) the label is narrow: the pause glyph and the clock on one line, the word "Paused" under
/// them in a small size ("Paused · 24:18" is about 120 pt wide, the island's trailing column only about 100 pt).
struct ActivityPausedLabel: View {
    var size: CGFloat = 14
    var detail: String? = nil
    var stacked: Bool = false

    private var title: String {
        if let detail = detail { return "Paused \u{00B7} " + detail }
        return "Paused"
    }

    private var spokenTitle: String {
        if let detail = detail { return "Workout paused, elapsed " + detail }
        return "Workout paused"
    }

    var body: some View {
        content
            .foregroundStyle(ActivityTheme.paused)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spokenTitle)
    }

    @ViewBuilder
    private var content: some View {
        if stacked, let detail = detail {
            VStack(alignment: .trailing, spacing: 0) {
                HStack(spacing: 4) {
                    Image(systemName: "pause.fill")
                        .font(.system(size: size * 0.7, weight: .bold))
                    Text(detail)
                        .font(ActivityTheme.number(size, .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Text("Paused")
                    .font(ActivityTheme.text(11, .semibold))
                    .lineLimit(1)
            }
        } else {
            HStack(spacing: 4) {
                Image(systemName: "pause.fill")
                    .font(.system(size: size * 0.7, weight: .bold))
                Text(title)
                    .font(ActivityTheme.number(size, .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }
}

// MARK: - Timers

/// Elapsed workout time: a running `.timer` text, or the frozen clock while paused.
struct ActivityElapsedText: View {
    let state: WorkoutSnapshot
    var size: CGFloat = 15
    var weight: Font.Weight = .regular
    var color: Color
    /// Upper bound of the reserved width (the compact island slot); the clock scales down inside it. nil: no bound.
    var maxWidth: CGFloat? = nil
    /// Snapshot tests only (nil in production): draw the clock at this instant instead of a live timer.
    @Environment(\.activityStaticNow) private var staticNow

    private var label: Text {
        if state.isPaused {
            return Text(state.frozenElapsedText)
        }
        if let now = staticNow {
            return Text(NumberText.clock(seconds: max(0, Int(now.timeIntervalSince(state.activeStart)))))
        }
        return Text(state.activeStart, style: .timer)
    }

    private var hasHours: Bool {
        if state.isPaused { return state.elapsedWhenPaused >= 3600 }
        return (staticNow ?? Date()).timeIntervalSince(state.activeStart) >= 3300
    }

    private var reservedWidth: CGFloat {
        let width = ActivityTheme.clockWidth(fontSize: size, hasHours: hasHours)
        guard let limit = maxWidth else { return width }
        return min(width, limit)
    }

    var body: some View {
        label
            .font(ActivityTheme.number(size, weight))
            .monospacedDigit()
            .foregroundStyle(color)
            .multilineTextAlignment(.trailing)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(width: reservedWidth, alignment: .trailing)
    }
}

/// Rest countdown text. Running: `Text(timerInterval:countsDown:)`, which counts down on its own.
/// Paused: the frozen remaining time. Rest over: "Go".
struct ActivityRestCountdownText: View {
    let state: WorkoutSnapshot
    let phase: SnapshotPhase
    let size: CGFloat
    let weight: Font.Weight
    let color: Color
    var alignment: TextAlignment = .center
    var tracking: CGFloat = 0
    /// Snapshot tests only (nil in production): draw the countdown at this instant instead of a live timer.
    @Environment(\.activityStaticNow) private var staticNow

    private var label: Text {
        if phase == .restOver {
            return Text("Go")
        }
        if state.isPaused {
            return Text(state.frozenRestText)
        }
        if let now = staticNow, let interval = state.restInterval {
            let remaining = Int(max(0, interval.upperBound.timeIntervalSince(now)).rounded(.up))
            return Text(NumberText.clock(seconds: remaining))
        }
        if let interval = state.restInterval {
            return Text(timerInterval: interval, countsDown: true, showsHours: false)
        }
        return Text(NumberText.clock(seconds: 0))
    }

    private var frameAlignment: Alignment {
        switch alignment {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }

    var body: some View {
        label
            .font(ActivityTheme.number(size, weight))
            .monospacedDigit()
            .tracking(tracking)
            .foregroundStyle(color)
            .multilineTextAlignment(alignment)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(width: ActivityTheme.countdownWidth(fontSize: size), alignment: frameAlignment)
    }
}

// MARK: - Rest ring

/// The rest ring.
/// * Running: `ProgressView(timerInterval:countsDown:)` in the circular style (label-less, tinted), the
///   only way a ring keeps draining inside a Live Activity.
/// * Paused: a static ring at the frozen fraction.
/// * Rest over: a static full ring.
/// With `centerFontSize` the countdown ("Go" when over) is drawn in the middle, in `centerColor`.
struct ActivityRestRing: View {
    let state: WorkoutSnapshot
    let phase: SnapshotPhase
    let diameter: CGFloat
    let lineWidth: CGFloat
    let track: Color
    var centerFontSize: CGFloat? = nil
    var centerColor: Color = Color.white
    /// Snapshot tests only (nil in production): draw a static ring for this instant instead of a live `ProgressView`.
    @Environment(\.activityStaticNow) private var staticNow

    var body: some View {
        ZStack {
            ring
            if let fontSize = centerFontSize {
                ActivityRestCountdownText(
                    state: state,
                    phase: phase,
                    size: fontSize,
                    weight: .bold,
                    color: centerColor
                )
            }
        }
        .frame(width: diameter, height: diameter)
    }

    @ViewBuilder
    private var ring: some View {
        if phase == .restOver {
            staticRing(fraction: 1)
        } else if state.isPaused {
            staticRing(fraction: state.frozenRestFraction)
        } else if let now = staticNow, let interval = state.restInterval {
            staticRing(fraction: remainingFraction(of: interval, at: now))
        } else if let interval = state.restInterval {
            ProgressView(timerInterval: interval, countsDown: true) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .progressViewStyle(.circular)
            .tint(ActivityTheme.accent)
            .frame(width: diameter, height: diameter)
            .accessibilityHidden(true)
        } else {
            staticRing(fraction: 0)
        }
    }

    /// Portion (0...1) of `interval` that is left at `now` (snapshot tests only).
    private func remainingFraction(of interval: ClosedRange<Date>, at now: Date) -> Double {
        let total = interval.upperBound.timeIntervalSince(interval.lowerBound)
        guard total > 0 else { return 0 }
        return min(1, max(0, interval.upperBound.timeIntervalSince(now) / total))
    }

    private func staticRing(fraction: Double) -> some View {
        ZStack {
            Circle()
                .stroke(track, lineWidth: lineWidth)
            if fraction > 0 {
                Circle()
                    .trim(from: 0, to: CGFloat(min(1, fraction)))
                    .stroke(ActivityTheme.accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
        .padding(lineWidth / 2)
        .accessibilityHidden(true)
    }
}

// MARK: - Stepper

/// A "- value unit +" capsule. The buttons run `NudgeSetIntent` in the app without opening it.
struct ActivityStepper: View {
    let value: String
    let unit: String
    let valueDescription: String
    let decrement: NudgeSetIntent
    let increment: NudgeSetIntent
    let decrementLabel: String
    let incrementLabel: String
    let surface: ActivitySurface
    let height: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            stepButton(decrement, kind: .minus, label: decrementLabel)
            Spacer(minLength: 2)
            valueView
            Spacer(minLength: 2)
            stepButton(increment, kind: .plus, label: incrementLabel)
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background(surface.pillFill, in: Capsule())
    }

    private var valueView: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(value)
                .font(ActivityTheme.number(16, .bold))
                .foregroundStyle(ActivityTheme.textPrimary)
            if !unit.isEmpty {
                Text(" " + unit)
                    .font(ActivityTheme.number(12, .semibold))
                    .foregroundStyle(surface.secondaryText)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(valueDescription)
    }

    private func stepButton(_ intent: NudgeSetIntent, kind: ActivityGlyphShape.Kind, label: String) -> some View {
        Button(intent: intent) {
            ActivityGlyph(kind: kind, size: 16, lineWidth: 3, color: Color.white)
                .frame(width: height - 8, height: height - 8)
                .background(surface.pillButtonFill, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Weight stepper (only for weight-tracked exercises) and reps / seconds stepper side by side.
struct ActivitySteppers: View {
    let state: WorkoutSnapshot
    let surface: ActivitySurface
    let height: CGFloat

    var body: some View {
        HStack(spacing: 10) {
            if state.showsWeight {
                weightStepper
            }
            repsStepper
        }
    }

    private var weightStepper: some View {
        ActivityStepper(
            value: state.weightText,
            unit: "kg",
            valueDescription: "Weight, \(state.weightText) kilograms",
            decrement: NudgeSetIntent(weightSteps: -1, repsSteps: 0),
            increment: NudgeSetIntent(weightSteps: 1, repsSteps: 0),
            decrementLabel: "Decrease weight",
            incrementLabel: "Increase weight",
            surface: surface,
            height: height
        )
    }

    private var repsStepper: some View {
        ActivityStepper(
            value: state.repsText,
            unit: state.repsUnit,
            valueDescription: "\(state.repsText) \(state.repsNoun)",
            decrement: NudgeSetIntent(weightSteps: 0, repsSteps: -1),
            increment: NudgeSetIntent(weightSteps: 0, repsSteps: 1),
            decrementLabel: "Decrease \(state.repsNoun)",
            incrementLabel: "Increase \(state.repsNoun)",
            surface: surface,
            height: height
        )
    }
}

// MARK: - Log set button

/// Green "Log set" capsule. Runs `LogSetIntent` for one specific set, so a late tap can never log another set.
/// In a superset the title names the member that is logged ("Log A2").
struct ActivityLogButton: View {
    let intent: LogSetIntent
    var title: String = "Log set"
    var spokenTitle: String = "Log set"
    var height: CGFloat = 44
    var fillsWidth: Bool = true
    var fontSize: CGFloat = 17

    var body: some View {
        Button(intent: intent) {
            HStack(spacing: 8) {
                ActivityGlyph(kind: .check, size: 16, lineWidth: 3.2, color: Color.white)
                Text(title)
                    .font(ActivityTheme.text(fontSize, .semibold))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: maxWidth)
            .frame(height: height)
            .background(ActivityTheme.buttonGreen, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(spokenTitle)
    }

    private var maxWidth: CGFloat? {
        fillsWidth ? CGFloat.infinity : nil
    }
}

// MARK: - Rest buttons

/// Lays its children out in one row with widths proportional to `weights` (the design's flex-grow 1 / 1 / 1.4).
struct ActivityWeightedRow: Layout {
    var weights: [CGFloat]
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let widths = columnWidths(total: proposal.width, count: subviews.count)
        var height: CGFloat = 0
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(ProposedViewSize(width: widths[index], height: proposal.height))
            height = max(height, size.height)
        }
        let gaps = spacing * CGFloat(max(0, subviews.count - 1))
        let total = widths.reduce(0, +) + gaps
        return CGSize(width: total, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let widths = columnWidths(total: bounds.width, count: subviews.count)
        var x = bounds.minX
        for index in subviews.indices {
            subviews[index].place(
                at: CGPoint(x: x, y: bounds.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: widths[index], height: bounds.height)
            )
            x += widths[index] + spacing
        }
    }

    private func columnWidths(total: CGFloat?, count: Int) -> [CGFloat] {
        guard count > 0 else { return [] }
        var available: CGFloat = 300
        if let total = total, total.isFinite {
            available = total
        }
        let usable = max(0, available - spacing * CGFloat(count - 1))
        var weightValues: [CGFloat] = []
        for index in 0..<count {
            weightValues.append(index < weights.count ? max(0.01, weights[index]) : 1)
        }
        let weightSum = weightValues.reduce(0, +)
        return weightValues.map { usable * $0 / weightSum }
    }
}

/// "-15 s", "+15 s" and "Skip rest" / "Skip": `AdjustRestIntent` and `SkipRestIntent`.
struct ActivityRestControls: View {
    let surface: ActivitySurface
    let skipTitle: String
    let height: CGFloat

    var body: some View {
        ActivityWeightedRow(weights: [1, 1, 1.4], spacing: 8) {
            adjustButton(seconds: -15, title: "\u{2212}15 s", spoken: "Subtract 15 seconds")
            adjustButton(seconds: 15, title: "+15 s", spoken: "Add 15 seconds")
            skipButton
        }
        .frame(height: height)
    }

    private func adjustButton(seconds: Int, title: String, spoken: String) -> some View {
        Button(intent: AdjustRestIntent(seconds: seconds)) {
            Text(title)
                .font(ActivityTheme.number(15, .semibold))
                .foregroundStyle(ActivityTheme.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .background(
                    surface.controlFill,
                    in: RoundedRectangle(cornerRadius: surface.buttonRadius(height: height), style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(spoken)
    }

    private var skipButton: some View {
        Button(intent: SkipRestIntent()) {
            Text(skipTitle)
                .font(ActivityTheme.text(15, .semibold))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .background(
                    ActivityTheme.buttonGreen,
                    in: RoundedRectangle(cornerRadius: surface.buttonRadius(height: height), style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Skip rest")
    }
}
#endif
