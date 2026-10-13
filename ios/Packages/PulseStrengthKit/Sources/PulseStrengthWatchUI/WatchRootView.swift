#if os(watchOS)
import SwiftUI
import PulseStrengthCore

// MARK: - Pages

/// The three vertical pages of a running workout.
enum WatchPage: Hashable {
    case log
    case rest
    case metrics
}

// MARK: - Root

/// The Watch app's only screen container.
///
/// * a finished workout (`environment.endedSummary`) shows `WatchSummaryView` until Done;
/// * without a workout it shows `WatchIdleView`;
/// * otherwise a vertical-page `TabView` with Log set, Rest and Metrics. The selection follows the rest timer (to Rest when a
///   rest starts, back to Log set when it ends); the user can swipe freely in between.
@MainActor
public struct WatchRootView: View {
    @ObservedObject private var environment: WatchEnvironment
    @ObservedObject private var controller: WorkoutController

    public init(environment: WatchEnvironment) {
        _environment = ObservedObject(wrappedValue: environment)
        _controller = ObservedObject(wrappedValue: environment.controller)
    }

    public var body: some View {
        content
    }

    @ViewBuilder
    private var content: some View {
        if let summary = environment.endedSummary {
            WatchSummaryView(summary: summary, onDone: { environment.dismissSummary() })
        } else if controller.state == nil {
            WatchIdleView(environment: environment)
        } else {
            WatchWorkoutPages(environment: environment, controller: controller)
        }
    }
}

// MARK: - Clock

/// Re-reads the snapshot once a second (the timeline pauses by itself when the screen is off and slows down when Always-On)
/// and hands it to the tabs.
@MainActor
private struct WatchWorkoutPages: View {
    @ObservedObject var environment: WatchEnvironment
    @ObservedObject var controller: WorkoutController

    /// Fixed for the lifetime of the workout so that re-rendering does not restart the timeline.
    @State private var clockStart: Date = Date()

    var body: some View {
        TimelineView(.periodic(from: clockStart, by: 1)) { context in
            tabs(at: context.date)
        }
    }

    @ViewBuilder
    private func tabs(at date: Date) -> some View {
        if let snapshot = controller.snapshot(now: date) {
            WatchWorkoutTabs(
                controller: controller,
                session: environment.session,
                snapshot: snapshot,
                date: date
            )
        } else {
            WatchIdleView(environment: environment)
        }
    }
}

// MARK: - Tabs

@MainActor
private struct WatchWorkoutTabs: View {
    let controller: WorkoutController
    let session: WatchWorkoutSession
    let snapshot: WorkoutSnapshot
    let date: Date

    @State private var selection: WatchPage = .log

    var body: some View {
        TabView(selection: $selection) {
            LogSetPage(
                controller: controller,
                snapshot: snapshot,
                date: date,
                isSelected: selection == .log
            )
            .tag(WatchPage.log)

            RestPage(
                controller: controller,
                snapshot: snapshot,
                date: date
            )
            .tag(WatchPage.rest)

            MetricsPage(
                session: session,
                snapshot: snapshot,
                date: date
            )
            .tag(WatchPage.metrics)
        }
        .tabViewStyle(.verticalPage)
        .onChange(of: snapshot.phase) { oldPhase, newPhase in
            phaseChanged(from: oldPhase, to: newPhase)
        }
        .onAppear {
            if snapshot.phase == .resting {
                selection = .rest
            }
        }
    }

    /// A rest starting moves to Rest; a rest ending (ran out, skipped, or the workout is complete) moves back to Log set.
    private func phaseChanged(from oldPhase: SnapshotPhase, to newPhase: SnapshotPhase) {
        if newPhase == .resting {
            if oldPhase != .resting { selection = .rest }
            return
        }
        guard oldPhase == .resting else { return }
        if newPhase == .restOver, selection == .rest, restAlertEnabled {
            // The rest ran out while the Rest page was showing: tap the wrist.
            WatchHaptics.notification()
        }
        selection = .log
    }

    /// "Alert when rest ends" is a workout setting (default on).
    private var restAlertEnabled: Bool {
        controller.state?.settings.alertWhenRestEnds ?? true
    }
}
#endif
