#if os(iOS)
import Foundation
import HealthKit
import PulseStrengthCore

/// Exchanges the user's body weight with Apple Health, when the user turned "Sync with Apple Health" on
/// (`WeighInPreferences.syncWithHealth`):
///
/// * **Saving**: a weigh-in entered in the app is saved to Health as a body-mass sample whose `HKMetadataKeyExternalUUID` is the
///   entry's id; deleting the entry deletes that sample (Health only lets an app delete the samples it saved itself).
/// * **Reading**: the newest body-mass samples of Health (a smart scale, the Health app, other apps) are added to the app's
///   weigh-ins as read-only entries (`StrengthData.mergeHealthBodyWeights`). The samples the app saved itself carry its entry id and
///   are not read back. A weight that arrives through Health also counts as a weigh-in for the reminder.
///
/// Health access is requested when the user turns the sync on, not at launch. HealthKit never says whether READ access was refused
/// (a refused read looks like an empty one); only the share status is visible, and the Settings footer reports that.
/// Without HealthKit on the device every call is a silent no-op.
@MainActor
final class BodyWeightHealthSync {
    /// How many of the newest Health samples one read looks at.
    private static let readLimit = 400

    /// nil when HealthKit is not available on this device.
    private let healthStore: HKHealthStore?
    private let store: StrengthStore
    private var isReading = false

    init(healthStore: HKHealthStore?, store: StrengthStore) {
        self.healthStore = healthStore
        self.store = store
    }

    /// The sync of the running app: its own `HKHealthStore` when this device has Health.
    static func make(store: StrengthStore) -> BodyWeightHealthSync {
        BodyWeightHealthSync(healthStore: HKHealthStore.isHealthDataAvailable() ? HKHealthStore() : nil, store: store)
    }

    /// False on a device without Health (the switch in Settings is then disabled).
    var isAvailable: Bool {
        healthStore != nil && bodyMass != nil
    }

    private var bodyMass: HKQuantityType? {
        HKQuantityType.quantityType(forIdentifier: .bodyMass)
    }

    // MARK: Authorization

    /// Asks to save and read body weight; true when saving is allowed afterwards.
    func requestAuthorization() async -> Bool {
        guard let healthStore = healthStore, let type = bodyMass else { return false }
        let share: Set<HKSampleType> = [type]
        let read: Set<HKObjectType> = [type]
        do {
            try await healthStore.requestAuthorization(toShare: share, read: read)
        } catch {
            ServiceLog.error("Health body weight authorization failed: \(error.localizedDescription)")
        }
        return canSave
    }

    /// True when the user allowed the app to save body weight to Health.
    var canSave: Bool {
        guard let healthStore = healthStore, let type = bodyMass else { return false }
        return healthStore.authorizationStatus(for: type) == .sharingAuthorized
    }

    // MARK: Reading

    /// Adds the body weights of Health that the app does not have yet. No-op while the sync is off or a read is running.
    func readFromHealth() async {
        guard store.weighIn.syncWithHealth, !isReading, let healthStore = healthStore, let type = bodyMass else { return }
        isReading = true
        defer { isReading = false }

        let descriptor = HKSampleQueryDescriptor<HKQuantitySample>(
            predicates: [HKSamplePredicate<HKQuantitySample>.quantitySample(type: type)],
            sortDescriptors: [SortDescriptor<HKQuantitySample>(\.endDate, order: .reverse)],
            limit: Self.readLimit
        )
        do {
            let samples = try await descriptor.result(for: healthStore)
            let kilogram = HKUnit.gramUnit(with: .kilo)
            let converted = samples.map { (sample: HKQuantitySample) -> HealthBodyWeightSample in
                let external = (sample.metadata?[HKMetadataKeyExternalUUID] as? String).flatMap { UUID(uuidString: $0) }
                return HealthBodyWeightSample(
                    sampleID: sample.uuid,
                    externalID: external,
                    date: sample.endDate,
                    kg: sample.quantity.doubleValue(for: kilogram)
                )
            }
            store.importHealthBodyWeights(converted)
        } catch {
            ServiceLog.error("Health body weight could not be read: \(error.localizedDescription)")
        }
    }

    // MARK: Writing

    /// Saves a weigh-in entered in the app to Health. No-op while the sync is off or saving is not allowed.
    func save(_ entry: BodyWeightEntry) {
        guard store.weighIn.syncWithHealth, canSave, let healthStore = healthStore, let type = bodyMass else { return }
        let quantity = HKQuantity(unit: HKUnit.gramUnit(with: .kilo), doubleValue: entry.kg)
        let sample = HKQuantitySample(
            type: type,
            quantity: quantity,
            start: entry.date,
            end: entry.date,
            metadata: [HKMetadataKeyExternalUUID: entry.id.uuidString]
        )
        Task {
            do {
                try await healthStore.save(sample)
            } catch {
                ServiceLog.error("Health body weight could not be saved: \(error.localizedDescription)")
            }
        }
    }

    /// Deletes the Health sample that was saved for an entry that was deleted in the app. No-op while the sync is off.
    func remove(_ entry: BodyWeightEntry) {
        guard store.weighIn.syncWithHealth, canSave, let healthStore = healthStore, let type = bodyMass else { return }
        let predicate = HKQuery.predicateForObjects(
            withMetadataKey: HKMetadataKeyExternalUUID,
            allowedValues: [entry.id.uuidString]
        )
        Task {
            do {
                _ = try await healthStore.deleteObjects(of: type, predicate: predicate)
            } catch {
                ServiceLog.error("Health body weight could not be deleted: \(error.localizedDescription)")
            }
        }
    }
}
#endif
