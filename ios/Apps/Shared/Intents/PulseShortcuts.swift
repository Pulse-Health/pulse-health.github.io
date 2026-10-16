// PulseShortcuts.swift
//
// The App Shortcuts of Pulse Strength (widgets/SPEC.md CT-10): they appear in the Shortcuts app, answer to Siri and can be chosen for the Action
// button (Settings > Action Button > Shortcut). The Action button's "Controls" choice offers the controls of Apps/Shared/Controls instead.
// TARGET MEMBERSHIP: the app. Shortcuts are defined next to the intents they run, so this sits with the other files of Apps/Shared/Intents; the widget
// extension, the Watch widget extension and the snapshot-test bundle that compile that folder do not need it and may exclude this file (the app
// provides the shortcuts; if the Shortcuts app ever lists each one twice, exclude it there).
//
// "Primary action" is the Action-button shortcut (PrimaryActionIntent decides what a press means). The other three are spoken commands that
// each mean one thing, so Siri never skips a rest when the person asked to log a set. Every phrase contains the application name exactly once, as the
// system requires; `\(.applicationName)` is "Pulse Strength".

#if os(iOS)
import AppIntents
import Foundation
import PulseStrengthCore

struct PulseShortcuts: AppShortcutsProvider {
    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PrimaryActionIntent(),
            phrases: ["Do my next step in \(.applicationName)"],
            shortTitle: "Primary action",
            systemImageName: "dumbbell.fill"
        )
        AppShortcut(
            intent: LogNextSetControlIntent(),
            phrases: ["Log my set in \(.applicationName)"],
            shortTitle: "Log set",
            systemImageName: "checkmark"
        )
        AppShortcut(
            intent: StartNextIntent(),
            phrases: ["Start my workout in \(.applicationName)"],
            shortTitle: "Start workout",
            systemImageName: "play.fill"
        )
        AppShortcut(
            intent: SkipRestControlIntent(),
            phrases: ["Skip rest in \(.applicationName)"],
            shortTitle: "Skip rest",
            systemImageName: "forward.end.fill"
        )
    }
}

/// The Action button: one press, three meanings, decided from the stored snapshot at the moment of the press.
///   * a set is due (logging, or the rest is over)  -> log the next set,
///   * the rest timer runs                           -> skip the rest,
///   * no workout runs                               -> start the next workout (the app opens),
/// and it never finishes a workout. When every set is logged there is nothing to log or skip, so it only says so.
/// The answer is the short confirmation the system shows after the press; Siri may speak it instead.
struct PrimaryActionIntent: LiveActivityIntent, ForegroundContinuableIntent {
    static var title: LocalizedStringResource = "Primary action"
    static var description: IntentDescription? = IntentDescription("One button for the whole workout: logs the next set while you lift, skips the rest timer while you rest, and starts your next workout when none is running.")
    static var openAppWhenRun: Bool { false }

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let active = WidgetSnapshotStore.load()?.active
        switch WorkoutControlPhase(active: active) {
        case .logging, .restOver:
            await WidgetIntentDispatch.send(.logNextSet, origin: .system)
            let setText = active?.nextSetText ?? ""
            if setText.isEmpty {
                return .result(dialog: "Set logged.")
            }
            return .result(dialog: "Logged \(setText).")
        case .resting:
            await WidgetIntentDispatch.send(.skipRest, origin: .system)
            return .result(dialog: "Rest skipped.")
        case .complete:
            return .result(dialog: "All sets are logged. Finish the workout in Pulse Strength.")
        case .idle:
            try await requestToContinueInForeground()
            WidgetIntentDispatch.openApp(.startNext, origin: .system)
            return .result(dialog: "Starting your next workout.")
        }
    }
}
#endif
