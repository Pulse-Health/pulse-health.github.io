#if os(iOS)
import Foundation
import ActivityKit
import PulseStrengthCore
import PulseStrengthActivity

/// Keeps the Lock Screen Live Activity and the Dynamic Island in step with the workout.
///
/// * `workoutStarted`: requests the activity (or re-attaches to the one that already shows this workout after a
///   relaunch, and ends activities of other workouts).
/// * `workoutChanged`: updates the content with a fresh `WorkoutSnapshot`; heart-rate-only changes are throttled to
///   about one per 10 seconds and an update that would show nothing new is skipped.
/// * `workoutEnded`: ends the activity at once.
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

    /// The workout the manager created or attached an activity for. When it is set and no live activity is left,
    /// the user dismissed the activity and it is not brought back.
    private var attachedWorkoutID: UUID?
    /// The last snapshot handed to the update queue, and when.
    private var lastQueuedSnapshot: WorkoutSnapshot?
    private var lastQueuedAt: Date?
    /// The most recently queued ActivityKit task; the next task waits for it.
    private var tail: Task<Void, Never>?

    init() {}

    // MARK: WorkoutSideEffect

    func workoutStarted(_ state: WorkoutState) {
        let now = Date()
        let snapshot = SnapshotBuilder.make(from: state, now: now, locale: .current)
        lastQueuedSnapshot = snapshot
        lastQueuedAt = now
        let content = Self.makeContent(state: state, snapshot: snapshot)
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
        let snapshot = SnapshotBuilder.make(from: new, now: now, locale: .current)
        if let previous = lastQueuedSnapshot, Self.showsSameContent(previous, snapshot) {
            return
        }
        lastQueuedSnapshot = snapshot
        lastQueuedAt = now
        let content = Self.makeContent(state: new, snapshot: snapshot)
        let workoutID = new.id
        let workoutName = new.name
        enqueue { [weak self] in
            guard let self = self else { return }
            await self.deliver(workoutID: workoutID, workoutName: workoutName, content: content, isStart: false)
        }
    }

    func workoutEnded(_ state: WorkoutState, completed: CompletedWorkout?) {
        lastQueuedSnapshot = nil
        lastQueuedAt = nil
        let finalSnapshot = Self.fittingActivity(SnapshotBuilder.make(from: state, now: Date(), locale: .current))
        let finalContent = ActivityContent(state: finalSnapshot, staleDate: nil)
        enqueue { [weak self] in
            guard let self = self else { return }
            await self.endAll(finalContent: finalContent)
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
            let attributes = WorkoutActivityAttributes(workoutID: workoutID, workoutName: Self.clamped(workoutName))
            _ = try WorkoutActivity.request(attributes: attributes, content: content, pushType: nil)
            attachedWorkoutID = workoutID
        } catch {
            // Typically the app is not in the foreground (a restore in the background); the next update tries again.
            lastQueuedSnapshot = nil
            ServiceLog.error("Live Activity could not be started: \(error.localizedDescription)")
        }
    }

    private func endAll(finalContent: ActivityContent<WorkoutSnapshot>) async {
        attachedWorkoutID = nil
        for candidate in WorkoutActivity.activities {
            await candidate.end(finalContent, dismissalPolicy: .immediate)
        }
    }

    /// Ends every activity that does not show `workoutID`, and every duplicate of the one that does.
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

    private static func makeContent(state: WorkoutState, snapshot: WorkoutSnapshot) -> ActivityContent<WorkoutSnapshot> {
        ActivityContent(state: fittingActivity(snapshot), staleDate: staleDate(for: state))
    }

    // MARK: Size limit

    /// ActivityKit accepts at most 4 KB for the attributes and the content state together. Everything in the snapshot is short
    /// except the workout and exercise names, which come from text fields without a limit, so these are bounded.
    /// 60 scalars are at most 240 bytes (UTF-8) per name, four names in all (the workout name is in the attributes as well).
    private static let maximumNameScalars = 60

    /// `text` itself when it has at most `maximumNameScalars` Unicode scalars, else its start (whole characters, so no
    /// emoji or accent is cut in half; a single character of more scalars than the limit is cut) followed by "…".
    private static func clamped(_ text: String) -> String {
        let limit = maximumNameScalars
        if text.unicodeScalars.dropFirst(limit).isEmpty {
            return text
        }
        var result = ""
        var used = 0
        for character in text {
            let size = character.unicodeScalars.count
            if used + size > limit {
                break
            }
            result.append(character)
            used += size
        }
        if result.isEmpty {
            result = String(text.unicodeScalars.prefix(limit))
        }
        return result + "…"
    }

    /// The snapshot as it goes to ActivityKit: `snapshot` with the names bounded. The queued snapshot that is compared
    /// with the next one stays the full one.
    private static func fittingActivity(_ snapshot: WorkoutSnapshot) -> WorkoutSnapshot {
        var fitting = snapshot
        fitting.workoutName = clamped(snapshot.workoutName)
        fitting.exerciseName = clamped(snapshot.exerciseName)
        fitting.nextExerciseName = snapshot.nextExerciseName.map { Self.clamped($0) }
        return fitting
    }
}
#endif
