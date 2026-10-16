package health.pulse.strength.core

import com.google.common.truth.Truth.assertThat
import com.google.common.truth.Truth.assertWithMessage
import health.pulse.strength.core.StrengthDataTests.SvcSyncFix
import java.time.Instant
import org.junit.Test

// Port of SampleDataTests.swift.

class SampleDataTests {
    private val now = SvcSyncFix.epoch
    private val day = 86_400.0

    private fun daysAgo(days: Int): Instant = now.addingTimeInterval(-days.toDouble() * day)

    private fun template(name: String): WorkoutTemplate =
        requireNotNull(SampleData.templates().firstOrNull { it.name == name }) { name }

    private fun workout(days: Int): CompletedWorkout =
        requireNotNull(SampleData.history(now).firstOrNull { it.finishedAt == daysAgo(days) }) { "no workout $days days ago" }

    private fun sets(workout: CompletedWorkout, exerciseID: String): List<CompletedSet> =
        requireNotNull(workout.exercises.firstOrNull { it.exerciseID == exerciseID }) { exerciseID }.sets

    // region Templates

    @Test
    fun testThreeTemplatesInTheDesignOrder() {
        assertThat(SampleData.templates().map { it.name }).isEqualTo(listOf("Upper A · Push", "Lower A · Quads", "Upper B · Pull"))
        assertThat(SampleData.templates().map { it.entries.size }).isEqualTo(listOf(6, 5, 6))
    }

    @Test
    fun testUpperAIsTheWorkoutOfTheDesign() {
        val upper = template("Upper A · Push")
        assertThat(upper.entries.map { it.exercise.id }).isEqualTo(listOf("bench", "incline", "ohp", "lateral", "pushdown", "crossover"))
        assertThat(upper.entries.map { it.restSeconds }).isEqualTo(listOf(150, 90, 120, 60, 60, 60))
        assertThat(upper.entries.map { it.supersetGroup }).isEqualTo(listOf(null, null, null, "A", "A", null))

        val bench = upper.entries[0].plannedSets
        assertThat(bench).isEqualTo(
            listOf(
                PlannedSet(type = SetType.WARMUP, weightKg = 50.0, reps = 8), PlannedSet(type = SetType.WARMUP, weightKg = 70.0, reps = 5),
                PlannedSet(type = SetType.NORMAL, weightKg = 82.5, reps = 6), PlannedSet(type = SetType.NORMAL, weightKg = 82.5, reps = 6),
                PlannedSet(type = SetType.NORMAL, weightKg = 85.0, reps = 6),
            ),
        )
        fun straight(count: Int, kg: Double, reps: Int): List<PlannedSet> = List(count) { PlannedSet(type = SetType.NORMAL, weightKg = kg, reps = reps) }
        assertThat(upper.entries[1].plannedSets).isEqualTo(straight(3, 28.0, 10))
        assertThat(upper.entries[2].plannedSets).isEqualTo(straight(3, 45.0, 8))
        assertThat(upper.entries[3].plannedSets).isEqualTo(straight(3, 8.0, 15))
        assertThat(upper.entries[4].plannedSets).isEqualTo(straight(3, 30.0, 12))
        assertThat(upper.entries[5].plannedSets).isEqualTo(straight(3, 15.0, 12))
        assertThat(upper.entries.flatMap { it.plannedSets }).hasSize(20)
    }

    @Test
    fun testOtherTemplatesHaveTheExpectedExercises() {
        assertThat(template("Lower A · Quads").entries.map { it.exercise.id }).isEqualTo(listOf("squat", "legpress", "lunge", "legext", "calf"))
        assertThat(template("Upper B · Pull").entries.map { it.exercise.id }).isEqualTo(listOf("pullup", "brow", "pulldown", "crow", "facepull", "curl"))
    }

    @Test
    fun testEveryTemplateExerciseIsTheLibraryExercise() {
        for (template in SampleData.templates()) {
            for (entry in template.entries) {
                assertWithMessage(entry.exercise.id).that(entry.exercise).isEqualTo(ExerciseLibrary.exercise(entry.exercise.id))
                assertThat(entry.plannedSets).isNotEmpty()
                assertThat(entry.restSeconds).isGreaterThan(0)
            }
        }
    }

    @Test
    fun testSupersetsHaveAtLeastTwoMembers() {
        for (template in SampleData.templates()) {
            val counts = mutableMapOf<String, Int>()
            for (entry in template.entries) entry.supersetGroup?.let { counts[it] = (counts[it] ?: 0) + 1 }
            for ((group, count) in counts) assertWithMessage(group).that(count).isAtLeast(2)
        }
    }

    @Test
    fun testTemplatesHaveStableIdsAndNeverBeenPerformedWithoutNow() {
        assertThat(SampleData.templates()).isEqualTo(SampleData.templates())
        assertThat(SampleData.templates().all { it.lastPerformed == null }).isTrue()
        val ids = SampleData.templates().flatMap { listOf(it.id) + it.entries.map { entry -> entry.id } }
        assertThat(ids.toSet()).hasSize(ids.size)
    }

    @Test
    fun testTemplatesPlanARealisticDuration() {
        for (template in SampleData.templates()) {
            assertWithMessage(template.name).that(template.estimatedMinutes).isAtLeast(30)
            assertWithMessage(template.name).that(template.estimatedMinutes).isAtMost(90)
        }
    }

    @Test
    fun testLastPerformedFollowsTheHistory() {
        val templates = SampleData.templates(now)
        assertThat(templates.map { it.name }).isEqualTo(listOf("Upper A · Push", "Lower A · Quads", "Upper B · Pull"))
        assertThat(templates[0].lastPerformed).isEqualTo(daysAgo(5))
        assertThat(templates[1].lastPerformed).isEqualTo(daysAgo(7))
        assertThat(templates[2].lastPerformed).isEqualTo(daysAgo(3))
        assertThat(templates.map { it.id }).isEqualTo(SampleData.templates().map { it.id })
        assertThat(templates.map { it.entries }).isEqualTo(SampleData.templates().map { it.entries })
    }

    // endregion

    // region History

    @Test
    fun testHistoryIsNewestFirstWithTheDemoTimeline() {
        val history = SampleData.history(now)
        assertThat(history.map { it.name })
            .isEqualTo(listOf("Upper B · Pull", "Upper A · Push", "Lower A · Quads", "Upper A · Push", "Upper A · Push"))
        assertThat(history.map { it.finishedAt }).isEqualTo(listOf(3, 5, 7, 10, 15).map { daysAgo(it) })
        assertThat(history.map { it.templateID }).isEqualTo(listOf(3, 1, 2, 1, 1).map { SampleData.templates()[it - 1].id })
        for (workout in history) {
            assertThat(workout.finishedAt.timeIntervalSince(workout.startedAt)).isWithin(0.001).of(workout.durationSeconds.toDouble())
            assertThat(workout.durationSeconds).isGreaterThan(30 * 60)
            assertThat(workout.finishedAt).isLessThan(now)
        }
    }

    @Test
    fun testBenchSessionsMatchTheDesign() {
        fun warmup(kg: Double, reps: Int): List<Double> = listOf(1.0, kg, reps.toDouble())
        fun shape(sets: List<CompletedSet>): List<List<Double>> =
            sets.map { listOf(if (it.type == SetType.WARMUP) 1.0 else 0.0, it.weightKg, it.reps.toDouble()) }
        assertThat(shape(sets(workout(5), "bench")))
            .isEqualTo(listOf(warmup(50.0, 8), warmup(70.0, 5), listOf(0.0, 80.0, 6.0), listOf(0.0, 80.0, 6.0), listOf(0.0, 80.0, 5.0)))
        assertThat(shape(sets(workout(10), "bench")))
            .isEqualTo(listOf(warmup(50.0, 8), warmup(70.0, 5), listOf(0.0, 80.0, 6.0), listOf(0.0, 82.5, 5.0), listOf(0.0, 85.0, 5.0)))
        assertThat(shape(sets(workout(15), "bench")))
            .isEqualTo(listOf(warmup(50.0, 8), listOf(0.0, 77.5, 6.0), listOf(0.0, 77.5, 6.0), listOf(0.0, 77.5, 6.0)))
    }

    @Test
    fun testOnlyTheTenDayBenchSessionIsAPersonalRecord() {
        for (workout in SampleData.history(now)) {
            val flagged = workout.exercises.filter { it.isPersonalRecord }.map { it.exerciseID }
            assertWithMessage(workout.name).that(flagged).isEqualTo(if (workout.finishedAt == daysAgo(10)) listOf("bench") else emptyList<String>())
            assertThat(workout.personalRecords.map { it.exerciseID }).isEqualTo(flagged)
        }
        val record = workout(10).personalRecords.first()
        assertThat(record.exerciseName).isEqualTo("Barbell bench press")
        assertThat(record.weightKg).isEqualTo(85.0)
        assertThat(record.reps).isEqualTo(5)
        assertThat(record.estimated1RM).isWithin(0.001).of(99.1667)
        assertThat(record.estimated1RM.roundedAwayFromZero()).isEqualTo(99.0)
        assertThat(record.previousBest).isGreaterThan(0.0)
        assertThat(record.previousBest).isLessThan(record.estimated1RM)
    }

    @Test
    fun testEntryFlagsAgreeWithTheEstimates() {
        for (workout in SampleData.history(now)) {
            for (entry in workout.exercises) {
                val computed = entry.sets.filter { it.type != SetType.WARMUP }
                    .maxOfOrNull { Estimated1RM.epley(it.weightKg, it.reps) } ?: 0.0
                val expected = if (entry.tracking == TrackingKind.WEIGHT_REPS) computed else 0.0
                assertWithMessage(entry.name).that(entry.bestE1RM).isWithin(1e-9).of(expected)
                assertThat(entry.sets).isNotEmpty()
            }
        }
    }

    @Test
    fun testTotalsAreConsistentWithTheSets() {
        for (workout in SampleData.history(now)) {
            var volume = 0.0
            var logged = 0
            val rir = mutableListOf<Int>()
            val muscles = mutableMapOf<MuscleGroup, Int>()
            for (entry in workout.exercises) {
                logged += entry.sets.size
                rir += entry.sets.mapNotNull { it.rir }
                for (set in entry.sets.filter { it.type != SetType.WARMUP }) {
                    if (entry.tracking == TrackingKind.WEIGHT_REPS) volume += set.weightKg * set.reps.toDouble()
                    muscles[entry.muscle] = (muscles[entry.muscle] ?: 0) + 1
                }
            }
            assertWithMessage(workout.name).that(workout.volumeKg).isWithin(1e-9).of(volume)
            assertWithMessage(workout.name).that(workout.loggedSets).isEqualTo(logged)
            assertThat(workout.muscleSets.sumOf { it.sets }).isEqualTo(muscles.values.sum())
            assertThat(workout.muscleSets.all { it.sets > 0 }).isTrue()
            assertThat(workout.muscleSets).isEqualTo(
                workout.muscleSets.sortedWith { lhs, rhs ->
                    if (lhs.sets != rhs.sets) rhs.sets.compareTo(lhs.sets) else lhs.muscle.rawValue.compareTo(rhs.muscle.rawValue)
                },
            )
            for (item in workout.muscleSets) assertThat(muscles[item.muscle]).isEqualTo(item.sets)
            if (rir.isEmpty()) {
                assertThat(workout.averageRIR).isNull()
            } else {
                assertThat(workout.averageRIR!!).isWithin(1e-9).of(rir.sum().toDouble() / rir.size.toDouble())
            }
        }
    }

    @Test
    fun testUpperADayFiveNumbers() {
        val workout = workout(5)
        assertThat(workout.loggedSets).isEqualTo(20)
        assertThat(workout.volumeKg).isWithin(1e-9).of(5076.0)
        assertThat(workout.muscleSets.map { it.muscle }).isEqualTo(listOf(MuscleGroup.CHEST, MuscleGroup.SHOULDERS, MuscleGroup.ARMS))
        assertThat(workout.muscleSets.map { it.sets }).isEqualTo(listOf(9, 6, 3))
        assertThat(workout.averageRIR ?: 0.0).isWithin(1e-9).of(2.0)
        assertThat(workout.averageHeartRate).isEqualTo(126)
    }

    @Test
    fun testAWorkoutWithoutWatchDataHasNoHeartRate() {
        assertThat(workout(15).averageHeartRate).isNull()
        assertThat(workout(15).averageRIR).isNull()
    }

    @Test
    fun testEveryWorkoutFollowsItsTemplate() {
        for (workout in SampleData.history(now)) {
            val template = requireNotNull(SampleData.templates().firstOrNull { it.id == workout.templateID })
            assertWithMessage(workout.name).that(workout.exercises.map { it.exerciseID }).isEqualTo(template.entries.map { it.exercise.id })
            for (entry in workout.exercises) {
                val library = requireNotNull(ExerciseLibrary.exercise(entry.exerciseID))
                assertThat(entry.name).isEqualTo(library.name)
                assertThat(entry.muscle).isEqualTo(library.muscle)
                assertThat(entry.mediaKey).isEqualTo(library.mediaKey)
                assertThat(entry.tracking).isEqualTo(library.tracking)
            }
        }
    }

    @Test
    fun testHistoryIsDeterministicAndMovesWithNow() {
        assertThat(SampleData.history(now)).isEqualTo(SampleData.history(now))
        val later = SampleData.history(now.addingTimeInterval(10 * day))
        val original = SampleData.history(now)
        assertThat(later).hasSize(original.size)
        for ((a, b) in later.zip(original)) {
            assertThat(a.id).isEqualTo(b.id)
            assertThat(a.finishedAt.timeIntervalSince(b.finishedAt)).isWithin(0.001).of(10 * day)
            assertThat(a.exercises).isEqualTo(b.exercises)
        }
    }

    @Test
    fun testIdsAreUniqueAcrossTheHistory() {
        val history = SampleData.history(now)
        val ids = history.map { it.id } + history.flatMap { workout -> workout.exercises.map { it.id } }
        assertThat(ids.toSet()).hasSize(ids.size)
        val templateIDs = SampleData.templates().flatMap { listOf(it.id) + it.entries.map { entry -> entry.id } }.toSet()
        assertThat(ids.toSet().intersect(templateIDs)).isEmpty()
    }

    // endregion

    // region Personal bests

    @Test
    fun testBenchPersonalBestIsTheTenDayRecord() {
        val best = requireNotNull(SampleData.personalBests(now)["bench"])
        assertThat(best.exerciseID).isEqualTo("bench")
        assertThat(best.weightKg).isEqualTo(85.0)
        assertThat(best.reps).isEqualTo(5)
        assertThat(best.estimated1RM).isWithin(0.001).of(99.1667)
        assertThat(best.date).isEqualTo(daysAgo(10))
    }

    @Test
    fun testBestsAreTheMaximaOfTheHistory() {
        val history = SampleData.history(now)
        val bests = SampleData.personalBests(now)
        val maxima = mutableMapOf<String, Double>()
        for (workout in history) for (entry in workout.exercises) maxima[entry.exerciseID] = maxOf(maxima[entry.exerciseID] ?: 0.0, entry.bestE1RM)
        val expectedIDs = maxima.filter { it.value > 0 }.keys
        assertThat(bests.keys).isEqualTo(expectedIDs)
        for ((id, best) in bests) {
            assertWithMessage(id).that(best.estimated1RM).isWithin(1e-9).of(maxima[id] ?: -1.0)
            assertThat(best.exerciseID).isEqualTo(id)
            assertWithMessage(id).that(Estimated1RM.epley(best.weightKg, best.reps)).isWithin(1e-9).of(best.estimated1RM)
            assertWithMessage(id).that(history.any { it.finishedAt == best.date }).isTrue()
        }
        assertWithMessage("bodyweight exercises have no e1RM").that(bests["pullup"]).isNull()
    }

    @Test
    fun testBestsMatchTheLibraryValuesOfTheDesignExercises() {
        val bests = SampleData.personalBests(now)
        for (id in listOf("bench", "incline", "ohp", "lateral", "pushdown", "crossover")) {
            val library = requireNotNull(ExerciseLibrary.exercise(id)).previousBestE1RM
            assertThat(library).isGreaterThan(0.0)
            assertWithMessage(id).that(requireNotNull(bests[id]).estimated1RM).isWithin(0.5).of(library)
        }
    }

    // endregion

    // region Overlay

    @Test
    fun testSeededDataReproducesThePreviousSetsOfTheDesign() {
        val data = StrengthData.demo(now)
        for (id in listOf("bench", "incline", "ohp", "lateral", "pushdown", "crossover")) {
            val library = requireNotNull(ExerciseLibrary.exercise(id))
            assertWithMessage(id).that(requireNotNull(data.exercise(id)).previousSets).isEqualTo(library.previousSets)
        }
    }

    @Test
    fun testDemoDataBundlesTheSamples() {
        val data = StrengthData.demo(now)
        assertThat(data.templates).isEqualTo(SampleData.templates(now))
        assertThat(data.history).isEqualTo(SampleData.history(now))
        assertThat(data.personalBests).isEqualTo(SampleData.personalBests(now))
        assertThat(data.customExercises).isEmpty()
        assertThat(data.isEmpty).isFalse()
    }

    @Test
    fun testTheDesignWorkoutCanBeStartedFromTheSampleTemplate() {
        val upper = SampleData.templates(now)[0]
        val state = WorkoutFactory.makeWorkout(upper, now)
        assertThat(state.exercises).hasSize(6)
        assertThat(state.exercises.flatMap { it.sets }).hasSize(20)
        assertThat(state.exercises.map { it.supersetGroup }).isEqualTo(listOf(null, null, null, "A", "A", null))
        assertThat(state.exercises[0].sets.map { it.type })
            .isEqualTo(listOf(SetType.WARMUP, SetType.WARMUP, SetType.NORMAL, SetType.NORMAL, SetType.NORMAL))
    }

    // endregion
}
