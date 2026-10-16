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

/// Set and volume totals of a workout (the presenter's rules: warm-up sets, exercises without a weight and weights that are not
/// positive are left out of the volume).
private struct WatchWorkoutTotals {
    var loggedSets = 0
    var totalSets = 0
    var volumeKg = 0.0

    init(_ state: WorkoutState) {
        for entry in state.exercises {
            totalSets += entry.sets.count
            loggedSets += entry.doneCount
            volumeKg += entry.loggedVolumeKg
        }
    }
}

// MARK: - Workouts the Watch saved to Health

private let savedHealthWorkoutsKey = "pulse.strength.watch.savedHealthWorkoutIDs"

/// How many saved workouts the Watch remembers.
private let savedHealthWorkoutsMemory = 8

/// The ids of the last workouts whose Health session the Watch ended with a save, oldest first (they survive a relaunch of the
/// Watch app: the phone can restore a finished workout days later).
private func loadSavedHealthWorkoutIDs() -> [UUID] {
    let strings = UserDefaults.standard.stringArray(forKey: savedHealthWorkoutsKey) ?? []
    return strings.compactMap { UUID(uuidString: $0) }
}

private func storeSavedHealthWorkoutIDs(_ ids: [UUID]) {
    UserDefaults.standard.set(ids.map { $0.uuidString }, forKey: savedHealthWorkoutsKey)
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
///   becomes active retries a start that failed, and a session that survived a crash is taken over again. The Health workout ends
///   when the phone ended the workout, a workout the Watch already saved gets no second session, and a session that ended by
///   itself is replaced by one that starts now, so the two Health workouts do not overlap.
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
    /// The workouts (the last few) whose Health session the Watch ended with a save. The phone can restore one of them (its history
    /// write failed and the next launch restored it): that workout gets no second Health session, Health holds it already.
    private var savedWorkoutIDs: [UUID] = loadSavedHealthWorkoutIDs()
    /// Whether the Health session of the workout shown ended by itself and was saved: a session started for the same workout
    /// again begins now, not at the workout's start.
    private var sessionSavedSegment = false
    /// The newest end notice that reached the Watch while it showed no workout, until a workout shows up.
    private var endNoticeWithoutWorkout: EndNoticeWithoutWorkout?
    private var orphanCheck: Task<Void, Never>?
    /// Whether the pending `orphanCheck` saves the session it ends.
    private var orphanCheckSaves = false

    private struct EndNoticeWithoutWorkout {
        var sentAt: Date
        var discarded: Bool?
    }

    /// Seconds a session that the phone launched may wait for the workout's state before it is stopped again.
    private let orphanTimeoutNanoseconds: UInt64 = 45_000_000_000

    public init() {
        let store = StrengthStore(persistence: nil)
        let controller = WorkoutController(store: store, persistence: nil, role: .mirror)
        controller.displayLocale = .current
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
        // A Health session that ended by itself was saved: the one that replaces it must not overlap it.
        session.onEndedByItself = { [weak self] in
            self?.sessionSavedSegment = true
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
        session.start(workoutStartDate: healthStartDate(for: controller.state))
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
    ///
    /// A check that is already waiting to save is not turned into one that throws the session away: the phone launching the app
    /// while a recovered session runs (`save: false`) must not discard what that session recorded before the crash.
    private func scheduleOrphanCheck(save: Bool) {
        let saves = save || (orphanCheck != nil && orphanCheckSaves)
        orphanCheck?.cancel()
        orphanCheckSaves = saves
        let timeout = orphanTimeoutNanoseconds
        orphanCheck = Task { [weak self] in
            try? await Task.sleep(nanoseconds: timeout)
            guard !Task.isCancelled, let self else { return }
            self.orphanCheckFired()
        }
    }

    private func cancelOrphanCheck() {
        orphanCheck?.cancel()
        orphanCheck = nil
        orphanCheckSaves = false
    }

    /// No workout showed up for the session nobody claimed: end it. The phone's end notice decides how when it reached the Watch
    /// (while it had no workout, so the engine told nobody): a workout the phone discarded is not saved, whatever the check was
    /// going to do, and a finished one ends when the phone ended it.
    private func orphanCheckFired() {
        let saves = orphanCheckSaves
        orphanCheck = nil
        orphanCheckSaves = false
        guard controller.state == nil else { return }
        sessionWorkoutID = nil
        sessionSavedSegment = false
        var save = saves
        var endDate: Date? = nil
        if let notice = endNoticeWithoutWorkout,
           SyncReconciler.endNotice(sentAt: notice.sentAt, settlesSessionStartedAt: session.recordingStartDate) {
            if notice.discarded == true {
                save = false
            } else {
                endDate = notice.sentAt
            }
        }
        endNoticeWithoutWorkout = nil
        session.end(save: save, endDate: endDate)
    }

    /// The phone said (while the Watch showed no workout) that the workout ended by throwing it away: a Health session no workout
    /// has claimed, one that is waiting for its orphan check, ends now without saving, when the notice was sent after the session
    /// began (an older one is an earlier workout's). A session still being recovered has no start yet and waits for its check.
    private func settleUnclaimedSession() {
        guard controller.state == nil, sessionWorkoutID == nil, orphanCheck != nil,
              let notice = endNoticeWithoutWorkout, notice.discarded == true,
              SyncReconciler.endNotice(sentAt: notice.sentAt, settlesSessionStartedAt: session.recordingStartDate)
        else { return }
        endNoticeWithoutWorkout = nil
        cancelOrphanCheck()
        session.end(save: false)
    }

    /// When a Health session for `state` begins: at the workout's start, or now when the session of this workout ended by itself
    /// and was saved (the new one must not overlap it). `Date()` without a workout.
    private func healthStartDate(for state: WorkoutState?) -> Date {
        if sessionSavedSegment { return Date() }
        return state?.startedAt ?? Date()
    }

    /// Makes the Health session record the workout `state` shows.
    ///
    /// A session that belongs to ANOTHER workout is ended first: the end notice of that workout never reached the Watch (the phone
    /// pushes with `updateApplicationContext`, which keeps only the latest value, so "A ended" followed by "B started" while the
    /// Watch was out of reach delivers only B), and without this B would carry on A's session and Health would get one long
    /// workout. The new session waits behind the old one (`WatchWorkoutSession.start` queues it while the old one ends). Nothing
    /// says how A ended, so it is saved when the Watch saw a logged set, the rule by which the phone discards a finish.
    ///
    /// A workout whose Health session the Watch already saved (the phone restored it after the history write failed) gets no new
    /// session: Health holds it, and a second one would save an overlapping workout when it is finished again.
    private func reconcileSession(with state: WorkoutState) {
        if let owner = sessionWorkoutID, owner != state.id {
            if sessionWorkoutHasLoggedSets { rememberSavedWorkout(owner) }
            session.end(save: sessionWorkoutHasLoggedSets)
            sessionWorkoutID = nil
            sessionSavedSegment = false
        }
        if sessionWorkoutID == nil {
            if savedWorkoutIDs.contains(state.id) { return }
            sessionWorkoutID = state.id
            sessionWorkoutHasLoggedSets = WatchWorkoutTotals(state).loggedSets > 0
        }
        session.start(workoutStartDate: healthStartDate(for: state))
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
        cancelOrphanCheck()
        endNoticeWithoutWorkout = nil
        reconcileSession(with: state)
    }

    fileprivate func handleWorkoutEnded(_ state: WorkoutState) {
        let now = Date()
        // When the phone ended the workout (the engine knows which envelope ended it; nil: it ended here). A late notice must not
        // inflate the duration, neither in the summary nor in Health.
        let phoneEndedAt = controller.lastEndNoticeSentAt
        let endedAt = min(phoneEndedAt ?? now, now)
        cancelOrphanCheck()
        // The phone threw the workout away (Discard Workout, or a finish with no logged set): the Health session is discarded
        // too, so no workout the user explicitly dropped lands in Health. Otherwise it is saved.
        let discarded = controller.lastEndDiscarded
        if !discarded, sessionWorkoutID == state.id {
            rememberSavedWorkout(state.id)
        }
        sessionWorkoutID = nil
        sessionSavedSegment = false
        session.end(save: !discarded, endDate: phoneEndedAt)
        session.setPaused(false)
        // A discarded workout, and one without a logged set, has nothing to summarise.
        if !discarded, WatchWorkoutTotals(state).loggedSets > 0 {
            endedSummary = WatchEndedSummary(state: state, endedAt: endedAt)
        }
    }

    private func rememberSavedWorkout(_ id: UUID) {
        savedWorkoutIDs.removeAll { $0 == id }
        savedWorkoutIDs.append(id)
        if savedWorkoutIDs.count > savedHealthWorkoutsMemory {
            savedWorkoutIDs.removeFirst(savedWorkoutIDs.count - savedHealthWorkoutsMemory)
        }
        storeSavedHealthWorkoutIDs(savedWorkoutIDs)
    }

    /// Called with every envelope from the phone just before the controller receives it. An end notice that reaches a Watch showing
    /// no workout ends nothing in the controller (it only remembers the id), so it is kept here: a Health session that no workout
    /// has claimed (one recovered after a crash) learns from it how its workout ended.
    private func noteEnvelope(_ envelope: SyncEnvelope) {
        guard envelope.state == nil, controller.state == nil, envelope.endedWorkoutID != nil else { return }
        if let known = endNoticeWithoutWorkout, known.sentAt >= envelope.sentAt { return }
        endNoticeWithoutWorkout = EndNoticeWithoutWorkout(sentAt: envelope.sentAt, discarded: envelope.discarded)
        settleUnclaimedSession()
    }
}
#endif
