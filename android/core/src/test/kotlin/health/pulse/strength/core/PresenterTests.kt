package health.pulse.strength.core

import com.google.common.truth.Truth.assertThat
import com.google.common.truth.Truth.assertWithMessage
import java.time.Instant
import java.util.UUID
import org.junit.Test

// Port of PresenterTests.swift (Swift: 96 tests in 8 classes).

// region Fixtures shared by the presenter, summary and snapshot tests

/** Deterministic fixtures (no clock, no randomness) for the presenter, summary and snapshot tests. */
internal object PresFix {
    /** The fake "start of the workout". */
    val t0: Instant = Instant.ofEpochSecond(1_800_000_000L)

    /** `t0` plus `seconds`. */
    fun at(seconds: Double): Instant = t0.addingTimeInterval(seconds)

    fun at(seconds: Int): Instant = at(seconds.toDouble())

    /** A stable UUID built from two numbers. */
    fun uuid(high: Int, low: Int): UUID {
        fun hex(value: Int, width: Int): String {
            val digits = value.toString(16)
            return "0".repeat(maxOf(0, width - digits.length)) + digits
        }
        return UUID.fromString("00000000-0000-0000-${hex(high, 4)}-${hex(low, 12)}")
    }

    /** A built-in exercise of the library. */
    fun lib(id: String): Exercise = ExerciseLibrary.exercise(id) ?: error("unknown exercise $id")

    /** `exercise` with another previous best estimated 1RM. */
    fun lib(id: String, best: Double): Exercise = lib(id).copy(previousBestE1RM = best)

    /** Demo recovery percentages (88 % chest). */
    val demoRecovery: RecoveryProvider = DemoRecovery.provider

    /** Fails the test when [value] is null (Swift `XCTUnwrap`). */
    fun <T : Any> unwrap(value: T?): T {
        assertThat(value).isNotNull()
        return value!!
    }

    // region Workouts

    /** A set as (type, weight, reps) (Swift `SetSpec`). */
    fun normal(count: Int, kg: Double, reps: Int): List<Triple<SetType, Double, Int>> = List(count) { Triple(SetType.NORMAL, kg, reps) }

    /** Entry number `n` (1-based) with deterministic ids: entry `uuid(0x100 + n, 0)`, sets `uuid(0x100 + n, i + 1)`. */
    fun entry(
        n: Int,
        exercise: Exercise,
        sets: List<Triple<SetType, Double, Int>>,
        rest: Int? = null,
        group: String? = null,
        templateEntry: UUID? = null,
    ): WorkoutExercise = WorkoutExercise(
        id = uuid(0x100 + n, 0),
        exercise = exercise,
        sets = sets.mapIndexed { offset, spec -> LoggedSet(id = uuid(0x100 + n, offset + 1), type = spec.first, weightKg = spec.second, reps = spec.third) },
        restSeconds = rest ?: exercise.defaults.restSeconds,
        supersetGroup = group,
        note = "",
        templateEntryID = templateEntry,
    )

    /** A workout of `entries` starting at `t0`. */
    fun workout(entries: List<WorkoutExercise>, index: Int = 0, name: String = "Test"): WorkoutState =
        WorkoutState(id = uuid(1, 2), name = name, exercises = entries, currentIndex = index, startedAt = t0)

    /** A single-exercise workout with the given sets. */
    fun single(exercise: Exercise, sets: List<Triple<SetType, Double, Int>>, rest: Int? = null): WorkoutState =
        workout(listOf(entry(1, exercise, sets, rest = rest)))

    /** Marks the sets at `indexes` of exercise `k` as logged without touching the rest of the state. */
    fun marking(state: WorkoutState, exercise: Int, done: List<Int>): WorkoutState {
        var copy = state
        for (i in done) copy = editSet(copy, exercise, i) { it.copy(isDone = true) }
        return copy
    }

    /** `state` with exercise `k` replaced by `transform(exercise k)`. */
    fun editExercise(state: WorkoutState, k: Int, transform: (WorkoutExercise) -> WorkoutExercise): WorkoutState =
        state.copy(exercises = state.exercises.toMutableList().also { it[k] = transform(it[k]) })

    /** `state` with set `i` of exercise `k` replaced by `transform(set)`. */
    fun editSet(state: WorkoutState, k: Int, i: Int, transform: (LoggedSet) -> LoggedSet): WorkoutState =
        editExercise(state, k) { entry -> entry.copy(sets = entry.sets.toMutableList().also { it[i] = transform(it[i]) }) }

    // endregion

    // region Upper A - Push (the design's workout)

    fun templateEntry(n: Int, exercise: Exercise, planned: List<PlannedSet>, rest: Int, group: String? = null): TemplateEntry =
        TemplateEntry(id = uuid(0x200 + n, 0), exercise = exercise, plannedSets = planned, restSeconds = rest, supersetGroup = group)

    fun planned(count: Int, kg: Double, reps: Int): List<PlannedSet> = List(count) { PlannedSet(type = SetType.NORMAL, weightKg = kg, reps = reps) }

    /** "Upper A · Push": bench with two warm-ups, incline, overhead press, lateral raise + pushdown (superset A), crossover. */
    fun upperA(): WorkoutTemplate = WorkoutTemplate(
        id = uuid(0x2FF, 1),
        name = "Upper A · Push",
        entries = listOf(
            templateEntry(
                1, lib("bench"),
                listOf(
                    PlannedSet(type = SetType.WARMUP, weightKg = 50.0, reps = 8), PlannedSet(type = SetType.WARMUP, weightKg = 70.0, reps = 5),
                    PlannedSet(weightKg = 82.5, reps = 6), PlannedSet(weightKg = 82.5, reps = 6), PlannedSet(weightKg = 85.0, reps = 6),
                ),
                rest = 150,
            ),
            templateEntry(2, lib("incline"), planned(3, 28.0, 10), rest = 90),
            templateEntry(3, lib("ohp"), planned(3, 45.0, 8), rest = 120),
            templateEntry(4, lib("lateral"), planned(3, 8.0, 15), rest = 60, group = "A"),
            templateEntry(5, lib("pushdown"), planned(3, 30.0, 12), rest = 60, group = "A"),
            templateEntry(6, lib("crossover"), planned(3, 15.0, 12), rest = 60),
        ),
    )

    /** The design's workout just started at `t0`, nothing logged. */
    fun freshUpperA(): WorkoutState = WorkoutFactory.makeWorkout(upperA(), t0, uuid(1, 1))

    /**
     * The design's opening state: warm-ups 50x8 and 70x5 and the first 82.5x6 logged (RIR 3), rest running.
     * The last set was logged at `t0 + 1403` (150 s rest, ends at `t0 + 1553`); the design clock reads 24:18 at `t0 + 1458`.
     */
    fun goldenState(): WorkoutState {
        var state = freshUpperA()
        state = WorkoutReducer.reduce(state, WorkoutAction.LogNextSet, at(1200))
        state = WorkoutReducer.reduce(state, WorkoutAction.LogNextSet, at(1300))
        state = WorkoutReducer.reduce(state, WorkoutAction.LogNextSet, at(1403))
        state = WorkoutReducer.reduce(state, WorkoutAction.ToggleLastSetRIR(3), at(1404))
        return state
    }

    /** The `now` at which the golden state shows the design's 24:18 clock and 1:35 of rest left. */
    val goldenNow: Instant get() = at(1458)

    // endregion

    // region Reducer shortcuts

    fun reduced(state: WorkoutState, action: WorkoutAction, seconds: Double = 0.0): WorkoutState =
        WorkoutReducer.reduce(state, action, at(seconds))

    fun reduced(state: WorkoutState, action: WorkoutAction, seconds: Int): WorkoutState = reduced(state, action, seconds.toDouble())

    fun log(state: WorkoutState, k: Int, i: Int): WorkoutAction = WorkoutAction.LogSet(state.exercises[k].id, state.exercises[k].sets[i].id)

    /** Logs every pending set of the workout, one second apart, starting at `t0 + start`. */
    fun loggedEverything(state: WorkoutState, start: Double = 0.0): WorkoutState {
        var copy = state
        var seconds = start
        while (WorkoutTargets.nextPending(copy) != null) {
            copy = WorkoutReducer.reduce(copy, WorkoutAction.LogNextSet, at(seconds))
            seconds += 1
        }
        return copy
    }

    fun present(state: WorkoutState, seconds: Double = 0.0): ActiveWorkoutPresentation =
        WorkoutPresenter.present(state, at(seconds), demoRecovery)

    fun present(state: WorkoutState, seconds: Int): ActiveWorkoutPresentation = present(state, seconds.toDouble())

    // endregion
}

// endregion

// region Presenter: the design's opening state

class PresenterGoldenTests {
    private var state = PresFix.goldenState()
    private val view: ActiveWorkoutPresentation get() = WorkoutPresenter.present(state, PresFix.goldenNow, PresFix.demoRecovery)

    @Test
    fun testFixtureMatchesTheDesignState() {
        assertThat(state.exercises.size).isEqualTo(6)
        assertThat(state.exercises[0].sets.map { it.isDone }).isEqualTo(listOf(true, true, true, false, false))
        assertThat(state.exercises[0].sets[2].rir).isEqualTo(3)
        assertThat(state.rest?.totalSeconds).isEqualTo(150)
        assertThat(state.rest?.endsAt).isEqualTo(PresFix.at(1553))
        assertThat(state.exercises[0].exercise.previousBestE1RM).isEqualTo(99.0)
    }

    @Test
    fun testHeaderTotals() {
        val header = view.header
        assertThat(header.title).isEqualTo("Upper A · Push")
        assertThat(header.clockText).isEqualTo("24:18")
        assertThat(header.isPaused).isFalse()
        assertThat(header.volumeText).isEqualTo("495")
        assertThat(header.setsText).isEqualTo("3 of 20")
        assertThat(header.heartRateText).isEqualTo("–")
        assertThat(header.hasHeartRate).isFalse()
        assertThat(view.totals.loggedSets).isEqualTo(3)
        assertThat(view.totals.totalSets).isEqualTo(20)
        assertThat(view.totals.volumeKg).isWithin(0.0001).of(495.0)
        assertThat(view.totals.completedExercises).isEqualTo(0)
        assertThat(view.isEmpty).isFalse()
    }

    @Test
    fun testSegmentsFollowTheLoggedShareOfEachExercise() {
        val segments = view.header.segments
        assertThat(segments.size).isEqualTo(6)
        assertThat(segments[0].fraction).isWithin(0.0001).of(0.6)
        assertThat(segments.drop(1).all { it.fraction == 0.0 }).isTrue()
        assertThat(segments.map { it.isCurrent }).isEqualTo(listOf(true, false, false, false, false, false))
    }

    @Test
    fun testNavigator() {
        val nav = PresFix.unwrap(view.navigator)
        assertThat(nav.position).isEqualTo(1)
        assertThat(nav.total).isEqualTo(6)
        assertThat(nav.canGoPrevious).isFalse()
        assertThat(nav.canGoNext).isTrue()
    }

    @Test
    fun testCardOfTheCurrentExercise() {
        val card = PresFix.unwrap(view.card)
        assertThat(card.exerciseID).isEqualTo(state.exercises[0].id)
        assertThat(card.exercise.id).isEqualTo("bench")
        assertThat(card.recoveryPercent).isEqualTo(88)
        assertThat(card.recoveryLevel).isEqualTo(ActiveWorkoutPresentation.RecoveryLevel.GOOD)
        assertThat(card.supersetLabel).isNull()
        assertThat(card.restSeconds).isEqualTo(150)
        assertThat(card.restText).isEqualTo("2:30")
        assertThat(card.weightColumnTitle).isEqualTo("kg")
        assertThat(card.repsColumnTitle).isEqualTo("Reps")
        assertThat(card.note).isEqualTo("")
        assertThat(card.rows.size).isEqualTo(5)
    }

    @Test
    fun testRows() {
        val rows = PresFix.unwrap(view.card).rows
        assertThat(rows.map { it.id }).isEqualTo(state.exercises[0].sets.map { it.id })
        assertThat(rows.map { it.number }).isEqualTo(listOf("W", "W", "1", "2", "3"))
        assertThat(rows.map { it.previousText }).isEqualTo(listOf("50 × 8", "70 × 5", "80 × 6", "80 × 6", "80 × 5"))
        assertThat(rows.map { it.weightText }).isEqualTo(listOf("50", "70", "82.5", "82.5", "85"))
        assertThat(rows.map { it.repsText }).isEqualTo(listOf("8", "5", "6", "6", "6"))
        assertThat(rows.map { it.isDone }).isEqualTo(listOf(true, true, true, false, false))
        assertThat(rows.map { it.isNext }).isEqualTo(listOf(false, false, false, true, false))
        assertThat(rows.all { it.weightEditable }).isTrue()
        assertThat(rows.map { it.type }).isEqualTo(listOf(SetType.WARMUP, SetType.WARMUP, SetType.NORMAL, SetType.NORMAL, SetType.NORMAL))
        assertThat(rows.map { it.rirText }).isEqualTo(listOf<String?>(null, null, "RIR 3", null, null))
        assertThat(rows.map { it.rir }).isEqualTo(listOf<Int?>(null, null, 3, null, null))
        // 82.5 x 6 is exactly the previous best (99.0): not a record.
        assertThat(rows.map { it.isPersonalRecord }).isEqualTo(listOf(false, false, false, false, false))
        assertThat(rows.map { it.estimated1RM }).isEqualTo(listOf<Int?>(null, null, null, null, null))
    }

    @Test
    fun testAccessibilityLabels() {
        val rows = PresFix.unwrap(view.card).rows
        assertThat(rows[0].accessibilityLabel).isEqualTo("Set 1, warm-up, 50 kilograms, 8 reps, logged")
        assertThat(rows[2].accessibilityLabel).isEqualTo("Set 3, working set, 82.5 kilograms, 6 reps, logged")
        assertThat(rows[3].accessibilityLabel).isEqualTo("Set 4, working set, 82.5 kilograms, 6 reps, not logged")
    }

    @Test
    fun testRestDockWhileTheRestRuns() {
        val dock = PresFix.unwrap(view.dock)
        assertThat(dock.phase).isEqualTo(ActiveWorkoutPresentation.DockPhase.RUNNING)
        assertThat(dock.remainingSeconds).isEqualTo(95)
        assertThat(dock.totalSeconds).isEqualTo(150)
        assertThat(dock.fraction).isWithin(0.0001).of(95.0 / 150.0)
        assertThat(dock.remainingText).isEqualTo("1:35")
        assertThat(dock.nextSetText).isEqualTo("Next · Set 2 · 82.5 kg × 6")
        assertThat(dock.showsRIR).isTrue()
        assertThat(dock.rirSelection).isEqualTo(3)
        assertThat(dock.isPaused).isFalse()
    }

    @Test
    fun testNoCoachTipWhileTheRestRuns() {
        assertThat(PresFix.unwrap(view.card).coachTip).isNull()
    }

    @Test
    fun testCoachTipAppearsOnceTheRestIsCleared() {
        state = PresFix.reduced(state, WorkoutAction.SkipRest, 1459)
        assertThat(view.dock).isNull()
        val tip = PresFix.unwrap(view.card).coachTip
        assertThat(tip).isEqualTo("85 kg × 6 on your last set would beat your best estimated 1RM of 99 kg.")
    }

    @Test
    fun testFinishCheckOfTheOpeningState() {
        val check = view.finishCheck
        assertThat(check.loggedSets).isEqualTo(3)
        assertThat(check.unloggedSets).isEqualTo(17)
        assertThat(check.canFinish).isTrue()
        assertThat(check.title).isEqualTo("Finish workout?")
        assertThat(check.message).isEqualTo("17 sets are not logged yet and will be left out.")
        assertThat(check.templateDiff.isEmpty).isTrue()
        assertThat(check.diffMessage).isEqualTo("Changes: none.")
        assertThat(check.asksToUpdateTemplate).isFalse()
    }

    @Test
    fun testNoUndoTextInitially() {
        assertThat(view.undoText).isNull()
    }
}

// endregion

// region Presenter: header, empty workout, paused clock

class PresenterHeaderTests {
    @Test
    fun testEmptyWorkout() {
        val state = WorkoutFactory.makeEmpty("Workout", PresFix.t0)
        val view = PresFix.present(state, 65)
        assertThat(view.isEmpty).isTrue()
        assertThat(view.navigator).isNull()
        assertThat(view.card).isNull()
        assertThat(view.dock).isNull()
        assertThat(view.undoText).isNull()
        assertThat(view.header.title).isEqualTo("Workout")
        assertThat(view.header.clockText).isEqualTo("1:05")
        assertThat(view.header.setsText).isEqualTo("0 of 0")
        assertThat(view.header.volumeText).isEqualTo("0")
        assertThat(view.header.segments).isEmpty()
        assertThat(view.totals).isEqualTo(ActiveWorkoutPresentation.Totals(loggedSets = 0, totalSets = 0, volumeKg = 0.0, completedExercises = 0))
        assertThat(view.finishCheck.title).isEqualTo("Nothing logged yet")
        assertThat(view.finishCheck.message).isEqualTo("Log at least one set to save this workout.")
        assertThat(view.finishCheck.canFinish).isFalse()
        assertThat(view.finishCheck.unloggedSets).isEqualTo(0)
    }

    @Test
    fun testEmptyWorkoutHasNoDockEvenWithAStrayRest() {
        val state = WorkoutFactory.makeEmpty("Workout", PresFix.t0).copy(rest = RestState(endsAt = PresFix.at(100), totalSeconds = 60))
        assertThat(PresFix.present(state, 10).dock).isNull()
    }

    @Test
    fun testClockFormats() {
        val state = PresFix.freshUpperA()
        assertThat(PresFix.present(state, 0).header.clockText).isEqualTo("0:00")
        assertThat(PresFix.present(state, 59.9).header.clockText).isEqualTo("0:59")
        assertThat(PresFix.present(state, 1458).header.clockText).isEqualTo("24:18")
        assertThat(PresFix.present(state, 3723).header.clockText).isEqualTo("1:02:03")
        assertThat(PresFix.present(state, -30).header.clockText).isEqualTo("0:00")
    }

    @Test
    fun testPausedClockText() {
        var state = PresFix.freshUpperA()
        state = WorkoutReducer.reduce(state, WorkoutAction.Pause, PresFix.at(600))
        val view = PresFix.present(state, 900)
        assertThat(view.header.clockText).isEqualTo("Paused · 10:00")
        assertThat(view.header.isPaused).isTrue()
        // The clock stays frozen while time passes.
        assertThat(PresFix.present(state, 5000).header.clockText).isEqualTo("Paused · 10:00")
    }

    @Test
    fun testClockExcludesPausedTimeAfterResume() {
        var state = PresFix.freshUpperA()
        state = WorkoutReducer.reduce(state, WorkoutAction.Pause, PresFix.at(600))
        state = WorkoutReducer.reduce(state, WorkoutAction.Resume, PresFix.at(1000))
        val view = PresFix.present(state, 1100)
        assertThat(view.header.clockText).isEqualTo("11:40")
        assertThat(view.header.isPaused).isFalse()
    }

    @Test
    fun testHeartRateText() {
        var state = PresFix.freshUpperA()
        assertThat(PresFix.present(state).header.heartRateText).isEqualTo("–")
        state = WorkoutReducer.reduce(state, WorkoutAction.UpdateHeartRate(128), PresFix.at(1))
        val view = PresFix.present(state, 2)
        assertThat(view.header.heartRateText).isEqualTo("128")
        assertThat(view.header.hasHeartRate).isTrue()
        state = WorkoutReducer.reduce(state, WorkoutAction.UpdateHeartRate(null), PresFix.at(3))
        assertThat(PresFix.present(state).header.heartRateText).isEqualTo("–")
        assertThat(PresFix.present(state).header.hasHeartRate).isFalse()
        state = WorkoutReducer.reduce(state, WorkoutAction.UpdateHeartRate(0), PresFix.at(4))
        assertThat(PresFix.present(state).header.heartRateText).isEqualTo("–")
    }

    @Test
    fun testVolumeUsesThousandsSeparators() {
        val state = PresFix.marking(PresFix.single(PresFix.lib("squat"), PresFix.normal(3, 100.0, 6)), 0, listOf(0, 1, 2))
        assertThat(PresFix.present(state).header.volumeText).isEqualTo("1,800")
        val heavy = PresFix.marking(PresFix.single(PresFix.lib("squat"), PresFix.normal(2, 1250.0, 10)), 0, listOf(0, 1))
        assertThat(PresFix.present(heavy).header.volumeText).isEqualTo("25,000")
    }

    @Test
    fun testVolumeExcludesWarmUpsUnloggedAndNonWeightExercises() {
        val bench = PresFix.entry(
            1, PresFix.lib("bench"),
            listOf(
                Triple(SetType.WARMUP, 50.0, 8), Triple(SetType.NORMAL, 80.0, 5), Triple(SetType.DROP, 60.0, 10),
                Triple(SetType.FAILURE, 70.0, 4), Triple(SetType.NORMAL, 80.0, 5),
            ),
        )
        val pushup = PresFix.entry(2, PresFix.lib("pushup"), PresFix.normal(2, 10.0, 12))
        val plank = PresFix.entry(3, PresFix.lib("plank"), PresFix.normal(1, 0.0, 45))
        var state = PresFix.workout(listOf(bench, pushup, plank))
        state = PresFix.marking(state, 0, listOf(0, 1, 2, 3))
        state = PresFix.marking(state, 1, listOf(0, 1))
        state = PresFix.marking(state, 2, listOf(0))
        // 80x5 + 60x10 + 70x4 = 400 + 600 + 280; the warm-up, the pending set and the bodyweight work do not count.
        assertThat(PresFix.present(state).totals.volumeKg).isWithin(0.0001).of(1280.0)
        assertThat(PresFix.present(state).header.volumeText).isEqualTo("1,280")
        assertThat(PresFix.present(state).totals.loggedSets).isEqualTo(7)
    }

    @Test
    fun testCompletedExercisesNeedASetAndAllDone() {
        val a = PresFix.entry(1, PresFix.lib("bench"), PresFix.normal(2, 80.0, 5))
        val b = PresFix.entry(2, PresFix.lib("incline"), PresFix.normal(2, 28.0, 10))
        val empty = PresFix.entry(3, PresFix.lib("ohp"), emptyList()).copy(sets = emptyList())
        var state = PresFix.workout(listOf(a, b, empty))
        state = PresFix.marking(state, 0, listOf(0, 1))
        state = PresFix.marking(state, 1, listOf(0))
        val view = PresFix.present(state)
        assertThat(view.totals.completedExercises).isEqualTo(1)
        assertThat(view.header.segments.map { it.fraction }).isEqualTo(listOf(1.0, 0.5, 0.0))
    }

    @Test
    fun testNavigatorAtTheEnds() {
        var state = PresFix.freshUpperA()
        state = PresFix.reduced(state, WorkoutAction.GoTo(5))
        val last = PresFix.unwrap(PresFix.present(state).navigator)
        assertThat(last.position).isEqualTo(6)
        assertThat(last.canGoPrevious).isTrue()
        assertThat(last.canGoNext).isFalse()
        state = PresFix.reduced(state, WorkoutAction.GoTo(2))
        val middle = PresFix.unwrap(PresFix.present(state).navigator)
        assertThat(middle.position).isEqualTo(3)
        assertThat(middle.canGoPrevious).isTrue()
        assertThat(middle.canGoNext).isTrue()
        assertThat(PresFix.present(state).header.segments.map { it.isCurrent }).isEqualTo(listOf(false, false, true, false, false, false))
    }

    @Test
    fun testOutOfRangeCurrentIndexIsClamped() {
        var state = PresFix.freshUpperA().copy(currentIndex = 99)
        val view = PresFix.present(state)
        assertThat(PresFix.unwrap(view.navigator).position).isEqualTo(6)
        assertThat(PresFix.unwrap(view.card).exercise.id).isEqualTo("crossover")
        state = state.copy(currentIndex = -4)
        assertThat(PresFix.unwrap(PresFix.present(state).navigator).position).isEqualTo(1)
    }

    @Test
    fun testUndoTextWindow() {
        var state = PresFix.freshUpperA()
        state = WorkoutReducer.reduce(state, WorkoutAction.RemoveExercise(state.exercises[5].id), PresFix.at(10))
        assertThat(PresFix.present(state, 11).undoText).isEqualTo("Removed Cable crossover")
        assertThat(PresFix.present(state, 16).undoText).isEqualTo("Removed Cable crossover")
        assertThat(PresFix.present(state, 16.001).undoText).isNull()
        assertThat(PresFix.present(state, 60).undoText).isNull()
    }

    @Test
    fun testUndoTextForADeletedSet() {
        var state = PresFix.freshUpperA()
        state = WorkoutReducer.reduce(state, WorkoutAction.DeleteSet(state.exercises[1].id, state.exercises[1].sets[0].id), PresFix.at(20))
        assertThat(PresFix.present(state, 21).undoText).isEqualTo("Set deleted")
        assertThat(PresFix.present(state, 21).totals.totalSets).isEqualTo(19)
    }
}

// endregion

// region Presenter: card, recovery, tracking kinds

class PresenterCardTests {
    private fun levelAndPercent(percent: Int): Pair<Int, ActiveWorkoutPresentation.RecoveryLevel> {
        val provider: RecoveryProvider = { _ -> percent }
        val view = WorkoutPresenter.present(PresFix.freshUpperA(), PresFix.t0, provider)
        val card = PresFix.unwrap(view.card)
        return card.recoveryPercent to card.recoveryLevel
    }

    @Test
    fun testRecoveryLevelsAtTheThresholds() {
        assertThat(levelAndPercent(100)).isEqualTo(100 to ActiveWorkoutPresentation.RecoveryLevel.GOOD)
        assertThat(levelAndPercent(80)).isEqualTo(80 to ActiveWorkoutPresentation.RecoveryLevel.GOOD)
        assertThat(levelAndPercent(79)).isEqualTo(79 to ActiveWorkoutPresentation.RecoveryLevel.FAIR)
        assertThat(levelAndPercent(60)).isEqualTo(60 to ActiveWorkoutPresentation.RecoveryLevel.FAIR)
        assertThat(levelAndPercent(59)).isEqualTo(59 to ActiveWorkoutPresentation.RecoveryLevel.LOW)
        assertThat(levelAndPercent(0)).isEqualTo(0 to ActiveWorkoutPresentation.RecoveryLevel.LOW)
    }

    @Test
    fun testRecoveryPercentIsClamped() {
        assertThat(levelAndPercent(250)).isEqualTo(100 to ActiveWorkoutPresentation.RecoveryLevel.GOOD)
        assertThat(levelAndPercent(-5)).isEqualTo(0 to ActiveWorkoutPresentation.RecoveryLevel.LOW)
    }

    @Test
    fun testRecoveryIsLookedUpByTheMuscleOfTheCurrentExercise() {
        var state = PresFix.freshUpperA()
        val provider: RecoveryProvider = { muscle ->
            when (muscle) {
                MuscleGroup.CHEST -> 90
                MuscleGroup.SHOULDERS -> 70
                MuscleGroup.ARMS -> 40
                else -> 100
            }
        }
        assertThat(PresFix.unwrap(WorkoutPresenter.present(state, PresFix.t0, provider).card).recoveryPercent).isEqualTo(90)
        state = PresFix.reduced(state, WorkoutAction.GoTo(2))
        assertThat(PresFix.unwrap(WorkoutPresenter.present(state, PresFix.t0, provider).card).recoveryPercent).isEqualTo(70)
        state = PresFix.reduced(state, WorkoutAction.GoTo(4))
        val card = PresFix.unwrap(WorkoutPresenter.present(state, PresFix.t0, provider).card)
        assertThat(card.recoveryPercent).isEqualTo(40)
        assertThat(card.recoveryLevel).isEqualTo(ActiveWorkoutPresentation.RecoveryLevel.LOW)
    }

    @Test
    fun testDemoRecoveryProviderValues() {
        var state = PresFix.freshUpperA()
        state = PresFix.reduced(state, WorkoutAction.GoTo(3))
        val card = PresFix.unwrap(PresFix.present(state).card)
        assertThat(card.exercise.muscle).isEqualTo(MuscleGroup.SHOULDERS)
        assertThat(card.recoveryPercent).isEqualTo(82)
        assertThat(card.recoveryLevel).isEqualTo(ActiveWorkoutPresentation.RecoveryLevel.GOOD)
    }

    @Test
    fun testSupersetLabelAndRestText() {
        var state = PresFix.freshUpperA()
        state = PresFix.reduced(state, WorkoutAction.GoTo(3))
        var card = PresFix.unwrap(PresFix.present(state).card)
        assertThat(card.supersetLabel).isEqualTo("Superset A")
        assertThat(card.restText).isEqualTo("1:00")
        state = PresFix.reduced(state, WorkoutAction.SetRest(state.exercises[3].id, 0))
        card = PresFix.unwrap(PresFix.present(state).card)
        assertThat(card.restText).isEqualTo("Off")
        assertThat(card.restSeconds).isEqualTo(0)
        state = PresFix.reduced(state, WorkoutAction.GoTo(5))
        assertThat(PresFix.unwrap(PresFix.present(state).card).supersetLabel).isNull()
    }

    @Test
    fun testNoteIsPassedThrough() {
        var state = PresFix.freshUpperA()
        state = PresFix.reduced(state, WorkoutAction.SetNote(state.exercises[0].id, "Pause on the chest"))
        assertThat(PresFix.unwrap(PresFix.present(state).card).note).isEqualTo("Pause on the chest")
    }

    @Test
    fun testRepsOnlyExercise() {
        val state = PresFix.single(PresFix.lib("pushup"), listOf(Triple(SetType.NORMAL, 0.0, 12), Triple(SetType.NORMAL, 0.0, 10)))
        val card = PresFix.unwrap(PresFix.present(state).card)
        assertThat(card.weightColumnTitle).isEqualTo("Added")
        assertThat(card.repsColumnTitle).isEqualTo("Reps")
        assertThat(card.rows.map { it.weightText }).isEqualTo(listOf("BW", "BW"))
        assertThat(card.rows.map { it.weightEditable }).isEqualTo(listOf(false, false))
        assertThat(card.rows.map { it.repsText }).isEqualTo(listOf("12", "10"))
        // The library's last session was 15 reps; the last entry is reused for further sets.
        assertThat(card.rows.map { it.previousText }).isEqualTo(listOf("15 reps", "15 reps"))
        assertThat(card.rows[0].accessibilityLabel).isEqualTo("Set 1, working set, bodyweight, 12 reps, not logged")
    }

    @Test
    fun testDurationExercise() {
        val state = PresFix.single(PresFix.lib("plank"), listOf(Triple(SetType.NORMAL, 0.0, 45), Triple(SetType.NORMAL, 0.0, 40)))
        val card = PresFix.unwrap(PresFix.present(state).card)
        assertThat(card.weightColumnTitle).isEqualTo("")
        assertThat(card.repsColumnTitle).isEqualTo("Sec")
        assertThat(card.rows.map { it.weightText }).isEqualTo(listOf("–", "–"))
        assertThat(card.rows.map { it.weightEditable }).isEqualTo(listOf(false, false))
        assertThat(card.rows.map { it.repsText }).isEqualTo(listOf("45", "40"))
        assertThat(card.rows.map { it.previousText }).isEqualTo(listOf("45 s", "45 s"))
        assertThat(card.rows[1].accessibilityLabel).isEqualTo("Set 2, working set, 40 seconds, not logged")
    }

    @Test
    fun testPreviousTextWithoutHistoryAndWithShorterHistory() {
        val noHistory = PresFix.single(PresFix.lib("dips"), PresFix.normal(2, 0.0, 8))
        assertThat(PresFix.unwrap(PresFix.present(noHistory).card).rows.map { it.previousText }).isEqualTo(listOf("–", "–"))

        // Incline has three previous sets; the fourth row reuses the last one.
        val incline = PresFix.single(PresFix.lib("incline"), PresFix.normal(4, 28.0, 10))
        assertThat(PresFix.unwrap(PresFix.present(incline).card).rows.map { it.previousText })
            .isEqualTo(listOf("26 × 10", "26 × 10", "26 × 9", "26 × 9"))
    }

    @Test
    fun testPreviousTextFormatsDecimalWeights() {
        val exercise = PresFix.lib("bench").copy(previousSets = listOf(PreviousSet(weightKg = 82.5, reps = 5), PreviousSet(weightKg = 80.25, reps = 6)))
        val state = PresFix.single(exercise, PresFix.normal(2, 80.0, 5))
        assertThat(PresFix.unwrap(PresFix.present(state).card).rows.map { it.previousText }).isEqualTo(listOf("82.5 × 5", "80.25 × 6"))
    }

    @Test
    fun testSetTypeNumberingAndLabels() {
        val sets = listOf(
            Triple(SetType.WARMUP, 40.0, 10), Triple(SetType.NORMAL, 80.0, 5), Triple(SetType.DROP, 60.0, 8),
            Triple(SetType.NORMAL, 80.0, 5), Triple(SetType.FAILURE, 70.0, 4), Triple(SetType.NORMAL, 80.0, 5),
        )
        val state = PresFix.single(PresFix.lib("bench"), sets)
        val rows = PresFix.unwrap(PresFix.present(state).card).rows
        assertThat(rows.map { it.number }).isEqualTo(listOf("W", "1", "D", "2", "F", "3"))
        assertThat(rows[2].accessibilityLabel).isEqualTo("Set 3, drop set, 60 kilograms, 8 reps, not logged")
        assertThat(rows[4].accessibilityLabel).isEqualTo("Set 5, failure set, 70 kilograms, 4 reps, not logged")
    }

    @Test
    fun testAccessibilityLabelSingulars() {
        val state = PresFix.single(PresFix.lib("bench"), listOf(Triple(SetType.NORMAL, 1.0, 1)))
        assertThat(PresFix.unwrap(PresFix.present(state).card).rows[0].accessibilityLabel)
            .isEqualTo("Set 1, working set, 1 kilogram, 1 rep, not logged")
        val plank = PresFix.single(PresFix.lib("plank"), listOf(Triple(SetType.NORMAL, 0.0, 1)))
        assertThat(PresFix.unwrap(PresFix.present(plank).card).rows[0].accessibilityLabel).isEqualTo("Set 1, working set, 1 second, not logged")
    }

    @Test
    fun testRIRText() {
        var state = PresFix.single(PresFix.lib("bench"), PresFix.normal(4, 80.0, 5))
        state = PresFix.marking(state, 0, listOf(0, 1, 2))
        state = PresFix.editSet(state, 0, 0) { it.copy(rir = 0) }
        state = PresFix.editSet(state, 0, 1) { it.copy(rir = 4) }
        state = PresFix.editSet(state, 0, 2) { it.copy(rir = null) }
        state = PresFix.editSet(state, 0, 3) { it.copy(rir = 2) } // pending sets never show a RIR tag
        val rows = PresFix.unwrap(PresFix.present(state).card).rows
        assertThat(rows.map { it.rirText }).isEqualTo(listOf<String?>("RIR 0", "RIR 4+", null, null))
        assertThat(rows.map { it.rir }).isEqualTo(listOf<Int?>(0, 4, null, 2))
    }

    @Test
    fun testOnlyTheFirstPendingSetIsNext() {
        var state = PresFix.single(PresFix.lib("bench"), PresFix.normal(4, 80.0, 5))
        assertThat(PresFix.unwrap(PresFix.present(state).card).rows.map { it.isNext }).isEqualTo(listOf(true, false, false, false))
        state = PresFix.marking(state, 0, listOf(0, 2))
        assertThat(PresFix.unwrap(PresFix.present(state).card).rows.map { it.isNext }).isEqualTo(listOf(false, true, false, false))
        state = PresFix.marking(state, 0, listOf(1, 3))
        assertThat(PresFix.unwrap(PresFix.present(state).card).rows.map { it.isNext }).isEqualTo(listOf(false, false, false, false))
    }

    @Test
    fun testCardFollowsTheCurrentExercise() {
        var state = PresFix.freshUpperA()
        state = PresFix.reduced(state, WorkoutAction.NextExercise)
        val card = PresFix.unwrap(PresFix.present(state).card)
        assertThat(card.exercise.id).isEqualTo("incline")
        assertThat(card.exerciseID).isEqualTo(state.exercises[1].id)
        assertThat(card.rows.map { it.weightText }).isEqualTo(listOf("28", "28", "28"))
        assertThat(card.restText).isEqualTo("1:30")
    }
}

// endregion

// region Presenter: personal records and the coach tip

class PresenterRecordTests {
    private fun rows(exercise: Exercise, sets: List<Triple<SetType, Double, Int>>, done: List<Int>): List<ActiveWorkoutPresentation.SetRow> {
        val state = PresFix.marking(PresFix.single(exercise, sets), 0, done)
        return PresFix.unwrap(PresFix.present(state).card).rows
    }

    @Test
    fun testBaselineRisesWithinOneWorkout() {
        val result = rows(PresFix.lib("bench", 80.0), listOf(Triple(SetType.NORMAL, 85.0, 5), Triple(SetType.NORMAL, 85.0, 6)), listOf(0, 1))
        assertThat(result.map { it.isPersonalRecord }).isEqualTo(listOf(true, true))
        // 85 x 5 = 99.17 and 85 x 6 = 102.
        assertThat(result.map { it.estimated1RM }).isEqualTo(listOf<Int?>(99, 102))
    }

    @Test
    fun testAnEqualOrLowerSetAfterARecordIsNoRecord() {
        val result = rows(
            PresFix.lib("bench", 80.0),
            listOf(Triple(SetType.NORMAL, 85.0, 6), Triple(SetType.NORMAL, 85.0, 5), Triple(SetType.NORMAL, 85.0, 6)),
            listOf(0, 1, 2),
        )
        assertThat(result.map { it.isPersonalRecord }).isEqualTo(listOf(true, false, false))
        assertThat(result.map { it.estimated1RM }).isEqualTo(listOf<Int?>(102, null, null))
    }

    @Test
    fun testASetMustBeatTheBaselineNotJustEqualIt() {
        // 82.5 x 6 = 99.0 = the previous best: not a record. 49.75 x 30 = 99.5: a record.
        val equal = rows(PresFix.lib("bench"), listOf(Triple(SetType.NORMAL, 82.5, 6)), listOf(0))
        assertThat(equal.map { it.isPersonalRecord }).isEqualTo(listOf(false))
        val above = rows(PresFix.lib("bench"), listOf(Triple(SetType.NORMAL, 49.75, 30)), listOf(0))
        assertThat(above.map { it.isPersonalRecord }).isEqualTo(listOf(true))
        assertThat(above.map { it.estimated1RM }).isEqualTo(listOf<Int?>(100)) // 99.5 rounds half up
    }

    @Test
    fun testARecordMustBeatTheBaselineByMoreThanFiftyGrams() {
        // 49.51 x 30 = 99.02: above the previous best of 99 but within the 0.05 margin.
        val within = rows(PresFix.lib("bench"), listOf(Triple(SetType.NORMAL, 49.51, 30)), listOf(0))
        assertThat(within.map { it.isPersonalRecord }).isEqualTo(listOf(false))
        // 49.53 x 30 = 99.06 clears the margin.
        val beyond = rows(PresFix.lib("bench"), listOf(Triple(SetType.NORMAL, 49.53, 30)), listOf(0))
        assertThat(beyond.map { it.isPersonalRecord }).isEqualTo(listOf(true))
        // The same margin applies to the coach tip: with a best of 98.96, 82.5 x 6 (99.0) is not enough.
        val state = PresFix.single(PresFix.lib("bench", 98.96), listOf(Triple(SetType.NORMAL, 70.0, 6)))
        assertThat(PresFix.unwrap(PresFix.present(state).card).coachTip)
            .isEqualTo("85 kg × 6 on your last set would beat your best estimated 1RM of 99 kg.")
    }

    @Test
    fun testNoRecordWithoutHistory() {
        val exercise = PresFix.lib("bench", 0.0)
        val result = rows(exercise, listOf(Triple(SetType.NORMAL, 100.0, 5), Triple(SetType.NORMAL, 110.0, 5)), listOf(0, 1))
        assertThat(result.map { it.isPersonalRecord }).isEqualTo(listOf(false, false))
        assertThat(result.map { it.estimated1RM }).isEqualTo(listOf<Int?>(null, null))
        val state = PresFix.marking(PresFix.single(exercise, listOf(Triple(SetType.NORMAL, 100.0, 5))), 0, listOf(0))
        assertThat(PresFix.unwrap(PresFix.present(state).card).coachTip).isNull()
    }

    @Test
    fun testPendingSetsAreNeverRecordsAndDoNotRaiseTheBaseline() {
        val result = rows(PresFix.lib("bench", 80.0), listOf(Triple(SetType.NORMAL, 120.0, 5), Triple(SetType.NORMAL, 85.0, 5)), listOf(1))
        assertThat(result.map { it.isPersonalRecord }).isEqualTo(listOf(false, true))
    }

    @Test
    fun testWarmUpsNeverCountAsRecordsOrRaiseTheBaseline() {
        val result = rows(PresFix.lib("bench", 80.0), listOf(Triple(SetType.WARMUP, 100.0, 5), Triple(SetType.NORMAL, 85.0, 5)), listOf(0, 1))
        assertThat(result.map { it.isPersonalRecord }).isEqualTo(listOf(false, true))
        assertThat(result.map { it.estimated1RM }).isEqualTo(listOf<Int?>(null, 99))
    }

    @Test
    fun testDropAndFailureSetsCanBeRecords() {
        val result = rows(PresFix.lib("bench", 80.0), listOf(Triple(SetType.FAILURE, 85.0, 5), Triple(SetType.DROP, 90.0, 5)), listOf(0, 1))
        assertThat(result.map { it.isPersonalRecord }).isEqualTo(listOf(true, true))
    }

    @Test
    fun testBodyweightAndDurationExercisesNeverGetRecords() {
        val pushup = PresFix.lib("pushup").copy(previousBestE1RM = 10.0)
        assertThat(rows(pushup, listOf(Triple(SetType.NORMAL, 20.0, 30)), listOf(0)).map { it.isPersonalRecord }).isEqualTo(listOf(false))
        val plank = PresFix.lib("plank").copy(previousBestE1RM = 10.0)
        assertThat(rows(plank, listOf(Triple(SetType.NORMAL, 20.0, 300)), listOf(0)).map { it.isPersonalRecord }).isEqualTo(listOf(false))
    }

    @Test
    fun testUnloggingARecordRemovesTheFlag() {
        var state = PresFix.marking(PresFix.single(PresFix.lib("bench", 80.0), listOf(Triple(SetType.NORMAL, 85.0, 5))), 0, listOf(0))
        assertThat(PresFix.unwrap(PresFix.present(state).card).rows.map { it.isPersonalRecord }).isEqualTo(listOf(true))
        state = PresFix.reduced(state, PresFix.log(state, 0, 0)) // logSet on a done set is a no-op
        assertThat(PresFix.unwrap(PresFix.present(state).card).rows.map { it.isPersonalRecord }).isEqualTo(listOf(true))
        state = PresFix.reduced(state, WorkoutAction.ToggleSet(state.exercises[0].id, state.exercises[0].sets[0].id))
        assertThat(PresFix.unwrap(PresFix.present(state).card).rows.map { it.isPersonalRecord }).isEqualTo(listOf(false))
    }

    // region Coach tip

    @Test
    fun testCoachTipUsesTheLastPendingNormalSet() {
        // Previous best 99: with 6 reps the lowest 2.5 kg multiple above 99.05 is 85 kg.
        val state = PresFix.single(
            PresFix.lib("bench"),
            listOf(Triple(SetType.NORMAL, 82.5, 6), Triple(SetType.NORMAL, 60.0, 6), Triple(SetType.FAILURE, 50.0, 4)),
        )
        assertThat(PresFix.unwrap(PresFix.present(state).card).coachTip)
            .isEqualTo("85 kg × 6 on your last set would beat your best estimated 1RM of 99 kg.")
    }

    /**
     * Kotlin-only addition (no Swift counterpart). In the Swift test above both pending normal sets have 6 reps, so a presenter that
     * picked the FIRST instead of the LAST pending normal set would give the same tip (mutation check). Here the reps differ:
     * ARCHITECTURE 3.3 says "take the LAST pending normal set", so the tip uses the 8 reps of the last set, not the 5 of the first.
     */
    @Test
    fun testExtraCoachTipUsesTheRepsOfTheLastPendingNormalSetNotTheFirst() {
        val state = PresFix.single(
            PresFix.lib("bench"),
            listOf(Triple(SetType.NORMAL, 70.0, 5), Triple(SetType.NORMAL, 70.0, 8), Triple(SetType.FAILURE, 50.0, 6)),
        )
        assertThat(PresFix.unwrap(PresFix.present(state).card).coachTip)
            .isEqualTo("80 kg × 8 on your last set would beat your best estimated 1RM of 99 kg.")
    }

    @Test
    fun testCoachTipIgnoresTheCurrentWeightOfTheSet() {
        // The set already equals the target weight (or is far above it): the tip is the same.
        for (weight in listOf(85.0, 100.0, 40.0)) {
            val state = PresFix.single(PresFix.lib("bench"), listOf(Triple(SetType.NORMAL, weight, 6)))
            assertThat(PresFix.unwrap(PresFix.present(state).card).coachTip)
                .isEqualTo("85 kg × 6 on your last set would beat your best estimated 1RM of 99 kg.")
        }
    }

    @Test
    fun testCoachTipUsesTheRepsOfTheTargetSet() {
        // 5 reps: 99.05 / (1 + 5/30) = 84.9 -> 85 kg (99.17); 8 reps: 99.05 / 1.2667 = 78.2 -> 80 kg.
        val five = PresFix.single(PresFix.lib("bench"), listOf(Triple(SetType.NORMAL, 70.0, 5)))
        assertThat(PresFix.unwrap(PresFix.present(five).card).coachTip)
            .isEqualTo("85 kg × 5 on your last set would beat your best estimated 1RM of 99 kg.")
        val eight = PresFix.single(PresFix.lib("bench"), listOf(Triple(SetType.NORMAL, 70.0, 8)))
        assertThat(PresFix.unwrap(PresFix.present(eight).card).coachTip)
            .isEqualTo("80 kg × 8 on your last set would beat your best estimated 1RM of 99 kg.")
    }

    @Test
    fun testCoachTipUsesTheWeightStepOfTheEquipment() {
        // Incline dumbbell press: best 38, 10 reps -> 38.05 / 1.3333 = 28.54 -> next multiple of 2 kg is 30.
        val dumbbell = PresFix.single(PresFix.lib("incline"), listOf(Triple(SetType.NORMAL, 24.0, 10)))
        assertThat(PresFix.unwrap(PresFix.present(dumbbell).card).coachTip)
            .isEqualTo("30 kg × 10 on your last set would beat your best estimated 1RM of 38 kg.")
        // A 1 kg step (bodyweight-style equipment with a weight column): 99.05 / 1.2 = 82.54 -> 83.
        val odd = PresFix.lib("bench").copy(equipment = Equipment.OTHER)
        val state = PresFix.single(odd, listOf(Triple(SetType.NORMAL, 70.0, 6)))
        assertThat(PresFix.unwrap(PresFix.present(state).card).coachTip)
            .isEqualTo("83 kg × 6 on your last set would beat your best estimated 1RM of 99 kg.")
    }

    @Test
    fun testCoachTipFallsBackToTheLastPendingNonWarmUpSet() {
        val state = PresFix.single(
            PresFix.lib("bench"),
            listOf(Triple(SetType.WARMUP, 50.0, 8), Triple(SetType.DROP, 60.0, 6), Triple(SetType.FAILURE, 50.0, 6)),
        )
        // The last pending set is a failure set with 6 reps.
        assertThat(PresFix.unwrap(PresFix.present(state).card).coachTip)
            .isEqualTo("85 kg × 6 on your last set would beat your best estimated 1RM of 99 kg.")
    }

    @Test
    fun testCoachTipBaselineRisesWithLoggedSets() {
        // 85 x 6 logged: the best is now 102, so the last set needs 87.5 kg (87.5 x 6 = 105).
        val state = PresFix.marking(
            PresFix.single(PresFix.lib("bench"), listOf(Triple(SetType.NORMAL, 85.0, 6), Triple(SetType.NORMAL, 85.0, 6))), 0, listOf(0),
        )
        assertThat(PresFix.unwrap(PresFix.present(state).card).coachTip)
            .isEqualTo("87.5 kg × 6 on your last set would beat your best estimated 1RM of 102 kg.")
    }

    @Test
    fun testNoCoachTipVariants() {
        // All sets logged / only warm-ups pending.
        val allDone = PresFix.marking(PresFix.single(PresFix.lib("bench"), PresFix.normal(2, 80.0, 5)), 0, listOf(0, 1))
        assertThat(PresFix.unwrap(PresFix.present(allDone).card).coachTip).isNull()
        val onlyWarmUp = PresFix.marking(
            PresFix.single(PresFix.lib("bench"), listOf(Triple(SetType.WARMUP, 50.0, 8), Triple(SetType.NORMAL, 80.0, 5))), 0, listOf(1),
        )
        assertThat(PresFix.unwrap(PresFix.present(onlyWarmUp).card).coachTip).isNull()
        // Not a weight exercise.
        val pushup = PresFix.lib("pushup").copy(previousBestE1RM = 40.0)
        assertThat(PresFix.unwrap(PresFix.present(PresFix.single(pushup, PresFix.normal(2, 0.0, 12))).card).coachTip).isNull()
        // Zero reps cannot beat anything.
        assertThat(PresFix.unwrap(PresFix.present(PresFix.single(PresFix.lib("bench"), listOf(Triple(SetType.NORMAL, 80.0, 0)))).card).coachTip).isNull()
    }

    @Test
    fun testNoCoachTipWhileARestIsRunningEvenWhenFinished() {
        var state = PresFix.single(PresFix.lib("bench"), PresFix.normal(3, 80.0, 5))
        state = state.copy(rest = RestState(endsAt = PresFix.at(100), totalSeconds = 100))
        assertThat(PresFix.unwrap(PresFix.present(state, 50).card).coachTip).isNull()
        assertThat(PresFix.unwrap(PresFix.present(state, 500).card).coachTip).isNull()
        state = state.copy(rest = null)
        assertThat(PresFix.unwrap(PresFix.present(state, 500).card).coachTip).isNotNull()
    }

    // endregion
}

// endregion

// region Presenter: the rest dock

class PresenterDockTests {
    /** Bench-only workout with `sets` normal sets of 80 x 5; the first set was logged at `t0 + 100` (150 s rest). */
    private fun benchAfterFirstSet(sets: Int = 3): WorkoutState {
        val state = PresFix.single(PresFix.lib("bench"), PresFix.normal(sets, 80.0, 5), rest = 150)
        return WorkoutReducer.reduce(state, PresFix.log(state, 0, 0), PresFix.at(100))
    }

    @Test
    fun testNoDockWithoutARest() {
        assertThat(PresFix.present(PresFix.freshUpperA()).dock).isNull()
        var state = benchAfterFirstSet()
        state = PresFix.reduced(state, WorkoutAction.SkipRest, 110)
        assertThat(PresFix.present(state, 111).dock).isNull()
    }

    @Test
    fun testRunningDockAndCeilingOfTheRemainingTime() {
        val state = benchAfterFirstSet() // rest ends at t0 + 250
        var dock = PresFix.unwrap(PresFix.present(state, 100).dock)
        assertThat(dock.remainingSeconds).isEqualTo(150)
        assertThat(dock.remainingText).isEqualTo("2:30")
        assertThat(dock.fraction).isWithin(0.0001).of(1.0)
        dock = PresFix.unwrap(PresFix.present(state, 100.4).dock)
        assertThat(dock.remainingSeconds).isEqualTo(150) // 149.6 s rounds up
        dock = PresFix.unwrap(PresFix.present(state, 101).dock)
        assertThat(dock.remainingSeconds).isEqualTo(149)
        assertThat(dock.remainingText).isEqualTo("2:29")
        dock = PresFix.unwrap(PresFix.present(state, 249.5).dock)
        assertThat(dock.remainingSeconds).isEqualTo(1)
        assertThat(dock.remainingText).isEqualTo("0:01")
        assertThat(dock.phase).isEqualTo(ActiveWorkoutPresentation.DockPhase.RUNNING)
    }

    @Test
    fun testFinishedDock() {
        val state = benchAfterFirstSet()
        for (seconds in listOf(250.0, 250.0001, 300.0, 10_000.0)) {
            val dock = PresFix.unwrap(PresFix.present(state, seconds).dock)
            assertWithMessage("at $seconds").that(dock.phase).isEqualTo(ActiveWorkoutPresentation.DockPhase.FINISHED)
            assertThat(dock.remainingSeconds).isEqualTo(0)
            assertThat(dock.remainingText).isEqualTo("Go")
            assertThat(dock.fraction).isEqualTo(1.0)
            assertThat(dock.totalSeconds).isEqualTo(150)
        }
    }

    @Test
    fun testNextSetTextForWorkingSets() {
        val state = benchAfterFirstSet()
        assertThat(PresFix.unwrap(PresFix.present(state, 101).dock).nextSetText).isEqualTo("Next · Set 2 · 80 kg × 5")
        val more = PresFix.reduced(state, PresFix.log(state, 0, 1), 120)
        assertThat(PresFix.unwrap(PresFix.present(more, 121).dock).nextSetText).isEqualTo("Next · Set 3 · 80 kg × 5")
    }

    @Test
    fun testNextSetTextForWarmUpDropAndFailureSets() {
        val sets = listOf(
            Triple(SetType.WARMUP, 50.0, 8), Triple(SetType.NORMAL, 80.0, 5), Triple(SetType.DROP, 60.0, 8),
            Triple(SetType.FAILURE, 70.0, 4), Triple(SetType.NORMAL, 82.5, 6),
        )
        var state = PresFix.single(PresFix.lib("bench"), sets, rest = 150)
        // A stray rest keeps the dock visible while sets are marked as logged one by one.
        state = state.copy(rest = RestState(endsAt = PresFix.at(500), totalSeconds = 150))
        assertThat(PresFix.unwrap(PresFix.present(state, 400).dock).nextSetText).isEqualTo("Next · Warm-up · 50 kg × 8")
        state = PresFix.marking(state, 0, listOf(0))
        assertThat(PresFix.unwrap(PresFix.present(state, 400).dock).nextSetText).isEqualTo("Next · Set 1 · 80 kg × 5")
        state = PresFix.marking(state, 0, listOf(1))
        assertThat(PresFix.unwrap(PresFix.present(state, 400).dock).nextSetText).isEqualTo("Next · Set D · 60 kg × 8")
        state = PresFix.marking(state, 0, listOf(2))
        assertThat(PresFix.unwrap(PresFix.present(state, 400).dock).nextSetText).isEqualTo("Next · Set F · 70 kg × 4")
        state = PresFix.marking(state, 0, listOf(3))
        assertThat(PresFix.unwrap(PresFix.present(state, 400).dock).nextSetText).isEqualTo("Next · Set 2 · 82.5 kg × 6")
    }

    @Test
    fun testNextSetTextForRepsOnlyAndDuration() {
        var pushup = PresFix.single(PresFix.lib("pushup"), listOf(Triple(SetType.NORMAL, 0.0, 12), Triple(SetType.NORMAL, 0.0, 10)))
        pushup = pushup.copy(rest = RestState(endsAt = PresFix.at(100), totalSeconds = 60))
        assertThat(PresFix.unwrap(PresFix.present(pushup, 50).dock).nextSetText).isEqualTo("Next · Set 1 · 12 reps")
        var plank = PresFix.single(PresFix.lib("plank"), listOf(Triple(SetType.NORMAL, 0.0, 45)))
        plank = plank.copy(rest = RestState(endsAt = PresFix.at(100), totalSeconds = 45))
        assertThat(PresFix.unwrap(PresFix.present(plank, 50).dock).nextSetText).isEqualTo("Next · Set 1 · 45 s")
    }

    @Test
    fun testAllSetsLoggedText() {
        var state = PresFix.single(PresFix.lib("bench"), PresFix.normal(2, 80.0, 5), rest = 150)
        state = PresFix.reduced(state, PresFix.log(state, 0, 0), 10)
        state = PresFix.reduced(state, PresFix.log(state, 0, 1), 20)
        val dock = PresFix.unwrap(PresFix.present(state, 30).dock)
        assertThat(dock.nextSetText).isEqualTo("All sets logged")
        assertThat(dock.showsRIR).isTrue()
    }

    @Test
    fun testRIRSelectorFollowsTheLastLoggedSet() {
        var state = benchAfterFirstSet()
        var dock = PresFix.unwrap(PresFix.present(state, 101).dock)
        assertThat(dock.showsRIR).isTrue()
        assertThat(dock.rirSelection).isNull()

        state = PresFix.reduced(state, WorkoutAction.ToggleLastSetRIR(2), 102)
        dock = PresFix.unwrap(PresFix.present(state, 103).dock)
        assertThat(dock.rirSelection).isEqualTo(2)
        state = PresFix.reduced(state, WorkoutAction.ToggleLastSetRIR(4), 104)
        assertThat(PresFix.unwrap(PresFix.present(state, 105).dock).rirSelection).isEqualTo(4)
        state = PresFix.reduced(state, WorkoutAction.ToggleLastSetRIR(4), 106)
        assertThat(PresFix.unwrap(PresFix.present(state, 107).dock).rirSelection).isNull()
    }

    @Test
    fun testRIRSelectorIsHiddenAfterAWarmUp() {
        var state = PresFix.single(PresFix.lib("bench"), listOf(Triple(SetType.WARMUP, 50.0, 8), Triple(SetType.NORMAL, 80.0, 5)), rest = 150)
        state = PresFix.reduced(state, PresFix.log(state, 0, 0), 10)
        val dock = PresFix.unwrap(PresFix.present(state, 11).dock)
        assertThat(dock.showsRIR).isFalse()
        assertThat(dock.rirSelection).isNull()
        assertThat(dock.nextSetText).isEqualTo("Next · Set 1 · 80 kg × 5")
    }

    @Test
    fun testRIRSelectorIsHiddenWhenTheLastLoggedSetIsNoLongerDone() {
        var state = benchAfterFirstSet()
        state = PresFix.reduced(state, WorkoutAction.ToggleSet(state.exercises[0].id, state.exercises[0].sets[0].id), 110)
        state = state.copy(rest = RestState(endsAt = PresFix.at(300), totalSeconds = 150)) // a stray rest is still shown
        assertThat(PresFix.unwrap(PresFix.present(state, 120).dock).showsRIR).isFalse()
    }

    @Test
    fun testRIRSelectorIsHiddenWithoutAResolvableLastLoggedSet() {
        var state = benchAfterFirstSet()
        state = state.copy(lastLogged = null)
        assertThat(PresFix.unwrap(PresFix.present(state, 120).dock).showsRIR).isFalse()
        state = state.copy(lastLogged = SetRef(exerciseID = PresFix.uuid(0xAAAA, 1), setID = PresFix.uuid(0xAAAA, 2)))
        assertThat(PresFix.unwrap(PresFix.present(state, 120).dock).showsRIR).isFalse()
        state = state.copy(lastLogged = SetRef(exerciseID = state.exercises[0].id, setID = PresFix.uuid(0xAAAA, 3)))
        assertThat(PresFix.unwrap(PresFix.present(state, 120).dock).showsRIR).isFalse()
    }

    @Test
    fun testRIRSelectorResolvesAcrossExercises() {
        // The last logged set belongs to another exercise than the one on the card.
        var state = PresFix.freshUpperA()
        state = PresFix.reduced(state, WorkoutAction.GoTo(2))
        state = PresFix.reduced(state, PresFix.log(state, 2, 0), 10)
        state = PresFix.reduced(state, WorkoutAction.ToggleLastSetRIR(1), 11)
        state = PresFix.reduced(state, WorkoutAction.GoTo(0), 12)
        val dock = PresFix.unwrap(PresFix.present(state, 20).dock)
        assertThat(dock.showsRIR).isTrue()
        assertThat(dock.rirSelection).isEqualTo(1)
    }

    @Test
    fun testDockWhilePausedIsFrozen() {
        var state = benchAfterFirstSet() // rest ends at t0 + 250
        state = PresFix.reduced(state, WorkoutAction.Pause, 130)
        for (seconds in listOf(131.0, 200.0, 5000.0)) {
            val dock = PresFix.unwrap(PresFix.present(state, seconds).dock)
            assertWithMessage("at $seconds").that(dock.remainingSeconds).isEqualTo(120)
            assertThat(dock.remainingText).isEqualTo("2:00")
            assertThat(dock.phase).isEqualTo(ActiveWorkoutPresentation.DockPhase.RUNNING)
            assertThat(dock.isPaused).isTrue()
        }
        state = PresFix.reduced(state, WorkoutAction.Resume, 520) // 390 s paused
        val dock = PresFix.unwrap(PresFix.present(state, 560).dock)
        assertThat(dock.remainingSeconds).isEqualTo(80)
        assertThat(dock.isPaused).isFalse()
    }

    @Test
    fun testDockFractionWithZeroTotalIsZero() {
        var state = PresFix.single(PresFix.lib("bench"), PresFix.normal(2, 80.0, 5))
        state = state.copy(rest = RestState(endsAt = PresFix.at(100), totalSeconds = 0))
        val dock = PresFix.unwrap(PresFix.present(state, 50).dock)
        assertThat(dock.fraction).isEqualTo(0.0)
        assertThat(dock.remainingSeconds).isEqualTo(50)
    }

    @Test
    fun testRestAdjustmentIsReflected() {
        var state = benchAfterFirstSet()
        state = PresFix.reduced(state, WorkoutAction.AdjustRest(15), 110) // ends at t0 + 265, total 165
        val dock = PresFix.unwrap(PresFix.present(state, 115).dock)
        assertThat(dock.remainingSeconds).isEqualTo(150)
        assertThat(dock.totalSeconds).isEqualTo(165)
        assertThat(dock.fraction).isWithin(0.0001).of(150.0 / 165.0)
    }
}

// endregion

// region Presenter: finish check

class PresenterFinishCheckTests {
    @Test
    fun testNothingLogged() {
        val check = PresFix.present(PresFix.freshUpperA()).finishCheck
        assertThat(check.loggedSets).isEqualTo(0)
        assertThat(check.unloggedSets).isEqualTo(20)
        assertThat(check.canFinish).isFalse()
        assertThat(check.title).isEqualTo("Nothing logged yet")
        assertThat(check.message).isEqualTo("Log at least one set to save this workout.")
    }

    @Test
    fun testOneUnloggedSetUsesTheSingular() {
        var state = PresFix.loggedEverything(PresFix.freshUpperA())
        val last = state.exercises[5].sets[2]
        state = PresFix.reduced(state, WorkoutAction.ToggleSet(state.exercises[5].id, last.id))
        val check = PresFix.present(state).finishCheck
        assertThat(check.loggedSets).isEqualTo(19)
        assertThat(check.unloggedSets).isEqualTo(1)
        assertThat(check.canFinish).isTrue()
        assertThat(check.title).isEqualTo("Finish workout?")
        assertThat(check.message).isEqualTo("1 set is not logged yet and will be left out.")
    }

    @Test
    fun testSeveralUnloggedSetsUseThePlural() {
        val state = PresFix.goldenState()
        assertThat(PresFix.present(state, 1500).finishCheck.message).isEqualTo("17 sets are not logged yet and will be left out.")
        val two = PresFix.marking(PresFix.single(PresFix.lib("bench"), PresFix.normal(4, 80.0, 5)), 0, listOf(0, 1))
        assertThat(PresFix.present(two).finishCheck.message).isEqualTo("2 sets are not logged yet and will be left out.")
    }

    @Test
    fun testAllSetsLogged() {
        val state = PresFix.loggedEverything(PresFix.freshUpperA())
        val view = PresFix.present(state, 600)
        assertThat(view.finishCheck.loggedSets).isEqualTo(20)
        assertThat(view.finishCheck.unloggedSets).isEqualTo(0)
        assertThat(view.finishCheck.canFinish).isTrue()
        assertThat(view.finishCheck.title).isEqualTo("Finish workout?")
        assertThat(view.finishCheck.message).isEqualTo("All sets are logged. Nice work.")
        assertThat(view.header.setsText).isEqualTo("20 of 20")
        assertThat(view.totals.completedExercises).isEqualTo(6)
        assertThat(view.header.segments.all { it.fraction == 1.0 }).isTrue()
    }

    @Test
    fun testTemplateChangesAskToUpdateTheTemplate() {
        var state = PresFix.goldenState()
        state = PresFix.reduced(state, WorkoutAction.RemoveExercise(state.exercises[5].id), 1500)
        state = PresFix.reduced(state, WorkoutAction.AddExercises(listOf(PresFix.lib("pushup"))), 1501)
        val check = PresFix.present(state, 1502).finishCheck
        assertThat(check.templateDiff).isEqualTo(TemplateDiff(added = 1, removed = 1, reordered = false))
        assertThat(check.diffMessage).isEqualTo("Changes: 1 added, 1 removed.")
        assertThat(check.asksToUpdateTemplate).isTrue()
    }

    @Test
    fun testNoTemplateMeansNoUpdateQuestion() {
        var state = WorkoutFactory.makeEmpty("Workout", PresFix.t0)
        state = PresFix.reduced(state, WorkoutAction.AddExercises(listOf(PresFix.lib("bench"), PresFix.lib("incline"))), 1)
        val check = PresFix.present(state, 2).finishCheck
        assertThat(check.templateDiff.isEmpty).isFalse()
        assertThat(state.templateID).isNull()
        assertThat(check.asksToUpdateTemplate).isFalse()
        assertThat(check.diffMessage).isEqualTo("Changes: 2 added.")
    }

    @Test
    fun testDiffMessageListsEveryKindOfChange() {
        var state = PresFix.freshUpperA()
        state = PresFix.reduced(state, WorkoutAction.MoveExercise(0, 2), 1)
        state = PresFix.reduced(state, WorkoutAction.RemoveExercise(state.exercises[4].id), 2)
        state = PresFix.reduced(state, WorkoutAction.AddExercises(listOf(PresFix.lib("dips"))), 3)
        val check = PresFix.present(state, 4).finishCheck
        assertThat(check.diffMessage).isEqualTo("Changes: 1 added, 1 removed, new order.")
        assertThat(check.asksToUpdateTemplate).isTrue()
    }
}

// endregion

// region Template diff

class TemplateDiffComputeTests {
    @Test
    fun testUntouchedWorkoutHasNoDiff() {
        val diff = TemplateDiff.compute(PresFix.freshUpperA())
        assertThat(diff.isEmpty).isTrue()
        assertThat(diff).isEqualTo(TemplateDiff(added = 0, removed = 0, reordered = false))
    }

    @Test
    fun testProgressDoesNotChangeTheDiff() {
        assertThat(TemplateDiff.compute(PresFix.goldenState()).isEmpty).isTrue()
        assertThat(TemplateDiff.compute(PresFix.loggedEverything(PresFix.freshUpperA())).isEmpty).isTrue()
    }

    @Test
    fun testAddedExercises() {
        var state = PresFix.freshUpperA()
        state = PresFix.reduced(state, WorkoutAction.AddExercises(listOf(PresFix.lib("dips"))))
        assertThat(TemplateDiff.compute(state)).isEqualTo(TemplateDiff(added = 1, removed = 0, reordered = false))
        state = PresFix.reduced(state, WorkoutAction.AddExercises(listOf(PresFix.lib("pullup"), PresFix.lib("squat"))))
        assertThat(TemplateDiff.compute(state)).isEqualTo(TemplateDiff(added = 3, removed = 0, reordered = false))
    }

    @Test
    fun testRemovedExercises() {
        var state = PresFix.freshUpperA()
        state = PresFix.reduced(state, WorkoutAction.RemoveExercise(state.exercises[2].id))
        assertThat(TemplateDiff.compute(state)).isEqualTo(TemplateDiff(added = 0, removed = 1, reordered = false))
        state = PresFix.reduced(state, WorkoutAction.RemoveExercise(state.exercises[0].id))
        assertThat(TemplateDiff.compute(state)).isEqualTo(TemplateDiff(added = 0, removed = 2, reordered = false))
    }

    @Test
    fun testRemovingAndUndoingRestoresTheOriginalDiff() {
        var state = PresFix.freshUpperA()
        state = PresFix.reduced(state, WorkoutAction.RemoveExercise(state.exercises[2].id), 1)
        assertThat(TemplateDiff.compute(state).removed).isEqualTo(1)
        state = PresFix.reduced(state, WorkoutAction.Undo, 2)
        assertThat(TemplateDiff.compute(state).isEmpty).isTrue()
    }

    @Test
    fun testReorderedExercises() {
        var state = PresFix.freshUpperA()
        state = PresFix.reduced(state, WorkoutAction.MoveExercise(0, 3))
        assertThat(TemplateDiff.compute(state)).isEqualTo(TemplateDiff(added = 0, removed = 0, reordered = true))
        // Moving it back restores the baseline order.
        state = PresFix.reduced(state, WorkoutAction.MoveExercise(3, 0))
        assertThat(TemplateDiff.compute(state).isEmpty).isTrue()
    }

    @Test
    fun testSwappingNeighboursCountsAsReordered() {
        var state = PresFix.freshUpperA()
        state = PresFix.reduced(state, WorkoutAction.MoveExerciseBy(state.exercises[1].id, 1))
        assertThat(TemplateDiff.compute(state).reordered).isTrue()
    }

    @Test
    fun testCombinedChanges() {
        var state = PresFix.freshUpperA()
        state = PresFix.reduced(state, WorkoutAction.RemoveExercise(state.exercises[1].id), 1)
        state = PresFix.reduced(state, WorkoutAction.AddExercises(listOf(PresFix.lib("dips"), PresFix.lib("pullup"))), 2)
        state = PresFix.reduced(state, WorkoutAction.MoveExercise(0, 2), 3)
        val diff = TemplateDiff.compute(state)
        assertThat(diff).isEqualTo(TemplateDiff(added = 2, removed = 1, reordered = true))
        assertThat(diff.summary).isEqualTo("2 added, 1 removed, new order")
    }

    @Test
    fun testRemovingFromTheMiddleIsNotAReorder() {
        var state = PresFix.freshUpperA()
        state = PresFix.reduced(state, WorkoutAction.RemoveExercise(state.exercises[2].id))
        assertThat(TemplateDiff.compute(state).reordered).isFalse()
    }

    @Test
    fun testMovingAnAddedExerciseIsNotAReorder() {
        var state = PresFix.freshUpperA()
        state = PresFix.reduced(state, WorkoutAction.AddExercises(listOf(PresFix.lib("dips"))), 1)
        state = PresFix.reduced(state, WorkoutAction.MoveExercise(6, 0), 2)
        assertThat(TemplateDiff.compute(state)).isEqualTo(TemplateDiff(added = 1, removed = 0, reordered = false))
    }

    @Test
    fun testReplacingKeepsTheTemplateEntry() {
        var state = PresFix.freshUpperA()
        state = PresFix.reduced(state, WorkoutAction.ReplaceExercise(state.exercises[1].id, PresFix.lib("cpress")))
        assertThat(TemplateDiff.compute(state).isEmpty).isTrue()
    }

    @Test
    fun testWorkoutWithoutTemplateCountsEveryExerciseAsAdded() {
        var state = WorkoutFactory.makeEmpty("Workout", PresFix.t0)
        assertThat(TemplateDiff.compute(state).isEmpty).isTrue()
        state = PresFix.reduced(state, WorkoutAction.AddExercises(listOf(PresFix.lib("bench"), PresFix.lib("incline"))))
        assertThat(TemplateDiff.compute(state)).isEqualTo(TemplateDiff(added = 2, removed = 0, reordered = false))
    }

    @Test
    fun testExercisesWithEntriesOutsideTheBaselineAreAdded() {
        var state = PresFix.freshUpperA()
        state = PresFix.editExercise(state, 0) { it.copy(templateEntryID = PresFix.uuid(0xBEEF, 1)) }
        assertThat(TemplateDiff.compute(state)).isEqualTo(TemplateDiff(added = 1, removed = 1, reordered = false))
    }

    @Test
    fun testADuplicatedTemplateEntryCountsAsAdded() {
        var state = PresFix.freshUpperA()
        val copy = state.exercises[0].copy(id = PresFix.uuid(0xCAFE, 1))
        state = state.copy(exercises = state.exercises + copy)
        assertThat(TemplateDiff.compute(state)).isEqualTo(TemplateDiff(added = 1, removed = 0, reordered = false))
    }

    @Test
    fun testEverythingRemovedAndReplacedByNewExercises() {
        var state = PresFix.freshUpperA()
        state = state.copy(exercises = listOf(PresFix.entry(1, PresFix.lib("squat"), PresFix.normal(3, 60.0, 6))))
        assertThat(TemplateDiff.compute(state)).isEqualTo(TemplateDiff(added = 1, removed = 6, reordered = false))
        state = state.copy(exercises = emptyList())
        assertThat(TemplateDiff.compute(state)).isEqualTo(TemplateDiff(added = 0, removed = 6, reordered = false))
    }
}

// endregion

// region Fuzz: invariants under random action sequences

/** Tiny deterministic linear congruential generator (no real randomness); 64-bit wrapping arithmetic as in the Swift original. */
internal class PresLCG(seed: Long) {
    private var state: Long = seed * 6364136223846793005L + 1442695040888963407L

    fun next(): Long {
        state = state * 6364136223846793005L + 1442695040888963407L
        return state ushr 33
    }

    fun below(bound: Int): Int = if (bound <= 0) 0 else (next() % bound.toLong()).toInt()
}

class PresenterFuzzTests {
    private fun randomAction(state: WorkoutState, rng: PresLCG): WorkoutAction {
        val exercise = if (state.exercises.isEmpty()) null else state.exercises[rng.below(state.exercises.size)]
        val set = exercise?.let { if (it.sets.isEmpty()) null else it.sets[rng.below(it.sets.size)] }
        val exerciseID = exercise?.id ?: PresFix.uuid(0xDEAD, 1)
        val setID = set?.id ?: PresFix.uuid(0xDEAD, 2)
        return when (rng.below(22)) {
            0, 1, 2, 3 -> WorkoutAction.ToggleSet(exerciseID, setID)
            4, 5 -> WorkoutAction.LogNextSet
            6 -> WorkoutAction.LogSet(exerciseID, setID)
            7 -> WorkoutAction.SetRIR(exerciseID, setID, if (rng.below(6) == 5) null else rng.below(5))
            8 -> WorkoutAction.ToggleLastSetRIR(rng.below(5))
            9 -> WorkoutAction.SetSetType(exerciseID, setID, SetType.entries[rng.below(4)])
            10 -> WorkoutAction.AddSet(exerciseID)
            11 -> WorkoutAction.DeleteSet(exerciseID, setID)
            12 -> WorkoutAction.RemoveExercise(exerciseID)
            13 -> WorkoutAction.Undo
            14 -> WorkoutAction.MoveExercise(rng.below(8), rng.below(8))
            15 -> WorkoutAction.GoTo(rng.below(8))
            16 -> WorkoutAction.AddExercises(listOf(PresFix.lib(listOf("dips", "pushup", "plank", "squat", "bench")[rng.below(5)])))
            17 -> WorkoutAction.AdjustRest(if (rng.below(2) == 0) 15 else -15)
            18 -> if (rng.below(2) == 0) WorkoutAction.Pause else WorkoutAction.Resume
            19 -> WorkoutAction.SetWeight(exerciseID, setID, rng.below(200).toDouble() / 2)
            20 -> WorkoutAction.ToggleSuperset(exerciseID)
            else -> WorkoutAction.SkipRest
        }
    }

    private fun check(state: WorkoutState, now: Instant, context: String) {
        val view = WorkoutPresenter.present(state, now, PresFix.demoRecovery)
        val totals = view.totals
        val allSets = state.exercises.flatMap { it.sets }
        assertWithMessage(context).that(totals.totalSets).isEqualTo(allSets.size)
        assertWithMessage(context).that(totals.loggedSets).isEqualTo(allSets.count { it.isDone })
        assertWithMessage(context).that(view.header.setsText).isEqualTo("${totals.loggedSets} of ${totals.totalSets}")
        assertWithMessage(context).that(view.header.segments.size).isEqualTo(state.exercises.size)
        assertWithMessage(context).that(view.header.segments.count { it.isCurrent }).isEqualTo(if (state.exercises.isEmpty()) 0 else 1)
        assertWithMessage(context).that(view.isEmpty).isEqualTo(state.exercises.isEmpty())
        assertWithMessage(context).that(view.card == null).isEqualTo(state.exercises.isEmpty())
        assertWithMessage(context).that(view.navigator == null).isEqualTo(state.exercises.isEmpty())
        assertWithMessage(context).that(view.dock != null).isEqualTo(state.rest != null && state.exercises.isNotEmpty())
        assertWithMessage(context).that(view.finishCheck.unloggedSets).isEqualTo(totals.totalSets - totals.loggedSets)
        assertWithMessage(context).that(view.finishCheck.canFinish).isEqualTo(totals.loggedSets > 0)
        assertWithMessage(context).that(totals.volumeKg).isAtLeast(0.0)
        for (segment in view.header.segments) {
            assertWithMessage(context).that(segment.fraction in 0.0..1.0).isTrue()
        }
        val dock = view.dock
        if (dock != null) {
            assertWithMessage(context).that(dock.fraction in 0.0..1.0).isTrue()
            assertWithMessage(context).that(dock.remainingSeconds).isAtLeast(0)
            assertWithMessage(context).that(dock.phase == ActiveWorkoutPresentation.DockPhase.FINISHED).isEqualTo(dock.remainingSeconds == 0)
            if (dock.phase == ActiveWorkoutPresentation.DockPhase.FINISHED) assertWithMessage(context).that(dock.remainingText).isEqualTo("Go")
        }
        val card = view.card
        if (card != null) {
            val entry = state.currentExercise!!
            assertWithMessage(context).that(card.rows.size).isEqualTo(entry.sets.size)
            val pending = entry.sets.any { !it.isDone }
            assertWithMessage(context).that(card.rows.count { it.isNext }).isEqualTo(if (pending) 1 else 0)
            assertWithMessage(context).that(card.coachTip != null && state.rest != null).isFalse()
            for (row in card.rows) {
                if (row.isPersonalRecord) {
                    assertWithMessage(context).that(row.isDone).isTrue()
                    assertWithMessage(context).that(row.estimated1RM).isNotNull()
                    assertWithMessage(context).that(row.type).isNotEqualTo(SetType.WARMUP)
                } else {
                    assertWithMessage(context).that(row.estimated1RM).isNull()
                }
                if (row.rirText != null) assertWithMessage(context).that(row.isDone).isTrue()
                assertWithMessage(context).that(row.accessibilityLabel.isEmpty()).isFalse()
            }
        }
        assertWithMessage(context).that(view.finishCheck.templateDiff).isEqualTo(TemplateDiff.compute(state))
    }

    @Test
    fun testInvariantsHoldUnderRandomActions() {
        for (seed in 1..12) {
            val rng = PresLCG(seed.toLong())
            var state = if (seed % 3 == 0) {
                WorkoutFactory.makeEmpty("Fuzz", PresFix.t0)
            } else {
                WorkoutFactory.makeWorkout(PresFix.upperA(), PresFix.t0)
            }
            var clock = 0.0
            for (step in 0 until 160) {
                clock += rng.below(40).toDouble() / 4
                val action = randomAction(state, rng)
                state = WorkoutReducer.reduce(state, action, PresFix.at(clock))
                check(state, PresFix.at(clock + rng.below(200).toDouble() / 2), "seed $seed step $step $action")
            }
        }
    }
}

// endregion
