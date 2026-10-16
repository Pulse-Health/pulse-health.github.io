#if os(iOS)
import SwiftUI
import UIKit
import PulseStrengthCore

/// The strength feature as one view: the Strength hub in a `NavigationStack`, the active workout as a full-screen
/// cover, the workout-in-progress bar above the bottom edge while a workout runs and its screen is minimised,
/// and the summary cover after a workout is finished.
///
/// * Starting a workout (`controller.startWorkout(template:)`) or resuming one presents the active workout.
/// * Minimising hides the cover; the bar then offers "Resume".
/// * Finishing hides the cover and, once it is gone, presents the summary (discarding presents nothing).
/// * `pulse-strength://workout` (the Live Activity's `widgetURL`) opens the active workout when one exists.
@MainActor
public struct PulseStrengthRootView: View {
    @ObservedObject private var environment: StrengthAppEnvironment
    @ObservedObject private var controller: WorkoutController

    @State private var showsActiveWorkout = false
    /// The finished workout waiting for the active-workout cover to go away before its summary is presented.
    @State private var pendingSummary: CompletedWorkout?
    @State private var summary: CompletedWorkout?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    public init(environment: StrengthAppEnvironment) {
        self._environment = ObservedObject(wrappedValue: environment)
        self._controller = ObservedObject(wrappedValue: environment.controller)
    }

    // MARK: Body

    public var body: some View {
        NavigationStack {
            StrengthHubView(
                environment: environment,
                onStart: { (template: WorkoutTemplate?) in
                    startWorkout(template)
                },
                onResume: {
                    resumeWorkout()
                }
            )
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            progressBarInset
                .animation(barAnimation, value: isBarVisible)
        }
        .fullScreenCover(isPresented: $showsActiveWorkout, onDismiss: {
            presentPendingSummary()
        }, content: {
            activeWorkoutCover
        })
        .fullScreenCover(item: $summary) { (workout: CompletedWorkout) in
            summaryCover(workout)
        }
        .sheet(isPresented: $environment.showsWeightEntry) {
            BodyWeightEntrySheet(store: environment.store)
        }
        .environment(\.watchStatus, environment.watchStatus)
        .environment(\.coachAudience, environment.audience)
        .tint(PulseTheme.green)
        // The whole app follows the user's text size up to accessibility3 (its screens scroll); the dense screens
        // (the active workout cover, the in-progress bar) narrow this range below.
        .dynamicTypeSize(PulseDynamicType.screenRange)
        .onOpenURL { (url: URL) in
            handleURL(url)
        }
        .task {
            await requestPermissions()
        }
        .task {
            // The launch itself: `onChange` below only sees the changes after it.
            environment.refreshOnActive()
        }
        .onChange(of: scenePhase) { _, phase in
            // A delivered reminder leaves the list of future ones, the clock or time zone may have changed, and Health may have new weights.
            if phase == .active {
                environment.refreshOnActive()
            }
        }
    }

    // MARK: Covers

    private var activeWorkoutCover: some View {
        ActiveWorkoutView(
            controller: environment.controller,
            store: environment.store,
            onMinimise: {
                showsActiveWorkout = false
            },
            onFinished: { (completed: CompletedWorkout?) in
                finishWorkout(completed)
            }
        )
        .environment(\.watchStatus, environment.watchStatus)
        .environment(\.coachAudience, environment.audience)
        .tint(PulseTheme.green)
        // The workout screen, its keypad and the rest dock cannot scroll as a page: their text stops growing at xxxLarge.
        .dynamicTypeSize(PulseDynamicType.activeWorkoutRange)
    }

    private func summaryCover(_ workout: CompletedWorkout) -> some View {
        WorkoutSummaryView(
            workout: workout,
            onDone: {
                summary = nil
            }
        )
        .tint(PulseTheme.green)
        .dynamicTypeSize(PulseDynamicType.screenRange)
    }

    // MARK: In-progress bar

    private var isBarVisible: Bool {
        controller.state != nil && !showsActiveWorkout
    }

    private var barAnimation: Animation? {
        reduceMotion ? nil : Animation.easeInOut(duration: 0.25)
    }

    @ViewBuilder
    private var progressBarInset: some View {
        if isBarVisible {
            TimelineView(.periodic(from: Date(), by: 1)) { context in
                progressBar(now: context.date)
            }
            // A floating bar above the hub: it keeps a fixed height, so its text stops growing at xxxLarge.
            .dynamicTypeSize(PulseDynamicType.activeWorkoutRange)
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private func progressBar(now: Date) -> some View {
        if let presentation = controller.presentation(now: now) {
            WorkoutInProgressBar(
                presentation: presentation,
                onResume: {
                    resumeWorkout()
                }
            )
            // The rest-over notification is not shown while the app is in the foreground, and the dock is not on
            // screen while the workout is minimised: this bar is then the only thing that can tell the user.
            .onChange(of: presentation.dock?.phase) { oldPhase, newPhase in
                restPhaseChanged(from: oldPhase, to: newPhase)
            }
        }
    }

    /// Haptic and announcement when the rest ends while the workout is minimised and the app is open
    /// (the active-workout screen does the same while it is showing; the bar and that screen are never both on screen).
    private func restPhaseChanged(
        from oldPhase: ActiveWorkoutPresentation.DockPhase?,
        to newPhase: ActiveWorkoutPresentation.DockPhase?
    ) {
        RestEndFeedback.playIfRestEnded(
            from: oldPhase,
            to: newPhase,
            scenePhase: scenePhase,
            alertsEnabled: controller.state?.settings.alertWhenRestEnds ?? true
        )
    }

    // MARK: Actions

    private func startWorkout(_ template: WorkoutTemplate?) {
        if controller.state == nil {
            controller.startWorkout(template: template)
            playStartHaptic()
        }
        presentActiveWorkout()
    }

    private func resumeWorkout() {
        presentActiveWorkout()
    }

    private func presentActiveWorkout() {
        if controller.state != nil {
            showsActiveWorkout = true
        }
    }

    /// `completed == nil` means the workout was discarded: no summary.
    private func finishWorkout(_ completed: CompletedWorkout?) {
        pendingSummary = completed
        showsActiveWorkout = false
    }

    /// Called once the active-workout cover is gone: a second cover cannot be presented while the first is leaving.
    private func presentPendingSummary() {
        if let pending = pendingSummary {
            pendingSummary = nil
            summary = pending
        }
    }

    private func handleURL(_ url: URL) {
        guard url.scheme?.lowercased() == StrengthConfig.urlScheme.lowercased() else { return }
        let host = url.host?.lowercased()
        if host == StrengthConfig.workoutURL.host?.lowercased() {
            presentActiveWorkout()
        } else if host == StrengthConfig.weightURL.host?.lowercased() {
            environment.requestWeightEntry()
        }
    }

    private func requestPermissions() async {
        guard environment.hasSystemServices else { return }
        await environment.services.requestPermissions()
    }

    private func playStartHaptic() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }
}
#endif
