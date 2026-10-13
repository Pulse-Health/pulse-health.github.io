#if os(watchOS)
import Foundation
import WatchConnectivity
import PulseStrengthCore

// MARK: - Plain helpers
//
// These are file-scope functions (not members of the main-actor class below) on purpose: the closures they create are
// called by WatchConnectivity on background queues, so they must not be main-actor isolated.

/// Decodes a WatchConnectivity payload; nil for an empty dictionary or anything that is not a `SyncMessage`.
private func decodeSyncMessage(_ payload: [String: Any]) -> SyncMessage? {
    if payload.isEmpty { return nil }
    return try? SyncCodec.decode(payload)
}

/// Sends `payload` with `sendMessage` while the phone is reachable and falls back to `transferUserInfo`
/// (queued, delivered later, in order) when it is not, or when the immediate send fails. A message is never dropped.
private func deliverReliably(_ payload: [String: Any], over session: WCSession) {
    if session.activationState == .activated && session.isReachable {
        session.sendMessage(payload, replyHandler: nil, errorHandler: { (_: Error) in
            _ = session.transferUserInfo(payload)
        })
    } else {
        _ = session.transferUserInfo(payload)
    }
}

/// Best-effort send for perishable data (heart rate, state requests): only while the phone is reachable, never queued.
private func deliverIfReachable(_ payload: [String: Any], over session: WCSession) {
    guard session.activationState == .activated, session.isReachable else { return }
    session.sendMessage(payload, replyHandler: nil, errorHandler: { (_: Error) in })
}

// MARK: - Client

/// The Watch's end of the Phone <-> Watch channel (WatchConnectivity).
///
/// * Phone -> Watch: `SyncMessage.state` envelopes arrive through `didReceiveApplicationContext`, `didReceiveMessage` or
///   `didReceiveUserInfo`. They are decoded on the delegate queue, then handed to the main actor and given to
///   `WorkoutController.receive(_: SyncEnvelope)`.
/// * Watch -> phone: as a `WorkoutSideEffect` the client forwards every action the Watch applied locally
///   (`origin == .watch`) as a `RemoteCommand`. Commands and `watchSession` messages use `sendMessage` while the phone is
///   reachable and `transferUserInfo` otherwise, so they are never lost; heart-rate samples (at most one every 5 s) and
///   state requests are sent only while the phone is reachable.
/// * It tracks the phone's reachability and asks the phone for the current state whenever the session activates or the
///   phone becomes reachable.
///
/// Create it with the Watch's mirror controller, register it with `controller.addEffect(_:)` and call `activate()`.
@MainActor
public final class WatchConnectivityClient: NSObject, WCSessionDelegate, WorkoutSideEffect {

    /// True while the paired iPhone app is reachable for immediate messages.
    public private(set) var isPhoneReachable: Bool = false

    /// Called on the main actor whenever `isPhoneReachable` changes.
    public var onReachabilityChange: (@MainActor (Bool) -> Void)?

    /// Called on the main actor with every inbound state envelope, just before the controller receives it.
    public var onEnvelope: (@MainActor (SyncEnvelope) -> Void)?

    private weak var controller: WorkoutController?
    private var lastHeartRateSent: Date?
    /// Messages that were produced before the session finished activating; sent right after activation.
    private var pendingMessages: [SyncMessage] = []

    private let heartRateInterval: TimeInterval = 5
    private let pendingLimit = 200

    /// Creates a client that feeds inbound envelopes to `controller` (the Watch's mirror controller).
    public init(controller: WorkoutController) {
        self.controller = controller
        super.init()
    }

    // MARK: Activation

    /// Sets the delegate and activates the session (no-op where WatchConnectivity is not supported).
    public func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        if session.activationState == .activated {
            activationFinished(isActivated: true, context: decodeSyncMessage(session.receivedApplicationContext))
        }
    }

    // MARK: State requests

    /// Re-reads the phone's last pushed state and, while the phone is reachable, asks it to send the current state again.
    public func requestState() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        if let message = decodeSyncMessage(session.receivedApplicationContext) {
            handle(message)
        }
        askPhoneForState(over: session)
    }

    private func askPhoneForState(over session: WCSession) {
        guard let payload = try? SyncCodec.encode(.requestState) else { return }
        deliverIfReachable(payload, over: session)
    }

    // MARK: Watch -> phone

    /// Sends a heart-rate sample to the phone; samples closer than 5 s to the previous one are dropped.
    public func sendHeartRate(_ bpm: Int) {
        guard WCSession.isSupported() else { return }
        let now = Date()
        if let last = lastHeartRateSent, now >= last, now.timeIntervalSince(last) < heartRateInterval {
            return
        }
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else { return }
        guard let payload = try? SyncCodec.encode(.heartRate(HeartRateSample(bpm: bpm, at: now))) else { return }
        lastHeartRateSent = now
        deliverIfReachable(payload, over: session)
    }

    /// Tells the phone that the Watch workout session started or stopped recording.
    public func sendWatchSession(isRecording: Bool) {
        sendReliably(.watchSession(isRecording: isRecording))
    }

    private func sendReliably(_ message: SyncMessage) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else {
            pendingMessages.append(message)
            if pendingMessages.count > pendingLimit {
                pendingMessages.removeFirst(pendingMessages.count - pendingLimit)
            }
            return
        }
        transmit(message, over: session)
    }

    private func transmit(_ message: SyncMessage, over session: WCSession) {
        guard let payload = try? SyncCodec.encode(message) else { return }
        deliverReliably(payload, over: session)
    }

    private func flushPendingMessages(over session: WCSession) {
        guard !pendingMessages.isEmpty else { return }
        let queued = pendingMessages
        pendingMessages.removeAll()
        for message in queued {
            transmit(message, over: session)
        }
    }

    // MARK: WorkoutSideEffect

    public func workoutStarted(_ state: WorkoutState) {
        lastHeartRateSent = nil
    }

    public func workoutChanged(from old: WorkoutState, to new: WorkoutState, action: WorkoutAction, origin: ActionOrigin) {
        // Only edits made on the Watch go to the phone; edits that came from the phone (envelopes) never reach this method.
        guard origin == .watch else { return }
        // Heart-rate samples have their own throttled channel.
        if case .updateHeartRate = action { return }
        sendReliably(.command(RemoteCommand(action: action, origin: .watch)))
    }

    public func workoutEnded(_ state: WorkoutState, completed: CompletedWorkout?) {
        lastHeartRateSent = nil
    }

    // MARK: Inbound (main actor)

    private func handle(_ message: SyncMessage) {
        // Only the phone's state envelopes are meant for the Watch; commands, heart rate and requests travel the other way.
        guard case .state(let envelope) = message else { return }
        onEnvelope?(envelope)
        controller?.receive(envelope)
    }

    private func applyReachability(_ reachable: Bool) {
        guard reachable != isPhoneReachable else { return }
        isPhoneReachable = reachable
        onReachabilityChange?(reachable)
    }

    private func reachabilityChanged(_ reachable: Bool) {
        applyReachability(reachable)
        guard reachable, WCSession.isSupported() else { return }
        let session = WCSession.default
        if session.activationState == .activated {
            askPhoneForState(over: session)
        }
    }

    private func activationFinished(isActivated: Bool, context: SyncMessage?) {
        guard isActivated else { return }
        let session = WCSession.default
        applyReachability(session.isReachable)
        if let context {
            handle(context)
        }
        flushPendingMessages(over: session)
        askPhoneForState(over: session)
    }

    // MARK: WCSessionDelegate (called on a background queue)

    nonisolated public func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        let isActivated = activationState == .activated
        let context: SyncMessage? = isActivated ? decodeSyncMessage(session.receivedApplicationContext) : nil
        Task { @MainActor [weak self] in
            self?.activationFinished(isActivated: isActivated, context: context)
        }
    }

    nonisolated public func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor [weak self] in
            self?.reachabilityChanged(reachable)
        }
    }

    nonisolated public func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handleInbound(message)
    }

    nonisolated public func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        handleInbound(message)
        replyHandler([:])
    }

    nonisolated public func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        handleInbound(userInfo)
    }

    nonisolated public func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        handleInbound(applicationContext)
    }

    /// Decodes on the delegate queue (the payload dictionary is not Sendable), then continues on the main actor
    /// with the decoded, Sendable message.
    nonisolated private func handleInbound(_ payload: [String: Any]) {
        guard let message = decodeSyncMessage(payload) else { return }
        Task { @MainActor [weak self] in
            self?.handle(message)
        }
    }
}
#endif
