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
///
/// While earlier messages still wait in the `transferUserInfo` queue, this one joins that queue even if the phone is reachable
/// again: a `sendMessage` would overtake the older, still queued ones. (A `sendMessage` that fails later moves to the queue by
/// itself, so one tap can still be overtaken by the next; the phone orders absolute edits by their sequence numbers.)
///
/// Returns true when the message went into the `transferUserInfo` queue right away: the system keeps it until the phone gets it.
@discardableResult
private func deliverReliably(_ payload: [String: Any], over session: WCSession) -> Bool {
    if session.activationState == .activated && session.isReachable && session.outstandingUserInfoTransfers.isEmpty {
        session.sendMessage(payload, replyHandler: nil, errorHandler: { (_: Error) in
            _ = session.transferUserInfo(payload)
        })
        return false
    }
    _ = session.transferUserInfo(payload)
    return true
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
/// * Watch -> phone: as a `WorkoutSideEffect` the client sends every `RemoteCommand` the mirror controller issues for an
///   action the Watch applied locally (`commandIssued`, once per command). Commands and `watchSession` messages use
///   `sendMessage` while the phone is reachable (and no older message waits in the `transferUserInfo` queue) and
///   `transferUserInfo` otherwise, so they are never lost (the phone drops a command it receives twice). A command that went
///   into the `transferUserInfo` queue is reported to the controller (`markQueued`), which then keeps showing its edit while the
///   phone is away; for the others a timer asks the controller to drop an edit the phone never acknowledged after 15 s, and asks
///   the phone for its state. Heart-rate samples (at most one every 5 s) and state requests are sent only while the phone is
///   reachable.
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
    /// The timer that drops an unacknowledged edit when its lifetime is over (see `scheduleExpiryCheck`).
    private var expiryTask: Task<Void, Never>?

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

    /// Sends `message` reliably. Returns true when it went into the system's `transferUserInfo` queue (the phone is out of reach).
    @discardableResult
    private func sendReliably(_ message: SyncMessage) -> Bool {
        guard WCSession.isSupported() else { return false }
        let session = WCSession.default
        guard session.activationState == .activated else {
            pendingMessages.append(message)
            if pendingMessages.count > pendingLimit {
                pendingMessages.removeFirst(pendingMessages.count - pendingLimit)
            }
            return false
        }
        return transmit(message, over: session)
    }

    @discardableResult
    private func transmit(_ message: SyncMessage, over session: WCSession) -> Bool {
        guard let payload = try? SyncCodec.encode(message) else { return false }
        return deliverReliably(payload, over: session)
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

    public func commandIssued(_ command: RemoteCommand) {
        // The controller makes one command per edit made on the Watch (never for heart-rate samples, which have their own
        // throttled channel, and never for envelopes from the phone) and keeps it until the phone acknowledges it.
        if sendReliably(.command(command)) {
            // The system queue delivers it whenever the phone is back: keep showing the edit for much longer than 15 seconds.
            controller?.markQueued(commandID: command.id)
        }
        scheduleExpiryCheck()
    }

    public func workoutEnded(_ state: WorkoutState, completed: CompletedWorkout?) {
        lastHeartRateSent = nil
    }

    // MARK: Lost commands

    /// Wakes up when the oldest unacknowledged edit is due to expire and lets the controller drop it. A command the phone never
    /// received makes the phone change nothing and send nothing, so no envelope would ever remove the edit from the screen.
    private func scheduleExpiryCheck() {
        guard expiryTask == nil, let due = controller?.nextPendingExpiry else { return }
        let seconds = min(max(1, due.timeIntervalSinceNow + 0.5), 86_400)
        expiryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            self?.expiryCheckFired()
        }
    }

    private func expiryCheckFired() {
        expiryTask = nil
        guard let controller = controller else { return }
        if controller.expirePending(), WCSession.isSupported() {
            // A dropped edit may have reached the phone after all (its acknowledgement was lost): ask what the phone has.
            let session = WCSession.default
            if session.activationState == .activated {
                askPhoneForState(over: session)
            }
        }
        scheduleExpiryCheck()
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
