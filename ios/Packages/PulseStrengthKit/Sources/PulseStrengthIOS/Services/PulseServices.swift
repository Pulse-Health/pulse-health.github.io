#if os(iOS)
import Foundation
import HealthKit
import os
import PulseStrengthCore

/// Error logging shared by the service files (Live Activity, notifications, HealthKit, Watch).
enum ServiceLog {
    private static let logger = Logger(subsystem: "health.pulse.strength", category: "services")

    static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }
}

/// The platform services of the strength feature, created once next to the `WorkoutController`:
/// the Live Activity / Dynamic Island, the rest-over notification, the Health workout export and the
/// Apple Watch bridge. `init` registers the four effects with the controller and activates WatchConnectivity.
@MainActor
public final class PulseServices {
    /// Called on the main actor whenever `watchStatus` changes.
    public var onWatchStatusChange: ((WatchStatus) -> Void)?

    /// What the active-workout screen should tell the user about the Apple Watch.
    /// `.healthDenied` wins over `.notConnected`; `.connected` means nothing to report.
    public private(set) var watchStatus: WatchStatus = .connected

    private let liveActivity: LiveActivityManager
    private let restNotifications: RestNotificationScheduler
    private let healthWriter: HealthKitWorkoutWriter
    private let watchBridge: PhoneWatchBridge

    private var connectivityStatus: WatchStatus = .connected
    private var isHealthAccessDenied = false

    /// Creates the four effects, registers them with `controller` and activates the WatchConnectivity session.
    public init(controller: WorkoutController) {
        let healthStore: HKHealthStore? = HKHealthStore.isHealthDataAvailable() ? HKHealthStore() : nil
        self.liveActivity = LiveActivityManager()
        self.restNotifications = RestNotificationScheduler()
        self.healthWriter = HealthKitWorkoutWriter(healthStore: healthStore)
        self.watchBridge = PhoneWatchBridge(controller: controller, healthStore: healthStore)

        watchBridge.onStatusChange = { [weak self] (status: WatchStatus) in
            self?.connectivityChanged(status)
        }
        healthWriter.onAuthorizationDenied = { [weak self] (denied: Bool) in
            self?.healthAccessChanged(denied: denied)
        }

        controller.addEffect(liveActivity)
        controller.addEffect(restNotifications)
        controller.addEffect(healthWriter)
        controller.addEffect(watchBridge)

        watchBridge.activate()
        healthWriter.refreshAuthorizationStatus()
    }

    /// Asks for the notification permission (alert, sound; the time-sensitive level needs no extra option),
    /// then for the HealthKit permission. Safe to call repeatedly: the system only prompts once.
    public func requestPermissions() async {
        _ = await requestNotificationPermission()
        _ = await requestHealthPermission()
    }

    /// Asks for the notification permission only (the onboarding asks at its own step). Returns whether alerts are allowed.
    public func requestNotificationPermission() async -> Bool {
        await restNotifications.requestAuthorization()
    }

    /// Asks for the HealthKit permission only (the onboarding asks at its own step). Returns true when Health is available and
    /// sharing workouts was not denied.
    public func requestHealthPermission() async -> Bool {
        await healthWriter.requestAuthorization()
    }

    /// Returns when the Live Activity updates queued so far have been delivered to ActivityKit.
    /// The command-bus handler awaits it, so a Live Activity button's intent finishes only after its effect is on the Lock Screen.
    public func waitForPendingUpdates() async {
        await liveActivity.waitUntilIdle()
    }

    // MARK: Watch status

    private func connectivityChanged(_ status: WatchStatus) {
        connectivityStatus = status
        recomputeWatchStatus()
    }

    private func healthAccessChanged(denied: Bool) {
        isHealthAccessDenied = denied
        recomputeWatchStatus()
    }

    private func recomputeWatchStatus() {
        let combined: WatchStatus = isHealthAccessDenied ? .healthDenied : connectivityStatus
        guard combined != watchStatus else { return }
        watchStatus = combined
        onWatchStatusChange?(combined)
    }
}
#endif
