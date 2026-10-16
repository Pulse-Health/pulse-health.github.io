// LogSetWatchWidget.swift
//
// WA-04 Smart Stack: Log set. The next set of the running workout (exercise, "Set 3/4", weight and reps) with a round "Log set" button.
// The button is the first, and only, control of the card, which makes it the target of the double-tap gesture: pinch twice to log the
// set with the hands on the bar. It runs `WatchLogSetIntent` for that one set (`WorkoutAction.logSet` is idempotent), so a late or
// repeated tap can never log another set than the one shown.
// Compiled into the watchOS widget extension.

#if os(watchOS)
import SwiftUI
import WidgetKit
import PulseStrengthCore

struct LogSetWatchWidget: Widget {
    static let kind = WatchWidgetTopic.logSet.kind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: WatchProvider(topic: .logSet)) { entry in
            LogSetWatchView(entry: entry)
        }
        .configurationDisplayName("Log set")
        .description("Log the next set with a tap, or a double tap.")
        .supportedFamilies([.accessoryRectangular])
    }
}

struct LogSetWatchView: View {
    let entry: WatchEntry

    private var live: WatchLive { WatchLive(entry.snapshot.active, at: entry.date) }

    var body: some View {
        content
            .widgetURL(StrengthDeepLink.workout.url)
            .widgetBackground(WidgetTheme.card)
    }

    @ViewBuilder
    private var content: some View {
        let live = self.live
        if live.stage == .complete {
            WatchRectMessage(eyebrow: "WORKOUT", title: "All sets logged", detail: "Finish on your iPhone")
        } else if let active = live.active, let exerciseID = active.targetExerciseID, let setID = active.targetSetID {
            setCard(active, exerciseID: exerciseID, setID: setID, isPaused: live.isPaused)
        } else {
            WatchRectMessage(eyebrow: "LOG SET", title: "No workout running", detail: "Start one on your iPhone")
        }
    }

    private func setCard(_ active: WorkoutSnapshot, exerciseID: UUID, setID: UUID, isPaused: Bool) -> some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 3) {
                    if isPaused {
                        Image(systemName: "pause.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(WidgetTheme.recovering)
                    }
                    Text(active.exerciseName)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text("· " + WatchText.compactSet(active.setLabel))
                        .lineLimit(1)
                        .fixedSize()
                }
                .font(WidgetTheme.text(11))
                .foregroundStyle(WidgetTheme.inkSecondary)
                workText(active)
                    .foregroundStyle(WidgetTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spoken(active, isPaused: isPaused))
            WatchIntentButton(intent: WatchLogSetIntent(exerciseID: exerciseID.uuidString, setID: setID.uuidString)) {
                WatchRoundButtonLabel(systemImage: "checkmark", title: nil, fill: WidgetTheme.green, foreground: WidgetTheme.onGreen)
            }
            .widgetAccentable()
            .accessibilityLabel("Log set")
        }
    }

    /// "80 kg × 6" with the weight large and the unit small, "8 reps" or "45 s".
    private func workText(_ active: WorkoutSnapshot) -> Text {
        let large = WidgetTheme.number(24, .bold)
        let small = WidgetTheme.text(12, .semibold)
        switch active.tracking {
        case .weightReps:
            return Text(active.weightText).font(large)
                + Text(" kg").font(small).foregroundStyle(WidgetTheme.inkSecondary)
                + Text(" × " + active.repsText).font(WidgetTheme.number(18, .semibold))
        case .repsOnly:
            return Text(active.repsText).font(large) + Text(" reps").font(small).foregroundStyle(WidgetTheme.inkSecondary)
        case .duration:
            return Text(active.repsText).font(large) + Text(" s").font(small).foregroundStyle(WidgetTheme.inkSecondary)
        }
    }

    private func spoken(_ active: WorkoutSnapshot, isPaused: Bool) -> String {
        let work: String
        switch active.tracking {
        case .weightReps: work = "\(active.weightText) kilograms, \(active.repsText) reps"
        case .repsOnly: work = "\(active.repsText) reps"
        case .duration: work = "\(active.repsText) seconds"
        }
        return (isPaused ? "Workout paused. " : "") + "\(active.exerciseName), \(active.setLabel), \(work)"
    }
}
#endif
