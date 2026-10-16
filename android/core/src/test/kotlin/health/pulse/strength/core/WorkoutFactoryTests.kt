package health.pulse.strength.core

import com.google.common.truth.Truth.assertThat
import com.google.common.truth.Truth.assertWithMessage
import java.time.Instant
import org.junit.Test

// Port of WorkoutFactoryTests.swift.

/** Template fixtures with deterministic ids for the factory tests. Mirrors Swift `RedTemplateFix`. */
internal object RedTemplateFix {
    fun entry(n: Int, exercise: Exercise, planned: List<PlannedSet>, rest: Int, group: String? = null): TemplateEntry =
        TemplateEntry(id = RedFix.uuid(0x200 + n, 0), exercise = exercise, plannedSets = planned, restSeconds = rest, supersetGroup = group)

    fun planned(count: Int, kg: Double, reps: Int): List<PlannedSet> =
        List(count) { PlannedSet(type = SetType.NORMAL, weightKg = kg, reps = reps) }

    /** "Upper A · Push": the design's workout. */
    fun upperA(lastPerformed: Instant? = RedFix.at(-432_000)): WorkoutTemplate = WorkoutTemplate(
        id = RedFix.uuid(0x2FF, 1),
        name = "Upper A · Push",
        entries = listOf(
            entry(
                1, RedFix.bench,
                listOf(
                    PlannedSet(type = SetType.WARMUP, weightKg = 50.0, reps = 8), PlannedSet(type = SetType.WARMUP, weightKg = 70.0, reps = 5),
                    PlannedSet(weightKg = 82.5, reps = 6), PlannedSet(weightKg = 82.5, reps = 6), PlannedSet(weightKg = 85.0, reps = 6),
                ),
                rest = 150,
            ),
            entry(2, RedFix.incline, planned(3, 28.0, 10), rest = 90),
            entry(3, RedFix.ohp, planned(3, 45.0, 8), rest = 120),
            entry(4, RedFix.lateral, planned(3, 8.0, 15), rest = 60, group = "A"),
            entry(5, RedFix.pushdown, planned(3, 30.0, 12), rest = 60, group = "A"),
            entry(6, RedFix.crossover, planned(3, 15.0, 12), rest = 60),
        ),
        lastPerformed = lastPerformed,
    )
}

class WorkoutFactoryTests {
    /** What a template stores about an exercise entry (without the entry id). */
    private data class Shape(val exerciseID: String, val rest: Int, val group: String?, val sets: List<PlannedSet>)

    private fun shapes(template: WorkoutTemplate): List<Shape> =
        template.entries.map { Shape(it.exercise.id, it.restSeconds, it.supersetGroup, it.plannedSets) }

    private fun shapes(state: WorkoutState): List<Shape> =
        state.exercises.map { entry ->
            Shape(
                entry.exercise.id, entry.restSeconds, entry.supersetGroup,
                entry.sets.map { PlannedSet(type = it.type, weightKg = it.weightKg, reps = it.reps) },
            )
        }

    // region makeEmpty

    @Test
    fun testMakeEmptyCreatesAnEmptyRunningWorkout() {
        val id = RedFix.uuid(9, 9)
        val s = WorkoutFactory.makeEmpty("Quick session", RedFix.t0, id)
        assertThat(s.id).isEqualTo(id)
        assertThat(s.name).isEqualTo("Quick session")
        assertThat(s.startedAt).isEqualTo(RedFix.t0)
        assertThat(s.exercises).isEmpty()
        assertThat(s.currentIndex).isEqualTo(0)
        assertThat(s.revision).isEqualTo(0)
        assertThat(s.templateID).isNull()
        assertThat(s.templateBaseline).isEmpty()
        assertThat(s.rest).isNull()
        assertThat(s.pausedAt).isNull()
        assertThat(s.lastLogged).isNull()
        assertThat(s.undo).isNull()
        assertThat(s.finishedAt).isNull()
        assertThat(s.settings).isEqualTo(WorkoutSettings())
        assertThat(s.heartRateCount).isEqualTo(0)
        assertThat(s.usedWatch).isFalse()
    }

    @Test
    fun testMakeEmptyUsesFreshIDsByDefault() {
        val a = WorkoutFactory.makeEmpty("A", RedFix.t0)
        val b = WorkoutFactory.makeEmpty("A", RedFix.t0)
        assertThat(a.id).isNotEqualTo(b.id)
    }

    // endregion

    // region makeWorkout

    @Test
    fun testMakeWorkoutCopiesTheTemplate() {
        val template = RedTemplateFix.upperA()
        val id = RedFix.uuid(9, 1)
        val s = WorkoutFactory.makeWorkout(template, RedFix.at(10), id)
        assertThat(s.id).isEqualTo(id)
        assertThat(s.name).isEqualTo("Upper A · Push")
        assertThat(s.templateID).isEqualTo(template.id)
        assertThat(s.startedAt).isEqualTo(RedFix.at(10))
        assertThat(s.templateBaseline).isEqualTo(template.entries.map { it.id })
        assertThat(s.currentIndex).isEqualTo(0)
        assertThat(s.revision).isEqualTo(0)
        assertThat(s.rest).isNull()
        assertThat(s.lastLogged).isNull()
        assertThat(s.undo).isNull()
        assertThat(s.pausedAt).isNull()
        assertThat(s.exercises.size).isEqualTo(6)
        assertThat(shapes(s)).isEqualTo(shapes(template))
        for ((workoutExercise, entry) in s.exercises.zip(template.entries)) {
            assertThat(workoutExercise.templateEntryID).isEqualTo(entry.id)
            assertThat(workoutExercise.id).isNotEqualTo(entry.id)
            assertThat(workoutExercise.exercise).isEqualTo(entry.exercise)
            assertThat(workoutExercise.note).isEqualTo("")
            assertThat(workoutExercise.sets.all { !it.isDone && it.rir == null }).isTrue()
        }
    }

    @Test
    fun testMakeWorkoutGivesEveryExerciseAndSetAFreshID() {
        val template = RedTemplateFix.upperA()
        val a = WorkoutFactory.makeWorkout(template, RedFix.t0)
        val b = WorkoutFactory.makeWorkout(template, RedFix.t0)
        val aIDs = a.exercises.map { it.id } + a.exercises.flatMap { e -> e.sets.map { it.id } }
        val bIDs = b.exercises.map { it.id } + b.exercises.flatMap { e -> e.sets.map { it.id } }
        assertThat(aIDs.toSet().size).isEqualTo(aIDs.size)
        assertThat(aIDs.toSet().intersect(bIDs.toSet())).isEmpty()
        assertThat(a.id).isNotEqualTo(b.id)
    }

    @Test
    fun testMakeWorkoutKeepsTheSameExerciseTwice() {
        val twice = WorkoutTemplate(
            name = "Doubles",
            entries = listOf(
                RedTemplateFix.entry(1, RedFix.bench, RedTemplateFix.planned(2, 80.0, 5), rest = 150),
                RedTemplateFix.entry(2, RedFix.bench, RedTemplateFix.planned(2, 60.0, 8), rest = 120),
            ),
        )
        val s = WorkoutFactory.makeWorkout(twice, RedFix.t0)
        assertThat(s.exercises.size).isEqualTo(2)
        assertThat(s.exercises[0].id).isNotEqualTo(s.exercises[1].id)
        assertThat(s.exercises[0].templateEntryID).isEqualTo(twice.entries[0].id)
        assertThat(s.exercises[1].templateEntryID).isEqualTo(twice.entries[1].id)
    }

    @Test
    fun testMakeWorkoutDropsALoneSupersetLetter() {
        val template = WorkoutTemplate(
            name = "Odd",
            entries = listOf(
                RedTemplateFix.entry(1, RedFix.lateral, RedTemplateFix.planned(2, 8.0, 15), rest = 60, group = "A"),
                RedTemplateFix.entry(2, RedFix.bench, RedTemplateFix.planned(2, 80.0, 5), rest = 150),
            ),
        )
        val s = WorkoutFactory.makeWorkout(template, RedFix.t0)
        assertThat(s.exercises.map { it.supersetGroup }).isEqualTo(listOf<String?>(null, null))
    }

    @Test
    fun testMakeWorkoutFromAnEmptyTemplate() {
        val s = WorkoutFactory.makeWorkout(WorkoutTemplate(name = "Nothing", entries = emptyList()), RedFix.t0)
        assertThat(s.exercises).isEmpty()
        assertThat(s.templateBaseline).isEmpty()
        assertThat(s.currentIndex).isEqualTo(0)
    }

    @Test
    fun testAFactoryWorkoutRunsTheDesignFlow() {
        var s = WorkoutFactory.makeWorkout(RedTemplateFix.upperA(), RedFix.t0)
        // bench: two warm-ups (60 s), then working sets (150 s)
        val expected = listOf(60, 60, 150, 150, 150)
        for ((i, rest) in expected.withIndex()) {
            s = RedFix.reduced(s, RedFix.toggle(s, 0, i), at = 100 * (i + 1))
            assertThat(s.rest?.totalSeconds).isEqualTo(rest)
        }
        // lateral / pushdown superset
        s = RedFix.reduced(s, WorkoutAction.GoTo(3), at = 700)
        s = RedFix.reduced(s, WorkoutAction.LogNextSet, at = 710)
        assertThat(s.currentIndex).isEqualTo(4)
        assertThat(s.rest).isNull()
        s = RedFix.reduced(s, WorkoutAction.LogNextSet, at = 720)
        assertThat(s.currentIndex).isEqualTo(3)
        assertThat(s.rest?.totalSeconds).isEqualTo(60)
        assertThat(s.exercises[3].doneCount).isEqualTo(1)
        assertThat(s.exercises[4].doneCount).isEqualTo(1)
    }

    // endregion

    // region updatedTemplate

    @Test
    fun testUnchangedWorkoutRoundTripsToAnEqualTemplate() {
        val template = RedTemplateFix.upperA()
        val workout = WorkoutFactory.makeWorkout(template, RedFix.t0)
        assertThat(WorkoutFactory.updatedTemplate(template, workout)).isEqualTo(template)
    }

    @Test
    fun testLoggingSetsDoesNotChangeTheTemplate() {
        val template = RedTemplateFix.upperA()
        var workout = WorkoutFactory.makeWorkout(template, RedFix.t0)
        for (i in 0 until 5) workout = RedFix.reduced(workout, RedFix.toggle(workout, 0, i), at = i * 200)
        workout = RedFix.reduced(workout, WorkoutAction.ToggleLastSetRIR(2), at = 2_000)
        assertThat(WorkoutFactory.updatedTemplate(template, workout)).isEqualTo(template)
    }

    @Test
    fun testUpdatedTemplateKeepsIdNameAndLastPerformed() {
        val template = RedTemplateFix.upperA(lastPerformed = RedFix.at(-86_400))
        var workout = WorkoutFactory.makeWorkout(template, RedFix.t0)
        workout = RedFix.reduced(workout, WorkoutAction.Rename("Renamed in the workout"))
        workout = RedFix.reduced(workout, WorkoutAction.RemoveExercise(RedFix.ex(workout, 5)))
        val updated = WorkoutFactory.updatedTemplate(template, workout)
        assertThat(updated.id).isEqualTo(template.id)
        assertThat(updated.name).isEqualTo("Upper A · Push")
        assertThat(updated.lastPerformed).isEqualTo(RedFix.at(-86_400))
        assertThat(updated.entries.size).isEqualTo(5)
    }

    @Test
    fun testUpdatedTemplateReflectsEditsAddedRemovedAndReorderedExercises() {
        val template = RedTemplateFix.upperA()
        var workout = WorkoutFactory.makeWorkout(template, RedFix.t0)
        workout = RedFix.reduced(workout, WorkoutAction.AddExercises(listOf(RedFix.squat)))
        workout = RedFix.reduced(workout, WorkoutAction.RemoveExercise(RedFix.ex(workout, 1)))           // incline
        workout = RedFix.reduced(workout, WorkoutAction.MoveExercise(0, 1))                                 // bench after ohp
        workout = RedFix.reduced(workout, WorkoutAction.SetWeight(RedFix.ex(workout, 1), RedFix.setID(workout, 1, 0), 47.5))
        workout = RedFix.reduced(workout, WorkoutAction.SetRest(RedFix.ex(workout, 1), 105))
        workout = RedFix.reduced(workout, WorkoutAction.AddSet(RedFix.ex(workout, 0)))

        val updated = WorkoutFactory.updatedTemplate(template, workout)
        assertThat(updated.entries.map { it.exercise.id }).isEqualTo(listOf("ohp", "bench", "lateral", "pushdown", "crossover", "squat"))
        assertThat(shapes(updated)).isEqualTo(shapes(workout))
        // kept entries keep their template entry id, the new one gets a fresh id
        assertThat(updated.entries[0].id).isEqualTo(template.entries[2].id)      // ohp
        assertThat(updated.entries[1].id).isEqualTo(template.entries[0].id)      // bench
        assertThat(updated.entries[2].id).isEqualTo(template.entries[3].id)
        assertThat(updated.entries[3].id).isEqualTo(template.entries[4].id)
        assertThat(updated.entries[4].id).isEqualTo(template.entries[5].id)
        assertThat(template.entries.map { it.id }.contains(updated.entries[5].id)).isFalse()
        assertThat(updated.entries.size).isEqualTo(6)
        assertThat(updated.entries.map { it.id }.toSet().size).isEqualTo(6)
    }

    @Test
    fun testUpdatedTemplateReflectsSetValuesRestAndSupersetChanges() {
        val template = RedTemplateFix.upperA()
        var workout = WorkoutFactory.makeWorkout(template, RedFix.t0)
        workout = RedFix.reduced(workout, WorkoutAction.SetWeight(RedFix.ex(workout, 2), RedFix.setID(workout, 2, 1), 47.5))
        workout = RedFix.reduced(workout, WorkoutAction.SetReps(RedFix.ex(workout, 2), RedFix.setID(workout, 2, 1), 6))
        workout = RedFix.reduced(workout, WorkoutAction.SetSetType(RedFix.ex(workout, 2), RedFix.setID(workout, 2, 2), SetType.DROP))
        workout = RedFix.reduced(workout, WorkoutAction.SetRest(RedFix.ex(workout, 0), 180))
        workout = RedFix.reduced(workout, WorkoutAction.ToggleSuperset(RedFix.ex(workout, 3)))    // dissolve A
        workout = RedFix.reduced(workout, WorkoutAction.DeleteSet(RedFix.ex(workout, 5), RedFix.setID(workout, 5, 2)))
        val updated = WorkoutFactory.updatedTemplate(template, workout)
        assertThat(updated.entries[2].plannedSets[1]).isEqualTo(PlannedSet(type = SetType.NORMAL, weightKg = 47.5, reps = 6))
        assertThat(updated.entries[2].plannedSets[2].type).isEqualTo(SetType.DROP)
        assertThat(updated.entries[0].restSeconds).isEqualTo(180)
        assertThat(updated.entries[3].supersetGroup).isNull()
        assertThat(updated.entries[4].supersetGroup).isNull()
        assertThat(updated.entries[5].plannedSets.size).isEqualTo(2)
        assertThat(shapes(updated)).isEqualTo(shapes(workout))
    }

    @Test
    fun testUpdatedTemplateTakesAReplacedExerciseAndKeepsItsEntryID() {
        val template = RedTemplateFix.upperA()
        var workout = WorkoutFactory.makeWorkout(template, RedFix.t0)
        workout = RedFix.reduced(workout, WorkoutAction.ReplaceExercise(RedFix.ex(workout, 1), RedFix.squat))
        val updated = WorkoutFactory.updatedTemplate(template, workout)
        assertThat(updated.entries[1].id).isEqualTo(template.entries[1].id)
        assertThat(updated.entries[1].exercise.id).isEqualTo("squat")
        assertThat(updated.entries[1].plannedSets.size).isEqualTo(3)
        assertThat(updated.entries[1].restSeconds).isEqualTo(180)
    }

    @Test
    fun testUpdatedTemplateIncludesPendingAndDoneSets() {
        val template = RedTemplateFix.upperA()
        var workout = WorkoutFactory.makeWorkout(template, RedFix.t0)
        workout = RedFix.reduced(workout, RedFix.toggle(workout, 1, 0), at = 1)
        val updated = WorkoutFactory.updatedTemplate(template, workout)
        assertThat(updated.entries[1].plannedSets.size).isEqualTo(3)
    }

    @Test
    fun testUpdatedTemplateOfAnEmptiedWorkoutHasNoEntries() {
        val template = RedTemplateFix.upperA()
        var workout = WorkoutFactory.makeWorkout(template, RedFix.t0)
        repeat(6) { workout = RedFix.reduced(workout, WorkoutAction.RemoveExercise(RedFix.ex(workout, 0)), at = 1) }
        assertThat(workout.exercises).isEmpty()
        assertThat(WorkoutFactory.updatedTemplate(template, workout).entries).isEmpty()
    }

    @Test
    fun testUpdatedTemplateNeverReusesAnEntryIDTwice() {
        val template = RedTemplateFix.upperA()
        var workout = WorkoutFactory.makeWorkout(template, RedFix.t0)
        val firstLink = workout.exercises[0].templateEntryID
        workout = RedFix.editExercise(workout, 1) { it.copy(templateEntryID = firstLink) }    // a corrupted link
        val updated = WorkoutFactory.updatedTemplate(template, workout)
        assertThat(updated.entries.map { it.id }.toSet().size).isEqualTo(6)
    }

    // endregion

    // region template(from:name:)

    @Test
    fun testSaveAsTemplateCreatesANewTemplateWithNewEntryIDs() {
        val source = RedTemplateFix.upperA()
        var workout = WorkoutFactory.makeWorkout(source, RedFix.t0)
        workout = RedFix.reduced(workout, WorkoutAction.AddExercises(listOf(RedFix.plank)))
        val saved = WorkoutFactory.template(workout, "Push + core")
        assertThat(saved.name).isEqualTo("Push + core")
        assertThat(saved.id).isNotEqualTo(source.id)
        assertThat(saved.lastPerformed).isNull()
        assertThat(saved.entries.size).isEqualTo(7)
        assertThat(shapes(saved)).isEqualTo(shapes(workout))
        val ids = saved.entries.map { it.id }
        assertThat(ids.toSet().size).isEqualTo(7)
        assertThat(ids.toSet().intersect(source.entries.map { it.id }.toSet())).isEmpty()
        assertThat(ids.toSet().intersect(workout.exercises.map { it.id }.toSet())).isEmpty()
        assertThat(saved.entries.map { it.supersetGroup }).isEqualTo(listOf<String?>(null, null, null, "A", "A", null, null))
    }

    @Test
    fun testSaveAsTemplateTrimsTheNameAndFallsBackToTheWorkoutName() {
        val workout = WorkoutFactory.makeWorkout(RedTemplateFix.upperA(), RedFix.t0)
        assertThat(WorkoutFactory.template(workout, "  Heavy day \n").name).isEqualTo("Heavy day")
        assertThat(WorkoutFactory.template(workout, "   ").name).isEqualTo("Upper A · Push")
        val unnamed = WorkoutFactory.makeEmpty(" ", RedFix.t0)
        assertThat(WorkoutFactory.template(unnamed, "").name).isEqualTo("Workout")
    }

    /**
     * Kotlin-only addition (no Swift test): Swift trims with `.whitespacesAndNewlines` (the Unicode White_Space set); Kotlin's
     * `String.trim()` has U+001C...U+001F and lacks U+0085.
     */
    @Test
    fun testKotlinOnlySaveAsTemplateTrimsLikeFoundation() {
        val workout = WorkoutFactory.makeWorkout(RedTemplateFix.upperA(), RedFix.t0)
        assertThat(WorkoutFactory.template(workout, "\u0085 Heavy day  ").name).isEqualTo("Heavy day")
        assertThat(WorkoutFactory.template(workout, " \u0085　").name).isEqualTo("Upper A · Push")
        assertThat(WorkoutFactory.template(workout, "\u001FX\u001C").name).isEqualTo("\u001FX\u001C")
        val unnamed = WorkoutFactory.makeEmpty("\u0085　", RedFix.t0)
        assertThat(WorkoutFactory.template(unnamed, "").name).isEqualTo("Workout")
        val oddlyNamed = WorkoutFactory.makeEmpty("\u001F", RedFix.t0)
        assertThat(WorkoutFactory.template(oddlyNamed, "").name).isEqualTo("\u001F")
    }

    @Test
    fun testSavedTemplateStartsAnIdenticalWorkout() {
        var workout = WorkoutFactory.makeWorkout(RedTemplateFix.upperA(), RedFix.t0)
        workout = RedFix.reduced(workout, WorkoutAction.AddExercises(listOf(RedFix.pushup)))
        workout = RedFix.reduced(workout, WorkoutAction.RemoveExercise(RedFix.ex(workout, 2)))
        val saved = WorkoutFactory.template(workout, "Mine")
        val again = WorkoutFactory.makeWorkout(saved, RedFix.at(99))
        assertThat(shapes(again)).isEqualTo(shapes(workout))
        assertThat(again.templateID).isEqualTo(saved.id)
        assertThat(again.templateBaseline).isEqualTo(saved.entries.map { it.id })
    }

    @Test
    fun testTemplateWorkoutTemplateRoundTripThroughTheReducer() {
        val template = RedTemplateFix.upperA()
        var workout = WorkoutFactory.makeWorkout(template, RedFix.t0)
        var clock = 0.0
        fun step(action: WorkoutAction) {
            clock += 5
            workout = WorkoutReducer.reduce(workout, action, RedFix.at(clock))
        }
        step(RedFix.toggle(workout, 0, 0))
        step(WorkoutAction.SetWeight(RedFix.ex(workout, 0), RedFix.setID(workout, 0, 4), 87.5))
        step(WorkoutAction.AddExercises(listOf(RedFix.plank)))
        step(WorkoutAction.MoveExerciseBy(RedFix.ex(workout, 6), -6))
        step(WorkoutAction.RemoveExercise(RedFix.ex(workout, 2)))      // incline
        step(WorkoutAction.Undo)                                        // put it back
        val updated = WorkoutFactory.updatedTemplate(template, workout)
        val next = WorkoutFactory.makeWorkout(updated, RedFix.at(1_000))
        assertThat(shapes(next)).isEqualTo(shapes(workout))
        assertThat(next.exercises.firstOrNull()?.exercise?.id).isEqualTo("plank")
        assertThat(next.exercises.firstOrNull { it.exercise.id == "bench" }?.sets?.get(4)?.weightKg).isEqualTo(87.5)
        // everything in the new workout is pending again
        assertThat(next.exercises.all { it.doneCount == 0 }).isTrue()
    }

    @Test
    fun testStateAndTemplateSurviveJSONRoundTrips() {
        val template = RedTemplateFix.upperA()
        var workout = WorkoutFactory.makeWorkout(template, RedFix.t0)
        workout = RedFix.reduced(workout, RedFix.toggle(workout, 0, 2), at = 30)
        workout = RedFix.reduced(workout, WorkoutAction.RemoveExercise(RedFix.ex(workout, 5)), at = 31)
        val json = StrengthJson.format
        val decodedState = json.decodeFromString(WorkoutState.serializer(), json.encodeToString(WorkoutState.serializer(), workout))
        assertThat(decodedState).isEqualTo(workout)
        val decodedTemplate = json.decodeFromString(WorkoutTemplate.serializer(), json.encodeToString(WorkoutTemplate.serializer(), template))
        assertThat(decodedTemplate).isEqualTo(template)
    }

    // endregion
}

/** `WorkoutTemplate.estimatedMinutes` follows reducer rule 2: an exercise rest of 0 (Off) means no rest after any set type. */
class TemplateEstimateRestTests {
    private fun template(entries: List<TemplateEntry>): WorkoutTemplate =
        WorkoutTemplate(id = RedFix.uuid(0x2FE, 1), name = "Estimate", entries = entries)

    private fun warmups(count: Int): List<PlannedSet> =
        List(count) { PlannedSet(type = SetType.WARMUP, weightKg = 40.0, reps = 8) }

    /** The arithmetic of the rule, written out once more for the comparison. */
    private fun reference(template: WorkoutTemplate): Int {
        var seconds = 0
        for (entry in template.entries) {
            val rest = maxOf(0, minOf(entry.restSeconds, 3_600))
            for (set in entry.plannedSets) {
                val after = if (rest == 0) 0 else (if (set.type == SetType.WARMUP) maxOf(30, rest * 2 / 5) else rest)
                seconds += 45 + after
            }
        }
        return maxOf(5, (seconds.toDouble() / 60.0 / 5.0).roundedAwayFromZero().toInt() * 5)
    }

    @Test
    fun testWarmupsOfAnOffExerciseAddNoRest() {
        // 20 warm-ups at 45 s of work each = 15 minutes; they used to add a 30 s rest each (25 minutes).
        val off = template(listOf(RedTemplateFix.entry(1, RedFix.bench, warmups(20), rest = 0)))
        assertThat(off.estimatedMinutes).isEqualTo(15)
        // The same sets with a rest still count it: 40 % of 100 s = 40 s per warm-up.
        val timed = template(listOf(RedTemplateFix.entry(1, RedFix.bench, warmups(20), rest = 100)))
        assertWithMessage("20 x (45 s + 40 s) = 28.3 minutes").that(timed.estimatedMinutes).isEqualTo(30)
        // The 30 s minimum still applies to a short, non-zero rest.
        val short = template(listOf(RedTemplateFix.entry(1, RedFix.bench, warmups(20), rest = 5)))
        assertWithMessage("20 x (45 s + 30 s) = 25 minutes").that(short.estimatedMinutes).isEqualTo(25)
    }

    @Test
    fun testWorkingSetsOfAnOffExerciseAddNoRestAsBefore() {
        val off = template(listOf(RedTemplateFix.entry(1, RedFix.bench, RedTemplateFix.planned(30, 60.0, 8), rest = 0)))
        assertWithMessage("30 x 45 s = 22.5 minutes, rounded to 5").that(off.estimatedMinutes).isEqualTo(25)
    }

    @Test
    fun testMixedEntriesAgreeWithTheRule() {
        val mixed = template(
            listOf(
                RedTemplateFix.entry(1, RedFix.bench, warmups(6) + RedTemplateFix.planned(4, 80.0, 5), rest = 0),
                RedTemplateFix.entry(2, RedFix.incline, warmups(2) + RedTemplateFix.planned(3, 28.0, 10), rest = 90),
                RedTemplateFix.entry(3, RedFix.ohp, warmups(12), rest = 0),
            ),
        )
        assertThat(mixed.estimatedMinutes).isEqualTo(reference(mixed))
        val allOn = mixed.copy(entries = mixed.entries.map { if (it.restSeconds == 0) it.copy(restSeconds = 90) else it })
        assertWithMessage("switching the timer on adds the rests").that(allOn.estimatedMinutes).isGreaterThan(mixed.estimatedMinutes)
    }

    @Test
    fun testTheSampleTemplatesAreUnchanged() {
        for (sample in SampleData.templates()) {
            assertWithMessage(sample.name).that(sample.estimatedMinutes).isEqualTo(reference(sample))
        }
    }
}
