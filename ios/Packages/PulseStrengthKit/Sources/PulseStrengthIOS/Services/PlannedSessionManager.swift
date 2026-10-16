#if os(iOS)
import Foundation
import ActivityKit
import UIKit
import UserNotifications
import PulseStrengthCore
import PulseStrengthActivity

/// Hands a request to the notification center. Kept outside the main-actor class so the completion handler,
/// which the system calls on a background queue, is not main-actor isolated.
private func addPlannedSessionRequest(_ request: UNNotificationRequest, to center: UNUserNotificationCenter) {
    center.add(request) { (error: Error?) in
        if let error = error {
            ServiceLog.error("Planned session notification could not be scheduled: \(error.localizedDescription)")
        }
    }
}

/// LA-06 Pre-workout countdown: plans a strength session for later and shows its countdown ("Planned 18:00", the first set, "Start now"
/// and "Snooze") on the Lock Screen and in the Dynamic Island (`PlannedSessionActivity` in the widget extension).
///
/// The entry point of the app is `PlannedSessionManager.shared.schedule(template:startsAt:)`, called by the screen on which the user
/// plans a session (the Strength hub); the Shortcuts action `PlanSessionIntent` reaches the same code through `PlannedSessionBus`.
/// * `schedule` stores the plan (UserDefaults, so a relaunch finds it), adds a local notification at the start time and, when the
///   app is in the foreground and the start is at most seven hours away, requests the activity. ActivityKit starts an activity only
///   from the foreground, so a plan made in the background, or more than seven hours ahead (an activity ends after eight), gets its
///   countdown the next time the app becomes active (`refresh`).
/// * `snooze` moves the start by ten minutes from now or from the planned time, whichever is later; the activity, the notification and
///   the stored plan follow.
/// * The plan ends when a workout starts (`workoutDidStart`, called by `LiveActivityManager`), when `cancel()` is called, or two hours
///   after its start time. If the user swipes the countdown away it stays gone: the plan and its notification remain.
///
/// The activity's `staleDate` is the start time, so the card changes to "Time to train" by itself when it passes.
@MainActor
public final class PlannedSessionManager {
    public static let shared = PlannedSessionManager()

    /// How long after its start time an unused plan lasts.
    public static let lingerInterval: TimeInterval = 2 * 60 * 60
    /// The countdown is requested at most this long before the start: an activity ends after eight hours.
    static let maximumLead: TimeInterval = 7 * 60 * 60

    private typealias PlannedActivity = Activity<PlannedSessionAttributes>

    private static let storageKey = "health.pulse.strength.planned-session"
    private static let notificationID = "health.pulse.strength.planned-session"

    /// What is kept between launches: the plan and whether its countdown was started (so a swiped-away countdown is not brought back).
    private struct Stored: Codable {
        var plan: PlannedSessionPlan
        var countdownStarted: Bool
    }

    /// The plan, nil when none is made.
    public private(set) var plan: PlannedSessionPlan?

    private let defaults: UserDefaults
    private var countdownStarted = false
    /// The most recently queued ActivityKit task; the next task waits for it.
    private var tail: Task<Void, Never>?
    /// Ends the plan two hours after its start.
    private var expiry: Task<Void, Never>?
    /// The manager lives as long as the app, so the observer is never removed; the token is kept because the call returns it.
    private var activationObserver: NSObjectProtocol?

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let stored = try? JSONDecoder().decode(Stored.self, from: data) {
            plan = stored.plan
            countdownStarted = stored.countdownStarted
        }
        PlannedSessionBus.shared.install { [weak self] command in
            await self?.handle(command)
        }
        activationObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
        refresh()
    }

    // MARK: Entry points

    /// Plans `template` for `startsAt`, replacing an earlier plan. Returns false (and plans nothing) when the time is not in the future.
    @discardableResult
    public func schedule(template: WorkoutTemplate, startsAt: Date) -> Bool {
        schedule(PlannedSessionPlan(template: template, startsAt: startsAt))
    }

    /// The same with the parts spelled out; `firstExercise` (usually `template.entries.first`) gives the "Squat first: 4 × 5 at 100 kg" line.
    @discardableResult
    public func schedule(templateID: UUID, name: String, firstExercise: TemplateEntry?, startsAt: Date) -> Bool {
        schedule(PlannedSessionPlan(templateID: templateID, name: name, firstExercise: firstExercise, startsAt: startsAt))
    }

    /// Moves the start by `minutes` from now or from the planned time, whichever is later.
    public func snooze(minutes: Int = PlannedSessionAttributes.snoozeMinutes) {
        guard let current = plan, minutes > 0 else { return }
        let start = max(current.startsAt, Date()).addingTimeInterval(Double(minutes) * 60)
        plan = current.moved(to: start)
        planChanged()
    }

    /// Drops the plan: ends the countdown and removes the notification.
    public func cancel() {
        plan = nil
        countdownStarted = false
        save()
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.notificationID])
        expiry?.cancel()
        expiry = nil
        enqueue { [weak self] in
            await self?.endActivities()
        }
    }

    /// A workout started or was restored: the plan has served its purpose.
    func workoutDidStart() {
        guard plan != nil else { return }
        cancel()
    }

    /// Brings the countdown in line with the stored plan; the app calls it when it becomes active.
    func refresh() {
        guard let current = plan else { return }
        if Date() >= current.startsAt.addingTimeInterval(Self.lingerInterval) {
            cancel()
            return
        }
        scheduleExpiry()
        requestActivity()
    }

    /// What a button of the countdown, or the Shortcuts action, asked for (`PlannedSessionBus`).
    func handle(_ command: PlannedSessionCommand) {
        switch command {
        case .schedule(let newPlan):
            schedule(newPlan)
        case .snooze(let minutes):
            snooze(minutes: minutes)
        case .cancel:
            cancel()
        }
    }

    // MARK: Planning

    @discardableResult
    private func schedule(_ newPlan: PlannedSessionPlan) -> Bool {
        guard newPlan.startsAt > Date() else { return false }
        plan = newPlan
        countdownStarted = false
        planChanged()
        return true
    }

    /// The plan or its start time changed: store it, move the notification and the expiry, update or request the countdown.
    private func planChanged() {
        save()
        scheduleNotification()
        scheduleExpiry()
        requestActivity()
    }

    private func save() {
        guard let plan = plan else {
            defaults.removeObject(forKey: Self.storageKey)
            return
        }
        if let data = try? JSONEncoder().encode(Stored(plan: plan, countdownStarted: countdownStarted)) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }

    // MARK: Notification

    /// A local notification at the start time, "Time to train", for when the phone is locked and the countdown is not on screen.
    private func scheduleNotification() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.notificationID])
        guard let current = plan else { return }
        let interval = current.startsAt.timeIntervalSinceNow
        guard interval >= 1 else { return }

        let content = UNMutableNotificationContent()
        content.title = "Time to train"
        content.body = current.state.firstLine.map { current.state.templateName + " \u{00B7} " + $0 } ?? current.state.templateName
        content.sound = UNNotificationSound.default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(identifier: Self.notificationID, content: content, trigger: trigger)
        addPlannedSessionRequest(request, to: center)
    }

    // MARK: Expiry

    /// Ends the plan two hours after its start, as long as the app runs; `refresh` does it at the next launch or activation otherwise.
    private func scheduleExpiry() {
        expiry?.cancel()
        expiry = nil
        guard let current = plan else { return }
        let end = current.startsAt.addingTimeInterval(Self.lingerInterval)
        expiry = Task { @MainActor [weak self] in
            let delay = end.timeIntervalSinceNow
            if delay.isFinite, delay > 0 {
                do {
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                } catch {
                    return
                }
            }
            guard let manager = self, let current = manager.plan,
                  Date() >= current.startsAt.addingTimeInterval(Self.lingerInterval) else { return }
            manager.cancel()
        }
    }

    // MARK: ActivityKit (run inside the queue)

    /// Runs `operation` after every earlier operation has finished.
    private func enqueue(_ operation: @escaping @MainActor () async -> Void) {
        let previous = tail
        tail = Task { @MainActor in
            await previous?.value
            await operation()
        }
    }

    /// Starts the countdown, or updates the one that runs, for the current plan.
    private func requestActivity() {
        guard let current = plan else { return }
        let content = ActivityContent(state: current.state, staleDate: current.startsAt)
        enqueue { [weak self] in
            await self?.present(current, content: content)
        }
    }

    private func present(_ current: PlannedSessionPlan, content: ActivityContent<PlannedSessionAttributes.ContentState>) async {
        var kept = false
        for candidate in PlannedActivity.activities {
            if !kept, candidate.attributes.templateID == current.templateID, Self.isLive(candidate) {
                kept = true
                await candidate.update(content)
            } else {
                await candidate.end(nil, dismissalPolicy: .immediate)
            }
        }
        if kept { return }

        // The countdown of this plan was started and is gone: the user swiped it away, so it stays gone.
        if countdownStarted { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled,
              current.startsAt.timeIntervalSinceNow <= Self.maximumLead,
              UIApplication.shared.applicationState == .active else { return }
        do {
            let attributes = PlannedSessionAttributes(templateID: current.templateID)
            _ = try PlannedActivity.request(attributes: attributes, content: content, pushType: nil)
            countdownStarted = true
            save()
        } catch {
            // The app was not ready to start an activity; `refresh` tries again when it becomes active.
            ServiceLog.error("Planned session countdown could not be started: \(error.localizedDescription)")
        }
    }

    private func endActivities() async {
        for candidate in PlannedActivity.activities {
            await candidate.end(nil, dismissalPolicy: .immediate)
        }
    }

    private static func isLive(_ activity: PlannedActivity) -> Bool {
        let activityState = activity.activityState
        return activityState == .active || activityState == .stale
    }
}
#endif
