package health.pulse.strength.core

import com.google.common.truth.Truth.assertThat
import com.google.common.truth.Truth.assertWithMessage
import java.time.Instant
import java.util.UUID
import org.junit.Test

// Port of WorkoutReducerTests.swift.
//
// Swift `WorkoutReducer.reduce(&state, action, now:)` is `state = WorkoutReducer.reduce(state, action, now)` here; Swift
// `s.field = x` on a value is `s = s.copy(field = x)`. Time arguments are `Number` seconds after `RedFix.t0`.

// region Fixtures shared by the reducer, factory and fuzz tests

/** Deterministic fixtures (no clock, no randomness) for the reducer test files. Mirrors Swift `RedFix`. */
internal object RedFix {
    /** The fake "start of the workout". */
    val t0: Instant = Instant.ofEpochSecond(1_800_000_000L)

    /** `t0` plus `seconds`. */
    fun at(seconds: Number): Instant = t0.addingTimeInterval(seconds.toDouble())

    /** A stable UUID built from two numbers. */
    fun uuid(high: Int, low: Int): UUID {
        fun hex(value: Int, width: Int): String = Integer.toHexString(value).padStart(width, '0')
        return UUID.fromString("00000000-0000-0000-${hex(high, 4)}-${hex(low, 12)}")
    }

    // region Exercises

    fun exercise(
        id: String,
        name: String,
        muscle: MuscleGroup,
        equipment: Equipment,
        tracking: TrackingKind = TrackingKind.WEIGHT_REPS,
        best: Double = 0.0,
        sets: Int = 3,
        kg: Double,
        reps: Int,
        rest: Int,
    ): Exercise = Exercise(
        id = id, name = name, muscle = muscle, secondary = "", equipment = equipment, tracking = tracking,
        mediaKey = null, previousBestE1RM = best, previousSets = emptyList(),
        defaults = ExerciseDefaults(sets = sets, weightKg = kg, reps = reps, restSeconds = rest),
        cues = emptyList(), barKg = 20.0, isCustom = false,
    )

    val bench: Exercise = exercise("bench", "Barbell bench press", MuscleGroup.CHEST, Equipment.BARBELL, best = 99.0, kg = 60.0, reps = 8, rest = 150)
    val incline: Exercise = exercise("incline", "Incline dumbbell press", MuscleGroup.CHEST, Equipment.DUMBBELL, best = 38.0, kg = 24.0, reps = 10, rest = 90)
    val ohp: Exercise = exercise("ohp", "Overhead press", MuscleGroup.SHOULDERS, Equipment.BARBELL, best = 58.0, kg = 40.0, reps = 8, rest = 120)
    val lateral: Exercise = exercise("lateral", "Dumbbell lateral raise", MuscleGroup.SHOULDERS, Equipment.DUMBBELL, best = 12.5, kg = 8.0, reps = 15, rest = 60)
    val pushdown: Exercise = exercise("pushdown", "Triceps pushdown", MuscleGroup.ARMS, Equipment.CABLE, best = 43.0, kg = 30.0, reps = 12, rest = 60)
    val crossover: Exercise = exercise("crossover", "Cable crossover", MuscleGroup.CHEST, Equipment.CABLE, best = 22.0, kg = 15.0, reps = 12, rest = 60)
    val pushup: Exercise = exercise("pushup", "Push-up", MuscleGroup.CHEST, Equipment.BODYWEIGHT, tracking = TrackingKind.REPS_ONLY, kg = 0.0, reps = 12, rest = 60)
    val plank: Exercise = exercise("plank", "Plank", MuscleGroup.CORE, Equipment.BODYWEIGHT, tracking = TrackingKind.DURATION, kg = 0.0, reps = 45, rest = 45)
    val squat: Exercise = exercise("squat", "Back squat", MuscleGroup.LEGS, Equipment.BARBELL, kg = 60.0, reps = 6, rest = 180)

    /** Exercises the fuzz tests draw from. */
    val pool: List<Exercise> = listOf(bench, incline, ohp, lateral, pushdown, crossover, pushup, plank, squat)

    // endregion

    // region Workout states

    /** `(type, kg, reps)` of one set (Swift `SetSpec`). */
    fun normal(count: Int, kg: Double, reps: Int): List<Triple<SetType, Double, Int>> =
        List(count) { Triple(SetType.NORMAL, kg, reps) }

    /** Entry number `n` (1-based) with deterministic ids: entry `uuid(0x100 + n, 0)`, sets `uuid(0x100 + n, i + 1)`. */
    fun entry(
        n: Int,
        exercise: Exercise,
        sets: List<Triple<SetType, Double, Int>>,
        rest: Int,
        group: String? = null,
        templateEntry: UUID? = null,
    ): WorkoutExercise = WorkoutExercise(
        id = uuid(0x100 + n, 0),
        exercise = exercise,
        sets = sets.mapIndexed { offset, spec -> LoggedSet(id = uuid(0x100 + n, offset + 1), type = spec.first, weightKg = spec.second, reps = spec.third) },
        restSeconds = rest,
        supersetGroup = group,
        note = "",
        templateEntryID = templateEntry,
    )

    /**
     * The design's workout, nothing logged yet: bench (2 warm-ups + 3 working sets, rest 150), incline, overhead press,
     * lateral raise + pushdown (superset A, rest 60) and cable crossover.
     */
    fun designState(now: Instant = t0): WorkoutState {
        val exercises = listOf(
            entry(
                1, bench,
                listOf(
                    Triple(SetType.WARMUP, 50.0, 8), Triple(SetType.WARMUP, 70.0, 5), Triple(SetType.NORMAL, 82.5, 6),
                    Triple(SetType.NORMAL, 82.5, 6), Triple(SetType.NORMAL, 85.0, 6),
                ),
                rest = 150,
            ),
            entry(2, incline, normal(3, 28.0, 10), rest = 90),
            entry(3, ohp, normal(3, 45.0, 8), rest = 120),
            entry(4, lateral, normal(3, 8.0, 15), rest = 60, group = "A"),
            entry(5, pushdown, normal(3, 30.0, 12), rest = 60, group = "A"),
            entry(6, crossover, normal(3, 15.0, 12), rest = 60),
        )
        return WorkoutState(id = uuid(1, 1), name = "Upper A · Push", exercises = exercises, currentIndex = 0, startedAt = now)
    }

    /** A workout of `exercises` starting at `index`. */
    fun state(exercises: List<WorkoutExercise>, index: Int = 0): WorkoutState =
        WorkoutState(id = uuid(1, 2), name = "Test", exercises = exercises, currentIndex = index, startedAt = t0)

    // endregion

    // region Ids and actions

    fun ex(s: WorkoutState, k: Int): UUID = s.exercises[k].id

    fun setID(s: WorkoutState, k: Int, i: Int): UUID = s.exercises[k].sets[i].id

    fun toggle(s: WorkoutState, k: Int, i: Int): WorkoutAction = WorkoutAction.ToggleSet(ex(s, k), setID(s, k, i))

    fun log(s: WorkoutState, k: Int, i: Int): WorkoutAction = WorkoutAction.LogSet(ex(s, k), setID(s, k, i))

    /** `s` after `action` at `t0 + seconds`. */
    fun reduced(s: WorkoutState, action: WorkoutAction, at: Number = 0): WorkoutState =
        WorkoutReducer.reduce(s, action, this.at(at))

    /** `s` after all `actions`, one second apart, starting at `t0 + start`. */
    fun reduced(s: WorkoutState, actions: List<WorkoutAction>, start: Number = 0): WorkoutState {
        var copy = s
        for ((n, action) in actions.withIndex()) {
            copy = WorkoutReducer.reduce(copy, action, this.at(start.toDouble() + n.toDouble()))
        }
        return copy
    }

    /** True for actions that create new entity ids (their results differ between two runs). */
    fun createsNewIDs(action: WorkoutAction): Boolean =
        action is WorkoutAction.AddSet || action is WorkoutAction.AddExercises || action is WorkoutAction.ReplaceExercise

    /** One action of every kind, using the first exercise / set of `s` (unknown ids when `s` is empty). */
    fun sampleActions(s: WorkoutState): List<WorkoutAction> {
        val e = s.exercises.firstOrNull()?.id ?: uuid(0xFFFF, 1)
        val st = s.exercises.firstOrNull()?.sets?.firstOrNull()?.id ?: uuid(0xFFFF, 2)
        return listOf(
            WorkoutAction.ToggleSet(e, st), WorkoutAction.LogSet(e, st), WorkoutAction.LogNextSet,
            WorkoutAction.SetWeight(e, st, 55.0), WorkoutAction.SetReps(e, st, 7),
            WorkoutAction.NudgeNextSet(1, -1), WorkoutAction.SetSetType(e, st, SetType.DROP),
            WorkoutAction.SetRIR(e, st, 2), WorkoutAction.ToggleLastSetRIR(2), WorkoutAction.AddSet(e),
            WorkoutAction.DeleteSet(e, st), WorkoutAction.SetNote(e, "slow negatives"),
            WorkoutAction.GoTo(99), WorkoutAction.GoTo(-4), WorkoutAction.NextExercise, WorkoutAction.PreviousExercise,
            WorkoutAction.AddExercises(listOf(bench, plank)), WorkoutAction.RemoveExercise(e), WorkoutAction.MoveExercise(0, 2),
            WorkoutAction.MoveExerciseBy(e, 1), WorkoutAction.ReplaceExercise(e, plank),
            WorkoutAction.ToggleSuperset(e), WorkoutAction.SetRest(e, 30),
            WorkoutAction.AdjustRest(15), WorkoutAction.SkipRest, WorkoutAction.SetAutoStartRest(false), WorkoutAction.SetAlertWhenRestEnds(false),
            WorkoutAction.Pause, WorkoutAction.Resume, WorkoutAction.Undo, WorkoutAction.UpdateHeartRate(120),
            WorkoutAction.SetUsedWatch(true), WorkoutAction.Rename("Renamed"),
        )
    }

    // endregion

    // region In-place edits of a state value (Swift `s.exercises[k].sets[i].x = y`)

    fun editExercise(s: WorkoutState, k: Int, transform: (WorkoutExercise) -> WorkoutExercise): WorkoutState =
        s.copy(exercises = s.exercises.mapIndexed { index, entry -> if (index == k) transform(entry) else entry })

    fun editSet(s: WorkoutState, k: Int, i: Int, transform: (LoggedSet) -> LoggedSet): WorkoutState =
        editExercise(s, k) { entry -> entry.copy(sets = entry.sets.mapIndexed { index, set -> if (index == i) transform(set) else set }) }

    /** Sets `isDone` of the sets `indices` of exercise `k`. */
    fun withDone(s: WorkoutState, k: Int, indices: Iterable<Int>, done: Boolean = true): WorkoutState {
        var result = s
        for (i in indices) result = editSet(result, k, i) { it.copy(isDone = done) }
        return result
    }

    /** Every set of every exercise done. */
    fun allDone(s: WorkoutState): WorkoutState {
        var result = s
        for (k in result.exercises.indices) result = withDone(result, k, result.exercises[k].sets.indices)
        return result
    }

    // endregion
}

// endregion

// region Rule 1: purity, revision, no-ops, currentIndex bounds

class WorkoutReducerRevisionTests {
    @Test
    fun testUndoWindowIsSixSeconds() {
        assertThat(WorkoutReducer.undoWindow).isEqualTo(6.0)
    }

    @Test
    fun testChangedStateBumpsRevisionByOne() {
        var s = RedFix.designState()
        assertThat(s.revision).isEqualTo(0)
        s = WorkoutReducer.reduce(s, WorkoutAction.SetNote(RedFix.ex(s, 0), "x"), RedFix.at(1))
        assertThat(s.revision).isEqualTo(1)
        s = WorkoutReducer.reduce(s, WorkoutAction.NextExercise, RedFix.at(2))
        assertThat(s.revision).isEqualTo(2)
        s = WorkoutReducer.reduce(s, RedFix.toggle(s, 0, 0), RedFix.at(3))
        assertThat(s.revision).isEqualTo(3)
    }

    @Test
    fun testRevisionContinuesFromItsCurrentValue() {
        var s = RedFix.designState()
        s = s.copy(revision = 41)
        s = WorkoutReducer.reduce(s, WorkoutAction.Rename("Pull day"), RedFix.at(1))
        assertThat(s.revision).isEqualTo(42)
        assertThat(s.name).isEqualTo("Pull day")
    }

    @Test
    fun testNoOpActionsKeepStateAndRevision() {
        val s = RedFix.designState()
        val e = RedFix.ex(s, 0)
        val st = RedFix.setID(s, 0, 0)
        val last = RedFix.ex(s, 5)
        val noOps: List<WorkoutAction> = listOf(
            WorkoutAction.GoTo(0), WorkoutAction.PreviousExercise, WorkoutAction.SkipRest, WorkoutAction.Resume, WorkoutAction.Undo,
            WorkoutAction.AdjustRest(-15), WorkoutAction.AdjustRest(0),
            WorkoutAction.SetAutoStartRest(true), WorkoutAction.SetAlertWhenRestEnds(true), WorkoutAction.SetUsedWatch(false),
            WorkoutAction.Rename("Upper A · Push"),
            WorkoutAction.SetRest(e, 150), WorkoutAction.SetWeight(e, st, 50.0),
            WorkoutAction.SetWeight(e, st, 50.004), WorkoutAction.SetWeight(e, st, Double.NaN),
            WorkoutAction.SetReps(e, st, 8), WorkoutAction.SetSetType(e, st, SetType.WARMUP),
            WorkoutAction.SetRIR(e, st, null), WorkoutAction.SetNote(e, ""),
            WorkoutAction.ToggleSuperset(last), WorkoutAction.MoveExercise(1, 1), WorkoutAction.MoveExerciseBy(e, 0),
            WorkoutAction.AddExercises(emptyList()), WorkoutAction.ToggleLastSetRIR(2), WorkoutAction.NudgeNextSet(0, 0),
        )
        for (action in noOps) {
            val t = WorkoutReducer.reduce(s, action, RedFix.at(5))
            assertWithMessage("expected a no-op: $action").that(t).isEqualTo(s)
        }
    }

    @Test
    fun testLogSetOnDoneSetKeepsRevision() {
        val s = RedFix.reduced(RedFix.designState(), RedFix.toggle(RedFix.designState(), 0, 0), at = 1)
        val again = RedFix.reduced(s, RedFix.log(s, 0, 0), at = 2)
        assertThat(again).isEqualTo(s)
        assertThat(again.revision).isEqualTo(1)
    }

    @Test
    fun testUnknownIDsAreNoOps() {
        val s = RedFix.designState()
        val ghost = RedFix.uuid(0xDEAD, 1)
        val ghostSet = RedFix.uuid(0xDEAD, 2)
        val e = RedFix.ex(s, 1)
        val actions: List<WorkoutAction> = listOf(
            WorkoutAction.ToggleSet(ghost, ghostSet), WorkoutAction.LogSet(ghost, ghostSet),
            WorkoutAction.ToggleSet(e, ghostSet), WorkoutAction.LogSet(e, ghostSet),
            WorkoutAction.SetWeight(ghost, ghostSet, 10.0), WorkoutAction.SetWeight(e, ghostSet, 10.0),
            WorkoutAction.SetReps(ghost, ghostSet, 3), WorkoutAction.SetReps(e, ghostSet, 3),
            WorkoutAction.SetSetType(ghost, ghostSet, SetType.DROP), WorkoutAction.SetSetType(e, ghostSet, SetType.DROP),
            WorkoutAction.SetRIR(ghost, ghostSet, 1), WorkoutAction.SetRIR(e, ghostSet, 1),
            WorkoutAction.AddSet(ghost), WorkoutAction.DeleteSet(ghost, ghostSet), WorkoutAction.DeleteSet(e, ghostSet),
            WorkoutAction.SetNote(ghost, "x"), WorkoutAction.RemoveExercise(ghost),
            WorkoutAction.MoveExerciseBy(ghost, 1), WorkoutAction.ReplaceExercise(ghost, RedFix.plank),
            WorkoutAction.ToggleSuperset(ghost), WorkoutAction.SetRest(ghost, 10),
        )
        for (action in actions) {
            val t = WorkoutReducer.reduce(s, action, RedFix.at(5))
            assertWithMessage("expected a no-op: $action").that(t).isEqualTo(s)
        }
    }

    @Test
    fun testOutOfRangeIndexesAreNoOps() {
        val s = RedFix.designState()
        val actions: List<WorkoutAction> = listOf(
            WorkoutAction.MoveExercise(-1, 2), WorkoutAction.MoveExercise(6, 0), WorkoutAction.MoveExercise(0, 6),
            WorkoutAction.MoveExercise(0, -1), WorkoutAction.MoveExerciseBy(RedFix.ex(s, 0), -1),
            WorkoutAction.MoveExerciseBy(RedFix.ex(s, 5), 1), WorkoutAction.MoveExerciseBy(RedFix.ex(s, 2), 9),
            WorkoutAction.MoveExerciseBy(RedFix.ex(s, 2), Int.MAX_VALUE),
        )
        for (action in actions) {
            val t = WorkoutReducer.reduce(s, action, RedFix.at(5))
            assertWithMessage("expected a no-op: $action").that(t).isEqualTo(s)
        }
    }

    @Test
    fun testReducingTheSameInputTwiceGivesTheSameState() {
        val s = RedFix.designState()
        // Swift also relied on value semantics ("the input is not mutated"). The Kotlin state is immutable, but its lists could in
        // principle be mutated in place, so the input is also compared with a JSON snapshot taken before.
        val before = StrengthJson.format.encodeToString(WorkoutState.serializer(), s)
        for (action in RedFix.sampleActions(s).filter { !RedFix.createsNewIDs(it) }) {
            assertWithMessage("$action").that(RedFix.reduced(s, action, at = 3)).isEqualTo(RedFix.reduced(s, action, at = 3))
        }
        for (action in RedFix.sampleActions(s)) RedFix.reduced(s, action, at = 3)
        assertThat(StrengthJson.format.encodeToString(WorkoutState.serializer(), s)).isEqualTo(before)
    }

    @Test
    fun testNewEntitiesGetFreshIDs() {
        val s = RedFix.designState()
        val added = RedFix.reduced(s, WorkoutAction.AddSet(RedFix.ex(s, 1)))
        val newSet = added.exercises[1].sets.last()
        assertThat(s.exercises.flatMap { it.sets }.any { it.id == newSet.id }).isFalse()
        val more = RedFix.reduced(s, WorkoutAction.AddExercises(listOf(RedFix.plank, RedFix.plank)))
        val ids = more.exercises.map { it.id }
        assertThat(ids.toSet().size).isEqualTo(ids.size)
    }

    @Test
    fun testCurrentIndexStaysInBoundsAfterEveryAction() {
        val starts: List<WorkoutState> = listOf(
            RedFix.designState(),
            WorkoutState(name = "Empty", startedAt = RedFix.t0),
            RedFix.state(listOf(RedFix.entry(1, RedFix.plank, RedFix.normal(1, 0.0, 45), rest = 45))),
        )
        for (start in starts) {
            for (index in listOf(-7, 0, 2, 5, 99)) {
                val s = start.copy(currentIndex = index)
                // each action alone
                for (action in RedFix.sampleActions(s)) {
                    val after = RedFix.reduced(s, action, at = 2)
                    assertInBounds(after, "$action from index $index")
                }
                // all actions in sequence
                var chained = s
                for ((n, action) in RedFix.sampleActions(s).withIndex()) {
                    chained = WorkoutReducer.reduce(chained, action, RedFix.at(n))
                    assertInBounds(chained, "chained $action from index $index")
                }
            }
        }
    }

    @Test
    fun testCurrentIndexIsZeroForEmptyWorkout() {
        var s = WorkoutState(name = "Empty", currentIndex = 3, startedAt = RedFix.t0)
        s = WorkoutReducer.reduce(s, WorkoutAction.NextExercise, RedFix.at(1))
        assertThat(s.currentIndex).isEqualTo(0)
        s = WorkoutReducer.reduce(s, WorkoutAction.GoTo(5), RedFix.at(2))
        assertThat(s.currentIndex).isEqualTo(0)
    }

    @Test
    fun testOutOfRangeIncomingIndexIsRepairedEvenForHeartRate() {
        var s = RedFix.designState()
        s = s.copy(currentIndex = 42)
        s = WorkoutReducer.reduce(s, WorkoutAction.UpdateHeartRate(100), RedFix.at(1))
        assertThat(s.currentIndex).isEqualTo(5)
        assertThat(s.revision).isEqualTo(0)
    }

    private fun assertInBounds(s: WorkoutState, message: String) {
        if (s.exercises.isEmpty()) {
            assertWithMessage(message).that(s.currentIndex).isEqualTo(0)
        } else {
            assertWithMessage("$message: ${s.currentIndex}").that(s.currentIndex in 0 until s.exercises.size).isTrue()
        }
    }
}

// endregion

// region Rule 2: logging

class WorkoutReducerLoggingTests {
    @Test
    fun testBenchLoggingFlowWithRestLengths60And150() {
        var s = RedFix.designState()
        // set index, logged at (seconds), expected rest seconds: warm-ups rest 40 % of 150 s, working sets the full 150 s.
        val steps = listOf(Triple(0, 10.0, 60), Triple(1, 100.0, 60), Triple(2, 200.0, 150), Triple(3, 400.0, 150), Triple(4, 600.0, 150))
        for ((n, step) in steps.withIndex()) {
            s = RedFix.reduced(s, RedFix.toggle(s, 0, step.first), at = step.second)
            assertThat(s.exercises[0].sets[step.first].isDone).isTrue()
            assertThat(s.lastLogged).isEqualTo(SetRef(RedFix.ex(s, 0), RedFix.setID(s, 0, step.first)))
            assertThat(s.rest?.totalSeconds).isEqualTo(step.third)
            assertThat(s.rest?.endsAt).isEqualTo(RedFix.at(step.second + step.third.toDouble()))
            assertThat(s.rest?.frozenRemaining).isNull()
            assertThat(s.currentIndex).isEqualTo(0)
            assertThat(s.revision).isEqualTo(n + 1)
        }
        assertThat(s.exercises[0].isComplete).isTrue()
        assertThat(WorkoutTargets.nextPending(s)).isEqualTo(SetTarget(exerciseIndex = 1, setIndex = 0))
        // The remaining exercises are untouched.
        assertThat(s.exercises.drop(1).flatMap { it.sets }.count { it.isDone }).isEqualTo(0)
    }

    @Test
    fun testWarmupRestFactorTable() {
        // rest -> warm-up rest: max(30, round(rest * 0.4 / 5) * 5); a rest of 0 (Off) means no rest after any set type (rule 2),
        // so the warm-up of an Off exercise starts no timer either (it used to start the 30 s minimum).
        val table = listOf(45 to 30, 60 to 30, 75 to 30, 90 to 35, 100 to 40, 120 to 50, 150 to 60, 180 to 70, 0 to 0)
        for ((rest, expected) in table) {
            val entry = RedFix.entry(
                1, RedFix.bench, listOf(Triple(SetType.WARMUP, 40.0, 8), Triple(SetType.NORMAL, 80.0, 5)), rest = rest,
            )
            val s = RedFix.state(listOf(entry))
            val warm = RedFix.reduced(s, RedFix.toggle(s, 0, 0), at = 0)
            if (expected > 0) {
                assertWithMessage("warm-up after rest $rest").that(warm.rest?.totalSeconds).isEqualTo(expected)
            } else {
                assertWithMessage("rest Off starts no timer after a warm-up either").that(warm.rest).isNull()
            }
            val work = RedFix.reduced(s, RedFix.toggle(s, 0, 1), at = 0)
            if (rest > 0) {
                assertWithMessage("working set after rest $rest").that(work.rest?.totalSeconds).isEqualTo(rest)
            } else {
                assertWithMessage("rest Off starts no timer after a working set").that(work.rest).isNull()
            }
        }
    }

    /** Rule 2: an exercise rest of 0 (Off) means no rest after a set of ANY type; a warm-up used to start its 30 s minimum. */
    @Test
    fun testRestOffMeansNoRestForAnySetType() {
        val types = listOf(SetType.NORMAL, SetType.WARMUP, SetType.DROP, SetType.FAILURE)
        for (type in types) {
            val entry = RedFix.entry(1, RedFix.bench, listOf(Triple(type, 40.0, 8), Triple(SetType.NORMAL, 80.0, 5)), rest = 0)
            val s = RedFix.state(listOf(entry))
            for (action in listOf(RedFix.toggle(s, 0, 0), RedFix.log(s, 0, 0), WorkoutAction.LogNextSet)) {
                val logged = RedFix.reduced(s, action, at = 5)
                assertWithMessage("$type $action").that(logged.exercises[0].sets[0].isDone).isTrue()
                assertWithMessage("no timer after a $type set of an exercise whose rest is Off ($action)").that(logged.rest).isNull()
            }
        }
    }

    @Test
    fun testLoggingAWarmupOfAnOffExerciseEndsARestThatWasRunning() {
        // A running rest from the previous exercise is replaced by "no rest", like after a working set of an Off exercise.
        val first = RedFix.entry(1, RedFix.bench, RedFix.normal(1, 80.0, 5), rest = 90)
        val off = RedFix.entry(2, RedFix.incline, listOf(Triple(SetType.WARMUP, 10.0, 10), Triple(SetType.NORMAL, 20.0, 10)), rest = 0)
        var s = RedFix.state(listOf(first, off))
        s = RedFix.reduced(s, RedFix.toggle(s, 0, 0), at = 1)
        assertThat(s.rest?.totalSeconds).isEqualTo(90)
        s = RedFix.reduced(s, RedFix.toggle(s, 1, 0), at = 2)
        assertThat(s.rest).isNull()
        assertThat(s.lastLogged).isEqualTo(SetRef(RedFix.ex(s, 1), RedFix.setID(s, 1, 0)))
    }

    @Test
    fun testTurningTheTimerOffDuringTheWorkoutAlsoSilencesWarmups() {
        val s = RedFix.state(
            listOf(
                RedFix.entry(
                    1, RedFix.bench,
                    listOf(Triple(SetType.WARMUP, 40.0, 8), Triple(SetType.WARMUP, 60.0, 5), Triple(SetType.NORMAL, 80.0, 5)),
                    rest = 150,
                ),
            ),
        )
        val before = RedFix.reduced(s, RedFix.toggle(s, 0, 0), at = 1)
        assertThat(before.rest?.totalSeconds).isEqualTo(60)
        var off = RedFix.reduced(s, WorkoutAction.SetRest(RedFix.ex(s, 0), 0), at = 1)
        off = RedFix.reduced(off, RedFix.toggle(off, 0, 0), at = 2)
        assertThat(off.rest).isNull()
        // Turning it back on restores the warm-up rule.
        var on = RedFix.reduced(off, WorkoutAction.SetRest(RedFix.ex(off, 0), 100), at = 3)
        on = RedFix.reduced(on, RedFix.toggle(on, 0, 1), at = 4)
        assertThat(on.rest?.totalSeconds).isEqualTo(40)
    }

    @Test
    fun testAWarmupOfAnOffExerciseInASupersetStartsNoRestEither() {
        val a = RedFix.entry(1, RedFix.lateral, listOf(Triple(SetType.WARMUP, 4.0, 15), Triple(SetType.NORMAL, 8.0, 15)), rest = 0, group = "A")
        val b = RedFix.entry(2, RedFix.pushdown, listOf(Triple(SetType.WARMUP, 15.0, 12), Triple(SetType.NORMAL, 30.0, 12)), rest = 0, group = "A")
        var s = RedFix.state(listOf(a, b))
        s = RedFix.reduced(s, RedFix.toggle(s, 0, 0), at = 1)
        assertWithMessage("the superset still moves on to its partner").that(s.currentIndex).isEqualTo(1)
        assertThat(s.rest).isNull()
        s = RedFix.reduced(s, RedFix.toggle(s, 1, 0), at = 2)
        assertThat(s.currentIndex).isEqualTo(0)
        assertWithMessage("end of the round: still no rest, the timer is Off").that(s.rest).isNull()
    }

    @Test
    fun testDropAndFailureSetsUseTheFullRest() {
        val entry = RedFix.entry(1, RedFix.bench, listOf(Triple(SetType.DROP, 60.0, 8), Triple(SetType.FAILURE, 60.0, 8)), rest = 150)
        val s = RedFix.state(listOf(entry))
        assertThat(RedFix.reduced(s, RedFix.toggle(s, 0, 0)).rest?.totalSeconds).isEqualTo(150)
        assertThat(RedFix.reduced(s, RedFix.toggle(s, 0, 1)).rest?.totalSeconds).isEqualTo(150)
    }

    @Test
    fun testTogglingADoneSetMakesItPendingKeepingRirAndRest() {
        var s = RedFix.designState()
        s = RedFix.reduced(s, RedFix.toggle(s, 0, 2), at = 10)
        s = RedFix.reduced(s, WorkoutAction.ToggleLastSetRIR(3), at = 11)
        val restBefore = s.rest
        val lastBefore = s.lastLogged
        assertThat(s.exercises[0].sets[2].rir).isEqualTo(3)
        s = RedFix.reduced(s, RedFix.toggle(s, 0, 2), at = 20)
        assertThat(s.exercises[0].sets[2].isDone).isFalse()
        assertThat(s.exercises[0].sets[2].rir).isEqualTo(3)
        assertThat(s.rest).isEqualTo(restBefore)
        assertThat(s.lastLogged).isEqualTo(lastBefore)
        // and toggling again logs it again with a new rest
        s = RedFix.reduced(s, RedFix.toggle(s, 0, 2), at = 30)
        assertThat(s.exercises[0].sets[2].isDone).isTrue()
        assertThat(s.rest?.endsAt).isEqualTo(RedFix.at(180))
    }

    @Test
    fun testAutoStartRestOffClearsAnyRest() {
        var s = RedFix.designState()
        s = s.copy(settings = s.settings.copy(autoStartRest = false))
        s = s.copy(rest = RestState(endsAt = RedFix.at(500), totalSeconds = 90))
        s = RedFix.reduced(s, RedFix.toggle(s, 0, 2), at = 10)
        assertThat(s.rest).isNull()
        assertThat(s.exercises[0].sets[2].isDone).isTrue()
    }

    @Test
    fun testRestOffForAnExerciseStartsNoTimer() {
        var s = RedFix.designState()
        s = RedFix.reduced(s, WorkoutAction.SetRest(RedFix.ex(s, 0), 0))
        s = s.copy(rest = RestState(endsAt = RedFix.at(500), totalSeconds = 90))
        s = RedFix.reduced(s, RedFix.toggle(s, 0, 2), at = 10)
        assertThat(s.rest).isNull()
    }

    @Test
    fun testLoggingWhilePausedStartsAFrozenRest() {
        var s = RedFix.designState()
        s = RedFix.reduced(s, WorkoutAction.Pause, at = 5)
        s = RedFix.reduced(s, RedFix.toggle(s, 0, 2), at = 10)
        assertThat(s.rest).isEqualTo(RestState(endsAt = RedFix.at(160), totalSeconds = 150, frozenRemaining = 150.0))
        assertThat(s.restRemaining(RedFix.at(9_999))).isEqualTo(150.0)
    }

    @Test
    fun testLogSetIsIdempotent() {
        var s = RedFix.designState()
        s = RedFix.reduced(s, RedFix.log(s, 0, 2), at = 10)
        assertThat(s.exercises[0].sets[2].isDone).isTrue()
        assertThat(s.rest?.totalSeconds).isEqualTo(150)
        val again = RedFix.reduced(s, RedFix.log(s, 0, 2), at = 99)
        assertThat(again).isEqualTo(s)
    }

    @Test
    fun testLogSetOnAPendingSetMatchesToggle() {
        val s = RedFix.designState()
        assertThat(RedFix.reduced(s, RedFix.log(s, 3, 1), at = 7)).isEqualTo(RedFix.reduced(s, RedFix.toggle(s, 3, 1), at = 7))
    }

    @Test
    fun testLogNextSetMovesToTheNextPendingExerciseAndLogsIt() {
        var s = RedFix.designState()
        for (i in 0 until 5) s = RedFix.reduced(s, RedFix.log(s, 0, i), at = i)
        assertThat(s.currentIndex).isEqualTo(0)
        s = RedFix.reduced(s, WorkoutAction.LogNextSet, at = 50)
        assertThat(s.currentIndex).isEqualTo(1)
        assertThat(s.exercises[1].sets[0].isDone).isTrue()
        assertThat(s.lastLogged).isEqualTo(SetRef(RedFix.ex(s, 1), RedFix.setID(s, 1, 0)))
        assertThat(s.rest).isEqualTo(RestState(endsAt = RedFix.at(140), totalSeconds = 90))
    }

    @Test
    fun testLogNextSetWrapsToEarlierExercises() {
        var s = RedFix.designState()
        s = s.copy(currentIndex = 5)
        for (i in 0 until 3) s = RedFix.reduced(s, RedFix.log(s, 5, i), at = i)
        s = RedFix.reduced(s, WorkoutAction.LogNextSet, at = 10)
        assertThat(s.currentIndex).isEqualTo(0)
        assertThat(s.exercises[0].sets[0].isDone).isTrue()
        assertThat(s.rest?.totalSeconds).isEqualTo(60)   // a warm-up of a 150 s exercise
    }

    @Test
    fun testLogNextSetWithNothingPendingIsANoOp() {
        val s = RedFix.allDone(RedFix.designState())
        assertThat(WorkoutTargets.nextPending(s)).isNull()
        assertThat(RedFix.reduced(s, WorkoutAction.LogNextSet)).isEqualTo(s)
        assertThat(RedFix.reduced(s, WorkoutAction.NudgeNextSet(1, 1))).isEqualTo(s)
    }

    @Test
    fun testNextPendingOrder() {
        var s = RedFix.designState()
        s = s.copy(currentIndex = 2)
        assertThat(WorkoutTargets.nextPending(s)).isEqualTo(SetTarget(exerciseIndex = 2, setIndex = 0))
        // current exercise done -> the following exercises first
        s = RedFix.withDone(s, 2, 0 until 3)
        assertThat(WorkoutTargets.nextPending(s)).isEqualTo(SetTarget(exerciseIndex = 3, setIndex = 0))
        // following exercises done too -> earlier ones
        for (k in 3 until 6) s = RedFix.withDone(s, k, 0 until 3)
        assertThat(WorkoutTargets.nextPending(s)).isEqualTo(SetTarget(exerciseIndex = 0, setIndex = 0))
        // first pending set within an exercise, not the first set
        s = RedFix.withDone(s, 0, listOf(0, 1))
        assertThat(WorkoutTargets.nextPending(s)).isEqualTo(SetTarget(exerciseIndex = 0, setIndex = 2))
        // earlier exercises are searched in order
        s = RedFix.withDone(s, 0, listOf(2, 3, 4))
        assertThat(WorkoutTargets.nextPending(s)).isEqualTo(SetTarget(exerciseIndex = 1, setIndex = 0))
    }

    @Test
    fun testNextPendingEdgeCases() {
        assertThat(WorkoutTargets.nextPending(WorkoutState(name = "E", startedAt = RedFix.t0))).isNull()
        var s = RedFix.designState()
        s = s.copy(currentIndex = 99)   // treated as the last exercise
        s = RedFix.withDone(s, 5, listOf(0))
        assertThat(WorkoutTargets.nextPending(s)).isEqualTo(SetTarget(exerciseIndex = 5, setIndex = 1))
        val noSets = RedFix.state(listOf(RedFix.entry(1, RedFix.plank, emptyList(), rest = 45)))
        assertThat(WorkoutTargets.nextPending(noSets)).isNull()
    }

    @Test
    fun testSupersetARoundTrip() {
        var s = RedFix.designState()
        s = s.copy(currentIndex = 3)
        s = s.copy(rest = RestState(endsAt = RedFix.at(500), totalSeconds = 90))   // an older rest that is still running
        // first leg (lateral raise): no rest, jump forward to the pushdown
        s = RedFix.reduced(s, RedFix.toggle(s, 3, 0), at = 10)
        assertThat(s.currentIndex).isEqualTo(4)
        assertThat(s.rest).isNull()
        assertThat(s.lastLogged).isEqualTo(SetRef(RedFix.ex(s, 3), RedFix.setID(s, 3, 0)))
        // last leg (pushdown): rest starts, jump back to the first leg
        s = RedFix.reduced(s, RedFix.toggle(s, 4, 0), at = 20)
        assertThat(s.currentIndex).isEqualTo(3)
        assertThat(s.rest).isEqualTo(RestState(endsAt = RedFix.at(80), totalSeconds = 60))
        assertThat(s.lastLogged).isEqualTo(SetRef(RedFix.ex(s, 4), RedFix.setID(s, 4, 0)))
        // the next round, driven by the Watch button
        s = RedFix.reduced(s, WorkoutAction.LogNextSet, at = 90)
        assertThat(s.exercises[3].sets[1].isDone).isEqualTo(true)
        assertThat(s.currentIndex).isEqualTo(4)
        assertThat(s.rest).isNull()
        s = RedFix.reduced(s, WorkoutAction.LogNextSet, at = 100)
        assertThat(s.exercises[4].sets[1].isDone).isEqualTo(true)
        assertThat(s.currentIndex).isEqualTo(3)
        assertThat(s.rest).isEqualTo(RestState(endsAt = RedFix.at(160), totalSeconds = 60))
    }

    @Test
    fun testSupersetLegsWithAutoStartOffNeverStartARest() {
        var s = RedFix.designState()
        s = s.copy(settings = s.settings.copy(autoStartRest = false))
        s = RedFix.reduced(s, RedFix.toggle(s, 3, 0), at = 1)
        s = RedFix.reduced(s, RedFix.toggle(s, 4, 0), at = 2)
        assertThat(s.rest).isNull()
        assertThat(s.currentIndex).isEqualTo(3)
    }

    @Test
    fun testThreeLegGroupAdvancesThroughTheLegs() {
        val legs = listOf(
            RedFix.entry(1, RedFix.lateral, RedFix.normal(2, 8.0, 15), rest = 60, group = "A"),
            RedFix.entry(2, RedFix.pushdown, RedFix.normal(2, 30.0, 12), rest = 60, group = "A"),
            RedFix.entry(3, RedFix.crossover, RedFix.normal(2, 15.0, 12), rest = 75, group = "A"),
        )
        var s = RedFix.state(legs)
        s = RedFix.reduced(s, RedFix.toggle(s, 0, 0), at = 1)
        assertThat(s.currentIndex).isEqualTo(1); assertThat(s.rest).isNull()
        s = RedFix.reduced(s, RedFix.toggle(s, 1, 0), at = 2)
        assertThat(s.currentIndex).isEqualTo(2); assertThat(s.rest).isNull()
        s = RedFix.reduced(s, RedFix.toggle(s, 2, 0), at = 3)
        assertThat(s.currentIndex).isEqualTo(0)
        assertThat(s.rest).isEqualTo(RestState(endsAt = RedFix.at(78), totalSeconds = 75))   // the last leg's own rest
    }

    @Test
    fun testLoggingASetOfAnotherExerciseDoesNotMoveTheCurrentIndex() {
        var s = RedFix.designState()
        s = s.copy(currentIndex = 1)
        s = RedFix.reduced(s, RedFix.toggle(s, 2, 0), at = 5)   // ohp, not in a superset
        assertThat(s.currentIndex).isEqualTo(1)
        assertThat(s.rest?.totalSeconds).isEqualTo(120)
    }

    @Test
    fun testSupersetJumpIsToIndexPlusOneEvenWhenTheGroupIsNotContiguous() {
        val legs = listOf(
            RedFix.entry(1, RedFix.lateral, RedFix.normal(2, 8.0, 15), rest = 60, group = "A"),
            RedFix.entry(2, RedFix.incline, RedFix.normal(2, 20.0, 10), rest = 90),
            RedFix.entry(3, RedFix.pushdown, RedFix.normal(2, 30.0, 12), rest = 60, group = "A"),
        )
        var s = RedFix.state(legs)
        s = RedFix.reduced(s, RedFix.toggle(s, 0, 0), at = 1)
        assertThat(s.currentIndex).isEqualTo(1)
        assertThat(s.rest).isNull()
        s = RedFix.reduced(s, RedFix.toggle(s, 2, 0), at = 2)
        assertThat(s.currentIndex).isEqualTo(0)
        assertThat(s.rest?.totalSeconds).isEqualTo(60)
    }
}

// endregion

// region Rules 3 and 4: set values, nudges, types, RIR, notes

class WorkoutReducerSetEditTests {
    @Test
    fun testSetWeightClampsAndRoundsToHundredths() {
        val s = RedFix.designState()
        val e = RedFix.ex(s, 0)
        val id = RedFix.setID(s, 0, 2)
        fun weight(kg: Double): Double =
            RedFix.reduced(s, WorkoutAction.SetWeight(e, id, kg)).exercises[0].sets[2].weightKg
        assertThat(weight(-5.0)).isEqualTo(0.0)
        assertThat(weight(0.0)).isEqualTo(0.0)
        assertThat(weight(82.504)).isWithin(1e-9).of(82.5)
        assertThat(weight(82.506)).isWithin(1e-9).of(82.51)
        assertThat(weight(100.0)).isEqualTo(100.0)
        assertThat(weight(Double.POSITIVE_INFINITY)).isEqualTo(82.5)     // not representable: ignored
        assertThat(weight(Double.NaN)).isEqualTo(82.5)          // ignored
        assertThat(weight(Double.NEGATIVE_INFINITY)).isEqualTo(0.0)       // clamped like any negative value
    }

    @Test
    fun testSetRepsClampsTo0Through999() {
        val s = RedFix.designState()
        val e = RedFix.ex(s, 0)
        val id = RedFix.setID(s, 0, 2)
        fun reps(n: Int): Int = RedFix.reduced(s, WorkoutAction.SetReps(e, id, n)).exercises[0].sets[2].reps
        assertThat(reps(-3)).isEqualTo(0)
        assertThat(reps(0)).isEqualTo(0)
        assertThat(reps(12)).isEqualTo(12)
        assertThat(reps(999)).isEqualTo(999)
        assertThat(reps(1000)).isEqualTo(999)
        assertThat(reps(Int.MAX_VALUE)).isEqualTo(999)
        assertThat(reps(Int.MIN_VALUE)).isEqualTo(0)
    }

    @Test
    fun testEditingValuesDoesNotChangeTheDoneFlag() {
        var s = RedFix.designState()
        s = RedFix.reduced(s, RedFix.toggle(s, 0, 2), at = 1)
        s = RedFix.reduced(s, WorkoutAction.SetWeight(RedFix.ex(s, 0), RedFix.setID(s, 0, 2), 90.0), at = 2)
        s = RedFix.reduced(s, WorkoutAction.SetReps(RedFix.ex(s, 0), RedFix.setID(s, 0, 2), 4), at = 3)
        assertThat(s.exercises[0].sets[2].isDone).isTrue()
        val pending = RedFix.reduced(s, WorkoutAction.SetWeight(RedFix.ex(s, 0), RedFix.setID(s, 0, 3), 91.0))
        assertThat(pending.exercises[0].sets[3].isDone).isFalse()
        assertThat(pending.rest).isEqualTo(s.rest)
    }

    @Test
    fun testNudgeEditsTheNextPendingSetWithTheExerciseSteps() {
        var s = RedFix.designState()
        // bench is a barbell: 2.5 kg steps; the next pending set is the first warm-up (50 x 8)
        s = RedFix.reduced(s, WorkoutAction.NudgeNextSet(1, 2))
        assertThat(s.exercises[0].sets[0].weightKg).isEqualTo(52.5)
        assertThat(s.exercises[0].sets[0].reps).isEqualTo(10)
        s = RedFix.reduced(s, WorkoutAction.NudgeNextSet(-3, -1))
        assertThat(s.exercises[0].sets[0].weightKg).isEqualTo(45.0)
        assertThat(s.exercises[0].sets[0].reps).isEqualTo(9)
        assertThat(s.exercises[0].sets[1].weightKg).isEqualTo(70.0)   // other sets untouched
        assertThat(s.currentIndex).isEqualTo(0)
    }

    @Test
    fun testNudgeUsesDumbbellBodyweightAndDurationSteps() {
        val dumbbell = RedFix.designState()
        var d = dumbbell
        d = d.copy(currentIndex = 1)                                   // incline: dumbbell, 2 kg steps
        d = RedFix.reduced(d, WorkoutAction.NudgeNextSet(2, 1))
        assertThat(d.exercises[1].sets[0].weightKg).isEqualTo(32.0)
        assertThat(d.exercises[1].sets[0].reps).isEqualTo(11)

        var bw = RedFix.state(listOf(RedFix.entry(1, RedFix.pushup, RedFix.normal(2, 0.0, 12), rest = 60)))
        bw = RedFix.reduced(bw, WorkoutAction.NudgeNextSet(4, -2))   // no weight for repsOnly
        assertThat(bw.exercises[0].sets[0].weightKg).isEqualTo(0.0)
        assertThat(bw.exercises[0].sets[0].reps).isEqualTo(10)

        var timed = RedFix.state(listOf(RedFix.entry(1, RedFix.plank, RedFix.normal(2, 0.0, 45), rest = 45)))
        timed = RedFix.reduced(timed, WorkoutAction.NudgeNextSet(1, 3))   // seconds move in 5 s steps
        assertThat(timed.exercises[0].sets[0].weightKg).isEqualTo(0.0)
        assertThat(timed.exercises[0].sets[0].reps).isEqualTo(60)
    }

    @Test
    fun testNudgeClampsAtTheBounds() {
        var s = RedFix.designState()
        s = RedFix.reduced(s, WorkoutAction.NudgeNextSet(-100, -100))
        assertThat(s.exercises[0].sets[0].weightKg).isEqualTo(0.0)
        assertThat(s.exercises[0].sets[0].reps).isEqualTo(0)
        s = RedFix.reduced(s, WorkoutAction.NudgeNextSet(Int.MAX_VALUE, Int.MAX_VALUE))
        assertThat(s.exercises[0].sets[0].reps).isEqualTo(999)
        assertThat(s.exercises[0].sets[0].weightKg.isFinite()).isTrue()
    }

    @Test
    fun testNudgeFollowsTheNextPendingSetAcrossExercises() {
        var s = RedFix.designState()
        s = RedFix.withDone(s, 0, 0 until 5)   // current exercise complete
        s = RedFix.reduced(s, WorkoutAction.NudgeNextSet(1, 0))
        assertThat(s.exercises[1].sets[0].weightKg).isEqualTo(30.0)
        assertThat(s.currentIndex).isEqualTo(0)                          // nudging does not navigate
    }

    @Test
    fun testSetSetTypeChangesOnlyTheType() {
        var s = RedFix.designState()
        s = RedFix.reduced(s, RedFix.toggle(s, 0, 2), at = 1)
        val rest = s.rest
        s = RedFix.reduced(s, WorkoutAction.SetSetType(RedFix.ex(s, 0), RedFix.setID(s, 0, 2), SetType.FAILURE), at = 2)
        assertThat(s.exercises[0].sets[2].type).isEqualTo(SetType.FAILURE)
        assertThat(s.exercises[0].sets[2].isDone).isTrue()
        assertThat(s.rest).isEqualTo(rest)
        s = RedFix.reduced(s, WorkoutAction.SetSetType(RedFix.ex(s, 0), RedFix.setID(s, 0, 0), SetType.NORMAL), at = 3)
        assertThat(s.exercises[0].sets[0].type).isEqualTo(SetType.NORMAL)
    }

    @Test
    fun testExplicitRIRClampsAndClears() {
        var s = RedFix.designState()
        val e = RedFix.ex(s, 0)
        val id = RedFix.setID(s, 0, 2)
        fun set(rir: Int?) { s = RedFix.reduced(s, WorkoutAction.SetRIR(e, id, rir)) }
        set(2); assertThat(s.exercises[0].sets[2].rir).isEqualTo(2)
        set(9); assertThat(s.exercises[0].sets[2].rir).isEqualTo(4)
        set(-3); assertThat(s.exercises[0].sets[2].rir).isEqualTo(0)
        set(null); assertThat(s.exercises[0].sets[2].rir).isNull()
        set(2); set(2)   // explicit set does not toggle
        assertThat(s.exercises[0].sets[2].rir).isEqualTo(2)
    }

    @Test
    fun testToggleLastSetRIRAppliesToTheLastLoggedSetAndSameValueClears() {
        var s = RedFix.designState()
        s = RedFix.reduced(s, RedFix.toggle(s, 0, 2), at = 1)
        s = RedFix.reduced(s, WorkoutAction.ToggleLastSetRIR(2), at = 2)
        assertThat(s.exercises[0].sets[2].rir).isEqualTo(2)
        s = RedFix.reduced(s, WorkoutAction.ToggleLastSetRIR(2), at = 3)
        assertThat(s.exercises[0].sets[2].rir).isNull()
        s = RedFix.reduced(s, WorkoutAction.ToggleLastSetRIR(3), at = 4)
        s = RedFix.reduced(s, WorkoutAction.ToggleLastSetRIR(1), at = 5)
        assertThat(s.exercises[0].sets[2].rir).isEqualTo(1)
        s = RedFix.reduced(s, WorkoutAction.ToggleLastSetRIR(9), at = 6)      // clamped to 4 ("4+")
        assertThat(s.exercises[0].sets[2].rir).isEqualTo(4)
        s = RedFix.reduced(s, WorkoutAction.ToggleLastSetRIR(4), at = 7)
        assertThat(s.exercises[0].sets[2].rir).isNull()
        // the next logged set becomes the target
        s = RedFix.reduced(s, RedFix.toggle(s, 0, 3), at = 8)
        s = RedFix.reduced(s, WorkoutAction.ToggleLastSetRIR(0), at = 9)
        assertThat(s.exercises[0].sets[3].rir).isEqualTo(0)
        assertThat(s.exercises[0].sets[2].rir).isNull()
    }

    @Test
    fun testToggleLastSetRIRWithoutALoggedSetIsANoOp() {
        val s = RedFix.designState()
        assertThat(RedFix.reduced(s, WorkoutAction.ToggleLastSetRIR(2))).isEqualTo(s)
    }

    @Test
    fun testSetNoteStoresTheText() {
        var s = RedFix.designState()
        s = RedFix.reduced(s, WorkoutAction.SetNote(RedFix.ex(s, 2), "Belt on, pause at the chest"))
        assertThat(s.exercises[2].note).isEqualTo("Belt on, pause at the chest")
        assertThat(s.exercises[1].note).isEqualTo("")
        s = RedFix.reduced(s, WorkoutAction.SetNote(RedFix.ex(s, 2), ""))
        assertThat(s.exercises[2].note).isEqualTo("")
    }
}

// endregion

// region Rule 5: add / delete set

class WorkoutReducerSetListTests {
    @Test
    fun testAddSetCopiesTheLastSetAsAPendingNormalSet() {
        var s = RedFix.designState()
        s = RedFix.editSet(s, 2, 2) { it.copy(type = SetType.FAILURE, isDone = true, rir = 1, weightKg = 47.5, reps = 7) }
        s = RedFix.reduced(s, WorkoutAction.AddSet(RedFix.ex(s, 2)))
        assertThat(s.exercises[2].sets.size).isEqualTo(4)
        val added = s.exercises[2].sets[3]
        assertThat(added.type).isEqualTo(SetType.NORMAL)
        assertThat(added.weightKg).isEqualTo(47.5)
        assertThat(added.reps).isEqualTo(7)
        assertThat(added.isDone).isFalse()
        assertThat(added.rir).isNull()
        assertThat(s.revision).isEqualTo(1)
    }

    @Test
    fun testAddSetWithoutSetsUsesTheExerciseDefaults() {
        var s = RedFix.designState()
        s = RedFix.editExercise(s, 0) { it.copy(sets = emptyList()) }
        s = RedFix.reduced(s, WorkoutAction.AddSet(RedFix.ex(s, 0)))
        assertThat(s.exercises[0].sets.size).isEqualTo(1)
        assertThat(s.exercises[0].sets[0].weightKg).isEqualTo(60.0)    // bench defaults: 60 kg x 8
        assertThat(s.exercises[0].sets[0].reps).isEqualTo(8)
        assertThat(s.exercises[0].sets[0].type).isEqualTo(SetType.NORMAL)
    }

    @Test
    fun testDeleteSetRemovesItAndCreatesAnUndoEntry() {
        var s = RedFix.designState()
        val removed = s.exercises[1].sets[1]
        s = RedFix.reduced(s, WorkoutAction.DeleteSet(RedFix.ex(s, 1), removed.id), at = 100)
        assertThat(s.exercises[1].sets.size).isEqualTo(2)
        assertThat(s.exercises[1].sets.any { it.id == removed.id }).isFalse()
        assertThat(s.undo?.title).isEqualTo("Set deleted")
        assertThat(s.undo?.expiresAt).isEqualTo(RedFix.at(106))
        assertThat(s.undo?.payload).isEqualTo(UndoPayload.DeletedSet(exerciseID = RedFix.ex(s, 1), index = 1, set = removed))
        assertThat(s.revision).isEqualTo(1)
    }

    @Test
    fun testDeleteSetClearsLastLoggedOnlyWhenItPointedAtThatSet() {
        var s = RedFix.designState()
        s = RedFix.reduced(s, RedFix.toggle(s, 0, 2), at = 1)
        val other = RedFix.reduced(s, WorkoutAction.DeleteSet(RedFix.ex(s, 0), RedFix.setID(s, 0, 3)), at = 2)
        assertThat(other.lastLogged).isNotNull()
        val same = RedFix.reduced(s, WorkoutAction.DeleteSet(RedFix.ex(s, 0), RedFix.setID(s, 0, 2)), at = 2)
        assertThat(same.lastLogged).isNull()
    }

    @Test
    fun testDeletingTheLastSetLeavesAnExerciseWithoutSets() {
        var s = RedFix.state(listOf(RedFix.entry(1, RedFix.plank, RedFix.normal(1, 0.0, 45), rest = 45)))
        s = RedFix.reduced(s, WorkoutAction.DeleteSet(RedFix.ex(s, 0), RedFix.setID(s, 0, 0)))
        assertThat(s.exercises[0].sets).isEmpty()
        assertThat(s.exercises[0].isComplete).isFalse()
        assertThat(WorkoutTargets.nextPending(s)).isNull()
    }
}

// endregion

// region Rule 6: remove exercise and undo

class WorkoutReducerRemoveUndoTests {
    @Test
    fun testRemoveExerciseCreatesAnUndoEntry() {
        var s = RedFix.designState()
        val removed = s.exercises[1]
        s = RedFix.reduced(s, WorkoutAction.RemoveExercise(removed.id), at = 50)
        assertThat(s.exercises.size).isEqualTo(5)
        assertThat(s.exercises.any { it.id == removed.id }).isFalse()
        assertThat(s.undo?.title).isEqualTo("Removed Incline dumbbell press")
        assertThat(s.undo?.expiresAt).isEqualTo(RedFix.at(56))
        assertThat(s.undo?.payload).isEqualTo(UndoPayload.RemovedExercise(index = 1, exercise = removed))
    }

    @Test
    fun testCurrentIndexShiftsDownWhenAnEarlierExerciseIsRemoved() {
        var s = RedFix.designState()
        s = s.copy(currentIndex = 3)
        val lateralID = RedFix.ex(s, 3)
        s = RedFix.reduced(s, WorkoutAction.RemoveExercise(RedFix.ex(s, 1)))
        assertThat(s.currentIndex).isEqualTo(2)
        assertThat(s.currentExercise?.id).isEqualTo(lateralID)
    }

    @Test
    fun testRemovingTheCurrentOrLaterExerciseKeepsTheIndexThenClamps() {
        var s = RedFix.designState()
        s = s.copy(currentIndex = 2)
        var a = RedFix.reduced(s, WorkoutAction.RemoveExercise(RedFix.ex(s, 2)))
        assertThat(a.currentIndex).isEqualTo(2)
        assertThat(a.currentExercise?.exercise?.id).isEqualTo("lateral")
        a = RedFix.reduced(s, WorkoutAction.RemoveExercise(RedFix.ex(s, 4)))
        assertThat(a.currentIndex).isEqualTo(2)
        s = s.copy(currentIndex = 5)
        val b = RedFix.reduced(s, WorkoutAction.RemoveExercise(RedFix.ex(s, 5)))
        assertThat(b.currentIndex).isEqualTo(4)
    }

    @Test
    fun testRemovingTheOnlyExerciseEmptiesTheWorkout() {
        var s = RedFix.state(listOf(RedFix.entry(1, RedFix.plank, RedFix.normal(1, 0.0, 45), rest = 45)))
        s = RedFix.reduced(s, WorkoutAction.RemoveExercise(RedFix.ex(s, 0)))
        assertThat(s.exercises).isEmpty()
        assertThat(s.currentIndex).isEqualTo(0)
        assertThat(s.undo).isNotNull()
    }

    @Test
    fun testLastLoggedIsClearedOnlyWhenItPointedAtTheRemovedExercise() {
        var s = RedFix.designState()
        s = RedFix.reduced(s, RedFix.toggle(s, 2, 0), at = 1)
        val keep = RedFix.reduced(s, WorkoutAction.RemoveExercise(RedFix.ex(s, 1)), at = 2)
        assertThat(keep.lastLogged).isNotNull()
        val clear = RedFix.reduced(s, WorkoutAction.RemoveExercise(RedFix.ex(s, 2)), at = 2)
        assertThat(clear.lastLogged).isNull()
    }

    @Test
    fun testRemovingOneOfTwoSupersetMembersReleasesTheOther() {
        var s = RedFix.designState()
        s = RedFix.reduced(s, WorkoutAction.RemoveExercise(RedFix.ex(s, 3)))
        assertThat(s.exercises.map { it.supersetGroup }).isEqualTo(listOf<String?>(null, null, null, null, null))
    }

    @Test
    fun testRemovingTheMiddleOfAThreeMemberSupersetKeepsTheGroup() {
        val legs = listOf(
            RedFix.entry(1, RedFix.bench, RedFix.normal(2, 80.0, 5), rest = 150),
            RedFix.entry(2, RedFix.lateral, RedFix.normal(2, 8.0, 15), rest = 60, group = "A"),
            RedFix.entry(3, RedFix.pushdown, RedFix.normal(2, 30.0, 12), rest = 60, group = "A"),
            RedFix.entry(4, RedFix.crossover, RedFix.normal(2, 15.0, 12), rest = 60, group = "A"),
        )
        var s = RedFix.state(legs)
        val removed = s.exercises[2]
        s = RedFix.reduced(s, WorkoutAction.RemoveExercise(removed.id), at = 10)
        assertThat(s.exercises.map { it.supersetGroup }).isEqualTo(listOf<String?>(null, "A", "A"))
        // the group still works: first leg jumps forward, last leg jumps back
        val first = RedFix.reduced(s, RedFix.toggle(s, 1, 0), at = 11)
        assertThat(first.currentIndex).isEqualTo(2)
        assertThat(first.rest).isNull()
        val last = RedFix.reduced(first, RedFix.toggle(first, 2, 0), at = 12)
        assertThat(last.currentIndex).isEqualTo(1)
        assertThat(last.rest).isNotNull()
        // undo puts the middle leg back into the group
        val restored = RedFix.reduced(s, WorkoutAction.Undo, at = 12)
        assertThat(restored.exercises.map { it.supersetGroup }).isEqualTo(listOf<String?>(null, "A", "A", "A"))
        assertThat(restored.exercises[2].id).isEqualTo(removed.id)
    }

    @Test
    fun testRemovingTheFirstOrLastOfAThreeMemberSupersetKeepsTheGroup() {
        val legs = listOf(
            RedFix.entry(1, RedFix.lateral, RedFix.normal(2, 8.0, 15), rest = 60, group = "A"),
            RedFix.entry(2, RedFix.pushdown, RedFix.normal(2, 30.0, 12), rest = 60, group = "A"),
            RedFix.entry(3, RedFix.crossover, RedFix.normal(2, 15.0, 12), rest = 60, group = "A"),
        )
        val s = RedFix.state(legs)
        assertThat(RedFix.reduced(s, WorkoutAction.RemoveExercise(RedFix.ex(s, 0))).exercises.map { it.supersetGroup }).isEqualTo(listOf<String?>("A", "A"))
        assertThat(RedFix.reduced(s, WorkoutAction.RemoveExercise(RedFix.ex(s, 2))).exercises.map { it.supersetGroup }).isEqualTo(listOf<String?>("A", "A"))
    }

    @Test
    fun testUndoInsideTheWindowRestoresTheExerciseAtItsIndex() {
        var s = RedFix.designState()
        s = s.copy(currentIndex = 4)
        val removed = s.exercises[1]
        s = RedFix.reduced(s, WorkoutAction.RemoveExercise(removed.id), at = 100)
        assertThat(s.currentIndex).isEqualTo(3)
        s = RedFix.reduced(s, WorkoutAction.Undo, at = 103)
        assertThat(s.exercises.size).isEqualTo(6)
        assertThat(s.exercises[1]).isEqualTo(removed)
        assertThat(s.currentIndex).isEqualTo(1)      // the restored exercise becomes the current one
        assertThat(s.undo).isNull()
    }

    @Test
    fun testUndoExactlyAtTheEndOfTheWindowStillRestores() {
        var s = RedFix.designState()
        s = RedFix.reduced(s, WorkoutAction.RemoveExercise(RedFix.ex(s, 5)), at = 100)
        s = RedFix.reduced(s, WorkoutAction.Undo, at = 106)
        assertThat(s.exercises.size).isEqualTo(6)
        assertThat(s.currentIndex).isEqualTo(5)
        assertThat(s.undo).isNull()
    }

    @Test
    fun testUndoAfterTheWindowDoesNotRestoreButClearsTheEntry() {
        var s = RedFix.designState()
        s = RedFix.reduced(s, WorkoutAction.RemoveExercise(RedFix.ex(s, 1)), at = 100)
        s = RedFix.reduced(s, WorkoutAction.Undo, at = 106.5)
        assertThat(s.exercises.size).isEqualTo(5)
        assertThat(s.undo).isNull()
        // a second undo does nothing
        val again = RedFix.reduced(s, WorkoutAction.Undo, at = 107)
        assertThat(again).isEqualTo(s)
    }

    @Test
    fun testUndoRestoresADeletedSetAtItsIndexInsideTheWindow() {
        var s = RedFix.designState()
        val original = s.exercises[1].sets
        s = RedFix.reduced(s, WorkoutAction.DeleteSet(RedFix.ex(s, 1), RedFix.setID(s, 1, 1)), at = 10)
        s = RedFix.reduced(s, WorkoutAction.Undo, at = 15)
        assertThat(s.exercises[1].sets).isEqualTo(original)
        assertThat(s.undo).isNull()
    }

    @Test
    fun testUndoAfterTheWindowDoesNotRestoreADeletedSet() {
        var s = RedFix.designState()
        s = RedFix.reduced(s, WorkoutAction.DeleteSet(RedFix.ex(s, 1), RedFix.setID(s, 1, 1)), at = 10)
        s = RedFix.reduced(s, WorkoutAction.Undo, at = 17)
        assertThat(s.exercises[1].sets.size).isEqualTo(2)
        assertThat(s.undo).isNull()
    }

    @Test
    fun testOnlyTheLastDestructiveEditCanBeUndone() {
        var s = RedFix.designState()
        val removed = s.exercises[2]
        s = RedFix.reduced(s, WorkoutAction.DeleteSet(RedFix.ex(s, 1), RedFix.setID(s, 1, 0)), at = 1)
        s = RedFix.reduced(s, WorkoutAction.RemoveExercise(removed.id), at = 2)
        s = RedFix.reduced(s, WorkoutAction.Undo, at = 3)
        assertThat(s.exercises[2]).isEqualTo(removed)
        assertThat(s.exercises[1].sets.size).isEqualTo(2)   // the set deletion is gone for good
        assertThat(s.undo).isNull()
    }

    @Test
    fun testUndoWithoutAnEntryIsANoOp() {
        val s = RedFix.designState()
        assertThat(RedFix.reduced(s, WorkoutAction.Undo)).isEqualTo(s)
    }

    @Test
    fun testUndoNeverCreatesDuplicatesOrALoneSupersetMember() {
        // pair A: remove one leg (the other leaves the group), undo -> no single-member group is created
        var s = RedFix.designState()
        val removed = s.exercises[3]
        s = RedFix.reduced(s, WorkoutAction.RemoveExercise(removed.id), at = 1)
        s = RedFix.reduced(s, WorkoutAction.Undo, at = 2)
        assertThat(s.exercises[3].id).isEqualTo(removed.id)
        assertThat(s.exercises[3].supersetGroup).isNull()
        assertThat(s.exercises[4].supersetGroup).isNull()
        // the entry cannot be applied twice
        var dupe = RedFix.designState()
        val first = dupe.exercises[0]
        dupe = dupe.copy(undo = UndoEntry(payload = UndoPayload.RemovedExercise(index = 0, exercise = first), title = "x", expiresAt = RedFix.at(100)))
        dupe = RedFix.reduced(dupe, WorkoutAction.Undo, at = 1)
        assertThat(dupe.exercises.size).isEqualTo(6)
        assertThat(dupe.undo).isNull()
    }
}

// endregion

// region Rule 7: order, replace, add, rest per exercise

class WorkoutReducerListEditTests {
    @Test
    fun testMoveExerciseReordersAndTheCurrentExerciseKeepsItsPlace() {
        var s = RedFix.designState()
        s = s.copy(currentIndex = 2)
        val ohpID = RedFix.ex(s, 2)
        s = RedFix.reduced(s, WorkoutAction.MoveExercise(2, 0))
        assertThat(s.exercises.map { it.exercise.id }).isEqualTo(listOf("ohp", "bench", "incline", "lateral", "pushdown", "crossover"))
        assertThat(s.currentIndex).isEqualTo(0)
        assertThat(s.currentExercise?.id).isEqualTo(ohpID)

        // moving another exercise across the current one shifts the index
        s = s.copy(currentIndex = 1)                        // bench
        s = RedFix.reduced(s, WorkoutAction.MoveExercise(0, 4))
        assertThat(s.exercises.map { it.exercise.id }).isEqualTo(listOf("bench", "incline", "lateral", "pushdown", "ohp", "crossover"))
        assertThat(s.currentIndex).isEqualTo(0)
        assertThat(s.currentExercise?.exercise?.id).isEqualTo("bench")
    }

    @Test
    fun testMoveExerciseByStepsUpAndDown() {
        var s = RedFix.designState()
        s = s.copy(currentIndex = 1)
        s = RedFix.reduced(s, WorkoutAction.MoveExerciseBy(RedFix.ex(s, 1), 1))
        assertThat(s.exercises.map { it.exercise.id }).isEqualTo(listOf("bench", "ohp", "incline", "lateral", "pushdown", "crossover"))
        assertThat(s.currentIndex).isEqualTo(2)
        s = RedFix.reduced(s, WorkoutAction.MoveExerciseBy(RedFix.ex(s, 4), -1))
        assertThat(s.exercises.map { it.exercise.id }).isEqualTo(listOf("bench", "ohp", "incline", "pushdown", "lateral", "crossover"))
        assertThat(s.currentIndex).isEqualTo(2)
        s = RedFix.reduced(s, WorkoutAction.MoveExerciseBy(RedFix.ex(s, 0), 3))
        assertThat(s.exercises.map { it.exercise.id }).isEqualTo(listOf("ohp", "incline", "pushdown", "bench", "lateral", "crossover"))
        assertThat(s.currentExercise?.exercise?.id).isEqualTo("incline")
    }

    @Test
    fun testReplaceExerciseKeepsTheEntryIDAndSupersetGroup() {
        var s = RedFix.designState()
        s = RedFix.reduced(s, RedFix.toggle(s, 3, 0), at = 1)     // log a lateral raise set
        s = RedFix.editExercise(s, 3) { it.copy(note = "slow") }
        val oldID = RedFix.ex(s, 3)
        s = RedFix.reduced(s, WorkoutAction.ReplaceExercise(oldID, RedFix.pushup), at = 2)
        val replaced = s.exercises[3]
        assertThat(replaced.id).isEqualTo(oldID)
        assertThat(replaced.supersetGroup).isEqualTo("A")
        assertThat(replaced.exercise.id).isEqualTo("pushup")
        assertThat(replaced.sets.size).isEqualTo(3)
        assertThat(replaced.sets.all { !it.isDone && it.type == SetType.NORMAL && it.rir == null && it.reps == 12 && it.weightKg == 0.0 }).isTrue()
        assertThat(replaced.restSeconds).isEqualTo(60)
        assertThat(replaced.note).isEqualTo("")
        assertThat(s.lastLogged).isNull()       // it pointed at a set of the replaced exercise
        assertThat(s.exercises[4].supersetGroup).isEqualTo("A")
    }

    @Test
    fun testReplaceExerciseKeepsLastLoggedOfOtherExercisesAndTheTemplateLink() {
        var s = RedFix.designState()
        val template = RedFix.uuid(0x7E, 1)
        s = RedFix.editExercise(s, 1) { it.copy(templateEntryID = template) }
        s = RedFix.reduced(s, RedFix.toggle(s, 0, 2), at = 1)
        val last = s.lastLogged
        s = RedFix.reduced(s, WorkoutAction.ReplaceExercise(RedFix.ex(s, 1), RedFix.squat), at = 2)
        assertThat(s.lastLogged).isEqualTo(last)
        assertThat(s.exercises[1].templateEntryID).isEqualTo(template)
        assertThat(s.exercises[1].restSeconds).isEqualTo(180)
    }

    @Test
    fun testReplaceExerciseDropsAnUndoEntryForASetOfTheReplacedExercise() {
        var s = RedFix.designState()
        s = RedFix.reduced(s, WorkoutAction.DeleteSet(RedFix.ex(s, 1), RedFix.setID(s, 1, 0)), at = 1)
        s = RedFix.reduced(s, WorkoutAction.ReplaceExercise(RedFix.ex(s, 1), RedFix.squat), at = 2)
        assertThat(s.undo).isNull()
        // an undo entry for another exercise survives
        var t = RedFix.designState()
        t = RedFix.reduced(t, WorkoutAction.DeleteSet(RedFix.ex(t, 2), RedFix.setID(t, 2, 0)), at = 1)
        t = RedFix.reduced(t, WorkoutAction.ReplaceExercise(RedFix.ex(t, 1), RedFix.squat), at = 2)
        assertThat(t.undo).isNotNull()
    }

    @Test
    fun testAddExercisesAppendsEntriesWithDefaultSetsAndRest() {
        var s = RedFix.designState()
        s = s.copy(currentIndex = 2)
        s = RedFix.reduced(s, WorkoutAction.AddExercises(listOf(RedFix.plank, RedFix.squat, RedFix.plank)))
        assertThat(s.exercises.size).isEqualTo(9)
        assertThat(s.currentIndex).isEqualTo(2)
        val plank = s.exercises[6]
        assertThat(plank.exercise.id).isEqualTo("plank")
        assertThat(plank.sets.size).isEqualTo(3)
        assertThat(plank.sets.all { !it.isDone && it.reps == 45 && it.weightKg == 0.0 && it.type == SetType.NORMAL }).isTrue()
        assertThat(plank.restSeconds).isEqualTo(45)
        assertThat(plank.supersetGroup).isNull()
        assertThat(plank.templateEntryID).isNull()
        assertThat(plank.note).isEqualTo("")
        assertThat(s.exercises[7].sets.firstOrNull()?.weightKg).isEqualTo(60.0)
        assertThat(s.exercises[7].restSeconds).isEqualTo(180)
        assertThat(s.exercises.map { it.id }.toSet().size).isEqualTo(9)   // the same exercise twice gets two entries
    }

    @Test
    fun testAddExercisesToAnEmptyWorkoutSelectsTheFirst() {
        var s = WorkoutState(name = "Empty", currentIndex = 4, startedAt = RedFix.t0)
        s = RedFix.reduced(s, WorkoutAction.AddExercises(listOf(RedFix.bench, RedFix.incline)))
        assertThat(s.currentIndex).isEqualTo(0)
        assertThat(s.exercises.size).isEqualTo(2)
    }

    @Test
    fun testSetRestSetsSecondsAndClampsNegativeToZero() {
        var s = RedFix.designState()
        s = RedFix.reduced(s, WorkoutAction.SetRest(RedFix.ex(s, 1), 105))
        assertThat(s.exercises[1].restSeconds).isEqualTo(105)
        s = RedFix.reduced(s, WorkoutAction.SetRest(RedFix.ex(s, 1), -20))
        assertThat(s.exercises[1].restSeconds).isEqualTo(0)
        s = RedFix.reduced(s, WorkoutAction.SetRest(RedFix.ex(s, 1), 0))
        assertThat(s.exercises[1].restSeconds).isEqualTo(0)
        assertThat(s.exercises[0].restSeconds).isEqualTo(150)
    }
}

// endregion

// region Rule 8: supersets

class WorkoutReducerSupersetTests {
    @Test
    fun testJoiningTheNextExerciseUsesTheFirstUnusedLetter() {
        var s = RedFix.designState()                  // letter A is taken by lateral + pushdown
        s = RedFix.reduced(s, WorkoutAction.ToggleSuperset(RedFix.ex(s, 1)))
        assertThat(s.exercises.map { it.supersetGroup }).isEqualTo(listOf<String?>(null, "B", "B", "A", "A", null))
    }

    @Test
    fun testJoiningAnExerciseThatIsNextToAGroupTakesThatGroup() {
        var s = RedFix.designState()
        s = RedFix.reduced(s, WorkoutAction.ToggleSuperset(RedFix.ex(s, 2)))   // ohp joins the lateral's group
        assertThat(s.exercises.map { it.supersetGroup }).isEqualTo(listOf<String?>(null, null, "A", "A", "A", null))
    }

    @Test
    fun testLeavingAGroupOfThreeKeepsTheOthers() {
        var s = RedFix.designState()
        s = RedFix.reduced(s, WorkoutAction.ToggleSuperset(RedFix.ex(s, 2)))
        s = RedFix.reduced(s, WorkoutAction.ToggleSuperset(RedFix.ex(s, 3)))
        val expected: List<String?> = listOf(null, null, "A", null, "A", null)
        assertThat(s.exercises.map { it.supersetGroup }).isEqualTo(expected)   // ohp + pushdown stay together
    }

    @Test
    fun testLeavingAGroupOfTwoReleasesBothMembers() {
        val s = RedFix.designState()
        val first = RedFix.reduced(s, WorkoutAction.ToggleSuperset(RedFix.ex(s, 3)))
        assertThat(first.exercises.map { it.supersetGroup }).isEqualTo(listOf<String?>(null, null, null, null, null, null))
        val second = RedFix.reduced(s, WorkoutAction.ToggleSuperset(RedFix.ex(s, 4)))
        assertThat(second.exercises.map { it.supersetGroup }).isEqualTo(listOf<String?>(null, null, null, null, null, null))
    }

    @Test
    fun testTheLastExerciseCannotJoinANextOne() {
        val s = RedFix.designState()
        assertThat(RedFix.reduced(s, WorkoutAction.ToggleSuperset(RedFix.ex(s, 5)))).isEqualTo(s)
    }

    @Test
    fun testLetterIsReusedAfterTheGroupIsDissolved() {
        var s = RedFix.designState()
        s = RedFix.reduced(s, WorkoutAction.ToggleSuperset(RedFix.ex(s, 3)))     // dissolve A
        s = RedFix.reduced(s, WorkoutAction.ToggleSuperset(RedFix.ex(s, 0)))     // bench + incline
        assertThat(s.exercises.map { it.supersetGroup }).isEqualTo(listOf<String?>("A", "A", null, null, null, null))
    }

    @Test
    fun testRunsOutOfLettersFallsBackToZ() {
        val entries = mutableListOf<WorkoutExercise>()
        val letters = listOf("A", "B", "C", "D", "E")
        for ((n, letter) in letters.withIndex()) {
            entries.add(RedFix.entry(n * 2 + 1, RedFix.lateral, RedFix.normal(1, 8.0, 15), rest = 60, group = letter))
            entries.add(RedFix.entry(n * 2 + 2, RedFix.pushdown, RedFix.normal(1, 30.0, 12), rest = 60, group = letter))
        }
        entries.add(RedFix.entry(11, RedFix.bench, RedFix.normal(1, 60.0, 8), rest = 150))
        entries.add(RedFix.entry(12, RedFix.ohp, RedFix.normal(1, 40.0, 8), rest = 120))
        var s = RedFix.state(entries)
        s = RedFix.reduced(s, WorkoutAction.ToggleSuperset(RedFix.ex(s, 10)))
        assertThat(s.exercises[10].supersetGroup).isEqualTo("Z")
        assertThat(s.exercises[11].supersetGroup).isEqualTo("Z")
    }

    @Test
    fun testSupersetsCreatedWithTheToggleDriveLogging() {
        var s = RedFix.state(
            listOf(
                RedFix.entry(1, RedFix.lateral, RedFix.normal(2, 8.0, 15), rest = 60),
                RedFix.entry(2, RedFix.pushdown, RedFix.normal(2, 30.0, 12), rest = 60),
            ),
        )
        s = RedFix.reduced(s, WorkoutAction.ToggleSuperset(RedFix.ex(s, 0)))
        s = RedFix.reduced(s, RedFix.toggle(s, 0, 0), at = 1)
        assertThat(s.currentIndex).isEqualTo(1)
        assertThat(s.rest).isNull()
    }
}

// endregion

// region Rule 9: rest timer

class WorkoutReducerRestTests {
    private fun resting(endsAt: Double, total: Int): WorkoutState =
        RedFix.designState().copy(rest = RestState(endsAt = RedFix.at(endsAt), totalSeconds = total))

    @Test
    fun testAdjustRestStartsARestWhenNoneRuns() {
        val s = RedFix.reduced(RedFix.designState(), WorkoutAction.AdjustRest(15), at = 100)
        assertThat(s.rest).isEqualTo(RestState(endsAt = RedFix.at(115), totalSeconds = 15))
        // and a non-positive request without a rest does nothing
        assertThat(RedFix.reduced(RedFix.designState(), WorkoutAction.AdjustRest(-15), at = 100)).isEqualTo(RedFix.designState())
        assertThat(RedFix.reduced(RedFix.designState(), WorkoutAction.AdjustRest(0), at = 100)).isEqualTo(RedFix.designState())
    }

    @Test
    fun testAdjustRestMovesTheEndAndTheTotal() {
        var s = resting(endsAt = 200.0, total = 90)
        s = RedFix.reduced(s, WorkoutAction.AdjustRest(15), at = 150)
        assertThat(s.rest).isEqualTo(RestState(endsAt = RedFix.at(215), totalSeconds = 105))
        s = RedFix.reduced(s, WorkoutAction.AdjustRest(-15), at = 150)
        s = RedFix.reduced(s, WorkoutAction.AdjustRest(-15), at = 150)
        assertThat(s.rest).isEqualTo(RestState(endsAt = RedFix.at(185), totalSeconds = 75))
    }

    @Test
    fun testAdjustRestNeverEndsBeforeNowAndKeepsAtLeastFiveSeconds() {
        var s = resting(endsAt = 160.0, total = 20)
        s = RedFix.reduced(s, WorkoutAction.AdjustRest(-15), at = 150)       // 10 s left -> ends now
        assertThat(s.rest).isEqualTo(RestState(endsAt = RedFix.at(150), totalSeconds = 5))
        s = RedFix.reduced(s, WorkoutAction.AdjustRest(-15), at = 150)
        assertThat(s.rest).isEqualTo(RestState(endsAt = RedFix.at(150), totalSeconds = 5))
    }

    @Test
    fun testAdjustRestOnAFinishedRestRestartsFromNow() {
        var s = resting(endsAt = 100.0, total = 60)                    // finished 50 s ago
        s = RedFix.reduced(s, WorkoutAction.AdjustRest(15), at = 150)
        assertThat(s.rest).isEqualTo(RestState(endsAt = RedFix.at(165), totalSeconds = 75))
    }

    @Test
    fun testAdjustRestWhilePausedAdjustsTheFrozenRemainingTime() {
        var s = resting(endsAt = 250.0, total = 150)
        s = RedFix.reduced(s, WorkoutAction.Pause, at = 130)                          // 120 s frozen
        s = RedFix.reduced(s, WorkoutAction.AdjustRest(15), at = 200)
        assertThat(s.rest?.frozenRemaining).isEqualTo(135.0)
        assertThat(s.rest?.totalSeconds).isEqualTo(165)
        assertThat(s.rest?.endsAt).isEqualTo(RedFix.at(250))                  // untouched while frozen
        s = RedFix.reduced(s, WorkoutAction.AdjustRest(-200), at = 210)
        assertThat(s.rest?.frozenRemaining).isEqualTo(0.0)                 // never negative
        assertThat(s.rest?.totalSeconds).isEqualTo(5)
        // a rest started with the plus button while paused is frozen too
        var empty = RedFix.reduced(RedFix.designState(), WorkoutAction.Pause, at = 5)
        empty = RedFix.reduced(empty, WorkoutAction.AdjustRest(30), at = 6)
        assertThat(empty.rest).isEqualTo(RestState(endsAt = RedFix.at(36), totalSeconds = 30, frozenRemaining = 30.0))
    }

    @Test
    fun testSkipRestClearsTheRest() {
        var s = resting(endsAt = 200.0, total = 90)
        s = RedFix.reduced(s, WorkoutAction.SkipRest, at = 150)
        assertThat(s.rest).isNull()
        assertThat(s.revision).isEqualTo(1)
        assertThat(RedFix.reduced(s, WorkoutAction.SkipRest)).isEqualTo(s)                 // nothing to skip
    }

    @Test
    fun testRestSettingFlagsAreStored() {
        var s = RedFix.designState()
        s = RedFix.reduced(s, WorkoutAction.SetAutoStartRest(false))
        assertThat(s.settings.autoStartRest).isFalse()
        assertThat(s.settings.alertWhenRestEnds).isTrue()
        s = RedFix.reduced(s, WorkoutAction.SetAlertWhenRestEnds(false))
        assertThat(s.settings.alertWhenRestEnds).isFalse()
        s = RedFix.reduced(s, WorkoutAction.SetAutoStartRest(true))
        assertThat(s.settings.autoStartRest).isTrue()
        assertThat(s.revision).isEqualTo(3)
    }
}

// endregion

// region Rule 10: pause and resume

class WorkoutReducerPauseTests {
    @Test
    fun testPauseFreezesTheRunningRest() {
        var s = RedFix.designState()
        s = RedFix.reduced(s, RedFix.toggle(s, 0, 2), at = 100)               // 150 s rest, ends 250
        s = RedFix.reduced(s, WorkoutAction.Pause, at = 130)
        assertThat(s.pausedAt).isEqualTo(RedFix.at(130))
        assertThat(s.rest?.frozenRemaining).isEqualTo(120.0)
        assertThat(s.restRemaining(RedFix.at(5_000))).isEqualTo(120.0)
        assertThat(s.isPaused).isTrue()
    }

    @Test
    fun testResumeAddsThePauseToTheTotalAndThawsTheRest() {
        var s = RedFix.designState()
        s = RedFix.reduced(s, RedFix.toggle(s, 0, 2), at = 100)
        s = RedFix.reduced(s, WorkoutAction.Pause, at = 130)
        s = RedFix.reduced(s, WorkoutAction.Resume, at = 330)
        assertThat(s.pausedAt).isNull()
        assertThat(s.pausedTotal).isEqualTo(200.0)
        assertThat(s.rest).isEqualTo(RestState(endsAt = RedFix.at(450), totalSeconds = 150))
        assertThat(s.restRemaining(RedFix.at(400))).isEqualTo(50.0)
        assertThat(s.isPaused).isFalse()
    }

    @Test
    fun testElapsedTimeExcludesPauses() {
        var s = RedFix.designState()
        s = RedFix.reduced(s, WorkoutAction.Pause, at = 100)
        assertThat(s.elapsedSeconds(RedFix.at(200))).isEqualTo(100)
        s = RedFix.reduced(s, WorkoutAction.Resume, at = 300)
        assertThat(s.elapsedSeconds(RedFix.at(400))).isEqualTo(200)
        s = RedFix.reduced(s, WorkoutAction.Pause, at = 400)
        s = RedFix.reduced(s, WorkoutAction.Resume, at = 450)
        assertThat(s.pausedTotal).isEqualTo(250.0)
        assertThat(s.elapsedSeconds(RedFix.at(500))).isEqualTo(250)
    }

    @Test
    fun testPauseWithoutRestOnlySetsThePauseTime() {
        val s = RedFix.reduced(RedFix.designState(), WorkoutAction.Pause, at = 50)
        assertThat(s.pausedAt).isEqualTo(RedFix.at(50))
        assertThat(s.rest).isNull()
        assertThat(RedFix.reduced(s, WorkoutAction.Resume, at = 60).rest).isNull()
    }

    @Test
    fun testPausingTwiceOrResumingWhileRunningIsANoOp() {
        var s = RedFix.designState()
        s = RedFix.reduced(s, RedFix.toggle(s, 0, 2), at = 100)
        assertThat(RedFix.reduced(s, WorkoutAction.Resume, at = 120)).isEqualTo(s)
        val paused = RedFix.reduced(s, WorkoutAction.Pause, at = 130)
        assertThat(RedFix.reduced(paused, WorkoutAction.Pause, at = 140)).isEqualTo(paused)
    }

    @Test
    fun testResumeOfAFinishedFrozenRestEndsRightNow() {
        var s = RedFix.designState()
        s = s.copy(rest = RestState(endsAt = RedFix.at(100), totalSeconds = 60))    // already over
        s = RedFix.reduced(s, WorkoutAction.Pause, at = 150)
        assertThat(s.rest?.frozenRemaining).isEqualTo(0.0)
        s = RedFix.reduced(s, WorkoutAction.Resume, at = 160)
        assertThat(s.rest?.endsAt).isEqualTo(RedFix.at(160))
        assertThat(s.rest?.frozenRemaining).isNull()
        assertThat(s.restRemaining(RedFix.at(160))).isEqualTo(0.0)
    }

    @Test
    fun testResumeNeverMovesTheClockBackwards() {
        var s = RedFix.designState()
        s = RedFix.reduced(s, WorkoutAction.Pause, at = 100)
        s = RedFix.reduced(s, WorkoutAction.Resume, at = 90)            // clock skew
        assertThat(s.pausedTotal).isEqualTo(0.0)
        assertThat(s.pausedAt).isNull()
    }

    @Test
    fun testPauseAndResumeKeepTheFrozenInvariant() {
        var s = RedFix.designState()
        s = RedFix.reduced(s, RedFix.toggle(s, 0, 2), at = 10)
        s = RedFix.reduced(s, WorkoutAction.Pause, at = 20)
        assertThat(s.rest?.frozenRemaining).isNotNull()
        s = RedFix.reduced(s, RedFix.toggle(s, 0, 3), at = 30)               // new rest while paused
        assertThat(s.rest?.frozenRemaining).isNotNull()
        s = RedFix.reduced(s, WorkoutAction.Resume, at = 40)
        assertThat(s.rest?.frozenRemaining).isNull()
        assertThat(s.rest?.endsAt).isEqualTo(RedFix.at(190))
    }
}

// endregion

// region Rule 11: navigation, flags, heart rate

class WorkoutReducerMiscTests {
    @Test
    fun testGoToNextAndPreviousClamp() {
        var s = RedFix.designState()
        s = RedFix.reduced(s, WorkoutAction.GoTo(3))
        assertThat(s.currentIndex).isEqualTo(3)
        s = RedFix.reduced(s, WorkoutAction.GoTo(99))
        assertThat(s.currentIndex).isEqualTo(5)
        s = RedFix.reduced(s, WorkoutAction.NextExercise)
        assertThat(s.currentIndex).isEqualTo(5)
        s = RedFix.reduced(s, WorkoutAction.GoTo(-2))
        assertThat(s.currentIndex).isEqualTo(0)
        s = RedFix.reduced(s, WorkoutAction.PreviousExercise)
        assertThat(s.currentIndex).isEqualTo(0)
        s = RedFix.reduced(s, WorkoutAction.NextExercise)
        s = RedFix.reduced(s, WorkoutAction.NextExercise)
        assertThat(s.currentIndex).isEqualTo(2)
        s = RedFix.reduced(s, WorkoutAction.PreviousExercise)
        assertThat(s.currentIndex).isEqualTo(1)
    }

    @Test
    fun testNavigationDoesNotTouchTheRest() {
        var s = RedFix.designState()
        s = RedFix.reduced(s, RedFix.toggle(s, 0, 2), at = 1)
        val rest = s.rest
        s = RedFix.reduced(s, WorkoutAction.NextExercise, at = 2)
        assertThat(s.rest).isEqualTo(rest)
    }

    @Test
    fun testFlagsAndNameAreSet() {
        var s = RedFix.designState()
        s = RedFix.reduced(s, WorkoutAction.SetUsedWatch(true))
        assertThat(s.usedWatch).isTrue()
        s = RedFix.reduced(s, WorkoutAction.SetUsedWatch(false))
        assertThat(s.usedWatch).isFalse()
        s = RedFix.reduced(s, WorkoutAction.Rename("Push day"))
        assertThat(s.name).isEqualTo("Push day")
        assertThat(s.revision).isEqualTo(3)
    }

    @Test
    fun testUpdateHeartRateStoresSamplesWithoutBumpingTheRevision() {
        var s = RedFix.designState()
        s = s.copy(revision = 7)
        s = RedFix.reduced(s, WorkoutAction.UpdateHeartRate(120), at = 1)
        assertThat(s.heartRate).isEqualTo(120)
        assertThat(s.heartRateSum).isEqualTo(120)
        assertThat(s.heartRateCount).isEqualTo(1)
        s = RedFix.reduced(s, WorkoutAction.UpdateHeartRate(130), at = 2)
        assertThat(s.heartRate).isEqualTo(130)
        assertThat(s.heartRateSum).isEqualTo(250)
        assertThat(s.heartRateCount).isEqualTo(2)
        assertThat(s.averageHeartRate).isEqualTo(125)
        assertThat(s.revision).isEqualTo(7)
        // the next real change bumps by exactly one
        s = RedFix.reduced(s, WorkoutAction.Rename("x"), at = 3)
        assertThat(s.revision).isEqualTo(8)
    }

    @Test
    fun testHeartRateRangeAndNilHandling() {
        var s = RedFix.designState()
        s = RedFix.reduced(s, WorkoutAction.UpdateHeartRate(30))
        s = RedFix.reduced(s, WorkoutAction.UpdateHeartRate(240))
        assertThat(s.heartRateCount).isEqualTo(2)
        assertThat(s.heartRateSum).isEqualTo(270)
        s = RedFix.reduced(s, WorkoutAction.UpdateHeartRate(29))       // shown, but not averaged
        assertThat(s.heartRate).isEqualTo(29)
        s = RedFix.reduced(s, WorkoutAction.UpdateHeartRate(241))
        assertThat(s.heartRate).isEqualTo(241)
        s = RedFix.reduced(s, WorkoutAction.UpdateHeartRate(0))
        assertThat(s.heartRateCount).isEqualTo(2)
        assertThat(s.heartRateSum).isEqualTo(270)
        s = RedFix.reduced(s, WorkoutAction.UpdateHeartRate(null))      // sensor lost
        assertThat(s.heartRate).isNull()
        assertThat(s.heartRateCount).isEqualTo(2)
        assertThat(s.revision).isEqualTo(0)
    }

    @Test
    fun testHeartRateChangesNothingElse() {
        var s = RedFix.designState()
        s = RedFix.reduced(s, RedFix.toggle(s, 0, 2), at = 1)
        val expected = s.copy(
            heartRate = 140,
            heartRateSum = 140,
            heartRateCount = 1,
            heartRateSeries = listOf(HeartRateSample(140, RedFix.at(50))),
        )
        assertThat(RedFix.reduced(s, WorkoutAction.UpdateHeartRate(140), at = 50)).isEqualTo(expected)
    }
}

// endregion

// region Kotlin-only additions (no Swift test)
//
// Rules of ARCHITECTURE.md section 3 that no Swift test of these five files exercises (found by mutation testing the Kotlin reducer: removing
// the clamp or the guard did not fail any ported test). The expectations follow the Swift reducer.

class WorkoutReducerKotlinOnlyTests {
    @Test
    fun testKotlinOnlyLimitsAreTheDocumentedOnes() {
        assertThat(WorkoutReducer.maximumWeightKg).isEqualTo(1_000_000.0)
        assertThat(WorkoutReducer.maximumRestSeconds).isEqualTo(3_600)
    }

    /** Rule 3: `setWeight` clamps to 0...`maximumWeightKg` (the fuzz test only checks that weights stay finite). */
    @Test
    fun testKotlinOnlySetWeightClampsToTheMaximum() {
        val s = RedFix.designState()
        val e = RedFix.ex(s, 0)
        val id = RedFix.setID(s, 0, 2)
        fun weight(kg: Double): Double = RedFix.reduced(s, WorkoutAction.SetWeight(e, id, kg)).exercises[0].sets[2].weightKg
        assertThat(weight(1e300)).isEqualTo(1_000_000.0)
        assertThat(weight(Double.MAX_VALUE)).isEqualTo(1_000_000.0)
        assertThat(weight(1_000_000.01)).isEqualTo(1_000_000.0)
        assertThat(weight(1_000_000.0)).isEqualTo(1_000_000.0)
        assertThat(weight(999_999.999)).isEqualTo(1_000_000.0)
        assertThat(weight(123_456.789)).isWithin(1e-9).of(123_456.79)
    }

    /** Rule 7: `setRest` and the default rest of a new or replaced exercise are clamped to 0...`maximumRestSeconds`. */
    @Test
    fun testKotlinOnlyRestIsClampedToOneHour() {
        var s = RedFix.designState()
        val id = RedFix.ex(s, 1)
        assertThat(RedFix.reduced(s, WorkoutAction.SetRest(id, 3_600)).exercises[1].restSeconds).isEqualTo(3_600)
        assertThat(RedFix.reduced(s, WorkoutAction.SetRest(id, 3_601)).exercises[1].restSeconds).isEqualTo(3_600)
        assertThat(RedFix.reduced(s, WorkoutAction.SetRest(id, Int.MAX_VALUE)).exercises[1].restSeconds).isEqualTo(3_600)
        assertThat(RedFix.reduced(s, WorkoutAction.SetRest(id, Int.MIN_VALUE)).exercises[1].restSeconds).isEqualTo(0)

        val endless = RedFix.exercise("endless", "Endless rest", MuscleGroup.CORE, Equipment.OTHER, kg = 10.0, reps = 5, rest = 99_999)
        val negative = RedFix.exercise("negative", "Negative rest", MuscleGroup.CORE, Equipment.OTHER, kg = 10.0, reps = 5, rest = -30)
        s = RedFix.reduced(s, WorkoutAction.AddExercises(listOf(endless, negative)))
        assertThat(s.exercises[6].restSeconds).isEqualTo(3_600)
        assertThat(s.exercises[7].restSeconds).isEqualTo(0)
        s = RedFix.reduced(s, WorkoutAction.ReplaceExercise(RedFix.ex(s, 0), endless))
        assertThat(s.exercises[0].restSeconds).isEqualTo(3_600)
    }

    /** `WorkoutTemplate.estimatedMinutes` counts a rest outside 0...3,600 as the nearest bound (rule 7). */
    @Test
    fun testKotlinOnlyTemplateEstimateClampsTheRest() {
        fun template(rest: Int): WorkoutTemplate = WorkoutTemplate(
            id = RedFix.uuid(0x2FD, 1), name = "Clamp",
            entries = listOf(RedTemplateFix.entry(1, RedFix.bench, RedTemplateFix.planned(1, 60.0, 8), rest = rest)),
        )
        // one set: 45 s of work plus the rest, in minutes rounded to 5
        assertThat(template(Int.MAX_VALUE).estimatedMinutes).isEqualTo(template(3_600).estimatedMinutes)
        assertThat(template(3_600).estimatedMinutes).isEqualTo(60)   // (45 + 3600) s = 60.75 min
        assertThat(template(Int.MIN_VALUE).estimatedMinutes).isEqualTo(template(0).estimatedMinutes)
        assertThat(template(0).estimatedMinutes).isEqualTo(5)        // 45 s = 0.75 min, at least 5
    }

    /** `undo` of a deleted set whose id exists again (in any exercise) must not duplicate it; the entry is still cleared. */
    @Test
    fun testKotlinOnlyUndoOfADeletedSetNeverDuplicatesASetID() {
        val base = RedFix.designState()
        val existing = base.exercises[1].sets[1]
        // same set id still in the same exercise
        val sameExercise = base.copy(undo = UndoEntry(UndoPayload.DeletedSet(RedFix.ex(base, 1), 1, existing), "Set deleted", RedFix.at(100)))
        val a = RedFix.reduced(sameExercise, WorkoutAction.Undo, at = 1)
        assertThat(a.exercises).isEqualTo(base.exercises)
        assertThat(a.undo).isNull()
        // same set id in another exercise
        val otherExercise = base.copy(undo = UndoEntry(UndoPayload.DeletedSet(RedFix.ex(base, 2), 0, existing), "Set deleted", RedFix.at(100)))
        val b = RedFix.reduced(otherExercise, WorkoutAction.Undo, at = 1)
        assertThat(b.exercises).isEqualTo(base.exercises)
        assertThat(b.undo).isNull()
    }

    @Test
    fun testKotlinOnlyUndoOfASetOfAnUnknownExerciseOnlyClearsTheEntry() {
        val base = RedFix.designState()
        val lost = base.exercises[1].sets[1].copy(id = RedFix.uuid(0xDEAD, 8))
        val s = base.copy(undo = UndoEntry(UndoPayload.DeletedSet(RedFix.uuid(0xDEAD, 7), 0, lost), "Set deleted", RedFix.at(100)))
        val after = RedFix.reduced(s, WorkoutAction.Undo, at = 1)
        assertThat(after.exercises).isEqualTo(base.exercises)
        assertThat(after.undo).isNull()
    }

    /** The restore index of an undo entry is clamped into the list (`max(0, min(index, count))`). */
    @Test
    fun testKotlinOnlyUndoClampsTheRestoreIndex() {
        val base = RedFix.designState()
        val removed = base.exercises[1]
        val without = RedFix.reduced(base, WorkoutAction.RemoveExercise(removed.id), at = 1)
        val late = without.copy(undo = UndoEntry(UndoPayload.RemovedExercise(99, removed), "Removed", RedFix.at(100)))
        val appended = RedFix.reduced(late, WorkoutAction.Undo, at = 2)
        assertThat(appended.exercises.last().id).isEqualTo(removed.id)
        assertThat(appended.currentIndex).isEqualTo(5)
        val early = without.copy(undo = UndoEntry(UndoPayload.RemovedExercise(-5, removed), "Removed", RedFix.at(100)))
        val prepended = RedFix.reduced(early, WorkoutAction.Undo, at = 2)
        assertThat(prepended.exercises.first().id).isEqualTo(removed.id)
        assertThat(prepended.currentIndex).isEqualTo(0)

        val kept = base.exercises[1].sets[1]
        val withoutSet = RedFix.reduced(base, WorkoutAction.DeleteSet(RedFix.ex(base, 1), kept.id), at = 1)
        val lateSet = withoutSet.copy(undo = UndoEntry(UndoPayload.DeletedSet(RedFix.ex(base, 1), 99, kept), "Set deleted", RedFix.at(100)))
        assertThat(RedFix.reduced(lateSet, WorkoutAction.Undo, at = 2).exercises[1].sets.last().id).isEqualTo(kept.id)
        val earlySet = withoutSet.copy(undo = UndoEntry(UndoPayload.DeletedSet(RedFix.ex(base, 1), -5, kept), "Set deleted", RedFix.at(100)))
        assertThat(RedFix.reduced(earlySet, WorkoutAction.Undo, at = 2).exercises[1].sets.first().id).isEqualTo(kept.id)
    }
}

// endregion
