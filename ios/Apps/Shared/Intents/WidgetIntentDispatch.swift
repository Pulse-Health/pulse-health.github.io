// WidgetIntentDispatch.swift
//
// How every App Intent of the app (Live Activity buttons, interactive widgets, controls, the Action button) hands a `WorkoutAction` or a deep link to
// the workout. TARGET MEMBERSHIP: with the other files of Apps/Shared/Intents - the app, the widget extension and the Watch widget extension.
//
// The system decides in which process an intent runs: the app's (launched in the background if needed) for a `LiveActivityIntent`, for an intent
// with `openAppWhenRun` and for an App Shortcut; possibly the widget extension's for a plain `AppIntent` that a widget or a control creates.
// Only the app owns the workout: `StrengthAppEnvironment` installs the `WorkoutCommandBus` handler when it is created, an extension never has one.
//
// `send(_:origin:)` - an action for the running workout. The cases, in the order `send` meets them:
//   1. App process, handler installed: the action is applied at once and `send` returns when the handler is done, that is after the Live Activity
//      update reached ActivityKit (an app that the intent launched in the background may be suspended right after `perform()` returns).
//   2. App process, no handler yet: a cold start, where the system may call `perform()` before `App.init` created the environment (which restores
//      the workout and installs the handler). `send` waits for the handler for up to 3 s, as long as `WorkoutCommandBus.perform` itself waits, and
//      then continues as in 1.
//   3. App process, still no handler after the wait (the environment could not start): the action goes to the inbox, as in 4.
//   4. Extension process (it never has a handler, so it does not wait): the action is appended to the App Group inbox and the Darwin notification
//      `StrengthConfig.commandInboxNotification` is posted. The app drains the inbox when its environment is created, when it becomes active and
//      on that notification, and applies the commands in order (`WidgetCommandDrain` in PulseStrengthIOS). A running app reacts at once; a
//      suspended app only when it runs again, and a command older than `WidgetCommandInbox.maximumAge` (10 minutes) is dropped. That is why the
//      controls use `LiveActivityIntent` for every intent that changes the workout (ControlIntents.swift): the system runs those in the app.
//
// `openApp(_:origin:)` - a deep link (start the next workout, plate calculator, the running workout): always the inbox, because only the app on screen
// can show the result. The intent has `openAppWhenRun = true`, so the system brings the app forward; it drains when it becomes active or on the
// notification and handles the link like an opened URL.
//
// Two things matter for the app's drain. It must register the Darwin observer BEFORE its first drain: a command appended between the two would
// otherwise wait for the next activation. And it must apply a drained action even when no scene exists yet (the background launch).

#if os(iOS)
import Foundation
import PulseStrengthActivity
import PulseStrengthCore

enum WidgetIntentDispatch {
    /// The longest a freshly launched app is given to install its handler: the wait `WorkoutCommandBus.perform` applies as well.
    private static let handlerWait: TimeInterval = 3
    /// Interval between two checks while waiting for the handler, in nanoseconds.
    private static let handlerPoll: UInt64 = 50_000_000

    /// Applies `action` now (app process) or leaves it for the app (extension process, or an app that never installed its handler).
    static func send(_ action: WorkoutAction, origin: ActionOrigin = .liveActivity) async {
        if await ownsWorkout() {
            await WorkoutCommandBus.shared.perform(action, origin: origin)
        } else {
            leave(PendingWidgetCommand(action: action, origin: origin))
        }
    }

    /// Asks the app to open `link` (start the next workout, open the plate calculator ...). Used by intents with `openAppWhenRun = true`:
    /// the app comes to the foreground, drains the inbox and handles the link as if it had been opened by URL.
    static func openApp(_ link: StrengthDeepLink, origin: ActionOrigin = .liveActivity) {
        leave(PendingWidgetCommand(deepLink: link, origin: origin))
    }

    // MARK: Private

    /// True when this process applies workout actions itself: the app, once its environment installed the bus handler. A freshly launched app is
    /// given `handlerWait` to get there; an extension never is, so it does not wait.
    private static func ownsWorkout() async -> Bool {
        let bus = WorkoutCommandBus.shared
        if bus.hasHandler { return true }
        guard runsInApp else { return false }
        let deadline = Date().addingTimeInterval(handlerWait)
        while Date() < deadline {
            do {
                try await Task.sleep(nanoseconds: handlerPoll)
            } catch {
                break
            }
            if bus.hasHandler { return true }
        }
        return bus.hasHandler
    }

    /// The main bundle of the app is an .app, the one of a widget extension an .appex.
    private static var runsInApp: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
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
#endif
