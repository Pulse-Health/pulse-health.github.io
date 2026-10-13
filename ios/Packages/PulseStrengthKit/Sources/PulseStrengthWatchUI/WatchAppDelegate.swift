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

    /// Asks the phone for the current workout state whenever the app comes to the foreground.
    public func applicationDidBecomeActive() {
        Task { @MainActor in
            WatchEnvironment.shared.requestStateFromPhone()
        }
    }

    /// The phone asked this app to start a workout (`HKHealthStore.startWatchApp(with:)`): start the session.
    /// The configuration is always a strength workout, which the session builds itself.
    public func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        Task { @MainActor in
            WatchEnvironment.shared.startSessionForPhoneLaunch()
        }
    }
}
#endif
