package health.pulse.strength.core.widgets

import com.google.common.truth.Truth.assertThat
import com.google.common.truth.Truth.assertWithMessage
import health.pulse.strength.core.CompletedSet
import health.pulse.strength.core.CompletedWorkout
import health.pulse.strength.core.ExerciseLibrary
import health.pulse.strength.core.MuscleGroup
import health.pulse.strength.core.PlannedSet
import health.pulse.strength.core.SetType
import health.pulse.strength.core.StrengthData
import health.pulse.strength.core.TemplateEntry
import health.pulse.strength.core.WorkoutTemplate
import health.pulse.strength.core.addingTimeInterval
import java.time.Instant
import org.junit.Test

/**
 * widgets/SPEC.md section 2: nextUp, templates, the exercise summary, overload, formCue and loadedBar. The Android store has no training
 * plans and `PlannedSet` has no rep range: the next workout is always the rotation and the rep rules read the planned reps.
 */
class WidgetNextUpRuleTests {
    private fun threeTemplates(performed: List<Instant?>): List<WorkoutTemplate> = listOf(
        WidFix.template(1, "Upper A · Push", listOf(WidFix.entry("bench", WidFix.planned(3, 80.0, 6))), last = performed[0]),
        WidFix.template(2, "Lower A · Quads", listOf(WidFix.entry("squat", WidFix.planned(3, 100.0, 5))), last = performed[1]),
        WidFix.template(3, "Upper B · Pull", listOf(WidFix.entry("brow", WidFix.planned(3, 60.0, 8))), last = performed[2]),
    )

    private fun next(templates: List<WorkoutTemplate>): NextUpSummary? = WidFix.snapshot(StrengthData(templates = templates)).nextUp

    private fun daysAgo(offset: Double): Instant = WidFix.now.addingTimeInterval(-offset * 86_400)

    // region nextUp

    @Test
    fun testNextUpIsTheTemplateAfterTheMostRecentlyPerformedOneInStoreOrder() {
        assertWithMessage("after Upper B (the newest) comes Upper A: wrapping")
            .that(next(threeTemplates(listOf(daysAgo(5.0), daysAgo(7.0), daysAgo(3.0))))?.name).isEqualTo("Upper A · Push")
        assertWithMessage("after Lower A comes Upper B")
            .that(next(threeTemplates(listOf(daysAgo(5.0), daysAgo(2.0), daysAgo(3.0))))?.name).isEqualTo("Upper B · Pull")
        assertThat(next(threeTemplates(listOf(daysAgo(1.0), daysAgo(2.0), daysAgo(3.0))))?.name).isEqualTo("Lower A · Quads")
    }

    @Test
    fun testNextUpWithNothingPerformedIsTheFirstTemplate() {
        assertThat(next(threeTemplates(listOf(null, null, null)))?.name).isEqualTo("Upper A · Push")
        val summary = next(threeTemplates(listOf(null, null, null)))
        assertThat(summary?.lastPerformedAt).isNull()
        assertThat(summary?.daysSince).isNull()
    }

    @Test
    fun testNextUpTakesTheLowestIndexOnATieOfTheMostRecentlyPerformed() {
        val same = WidFix.now.addingTimeInterval(-86_400.0)
        assertWithMessage("Lower A (index 1) is the latest one, so Upper B comes next")
            .that(next(threeTemplates(listOf(null, same, same)))?.name).isEqualTo("Upper B · Pull")
    }

    @Test
    fun testNextUpOfASingleTemplateIsThatTemplate() {
        val only = WidFix.template(1, "Full Body", listOf(WidFix.entry("bench", WidFix.planned(3, 60.0, 8))), last = WidFix.now.addingTimeInterval(-86_400.0))
        val snapshot = WidFix.snapshot(StrengthData(templates = listOf(only)))
        assertThat(snapshot.nextUp?.templateID).isEqualTo(only.id.toString())
        assertThat(snapshot.templates.map { it.isSuggested }).containsExactly(true)
    }

    @Test
    fun testNoTemplatesMeansNoNextUpAndAnEmptyLauncher() {
        val snapshot = WidFix.snapshot(StrengthData())
        assertThat(snapshot.nextUp).isNull()
        assertThat(snapshot.templates).isEmpty()
        assertThat(snapshot.overload).isNull()
        assertThat(snapshot.formCue).isNull()
        assertThat(snapshot.loadedBar).isNull()
        assertThat(snapshot.tomorrow).isNull()
    }

    @Test
    fun testNextUpDescribesTheTemplate() {
        val template = WidFix.template(
            1, "Upper A · Push",
            listOf(
                WidFix.entry("bench", listOf(PlannedSet(type = SetType.WARMUP, weightKg = 50.0, reps = 8)) + WidFix.planned(3, 85.0, 5), rest = 150),
                WidFix.entry("lateral", WidFix.planned(3, 8.0, 15), rest = 60),
            ),
            last = WidFix.date(2026, 10, 11, 20, 0),
        )
        val summary = next(listOf(template))!!
        assertThat(summary.templateID).isEqualTo(template.id.toString())
        assertThat(summary.name).isEqualTo("Upper A · Push")
        assertThat(summary.splitLabel).isEqualTo("Push day")
        assertThat(summary.exerciseCount).isEqualTo(2)
        assertWithMessage("every planned set, warm-ups included").that(summary.setCount).isEqualTo(7)
        assertThat(summary.estimatedMinutes).isEqualTo(template.estimatedMinutes)
        assertThat(summary.lastPerformedAt).isEqualTo(WidFix.date(2026, 10, 11, 20, 0))
        assertThat(summary.daysSince).isEqualTo(5)
        assertThat(summary.exercises.map { it.exerciseID }).containsExactly("bench", "lateral").inOrder()
        assertThat(summary.exercises.map { it.name }).containsExactly("Barbell bench press", "Dumbbell lateral raise").inOrder()
        assertThat(summary.exercises.map { it.muscle }).containsExactly(MuscleGroup.CHEST, MuscleGroup.SHOULDERS).inOrder()
        assertWithMessage("all planned sets including warm-ups").that(summary.exercises.map { it.setCount }).containsExactly(4, 3).inOrder()
        assertThat(summary.exercises.map { it.summary }).containsExactly("3 × 85", "3 × 8").inOrder()
        assertWithMessage("the Android store has no training plans").that(summary.planName).isNull()
        assertThat(summary.planPosition).isNull()
        assertThat(summary.planCount).isNull()
    }

    @Test
    fun testNextUpDaysSinceCountsCalendarDays() {
        val template = WidFix.template(1, "Legs", emptyList(), last = WidFix.date(2026, 10, 15, 23, 50))
        assertWithMessage("23:50 yesterday is 1 day ago").that(next(listOf(template))?.daysSince).isEqualTo(1)
    }

    // endregion

    // region templates

    @Test
    fun testTemplatesKeepStoreOrderAndMarkTheSuggestedOne() {
        val templates = threeTemplates(listOf(WidFix.now.addingTimeInterval(-5 * 86_400.0), null, WidFix.date(2026, 10, 13, 9, 41)))
        val list = WidFix.snapshot(StrengthData(templates = templates)).templates
        assertThat(list.map { it.name }).containsExactly("Upper A · Push", "Lower A · Quads", "Upper B · Pull").inOrder()
        assertWithMessage("after Upper B comes Upper A").that(list.map { it.isSuggested }).containsExactly(true, false, false).inOrder()
        assertThat(list.map { it.templateID }).isEqualTo(templates.map { it.id.toString() })
        assertThat(list.map { it.exerciseCount }).containsExactly(1, 1, 1).inOrder()
        assertThat(list.map { it.estimatedMinutes }).isEqualTo(templates.map { it.estimatedMinutes })
        assertWithMessage("a template that was never performed has no days").that(list.map { it.daysSince }).containsExactly(5, null, 3).inOrder()
        assertThat(list.map { it.lastPerformedAt }).isEqualTo(templates.map { it.lastPerformed })
    }

    @Test
    fun testTemplatesNeverPerformedHaveNoLastPerformed() {
        val list = WidFix.snapshot(StrengthData(templates = threeTemplates(listOf(null, null, null)))).templates
        assertThat(list.all { it.lastPerformedAt == null && it.daysSince == null }).isTrue()
        assertThat(list.map { it.isSuggested }).containsExactly(true, false, false).inOrder()
    }

    // endregion

    // region Exercise summary

    private fun summary(exerciseID: String, sets: List<PlannedSet>): String = WidgetTemplates.summary(WidFix.entry(exerciseID, sets))

    @Test
    fun testExerciseSummaryOfAWeightExerciseIsTheWorkingSetsTimesTheHeaviestWorkingWeight() {
        assertWithMessage("a heavier warm-up does not count")
            .that(summary("bench", listOf(PlannedSet(type = SetType.WARMUP, weightKg = 100.0, reps = 3)) + WidFix.planned(3, 85.0, 5))).isEqualTo("3 × 85")
        assertThat(summary("bench", listOf(PlannedSet(weightKg = 80.0, reps = 6), PlannedSet(weightKg = 82.5, reps = 5), PlannedSet(weightKg = 77.5, reps = 8))))
            .isEqualTo("3 × 82.5")
        assertThat(summary("bench", listOf(PlannedSet(type = SetType.DROP, weightKg = 60.0, reps = 10), PlannedSet(type = SetType.FAILURE, weightKg = 70.0, reps = 6))))
            .isEqualTo("2 × 70")
    }

    @Test
    fun testExerciseSummaryCountsAllSetsWhenThereAreOnlyWarmUps() {
        assertThat(summary("bench", listOf(PlannedSet(type = SetType.WARMUP, weightKg = 40.0, reps = 8), PlannedSet(type = SetType.WARMUP, weightKg = 50.0, reps = 5))))
            .isEqualTo("2 × 50")
        assertThat(summary("bench", emptyList())).isEqualTo("0 × 0")
    }

    @Test
    fun testExerciseSummaryOfARepsOnlyExerciseIsTheSetsTimesTheMostReps() {
        assertThat(summary("pushup", listOf(PlannedSet(weightKg = 0.0, reps = 12), PlannedSet(weightKg = 0.0, reps = 10), PlannedSet(weightKg = 0.0, reps = 8))))
            .isEqualTo("3 × 12")
        assertThat(summary("pullup", WidFix.planned(4, 0.0, 6))).isEqualTo("4 × 6")
    }

    @Test
    fun testExerciseSummaryOfADurationExerciseIsTheSetsTimesTheLongestTime() {
        assertThat(summary("plank", listOf(PlannedSet(weightKg = 0.0, reps = 30), PlannedSet(weightKg = 0.0, reps = 45), PlannedSet(weightKg = 0.0, reps = 40))))
            .isEqualTo("3 × 45 s")
    }

    // endregion
}

class WidgetOverloadRuleTests {
    private fun overload(entries: List<TemplateEntry>, history: List<CompletedWorkout>, extraTemplates: List<WorkoutTemplate> = emptyList()): OverloadTarget? {
        val template = WidFix.template(1, "Upper A · Push", entries)
        return WidFix.snapshot(StrengthData(templates = listOf(template) + extraTemplates, history = history)).overload
    }

    private fun benchHistory(sets: List<CompletedSet>, daysAgo: Double = 5.0, n: Int = 1): List<CompletedWorkout> =
        listOf(WidFix.workout(n, "Upper A · Push", daysAgo = daysAgo).withExercises(listOf(WidFix.lift("bench", sets, n = n))))

    @Test
    fun testOverloadAddsTheWeightStepWhenLastTimeReachedThePlannedReps() {
        val target = overload(
            listOf(WidFix.entry("bench", WidFix.planned(4, 82.5, 6))),
            benchHistory(listOf(WidFix.set(80.0, 6), WidFix.set(80.0, 6), WidFix.set(80.0, 5))),
        )!!
        assertThat(target.exerciseID).isEqualTo("bench")
        assertThat(target.exerciseName).isEqualTo("Barbell bench press")
        assertThat(target.lastWeightKg).isEqualTo(80.0)
        assertThat(target.lastReps).isEqualTo(6)
        assertThat(target.lastDaysAgo).isEqualTo(5)
        assertWithMessage("the barbell step is 2.5 kg").that(target.targetWeightKg).isEqualTo(82.5)
        assertThat(target.targetReps).isEqualTo(6)
        assertWithMessage("the planned working sets").that(target.targetSets).isEqualTo(4)
        assertThat(target.deltaKg).isEqualTo(2.5)
    }

    @Test
    fun testOverloadUsesTheExercisesOwnWeightStep() {
        val dumbbell = overload(
            listOf(WidFix.entry("incline", WidFix.planned(3, 28.0, 10))),
            listOf(WidFix.workout(1, daysAgo = 3.0).withExercises(listOf(WidFix.lift("incline", listOf(WidFix.set(26.0, 10)), n = 1)))),
        )!!
        assertWithMessage("dumbbells step by 2 kg").that(dumbbell.targetWeightKg).isEqualTo(28.0)
        assertThat(dumbbell.deltaKg).isEqualTo(2.0)
        val cable = overload(
            listOf(WidFix.entry("pushdown", WidFix.planned(3, 30.0, 12))),
            listOf(WidFix.workout(1, daysAgo = 3.0).withExercises(listOf(WidFix.lift("pushdown", listOf(WidFix.set(30.0, 13)), n = 1)))),
        )!!
        assertThat(cable.targetWeightKg).isEqualTo(32.5)
        assertWithMessage("the planned reps, not last time's").that(cable.targetReps).isEqualTo(12)
    }

    @Test
    fun testOverloadAddsOneRepWhenLastTimeFellShortOfThePlannedReps() {
        val target = overload(listOf(WidFix.entry("bench", WidFix.planned(3, 82.5, 6))), benchHistory(listOf(WidFix.set(80.0, 5))))!!
        assertWithMessage("same weight").that(target.targetWeightKg).isEqualTo(80.0)
        assertWithMessage("one more rep than last time").that(target.targetReps).isEqualTo(6)
        assertThat(target.deltaKg).isEqualTo(0.0)
    }

    @Test
    fun testOverloadNeverAsksForMoreThanThePlannedReps() {
        val target = overload(listOf(WidFix.entry("bench", WidFix.planned(3, 82.5, 6))), benchHistory(listOf(WidFix.set(80.0, 4))))!!
        assertWithMessage("min(lastReps + 1, plannedReps)").that(target.targetReps).isEqualTo(5)
        val far = overload(listOf(WidFix.entry("bench", WidFix.planned(3, 82.5, 3))), benchHistory(listOf(WidFix.set(80.0, 2))))!!
        assertThat(far.targetReps).isEqualTo(3)
    }

    @Test
    fun testOverloadTakesTheBestWorkingSetByEstimatedOneRepMax() {
        // 100 × 3 = 110, 90 × 6 = 108, 80 × 12 = 112 (the best), and a heavier warm-up that does not count.
        val sets = listOf(WidFix.set(120.0, 5, SetType.WARMUP), WidFix.set(100.0, 3), WidFix.set(90.0, 6), WidFix.set(80.0, 12))
        val target = overload(listOf(WidFix.entry("bench", WidFix.planned(3, 80.0, 8))), benchHistory(sets))!!
        assertThat(target.lastWeightKg).isEqualTo(80.0)
        assertThat(target.lastReps).isEqualTo(12)
        assertThat(target.targetWeightKg).isEqualTo(82.5)
    }

    @Test
    fun testOverloadLooksAtTheNewestWorkoutThatContainsTheExerciseOnly() {
        val history = listOf(
            WidFix.workout(3, "Lower A · Quads", daysAgo = 1.0).withExercises(listOf(WidFix.lift("squat", listOf(WidFix.set(100.0, 5)), n = 3))),
            WidFix.workout(2, "Upper A · Push", daysAgo = 5.0).withExercises(listOf(WidFix.lift("bench", listOf(WidFix.set(80.0, 6)), n = 2))),
            WidFix.workout(1, "Upper A · Push", daysAgo = 12.0).withExercises(listOf(WidFix.lift("bench", listOf(WidFix.set(90.0, 6)), n = 1))),
        )
        val target = overload(listOf(WidFix.entry("bench", WidFix.planned(3, 82.5, 6))), history)!!
        assertWithMessage("the heavier session 12 days ago is not the last time").that(target.lastWeightKg).isEqualTo(80.0)
        assertThat(target.lastDaysAgo).isEqualTo(5)
    }

    @Test
    fun testOverloadWalksTheEntriesToTheFirstThatTracksWeightHasAWorkingSetAndHasHistory() {
        val entries = listOf(
            WidFix.entry("pullup", WidFix.planned(3, 0.0, 8)), // does not track weight
            WidFix.entry("ohp", listOf(PlannedSet(type = SetType.WARMUP, weightKg = 30.0, reps = 8))), // no working set
            WidFix.entry("bench", WidFix.planned(3, 82.5, 6)), // no history
            WidFix.entry("squat", WidFix.planned(3, 100.0, 5)), // the one
            WidFix.entry("deadlift", WidFix.planned(3, 120.0, 5)),
        )
        val history = listOf(
            WidFix.workout(1, daysAgo = 4.0).withExercises(
                listOf(
                    WidFix.lift("ohp", listOf(WidFix.set(40.0, 8)), n = 1),
                    WidFix.lift("squat", listOf(WidFix.set(97.5, 5)), n = 2),
                    WidFix.lift("deadlift", listOf(WidFix.set(120.0, 5)), n = 3),
                ),
            ),
        )
        val target = overload(entries, history)!!
        assertThat(target.exerciseID).isEqualTo("squat")
        assertThat(target.targetWeightKg).isEqualTo(100.0)
    }

    @Test
    fun testOverloadIsNullWhenNothingHasHistoryOrNothingTracksWeight() {
        assertThat(overload(listOf(WidFix.entry("bench", WidFix.planned(3, 82.5, 6))), emptyList())).isNull()
        assertWithMessage("no weight exercises")
            .that(overload(listOf(WidFix.entry("pushup", WidFix.planned(3, 0.0, 12)), WidFix.entry("plank", WidFix.planned(3, 0.0, 45))), benchHistory(listOf(WidFix.set(80.0, 6)))))
            .isNull()
        assertThat(overload(emptyList(), benchHistory(listOf(WidFix.set(80.0, 6))))).isNull()
    }

    @Test
    fun testOverloadIgnoresAWorkoutThatHoldsOnlyWarmUpsOfTheExercise() {
        assertThat(overload(listOf(WidFix.entry("bench", WidFix.planned(3, 82.5, 6))), benchHistory(listOf(WidFix.set(60.0, 8, SetType.WARMUP))))).isNull()
    }

    @Test
    fun testOverloadIsForTheNextUpTemplateOnly() {
        // The rotation says Lower A (after Upper A); the bench is only in Upper A.
        val upper = WidFix.template(1, "Upper A · Push", listOf(WidFix.entry("bench", WidFix.planned(3, 82.5, 6))), last = WidFix.now.addingTimeInterval(-86_400.0))
        val lower = WidFix.template(2, "Lower A · Quads", listOf(WidFix.entry("squat", WidFix.planned(3, 100.0, 5))))
        val history = listOf(
            WidFix.workout(1, daysAgo = 1.0)
                .withExercises(listOf(WidFix.lift("bench", listOf(WidFix.set(80.0, 6)), n = 1), WidFix.lift("squat", listOf(WidFix.set(95.0, 5)), n = 2))),
        )
        val target = WidFix.snapshot(StrengthData(templates = listOf(upper, lower), history = history)).overload!!
        assertThat(target.exerciseID).isEqualTo("squat")
        assertThat(target.targetWeightKg).isEqualTo(97.5)
    }
}

class WidgetFormCueAndLoadedBarRuleTests {
    private fun snapshot(entries: List<TemplateEntry>, now: Instant = WidFix.now): WidgetSnapshot =
        WidFix.snapshot(StrengthData(templates = listOf(WidFix.template(1, "Upper A · Push", entries))), now = now)

    // region formCue

    @Test
    fun testFormCueIsAnEntryOfTheFirstExerciseThatHasCuesRotatingWithTheDayOfTheYear() {
        val entries = listOf(WidFix.entry("bench", WidFix.planned(3, 80.0, 6)), WidFix.entry("incline", WidFix.planned(3, 28.0, 10)))
        val bench = ExerciseLibrary.exercise("bench")!!
        assertThat(bench.cues).hasSize(3)
        // 16 October 2026 is day 289 of the year: (289 - 1) mod 3 = 0, the first cue.
        for ((offset, expected) in listOf(0, 1, 2, 0, 1).withIndex()) {
            val cue = snapshot(entries, now = WidFix.now.addingTimeInterval(offset * 86_400.0)).formCue!!
            assertThat(cue.exerciseID).isEqualTo("bench")
            assertThat(cue.exerciseName).isEqualTo("Barbell bench press")
            assertThat(cue.count).isEqualTo(3)
            assertWithMessage("1-based, day ${289 + offset}").that(cue.index).isEqualTo(expected + 1)
            assertThat(cue.cue).isEqualTo(bench.cues[expected])
        }
    }

    @Test
    fun testFormCueSkipsEntriesWhoseExerciseHasNoCues() {
        val bare = ExerciseLibrary.exercise("bench")!!.copy(cues = emptyList())
        val entries = listOf(
            TemplateEntry(exercise = bare, plannedSets = WidFix.planned(3, 80.0, 6), restSeconds = 90),
            WidFix.entry("incline", WidFix.planned(3, 28.0, 10)),
        )
        val cue = snapshot(entries).formCue!!
        assertThat(cue.exerciseID).isEqualTo("incline")
        assertThat(cue.count).isEqualTo(3)
    }

    @Test
    fun testFormCueIsNullWhenNoExerciseHasCues() {
        val bare = ExerciseLibrary.exercise("bench")!!.copy(cues = emptyList())
        assertThat(snapshot(listOf(TemplateEntry(exercise = bare, plannedSets = WidFix.planned(3, 80.0, 6), restSeconds = 90))).formCue).isNull()
        assertThat(snapshot(emptyList()).formCue).isNull()
    }

    // endregion

    // region loadedBar

    @Test
    fun testLoadedBarIsTheHeaviestWorkingSetAmongTheExercisesThatUsePlates() {
        val entries = listOf(
            WidFix.entry("legpress", WidFix.planned(3, 200.0, 10)), // a machine: no plates
            WidFix.entry("ohp", WidFix.planned(3, 45.0, 8)),
            WidFix.entry("bench", listOf(PlannedSet(type = SetType.WARMUP, weightKg = 100.0, reps = 3)) + WidFix.planned(3, 85.0, 5)),
        )
        val bar = snapshot(entries).loadedBar!!
        assertThat(bar.exerciseID).isEqualTo("bench")
        assertThat(bar.exerciseName).isEqualTo("Barbell bench press")
        assertWithMessage("the 100 kg warm-up is not a working set").that(bar.totalKg).isEqualTo(85.0)
        assertThat(bar.barKg).isEqualTo(20.0)
        assertWithMessage("(85 - 20) / 2 = 32.5 kg a side").that(bar.platesPerSide).containsExactly(25.0, 5.0, 2.5).inOrder()
        assertThat(bar.leftoverKg).isEqualTo(0.0)
        assertThat(bar.summary).isEqualTo("25 + 5 + 2.5")
    }

    @Test
    fun testLoadedBarTakesTheFirstEntryOnATie() {
        val entries = listOf(WidFix.entry("squat", WidFix.planned(3, 100.0, 5)), WidFix.entry("bench", WidFix.planned(3, 100.0, 5)))
        assertThat(snapshot(entries).loadedBar!!.exerciseID).isEqualTo("squat")
    }

    @Test
    fun testLoadedBarUsesTheBarOfTheExercise() {
        val bar = snapshot(listOf(WidFix.entry("skull", WidFix.planned(3, 30.0, 10)))).loadedBar!!
        assertWithMessage("the skull crusher bar weighs 10 kg").that(bar.barKg).isEqualTo(10.0)
        assertThat(bar.platesPerSide).containsExactly(10.0)
        assertThat(bar.summary).isEqualTo("10")
    }

    @Test
    fun testLoadedBarReportsWhatThePlatesCannotMake() {
        val bar = snapshot(listOf(WidFix.entry("bench", WidFix.planned(3, 21.0, 5)))).loadedBar!!
        assertThat(bar.platesPerSide).isEmpty()
        assertThat(bar.leftoverKg).isEqualTo(0.5)
        assertThat(bar.summary).isEqualTo("")
    }

    @Test
    fun testLoadedBarIsNullWithoutABarbellWeightExerciseOrBelowTheEmptyBar() {
        assertWithMessage("no weight exercises with plates")
            .that(snapshot(listOf(WidFix.entry("legpress", WidFix.planned(3, 200.0, 10)), WidFix.entry("pushup", WidFix.planned(3, 0.0, 12)))).loadedBar)
            .isNull()
        assertWithMessage("lighter than the bar").that(snapshot(listOf(WidFix.entry("bench", WidFix.planned(3, 15.0, 10)))).loadedBar).isNull()
        assertWithMessage("no working set")
            .that(snapshot(listOf(WidFix.entry("bench", listOf(PlannedSet(type = SetType.WARMUP, weightKg = 60.0, reps = 5))))).loadedBar)
            .isNull()
        assertThat(snapshot(emptyList()).loadedBar).isNull()
    }

    // endregion
}
