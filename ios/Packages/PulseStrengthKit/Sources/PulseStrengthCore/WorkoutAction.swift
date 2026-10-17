import Foundation

/// Everything that can change a workout. The reducer (`WorkoutReducer`) is the only code
/// that applies these. Actions are Codable so the Watch and Live Activity can send them.
public enum WorkoutAction: Codable, Hashable, Sendable {
    // MARK: Set logging
    /// Tap on a set's check circle: toggles done / not done (starts rest when becoming done).
    case toggleSet(exerciseID: UUID, setID: UUID)
    /// Idempotent: marks a pending set done (same side effects as toggle); no-op if already done.
    case logSet(exerciseID: UUID, setID: UUID)
    /// Logs the next pending set (see `WorkoutTargets.nextPending`), moving to its exercise first.
    case logNextSet
    case setWeight(exerciseID: UUID, setID: UUID, kg: Double)
    case setReps(exerciseID: UUID, setID: UUID, reps: Int)
    /// Adjusts the next pending set: weight by `weightSteps` x `Exercise.weightStep(in:)` (in the workout's unit) and
    /// reps by `repsSteps` x Exercise.repsStep. Used by the Watch and the Live Activity.
    case nudgeNextSet(weightSteps: Int, repsSteps: Int)
    case setSetType(exerciseID: UUID, setID: UUID, type: SetType)
    /// Explicit reps-in-reserve value (nil clears it). Used by the set sheet.
    case setRIR(exerciseID: UUID, setID: UUID, rir: Int?)
    /// Rest-dock chips: applies to `lastLogged`; selecting the already selected value clears it.
    case toggleLastSetRIR(Int)
    case addSet(exerciseID: UUID)
    case deleteSet(exerciseID: UUID, setID: UUID)
    case setNote(exerciseID: UUID, note: String)

    // MARK: Timed sets
    /// Starts timing a pending set of an exercise that tracks duration (ignored for any other set, and while a timed set already
    /// runs): the stopwatch counts towards the set's seconds, `currentIndex` moves to its exercise and a running rest ends.
    case startTimedSet(SetRef)
    /// Logs the running timed set with the seconds timed so far (at most `WorkoutReducer.maximumDurationSeconds`); from there it is
    /// `logSet`: the rest after it follows the normal rules. Ignored without a running timed set.
    case stopTimedSet
    /// Drops the running timed set without logging anything.
    case cancelTimedSet

    // MARK: Navigation
    case goTo(index: Int)
    case nextExercise
    case previousExercise

    // MARK: Exercise list editing
    case addExercises([Exercise])
    case removeExercise(exerciseID: UUID)
    case moveExercise(from: Int, to: Int)
    case moveExerciseBy(exerciseID: UUID, delta: Int)
    case replaceExercise(exerciseID: UUID, with: Exercise)
    /// Joins the exercise with the next one in a superset, or removes it from its superset.
    case toggleSuperset(exerciseID: UUID)
    /// Per-exercise rest seconds; 0 turns the timer off for this exercise.
    case setRest(exerciseID: UUID, seconds: Int)

    // MARK: Rest timer
    case adjustRest(seconds: Int)
    case skipRest
    case setAutoStartRest(Bool)
    case setAlertWhenRestEnds(Bool)

    // MARK: Display
    /// The unit weights are shown and typed in (the Watch and the Live Activity follow it). Stored weights stay in kilograms.
    case setWeightUnit(WeightUnit)

    // MARK: Lifecycle
    case pause
    case resume
    /// Restores the last removed or replaced exercise / deleted set if its undo window is still open.
    case undo
    case updateHeartRate(Int?)
    case setUsedWatch(Bool)
    case rename(String)
}

/// Who initiated an action (used by side effects to avoid echoing it back).
public enum ActionOrigin: String, Codable, Hashable, Sendable {
    case phone
    case watch
    case liveActivity
    case system
}
