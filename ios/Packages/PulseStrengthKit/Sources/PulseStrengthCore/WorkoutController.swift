import Foundation

#if canImport(Combine) || PULSE_COMBINE_SHIM
#if canImport(Combine)
import Combine
#endif

/// The observable face of a workout in progress, used by the iPhone screens, the Watch and the Live Activity services.
///
/// A thin Combine wrapper around `WorkoutEngine`: the engine does the work (reduce, save, sync rules, effects) and this class
/// republishes its state. The phone is the `.authority` (it saves and executes commands); the Watch is a `.mirror`.
@MainActor
public final class WorkoutController: ObservableObject {
    /// The workout in progress; nil when there is none.
    @Published public private(set) var state: WorkoutState?
    /// The workout finished most recently (cleared when the next one starts).
    @Published public private(set) var lastCompleted: CompletedWorkout?
    /// The store that holds templates, history and exercises.
    public let store: StrengthStore
    /// Phone (authority) or Watch (mirror).
    public let role: WorkoutRole

    /// Muscle recovery lookup used by `presentation(now:)`; replace it with the Pulse app's real model.
    public var recovery: RecoveryProvider {
        get { engine.recovery }
        set {
            engine.recovery = newValue
            isUsingDemoRecovery = false
        }
    }

    /// True until a recovery model is passed to the initializer or assigned to `recovery`. The numbers are then the demo constants
    /// (`DemoRecovery`), so a screen should not turn them into advice such as "Chest is recovered".
    public private(set) var isUsingDemoRecovery: Bool

    private let engine: WorkoutEngine

    /// Creates a controller on top of `store`; `persistence` holds the active workout (authority only), `clock` is injectable for tests.
    public init(
        store: StrengthStore,
        persistence: FileStrengthPersistence?,
        role: WorkoutRole = .authority,
        recovery: RecoveryProvider? = nil,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.store = store
        self.role = role
        self.isUsingDemoRecovery = (recovery == nil)
        self.engine = WorkoutEngine(
            role: role,
            persistence: persistence,
            data: StoreDataAdapter(store: store),
            recovery: recovery ?? DemoRecovery.provider,
            clock: clock
        )
        engine.onUpdate = { [weak self] in self?.republish() }
    }

    /// Registers a side effect (Live Activity, Watch bridge, notifications, Health) that is told about every change.
    public func addEffect(_ effect: WorkoutSideEffect) {
        engine.addEffect(effect)
    }

    /// On launch: reloads the active workout from disk and tells the effects (authority only).
    public func restoreFromDisk() {
        engine.restore()
    }

    /// Starts a workout from `template`, or an empty one named `name ?? "Workout"`; ignored while a workout is in progress.
    public func startWorkout(template: WorkoutTemplate?, name: String? = nil) {
        engine.start(template: template, name: name)
    }

    /// Applies `action`: reduce, save (authority), publish, tell the effects.
    ///
    /// A mirror (the Watch) that applies an action of origin `.watch` also makes a `RemoteCommand` of it, remembers it in
    /// `pendingCommands` until the phone acknowledges it and tells the effects through `commandIssued`.
    public func send(_ action: WorkoutAction, origin: ActionOrigin = .phone) {
        engine.send(action, origin: origin)
    }

    /// Authority: runs a command from the Watch or the Live Activity once (duplicates by id are dropped) and acknowledges it, even
    /// when it was a duplicate or changed nothing. Send `makeEnvelope(now:)` afterwards.
    public func receive(_ command: RemoteCommand) {
        engine.receive(command)
    }

    /// Mirror: adopts the phone's state unless it is stale (see `SyncReconciler.shouldAdopt`), drops the edits the envelope
    /// acknowledges and replays the others on top; an envelope without a state ends the local workout. Never reports a change to
    /// the effects (no echo).
    public func receive(_ envelope: SyncEnvelope) {
        engine.receive(envelope)
    }

    /// Authority: the envelope to push to the Watch (state, or the id of the workout that ended last, plus the acknowledgements
    /// of the most recent commands). Push it after every change and after every received command, even a duplicate or a no-op.
    public func makeEnvelope(now: Date) -> SyncEnvelope {
        engine.makeEnvelope(now: now)
    }

    /// Mirror: the edits shown on top of the phone's state that the phone has not acknowledged yet, oldest first.
    public var pendingCommands: [RemoteCommand] {
        engine.pendingCommands
    }

    /// Mirror: when the oldest unacknowledged edit stops being shown (nil without one); call `expirePending()` then, because a
    /// command the phone never received produces no envelope that would drop it.
    public var nextPendingExpiry: Date? {
        engine.nextPendingExpiry
    }

    /// Mirror: drops the unacknowledged edits that are older than their lifetime and shows the phone's last state with the rest on
    /// top. Returns true when an edit was dropped (ask the phone for its state then). See `WorkoutEngine.expirePending()`.
    @discardableResult
    public func expirePending() -> Bool {
        engine.expirePending()
    }

    /// Mirror: the transport holds the command in its guaranteed queue (`transferUserInfo`): keep showing its edit for
    /// `SyncReconciler.queuedPendingLifetime`. See `WorkoutEngine.markQueued(commandID:)`.
    public func markQueued(commandID: UUID) {
        engine.markQueued(commandID: commandID)
    }

    /// Mirror: the revision of the last phone state adopted for the workout in progress (the phone's, not the Watch's own).
    public var authoritativeRevision: Int? {
        engine.authoritativeRevision
    }

    /// How the workout that ended most recently ended: true when it was thrown away, false when it was finished. Read it from
    /// `WorkoutSideEffect.workoutEnded`, where `completed` is nil on a mirror in both cases. See `WorkoutEngine.lastEndDiscarded`.
    public var lastEndDiscarded: Bool {
        engine.lastEndDiscarded
    }

    /// Mirror: when the phone sent the end notice that ended the workout that ended last (nil: it ended on this side). Read it
    /// from `WorkoutSideEffect.workoutEnded` like `lastEndDiscarded`. See `WorkoutEngine.lastEndNoticeSentAt`.
    public var lastEndNoticeSentAt: Date? {
        engine.lastEndNoticeSentAt
    }

    /// The active-workout screen model for `now`; nil without a workout.
    public func presentation(now: Date) -> ActiveWorkoutPresentation? {
        engine.presentation(now: now)
    }

    /// The Live Activity / Watch snapshot for `now`; nil without a workout.
    public func snapshot(now: Date) -> WorkoutSnapshot? {
        engine.snapshot(now: now)
    }

    /// What changed against the template the workout started from.
    public func templateDiff() -> TemplateDiff {
        engine.templateDiff()
    }

    /// Finishes the workout: builds the summary, records it in the store, clears the state and tells the effects.
    @discardableResult
    public func finish(updateTemplate: Bool) -> CompletedWorkout? {
        engine.finish(updateTemplate: updateTemplate)
    }

    /// Throws the workout away without recording it.
    public func discard() {
        engine.discard()
    }

    /// Copies the engine's values into the published properties that changed.
    private func republish() {
        if state != engine.state { state = engine.state }
        if lastCompleted != engine.lastCompleted { lastCompleted = engine.lastCompleted }
    }
}

/// Lets the engine use the store's public API, so every recorded workout also refreshes the store's published values.
@MainActor
private final class StoreDataAdapter: WorkoutDataProviding {
    private let store: StrengthStore

    init(store: StrengthStore) {
        self.store = store
    }

    func exercise(id: String) -> Exercise? {
        store.exercise(id: id)
    }

    func template(id: UUID) -> WorkoutTemplate? {
        store.templates.first { $0.id == id }
    }

    func record(_ completed: CompletedWorkout, updateTemplate: WorkoutTemplate?) -> Result<Void, Error> {
        store.record(completed, updateTemplate: updateTemplate)
    }
}

#endif
