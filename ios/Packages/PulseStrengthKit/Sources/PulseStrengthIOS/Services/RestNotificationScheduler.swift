#if os(iOS)
import Foundation
import UserNotifications
import PulseStrengthCore

/// Keeps notifications that arrive while the app is in the foreground out of sight: the rest dock and the
/// haptic already tell the user that the rest is over.
final class RestNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([])
    }
}

/// Hands a request to the notification center. Kept outside the main-actor class so the completion handler,
/// which the system calls on a background queue, is not main-actor isolated.
private func addNotificationRequest(_ request: UNNotificationRequest, to center: UNUserNotificationCenter) {
    center.add(request) { (error: Error?) in
        if let error = error {
            ServiceLog.error("Rest notification could not be scheduled: \(error.localizedDescription)")
        }
    }
}

/// Schedules a time-sensitive local notification for the end of the rest timer, so the user hears it with
/// the phone locked or the app in the background.
///
/// The notification (identifier `StrengthConfig.restNotificationID`) exists only while a rest is running, is not paused
/// and `settings.alertWhenRestEnds` is on. Every change that moves the rest end, pauses, skips or finishes the
/// workout removes the old request first, then adds the new one.
@MainActor
final class RestNotificationScheduler: WorkoutSideEffect {
    private struct Plan: Equatable {
        var endsAt: Date
        var body: String
    }

    private let center: UNUserNotificationCenter
    /// The center holds its delegate weakly, so the scheduler keeps it alive.
    private let delegate = RestNotificationDelegate()
    /// What is currently scheduled with the system; nil when nothing is.
    private var scheduled: Plan?

    init() {
        let center = UNUserNotificationCenter.current()
        self.center = center
        center.delegate = delegate
    }

    /// Asks for permission to show alerts and play the sound (the time-sensitive level needs no extra option).
    /// Returns whether the user allowed alerts (false when the prompt failed).
    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            ServiceLog.error("Notification authorization failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: WorkoutSideEffect

    func workoutStarted(_ state: WorkoutState) {
        if let plan = Self.plan(for: state, now: Date()) {
            schedule(plan)
        } else {
            clearSystemNotification()
        }
    }

    func workoutChanged(from old: WorkoutState, to new: WorkoutState, action: WorkoutAction, origin: ActionOrigin) {
        if case .updateHeartRate = action {
            return
        }
        guard let plan = Self.plan(for: new, now: Date()) else {
            if scheduled != nil {
                clearSystemNotification()
            }
            return
        }
        if plan != scheduled {
            schedule(plan)
        }
    }

    func workoutEnded(_ state: WorkoutState, completed: CompletedWorkout?) {
        clearSystemNotification()
    }

    // MARK: Scheduling

    /// Replaces any scheduled request with one that fires at `plan.endsAt`.
    private func schedule(_ plan: Plan) {
        clearSystemNotification()

        let interval = plan.endsAt.timeIntervalSinceNow
        guard interval >= 1 else { return }

        let content = UNMutableNotificationContent()
        content.title = "Rest over"
        content.body = plan.body
        content.sound = UNNotificationSound.default
        content.interruptionLevel = .timeSensitive

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(
            identifier: StrengthConfig.restNotificationID,
            content: content,
            trigger: trigger
        )
        addNotificationRequest(request, to: center)
        scheduled = plan
    }

    /// Removes the pending request and a notification that was already delivered.
    private func clearSystemNotification() {
        let identifiers = [StrengthConfig.restNotificationID]
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
        scheduled = nil
    }

    /// The notification the state calls for, or nil when there should be none.
    private static func plan(for state: WorkoutState, now: Date) -> Plan? {
        guard state.settings.alertWhenRestEnds, !state.isPaused else { return nil }
        guard let rest = state.rest, rest.frozenRemaining == nil else { return nil }
        guard rest.endsAt.timeIntervalSince(now) >= 1 else { return nil }

        let snapshot = SnapshotBuilder.make(from: state, now: now)
        let body: String
        if snapshot.targetSetID == nil {
            body = snapshot.nextSetText
        } else {
            body = "Next · " + snapshot.nextSetText
        }
        return Plan(endsAt: rest.endsAt, body: body)
    }
}
#endif
