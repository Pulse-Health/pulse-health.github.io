// ControlIntents.swift
//
// App Intents behind the Controls (Control Center and the Lock Screen's two bottom slots; widgets/SPEC.md CT-01...CT-09), the Action button
// (CT-10) and the Siri phrases of PulseShortcuts.swift. TARGET MEMBERSHIP: with the other files of Apps/Shared/Intents - the app, which runs
// them, and the widget extension, whose controls create them.
//
// Where an intent runs decides what it can do. Apple's documentation ("Configuring the runtime behavior of your app intents") says the system runs
// the app intent of a control from the widget extension, in the background, and prefers an extension to the app for a background intent that exists
// in both. An extension can only leave an action in the App Group inbox, which nobody reads while the app is suspended. A `LiveActivityIntent` is
// different: the system launches the app's process without opening the app and performs the intent there (the documentation's own example is a
// control in Control Center). So the intents come in three kinds:
//   * Intents that change the workout (log a set, skip the rest, pause) are `LiveActivityIntent`s, like the buttons of the Live Activity, and reach
//     the workout while the app is suspended. WidgetIntentDispatch.swift still copes with an extension process, should the system choose one.
//   * Intents that need the app on screen (start the next workout, plate calculator, finish) set `openAppWhenRun`, which only the app can satisfy.
//     They leave a deep link, which the app handles like an opened URL. A finish always needs the confirmation dialog of the app, so no control
//     finishes a workout on its own: Finish opens the running workout.
//   * `PrimaryActionIntent`, the Action button, has three meanings and opens the app in only one of them. `openAppWhenRun` is a static property,
//     so one intent cannot choose per press, and two separate intents cannot share one button. It is therefore a `ForegroundContinuableIntent`:
//     logging and resting finish in the background, and only the idle case asks the system to continue in the foreground (the system unlocks the
//     phone and may ask for a confirmation first). It is also a `LiveActivityIntent`, so that it runs in the app, never in the extension (an
//     extension cannot continue in the foreground). `ForegroundContinuableIntent` is deprecated from iOS 26 in favour of `supportedModes`, which
//     needs the iOS 26 SDK; while iOS 17 is supported this is the way to do it. The dedicated `StartNextIntent`, which always opens the app,
//     serves the controls and the "Start my workout" phrase.
//
// Every intent that reads the workout state reads the stored snapshot (`WidgetSnapshotStore.load()`), which the app writes with every change.

#if os(iOS)
import AppIntents
import Foundation
import PulseStrengthCore

// MARK: - Open the app

/// Start workout and Next up controls, and the "Start my workout" phrase: opens the app on the workout that comes next in the split. While a
/// workout already runs it opens that one instead, because the engine never starts a second workout and the running one is what the person wants.
struct StartNextIntent: AppIntent {
    static var title: LocalizedStringResource = "Start next workout"
    static var description: IntentDescription? = IntentDescription("Opens Pulse Strength and starts the next workout of your split, or returns to the workout that is running.")
    static var openAppWhenRun: Bool { true }

    init() {}

    func perform() async throws -> some IntentResult {
        let isRunning = WorkoutControlPhase(active: WidgetSnapshotStore.load()?.active) != .idle
        WidgetIntentDispatch.openApp(isRunning ? .workout : .startNext, origin: .system)
        return .result()
    }
}

/// Plate calculator control: opens the running workout on the plate calculator (the hub when none runs).
struct OpenPlateCalculatorControlIntent: AppIntent {
    static var title: LocalizedStringResource = "Open plate calculator"
    static var description: IntentDescription? = IntentDescription("Opens the plate calculator of the running workout in Pulse Strength.")
    static var openAppWhenRun: Bool { true }
    static var isDiscoverable: Bool { false }

    init() {}

    func perform() async throws -> some IntentResult {
        WidgetIntentDispatch.openApp(.plates, origin: .system)
        return .result()
    }
}

/// Finish workout control: opens the running workout, where finishing asks for its confirmation (and for the template update, when the
/// workout changed the template). Nothing is finished from outside the app.
struct FinishWorkoutControlIntent: AppIntent {
    static var title: LocalizedStringResource = "Finish workout"
    static var description: IntentDescription? = IntentDescription("Opens the running workout in Pulse Strength so you can finish it. Finishing always needs your confirmation in the app.")
    static var openAppWhenRun: Bool { true }
    static var isDiscoverable: Bool { false }

    init() {}

    func perform() async throws -> some IntentResult {
        WidgetIntentDispatch.openApp(.workout, origin: .system)
        return .result()
    }
}

// MARK: - Change the workout

/// Log set control and the "Log my set" phrase: logs the next pending set with the weight and reps it has.
struct LogNextSetControlIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Log next set"
    static var description: IntentDescription? = IntentDescription("Logs the next set of the running strength workout with its planned weight and reps.")
    static var openAppWhenRun: Bool { false }

    init() {}

    func perform() async throws -> some IntentResult {
        await WidgetIntentDispatch.send(.logNextSet, origin: .system)
        return .result()
    }
}

/// Rest timer control and the "Skip rest" phrase: ends the rest timer of the running workout.
struct SkipRestControlIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Skip rest"
    static var description: IntentDescription? = IntentDescription("Ends the rest timer of the running strength workout.")
    static var openAppWhenRun: Bool { false }

    init() {}

    func perform() async throws -> some IntentResult {
        await WidgetIntentDispatch.send(.skipRest, origin: .system)
        return .result()
    }
}

/// Pause control, a toggle: the system sets `value` to the state the person asked for. True pauses the workout (and freezes its rest timer),
/// false resumes it. Both actions are idempotent, so a repeated or late press cannot toggle the workout the wrong way round.
/// `SetValueIntent` is iOS 18 API (it exists for the toggle of a control), the app supports iOS 17.
@available(iOS 18.0, *)
struct SetPausedControlIntent: SetValueIntent, LiveActivityIntent {
    static var title: LocalizedStringResource = "Pause workout"
    static var description: IntentDescription? = IntentDescription("Pauses the running strength workout, or resumes it.")
    static var openAppWhenRun: Bool { false }
    static var isDiscoverable: Bool { false }

    /// True when the workout should be paused.
    @Parameter(title: "Paused", default: false)
    var value: Bool

    init() {}

    func perform() async throws -> some IntentResult {
        await WidgetIntentDispatch.send(value ? .pause : .resume, origin: .system)
        return .result()
    }
}

// MARK: - Action button

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
