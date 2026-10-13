#if os(watchOS)
import Foundation
import Combine
import PulseStrengthCore

// MARK: - Ended-workout summary

/// What the Watch shows after the phone ended the workout, built from the last state the Watch knew.
///
/// All texts are display-ready: `durationText` "24:18" (or "1:02:03"), `volumeText` "1,980 kg", `setsText` "7/19 sets",
/// `averageHeartRateText` the average in bpm as a plain number ("128") or "–" when no heart rate was recorded.
public struct WatchEndedSummary: Equatable, Sendable {
    public var workoutName: String
    public var durationText: String
    public var volumeText: String
    public var setsText: String
    public var averageHeartRateText: String

    public init(
        workoutName: String,
        durationText: String,
        volumeText: String,
        setsText: String,
        averageHeartRateText: String
    ) {
        self.workoutName = workoutName
        self.durationText = durationText
        self.volumeText = volumeText
        self.setsText = setsText
        self.averageHeartRateText = averageHeartRateText
    }

    /// The summary of `state` as it was at `endedAt`: active time (pauses excluded), volume of the logged sets without
    /// warm-ups, "logged/total sets" and the average of the recorded heart-rate samples.
    public init(state: WorkoutState, endedAt: Date) {
        let totals = WatchWorkoutTotals(state)
        let heartRate: String = state.averageHeartRate.map { String($0) } ?? "–"
        self.init(
            workoutName: state.name,
            durationText: NumberText.clock(seconds: state.elapsedSeconds(now: endedAt)),
            volumeText: NumberText.thousands(totals.volumeKg) + " kg",
            setsText: "\(totals.loggedSets)/\(totals.totalSets) sets",
            averageHeartRateText: heartRate
        )
    }
}

/// Set and volume totals of a workout (the presenter's rules: warm-up sets and exercises without a weight are left out of the volume).
private struct WatchWorkoutTotals {
    var loggedSets = 0
    var totalSets = 0
    var volumeKg = 0.0

    init(_ state: WorkoutState) {
        for entry in state.exercises {
            totalSets += entry.sets.count
            for set in entry.sets where set.isDone {
                loggedSets += 1
                if set.type.countsTowardVolume && entry.exercise.tracksWeight {
                    volumeKg += set.weightKg * Double(set.reps)
                }
            }
        }
    }
}

// MARK: - Lifecycle effect

/// Forwards the controller's workout lifecycle to the environment: start the Health session when a workout begins on the
/// phone, end it (and build the summary) when the workout ends.
@MainActor
private final class WatchLifecycleEffect: WorkoutSideEffect {
    private weak var environment: WatchEnvironment?

    init(environment: WatchEnvironment) {
        self.environment = environment
    }

    func workoutStarted(_ state: WorkoutState) {
        environment?.handleWorkoutStarted(state)
    }

    func workoutEnded(_ state: WorkoutState, completed: CompletedWorkout?) {
        environment?.handleWorkoutEnded(state)
    }
}

// MARK: - Environment

/// Everything the Watch screens need, created once per process.
///
/// * `controller` is the Watch's mirror of the phone's workout (role `.mirror`, no persistence, an in-memory store).
///   Views read `controller.state` / `controller.snapshot(now:)` and dispatch with `controller.send(_, origin: .watch)`.
/// * `WatchConnectivityClient` (phone sync) and the lifecycle effect are registered with the controller. When an envelope for
///   a new workout arrives the Health `session` starts; when the workout ends the session ends and `endedSummary` is set.
/// * `isPhoneReachable` follows WatchConnectivity; `requestStateFromPhone()` asks the phone for the current state.
///
/// Use `WatchEnvironment.shared`. It is main-actor isolated, so touch it from main-actor code (the `App` struct's
/// initializer or `body`, `WatchAppDelegate`, a view). Creating it activates WatchConnectivity, so reference it early at launch.
@MainActor
public final class WatchEnvironment: ObservableObject {

    /// The Watch's mirror of the phone's workout.
    public let controller: WorkoutController

    /// The Health workout session (heart rate, saving the workout).
    public let session: WatchWorkoutSession

    /// True while the paired iPhone app is reachable.
    @Published public private(set) var isPhoneReachable: Bool = false

    /// Set when the phone ended a workout that had logged sets; cleared by `dismissSummary()` or when the next workout starts.
    @Published public private(set) var endedSummary: WatchEndedSummary? = nil

    /// The process-wide environment, created lazily on first use. Main-actor isolated: do not touch it from nonisolated code.
    @MainActor public static let shared = WatchEnvironment()

    private let connectivity: WatchConnectivityClient
    private var sessionObserver: AnyCancellable?
    /// When the phone sent the envelope that ended the workout (the summary's end time).
    private var pendingEndDate: Date?
    private var orphanCheck: Task<Void, Never>?

    /// Seconds a session that the phone launched may wait for the workout's state before it is stopped again.
    private let orphanTimeoutNanoseconds: UInt64 = 45_000_000_000

    public init() {
        let store = StrengthStore(persistence: nil)
        let controller = WorkoutController(store: store, persistence: nil, role: .mirror)
        let session = WatchWorkoutSession()
        let connectivity = WatchConnectivityClient(controller: controller)

        self.controller = controller
        self.session = session
        self.connectivity = connectivity

        // Heart rate: into the local mirror state and (throttled by the client) to the phone.
        session.onHeartRate = { [weak controller, weak connectivity] (bpm: Int) in
            controller?.send(.updateHeartRate(bpm), origin: .system)
            connectivity?.sendHeartRate(bpm)
        }
        // The phone must know whether the Watch records (it then skips its own Health workout).
        session.onRecordingChanged = { [weak connectivity] (isRecording: Bool) in
            connectivity?.sendWatchSession(isRecording: isRecording)
        }
        connectivity.onReachabilityChange = { [weak self] (reachable: Bool) in
            self?.isPhoneReachable = reachable
        }
        connectivity.onEnvelope = { [weak self] (envelope: SyncEnvelope) in
            self?.noteEnvelope(envelope)
        }

        // Views that observe the environment also refresh when the Health session changes (recording, access denied, heart rate).
        sessionObserver = session.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }

        controller.addEffect(connectivity)
        controller.addEffect(WatchLifecycleEffect(environment: self))
        connectivity.activate()
    }

    /// For the snapshot tests (and previews): wraps an existing `controller` and starts nothing. No WatchConnectivity session is
    /// activated and no effect is registered, so handing the controller a workout does not start a Health session. Reachability
    /// and the post-workout summary are set directly. Internal on purpose: it is not part of the public API.
    init(previewController controller: WorkoutController, isPhoneReachable: Bool = false, endedSummary: WatchEndedSummary? = nil) {
        let session = WatchWorkoutSession()
        self.controller = controller
        self.session = session
        self.connectivity = WatchConnectivityClient(controller: controller)
        self.isPhoneReachable = isPhoneReachable
        self.endedSummary = endedSummary
        sessionObserver = session.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    // MARK: Public API

    /// Hides the post-workout summary.
    public func dismissSummary() {
        endedSummary = nil
    }

    /// Asks the phone for the current workout state (also re-reads the last state the phone pushed).
    public func requestStateFromPhone() {
        connectivity.requestState()
    }

    // MARK: Phone launch

    /// Called by `WatchAppDelegate` when the phone launches the Watch app for a workout: starts the Health session right
    /// away (the workout's state follows over WatchConnectivity). If no workout shows up the session is stopped again.
    func startSessionForPhoneLaunch() {
        session.start(workoutStartDate: controller.state?.startedAt ?? Date())
        if controller.state == nil {
            scheduleOrphanCheck()
        }
        requestStateFromPhone()
    }

    private func scheduleOrphanCheck() {
        orphanCheck?.cancel()
        let timeout = orphanTimeoutNanoseconds
        orphanCheck = Task { [weak self] in
            try? await Task.sleep(nanoseconds: timeout)
            guard !Task.isCancelled, let self else { return }
            if self.controller.state == nil {
                self.session.end()
            }
            self.orphanCheck = nil
        }
    }

    // MARK: Workout lifecycle (called by WatchLifecycleEffect)

    fileprivate func handleWorkoutStarted(_ state: WorkoutState) {
        endedSummary = nil
        pendingEndDate = nil
        orphanCheck?.cancel()
        orphanCheck = nil
        session.start(workoutStartDate: state.startedAt)
    }

    fileprivate func handleWorkoutEnded(_ state: WorkoutState) {
        let endedAt = pendingEndDate ?? Date()
        pendingEndDate = nil
        orphanCheck?.cancel()
        orphanCheck = nil
        session.end()
        // A workout without a logged set was discarded: there is nothing to summarise.
        if WatchWorkoutTotals(state).loggedSets > 0 {
            endedSummary = WatchEndedSummary(state: state, endedAt: endedAt)
        }
    }

    /// Remembers when the phone ended the workout, so a late-delivered end message does not inflate the duration.
    private func noteEnvelope(_ envelope: SyncEnvelope) {
        // Only an envelope that will really end the current workout (same rule as the controller) counts.
        guard envelope.state == nil, let current = controller.state else { return }
        if let endedID = envelope.endedWorkoutID, endedID != current.id { return }
        pendingEndDate = min(envelope.sentAt, Date())
    }
}
#endif
