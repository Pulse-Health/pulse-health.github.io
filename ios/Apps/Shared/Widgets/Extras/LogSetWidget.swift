// LogSetWidget.swift
//
// WI-02 Log from the Home Screen (systemMedium, interactive). The widget shows `snapshot.active`, the content of the Live Activity:
//   * a set is waiting (logging, rest over): exercise and set label, a reps stepper and (weight exercises) a weight stepper made of
//     `Button(intent: NudgeSetIntent)`, and "Log set" (`LogSetIntent` for that exact set, so a late tap can never log another one);
//   * resting: the countdown (`Text(timerInterval:)` keeps counting without a reload), "+15 s" and "Skip rest";
//   * every set logged: a check, and a tap into the workout where it is finished;
//   * no workout: a "Start workout" `Link`.
// The intents are the Live Activity's: they run in the app, or leave the command in the App Group inbox (WidgetIntentDispatch).
//
// A widget can only redraw when the app writes a new snapshot, so the view shows what the snapshot says. The values a button changes are
// marked `invalidatableContent()`: from the tap until the new snapshot is presented the system draws them as invalidated, so a stale
// number does not look current. Whether a rest is over is decided at the entry's date, not at the render time: the provider adds an
// entry at the end of every rest.

#if os(iOS)
import AppIntents
import SwiftUI
import WidgetKit
import PulseStrengthCore

struct LogSetWidget: Widget {
    static let kind = "health.pulse.strength.widget.logSet"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: SnapshotProvider()) { entry in
            LogSetView(entry: entry)
        }
        .configurationDisplayName("Log set")
        .description("Log the next set, change weight and reps and run the rest timer from the Home Screen while a workout is running.")
        .supportedFamilies([.systemMedium])
    }
}

struct LogSetView: View {
    let entry: SnapshotEntry

    var body: some View {
        card
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .widgetCardBackground()
            .widgetURL(entry.snapshot.active == nil ? StrengthDeepLink.hub.url : StrengthDeepLink.workout.url)
    }

    @ViewBuilder
    private var card: some View {
        switch LogSetMode.resolve(entry.snapshot.active, at: entry.date) {
        case .idle:
            LogSetIdleCard(nextUp: entry.snapshot.nextUp)
        case .logging(let active, let restOver):
            LogSetLoggingCard(active: active, restOver: restOver)
        case .resting(let active, let countdown):
            LogSetRestCard(active: active, countdown: countdown)
        case .complete(let active):
            LogSetCompleteCard(active: active)
        }
    }
}

// MARK: - Mode

/// What the widget draws for the running workout at the date of an entry.
private enum LogSetMode {
    case idle
    case logging(WorkoutSnapshot, restOver: Bool)
    /// `countdown` is nil while the workout is paused: the rest then stands still at `restFrozenRemaining`.
    case resting(WorkoutSnapshot, countdown: ClosedRange<Date>?)
    case complete(WorkoutSnapshot)

    static func resolve(_ active: WorkoutSnapshot?, at now: Date) -> LogSetMode {
        guard let active else { return .idle }
        switch active.phase {
        case .complete:
            return .complete(active)
        case .logging:
            return .logging(active, restOver: false)
        case .restOver:
            return .logging(active, restOver: true)
        case .resting:
            if active.isPaused { return .resting(active, countdown: nil) }
            // The snapshot says "resting" until the app writes the next one; once the rest has run out at `now` the set is waiting again.
            if let countdown = LogSetCountdown.interval(of: active, endingAfter: now) {
                return .resting(active, countdown: countdown)
            }
            return .logging(active, restOver: true)
        }
    }
}

private enum LogSetCountdown {
    /// The span the system timer views count down over; nil when the rest has ended at `now` or its dates are missing or inverted.
    static func interval(of active: WorkoutSnapshot, endingAfter now: Date) -> ClosedRange<Date>? {
        guard let end = active.restEndsAt, end > now else { return nil }
        let start = active.restStartedAt ?? end.addingTimeInterval(-Double(max(active.restTotalSeconds, 0)))
        guard start < end else { return nil }
        return start...end
    }
}

// MARK: - Logging

/// Exercise and set, "Log set", the steppers and (when there is room) the progress of the exercise and the workout.
private struct LogSetLoggingCard: View {
    let active: WorkoutSnapshot
    let restOver: Bool

    private var logIntent: LogSetIntent? {
        guard let exerciseID = active.targetExerciseID, let setID = active.targetSetID else { return nil }
        return LogSetIntent(exerciseID: exerciseID.uuidString, setID: setID.uuidString)
    }

    /// "Set 2 of 3", followed by "Rest over" and "Paused" when they apply.
    private var subtitle: String {
        var parts = [active.setLabel]
        if restOver { parts.append("Rest over") }
        if active.isPaused { parts.append("Paused") }
        return parts.joined(separator: " \u{00B7} ")
    }

    private var repsNoun: String { active.repsUnit == "sec" ? "seconds" : "reps" }

    var body: some View {
        ViewThatFits(in: .vertical) {
            VStack(alignment: .leading, spacing: 10) {
                header
                steppers
                progress
            }
            VStack(alignment: .leading, spacing: 10) {
                header
                steppers
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(active.exerciseName)
                    .font(WidgetTheme.text(17, .semibold))
                    .foregroundStyle(WidgetTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(subtitle)
                    .font(WidgetTheme.text(13))
                    .foregroundStyle(restOver ? WidgetTheme.greenText : WidgetTheme.inkSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .invalidatableContent()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(active.exerciseName + ". " + subtitle)
            if let intent = logIntent {
                LogSetButton(intent: intent)
            }
        }
    }

    private var steppers: some View {
        HStack(spacing: 8) {
            if active.showsWeight {
                LogSetStepper(
                    value: active.weightText,
                    unit: "kg",
                    spoken: "Weight, \(active.weightText) kilograms",
                    decrement: NudgeSetIntent(weightSteps: -1, repsSteps: 0),
                    increment: NudgeSetIntent(weightSteps: 1, repsSteps: 0),
                    decrementLabel: "Decrease weight",
                    incrementLabel: "Increase weight"
                )
            }
            LogSetStepper(
                value: active.repsText,
                unit: active.repsUnit,
                spoken: "\(active.repsText) \(repsNoun)",
                decrement: NudgeSetIntent(weightSteps: 0, repsSteps: -1),
                increment: NudgeSetIntent(weightSteps: 0, repsSteps: 1),
                decrementLabel: "Decrease \(repsNoun)",
                incrementLabel: "Increase \(repsNoun)"
            )
        }
    }

    /// The sets of this exercise as bars, then the progress of the workout ("5 of 12 sets" and the volume so far).
    private var progress: some View {
        HStack(spacing: 8) {
            if let total = active.exerciseSetCount, total > 0 {
                LogSetDots(done: active.exerciseDoneSets ?? 0, total: total)
            }
            Text(verbatim: "\(active.loggedSets) of \(active.totalSets) sets \u{00B7} \(active.volumeText) kg")
                .font(WidgetTheme.text(12))
                .foregroundStyle(WidgetTheme.inkSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
        .invalidatableContent()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(active.loggedSets) of \(active.totalSets) sets logged, \(active.volumeText) kilograms lifted")
    }
}

/// "- value unit +" in a capsule. The value is stacked over its unit, so two steppers fit side by side on the narrowest widget.
private struct LogSetStepper: View {
    let value: String
    let unit: String
    let spoken: String
    let decrement: NudgeSetIntent
    let increment: NudgeSetIntent
    let decrementLabel: String
    let incrementLabel: String

    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.colorScheme) private var colorScheme

    private var palette: ExtrasPalette { ExtrasPalette(renderingMode: renderingMode, colorScheme: colorScheme) }

    var body: some View {
        HStack(spacing: 0) {
            stepButton(decrement, systemImage: "minus", label: decrementLabel)
            VStack(spacing: 0) {
                Text(value)
                    .font(WidgetTheme.number(20))
                    .foregroundStyle(WidgetTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(unit)
                    .font(WidgetTheme.text(11))
                    .foregroundStyle(WidgetTheme.inkSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .invalidatableContent()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spoken)
            stepButton(increment, systemImage: "plus", label: incrementLabel)
        }
        .padding(.horizontal, 2)
        .frame(maxWidth: .infinity)
        .frame(height: 48)
        .background(palette.surface, in: Capsule())
    }

    /// A 40 pt round button inside a 44 x 48 pt touch area.
    private func stepButton(_ intent: NudgeSetIntent, systemImage: String, label: String) -> some View {
        Button(intent: intent) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(WidgetTheme.ink)
                .frame(width: 40, height: 40)
                .background(palette.raised, in: Circle())
                .frame(width: 44, height: 48)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

private struct LogSetButton: View {
    let intent: LogSetIntent

    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.colorScheme) private var colorScheme

    private var palette: ExtrasPalette { ExtrasPalette(renderingMode: renderingMode, colorScheme: colorScheme) }

    var body: some View {
        Button(intent: intent) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                Text("Log set")
                    .font(WidgetTheme.text(16, .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(WidgetTheme.onGreen)
            .padding(.horizontal, 16)
            .frame(height: 44)
            .background {
                Capsule().fill(palette.action(WidgetTheme.green)).widgetAccentable()
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Log set")
    }
}

/// One bar per set of the exercise: logged, the one that waits, the ones to come.
private struct LogSetDots: View {
    let done: Int
    let total: Int

    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.colorScheme) private var colorScheme

    private var palette: ExtrasPalette { ExtrasPalette(renderingMode: renderingMode, colorScheme: colorScheme) }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<min(total, 8), id: \.self) { index in
                Capsule()
                    .fill(color(for: index))
                    .frame(width: 18, height: 6)
                    .widgetAccentable(index < done)
            }
        }
        .accessibilityHidden(true)
    }

    private func color(for index: Int) -> Color {
        if index < done { return WidgetTheme.progress }
        return index == done ? palette.step : palette.track
    }
}

// MARK: - Resting

/// The countdown with the next set beside it, then "+15 s" and "Skip rest". A shorter variant keeps both buttons on the smallest widget.
private struct LogSetRestCard: View {
    let active: WorkoutSnapshot
    let countdown: ClosedRange<Date>?

    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.colorScheme) private var colorScheme

    private var palette: ExtrasPalette { ExtrasPalette(renderingMode: renderingMode, colorScheme: colorScheme) }
    private var frozenSeconds: Int { max(0, active.restFrozenRemaining ?? 0) }

    private var frozenFraction: Double {
        guard active.restTotalSeconds > 0 else { return 0 }
        return min(1, max(0, Double(frozenSeconds) / Double(active.restTotalSeconds)))
    }

    private var remainingText: Text {
        if let countdown {
            return Text(timerInterval: countdown, countsDown: true, showsHours: false)
        }
        return Text(NumberText.clock(seconds: frozenSeconds))
    }

    var body: some View {
        ViewThatFits(in: .vertical) {
            layout(compact: false)
            layout(compact: true)
        }
    }

    private func layout(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            HStack(alignment: .center, spacing: 14) {
                clock(compact: compact)
                upNext
            }
            controls
        }
    }

    /// The timer text is as wide as its container allows, so it gets a fixed width (m:ss at the font size).
    private func clock(compact: Bool) -> some View {
        let size: CGFloat = compact ? 30 : 38
        return VStack(alignment: .leading, spacing: compact ? 3 : 4) {
            if !compact {
                ExtrasEyebrow(title: active.isPaused ? "Rest \u{00B7} paused" : "Rest", color: WidgetTheme.greenText)
            }
            remainingText
                .font(WidgetTheme.number(size))
                .foregroundStyle(WidgetTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .multilineTextAlignment(.leading)
                .widgetAccentable()
            meter
                .accessibilityHidden(true)
        }
        .frame(width: size * 2.75, alignment: .leading)
        .invalidatableContent()
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var meter: some View {
        if let countdown {
            ProgressView(timerInterval: countdown, countsDown: true) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .progressViewStyle(.linear)
            .tint(WidgetTheme.progress)
            .widgetAccentable()
        } else {
            ExtrasProgressBar(fraction: frozenFraction, height: 6)
        }
    }

    /// The set that waits after the rest.
    private var upNext: some View {
        VStack(alignment: .leading, spacing: 2) {
            ExtrasEyebrow(title: "Up next")
            Text(active.exerciseName)
                .font(WidgetTheme.text(17, .semibold))
                .foregroundStyle(WidgetTheme.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Text(active.nextSetText)
                .font(WidgetTheme.text(13))
                .foregroundStyle(WidgetTheme.inkSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .invalidatableContent()
        .accessibilityElement(children: .combine)
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Button(intent: AdjustRestIntent(seconds: 15)) {
                Text("+15 s")
                    .font(WidgetTheme.number(15, .semibold))
                    .foregroundStyle(WidgetTheme.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(palette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add 15 seconds")
            Button(intent: SkipRestIntent()) {
                Text("Skip rest")
                    .font(WidgetTheme.text(15, .semibold))
                    .foregroundStyle(WidgetTheme.onGreen)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(palette.action(WidgetTheme.green))
                            .widgetAccentable()
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Skip rest")
        }
    }
}

// MARK: - Complete and idle

/// Every set is logged, or the workout has no set at all. The widget's tap target opens the workout, where it is finished or filled.
private struct LogSetCompleteCard: View {
    let active: WorkoutSnapshot

    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.colorScheme) private var colorScheme

    private var palette: ExtrasPalette { ExtrasPalette(renderingMode: renderingMode, colorScheme: colorScheme) }
    private var hasNoSets: Bool { active.totalSets == 0 }

    private var title: String {
        if !hasNoSets { return "All sets logged" }
        return active.exerciseCount == 0 ? "No exercises yet" : "No sets yet"
    }

    private var detail: String {
        if !hasNoSets { return "\(active.loggedSets) of \(active.totalSets) sets \u{00B7} \(active.volumeText) kg" }
        return active.exerciseCount == 0 ? "Add exercises in Pulse Strength" : "Add sets in Pulse Strength"
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: hasNoSets ? "dumbbell.fill" : "checkmark")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(WidgetTheme.onGreen)
                .frame(width: 48, height: 48)
                .background {
                    Circle().fill(palette.action(WidgetTheme.green)).widgetAccentable()
                }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(WidgetTheme.text(17, .semibold))
                    .foregroundStyle(WidgetTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(detail)
                    .font(WidgetTheme.text(13))
                    .foregroundStyle(WidgetTheme.inkSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text("Tap to open the workout")
                    .font(WidgetTheme.text(12))
                    .foregroundStyle(WidgetTheme.inkSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title + ". " + detail + ". Opens the workout.")
    }
}

/// No workout: what "Start workout" will start, and the link that starts it.
private struct LogSetIdleCard: View {
    let nextUp: NextUpSummary?

    private var eyebrow: String { nextUp == nil ? "No workout running" : "Next up" }
    private var title: String { nextUp?.name ?? "Empty workout" }

    private var detail: String {
        guard let nextUp else { return "Add exercises as you go." }
        return WidgetText.exercises(nextUp.exerciseCount) + " \u{00B7} " + WidgetText.minutes(nextUp.estimatedMinutes)
    }

    /// `start-next` needs a template to start; without one the link starts an empty workout.
    private var destination: StrengthDeepLink {
        nextUp == nil ? .startEmpty(name: StrengthConfig.defaultWorkoutName) : .startNext
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                ExtrasEyebrow(title: eyebrow)
                Text(title)
                    .font(WidgetTheme.text(17, .semibold))
                    .foregroundStyle(WidgetTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(detail)
                    .font(WidgetTheme.text(13))
                    .foregroundStyle(WidgetTheme.inkSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            Link(destination: destination.url) {
                ExtrasPill(title: "Start workout", systemImage: "play.fill", height: 44)
            }
        }
    }
}
#endif
