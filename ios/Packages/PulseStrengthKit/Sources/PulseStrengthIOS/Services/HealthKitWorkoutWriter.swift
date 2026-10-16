#if os(iOS)
import Foundation
import HealthKit
import PulseStrengthCore

/// Why a Health write failed when HealthKit itself reported no error.
private enum HealthWriteError: Error {
    case rejected
}

// The HealthKit completion handlers below are called on background queues. They live in plain functions
// (not in the main-actor class) so the closures are not main-actor isolated.

private func hkRequestAuthorization(
    store: HKHealthStore,
    share: Set<HKSampleType>,
    read: Set<HKObjectType>
) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        store.requestAuthorization(toShare: share, read: read) { (_: Bool, error: Error?) in
            if let error = error {
                continuation.resume(throwing: error)
            } else {
                continuation.resume()
            }
        }
    }
}

private func hkBeginCollection(of builder: HKWorkoutBuilder, at start: Date) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        builder.beginCollection(withStart: start) { (success: Bool, error: Error?) in
            if let error = error {
                continuation.resume(throwing: error)
            } else if success {
                continuation.resume()
            } else {
                continuation.resume(throwing: HealthWriteError.rejected)
            }
        }
    }
}

private func hkAddMetadata(_ metadata: [String: Any], to builder: HKWorkoutBuilder) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        builder.addMetadata(metadata) { (success: Bool, error: Error?) in
            if let error = error {
                continuation.resume(throwing: error)
            } else if success {
                continuation.resume()
            } else {
                continuation.resume(throwing: HealthWriteError.rejected)
            }
        }
    }
}

private func hkAddWorkoutEvents(_ events: [HKWorkoutEvent], to builder: HKWorkoutBuilder) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        builder.addWorkoutEvents(events) { (success: Bool, error: Error?) in
            if let error = error {
                continuation.resume(throwing: error)
            } else if success {
                continuation.resume()
            } else {
                continuation.resume(throwing: HealthWriteError.rejected)
            }
        }
    }
}

private func hkEndCollection(of builder: HKWorkoutBuilder, at end: Date) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        builder.endCollection(withEnd: end) { (success: Bool, error: Error?) in
            if let error = error {
                continuation.resume(throwing: error)
            } else if success {
                continuation.resume()
            } else {
                continuation.resume(throwing: HealthWriteError.rejected)
            }
        }
    }
}

/// Finishes the workout. A completion without an error is a success even when the `HKWorkout` is nil: HealthKit documents
/// that result as "finishing the workout succeeded but the workout sample is not available because the device is locked".
/// Treating it as a failure would discard the builder of a saved workout and, without a record that it was saved, write it
/// to Health a second time.
private func hkFinishWorkout(of builder: HKWorkoutBuilder) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        builder.finishWorkout { (_: HKWorkout?, error: Error?) in
            if let error = error {
                continuation.resume(throwing: error)
            } else {
                continuation.resume()
            }
        }
    }
}

/// Saves a finished workout to Apple Health as a traditional strength-training `HKWorkout` (indoor).
///
/// Only the phone writes, and only when no Apple Watch recorded the workout (`state.usedWatch == false`);
/// with the Watch recording, the Watch saves it. Without HealthKit on the device every call is a silent no-op.
///
/// A workout is saved to Health at most once. The core can finish the same workout twice (when the history file could not
/// be written the workout is kept and restored on the next launch, and finishing it again records it by its id), and
/// HealthKit does not merge two workouts that carry the same `HKMetadataKeyExternalUUID`. So the writer keeps the ids of the
/// workouts it has saved (the last 64, in `UserDefaults`, so they survive a relaunch) and skips a workout it already saved.
///
/// The phone does not know when a pause happened, only how long the pauses took in total, so a workout that was paused gets one
/// pause / resume event pair of that total length: Health's duration is the app's duration without the pauses, as on the Watch.
@MainActor
final class HealthKitWorkoutWriter: WorkoutSideEffect {
    /// `UserDefaults` key of the saved workout ids (an array of `UUID` strings, oldest first).
    private static let savedIDsKey = "health.pulse.strength.healthSavedWorkoutIDs"
    /// How many saved workout ids are remembered. A workout can only be finished again right after a failed history write,
    /// so a short memory is enough.
    private static let savedIDsCapacity = 64

    /// Reports whether sharing workouts is denied: true when it is (or became) denied, false when it is not (any more).
    /// Called on the main actor, only when the value changes.
    var onAuthorizationDenied: (@MainActor (Bool) -> Void)?

    /// nil when HealthKit is not available on this device.
    private let healthStore: HKHealthStore?
    /// Holds the ids of the workouts already saved to Health.
    private let defaults: UserDefaults
    /// Workouts whose Health write is running right now (a second `workoutEnded` for one of them is ignored).
    private var writing = Set<UUID>()
    private var reportedDenied = false

    init(healthStore: HKHealthStore?, defaults: UserDefaults = .standard) {
        self.healthStore = healthStore
        self.defaults = defaults
    }

    // MARK: Authorization

    /// Asks to share workouts and to read heart rate and active energy, then reports a denied share status.
    /// Returns true when Health is available, the request went through and sharing workouts was allowed. (HealthKit never says
    /// whether reading was allowed, so a user who allowed only the sharing counts as connected too.)
    @discardableResult
    func requestAuthorization() async -> Bool {
        guard let store = healthStore else { return false }
        var readTypes = Set<HKObjectType>()
        if let heartRate = HKObjectType.quantityType(forIdentifier: .heartRate) {
            readTypes.insert(heartRate)
        }
        if let activeEnergy = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) {
            readTypes.insert(activeEnergy)
        }
        let shareTypes: Set<HKSampleType> = [HKObjectType.workoutType()]
        var requested = true
        do {
            try await hkRequestAuthorization(store: store, share: shareTypes, read: readTypes)
        } catch {
            ServiceLog.error("Health authorization failed: \(error.localizedDescription)")
            requested = false
        }
        refreshAuthorizationStatus()
        return requested && store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized
    }

    /// Reads the current share status of workouts and tells `onAuthorizationDenied` when it changed.
    /// (HealthKit hides whether read access was denied; a denied share is the only visible signal.)
    func refreshAuthorizationStatus() {
        guard let store = healthStore else { return }
        let denied = store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingDenied
        guard denied != reportedDenied else { return }
        reportedDenied = denied
        onAuthorizationDenied?(denied)
    }

    // MARK: WorkoutSideEffect

    func workoutStarted(_ state: WorkoutState) {
        // The user may have changed the permission in Settings since the last workout.
        refreshAuthorizationStatus()
    }

    func workoutEnded(_ state: WorkoutState, completed: CompletedWorkout?) {
        guard let completed = completed, !state.usedWatch, let store = healthStore else { return }
        let workoutID = completed.id
        // Finished a second time (see the class comment): Health already has it, or is being given it right now.
        guard !hasSaved(workoutID), !writing.contains(workoutID) else { return }
        writing.insert(workoutID)
        let start = state.startedAt
        // HealthKit rejects a workout that ends before it starts.
        let end = max(completed.finishedAt, start.addingTimeInterval(1))
        let activeSeconds = completed.durationSeconds
        Task { [weak self] in
            guard let self = self else { return }
            await self.write(store: store, workoutID: workoutID, start: start, end: end, activeSeconds: activeSeconds)
        }
    }

    // MARK: Writing

    /// `activeSeconds` is the workout's duration without the pauses (`CompletedWorkout.durationSeconds`).
    private func write(store: HKHealthStore, workoutID: UUID, start: Date, end: Date, activeSeconds: Int) async {
        defer { writing.remove(workoutID) }
        refreshAuthorizationStatus()
        guard store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized else { return }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor

        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: HKDevice.local())
        do {
            try await hkBeginCollection(of: builder, at: start)
            let metadata: [String: Any] = [
                HKMetadataKeyExternalUUID: workoutID.uuidString,
                HKMetadataKeyIndoorWorkout: true
            ]
            do {
                try await hkAddMetadata(metadata, to: builder)
            } catch {
                ServiceLog.error("Health workout metadata could not be added: \(error.localizedDescription)")
            }
            if let pauseEvents = Self.pauseEvents(start: start, end: end, activeSeconds: activeSeconds) {
                do {
                    try await hkAddWorkoutEvents(pauseEvents, to: builder)
                } catch {
                    // Without the events Health shows the whole span, pauses included; the workout is still saved.
                    ServiceLog.error("Health workout pause could not be added: \(error.localizedDescription)")
                }
            }
            try await hkEndCollection(of: builder, at: end)
            try await hkFinishWorkout(of: builder)
            markSaved(workoutID)
        } catch {
            builder.discardWorkout()
            ServiceLog.error("Health workout could not be saved: \(error.localizedDescription)")
        }
    }

    /// A pause and a resume event that leave `activeSeconds` of `start ... end` active, so that Health's duration of the
    /// workout equals the app's (`HKWorkout.duration` is the time between start and end that is not paused). nil when the
    /// workout was not paused (less than a second of difference) or has no active time to put the pause around.
    ///
    /// The phone does not record when the pauses happened (the builder gets no samples), only their total matters here:
    /// one pause of the total length, in the middle of the active time, strictly between `start` and `end`.
    private static func pauseEvents(start: Date, end: Date, activeSeconds: Int) -> [HKWorkoutEvent]? {
        let span = end.timeIntervalSince(start)
        let paused = span - Double(activeSeconds)
        guard paused >= 1, activeSeconds >= 1 else { return nil }
        let pauseAt = start.addingTimeInterval(Double(activeSeconds) / 2)
        let resumeAt = min(pauseAt.addingTimeInterval(paused), end)
        return [
            HKWorkoutEvent(type: .pause, dateInterval: DateInterval(start: pauseAt, duration: 0), metadata: nil),
            HKWorkoutEvent(type: .resume, dateInterval: DateInterval(start: resumeAt, duration: 0), metadata: nil)
        ]
    }

    // MARK: Saved workout ids

    private func savedIDs() -> [String] {
        defaults.stringArray(forKey: Self.savedIDsKey) ?? []
    }

    private func hasSaved(_ workoutID: UUID) -> Bool {
        savedIDs().contains(workoutID.uuidString)
    }

    /// Remembers that `workoutID` is in Health; the oldest ids beyond the capacity are forgotten.
    private func markSaved(_ workoutID: UUID) {
        var ids = savedIDs().filter { $0 != workoutID.uuidString }
        ids.append(workoutID.uuidString)
        if ids.count > Self.savedIDsCapacity {
            ids.removeFirst(ids.count - Self.savedIDsCapacity)
        }
        defaults.set(ids, forKey: Self.savedIDsKey)
    }
}
#endif
