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
        set { engine.recovery = newValue }
    }

    private let engine: WorkoutEngine

    /// Creates a controller on top of `store`; `persistence` holds the active workout (authority only), `clock` is injectable for tests.
    public init(
        store: StrengthStore,
        persistence: FileStrengthPersistence?,
        role: WorkoutRole = .authority,
        recovery: @escaping RecoveryProvider = DemoRecovery.provider,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.store = store
        self.role = role
        self.engine = WorkoutEngine(
            role: role,
            persistence: persistence,
            data: StoreDataAdapter(store: store),
            recovery: recovery,
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
    public func send(_ action: WorkoutAction, origin: ActionOrigin = .phone) {
        engine.send(action, origin: origin)
    }

    /// Authority: runs a command from the Watch or the Live Activity once (duplicates by id are dropped).
    public func receive(_ command: RemoteCommand) {
        engine.receive(command)
    }

    /// Mirror: adopts the phone's newer state; an envelope without a state ends the local workout.
    public func receive(_ envelope: SyncEnvelope) {
        engine.receive(envelope)
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

    func record(_ completed: CompletedWorkout, updateTemplate: WorkoutTemplate?) {
        store.record(completed, updateTemplate: updateTemplate)
    }
}

#endif
