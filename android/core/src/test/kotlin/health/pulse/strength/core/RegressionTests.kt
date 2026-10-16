package health.pulse.strength.core

import com.google.common.truth.Truth.assertThat
import com.google.common.truth.Truth.assertWithMessage
import java.io.File
import java.time.Instant
import java.util.UUID
import org.junit.After
import org.junit.Test

// Port of RegressionTests.swift (Swift: 3 tests).

/**
 * One test per verified bug, named after its id. Each test uses only the documented bounds (as literals), so it states the
 * contract in ARCHITECTURE.md and not the name of a constant.
 */
class RegressionTests {
    /** The subset of the reducer test fixtures (Swift `RedFix`) these tests need, kept private to this class. */
    private object Fix {
        val t0: Instant = Instant.ofEpochSecond(1_800_000_000L)

        fun at(seconds: Double): Instant = t0.addingTimeInterval(seconds)

        fun at(seconds: Int): Instant = at(seconds.toDouble())

        fun uuid(high: Int, low: Int): UUID {
            fun hex(value: Int, width: Int): String {
                val digits = value.toString(16)
                return "0".repeat(maxOf(0, width - digits.length)) + digits
            }
            return UUID.fromString("00000000-0000-0000-${hex(high, 4)}-${hex(low, 12)}")
        }

        fun exercise(
            id: String,
            name: String,
            muscle: MuscleGroup,
            equipment: Equipment,
            best: Double = 0.0,
            kg: Double,
            reps: Int,
            rest: Int,
        ): Exercise = Exercise(
            id = id, name = name, muscle = muscle, secondary = "", equipment = equipment, tracking = TrackingKind.WEIGHT_REPS,
            mediaKey = null, previousBestE1RM = best, previousSets = emptyList(),
            defaults = ExerciseDefaults(sets = 3, weightKg = kg, reps = reps, restSeconds = rest),
            cues = emptyList(), barKg = 20.0, isCustom = false,
        )

        val bench = exercise("bench", "Barbell bench press", MuscleGroup.CHEST, Equipment.BARBELL, best = 99.0, kg = 60.0, reps = 8, rest = 150)
        val incline = exercise("incline", "Incline dumbbell press", MuscleGroup.CHEST, Equipment.DUMBBELL, best = 38.0, kg = 24.0, reps = 10, rest = 90)
        val ohp = exercise("ohp", "Overhead press", MuscleGroup.SHOULDERS, Equipment.BARBELL, best = 58.0, kg = 40.0, reps = 8, rest = 120)
        val lateral = exercise("lateral", "Dumbbell lateral raise", MuscleGroup.SHOULDERS, Equipment.DUMBBELL, best = 12.5, kg = 8.0, reps = 15, rest = 60)
        val pushdown = exercise("pushdown", "Triceps pushdown", MuscleGroup.ARMS, Equipment.CABLE, best = 43.0, kg = 30.0, reps = 12, rest = 60)
        val crossover = exercise("crossover", "Cable crossover", MuscleGroup.CHEST, Equipment.CABLE, best = 22.0, kg = 15.0, reps = 12, rest = 60)

        private fun normal(count: Int, kg: Double, reps: Int): List<Triple<SetType, Double, Int>> = List(count) { Triple(SetType.NORMAL, kg, reps) }

        /** Entry number `n` (1-based) with deterministic ids: entry `uuid(0x100 + n, 0)`, sets `uuid(0x100 + n, i + 1)`. */
        private fun entry(n: Int, exercise: Exercise, sets: List<Triple<SetType, Double, Int>>, rest: Int, group: String? = null): WorkoutExercise =
            WorkoutExercise(
                id = uuid(0x100 + n, 0),
                exercise = exercise,
                sets = sets.mapIndexed { offset, spec -> LoggedSet(id = uuid(0x100 + n, offset + 1), type = spec.first, weightKg = spec.second, reps = spec.third) },
                restSeconds = rest,
                supersetGroup = group,
                note = "",
                templateEntryID = null,
            )

        /** The design's workout, nothing logged yet. */
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
    }

    private val temporaryDirectories = mutableListOf<File>()

    private fun temporaryPersistence(): FileStrengthPersistence {
        val persistence = FileStrengthPersistence.temporary()
        temporaryDirectories.add(persistence.directory)
        return persistence
    }

    @After
    fun removeTemporaryDirectories() {
        for (directory in temporaryDirectories) directory.deleteRecursively()
        temporaryDirectories.clear()
    }

    // region B1: an unbounded weight traps the presenter

    /**
     * The reducer used to accept any finite weight (1e20, 1e300). Logged as a personal record, it made
     * `WorkoutPresenter` convert an enormous Double to Int and trap, and because the active workout is saved after every change
     * the same state trapped again on every launch.
     *
     * Kotlin note: `Double.toInt()` saturates instead of trapping, so "never traps" is not observable here; the assertions that
     * matter are kept (the reducer's bound, the personal record at the bound, and presenter / snapshot / summary on a state
     * with an absurd stored weight that round-trips through the persistence file).
     */
    @Test
    fun testB1_AnAbsurdWeightIsBoundedAndNeverTrapsThePresenter() {
        val maximumKg = 1_000_000.0 // ARCHITECTURE 3.2 rule 3

        // The reducer bounds the weight (and still keeps what the keypad can type: at most 6 characters, so 999999).
        val design = Fix.designState()
        val exercise = design.exercises[0]
        val setID = exercise.sets[2].id
        fun weight(kg: Double): Double {
            val s = WorkoutReducer.reduce(design, WorkoutAction.SetWeight(exercise.id, setID, kg), Fix.t0)
            return s.exercises[0].sets[2].weightKg
        }
        assertWithMessage("a value the keypad can produce is kept").that(weight(999_999.0)).isEqualTo(999_999.0)
        assertThat(weight(1e20)).isEqualTo(maximumKg)
        assertThat(weight(1e300)).isEqualTo(maximumKg)
        assertThat(weight(Double.MAX_VALUE)).isEqualTo(maximumKg)
        assertThat(weight(-1e20)).isEqualTo(0.0)
        assertWithMessage("not representable: still ignored").that(weight(Double.POSITIVE_INFINITY)).isEqualTo(82.5)
        assertWithMessage("still ignored").that(weight(Double.NaN)).isEqualTo(82.5)

        // The reported scenario: a record set with the absurd weight, then present (this trapped).
        var s = design
        s = WorkoutReducer.reduce(s, WorkoutAction.SetWeight(exercise.id, setID, 1e20), Fix.t0)
        s = WorkoutReducer.reduce(s, WorkoutAction.LogSet(exercise.id, setID), Fix.at(1))
        val view = WorkoutPresenter.present(s, Fix.at(2), DemoRecovery.provider)
        val row = PresFix.unwrap(view.card?.rows?.get(2))
        assertThat(row.isPersonalRecord).isTrue()
        assertThat(row.estimated1RM).isNotNull()

        // A state that did not come through the reducer (a file saved by an older build, a corrupt file, a decoded sync message)
        // must not crash the presenter either. The weights below are what an older build could have saved.
        for (kg in listOf(1e20, 1e300, Double.MAX_VALUE)) {
            val raw = PresFix.editSet(design, 0, 2) { it.copy(weightKg = kg, isDone = true) }

            val persistence = temporaryPersistence()
            persistence.saveActiveWorkout(raw)
            val reloaded = PresFix.unwrap(persistence.loadActiveWorkout())

            val shown = WorkoutPresenter.present(reloaded, Fix.at(2), DemoRecovery.provider)
            assertThat(shown.card?.rows?.size).isEqualTo(5)
            SnapshotBuilder.make(reloaded, Fix.at(2))
            val summary = SummaryBuilder.build(reloaded, Fix.at(3))
            assertThat(summary.loggedSets).isEqualTo(1)
            assertWithMessage("an estimate that overflowed is not stored").that(summary.exercises.all { it.bestE1RM.isFinite() }).isTrue()
            assertThat(summary.personalRecords.all { it.estimated1RM.isFinite() }).isTrue()
        }
    }

    // endregion

    // region B2: an unbounded rest overflows the template estimate

    /**
     * `setRest(Int.max)` was accepted, copied into a saved template and `WorkoutTemplate.estimatedMinutes` (shown on the hub)
     * overflowed its integer arithmetic.
     */
    @Test
    fun testB2_AnAbsurdRestIsBoundedAndTheTemplateEstimateNeverTraps() {
        val maximumRest = 3_600 // ARCHITECTURE 3.2 rule 7

        val design = Fix.designState()
        val exerciseID = design.exercises[0].id
        fun rest(seconds: Int): Int {
            val s = WorkoutReducer.reduce(design, WorkoutAction.SetRest(exerciseID, seconds), Fix.t0)
            return s.exercises[0].restSeconds
        }
        assertThat(rest(0)).isEqualTo(0)
        assertThat(rest(105)).isEqualTo(105)
        assertWithMessage("the bound itself is allowed").that(rest(3_600)).isEqualTo(3_600)
        assertThat(rest(3_601)).isEqualTo(maximumRest)
        assertThat(rest(Int.MAX_VALUE)).isEqualTo(maximumRest)
        assertThat(rest(-5)).isEqualTo(0)
        assertThat(rest(Int.MIN_VALUE)).isEqualTo(0)

        // The reported scenario: the huge rest reaches a template, whose estimate is shown on the hub.
        val s = WorkoutReducer.reduce(design, WorkoutAction.SetRest(exerciseID, Int.MAX_VALUE), Fix.t0)
        val template = WorkoutFactory.template(s, "Mine")
        assertThat(template.entries[0].restSeconds).isEqualTo(maximumRest)
        assertThat(template.estimatedMinutes).isAtLeast(5)

        // A template that did not come through the reducer (a corrupt file) must not trap either.
        val corrupt = template.copy(
            entries = template.entries.mapIndexed { index, entry ->
                when (index) {
                    0 -> entry.copy(restSeconds = Int.MAX_VALUE)
                    1 -> entry.copy(restSeconds = Int.MIN_VALUE)
                    else -> entry
                }
            },
        )
        assertThat(corrupt.estimatedMinutes).isAtLeast(5)
        assertWithMessage("an hour of rest still counts").that(corrupt.estimatedMinutes)
            .isGreaterThan(SampleData.templates()[0].estimatedMinutes)

        // The estimate of every normal template is unchanged (the original integer arithmetic, rests of 0...3600 s).
        fun reference(template: WorkoutTemplate): Int {
            var seconds = 0
            for (entry in template.entries) {
                for (set in entry.plannedSets) {
                    seconds += 45 + (if (set.type == SetType.WARMUP) maxOf(30, entry.restSeconds * 2 / 5) else entry.restSeconds)
                }
            }
            return maxOf(5, (seconds.toDouble() / 60.0 / 5.0).roundedAwayFromZero().toInt() * 5)
        }
        for (sample in SampleData.templates()) {
            assertWithMessage(sample.name).that(sample.estimatedMinutes).isEqualTo(reference(sample))
        }
    }

    // endregion

    // region SVC-1: finish deletes the only copy of the workout when the history cannot be saved

    /**
     * `StrengthDataModel.persist` swallowed write errors and `WorkoutEngine.finish` then deleted `active-workout.json`
     * unconditionally, so a failed `history.json` write lost the whole workout at the next launch.
     */
    @Test
    fun testSVC1_FinishKeepsTheActiveWorkoutFileWhenTheHistoryCouldNotBeSaved() {
        val epoch = Instant.ofEpochSecond(1_791_919_800L)
        val persistence = temporaryPersistence()
        val directory = persistence.directory
        // history.json can no longer be replaced (stands in for a full disk / I/O error: the atomic write throws).
        val blocker = File(directory, "history.json")
        assertThat(blocker.mkdirs()).isTrue()
        File(blocker, "keep").writeText("x")

        var now = epoch
        val workoutID: UUID
        run {
            val model = StrengthDataModel(persistence, seedDemoData = true, now = epoch)
            val engine = WorkoutEngine(persistence = persistence, data = model, clock = { now })
            engine.start(model.data.templates[0])
            // Logs the next two pending sets, one minute apart.
            repeat(2) {
                now = now.plusSeconds(60)
                engine.send(WorkoutAction.LogNextSet)
            }
            val loggedBefore = engine.state?.exercises?.sumOf { it.doneCount }
            assertThat(loggedBefore).isEqualTo(2)
            val id = engine.state!!.id

            val completed = engine.finish(updateTemplate = false)
            assertWithMessage("the user still gets the finished workout (summary screen)").that(completed?.loggedSets).isEqualTo(2)
            assertThat(engine.state).isNull()
            assertWithMessage("the workout is in memory").that(model.data.history.firstOrNull()?.id).isEqualTo(id)
            assertWithMessage("the failed save is reported, not swallowed").that(engine.lastPersistenceError).isNotNull()

            // What a relaunch would find on disk.
            assertWithMessage("precondition: nothing could be written to history.json").that(persistence.loadHistory()).isEmpty()
            assertWithMessage("the two logged sets exist nowhere on disk any more").that(persistence.loadActiveWorkout()).isNotNull()
            workoutID = id
        }

        // The relaunch: the unsaved workout comes back with every logged set, and finishing it again saves it once the disk works.
        assertThat(blocker.deleteRecursively()).isTrue()
        run {
            val model = StrengthDataModel(persistence, seedDemoData = false, now = epoch)
            val engine = WorkoutEngine(persistence = persistence, data = model, clock = { epoch })
            engine.restore()
            assertThat(engine.state?.id).isEqualTo(workoutID)
            assertThat(engine.state?.exercises?.sumOf { it.doneCount }).isEqualTo(2)
            assertThat(engine.finish(updateTemplate = false)).isNotNull()
            assertThat(engine.lastPersistenceError).isNull()
            assertWithMessage("saved exactly once").that(persistence.loadHistory().map { it.id }).isEqualTo(listOf(workoutID))
            assertWithMessage("now that the history is safe the active file is removed").that(persistence.loadActiveWorkout()).isNull()
        }
    }

    // endregion
}
