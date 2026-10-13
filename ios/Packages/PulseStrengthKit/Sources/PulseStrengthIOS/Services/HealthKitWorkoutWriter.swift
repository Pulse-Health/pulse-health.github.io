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

private func hkFinishWorkout(of builder: HKWorkoutBuilder) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        builder.finishWorkout { (workout: HKWorkout?, error: Error?) in
            if let error = error {
                continuation.resume(throwing: error)
            } else if workout != nil {
                continuation.resume()
            } else {
                continuation.resume(throwing: HealthWriteError.rejected)
            }
        }
    }
}

/// Saves a finished workout to Apple Health as a traditional strength-training `HKWorkout` (indoor).
///
/// Only the phone writes, and only when no Apple Watch recorded the workout (`state.usedWatch == false`);
/// with the Watch recording, the Watch saves it. Without HealthKit on the device every call is a silent no-op.
@MainActor
final class HealthKitWorkoutWriter: WorkoutSideEffect {
    /// Reports whether sharing workouts is denied: true when it is (or became) denied, false when it is not (any more).
    /// Called on the main actor, only when the value changes.
    var onAuthorizationDenied: (@MainActor (Bool) -> Void)?

    /// nil when HealthKit is not available on this device.
    private let healthStore: HKHealthStore?
    private var reportedDenied = false

    init(healthStore: HKHealthStore?) {
        self.healthStore = healthStore
    }

    // MARK: Authorization

    /// Asks to share workouts and to read heart rate and active energy, then reports a denied share status.
    func requestAuthorization() async {
        guard let store = healthStore else { return }
        var readTypes = Set<HKObjectType>()
        if let heartRate = HKObjectType.quantityType(forIdentifier: .heartRate) {
            readTypes.insert(heartRate)
        }
        if let activeEnergy = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) {
            readTypes.insert(activeEnergy)
        }
        let shareTypes: Set<HKSampleType> = [HKObjectType.workoutType()]
        do {
            try await hkRequestAuthorization(store: store, share: shareTypes, read: readTypes)
        } catch {
            ServiceLog.error("Health authorization failed: \(error.localizedDescription)")
        }
        refreshAuthorizationStatus()
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
        let start = state.startedAt
        // HealthKit rejects a workout that ends before it starts.
        let end = max(completed.finishedAt, start.addingTimeInterval(1))
        Task { [weak self] in
            guard let self = self else { return }
            await self.write(store: store, workoutID: workoutID, start: start, end: end)
        }
    }

    // MARK: Writing

    private func write(store: HKHealthStore, workoutID: UUID, start: Date, end: Date) async {
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
            try await hkEndCollection(of: builder, at: end)
            try await hkFinishWorkout(of: builder)
        } catch {
            builder.discardWorkout()
            ServiceLog.error("Health workout could not be saved: \(error.localizedDescription)")
        }
    }
}
#endif
