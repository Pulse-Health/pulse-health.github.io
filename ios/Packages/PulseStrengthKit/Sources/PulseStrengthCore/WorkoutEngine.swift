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
///
/// Delivery is unreliable, so the engine also orders what it hears: the mirror ignores a phone envelope of another workout that
/// is older than the newest one it applied, and an end notice only blocks the states sent before it; the authority drops an
/// absolute edit that was overtaken by a newer edit of the same value, runs a late command at the time of the tap and remembers
/// the commands it dealt with across a relaunch.
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

    /// How the workout that ended most recently ended: true when it was thrown away, false when it was finished and recorded.
    /// Set before `onUpdate` and the effects' `workoutEnded` run, so an effect can read it from inside `workoutEnded` (a mirror
    /// is always told `completed: nil`, which does not say which of the two it was).
    ///
    /// Authority: `discard()` and a `finish` with no logged set are discards. Mirror: what the phone's end notice says
    /// (`SyncEnvelope.discarded`); a notice that does not say (an older phone build, the legacy "no workout" notice, a workout
    /// the Watch never heard ended) counts as a discard when the Watch's copy has no logged set, the rule by which the phone
    /// treats a finish. Meaningless before the first workout ended.
    public private(set) var lastEndDiscarded = false

    /// Mirror: when the phone sent the envelope that ended the workout that ended most recently (the phone's clock). It is the
    /// moment the phone ended the workout, which can be long before the Watch learned of it (the phone finished while the link
    /// was down), so the Watch ends its Health workout then and not when the notice arrived. Set before `onUpdate` and the
    /// effects' `workoutEnded` run, like `lastEndDiscarded`. nil when the workout ended here (`finish`, `discard`, every
    /// authority end); an envelope that was ignored (a stale notice) does not set it.
    public private(set) var lastEndNoticeSentAt: Date?

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
    /// Mirror: for an ended workout, when the phone's end notice was sent (`.distantFuture` for a workout the Watch ended itself).
    /// A state of that workout sent after the notice is the phone restoring it, a state sent before is a late message.
    private var endNoticeSentAt: [UUID: Date] = [:]
    /// Mirror: the newest `sentAt` of any phone envelope applied so far, state or end notice. It survives the end of a workout.
    private var newestSentAt: Date?

    /// Authority: the ids of the commands it has dealt with (applied, duplicate or without effect), oldest first, at most
    /// `SyncReconciler.acknowledgedMemory`. The most recent ones go out in every envelope.
    private var acknowledged: [UUID] = []
    /// Mirror: the edits applied locally that the phone has not acknowledged yet, oldest first.
    private var pending: [RemoteCommand] = []
    /// Mirror: what the last adopted phone state of the running workout looked like.
    private var authoritative: AuthoritativeMark?
    /// Mirror: the last adopted phone state of the running workout itself, without the unacknowledged edits on top.
    private var authoritativeBase: WorkoutState?
    /// Mirror: the pending commands the transport holds in its guaranteed queue (`markQueued(commandID:)`); they keep their edit
    /// longer. Always a subset of `pending`.
    private var queuedCommands = Set<UUID>()
    /// Mirror: identifies this engine in the commands it makes; `nextSequence` is the number of the last one.
    private let senderID = UUID()
    private var nextSequence = 0
    /// Mirror: commands made but not yet announced to the effects, oldest first; `sendDepth` counts the `send` calls in progress.
    private var issuedQueue: [RemoteCommand] = []
    private var sendDepth = 0
    /// Authority: for each value a Watch command sets (see `EditKey`), the newest command applied, and the keys in the order they
    /// were first seen (at most `Self.editMemory`).
    private var newestEdit: [EditKey: EditMark] = [:]
    private var newestEditOrder: [EditKey] = []

    /// How many different values the authority remembers the newest command of.
    private static let editMemory = 128

    /// A value that a single absolute action sets: the same value set twice means the later command wins.
    private struct EditKey: Hashable {
        var kind: Int
        var exerciseID: UUID
        var setID: UUID?

        init?(_ action: WorkoutAction) {
            switch action {
            case let .setWeight(exercise, set, _): self.init(kind: 0, exerciseID: exercise, setID: set)
            case let .setReps(exercise, set, _): self.init(kind: 1, exerciseID: exercise, setID: set)
            case let .setSetType(exercise, set, _): self.init(kind: 2, exerciseID: exercise, setID: set)
            case let .setRIR(exercise, set, _): self.init(kind: 3, exerciseID: exercise, setID: set)
            case let .setNote(exercise, _): self.init(kind: 4, exerciseID: exercise, setID: nil)
            case let .setRest(exercise, _): self.init(kind: 5, exerciseID: exercise, setID: nil)
            default: return nil
            }
        }

        private init(kind: Int, exerciseID: UUID, setID: UUID?) {
            self.kind = kind
            self.exerciseID = exerciseID
            self.setID = setID
        }
    }

    /// The newest command applied for an `EditKey`: who sent it and its number.
    private struct EditMark {
        var sender: UUID
        var sequence: Int
    }

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
    ///
    /// The acknowledged command ids are restored too (whether or not a workout is saved): a command that was applied before the
    /// relaunch is acknowledged again by the next envelope and is not applied a second time when it is redelivered.
    public func restore() {
        guard role == .authority, state == nil, let persistence else { return }
        restoreAcknowledgements(from: persistence)
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
        setPending([])
        authoritative = nil
        authoritativeBase = nil
        persistActiveWorkout()
        onUpdate?()
        for effect in effects { effect.workoutStarted(started) }
        return true
    }

    /// Applies `action`: reduce, save (authority only), publish, tell the effects. A change-free action does nothing.
    ///
    /// A mirror that applies an action of origin `.watch` also makes ONE `RemoteCommand` of it, numbers it (`senderID`,
    /// `sequence`), keeps it in `pendingCommands` until the phone acknowledges it and tells the effects through `commandIssued`
    /// (after `workoutChanged`). Heart-rate samples make no command: they travel as their own message.
    ///
    /// The commands are announced in the order they were made, also when an effect edits from inside `workoutChanged` or
    /// `commandIssued`: a nested `send` is announced after the one that is in progress.
    public func send(_ action: WorkoutAction, origin: ActionOrigin = .phone) {
        let now = clock()
        apply(action, origin: origin, now: now, reducingAt: now)
    }

    /// `send`, with the time the reducer sees (`reducingAt`) apart from the engine's now: an authority that runs a late command
    /// reduces it at the time of the tap.
    private func apply(_ action: WorkoutAction, origin: ActionOrigin, now: Date, reducingAt reducerTime: Date) {
        guard let old = state else { return }
        var new = old
        WorkoutReducer.reduce(&new, action, now: reducerTime)
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

        if role == .mirror, origin == .watch, !isHeartRate {
            nextSequence += 1
            let command = RemoteCommand(
                action: action, origin: .watch, issuedAt: now, workoutID: new.id, senderID: senderID, sequence: nextSequence
            )
            var kept = pending
            kept.append(command)
            if kept.count > SyncReconciler.pendingCapacity {
                kept.removeFirst(kept.count - SyncReconciler.pendingCapacity)
            }
            setPending(kept)
            issuedQueue.append(command)
        }

        sendDepth += 1
        persistActiveWorkout()
        onUpdate?()
        for effect in effects {
            effect.workoutChanged(from: old, to: new, action: action, origin: origin)
        }
        sendDepth -= 1
        announceIssuedCommands()
    }

    /// Tells the effects about the commands made so far, oldest first, once no `send` is in progress. A `send` made by an effect
    /// while it is told only appends to the queue; the loop picks it up after the command being announced.
    private func announceIssuedCommands() {
        guard sendDepth == 0, !issuedQueue.isEmpty else { return }
        sendDepth += 1
        defer { sendDepth -= 1 }
        while !issuedQueue.isEmpty {
            let command = issuedQueue.removeFirst()
            for effect in effects { effect.commandIssued(command) }
        }
    }

    /// Authority: runs a command from another surface once (a repeated command id is ignored) and acknowledges it. A mirror
    /// ignores commands.
    ///
    /// The id is acknowledged in every case: when the command changes the state, when it is a duplicate, and when it changes
    /// nothing (including a command that arrives without a workout). A command that names another workout than the one running
    /// (a late command of an earlier workout) is not applied either, but still acknowledged. `makeEnvelope(now:)` carries the
    /// acknowledgements; the caller sends an envelope even when the state did not change.
    ///
    /// Two more cases are acknowledged without effect or with a different time:
    /// * An absolute edit (a weight, the reps, a set type, a RIR, a note, a rest time) that a NEWER command of the same sender
    ///   already set again is dropped: the Watch's two channels have no common order, so the older command can arrive last.
    ///   Cumulative actions (nudges, rest adjustments) are not ordered.
    /// * A command that reaches the phone up to `SyncReconciler.lateCommandWindow` after the Watch stamped it acts at the time of
    ///   the tap (the rest timer starts then, as the Watch showed it); a stamp further in the past or in the future is not trusted.
    ///
    /// The acknowledgements are saved after the state was (see `restore()`): a crash in between can only apply the command again,
    /// never lose it.
    public func receive(_ command: RemoteCommand) {
        guard role == .authority else { return }
        let isNew = seenCommands.insertIfNew(command.id)
        acknowledge(command.id)
        defer { saveAcknowledgements() }
        guard isNew else { return }
        if let target = command.workoutID, target != state?.id { return }
        guard !isSuperseded(command) else { return }
        let now = clock()
        let age = now.timeIntervalSince(command.issuedAt)
        var reducerTime = now
        if age > 0, age <= SyncReconciler.lateCommandWindow, !isHeartRate(command.action) { reducerTime = command.issuedAt }
        apply(command.action, origin: command.origin, now: now, reducingAt: reducerTime)
    }

    private func isHeartRate(_ action: WorkoutAction) -> Bool {
        if case .updateHeartRate = action { return true }
        return false
    }

    /// Authority: the envelope for the Watch. It carries the current state, or no state and the id of the workout that ended last,
    /// plus the ids of the most recent commands received (`SyncReconciler.acknowledgementWindow`). Send it after every change and
    /// after every received command, changed or not.
    ///
    /// An envelope that names the ended workout also says how it ended (`SyncEnvelope.discarded`), so the Watch can throw its
    /// Health session away for a discard instead of saving it.
    ///
    /// A mirror has nothing to acknowledge; its envelope carries no acknowledgements.
    public func makeEnvelope(now: Date) -> SyncEnvelope {
        let ended = state == nil ? recentlyEnded.last : nil
        return SyncEnvelope(
            state: state,
            endedWorkoutID: ended,
            sentAt: now,
            ackedCommandIDs: Array(acknowledged.suffix(SyncReconciler.acknowledgementWindow)),
            discarded: ended == nil ? nil : lastEndDiscarded
        )
    }

    /// Mirror: follows the phone. An envelope that carries a state is adopted when it is not stale, an envelope without a state
    /// ends the local workout (see the table below).
    ///
    /// Adopting (`SyncReconciler.shouldAdopt`): the phone's state becomes the base, the commands the envelope acknowledges and
    /// those older than their lifetime (`SyncReconciler.pendingLifetime`, or `queuedPendingLifetime` for a command the transport
    /// queued) leave `pendingCommands`, and the rest is replayed on the base in order, so the Watch keeps showing its
    /// unacknowledged taps on top of the phone's truth. An envelope that changes nothing is not published. An envelope that comes
    /// from a phone build without acknowledgements (`SyncEnvelope.isFromLegacyPhone`) drops every pending edit: nothing will ever
    /// acknowledge them, so the phone's state wins, as it did before acknowledgements existed.
    ///
    /// Ordering. An envelope for ANOTHER workout than the one shown is ignored when it was sent up to
    /// `SyncReconciler.staleEnvelopeWindow` before the newest envelope applied so far (a late or replayed message of an earlier
    /// workout; `newestSentAt` survives the end of a workout). An envelope for a workout that ended is ignored when it was sent
    /// before (or when) the phone's end notice was: a state sent after the notice is the phone restoring the workout (its history
    /// write failed and the next launch restored it), and is adopted. A workout the Watch ended itself stays ended.
    ///
    /// Never calls `workoutChanged` (no echo back to the phone). Calls `workoutStarted` when the envelope is for another workout
    /// than the one shown, `workoutEnded(_, completed: nil)` when the workout ends.
    ///
    /// An envelope without a state (`endedWorkoutID` is the workout the phone says ended):
    ///
    /// | local workout | `endedWorkoutID` | effect |
    /// |---|---|---|
    /// | none | nil | nothing happens; nothing is remembered |
    /// | none | X | X is remembered, so a late state of X (sent before the notice) is ignored |
    /// | W | W | W ends and is remembered |
    /// | W | X, a different workout | W keeps running, X is remembered; unless the notice is newer than the last state adopted for W, then W is a ghost the Watch never heard ended and ends |
    /// | W | nil | the legacy notice "the phone has no workout": W ends but is NOT remembered, so the phone's next state for W is welcome; unless the notice was sent BEFORE the last state adopted for W (a stale context re-read after W was adopted), then it is ignored |
    ///
    /// When a workout ends here, `lastEndDiscarded` tells the effects whether the phone threw it away.
    public func receive(_ envelope: SyncEnvelope) {
        guard role == .mirror else { return }
        if let incoming = envelope.state {
            adopt(incoming, from: envelope)
        } else {
            apply(endNoticeOf: envelope)
        }
    }

    /// Mirror: tells the engine that the transport holds the command `commandID` in its guaranteed queue (WatchConnectivity's
    /// `transferUserInfo`, used while the phone is out of reach): the phone gets it whenever it is back, however late. Its edit
    /// then stays shown for `SyncReconciler.queuedPendingLifetime` instead of `pendingLifetime`, so the sets the user logs while
    /// the phone is away do not vanish from the Watch after 15 seconds. Does nothing for a command that is not pending.
    public func markQueued(commandID: UUID) {
        guard role == .mirror, pending.contains(where: { $0.id == commandID }) else { return }
        queuedCommands.insert(commandID)
    }

    /// Mirror: when the oldest unacknowledged edit stops being shown (its issue time plus its lifetime; it is dropped once this
    /// moment has passed). nil without a pending edit and for an authority. Call `expirePending()` then.
    public var nextPendingExpiry: Date? {
        guard role == .mirror else { return nil }
        return pending.map { $0.issuedAt.addingTimeInterval(SyncReconciler.lifetime(of: $0, queued: queuedCommands)) }.min()
    }

    /// Mirror: drops the unacknowledged edits that are older than their lifetime and shows the phone's last state with the
    /// remaining edits on top. Adopting an envelope does this too, but a command that really got lost makes the phone change
    /// nothing and send nothing, so no envelope would ever come: whoever sends the commands calls this when `nextPendingExpiry`
    /// has passed. Keeps the Watch's own heart rate. Returns true when at least one edit was dropped (the shown state may be
    /// the same then, and the phone's copy of it can be out of date: ask the phone for its state).
    @discardableResult
    public func expirePending() -> Bool {
        guard role == .mirror, !pending.isEmpty else { return false }
        let kept = SyncReconciler.remainingPending(pending, acknowledged: [], now: clock(), queued: queuedCommands)
        guard kept.count != pending.count else { return false }
        setPending(kept)
        guard let base = authoritativeBase, let current = state, base.id == current.id else { return true }
        var shown = SyncReconciler.rebase(base, replaying: kept)
        shown.heartRate = current.heartRate
        shown.heartRateSum = current.heartRateSum
        shown.heartRateCount = current.heartRateCount
        if shown != current {
            state = shown
            onUpdate?()
        }
        return true
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
        // A workout that ended stays ended for the messages sent before its end notice (or that the Watch ended itself).
        if recentlyEnded.contains(incoming.id), envelope.sentAt <= (endNoticeSentAt[incoming.id] ?? .distantFuture) { return }
        guard SyncReconciler.shouldAdopt(incoming: incoming, authoritativeRevision: authoritativeRevision, currentWorkoutID: state?.id)
        else { return }

        let isNewWorkout = state?.id != incoming.id
        if isNewWorkout, isOlderThanNewestApplied(envelope.sentAt) { return }
        noteApplied(sentAt: envelope.sentAt)

        if isNewWorkout || envelope.isFromLegacyPhone { setPending([]) }
        setPending(SyncReconciler.remainingPending(
            pending, acknowledged: envelope.ackedCommandIDs, now: clock(), queued: queuedCommands
        ))
        let shown = SyncReconciler.rebase(incoming, replaying: pending)

        let previous = state
        let previousSentAt = isNewWorkout ? nil : authoritative?.sentAt
        authoritative = AuthoritativeMark(
            workoutID: incoming.id,
            revision: incoming.revision,
            sentAt: max(envelope.sentAt, previousSentAt ?? envelope.sentAt)
        )
        authoritativeBase = incoming
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

    /// True when an envelope sent at `sentAt` is older than the newest one applied, by no more than the stale window.
    private func isOlderThanNewestApplied(_ sentAt: Date) -> Bool {
        guard let newest = newestSentAt, sentAt < newest else { return false }
        return newest.timeIntervalSince(sentAt) <= SyncReconciler.staleEnvelopeWindow
    }

    private func noteApplied(sentAt: Date) {
        newestSentAt = max(sentAt, newestSentAt ?? sentAt)
    }

    /// Applies an envelope without a state (mirror), see the table at `receive(_: SyncEnvelope)`.
    private func apply(endNoticeOf envelope: SyncEnvelope) {
        noteApplied(sentAt: envelope.sentAt)
        guard let previous = state else {
            if let ended = envelope.endedWorkoutID { remember(ended, noticeSentAt: envelope.sentAt) }
            return
        }
        // Without a flag from the phone, a workout with no logged set counts as discarded (the phone's own rule for a finish).
        let unlogged = !Self.hasLoggedSet(previous)
        guard let ended = envelope.endedWorkoutID else {
            // The phone says only "no workout": whatever runs here ends, but the next state for it is welcome. A notice sent
            // before the state last adopted for this workout is a stale context that was read again (the Watch re-reads the
            // last delivered one whenever it wakes, and it can lag behind a message): the workout started after it was written.
            if let mark = authoritative, mark.workoutID == previous.id, envelope.sentAt < mark.sentAt { return }
            end(previous, completed: nil, remembering: false, noticeSentAt: envelope.sentAt, discarded: unlogged)
            return
        }
        var discarded = envelope.discarded
        if ended != previous.id {
            remember(ended, noticeSentAt: envelope.sentAt)
            // A notice that is newer than everything adopted for the running workout means the phone has moved on: the Watch
            // never heard that this workout ended. An older notice belongs to an earlier workout and changes nothing.
            guard let mark = authoritative, mark.workoutID == previous.id, envelope.sentAt > mark.sentAt else { return }
            // The flag tells how the OTHER workout ended; nothing says how this one did.
            discarded = nil
        }
        end(previous, completed: nil, noticeSentAt: envelope.sentAt, discarded: discarded ?? unlogged)
    }

    /// True when at least one set of the workout is logged.
    private static func hasLoggedSet(_ state: WorkoutState) -> Bool {
        state.exercises.contains { entry in entry.sets.contains { $0.isDone } }
    }

    /// Mirror: replaces the pending edits and forgets the queue marks of the commands that are gone.
    private func setPending(_ commands: [RemoteCommand]) {
        pending = commands
        if !queuedCommands.isEmpty { queuedCommands.formIntersection(commands.map { $0.id }) }
    }

    /// Authority: true when a NEWER command of the same sender already set the same value (the older one arrived last, over the
    /// other channel). Otherwise remembers this command as the newest for its value.
    private func isSuperseded(_ command: RemoteCommand) -> Bool {
        guard let sender = command.senderID, let sequence = command.sequence, let key = EditKey(command.action) else { return false }
        if let newest = newestEdit[key], newest.sender == sender, newest.sequence > sequence { return true }
        if newestEdit[key] == nil {
            newestEditOrder.append(key)
            if newestEditOrder.count > Self.editMemory { newestEdit[newestEditOrder.removeFirst()] = nil }
        }
        newestEdit[key] = EditMark(sender: sender, sequence: sequence)
        return false
    }

    /// Authority: loads the acknowledged command ids saved before the relaunch (unless commands were received already).
    private func restoreAcknowledgements(from persistence: FileStrengthPersistence) {
        guard acknowledged.isEmpty else { return }
        acknowledged = persistence.loadAcknowledgedCommands()
        for id in acknowledged { _ = seenCommands.insertIfNew(id) }
    }

    /// Authority: saves the acknowledged command ids; a failure is ignored (the worst case is a command applied again after a
    /// relaunch, which is what happened before they were saved at all).
    private func saveAcknowledgements() {
        guard role == .authority else { return }
        try? persistence?.saveAcknowledgedCommands(acknowledged)
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
    /// is not added to the ended workouts, so a later state for it is not ignored. `noticeSentAt` is when the phone's end notice
    /// was sent (nil: the workout ended here, nothing sent later revives it); it is also what `lastEndNoticeSentAt` reports, and it
    /// is given for the legacy "no workout" notice too, which is not remembered. `discarded` is how it ended (`lastEndDiscarded`);
    /// nil: it was discarded exactly when there is no `completed` workout.
    private func end(
        _ previous: WorkoutState,
        completed: CompletedWorkout?,
        unsavedBecause saveFailure: Error? = nil,
        remembering: Bool = true,
        noticeSentAt: Date? = nil,
        discarded: Bool? = nil
    ) {
        lastEndDiscarded = discarded ?? (completed == nil)
        lastEndNoticeSentAt = noticeSentAt
        state = nil
        setPending([])
        authoritative = nil
        authoritativeBase = nil
        if remembering { remember(previous.id, noticeSentAt: noticeSentAt) }
        lastHeartRateReport = nil
        if let saveFailure {
            lastPersistenceError = saveFailure
        } else {
            persistActiveWorkout()
        }
        onUpdate?()
        for effect in effects { effect.workoutEnded(previous, completed: completed) }
    }

    /// Remembers that the workout ended. `noticeSentAt` is when the phone sent the end notice (nil: it ended here); a repeated
    /// notice never lowers the time, so a duplicate of an older notice cannot reopen the workout to late messages.
    private func remember(_ id: UUID, noticeSentAt: Date? = nil) {
        let known = recentlyEnded.contains(id) ? endNoticeSentAt[id] : nil
        let sentAt = noticeSentAt ?? .distantFuture
        recentlyEnded.removeAll { $0 == id }
        recentlyEnded.append(id)
        endNoticeSentAt[id] = max(known ?? sentAt, sentAt)
        while recentlyEnded.count > Self.endedMemory {
            endNoticeSentAt[recentlyEnded.removeFirst()] = nil
        }
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

    /// The template's exercise brought up to date: a built-in exercise is the library's current one (name, cues, media, ...), any
    /// exercise gets the latest remembered best and last sets. Nothing else of a custom exercise changes (the store refreshes the
    /// template copies when the exercise is edited).
    private func refreshed(_ exercise: Exercise) -> Exercise {
        guard let latest = data.exercise(id: exercise.id) else { return exercise }
        var result = ExerciseLibrary.exercise(id: exercise.id) != nil ? latest : exercise
        result.previousBestE1RM = latest.previousBestE1RM
        result.previousSets = latest.previousSets
        return result
    }
}
