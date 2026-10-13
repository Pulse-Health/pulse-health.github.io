// PulseStrengthApp.swift
//
// Entry point of the standalone iOS host app. It shows the Strength hub of PulseStrengthKit; when the feature is
// integrated into the Pulse app, only `PulseStrengthRootView(environment:)` moves over (see README.md).

#if os(iOS)
import SwiftUI
import PulseStrengthCore
import PulseStrengthIOS

@main
@MainActor
struct PulseStrengthApp: App {
    /// The shared environment (store, workout controller, Live Activity / Watch / notification / HealthKit services).
    private let environment: StrengthAppEnvironment

    init() {
        if ProcessInfo.processInfo.arguments.contains("-PulseUITest") {
            // UI-test mode (Apps/PulseStrengthUITests): a fresh temporary store with the demo templates and history and
            // no live services (no Live Activity, Health, notification or Watch side effects, no permission prompts),
            // so every run starts from the same hub. `StrengthAppEnvironment.shared` is deliberately never touched.
            self.environment = StrengthAppEnvironment.preview(withActiveWorkout: false)
        } else {
            // Created here rather than lazily by the first view: when a Live Activity button (an App Intent) launches the
            // app in the background no scene is ever created, but the first access to `StrengthAppEnvironment.shared`
            // restores the running workout and installs the WorkoutCommandBus handler the intent is waiting for.
            self.environment = StrengthAppEnvironment.shared
        }
    }

    var body: some Scene {
        WindowGroup {
            PulseStrengthRootView(environment: environment)
        }
    }
}
#endif
