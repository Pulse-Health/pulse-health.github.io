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
///   a new workout arrives the Health `session` starts; when the workout ends the session ends (saved to Health when the phone
///   finished the workout, thrown away when the phone discarded it) and `endedSummary` is set for a finished one. The session
///   follows the workout shown: another workout replacing it ends the old session, a pause on the phone pauses it, an app that
///   becomes active retries a start that failed, and a session that survived a crash is taken over again.
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
    private var stateObserver: AnyCancellable?
    /// The workout the Health session records; nil when it was started for a phone launch and no workout has claimed it yet (or
    /// there is no session).
    private var sessionWorkoutID: UUID?
    /// Whether that workout had a logged set the last time the Watch saw it (decides whether a session that lost its workout
    /// without a word is saved).
    private var sessionWorkoutHasLoggedSets = false
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
        // `$state` publishes the new value before it is stored, so the value it delivers is the one to look at.
        stateObserver = controller.$state.sink { [weak self] (state: WorkoutState?) in
            self?.stateChanged(state)
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
            scheduleOrphanCheck(save: false)
        }
        requestStateFromPhone()
    }

    /// Called by `WatchAppDelegate` when the system relaunches the app after it crashed or was terminated during a workout: takes
    /// over the Health session the system kept alive and asks the phone for the workout. If no workout shows up the session is
    /// stopped again, but saved: it recorded a real workout before the crash, which the phone may have finished meanwhile.
    func recoverWorkoutSession() {
        if session.recover(), controller.state == nil {
            scheduleOrphanCheck(save: true)
        }
        requestStateFromPhone()
    }

    /// Called by `WatchAppDelegate` whenever the app becomes active: a Health session that failed to start (for instance because
    /// the app was in the background when the workout arrived) is started again, and one that belongs to another workout than the
    /// one shown is replaced. Does nothing without a workout.
    func reconcileSessionWithWorkout() {
        guard let state = controller.state else { return }
        reconcileSession(with: state)
    }

    /// Ends the session after `orphanTimeoutNanoseconds` when still no workout is shown. `save` is whether the session recorded
    /// anything worth keeping: a session the phone launched for a workout that never arrived did not, a recovered one did.
    private func scheduleOrphanCheck(save: Bool) {
        orphanCheck?.cancel()
        let timeout = orphanTimeoutNanoseconds
        orphanCheck = Task { [weak self] in
            try? await Task.sleep(nanoseconds: timeout)
            guard !Task.isCancelled, let self else { return }
            if self.controller.state == nil {
                self.sessionWorkoutID = nil
                self.session.end(save: save)
            }
            self.orphanCheck = nil
        }
    }

    /// Makes the Health session record the workout `state` shows.
    ///
    /// A session that belongs to ANOTHER workout is ended first: the end notice of that workout never reached the Watch (the phone
    /// pushes with `updateApplicationContext`, which keeps only the latest value, so "A ended" followed by "B started" while the
    /// Watch was out of reach delivers only B), and without this B would carry on A's session and Health would get one long
    /// workout. The new session waits behind the old one (`WatchWorkoutSession.start` queues it while the old one ends). Nothing
    /// says how A ended, so it is saved when the Watch saw a logged set, the rule by which the phone discards a finish.
    private func reconcileSession(with state: WorkoutState) {
        if let owner = sessionWorkoutID, owner != state.id {
            session.end(save: sessionWorkoutHasLoggedSets)
            sessionWorkoutID = nil
        }
        if sessionWorkoutID == nil {
            sessionWorkoutID = state.id
            sessionWorkoutHasLoggedSets = WatchWorkoutTotals(state).loggedSets > 0
        }
        session.start(workoutStartDate: state.startedAt)
    }

    /// Every state the controller publishes (the Watch's own edits and the phone's): keeps the Health session paused while the
    /// workout is, and remembers whether the session's workout has a logged set.
    private func stateChanged(_ state: WorkoutState?) {
        guard let state = state else { return }
        session.setPaused(state.isPaused)
        if state.id == sessionWorkoutID {
            sessionWorkoutHasLoggedSets = WatchWorkoutTotals(state).loggedSets > 0
        }
    }

    // MARK: Workout lifecycle (called by WatchLifecycleEffect)

    fileprivate func handleWorkoutStarted(_ state: WorkoutState) {
        endedSummary = nil
        pendingEndDate = nil
        orphanCheck?.cancel()
        orphanCheck = nil
        reconcileSession(with: state)
    }

    fileprivate func handleWorkoutEnded(_ state: WorkoutState) {
        let endedAt = pendingEndDate ?? Date()
        pendingEndDate = nil
        orphanCheck?.cancel()
        orphanCheck = nil
        // The phone threw the workout away (Discard Workout, or a finish with no logged set): the Health session is discarded
        // too, so no workout the user explicitly dropped lands in Health. Otherwise it is saved.
        let discarded = controller.lastEndDiscarded
        sessionWorkoutID = nil
        session.end(save: !discarded)
        session.setPaused(false)
        // A discarded workout, and one without a logged set, has nothing to summarise.
        if !discarded, WatchWorkoutTotals(state).loggedSets > 0 {
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
