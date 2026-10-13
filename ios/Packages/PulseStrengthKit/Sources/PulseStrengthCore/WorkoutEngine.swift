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
    func record(_ completed: CompletedWorkout, updateTemplate: WorkoutTemplate?)
}

// MARK: - Engine

/// The platform-neutral heart of `WorkoutController`: owns the workout in progress and runs every change through the reducer.
///
/// The engine has no Combine dependency. After each change it calls `onUpdate` (so a wrapper can publish) and then tells the
/// registered side effects. Heart-rate samples are applied to the in-memory state every time, but they are saved and reported to
/// the effects at most once per `heartRateInterval` seconds of the injected clock.
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
    /// The error of the last failed attempt to save the active workout; nil after a successful save.
    public private(set) var lastPersistenceError: Error?
    /// Called after `state` or `lastCompleted` changed and before the side effects are told.
    public var onUpdate: (() -> Void)?

    private let persistence: FileStrengthPersistence?
    private let data: WorkoutDataProviding
    private let clock: @Sendable () -> Date
    private var seenCommands = SeenCommands()
    private var effects: [WorkoutSideEffect] = []
    private var lastHeartRateReport: Date?
    private var recentlyEnded: [UUID] = []

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
        persistActiveWorkout()
        onUpdate?()
        for effect in effects { effect.workoutStarted(started) }
        return true
    }

    /// Applies `action`: reduce, save (authority only), publish, tell the effects. A change-free action does nothing.
    public func send(_ action: WorkoutAction, origin: ActionOrigin = .phone) {
        guard let old = state else { return }
        let now = clock()
        var new = old
        WorkoutReducer.reduce(&new, action, now: now)
        guard new != old else { return }
        state = new

        if case .updateHeartRate = action {
            if let last = lastHeartRateReport, now >= last, now.timeIntervalSince(last) < Self.heartRateInterval {
                onUpdate?()
                return
            }
            lastHeartRateReport = now
        }

        persistActiveWorkout()
        onUpdate?()
        for effect in effects {
            effect.workoutChanged(from: old, to: new, action: action, origin: origin)
        }
    }

    /// Authority: runs a command from another surface once (a repeated command id is ignored). A mirror ignores commands.
    public func receive(_ command: RemoteCommand) {
        guard role == .authority else { return }
        guard seenCommands.insertIfNew(command.id) else { return }
        send(command.action, origin: command.origin)
    }

    /// Mirror: adopts the phone's workout when it is newer, or ends the local one when the envelope carries no state.
    ///
    /// Never calls `workoutChanged` (no echo back to the phone). An envelope for a workout that already ended is ignored.
    public func receive(_ envelope: SyncEnvelope) {
        guard role == .mirror else { return }
        if let incoming = envelope.state {
            guard !recentlyEnded.contains(incoming.id), SyncReconciler.isNewer(incoming, than: state) else { return }
            let isNewWorkout = state?.id != incoming.id
            state = incoming
            if isNewWorkout {
                lastCompleted = nil
                lastHeartRateReport = nil
            }
            onUpdate?()
            if isNewWorkout {
                for effect in effects { effect.workoutStarted(incoming) }
            }
        } else {
            guard let previous = state else {
                if let ended = envelope.endedWorkoutID { remember(ended) }
                return
            }
            if let ended = envelope.endedWorkoutID, ended != previous.id {
                remember(ended)
                return
            }
            end(previous, completed: nil)
        }
    }

    /// Finishes the workout: builds the summary, records it (history, bests, template), clears the state and tells the effects.
    ///
    /// With `updateTemplate` the workout's template is rebuilt from the exercises as they are now. A workout with no logged set is
    /// discarded instead (nil is returned). A mirror finishes locally too.
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
        data.record(completed, updateTemplate: updated)
        lastCompleted = completed
        end(current, completed: completed)
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

    private func end(_ previous: WorkoutState, completed: CompletedWorkout?) {
        state = nil
        remember(previous.id)
        lastHeartRateReport = nil
        persistActiveWorkout()
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
