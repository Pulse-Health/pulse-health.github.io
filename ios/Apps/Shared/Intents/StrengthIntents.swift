// StrengthIntents.swift
//
// App Intents behind the Live Activity / Dynamic Island buttons of Pulse Strength.
//
// TARGET MEMBERSHIP: this file MUST be a member of BOTH the iOS app target (PulseStrength) AND the
// widget extension target (PulseStrengthWidgets). Do not move it into a Swift package.
//
// Why: a `LiveActivityIntent` is *referenced* by the widget extension (the views create it inside
// `Button(intent:)`) but *executed* in the app's process, which the system launches in the background
// when the button is pressed. Apple's documented pattern is to compile the intent source into both
// targets. (Intents inside a Swift package would additionally need `AppIntentsPackage` plumbing that
// only exists from iOS 17.4.) The intents hold no logic of their own: they translate the button press
// into a `WorkoutAction` and hand it to `WorkoutCommandBus`, whose handler the app installs when
// `StrengthAppEnvironment` starts (see ARCHITECTURE.md 5.4). In the extension process no handler is ever
// installed, which is fine because `perform()` does not run there.

#if os(iOS)
import AppIntents
import Foundation
import PulseStrengthActivity
import PulseStrengthCore

// MARK: - Dispatch helper

/// Shared forwarding code of the four intents.
private enum LiveActivityDispatch {
    /// Sends `action` to the running app, marked as coming from the Live Activity.
    static func send(_ action: WorkoutAction) async {
        await WorkoutCommandBus.shared.perform(action, origin: .liveActivity)
    }
}

// MARK: - Log set

/// "Log set" button (logging phase and rest-over phase). Logs one specific set, so a late or repeated
/// tap can never log a different set than the one shown (`WorkoutAction.logSet` is idempotent).
struct LogSetIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Log set"
    static var description: IntentDescription? = IntentDescription("Logs the shown set of the running strength workout.")
    static var openAppWhenRun: Bool { false }

    /// `UUID` string of the exercise entry (`WorkoutSnapshot.targetExerciseID`).
    @Parameter(title: "Exercise ID", default: "")
    var exerciseID: String

    /// `UUID` string of the set (`WorkoutSnapshot.targetSetID`).
    @Parameter(title: "Set ID", default: "")
    var setID: String

    init() {}

    init(exerciseID: String, setID: String) {
        self.exerciseID = exerciseID
        self.setID = setID
    }

    func perform() async throws -> some IntentResult {
        guard let exerciseUUID = UUID(uuidString: exerciseID),
              let setUUID = UUID(uuidString: setID) else {
            return .result()
        }
        await LiveActivityDispatch.send(.logSet(exerciseID: exerciseUUID, setID: setUUID))
        return .result()
    }
}

// MARK: - Nudge set

/// The - / + buttons next to the weight and reps values. Edits the next pending set by whole steps
/// (`Exercise.weightStepKg` / `Exercise.repsStep` are applied by the reducer).
struct NudgeSetIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Adjust set"
    static var description: IntentDescription? = IntentDescription("Changes the weight or reps of the next set by one step.")
    static var openAppWhenRun: Bool { false }

    /// Number of weight steps to add (negative to subtract).
    @Parameter(title: "Weight steps", default: 0)
    var weightSteps: Int

    /// Number of reps steps to add (negative to subtract).
    @Parameter(title: "Reps steps", default: 0)
    var repsSteps: Int

    init() {}

    init(weightSteps: Int, repsSteps: Int) {
        self.weightSteps = weightSteps
        self.repsSteps = repsSteps
    }

    func perform() async throws -> some IntentResult {
        await LiveActivityDispatch.send(.nudgeNextSet(weightSteps: weightSteps, repsSteps: repsSteps))
        return .result()
    }
}

// MARK: - Adjust rest

/// The "-15 s" / "+15 s" buttons of the rest timer.
struct AdjustRestIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Adjust rest"
    static var description: IntentDescription? = IntentDescription("Adds or removes seconds on the running rest timer.")
    static var openAppWhenRun: Bool { false }

    /// Seconds to add to the rest timer (negative to subtract).
    @Parameter(title: "Seconds", default: 0)
    var seconds: Int

    init() {}

    init(seconds: Int) {
        self.seconds = seconds
    }

    func perform() async throws -> some IntentResult {
        await LiveActivityDispatch.send(.adjustRest(seconds: seconds))
        return .result()
    }
}

// MARK: - Skip rest

/// The "Skip" button of the rest timer.
struct SkipRestIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Skip rest"
    static var description: IntentDescription? = IntentDescription("Ends the rest timer of the running strength workout.")
    static var openAppWhenRun: Bool { false }

    init() {}

    func perform() async throws -> some IntentResult {
        await LiveActivityDispatch.send(.skipRest)
        return .result()
    }
}
#endif
