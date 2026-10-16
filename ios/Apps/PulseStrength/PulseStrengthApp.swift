// PulseStrengthApp.swift
//
// Entry point of the standalone iOS host app. It shows the Strength hub of PulseStrengthKit, behind the first-run onboarding
// (welcome, sign up / log in, profile, Apple Health, AI Coaching, notifications) and followed by the walkthrough; when the feature is
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
    /// Whether the onboarding runs (decided from the launch arguments, see `OnboardingLaunchMode`).
    private let onboardingMode: OnboardingLaunchMode
    private let onboardingServices: PulseOnboardingServices
    private let onboardingStore: OnboardingRecordStore

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let environment: StrengthAppEnvironment
        if arguments.contains(OnboardingLaunchMode.uiTestArgument) {
            // UI-test mode (Apps/PulseStrengthUITests): a fresh temporary store with the demo templates and history and
            // no live services (no Live Activity, Health, notification or Watch side effects, no permission prompts),
            // so every run starts from the same hub. `StrengthAppEnvironment.shared` is deliberately never touched.
            environment = StrengthAppEnvironment.preview(withActiveWorkout: false)
        } else {
            // Created here rather than lazily by the first view: when a Live Activity button (an App Intent) launches the
            // app in the background no scene is ever created, but the first access to `StrengthAppEnvironment.shared`
            // restores the running workout and installs the WorkoutCommandBus handler the intent is waiting for.
            environment = StrengthAppEnvironment.shared
        }
        self.environment = environment
        let mode = OnboardingLaunchMode.resolve(arguments: arguments)
        self.onboardingMode = mode

        let store: OnboardingRecordStore
        if environment.hasSystemServices {
            // The live services ask the system at their own steps of the onboarding.
            self.onboardingServices = PulseOnboardingServices(system: environment.services)
            store = OnboardingRecordStore()
        } else {
            // UI tests: nothing is asked of the system, the pauses are short, and the record of a completed onboarding is a
            // throwaway one, so a test neither depends on nor changes the real one.
            let suite = "health.pulse.strength.uitest"
            let defaults = UserDefaults(suiteName: suite) ?? UserDefaults.standard
            defaults.removePersistentDomain(forName: suite)
            self.onboardingServices = PulseOnboardingServices(system: nil, simulatedLatency: 0.15)
            store = OnboardingRecordStore(defaults: defaults)
        }
        self.onboardingStore = store

        // The walkthrough follows the onboarding. When the flow is not going to run (it was completed on an earlier launch, or it is
        // switched off), the launch stands in for "after onboarding": the tour opens once and never again by itself. It is set before
        // the first screen so that the permission prompts of the root view wait for it. When the flow runs, `OnboardingGate` says
        // when it is over (below). Previews and UI tests have no walkthrough memory, so this does nothing there.
        let runsOnboarding = mode == .always || (mode == .firstLaunch && store.load() == nil)
        if !runsOnboarding {
            environment.showWalkthroughAfterOnboarding()
        }
    }

    var body: some Scene {
        WindowGroup {
            if onboardingMode == .skip {
                PulseStrengthRootView(environment: environment)
            } else {
                OnboardingGate(
                    services: onboardingServices,
                    store: onboardingStore,
                    showsAlways: onboardingMode == .always,
                    onFinish: { (_: OnboardingRecord) in
                        environment.showWalkthroughAfterOnboarding()
                    },
                    content: { (record: OnboardingRecord?) in
                        // An account that went through the setup steps was already asked for Health and notifications there.
                        PulseStrengthRootView(
                            environment: environment,
                            requestsPermissionsAtLaunch: !(record?.askedForPermissions ?? false)
                        )
                    }
                )
            }
        }
    }
}
#endif
