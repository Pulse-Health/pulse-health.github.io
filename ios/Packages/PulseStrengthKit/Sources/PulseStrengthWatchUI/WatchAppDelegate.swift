#if os(watchOS)
import Foundation
import WatchKit
import HealthKit

/// The Watch app's delegate. Install it in the `App` with `@WKApplicationDelegateAdaptor(WatchAppDelegate.self)`.
///
/// The phone launches the Watch app for a workout with `HKHealthStore.startWatchApp(with:)`; the system then calls
/// `handle(_:)`, which starts the Health workout session of the shared environment so heart rate is measured from the first set.
public final class WatchAppDelegate: NSObject, WKApplicationDelegate {

    public override init() {
        super.init()
    }

    /// Creates the shared environment at launch, which activates WatchConnectivity as early as possible.
    public func applicationDidFinishLaunching() {
        Task { @MainActor in
            _ = WatchEnvironment.shared
        }
    }

    /// Asks the phone for the current workout state whenever the app comes to the foreground, and makes sure the Health session
    /// records the workout the Watch shows (a start that failed in the background is tried again here, where it can succeed).
    public func applicationDidBecomeActive() {
        Task { @MainActor in
            let environment = WatchEnvironment.shared
            environment.requestStateFromPhone()
            environment.reconcileSessionWithWorkout()
        }
    }

    /// The phone asked this app to start a workout (`HKHealthStore.startWatchApp(with:)`): start the session.
    /// The configuration is always a strength workout, which the session builds itself.
    public func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        Task { @MainActor in
            WatchEnvironment.shared.startSessionForPhoneLaunch()
        }
    }

    /// The system relaunched the app after it crashed (or was terminated) in the middle of a workout and kept the Health session
    /// alive: take that session over instead of leaving it without an owner, and ask the phone for the workout again.
    public func handleActiveWorkoutRecovery() {
        Task { @MainActor in
            WatchEnvironment.shared.recoverWorkoutSession()
        }
    }
}
#endif
