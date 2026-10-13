#if os(iOS)
import Foundation
import HealthKit
import WatchConnectivity
import PulseStrengthCore

// These two helpers are plain functions (not members of the main-actor class) so that the closures they create,
// which the system calls on background queues, are not main-actor isolated.

/// Wakes or launches the companion Watch app so it starts its strength-training session.
private func launchCompanionWatchApp(using store: HKHealthStore) {
    let configuration = HKWorkoutConfiguration()
    configuration.activityType = .traditionalStrengthTraining
    configuration.locationType = .indoor
    store.startWatchApp(with: configuration) { (_: Bool, error: Error?) in
        if let error = error {
            ServiceLog.error("The Watch app could not be launched: \(error.localizedDescription)")
        }
    }
}

/// Sends `payload` to the Watch as the latest application context and, when the Watch is reachable, as a message too.
/// Errors are ignored: the next state change sends a newer envelope anyway.
private func deliverToWatch(_ payload: [String: Any], over session: WCSession) {
    do {
        try session.updateApplicationContext(payload)
    } catch {
        // Not activated, or the Watch app is gone: nothing to do.
    }
    if session.isReachable {
        session.sendMessage(payload, replyHandler: nil, errorHandler: { (_: Error) in })
    }
}

/// The phone's end of the Phone <-> Watch channel (WatchConnectivity).
///
/// * Phone -> Watch: after every change except heart-rate samples, the phone's authoritative state goes out as a
///   `SyncEnvelope` made by `WorkoutController.makeEnvelope(now:)` (`updateApplicationContext`, plus `sendMessage` when the
///   Watch is reachable). When the workout ends, an envelope without state and with the workout id follows.
/// * Watch -> phone: commands, heart-rate samples, "the Watch is recording" and "send me the state" requests are
///   decoded on the delegate queue, then handed to the main actor and turned into controller calls. Every command is
///   acknowledged by the envelope that follows it: when the command changed the state that is the envelope of the
///   change, otherwise (a duplicate, or a command without effect) the bridge pushes an envelope of its own.
/// * A new workout launches the Watch app (`HKHealthStore.startWatchApp(with:)`) when it is installed.
/// * The reachability of an installed Watch app during a workout becomes the `WatchStatus` shown on the workout screen.
@MainActor
final class PhoneWatchBridge: NSObject, WorkoutSideEffect, WCSessionDelegate {
    /// Called on the main actor when the status derived from reachability changes.
    var onStatusChange: (@MainActor (WatchStatus) -> Void)?
    /// `.notConnected` only while a workout runs and a paired Watch with the app installed is out of reach.
    private(set) var status: WatchStatus = .connected

    private weak var controller: WorkoutController?
    private let healthStore: HKHealthStore?
    private var activeWorkoutID: UUID?
    /// How many envelopes `push` was asked for so far; lets `handle` see whether a command already caused one.
    private var pushRequests = 0
    /// A workout that started before the session finished activating; its Watch launch waits for activation.
    private var pendingLaunchWorkoutID: UUID?
    private var graceTask: Task<Void, Never>?

    /// A Watch that was reachable a moment ago needs a few seconds to come up when the workout starts; only an
    /// outage that lasts this long is reported, so the banner does not flash at the start of every workout.
    private static let disconnectGraceNanoseconds: UInt64 = 5_000_000_000

    init(controller: WorkoutController, healthStore: HKHealthStore?) {
        self.controller = controller
        self.healthStore = healthStore
        super.init()
    }

    /// Sets the delegate and activates the session (no-op where WatchConnectivity is not supported).
    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    // MARK: WorkoutSideEffect

    func workoutStarted(_ state: WorkoutState) {
        activeWorkoutID = state.id
        pushCurrentState()
        launchWatchApp(for: state)
        refreshStatus()
    }

    func workoutChanged(from old: WorkoutState, to new: WorkoutState, action: WorkoutAction, origin: ActionOrigin) {
        // Heart-rate samples arrive every few seconds; the Watch measures them itself.
        if case .updateHeartRate = action {
            return
        }
        if activeWorkoutID != new.id {
            activeWorkoutID = new.id
            refreshStatus()
        }
        pushCurrentState()
    }

    func workoutEnded(_ state: WorkoutState, completed: CompletedWorkout?) {
        activeWorkoutID = nil
        pendingLaunchWorkoutID = nil
        pushCurrentState()
        refreshStatus()
    }

    // MARK: Phone -> Watch

    /// Sends the controller's envelope to the Watch: the current state (no state and the id of the workout that ended last when
    /// there is no workout) and the acknowledgements of the most recent commands.
    private func pushCurrentState() {
        guard let controller = controller else { return }
        push(.state(controller.makeEnvelope(now: Date())))
    }

    /// Sends the current state only while a workout is running.
    private func pushStateIfWorkoutRunning() {
        guard let controller = controller, controller.state != nil else { return }
        pushCurrentState()
    }

    private func push(_ message: SyncMessage) {
        pushRequests += 1
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        guard let payload = try? SyncCodec.encode(message) else { return }
        deliverToWatch(payload, over: session)
    }

    private func launchWatchApp(for state: WorkoutState) {
        // The Watch already records this workout: launching it again would restart its session.
        guard !state.usedWatch else {
            pendingLaunchWorkoutID = nil
            return
        }
        guard WCSession.isSupported(), let store = healthStore else { return }
        let session = WCSession.default
        guard session.activationState == .activated else {
            pendingLaunchWorkoutID = state.id
            return
        }
        pendingLaunchWorkoutID = nil
        guard session.isPaired, session.isWatchAppInstalled else { return }
        launchCompanionWatchApp(using: store)
    }

    // MARK: Watch -> phone

    private func handle(_ message: SyncMessage) {
        guard let controller = controller else { return }
        switch message {
        case .command(let command):
            let requestsBefore = pushRequests
            controller.receive(command)
            // A command that changed the state was announced by workoutChanged, acknowledgement included. A duplicate, or a
            // command without effect, changed nothing: its acknowledgement needs an envelope of its own.
            if pushRequests == requestsBefore {
                pushCurrentState()
            }
        case .heartRate(let sample):
            controller.send(.updateHeartRate(sample.bpm), origin: .watch)
        case .watchSession(let isRecording):
            controller.send(.setUsedWatch(isRecording), origin: .watch)
        case .requestState:
            pushCurrentState()
        case .state:
            // Phone -> Watch only; nothing to do if one ever comes back.
            break
        }
    }

    // MARK: Status

    private func computeStatus() -> WatchStatus {
        guard activeWorkoutID != nil, WCSession.isSupported() else { return .connected }
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else {
            return .connected
        }
        return session.isReachable ? .connected : .notConnected
    }

    private func refreshStatus() {
        switch computeStatus() {
        case .connected:
            graceTask?.cancel()
            graceTask = nil
            applyStatus(.connected)
        case .notConnected:
            guard status != .notConnected, graceTask == nil else { return }
            graceTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: PhoneWatchBridge.disconnectGraceNanoseconds)
                guard !Task.isCancelled, let self = self else { return }
                self.graceTask = nil
                self.applyStatus(self.computeStatus())
            }
        case .healthDenied:
            // Health access is reported by the Health writer, not by the connection.
            break
        }
    }

    private func applyStatus(_ newStatus: WatchStatus) {
        guard newStatus != status else { return }
        status = newStatus
        onStatusChange?(newStatus)
    }

    // MARK: Session events on the main actor

    private func sessionDidActivate() {
        if let pendingID = pendingLaunchWorkoutID, let state = controller?.state, state.id == pendingID {
            launchWatchApp(for: state)
        }
        pushStateIfWorkoutRunning()
        refreshStatus()
    }

    private func sessionConnectionDidChange() {
        refreshStatus()
        pushStateIfWorkoutRunning()
    }

    // MARK: WCSessionDelegate

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor [weak self] in
            self?.sessionDidActivate()
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        Task { @MainActor [weak self] in
            self?.refreshStatus()
        }
    }

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // The user switched to another paired Watch: activate again to receive the new Watch's data.
        session.activate()
        Task { @MainActor [weak self] in
            self?.refreshStatus()
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor [weak self] in
            self?.sessionConnectionDidChange()
        }
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor [weak self] in
            self?.sessionConnectionDidChange()
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handleInbound(message)
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        handleInbound(message)
        // The answer to a state request travels as a separate envelope; the Watch only needs to know it arrived.
        replyHandler([:])
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        handleInbound(userInfo)
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        handleInbound(applicationContext)
    }

    /// Decodes on the delegate queue (the payload dictionary is not Sendable), then continues on the main actor.
    nonisolated private func handleInbound(_ payload: [String: Any]) {
        guard let message = try? SyncCodec.decode(payload) else { return }
        Task { @MainActor [weak self] in
            self?.handle(message)
        }
    }
}
#endif
