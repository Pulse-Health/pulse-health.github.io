// WidgetIntentDispatch.swift
//
// How every App Intent of the app (Live Activity buttons, interactive widgets, controls, the Action button) hands a `WorkoutAction` to the
// workout. TARGET MEMBERSHIP: with the other files of Apps/Shared/Intents - the app, the widget extension and the Watch widget extension.
//
// The system decides in which process an intent runs: the app's (launched in the background if needed) for a `LiveActivityIntent`, possibly
// the widget extension's for a plain `AppIntent` used by a widget or control. Both must work:
//   * a process that owns the workout (the app: `WorkoutCommandBus` has a handler) applies the action at once;
//   * any other process (a widget extension) appends the action to the App Group command inbox and posts the Darwin notification
//     `StrengthConfig.commandInboxNotification`; the app drains the inbox at launch, when it becomes active and on that notification
//     (`WidgetCommandDrain` in PulseStrengthIOS), so the action is applied as soon as the app runs.
// A process without handler that is the app itself still starting up (a cold background launch by the intent) also uses the inbox: the app
// drains it when its environment is created.

#if os(iOS)
import Foundation
import PulseStrengthActivity
import PulseStrengthCore

enum WidgetIntentDispatch {
    /// Applies `action` now (app process) or leaves it for the app (extension process).
    static func send(_ action: WorkoutAction, origin: ActionOrigin = .liveActivity) async {
        if WorkoutCommandBus.shared.hasHandler {
            await WorkoutCommandBus.shared.perform(action, origin: origin)
            return
        }
        leave(PendingWidgetCommand(action: action, origin: origin))
    }

    /// Asks the app to open `link` (start the next workout, open the plate calculator ...). Used by intents with `openAppWhenRun = true`:
    /// the app comes to the foreground, drains the inbox and handles the link as if it had been opened by URL.
    static func openApp(_ link: StrengthDeepLink, origin: ActionOrigin = .liveActivity) {
        leave(PendingWidgetCommand(deepLink: link, origin: origin))
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
