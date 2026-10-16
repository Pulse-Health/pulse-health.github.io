#if os(iOS)
import Foundation
import ActivityKit
import UIKit
import PulseStrengthCore
import PulseStrengthActivity

/// Keeps the Lock Screen Live Activity and the Dynamic Island in step with the workout.
///
/// * `workoutStarted`: requests the activity (or re-attaches to the one that already shows this workout after a
///   relaunch, and ends activities of other workouts, a finish card of the last workout included), and ends the countdown of a
///   planned session (`PlannedSessionManager`).
/// * `workoutChanged`: updates the content with a fresh `WorkoutSnapshot`; heart-rate-only changes are throttled to
///   about one per 10 seconds and an update that would show nothing new is skipped. When the change logged a personal record
///   (`SnapshotBuilder.prMoment`) the content carries the record banner for four seconds, and a task sends the same content
///   without it when the time is up.
/// * `workoutEnded`: a finished workout ends the activity with a final content that carries the finish card and keeps it on the
///   Lock Screen for two hours; a discarded one ends it at once.
///
/// Every ActivityKit call is `async`; they run in tasks that are chained one after the other, so updates reach
/// ActivityKit in the order they were made and the main actor is never blocked.
@MainActor
final class LiveActivityManager: WorkoutSideEffect {
    private typealias WorkoutActivity = Activity<WorkoutActivityAttributes>

    /// Heart-rate-only updates are sent at most this often. The workout engine already spaces heart-rate changes by
    /// 10 seconds, so a small tolerance keeps its sample at exactly 10 s from being dropped by clock jitter.
    private static let heartRateInterval: TimeInterval = 10
    private static let heartRateTolerance: TimeInterval = 0.5
    /// How long the record banner stays (widgets/SPEC.md LA-01).
    private static let momentLifetime: TimeInterval = 4
    /// How long the card of a finished workout stays on the Lock Screen (the system allows up to four hours).
    private static let finishCardLifetime: TimeInterval = 2 * 60 * 60

    /// The workout the manager created or attached an activity for. When it is set and no live activity is left,
    /// the user dismissed the activity and it is not brought back.
    private var attachedWorkoutID: UUID?
    /// The last snapshot handed to the update queue, when, and with which stale date.
    private var lastQueuedSnapshot: WorkoutSnapshot?
    private var lastQueuedAt: Date?
    private var lastQueuedStaleDate: Date?
    /// The most recently queued ActivityKit task; the next task waits for it.
    private var tail: Task<Void, Never>?
    /// The record banner the content carries now (nil when none), the task that clears it at `expiresAt`, and the background task
    /// that keeps the app alive until then (an app a Live Activity button launched in the background may otherwise be suspended
    /// before the banner is cleared).
    private var activeMoment: PRMoment?
    private var momentClearing: Task<Void, Never>?
    private var momentBackgroundTask: UIBackgroundTaskIdentifier = .invalid

    init() {
        // The planned-session manager installs the handler of its Live Activity buttons when it is first used. The services are
        // created at launch, so touching it here lets a Snooze pressed on the Lock Screen find it even in a background launch.
        _ = PlannedSessionManager.shared
    }

    // MARK: WorkoutSideEffect

    func workoutStarted(_ state: WorkoutState) {
        let now = Date()
        PlannedSessionManager.shared.workoutDidStart()
        dropMoment()
        let snapshot = SnapshotBuilder.make(from: state, now: now)
        let staleDate = Self.staleDate(for: state)
        remember(snapshot, at: now, staleDate: staleDate)
        let content = Self.makeContent(snapshot: snapshot, staleDate: staleDate)
        let workoutID = state.id
        let workoutName = state.name
        enqueue { [weak self] in
            guard let self = self else { return }
            await self.deliver(workoutID: workoutID, workoutName: workoutName, content: content, isStart: true)
        }
    }

    func workoutChanged(from old: WorkoutState, to new: WorkoutState, action: WorkoutAction, origin: ActionOrigin) {
        let now = Date()
        if case .updateHeartRate = action, isInsideHeartRateInterval(now) {
            return
        }
        let fresh = SnapshotBuilder.prMoment(from: old, to: new, now: now, lifetime: Self.momentLifetime)
        var snapshot = SnapshotBuilder.make(from: new, now: now)
        snapshot.moment = fresh ?? carriedMoment(at: now)
        if let previous = lastQueuedSnapshot, Self.showsSameContent(previous, snapshot) {
            return
        }
        if let fresh = fresh {
            activeMoment = fresh
            scheduleMomentClearing(fresh, workoutID: new.id)
        } else if snapshot.moment == nil {
            dropMoment()
        }
        let staleDate = Self.staleDate(for: new)
        remember(snapshot, at: now, staleDate: staleDate)
        let content = Self.makeContent(snapshot: snapshot, staleDate: staleDate)
        let workoutID = new.id
        let workoutName = new.name
        enqueue { [weak self] in
            guard let self = self else { return }
            await self.deliver(workoutID: workoutID, workoutName: workoutName, content: content, isStart: false)
        }
    }

    /// A finished workout (`completed != nil`) ends the activity with the finish card as its final content and `.after(now + 2 h)`
    /// as the dismissal, so the card stays on the Lock Screen; a discard ends it at once.
    ///
    /// "Saved to Health" on the card is `state.usedWatch`: with the Watch recording, the Watch saves the workout to Health. A phone
    /// that writes the workout itself (`HealthKitWorkoutWriter`, only without the Watch and with the permission) is not claimed here:
    /// the write is asynchronous and may still fail, and the card must not say it unless it is true.
    func workoutEnded(_ state: WorkoutState, completed: CompletedWorkout?) {
        dropMoment()
        lastQueuedSnapshot = nil
        lastQueuedAt = nil
        lastQueuedStaleDate = nil
        let now = Date()
        var finalSnapshot = SnapshotBuilder.make(from: state, now: now)
        let dismissal: ActivityUIDismissalPolicy
        if let completed = completed {
            finalSnapshot.moment = nil
            finalSnapshot.superset = nil
            finalSnapshot.plates = nil
            finalSnapshot.coachTip = nil
            finalSnapshot.finish = SnapshotBuilder.finishBrief(from: completed, savedToHealth: state.usedWatch)
            dismissal = .after(now.addingTimeInterval(Self.finishCardLifetime))
        } else {
            dismissal = .immediate
        }
        let finalContent = Self.makeContent(snapshot: finalSnapshot, staleDate: nil)
        enqueue { [weak self] in
            guard let self = self else { return }
            await self.endAll(finalContent: finalContent, dismissalPolicy: dismissal)
        }
    }

    // MARK: Queue

    /// Runs `operation` after every earlier operation has finished.
    private func enqueue(_ operation: @escaping @MainActor () async -> Void) {
        let previous = tail
        tail = Task { @MainActor in
            await previous?.value
            await operation()
        }
    }

    /// Returns when every ActivityKit operation queued so far has finished.
    ///
    /// The command-bus handler awaits this after it applied a Live Activity button, so the intent's `perform()` returns
    /// only once the new content was handed to ActivityKit (a process that the intent launched in the background may be
    /// suspended as soon as `perform()` has returned, before a fire-and-forget update would have run).
    func waitUntilIdle() async {
        await tail?.value
    }

    // MARK: Record banner

    /// The banner still on screen at `now` (a record logged a moment ago and not cleared yet), so an update that has nothing to do with
    /// it, such as a rest adjustment, does not take it away early.
    private func carriedMoment(at now: Date) -> PRMoment? {
        guard let moment = activeMoment, moment.expiresAt > now else { return nil }
        return moment
    }

    /// Sends the content without `moment` at `moment.expiresAt`. The wait is not part of the update queue, which must not hold up
    /// the updates in between; only the clearing update itself is queued.
    private func scheduleMomentClearing(_ moment: PRMoment, workoutID: UUID) {
        cancelMomentClearing()
        beginMomentBackgroundTask()
        momentClearing = Task { @MainActor [weak self] in
            let delay = moment.expiresAt.timeIntervalSinceNow
            if delay.isFinite, delay > 0 {
                do {
                    try await Task.sleep(nanoseconds: UInt64(min(delay, 60) * 1_000_000_000))
                } catch {
                    return
                }
            }
            self?.clearMoment(moment, workoutID: workoutID)
        }
    }

    /// Queues the clearing update, unless a newer update has replaced the banner (it owns the clearing task and the background task
    /// now) or the workout is over.
    private func clearMoment(_ moment: PRMoment, workoutID: UUID) {
        momentClearing = nil
        guard activeMoment == moment else { return }
        guard var snapshot = lastQueuedSnapshot, snapshot.workoutID == workoutID else {
            dropMoment()
            return
        }
        activeMoment = nil
        snapshot.moment = nil
        lastQueuedSnapshot = snapshot
        let content = Self.makeContent(snapshot: snapshot, staleDate: lastQueuedStaleDate)
        let workoutName = snapshot.workoutName
        enqueue { [weak self] in
            guard let self = self else { return }
            await self.deliver(workoutID: workoutID, workoutName: workoutName, content: content, isStart: false)
            self.endMomentBackgroundTask()
        }
    }

    /// Forgets the banner and its clearing task (a new workout, the end of the workout, or a banner that ran out).
    private func dropMoment() {
        activeMoment = nil
        cancelMomentClearing()
    }

    private func cancelMomentClearing() {
        momentClearing?.cancel()
        momentClearing = nil
        endMomentBackgroundTask()
    }

    private func beginMomentBackgroundTask() {
        momentBackgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Clear record banner") { [weak self] in
            self?.endMomentBackgroundTask()
        }
    }

    private func endMomentBackgroundTask() {
        guard momentBackgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(momentBackgroundTask)
        momentBackgroundTask = .invalid
    }

    // MARK: ActivityKit calls (run inside the queue)

    private func deliver(
        workoutID: UUID,
        workoutName: String,
        content: ActivityContent<WorkoutSnapshot>,
        isStart: Bool
    ) async {
        if isStart {
            attachedWorkoutID = nil
            await endActivitiesExcept(workoutID: workoutID)
        }

        if let live = liveActivity(for: workoutID) {
            attachedWorkoutID = workoutID
            await live.update(content)
            return
        }

        // The activity of this workout existed and is gone: the user swiped it away, so do not bring it back.
        if attachedWorkoutID == workoutID {
            return
        }

        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            lastQueuedSnapshot = nil
            return
        }

        do {
            let attributes = WorkoutActivityAttributes(workoutID: workoutID, workoutName: ActivityContentFitting.clamped(workoutName))
            _ = try WorkoutActivity.request(attributes: attributes, content: content, pushType: nil)
            attachedWorkoutID = workoutID
        } catch {
            // Typically the app is not in the foreground (a restore in the background); the next update tries again.
            lastQueuedSnapshot = nil
            ServiceLog.error("Live Activity could not be started: \(error.localizedDescription)")
        }
    }

    private func endAll(finalContent: ActivityContent<WorkoutSnapshot>, dismissalPolicy: ActivityUIDismissalPolicy) async {
        attachedWorkoutID = nil
        for candidate in WorkoutActivity.activities {
            await candidate.end(finalContent, dismissalPolicy: dismissalPolicy)
        }
    }

    /// Ends every activity that does not show `workoutID`, and every duplicate of the one that does. The finish card of the previous
    /// workout is one of them: it is dismissed when the next workout starts.
    private func endActivitiesExcept(workoutID: UUID) async {
        var keptOne = false
        for candidate in WorkoutActivity.activities {
            if !keptOne, candidate.attributes.workoutID == workoutID, Self.isLive(candidate) {
                keptOne = true
                continue
            }
            await candidate.end(nil, dismissalPolicy: .immediate)
        }
    }

    private func liveActivity(for workoutID: UUID) -> WorkoutActivity? {
        for candidate in WorkoutActivity.activities {
            if candidate.attributes.workoutID == workoutID, Self.isLive(candidate) {
                return candidate
            }
        }
        return nil
    }

    // MARK: Helpers

    private func remember(_ snapshot: WorkoutSnapshot, at now: Date, staleDate: Date?) {
        lastQueuedSnapshot = snapshot
        lastQueuedAt = now
        lastQueuedStaleDate = staleDate
    }

    private func isInsideHeartRateInterval(_ now: Date) -> Bool {
        guard let last = lastQueuedAt else { return false }
        let elapsed = now.timeIntervalSince(last)
        return elapsed >= 0 && elapsed < Self.heartRateInterval - Self.heartRateTolerance
    }

    private static func isLive(_ activity: WorkoutActivity) -> Bool {
        let activityState = activity.activityState
        return activityState == .active || activityState == .stale
    }

    /// True when `new` would look the same as `old` on screen (only the sync revision differs).
    private static func showsSameContent(_ old: WorkoutSnapshot, _ new: WorkoutSnapshot) -> Bool {
        var comparable = old
        comparable.revision = new.revision
        return comparable == new
    }

    /// While an unpaused rest runs the content goes stale when the rest ends, so the views can switch to "Go".
    private static func staleDate(for state: WorkoutState) -> Date? {
        guard !state.isPaused, let rest = state.rest, rest.frozenRemaining == nil else { return nil }
        return rest.endsAt
    }

    /// The snapshot as ActivityKit gets it: texts and lists bounded to the 4 KB limit (`ActivityContentFitting`). The snapshot
    /// the manager keeps and compares with the next one stays the full one.
    private static func makeContent(snapshot: WorkoutSnapshot, staleDate: Date?) -> ActivityContent<WorkoutSnapshot> {
        ActivityContent(state: ActivityContentFitting.fitting(snapshot), staleDate: staleDate)
    }
}
#endif
