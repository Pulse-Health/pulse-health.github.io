#if os(iOS)
import Foundation
import PulseStrengthCore

/// Applies what widgets, controls and the Action button left for the app in the App Group command inbox.
///
/// An App Intent that runs in the widget extension's process cannot touch the workout, so `WidgetIntentDispatch` appends the action (or a
/// deep link to open) to the inbox and posts the Darwin notification `StrengthConfig.commandInboxNotification`. This class drains the inbox
/// at launch (after the running workout was restored), when the app becomes active and on that notification, applies each action with
/// `controller.send` in the order it was issued and hands each deep link to `openLink`.
@MainActor
final class WidgetCommandDrain {
    private let controller: WorkoutController
    private let inbox: WidgetCommandInbox?
    private let openLink: @MainActor (StrengthDeepLink) -> Void
    private var isObserving = false

    init(controller: WorkoutController, inbox: WidgetCommandInbox?, openLink: @escaping @MainActor (StrengthDeepLink) -> Void) {
        self.controller = controller
        self.inbox = inbox
        self.openLink = openLink
    }

    deinit {
        if isObserving {
            CFNotificationCenterRemoveEveryObserver(CFNotificationCenterGetDarwinNotifyCenter(), Unmanaged.passUnretained(self).toOpaque())
        }
    }

    /// Starts listening for the extension's notification and drains what is already there.
    func start() {
        guard inbox != nil else { return }
        if !isObserving {
            isObserving = true
            let observer = Unmanaged.passUnretained(self).toOpaque()
            CFNotificationCenterAddObserver(
                CFNotificationCenterGetDarwinNotifyCenter(),
                observer,
                { (_: CFNotificationCenter?, observer: UnsafeMutableRawPointer?, _: CFNotificationName?, _: UnsafeRawPointer?, _: CFDictionary?) in
                    guard let observer else { return }
                    let drain = Unmanaged<WidgetCommandDrain>.fromOpaque(observer).takeUnretainedValue()
                    Task { @MainActor in drain.drain() }
                },
                StrengthConfig.commandInboxNotification as CFString,
                nil,
                .deliverImmediately
            )
        }
        drain()
    }

    /// Applies every pending command. Safe to call at any time.
    func drain() {
        guard let inbox, let commands = try? inbox.drain(), !commands.isEmpty else { return }
        for command in commands {
            if let action = command.action {
                controller.send(action, origin: command.origin)
            }
            if let link = command.link {
                openLink(link)
            }
        }
    }
}
#endif
