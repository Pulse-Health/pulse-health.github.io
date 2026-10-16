// WatchIntents.swift
//
// The App Intents behind the buttons of the Watch widgets (Log set, +15 s, Skip, Start).
//
// TARGET MEMBERSHIP: this file MUST be a member of BOTH the watchOS widget extension (PulseStrengthWatchWidgets, which references the
// intents in `Button(intent:)`) AND the Watch app (PulseStrengthWatch), exactly like Apps/Shared/Intents/StrengthIntents.swift on the iPhone.
// It therefore depends only on Foundation, AppIntents and PulseStrengthCore, never on the other widget files.
//
// How an action reaches the workout. The Watch app owns the Watch's mirror of the workout and is the only code that forwards an edit to
// the iPhone (`WorkoutController.send(_, origin: .watch)` -> `RemoteCommand` -> WatchConnectivity). A widget extension must not invent a
// second path, so `perform()` only leaves the request in the Watch's command inbox (`WidgetCommandInbox`, in the Watch's App Group
// directory) and posts the Darwin notification `StrengthConfig.commandInboxNotification`. `WatchWidgetSnapshotReceiver` in the Watch app
// drains the inbox on that notification, when the app launches and whenever it asks the iPhone for its state, and applies each action
// with the Watch controller.
//
// Which intents open the app. Log set, +15 s and Skip rest are handled quietly (`openAppWhenRun = false`): during a workout the Watch app is
// kept running by its Health session, so it hears the notification at once. Start cannot be handled quietly: starting a workout is the
// iPhone's job and the Watch has no way to ask for it, so the intent opens the Watch app (`openAppWhenRun = true`), which shows the running
// workout when the iPhone already started it and asks the iPhone for its state.

#if os(watchOS)
import AppIntents
import Foundation
import PulseStrengthCore

// MARK: - Hand-off

/// Leaves a request for the Watch app in the App Group inbox and wakes the app if it is running.
enum WatchWidgetDispatch {
    /// A workout action to apply with the Watch controller.
    static func send(_ action: WorkoutAction) {
        leave(PendingWidgetCommand(action: action, origin: .watch))
    }

    /// A link the app handles as if it had been opened by URL (start the next workout).
    static func openApp(_ link: StrengthDeepLink) {
        leave(PendingWidgetCommand(deepLink: link, origin: .watch))
    }

    private static func leave(_ command: PendingWidgetCommand) {
        guard let inbox = WidgetCommandInbox.shared() else { return }
        do {
            try inbox.append(command)
        } catch {
            return
        }
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(StrengthConfig.commandInboxNotification as CFString),
            nil,
            nil,
            true
        )
    }
}

// MARK: - Log set

/// The "Log set" button of the Log set card. Logs one specific set, so a late or repeated tap can never log a different set than the
/// one shown (`WorkoutAction.logSet` is idempotent).
struct WatchLogSetIntent: AppIntent {
    static var title: LocalizedStringResource = "Log set"
    static var description: IntentDescription? = IntentDescription("Logs the shown set of the running strength workout.")
    static var openAppWhenRun: Bool { false }
    static var isDiscoverable: Bool { false }

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
        WatchWidgetDispatch.send(.logSet(exerciseID: exerciseUUID, setID: setUUID))
        return .result()
    }
}

// MARK: - Adjust rest

/// The "+15" button of the Rest card.
struct WatchAdjustRestIntent: AppIntent {
    static var title: LocalizedStringResource = "Adjust rest"
    static var description: IntentDescription? = IntentDescription("Adds or removes seconds on the running rest timer.")
    static var openAppWhenRun: Bool { false }
    static var isDiscoverable: Bool { false }

    /// Seconds to add to the rest timer (negative to subtract).
    @Parameter(title: "Seconds", default: 0)
    var seconds: Int

    init() {}

    init(seconds: Int) {
        self.seconds = seconds
    }

    func perform() async throws -> some IntentResult {
        WatchWidgetDispatch.send(.adjustRest(seconds: seconds))
        return .result()
    }
}

// MARK: - Skip rest

/// The "Skip" button of the Rest card.
struct WatchSkipRestIntent: AppIntent {
    static var title: LocalizedStringResource = "Skip rest"
    static var description: IntentDescription? = IntentDescription("Ends the rest timer of the running strength workout.")
    static var openAppWhenRun: Bool { false }
    static var isDiscoverable: Bool { false }

    init() {}

    func perform() async throws -> some IntentResult {
        WatchWidgetDispatch.send(.skipRest)
        return .result()
    }
}

// MARK: - Start

/// The "Start" button of the Next up card: opens the Watch app and leaves the `start-next` link for it (see the header).
struct WatchStartNextIntent: AppIntent {
    static var title: LocalizedStringResource = "Start next workout"
    static var description: IntentDescription? = IntentDescription("Opens Pulse Strength on the Apple Watch for the next workout.")
    static var openAppWhenRun: Bool { true }
    static var isDiscoverable: Bool { false }

    init() {}

    func perform() async throws -> some IntentResult {
        WatchWidgetDispatch.openApp(.startNext)
        return .result()
    }
}
#endif
