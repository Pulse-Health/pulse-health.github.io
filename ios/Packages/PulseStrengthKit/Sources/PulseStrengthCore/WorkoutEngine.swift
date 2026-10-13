import Foundation

// MARK: - Roles and data access

/// Which side of the phone / Watch pair a controller is.
public enum WorkoutRole: Hashable, Sendable {
    /// The phone: owns the workout, persists it and executes commands from other surfaces.
    case authority
    /// The Watch: shows a copy of the phone's workout, applies edits optimistically and never persists.
    case mirror
}

/// What the workout engine needs from the app's saved data: exercise lookups and a place to record finished workouts.
@MainActor
public protocol WorkoutDataProviding: AnyObject {
    /// The exercise with the remembered previous results overlaid, or nil for an unknown id.
    func exercise(id: String) -> Exercise?
    /// The saved template with the given id.
    func template(id: UUID) -> WorkoutTemplate?
    /// Records a finished workout (history, personal bests, template `lastPerformed`) and replaces `updateTemplate` when given.
    ///
    /// The data changes in memory in every case. The result is `.failure` when the workout could not be saved to disk (its history
    /// file); the engine then keeps the active-workout file, the last saved copy of the workout.
    @discardableResult
    func record(_ completed: CompletedWorkout, updateTemplate: WorkoutTemplate?) -> Result<Void, Error>
}

// MARK: - Engine

/// The platform-neutral heart of `WorkoutController`: owns the workout in progress and runs every change through the reducer.
///
/// The engine has no Combine dependency. After each change it calls `onUpdate` (so a wrapper can publish) and then tells the
/// registered side effects. Heart-rate samples are applied to the in-memory state every time, but they are saved and reported to
/// the effects at most once per `heartRateInterval` seconds of the injected clock.
///
/// Phone / Watch sync (`SyncReconciler` explains the rules): the authority applies commands once, acknowledges every command it
/// receives and puts the acknowledgements into `makeEnvelope(now:)`. The mirror applies its own edits at once, issues one command
/// per edit (`WorkoutSideEffect.commandIssued`) and, when a phone envelope arrives, shows the phone's state with its still
/// unacknowledged edits replayed on top.
@MainActor
public final class WorkoutEngine {
    /// Minimum time between saving / reporting two heart-rate-only changes (10 seconds).
    public nonisolated static var heartRateInterval: TimeInterval { 10 }

    /// How many finished workout ids are remembered to ignore late sync messages about them.
    private static let endedMemory = 8

    /// Phone (authority) or Watch (mirror).
    public let role: WorkoutRole
    /// Muscle recovery lookup used by `presentation(now:)`.
    public var recovery: RecoveryProvider
    /// The workout in progress; nil when there is none.
    public private(set) var state: WorkoutState?
    /// The workout finished most recently (cleared when the next one starts).
    public private(set) var lastCompleted: CompletedWorkout?
    /// The error of the last failed attempt to save the active workout, or of a finished workout that could not be saved to the
    /// history; nil after a successful save.
    public private(set) var lastPersistenceError: Error?
    /// Called after `state` or `lastCompleted` changed and before the side effects are told.
    public var onUpdate: (() -> Void)?

    /// Mirror: the edits shown on top of the phone's state that the phone has not acknowledged yet, oldest first (empty for an
    /// authority).
    public var pendingCommands: [RemoteCommand] { pending }

    /// Mirror: the revision of the last phone state adopted for the workout in progress. This is the phone's own revision, not the
    /// revision of the mirror's optimistically edited copy. nil without a workout or before the first adoption.
    public var authoritativeRevision: Int? {
        guard let authoritative, authoritative.workoutID == state?.id else { return nil }
        return authoritative.revision
    }

    private let persistence: FileStrengthPersistence?
    private let data: WorkoutDataProviding
    private let clock: @Sendable () -> Date
    private var seenCommands = SeenCommands()
    private var effects: [WorkoutSideEffect] = []
    private var lastHeartRateReport: Date?
    private var recentlyEnded: [UUID] = []

    /// Authority: the ids of the commands it has dealt with (applied, duplicate or without effect), oldest first, at most
    /// `SyncReconciler.acknowledgedMemory`. The most recent ones go out in every envelope.
    private var acknowledged: [UUID] = []
    /// Mirror: the edits applied locally that the phone has not acknowledged yet, oldest first.
    private var pending: [RemoteCommand] = []
    /// Mirror: what the last adopted phone state of the running workout looked like.
    private var authoritative: AuthoritativeMark?

    /// The phone's last adopted state of the workout the mirror shows: its id and revision, and when the phone sent it.
    private struct AuthoritativeMark {
        var workoutID: UUID
        var revision: Int
        var sentAt: Date
    }

    /// Creates an engine; `persistence` is only written when `role == .authority`.
    public init(
        role: WorkoutRole,
        persistence: FileStrengthPersistence?,
        data: WorkoutDataProviding,
        recovery: @escaping RecoveryProvider = DemoRecovery.provider,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.role = role
        self.persistence = persistence
        self.data = data
        self.recovery = recovery
        self.clock = clock
    }

    /// Registers a side effect (ignored when the same object is already registered).
    public func addEffect(_ effect: WorkoutSideEffect) {
        guard !effects.contains(where: { $0 === effect }) else { return }
        effects.append(effect)
    }

    // MARK: Lifecycle

    /// Authority: loads the saved active workout (if any) and tells the effects it was restored.
    ///
    /// Does nothing for a mirror, without persistence, without a saved workout, or while a workout is already in progress
    /// (the in-memory copy can be newer than the file because heart-rate samples are saved only every few seconds).
    public func restore() {
        guard role == .authority, state == nil, let persistence else { return }
        guard let restored = persistence.loadActiveWorkout() else { return }
        state = restored
        lastHeartRateReport = nil
        onUpdate?()
        for effect in effects { effect.workoutStarted(restored) }
    }

    /// Starts a workout from `template`, or an empty one named `name` (default "Workout"), and tells the effects.
    ///
    /// Returns false (and changes nothing) while a workout is already in progress, so a double tap cannot replace a running workout.
    @discardableResult
    public func start(template: WorkoutTemplate?, name: String? = nil) -> Bool {
        guard state == nil else { return false }
        let now = clock()
        var started: WorkoutState
        if let template {
            started = WorkoutFactory.makeWorkout(from: template, now: now)
            for index in started.exercises.indices {
                started.exercises[index].exercise = refreshed(started.exercises[index].exercise)
            }
        } else {
            let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            started = WorkoutFactory.makeEmpty(name: trimmed.isEmpty ? StrengthConfig.defaultWorkoutName : trimmed, now: now)
        }
        state = started
        lastCompleted = nil
        lastHeartRateReport = nil
        pending.removeAll()
        authoritative = nil
        persistActiveWorkout()
        onUpdate?()
        for effect in effects { effect.workoutStarted(started) }
        return true
    }

    /// Applies `action`: reduce, save (authority only), publish, tell the effects. A change-free action does nothing.
    ///
    /// A mirror that applies an action of origin `.watch` also makes ONE `RemoteCommand` of it, keeps it in `pendingCommands`
    /// until the phone acknowledges it and tells the effects through `commandIssued` (after `workoutChanged`). Heart-rate samples
    /// make no command: they travel as their own message.
    public func send(_ action: WorkoutAction, origin: ActionOrigin = .phone) {
        guard let old = state else { return }
        let now = clock()
        var new = old
        WorkoutReducer.reduce(&new, action, now: now)
        guard new != old else { return }
        state = new

        let isHeartRate: Bool
        if case .updateHeartRate = action { isHeartRate = true } else { isHeartRate = false }
        if isHeartRate {
            if let last = lastHeartRateReport, now >= last, now.timeIntervalSince(last) < Self.heartRateInterval {
                onUpdate?()
                return
            }
            lastHeartRateReport = now
        }

        var issued: RemoteCommand?
        if role == .mirror, origin == .watch, !isHeartRate {
            let command = RemoteCommand(action: action, origin: .watch, issuedAt: now, workoutID: new.id)
            pending.append(command)
            if pending.count > SyncReconciler.pendingCapacity {
                pending.removeFirst(pending.count - SyncReconciler.pendingCapacity)
            }
            issued = command
        }

        persistActiveWorkout()
        onUpdate?()
        for effect in effects {
            effect.workoutChanged(from: old, to: new, action: action, origin: origin)
        }
        if let issued {
            for effect in effects { effect.commandIssued(issued) }
        }
    }

    /// Authority: runs a command from another surface once (a repeated command id is ignored) and acknowledges it. A mirror
    /// ignores commands.
    ///
    /// The id is acknowledged in every case: when the command changes the state, when it is a duplicate, and when it changes
    /// nothing (including a command that arrives without a workout). A command that names another workout than the one running
    /// (a late command of an earlier workout) is not applied either, but still acknowledged. `makeEnvelope(now:)` carries the
    /// acknowledgements; the caller sends an envelope even when the state did not change.
    public func receive(_ command: RemoteCommand) {
        guard role == .authority else { return }
        let isNew = seenCommands.insertIfNew(command.id)
        acknowledge(command.id)
        guard isNew else { return }
        if let target = command.workoutID, target != state?.id { return }
        send(command.action, origin: command.origin)
    }

    /// Authority: the envelope for the Watch. It carries the current state, or no state and the id of the workout that ended last,
    /// plus the ids of the most recent commands received (`SyncReconciler.acknowledgementWindow`). Send it after every change and
    /// after every received command, changed or not.
    ///
    /// A mirror has nothing to acknowledge; its envelope carries no acknowledgements.
    public func makeEnvelope(now: Date) -> SyncEnvelope {
        SyncEnvelope(
            state: state,
            endedWorkoutID: state == nil ? recentlyEnded.last : nil,
            sentAt: now,
            ackedCommandIDs: Array(acknowledged.suffix(SyncReconciler.acknowledgementWindow))
        )
    }

    /// Mirror: follows the phone. An envelope that carries a state is adopted when it is not stale, an envelope without a state
    /// ends the local workout (see the table below).
    ///
    /// Adopting (`SyncReconciler.shouldAdopt`): the phone's state becomes the base, the commands the envelope acknowledges and
    /// those older than `SyncReconciler.pendingLifetime` leave `pendingCommands`, and the rest is replayed on the base in order,
    /// so the Watch keeps showing its unacknowledged taps on top of the phone's truth. An envelope that changes nothing is not
    /// published.
    ///
    /// Never calls `workoutChanged` (no echo back to the phone). Calls `workoutStarted` when the envelope is for another workout
    /// than the one shown, `workoutEnded(_, completed: nil)` when the workout ends. An envelope for a workout that already ended is
    /// ignored.
    ///
    /// An envelope without a state (`endedWorkoutID` is the workout the phone says ended):
    ///
    /// | local workout | `endedWorkoutID` | effect |
    /// |---|---|---|
    /// | none | nil | nothing happens; nothing is remembered |
    /// | none | X | X is remembered, so a late state of X is ignored |
    /// | W | W | W ends and is remembered |
    /// | W | X, a different workout | W keeps running, X is remembered; unless the notice is newer than the last state adopted for W, then W is a ghost the Watch never heard ended and ends |
    /// | W | nil | the legacy notice "the phone has no workout": W ends but is NOT remembered, so the phone's next state for W is welcome |
    public func receive(_ envelope: SyncEnvelope) {
        guard role == .mirror else { return }
        if let incoming = envelope.state {
            adopt(incoming, from: envelope)
        } else {
            apply(endNoticeOf: envelope)
        }
    }

    /// Finishes the workout: builds the summary, records it (history, bests, template), clears the state and tells the effects.
    ///
    /// With `updateTemplate` the workout's template is rebuilt from the exercises as they are now. A workout with no logged set is
    /// discarded instead (nil is returned). A mirror finishes locally too.
    ///
    /// The workout is finished (and returned) even when the history cannot be written. The saved active workout is then kept
    /// instead of deleted and `lastPersistenceError` is set, so the logged sets are not lost: the next launch restores the workout
    /// and finishing it again saves it (a workout is recorded by its id, so it is never saved twice). Starting another workout
    /// replaces the kept file; until then the history is rewritten in full by the next successful save.
    @discardableResult
    public func finish(updateTemplate: Bool) -> CompletedWorkout? {
        guard let current = state else { return nil }
        let completed = SummaryBuilder.build(from: current, finishedAt: clock())
        guard completed.loggedSets > 0 else {
            end(current, completed: nil)
            return nil
        }
        var updated: WorkoutTemplate?
        if updateTemplate, let templateID = current.templateID, let template = data.template(id: templateID) {
            updated = WorkoutFactory.updatedTemplate(template, from: current)
        }
        var saveFailure: Error?
        if case let .failure(error) = data.record(completed, updateTemplate: updated) { saveFailure = error }
        lastCompleted = completed
        end(current, completed: completed, unsavedBecause: saveFailure)
        return completed
    }

    /// Throws the workout away without recording it and tells the effects (`completed == nil`).
    public func discard() {
        guard let current = state else { return }
        end(current, completed: nil)
    }

    // MARK: Derived values

    /// The active-workout screen model for `now`; nil without a workout.
    public func presentation(now: Date) -> ActiveWorkoutPresentation? {
        state.map { WorkoutPresenter.present($0, now: now, recovery: recovery) }
    }

    /// The Live Activity / Watch snapshot for `now`; nil without a workout.
    public func snapshot(now: Date) -> WorkoutSnapshot? {
        state.map { SnapshotBuilder.make(from: $0, now: now) }
    }

    /// What changed against the template the workout started from (empty without a workout).
    public func templateDiff() -> TemplateDiff {
        state.map { TemplateDiff.compute(for: $0) } ?? TemplateDiff()
    }

    // MARK: Helpers

    /// Adopts the phone's `incoming` state (mirror), see `receive(_: SyncEnvelope)`.
    private func adopt(_ incoming: WorkoutState, from envelope: SyncEnvelope) {
        guard !recentlyEnded.contains(incoming.id) else { return }
        guard SyncReconciler.shouldAdopt(incoming: incoming, authoritativeRevision: authoritativeRevision, currentWorkoutID: state?.id)
        else { return }

        let isNewWorkout = state?.id != incoming.id
        if isNewWorkout { pending.removeAll() }
        pending = SyncReconciler.remainingPending(pending, acknowledged: envelope.ackedCommandIDs, now: clock())
        let shown = SyncReconciler.rebase(incoming, replaying: pending)

        let previous = state
        let previousSentAt = isNewWorkout ? nil : authoritative?.sentAt
        authoritative = AuthoritativeMark(
            workoutID: incoming.id,
            revision: incoming.revision,
            sentAt: max(envelope.sentAt, previousSentAt ?? envelope.sentAt)
        )
        state = shown
        if isNewWorkout {
            lastCompleted = nil
            lastHeartRateReport = nil
        }
        if isNewWorkout || shown != previous { onUpdate?() }
        if isNewWorkout {
            for effect in effects { effect.workoutStarted(shown) }
        }
    }

    /// Applies an envelope without a state (mirror), see the table at `receive(_: SyncEnvelope)`.
    private func apply(endNoticeOf envelope: SyncEnvelope) {
        guard let previous = state else {
            if let ended = envelope.endedWorkoutID { remember(ended) }
            return
        }
        guard let ended = envelope.endedWorkoutID else {
            // The phone says only "no workout": whatever runs here ends, but the next state for it is welcome.
            end(previous, completed: nil, remembering: false)
            return
        }
        if ended != previous.id {
            remember(ended)
            // A notice that is newer than everything adopted for the running workout means the phone has moved on: the Watch
            // never heard that this workout ended. An older notice belongs to an earlier workout and changes nothing.
            guard let mark = authoritative, mark.workoutID == previous.id, envelope.sentAt > mark.sentAt else { return }
        }
        end(previous, completed: nil)
    }

    /// Authority: remembers that the command was dealt with; a repeated id moves to the most recent position.
    private func acknowledge(_ id: UUID) {
        if let index = acknowledged.lastIndex(of: id) { acknowledged.remove(at: index) }
        acknowledged.append(id)
        if acknowledged.count > SyncReconciler.acknowledgedMemory {
            acknowledged.removeFirst(acknowledged.count - SyncReconciler.acknowledgedMemory)
        }
    }

    /// Ends the workout. With `unsavedBecause` (the finished workout could not be written to the history) the active-workout file
    /// is left alone: it still holds the workout's sets and is the only copy on disk. With `remembering` false the workout's id
    /// is not added to the ended workouts, so a later state for it is not ignored.
    private func end(
        _ previous: WorkoutState,
        completed: CompletedWorkout?,
        unsavedBecause saveFailure: Error? = nil,
        remembering: Bool = true
    ) {
        state = nil
        pending.removeAll()
        authoritative = nil
        if remembering { remember(previous.id) }
        lastHeartRateReport = nil
        if let saveFailure {
            lastPersistenceError = saveFailure
        } else {
            persistActiveWorkout()
        }
        onUpdate?()
        for effect in effects { effect.workoutEnded(previous, completed: completed) }
    }

    private func remember(_ id: UUID) {
        recentlyEnded.removeAll { $0 == id }
        recentlyEnded.append(id)
        if recentlyEnded.count > Self.endedMemory { recentlyEnded.removeFirst(recentlyEnded.count - Self.endedMemory) }
    }

    /// Writes the active workout (or deletes the file when there is none); only the authority persists.
    private func persistActiveWorkout() {
        guard role == .authority, let persistence else { return }
        do {
            try persistence.saveActiveWorkout(state)
            lastPersistenceError = nil
        } catch {
            lastPersistenceError = error
        }
    }

    /// The template's exercise with the latest remembered best and last sets (everything else stays as the template has it).
    private func refreshed(_ exercise: Exercise) -> Exercise {
        guard let latest = data.exercise(id: exercise.id) else { return exercise }
        var result = exercise
        result.previousBestE1RM = latest.previousBestE1RM
        result.previousSets = latest.previousSets
        return result
    }
}
