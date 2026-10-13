#if os(watchOS)
import SwiftUI
import Combine
import PulseStrengthCore

// MARK: - Pages

/// The three vertical pages of a running workout.
enum WatchPage: Hashable {
    case log
    case rest
    case metrics
}

// MARK: - Rest alert

/// Taps the wrist when the rest timer runs out.
///
/// The cue is driven by the workout state, not by the screen: it is scheduled for the rest's end time (`RestState.endsAt`) as soon
/// as a state with a running rest exists, whichever page is showing and whether or not the view hierarchy is being redrawn (the
/// one-second `TimelineView` slows down in the Always-On state and stops with the screen off, which is exactly when a user who
/// rests with the wrist down needs the cue). The workout's Health session keeps the app running, which is what allows the haptic in
/// the background. Any change of the rest (adjusted, skipped, paused, resumed, another workout, the alert switched off) replaces
/// the scheduled cue; a state that merely carries a new heart rate does not.
///
/// `WatchRootView` owns one instance for the life of the app.
@MainActor
final class WatchRestAlert: ObservableObject {
    /// What a scheduled cue is for.
    private struct Due: Equatable {
        let workoutID: UUID
        let endsAt: Date
    }

    /// A rest that ended no longer ago than this still gets its cue (a state that arrives just after the end, or a rest cut short
    /// with -15, which ends it at once). One that ended earlier is old news (the state of a relaunched app) and stays silent.
    private static let lateTolerance: TimeInterval = 3
    /// End times closer than this are the same rest: the phone's copy of an end time can differ from the Watch's own by under a
    /// second (its dates travel without fractions), and one rest must not buzz twice.
    private static let sameRestTolerance: TimeInterval = 2
    /// The longest single sleep, so the nanosecond count below can never overflow whatever date a state carries.
    private static let longestSleep: TimeInterval = 3_600

    private var subscription: AnyCancellable?
    private var waiting: Task<Void, Never>?
    private var scheduled: Due?
    private var lastAlertedEnd: Date?

    init(controller: WorkoutController) {
        // `$state` publishes the new value before it is stored, so the value it delivers is the one to look at.
        subscription = controller.$state.sink { [weak self] (state: WorkoutState?) in
            self?.stateChanged(state)
        }
    }

    /// The cue a state asks for: a running (not paused) rest of a workout that has "alert when rest ends" on.
    private static func due(for state: WorkoutState?) -> Due? {
        guard let state = state, state.settings.alertWhenRestEnds, !state.isPaused,
              let rest = state.rest, rest.frozenRemaining == nil,
              rest.endsAt.timeIntervalSinceNow.isFinite
        else { return nil }
        return Due(workoutID: state.id, endsAt: rest.endsAt)
    }

    private func stateChanged(_ state: WorkoutState?) {
        let next = WatchRestAlert.due(for: state)
        guard next != scheduled else { return }
        waiting?.cancel()
        waiting = nil
        scheduled = next
        guard let due = next, due.endsAt.timeIntervalSinceNow > -WatchRestAlert.lateTolerance else { return }
        waiting = Task { @MainActor [weak self] in
            // Sleep to the end time, then look at the wall clock again: a sleep that was cut short or that did not count a pause
            // of the device must not make the cue early or lost.
            while !Task.isCancelled {
                let remaining = due.endsAt.timeIntervalSinceNow
                if remaining <= 0 { break }
                let seconds = min(remaining, WatchRestAlert.longestSleep)
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            }
            guard !Task.isCancelled else { return }
            self?.restEnded(due)
        }
    }

    private func restEnded(_ due: Due) {
        guard scheduled == due else { return }
        if let last = lastAlertedEnd, abs(due.endsAt.timeIntervalSince(last)) < WatchRestAlert.sameRestTolerance { return }
        lastAlertedEnd = due.endsAt
        WatchHaptics.notification()
    }
}

// MARK: - Root

/// The Watch app's only screen container.
///
/// * a finished workout (`environment.endedSummary`) shows `WatchSummaryView` until Done;
/// * without a workout it shows `WatchIdleView`;
/// * otherwise a vertical-page `TabView` with Log set, Rest and Metrics. The selection follows the rest timer (to Rest when a
///   rest starts, back to Log set when it ends); the user can swipe freely in between.
///
/// It also owns the `WatchRestAlert` that taps the wrist when a rest runs out.
@MainActor
public struct WatchRootView: View {
    @ObservedObject private var environment: WatchEnvironment
    @ObservedObject private var controller: WorkoutController
    /// Held for its side effect (the scheduled wrist haptic); the views never read it.
    @StateObject private var restAlert: WatchRestAlert

    public init(environment: WatchEnvironment) {
        _environment = ObservedObject(wrappedValue: environment)
        _controller = ObservedObject(wrappedValue: environment.controller)
        _restAlert = StateObject(wrappedValue: WatchRestAlert(controller: environment.controller))
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

    /// What tells "a set was logged and it started a new rest" from every other change: the logged-set count together with the
    /// start time of the rest that is running.
    private struct RestStart: Equatable {
        let loggedSets: Int
        let startedAt: Date?
    }

    private var restStart: RestStart {
        RestStart(
            loggedSets: snapshot.loggedSets,
            startedAt: snapshot.phase == .resting ? snapshot.restStartedAt : nil
        )
    }

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
        .onChange(of: restStart) { oldValue, newValue in
            restRestarted(from: oldValue, to: newValue)
        }
        .onAppear {
            if snapshot.phase == .resting {
                selection = .rest
            }
        }
    }

    /// A rest starting moves to Rest; a rest ending (ran out, skipped, or the workout is complete) moves back to Log set.
    ///
    /// The wrist haptic for a rest that ran out is not played here: this runs on the timeline tick, which is slow or absent with
    /// the wrist down, and the page showing is irrelevant to it. `WatchRestAlert` plays it from the rest's end time.
    private func phaseChanged(from oldPhase: SnapshotPhase, to newPhase: SnapshotPhase) {
        if newPhase == .resting {
            if oldPhase != .resting { selection = .rest }
            return
        }
        guard oldPhase == .resting else { return }
        selection = .log
    }

    /// Logging a set while the previous rest is still running replaces that rest by a new one without the phase ever leaving
    /// `.resting`, so `phaseChanged` does not see it: bring the Rest page forward then too. A set that starts no rest (the first
    /// half of a superset pair) leaves the running rest as it was and the page where the user put it.
    private func restRestarted(from oldValue: RestStart, to newValue: RestStart) {
        guard newValue.loggedSets > oldValue.loggedSets,
              let startedAt = newValue.startedAt,
              startedAt != oldValue.startedAt
        else { return }
        selection = .rest
    }
}
#endif
