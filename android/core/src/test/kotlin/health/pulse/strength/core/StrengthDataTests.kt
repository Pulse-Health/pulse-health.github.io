package health.pulse.strength.core

import com.google.common.truth.Truth.assertThat
import com.google.common.truth.Truth.assertWithMessage
import health.pulse.strength.core.StrengthDataTests.SvcDataFix
import health.pulse.strength.core.StrengthDataTests.SvcSyncFix
import java.time.Instant
import java.util.UUID
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runTest
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

// Port of StrengthDataTests.swift: StrengthDataTests (the value type), StrengthDataModelTests (data + files) and
// StrengthStoreWrapperTests (the Swift Combine wrapper; here StrengthStore and its `data` StateFlow).

class StrengthDataTests {
    /** Fixtures shared by several test files (Swift `SvcSyncFix`, defined in SyncTests.swift). */
    object SvcSyncFix {
        /** 2026-10-13T19:30:00Z. */
        val epoch: Instant = Instant.ofEpochSecond(1_791_919_800)

        fun at(offset: Double): Instant = epoch.addingTimeInterval(offset)

        fun uuid(n: Int): UUID {
            val hex = n.toString(16).uppercase().padStart(12, '0')
            return UUID.fromString("0000FEED-0000-4000-8000-$hex")
        }

        /** A workout started from "Upper A · Push" with some progress, a rest, an undo entry and heart-rate data. */
        fun richState(): WorkoutState {
            var state = WorkoutFactory.makeWorkout(SampleData.templates()[0], epoch, uuid(1))
            var now = epoch.addingTimeInterval(60.0)
            repeat(3) {
                state = WorkoutReducer.reduce(state, WorkoutAction.LogNextSet, now)
                now = now.addingTimeInterval(90.0)
            }
            state = WorkoutReducer.reduce(state, WorkoutAction.ToggleLastSetRIR(2), now)
            state = WorkoutReducer.reduce(state, WorkoutAction.UpdateHeartRate(131), now)
            state = WorkoutReducer.reduce(
                state,
                WorkoutAction.SetNote(state.exercises[1].id, "Slow tempo — \"quotes\" and ünïcode"),
                now,
            )
            state = WorkoutReducer.reduce(state, WorkoutAction.RemoveExercise(state.exercises[5].id), now)
            state = WorkoutReducer.reduce(state, WorkoutAction.Pause, now)
            return state
        }
    }

    /** Deterministic pseudo random numbers (64-bit LCG), the Kotlin twin of Swift's `SvcLCG`. */
    class SvcLCG(seed: ULong) {
        private var state: ULong = seed

        fun next(): ULong {
            state = state * 6_364_136_223_846_793_005uL + 1_442_695_040_888_963_407uL
            return state shr 24
        }

        /** A value in `0 until count`. */
        fun int(count: Int): Int = (next() % maxOf(1, count).toULong()).toInt()

        /** A value in [range] (inclusive). */
        fun int(range: IntRange): Int = range.first + int(range.last - range.first + 1)
    }

    /** Builders for finished workouts with deterministic ids (Swift `SvcDataFix`). */
    object SvcDataFix {
        val now: Instant = SvcSyncFix.epoch

        fun daysAgo(days: Double): Instant = now.addingTimeInterval(-days * 86_400.0)

        fun work(kg: Number, reps: Int, rir: Int? = null): CompletedSet =
            CompletedSet(type = SetType.NORMAL, weightKg = kg.toDouble(), reps = reps, rir = rir)

        fun warmup(kg: Number, reps: Int): CompletedSet = CompletedSet(type = SetType.WARMUP, weightKg = kg.toDouble(), reps = reps)

        /** An entry for a built-in exercise; [best] overrides the recorded e1RM (null = the real best of the working sets). */
        fun entry(exerciseID: String, sets: List<CompletedSet>, best: Double? = null, pr: Boolean = false, n: Int = 0): CompletedExercise {
            val exercise = ExerciseLibrary.exercise(exerciseID)!!
            val computed = if (exercise.tracksWeight) {
                sets.filter { it.type != SetType.WARMUP }.maxOfOrNull { Estimated1RM.epley(it.weightKg, it.reps) } ?: 0.0
            } else {
                0.0
            }
            return CompletedExercise(
                id = SvcSyncFix.uuid(5000 + n), exerciseID = exerciseID, name = exercise.name, muscle = exercise.muscle,
                mediaKey = exercise.mediaKey, tracking = exercise.tracking, sets = sets, isPersonalRecord = pr, bestE1RM = best ?: computed,
            )
        }

        fun workout(
            n: Int,
            finishedAt: Instant,
            vararg entries: CompletedExercise,
            name: String = "Upper A · Push",
            templateID: UUID? = null,
        ): CompletedWorkout = CompletedWorkout(
            id = SvcSyncFix.uuid(n), name = name, templateID = templateID, startedAt = finishedAt.addingTimeInterval(-3000.0),
            finishedAt = finishedAt, durationSeconds = 3000, volumeKg = 0.0, loggedSets = entries.sumOf { it.sets.size },
            averageHeartRate = null, averageRIR = null, exercises = entries.toList(), personalRecords = emptyList(), muscleSets = emptyList(),
        )

        fun customExercise(name: String, tracking: TrackingKind = TrackingKind.WEIGHT_REPS): Exercise =
            Exercise.custom(name = name, muscle = MuscleGroup.ARMS, equipment = Equipment.DUMBBELL, tracking = tracking, id = "custom-" + name.lowercase())
    }

    private val F = SvcDataFix

    // region Exercises and overlay

    @Test
    fun testWithoutResultsTheLibraryIsReturnedUnchanged() {
        val data = StrengthData()
        assertThat(data.exercises()).isEqualTo(ExerciseLibrary.builtIn)
        assertThat(data.exercises()).hasSize(36)
        assertThat(data.exercise("bench")).isEqualTo(ExerciseLibrary.exercise("bench"))
        assertThat(data.exercise("nope")).isNull()
        assertThat(data.isEmpty).isTrue()
    }

    @Test
    fun testAPersonalBestOverridesThePreviousBest() {
        val data = StrengthData(
            personalBests = mapOf(
                "bench" to PersonalBest(exerciseID = "bench", estimated1RM = 120.0, weightKg = 100.0, reps = 6, date = F.now),
                "incline" to PersonalBest(exerciseID = "incline", estimated1RM = 10.0, weightKg = 8.0, reps = 8, date = F.now),
            ),
        )
        assertThat(data.exercise("bench")!!.previousBestE1RM).isEqualTo(120.0)
        assertWithMessage("what is remembered wins").that(data.exercise("incline")!!.previousBestE1RM).isEqualTo(10.0)
        assertWithMessage("untouched exercises keep the library value").that(data.exercise("ohp")!!.previousBestE1RM).isEqualTo(58.0)
        val expected = ExerciseLibrary.exercise("bench")!!.copy(previousBestE1RM = 120.0)
        assertThat(data.exercise("bench")).isEqualTo(expected)
    }

    @Test
    fun testHistoryProvidesTheBestAndThePreviousSets() {
        val data = StrengthData(
            history = listOf(F.workout(1, F.daysAgo(2.0), F.entry("squat", listOf(F.warmup(40, 8), F.work(80, 6), F.work(90, 4)), n = 1), name = "Lower")),
        )
        val squat = data.exercise("squat")!!
        assertThat(squat.previousSets).isEqualTo(listOf(PreviousSet(40.0, 8), PreviousSet(80.0, 6), PreviousSet(90.0, 4)))
        assertThat(squat.previousBestE1RM).isWithin(1e-9).of(102.0)       // 90 x 4 (102) beats 80 x 6 (96); the warm-up is ignored
        assertThat(data.exercise("legpress")).isEqualTo(ExerciseLibrary.exercise("legpress"))
    }

    @Test
    fun testThePreviousSetsComeFromTheNewestSessionWhateverTheArrayOrder() {
        val older = F.workout(1, F.daysAgo(9.0), F.entry("bench", listOf(F.work(70, 8)), n = 1))
        val newer = F.workout(2, F.daysAgo(2.0), F.entry("bench", listOf(F.work(75, 6)), n = 2))
        var data = StrengthData(history = listOf(older, newer))
        assertThat(data.exercise("bench")?.previousSets).isEqualTo(listOf(PreviousSet(75.0, 6)))
        data = data.copy(history = listOf(newer, older))
        assertThat(data.exercise("bench")?.previousSets).isEqualTo(listOf(PreviousSet(75.0, 6)))
        // The best comes from every session: 75 x 6 = 90 beats 70 x 8 = 88.67, and replaces the library's 99.
        assertThat(data.exercise("bench")!!.previousBestE1RM).isWithin(1e-9).of(90.0)
    }

    @Test
    fun testTheHistoryBestWinsOverALowerPersonalBestAndViceVersa() {
        var data = StrengthData(history = listOf(F.workout(1, F.daysAgo(2.0), F.entry("bench", listOf(F.work(100, 3)), n = 1))))   // 110
        data = data.copy(personalBests = mapOf("bench" to PersonalBest("bench", 105.0, 100.0, 1, F.daysAgo(40.0))))
        assertThat(data.exercise("bench")!!.previousBestE1RM).isWithin(1e-9).of(110.0)
        data = data.copy(personalBests = mapOf("bench" to PersonalBest("bench", 130.0, 110.0, 1, F.daysAgo(40.0))))
        assertThat(data.exercise("bench")!!.previousBestE1RM).isWithin(1e-9).of(130.0)
    }

    @Test
    fun testEntriesWithoutSetsDoNotReplaceThePreviousSets() {
        val data = StrengthData(history = listOf(F.workout(1, F.daysAgo(1.0), F.entry("bench", emptyList(), n = 1))))
        assertThat(data.exercise("bench")?.previousSets).isEqualTo(ExerciseLibrary.exercise("bench")?.previousSets)
    }

    @Test
    fun testTheSameExerciseTwiceInOneWorkoutIsMerged() {
        val data = StrengthData(
            history = listOf(
                F.workout(
                    1, F.daysAgo(1.0),
                    F.entry("bench", listOf(F.work(60, 10)), n = 1), F.entry("incline", listOf(F.work(20, 10)), n = 2), F.entry("bench", listOf(F.work(65, 8)), n = 3),
                ),
            ),
        )
        assertThat(data.exercise("bench")?.previousSets).isEqualTo(listOf(PreviousSet(60.0, 10), PreviousSet(65.0, 8)))
    }

    @Test
    fun testCustomExercisesFollowTheLibraryAndGetTheOverlayToo() {
        val curl = F.customExercise("Zottman curl")
        var data = StrengthData().addingCustomExercise(curl)
        data = data.copy(
            history = listOf(
                F.workout(
                    1, F.daysAgo(1.0),
                    CompletedExercise(
                        exerciseID = curl.id, name = curl.name, muscle = MuscleGroup.ARMS, mediaKey = null, tracking = TrackingKind.WEIGHT_REPS,
                        sets = listOf(F.work(14, 10)), isPersonalRecord = false, bestE1RM = 0.0,
                    ),
                ),
            ),
        )
        val all = data.exercises()
        assertThat(all).hasSize(37)
        assertThat(all.last().id).isEqualTo(curl.id)
        val overlaid = data.exercise(curl.id)!!
        assertThat(overlaid.previousSets).isEqualTo(listOf(PreviousSet(14.0, 10)))
        assertWithMessage("computed from the sets when the entry recorded none")
            .that(overlaid.previousBestE1RM).isWithin(1e-9).of(14 * (1 + 10.0 / 30))
        assertThat(overlaid.isCustom).isTrue()
    }

    @Test
    fun testCustomExercisesMustNotShadowBuiltInIds() {
        val impostor = F.customExercise("Fake bench").copy(id = "bench")
        var data = StrengthData().addingCustomExercise(impostor)
        assertThat(data.customExercises).isEmpty()
        data = data.copy(customExercises = listOf(impostor))          // e.g. loaded from a damaged file
        assertThat(data.exercises()).hasSize(36)
        assertThat(data.exercise("bench")).isEqualTo(ExerciseLibrary.exercise("bench"))
    }

    @Test
    fun testAddingACustomExerciseMarksItCustomAndReplacesById() {
        var data = StrengthData()
        val first = F.customExercise("Landmine press").copy(isCustom = false)
        data = data.addingCustomExercise(first)
        assertThat(data.customExercises.map { it.isCustom }).isEqualTo(listOf(true))
        val renamed = first.copy(name = "Landmine press (heavy)")
        data = data.addingCustomExercise(renamed)
        data = data.addingCustomExercise(F.customExercise("Sled push"))
        assertThat(data.customExercises.map { it.name }).isEqualTo(listOf("Landmine press (heavy)", "Sled push"))
    }

    // endregion

    // region Templates

    @Test
    fun testSaveTemplateInsertsThenReplacesInPlace() {
        var data = StrengthData(templates = SampleData.templates())
        val edited = data.templates[1].copy(name = "Lower A · Quads (new)")
        data = data.savingTemplate(edited)
        assertThat(data.templates.map { it.name }).isEqualTo(listOf("Upper A · Push", "Lower A · Quads (new)", "Upper B · Pull"))
        val extra = WorkoutTemplate(id = SvcSyncFix.uuid(77), name = "Arms", entries = emptyList())
        data = data.savingTemplate(extra)
        assertThat(data.templates).hasSize(4)
        assertThat(data.templates.last()).isEqualTo(extra)
        assertThat(data.template(extra.id)).isEqualTo(extra)
        assertThat(data.template(SvcSyncFix.uuid(78))).isNull()
    }

    // endregion

    // region Recording

    @Test
    fun testRecordInsertsNewestFirst() {
        var data = StrengthData()
        val a = F.workout(1, F.daysAgo(5.0), F.entry("bench", listOf(F.work(80, 5)), n = 1))
        val b = F.workout(2, F.daysAgo(1.0), F.entry("bench", listOf(F.work(80, 5)), n = 2))
        val c = F.workout(3, F.daysAgo(3.0), F.entry("bench", listOf(F.work(80, 5)), n = 3))
        for (workout in listOf(a, b, c)) data = data.recording(workout, null)
        assertThat(data.history.map { it.id }).isEqualTo(listOf(b.id, c.id, a.id))
    }

    @Test
    fun testRecordingTheSameWorkoutTwiceReplacesIt() {
        var data = StrengthData()
        val first = F.workout(1, F.daysAgo(1.0), F.entry("bench", listOf(F.work(80, 5)), n = 1))
        val edited = first.copy(name = "Edited")
        data = data.recording(first, null)
        data = data.recording(edited, null)
        assertThat(data.history).isEqualTo(listOf(edited))
    }

    @Test
    fun testPersonalBestIsCreatedAndOnlyRaisedWhenBeaten() {
        var data = StrengthData()
        data = data.recording(
            F.workout(1, F.daysAgo(10.0), F.entry("bench", listOf(F.warmup(120, 3), F.work(80, 6), F.work(85, 5)), n = 1)),
            null,
        )
        var best = data.personalBests["bench"]!!
        assertThat(best.exerciseID).isEqualTo("bench")
        assertThat(best.estimated1RM).isWithin(1e-9).of(85 * (1 + 5.0 / 30))
        assertWithMessage("the warm-up with more weight is not the best set").that(best.weightKg).isEqualTo(85.0)
        assertThat(best.reps).isEqualTo(5)
        assertThat(best.date).isEqualTo(F.daysAgo(10.0))

        // Equal estimate: unchanged (strictly greater is required).
        data = data.recording(F.workout(2, F.daysAgo(5.0), F.entry("bench", listOf(F.work(85, 5)), n = 2)), null)
        assertThat(data.personalBests["bench"]).isEqualTo(best)
        // Lower: unchanged.
        data = data.recording(F.workout(3, F.daysAgo(4.0), F.entry("bench", listOf(F.work(80, 6)), n = 3)), null)
        assertThat(data.personalBests["bench"]).isEqualTo(best)
        // Higher: raised, with the new set and date.
        data = data.recording(F.workout(4, F.daysAgo(1.0), F.entry("bench", listOf(F.work(87.5, 5)), n = 4)), null)
        best = data.personalBests["bench"]!!
        assertThat(best.estimated1RM).isWithin(1e-9).of(87.5 * (1 + 5.0 / 30))
        assertThat(best.weightKg).isEqualTo(87.5)
        assertThat(best.date).isEqualTo(F.daysAgo(1.0))
    }

    @Test
    fun testEveryExerciseOfAWorkoutIsConsidered() {
        val data = StrengthData().recording(
            F.workout(
                1, F.daysAgo(1.0),
                F.entry("bench", listOf(F.work(80, 5)), n = 1), F.entry("squat", listOf(F.work(100, 5)), n = 2),
                F.entry("pullup", listOf(F.work(0, 12)), n = 3), F.entry("plank", listOf(F.work(0, 60)), n = 4),
            ),
            null,
        )
        assertWithMessage("bodyweight and duration exercises have no e1RM").that(data.personalBests.keys).isEqualTo(setOf("bench", "squat"))
    }

    @Test
    fun testTheRecordedEstimateIsUsedAndAZeroOneIsComputedFromTheSets() {
        var data = StrengthData()
        data = data.recording(F.workout(1, F.daysAgo(2.0), F.entry("bench", listOf(F.work(80, 5)), best = 120.0, n = 1)), null)
        assertThat(data.personalBests["bench"]!!.estimated1RM).isEqualTo(120.0)
        data = data.recording(F.workout(2, F.daysAgo(1.0), F.entry("squat", listOf(F.warmup(60, 5), F.work(100, 3)), best = 0.0, n = 2)), null)
        assertThat(data.personalBests["squat"]!!.estimated1RM).isWithin(1e-9).of(110.0)
        data = data.recording(F.workout(3, F.daysAgo(1.0), F.entry("deadlift", listOf(F.warmup(100, 5)), best = 0.0, n = 3)), null)
        assertWithMessage("warm-ups alone never set a best").that(data.personalBests["deadlift"]).isNull()
    }

    @Test
    fun testRecordSetsLastPerformedOfTheWorkoutsTemplate() {
        var data = StrengthData(templates = SampleData.templates(F.now))
        val upper = data.templates[0]
        assertThat(upper.lastPerformed).isEqualTo(F.daysAgo(5.0))
        data = data.recording(F.workout(1, F.daysAgo(0.5), F.entry("bench", listOf(F.work(80, 5)), n = 1), templateID = upper.id), null)
        assertThat(data.templates[0].lastPerformed).isEqualTo(F.daysAgo(0.5))
        assertWithMessage("other templates are untouched").that(data.templates[1].lastPerformed).isEqualTo(F.daysAgo(7.0))
        // An older workout never moves lastPerformed backwards.
        data = data.recording(F.workout(2, F.daysAgo(30.0), F.entry("bench", listOf(F.work(60, 5)), n = 2), templateID = upper.id), null)
        assertThat(data.templates[0].lastPerformed).isEqualTo(F.daysAgo(0.5))
        // A workout of an unknown template changes no template.
        val before = data.templates
        data = data.recording(F.workout(3, F.daysAgo(0.1), F.entry("bench", listOf(F.work(60, 5)), n = 3), templateID = SvcSyncFix.uuid(999)), null)
        assertThat(data.templates).isEqualTo(before)
    }

    @Test
    fun testRecordWithAnUpdatedTemplateReplacesTheStoredOne() {
        var data = StrengthData(templates = SampleData.templates())
        val updated = data.templates[0].let { it.copy(entries = it.entries.dropLast(1)) }
        assertThat(updated.lastPerformed).isNull()
        data = data.recording(F.workout(1, F.daysAgo(1.0), F.entry("bench", listOf(F.work(80, 5)), n = 1), templateID = updated.id), updated)
        assertThat(data.templates).hasSize(3)
        assertThat(data.templates[0].id).isEqualTo(updated.id)
        assertThat(data.templates[0].entries).isEqualTo(updated.entries)
        assertThat(data.templates[0].lastPerformed).isEqualTo(F.daysAgo(1.0))
        assertWithMessage("position is kept").that(data.templates.map { it.name })
            .isEqualTo(listOf("Upper A · Push", "Lower A · Quads", "Upper B · Pull"))
    }

    @Test
    fun testRecordWithATemplateThatIsNotStoredYetAddsIt() {
        val template = SampleData.templates()[2]
        val data = StrengthData().recording(F.workout(1, F.daysAgo(1.0), F.entry("bench", listOf(F.work(80, 5)), n = 1)), template)
        assertThat(data.templates.map { it.id }).isEqualTo(listOf(template.id))
        assertThat(data.templates[0].lastPerformed).isEqualTo(F.daysAgo(1.0))
    }

    // endregion

    // region Seeding

    @Test
    fun testSeedingFillsAnEmptyStoreOnce() {
        val empty = StrengthData()
        val data = empty.seedingDemoDataIfEmpty(F.now)
        assertWithMessage("it seeded").that(data).isNotEqualTo(empty)
        assertThat(data.templates).hasSize(3)
        assertThat(data.history).hasSize(5)
        assertThat(data.personalBests).isNotEmpty()
        assertThat(data.isEmpty).isFalse()
        val again = data.seedingDemoDataIfEmpty(F.now.addingTimeInterval(86_400.0))
        assertThat(again).isEqualTo(data)
    }

    @Test
    fun testSeedingKeepsExistingBestsAndRefusesANonEmptyStore() {
        val mine = PersonalBest(exerciseID = "bench", estimated1RM = 140.0, weightKg = 120.0, reps = 5, date = F.now)
        val onlyBests = StrengthData(personalBests = mapOf("bench" to mine))
        val seededBests = onlyBests.seedingDemoDataIfEmpty(F.now)
        assertWithMessage("it seeded").that(seededBests).isNotEqualTo(onlyBests)
        assertThat(seededBests.personalBests).isEqualTo(mapOf("bench" to mine))

        val withTemplate = StrengthData(templates = listOf(WorkoutTemplate(name = "Mine", entries = emptyList())))
        val refusedTemplate = withTemplate.seedingDemoDataIfEmpty(F.now)
        assertWithMessage("it refused").that(refusedTemplate).isEqualTo(withTemplate)
        assertThat(refusedTemplate.templates.map { it.name }).isEqualTo(listOf("Mine"))
        assertThat(refusedTemplate.history).isEmpty()

        val withHistory = StrengthData(history = listOf(F.workout(1, F.daysAgo(1.0))))
        val refusedHistory = withHistory.seedingDemoDataIfEmpty(F.now)
        assertWithMessage("it refused").that(refusedHistory).isEqualTo(withHistory)
        assertThat(refusedHistory.templates).isEmpty()
    }

    // endregion

    // region Exercise history

    private fun demoHistory(exerciseID: String, now: Instant = F.now): ExerciseHistory =
        StrengthData.demo(F.now).history(exerciseID, now)

    @Test
    fun testBenchHistoryOfTheDemo() {
        val history = demoHistory("bench")
        assertThat(history.exerciseID).isEqualTo("bench")
        assertThat(history.sessions.map { it.date }).isEqualTo(listOf(5.0, 10.0, 15.0).map { F.daysAgo(it) })
        assertThat(history.sessions.map { it.workoutName }).isEqualTo(List(3) { "Upper A · Push" })
        assertThat(history.sessions.map { it.isPersonalRecord }).isEqualTo(listOf(false, true, false))
        assertThat(history.sessions[1].sets.map { it.weightKg }).isEqualTo(listOf(50.0, 70.0, 80.0, 82.5, 85.0))
        assertThat(history.sessions[1].sets.map { it.type })
            .isEqualTo(listOf(SetType.WARMUP, SetType.WARMUP, SetType.NORMAL, SetType.NORMAL, SetType.NORMAL))
        assertWithMessage("oldest first").that(history.e1RMSeries.map { it.date }).isEqualTo(listOf(15.0, 10.0, 5.0).map { F.daysAgo(it) })
        val expectedSeries = listOf(93.0, 85 * (1 + 5.0 / 30), 96.0)
        assertThat(history.e1RMSeries).hasSize(3)
        for ((point, expected) in history.e1RMSeries.zip(expectedSeries)) assertThat(point.value).isWithin(1e-9).of(expected)
        assertThat(history.bestE1RM).isWithin(1e-9).of(85 * (1 + 5.0 / 30))
        assertThat(history.bestSetText).isEqualTo("85 kg × 5")
        assertThat(history.bestSetDate).isEqualTo(F.daysAgo(10.0))
    }

    @Test
    fun testThirtyDayTotalsAndTheirWindow() {
        val all = demoHistory("bench")
        val volume = 1360.0 + (480 + 412.5 + 425) + (3 * 77.5 * 6)
        assertThat(all.volumeLast30Days).isWithin(1e-9).of(volume)
        assertThat(all.sessionsLast30Days).isEqualTo(3)

        val later = demoHistory("bench", F.now.addingTimeInterval(21 * 86_400.0))     // only the 5 day old session (26 days) remains... 10 d = 31 d
        assertThat(later.sessionsLast30Days).isEqualTo(1)
        assertThat(later.volumeLast30Days).isWithin(1e-9).of(1360.0)
        assertWithMessage("the list keeps every session").that(later.sessions).hasSize(3)

        val muchLater = demoHistory("bench", F.now.addingTimeInterval(200 * 86_400.0))
        assertThat(muchLater.sessionsLast30Days).isEqualTo(0)
        assertThat(muchLater.volumeLast30Days).isEqualTo(0.0)
    }

    @Test
    fun testBenchRecordRows() {
        val history = demoHistory("bench")
        assertThat(history.records.map { it.id }).isEqualTo(listOf("e1rm", "bestSet", "repsAtWeight", "bestVolume"))
        assertThat(history.records.map { it.label })
            .isEqualTo(listOf("Estimated 1RM", "Best set", "Most reps at 80 kg", "Best session volume"))
        assertThat(history.records[0].value).isEqualTo("99 kg")
        assertThat(history.records[0].date).isEqualTo(F.daysAgo(10.0))
        assertThat(history.records[1].value).isEqualTo("85 kg × 5")
        assertThat(history.records[1].date).isEqualTo(F.daysAgo(10.0))
        assertThat(history.records[2].value).isEqualTo("6")
        assertWithMessage("the newest session that reached the maximum").that(history.records[2].date).isEqualTo(F.daysAgo(5.0))
        assertWithMessage("3 x 77.5 x 6 beats the two heavier but shorter sessions").that(history.records[3].value).isEqualTo("1,395 kg")
        assertThat(history.records[3].date).isEqualTo(F.daysAgo(15.0))
    }

    @Test
    fun testAnExerciseWithoutSessionsHasAnEmptyHistory() {
        val history = demoHistory("dips")
        assertThat(history.sessions).isEmpty()
        assertThat(history.e1RMSeries).isEmpty()
        assertThat(history.bestE1RM).isEqualTo(0.0)
        assertThat(history.bestSetText).isNull()
        assertThat(history.bestSetDate).isNull()
        assertThat(history.volumeLast30Days).isEqualTo(0.0)
        assertThat(history.sessionsLast30Days).isEqualTo(0)
        assertThat(history.records).isEmpty()
        assertThat(StrengthData().history("bench", F.now).sessions).hasSize(0)
    }

    @Test
    fun testAStoredPersonalBestBeyondTheHistoryIsShown() {
        var data = StrengthData.demo(F.now)
        data = data.copy(personalBests = data.personalBests + ("bench" to PersonalBest("bench", 120.0, 100.0, 6, F.daysAgo(100.0))))
        val history = data.history("bench", F.now)
        assertThat(history.bestE1RM).isEqualTo(120.0)
        assertThat(history.bestSetText).isEqualTo("100 kg × 6")
        assertThat(history.bestSetDate).isEqualTo(F.daysAgo(100.0))
        assertThat(history.records.firstOrNull()?.value).isEqualTo("120 kg")
    }

    @Test
    fun testBodyweightAndDurationRecords() {
        val data = StrengthData(
            history = listOf(
                F.workout(
                    1, F.daysAgo(2.0),
                    F.entry("pullup", listOf(F.work(0, 8), F.work(0, 9), F.work(0, 7)), n = 1), F.entry("plank", listOf(F.work(0, 45), F.work(0, 60)), n = 2),
                ),
                F.workout(
                    2, F.daysAgo(9.0),
                    F.entry("pullup", listOf(F.work(0, 10), F.work(0, 6)), n = 3), F.entry("plank", listOf(F.work(0, 50)), n = 4),
                ),
            ),
        )
        val pullups = data.history("pullup", F.now)
        assertThat(pullups.bestE1RM).isEqualTo(0.0)
        assertThat(pullups.bestSetText).isEqualTo("10 reps")
        assertThat(pullups.bestSetDate).isEqualTo(F.daysAgo(9.0))
        assertThat(pullups.records.map { it.id }).isEqualTo(listOf("mostReps", "bestSessionReps"))
        assertThat(pullups.records.map { it.value }).isEqualTo(listOf("10", "24"))
        assertThat(pullups.records.map { it.date }).isEqualTo(listOf(F.daysAgo(9.0), F.daysAgo(2.0)))
        assertThat(pullups.e1RMSeries).isEmpty()
        assertThat(pullups.volumeLast30Days).isEqualTo(0.0)
        assertThat(pullups.sessionsLast30Days).isEqualTo(2)

        val planks = data.history("plank", F.now)
        assertThat(planks.bestSetText).isEqualTo("60 s")
        assertThat(planks.records.map { it.id }).isEqualTo(listOf("longest", "bestSessionTime"))
        assertThat(planks.records.map { it.value }).isEqualTo(listOf("60 s", "1:45"))
    }

    @Test
    fun testTwoEntriesOfOneExerciseFormOneSession() {
        val data = StrengthData(
            history = listOf(
                F.workout(
                    1, F.daysAgo(2.0),
                    F.entry("bench", listOf(F.work(60, 10)), pr = false, n = 1), F.entry("bench", listOf(F.work(80, 5)), pr = true, n = 2),
                ),
            ),
        )
        val history = data.history("bench", F.now)
        assertThat(history.sessions).hasSize(1)
        assertThat(history.sessions[0].sets.map { it.weightKg }).isEqualTo(listOf(60.0, 80.0))
        assertThat(history.sessions[0].isPersonalRecord).isTrue()
        assertThat(history.e1RMSeries).hasSize(1)
    }

    @Test
    fun testSessionsWithTheSameDateKeepTheStoredOrder() {
        val `when` = F.daysAgo(1.0)
        val data = StrengthData(
            history = listOf(
                F.workout(1, `when`, F.entry("bench", listOf(F.work(60, 5)), n = 1), name = "First"),
                F.workout(2, `when`, F.entry("bench", listOf(F.work(61, 5)), n = 2), name = "Second"),
            ),
        )
        assertThat(data.history("bench", F.now).sessions.map { it.workoutName }).isEqualTo(listOf("First", "Second"))
    }

    // endregion
}

// region StrengthDataModel (data + files)

class StrengthDataModelTests {
    @get:Rule
    val folder = TemporaryFolder()

    private val F = SvcDataFix

    private fun makePersistence(): FileStrengthPersistence = FileStrengthPersistence(folder.newFolder())

    @Test
    fun testWithoutPersistenceEverythingStaysInMemory() {
        val model = StrengthDataModel(persistence = null, seedDemoData = true, now = F.now)
        assertThat(model.data.templates).hasSize(3)
        model.record(F.workout(1, F.daysAgo(0.1), F.entry("bench", listOf(F.work(100, 5)), n = 1)), null)
        assertThat(model.data.history).hasSize(6)
        model.reload()                                  // nothing to reload from
        assertThat(model.data.history).hasSize(6)
    }

    @Test
    fun testSeedingIsPersistedAndNotRepeated() {
        val persistence = makePersistence()
        val first = StrengthDataModel(persistence = persistence, seedDemoData = true, now = F.now).data
        assertThat(first.templates).hasSize(3)
        assertThat(persistence.loadTemplates()).isEqualTo(first.templates)
        assertThat(persistence.loadHistory()).isEqualTo(first.history)
        assertThat(persistence.loadPersonalBests()).isEqualTo(first.personalBests)

        val second = StrengthDataModel(persistence = persistence, seedDemoData = true, now = F.now.addingTimeInterval(86_400.0 * 3)).data
        assertWithMessage("an existing store is neither reseeded nor shifted").that(second).isEqualTo(first)
    }

    @Test
    fun testNoSeedingWithoutTheFlag() {
        val persistence = makePersistence()
        val data = StrengthDataModel(persistence = persistence, now = F.now).data
        assertThat(data.isEmpty).isTrue()
        assertThat(persistence.loadTemplates()).isEmpty()
    }

    @Test
    fun testRecordPersistsHistoryBestsAndTemplates() {
        val persistence = makePersistence()
        val model = StrengthDataModel(persistence = persistence, seedDemoData = true, now = F.now)
        val upper = model.data.templates[0]
        val workout = F.workout(50, F.daysAgo(0.1), F.entry("bench", listOf(F.work(90, 5)), n = 50), templateID = upper.id)
        val result = model.record(workout, null)
        assertThat(result.isSuccess).isTrue()

        assertThat(persistence.loadHistory().first()).isEqualTo(workout)
        assertThat(persistence.loadHistory()).hasSize(6)
        assertThat(persistence.loadPersonalBests()["bench"]?.estimated1RM ?: 0.0).isWithin(1e-9).of(105.0)
        assertThat(persistence.loadTemplates().first().lastPerformed).isEqualTo(F.daysAgo(0.1))
        assertThat(persistence.loadHistory()).isEqualTo(model.data.history)
        assertThat(model.lastPersistenceError).isNull()
    }

    @Test
    fun testTheExerciseOverlayRefreshesAfterRecording() {
        val model = StrengthDataModel(persistence = null, seedDemoData = true, now = F.now)
        assertThat(model.exercise("bench")?.previousBestE1RM ?: 0.0).isWithin(0.001).of(99.1667)
        assertThat(model.exercises.firstOrNull { it.id == "bench" }?.previousBestE1RM ?: 0.0).isWithin(0.001).of(99.1667)
        model.record(F.workout(60, F.daysAgo(0.1), F.entry("bench", listOf(F.work(100, 3)), n = 60)), null)
        assertThat(model.exercise("bench")?.previousBestE1RM ?: 0.0).isWithin(1e-9).of(110.0)
        assertThat(model.exercises.firstOrNull { it.id == "bench" }?.previousSets).isEqualTo(listOf(PreviousSet(100.0, 3)))
        assertThat(model.exercise("unknown")).isNull()
        assertThat(model.exercises).hasSize(36)
    }

    @Test
    fun testCustomExercisesAndTemplatesArePersisted() {
        val persistence = makePersistence()
        run {
            val model = StrengthDataModel(persistence = persistence)
            val curl = F.customExercise("Spider curl")
            model.addCustomExercise(curl)
            model.addCustomExercise(curl)                                      // duplicate: still one
            assertThat(persistence.loadCustomExercises()).isEqualTo(listOf(curl))
            assertThat(model.exercise(curl.id)?.name).isEqualTo("Spider curl")
            assertThat(model.exercises).hasSize(37)

            val template = WorkoutTemplate(id = SvcSyncFix.uuid(40), name = "Arms", entries = emptyList())
            model.saveTemplate(template)
            assertThat(persistence.loadTemplates()).isEqualTo(listOf(template))
            assertThat(model.template(template.id)).isEqualTo(template)
        }
        // A new model sees everything.
        run {
            val reopened = StrengthDataModel(persistence = persistence)
            assertThat(reopened.data.customExercises.map { it.name }).isEqualTo(listOf("Spider curl"))
            assertThat(reopened.data.templates.map { it.name }).isEqualTo(listOf("Arms"))
            assertThat(reopened.exercises).hasSize(37)
        }
    }

    @Test
    fun testReloadPicksUpChangesMadeElsewhere() {
        val persistence = makePersistence()
        val model = StrengthDataModel(persistence = persistence)
        assertThat(model.data.isEmpty).isTrue()
        persistence.saveTemplates(SampleData.templates())
        persistence.saveHistory(SampleData.history(F.now))
        persistence.savePersonalBests(SampleData.personalBests(F.now))
        persistence.saveCustomExercises(listOf(F.customExercise("Hex press")))
        model.reload()
        assertThat(model.data.templates).hasSize(3)
        assertThat(model.data.history).hasSize(5)
        assertThat(model.data.customExercises).hasSize(1)
        assertWithMessage("the cached exercise list is refreshed too").that(model.exercises).hasSize(37)
        assertThat(model.exercise("bench")?.previousBestE1RM ?: 0.0).isWithin(0.001).of(99.1667)
    }

    @Test
    fun testHistoryForAnExerciseDelegatesToTheData() {
        val model = StrengthDataModel(persistence = null, seedDemoData = true, now = F.now)
        assertThat(model.history("bench", F.now)).isEqualTo(model.data.history("bench", F.now))
        assertThat(model.history("bench", F.now).sessions).hasSize(3)
    }
}

// endregion

// region StrengthStore (Swift: the Combine wrapper; Kotlin: the StateFlow wrapper)

class StrengthStoreWrapperTests {
    @get:Rule
    val folder = TemporaryFolder()

    private val F = SvcDataFix

    private fun makePersistence(): FileStrengthPersistence = FileStrengthPersistence(folder.newFolder())

    @Test
    fun testAnEmptyStoreHasTheLibraryOnly() {
        val store = StrengthStore(persistence = null)
        assertThat(store.templates).isEmpty()
        assertThat(store.history).isEmpty()
        assertThat(store.customExercises).isEmpty()
        assertThat(store.personalBests).isEmpty()
        assertThat(store.exercises).isEqualTo(ExerciseLibrary.builtIn)
        assertThat(store.exercise("bench")).isEqualTo(ExerciseLibrary.exercise("bench"))
        assertThat(store.exercise("nope")).isNull()
        assertThat(store.data.value).isEqualTo(StrengthData())
    }

    @Test
    fun testSeedingFillsTemplatesHistoryAndBests() {
        val store = StrengthStore(persistence = null, seedDemoData = true)
        assertThat(store.templates.map { it.name }).isEqualTo(listOf("Upper A · Push", "Lower A · Quads", "Upper B · Pull"))
        assertThat(store.history).hasSize(5)
        assertThat(store.history.map { it.finishedAt }).isEqualTo(store.history.map { it.finishedAt }.sortedDescending())
        assertThat(store.personalBests["bench"]?.weightKg).isEqualTo(85.0)
        assertThat(store.exercise("bench")?.previousBestE1RM ?: 0.0).isWithin(0.001).of(99.1667)
        assertThat(store.history("bench", F.now).sessions.size).isEqualTo(3)
        assertWithMessage("the published data is the seeded data").that(store.data.value.templates).isEqualTo(store.templates)
    }

    @Test
    fun testSeedingHappensOnlyOnceWithPersistence() {
        val persistence = makePersistence()
        val first = StrengthStore(persistence = persistence, seedDemoData = true).history.map { it.id }
        val second = StrengthStore(persistence = persistence, seedDemoData = true).history.map { it.id }
        assertThat(first).hasSize(5)
        assertThat(first).isEqualTo(second)
        assertThat(persistence.loadHistory().map { it.id }).isEqualTo(first)
    }

    @Test
    fun testChangesAreVisibleThroughThePublishedValuesAndPersisted() {
        val persistence = makePersistence()
        val store = StrengthStore(persistence = persistence)
        val curl = F.customExercise("Cable curl")
        store.addCustomExercise(curl)
        assertThat(store.customExercises).isEqualTo(listOf(curl.copy(isCustom = true)))
        assertThat(store.data.value.customExercises).isEqualTo(store.customExercises)
        assertThat(store.exercises).hasSize(37)
        assertThat(store.exercise(curl.id)).isEqualTo(curl.copy(isCustom = true))

        val template = WorkoutTemplate(id = SvcSyncFix.uuid(90), name = "Arms", entries = emptyList())
        store.saveTemplate(template)
        assertThat(store.templates).isEqualTo(listOf(template))
        assertThat(store.data.value.templates).isEqualTo(listOf(template))

        val workout = F.workout(91, F.now, F.entry("bench", listOf(F.work(100, 5)), n = 91), templateID = template.id)
        val result = store.record(workout, null)
        assertThat(result.isSuccess).isTrue()
        assertThat(store.history).isEqualTo(listOf(workout))
        assertThat(store.data.value.history).isEqualTo(listOf(workout))
        assertThat(store.personalBests["bench"]?.weightKg).isEqualTo(100.0)
        assertThat(store.templates[0].lastPerformed).isEqualTo(workout.finishedAt)
        assertThat(store.exercise("bench")?.previousSets).isEqualTo(listOf(PreviousSet(100.0, 5)))
        assertThat(store.lastPersistenceError).isNull()

        assertThat(persistence.loadCustomExercises()).hasSize(1)
        assertThat(persistence.loadTemplates()).hasSize(1)
        assertThat(persistence.loadHistory()).hasSize(1)
        assertThat(persistence.loadPersonalBests()).hasSize(1)
    }

    @Test
    fun testReloadReadsWhatWasWrittenElsewhere() {
        val persistence = makePersistence()
        val store = StrengthStore(persistence = persistence)
        assertThat(store.templates).isEmpty()
        persistence.saveTemplates(SampleData.templates())
        persistence.saveHistory(SampleData.history(F.now))
        persistence.savePersonalBests(SampleData.personalBests(F.now))
        persistence.saveCustomExercises(listOf(F.customExercise("Hex press")))
        store.reload()
        assertThat(store.templates).hasSize(3)
        assertThat(store.history).hasSize(5)
        assertThat(store.customExercises).hasSize(1)
        assertThat(store.personalBests).isNotEmpty()
        assertThat(store.exercises).hasSize(37)
        assertWithMessage("the published data follows the reload").that(store.data.value.templates).hasSize(3)
    }

    /** Swift: `testObjectWillChangeFiresOnlyWhenSomethingChanges` (Combine only). Kotlin: the `data` StateFlow. */
    @OptIn(ExperimentalCoroutinesApi::class)
    @Test
    fun testTheDataFlowEmitsOnlyWhenSomethingChanges() = runTest {
        val store = StrengthStore(persistence = null)
        val emissions = mutableListOf<StrengthData>()
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { store.data.collect { emissions.add(it) } }
        assertWithMessage("the current value is delivered to a new collector").that(emissions).hasSize(1)
        store.reload()
        assertWithMessage("nothing changed").that(emissions).hasSize(1)
        store.saveTemplate(WorkoutTemplate(name = "Arms", entries = emptyList()))
        assertThat(emissions).hasSize(2)
        assertThat(emissions.last().templates.map { it.name }).isEqualTo(listOf("Arms"))
        store.addCustomExercise(ExerciseLibrary.exercise("bench")!!)       // a built-in id is ignored: nothing changes
        assertThat(emissions).hasSize(2)
    }

    /** A reload that reads the same data back publishes nothing new (the data is an equal value). */
    @OptIn(ExperimentalCoroutinesApi::class)
    @Test
    fun testReloadOfUnchangedFilesPublishesNothing() = runTest {
        val persistence = makePersistence()
        val store = StrengthStore(persistence = persistence, seedDemoData = true, now = F.now)
        val emissions = mutableListOf<StrengthData>()
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { store.data.collect { emissions.add(it) } }
        assertThat(emissions).hasSize(1)
        store.reload()
        assertThat(emissions).hasSize(1)
        persistence.saveTemplates(emptyList())
        store.reload()
        assertThat(emissions).hasSize(2)
        assertThat(emissions.last().templates).isEmpty()
    }
}

// endregion
