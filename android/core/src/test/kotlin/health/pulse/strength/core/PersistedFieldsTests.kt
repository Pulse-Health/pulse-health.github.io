package health.pulse.strength.core

import com.google.common.truth.Truth.assertThat
import com.google.common.truth.Truth.assertWithMessage
import java.time.Instant
import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import org.junit.Assert.assertThrows
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

// The additive persisted fields of widgets/SPEC.md section 2: `LoggedSet.doneAt`, `CompletedSet.loggedAt`,
// `WorkoutState.heartRateSeries` and `CompletedWorkout.heartRateSeries`. Mirrors the Swift PersistedFieldsTests.

// region LoggedSet.doneAt (reducer)

class SetDoneTimeTests {
    private fun doneAt(s: WorkoutState, k: Int, i: Int): Instant? = s.exercises[k].sets[i].doneAt

    @Test
    fun testLogNextSetStampsTheSetWithTheReducersNow() {
        val s = RedFix.reduced(RedFix.designState(), WorkoutAction.LogNextSet, 100)
        assertThat(s.exercises[0].sets[0].isDone).isTrue()
        assertThat(doneAt(s, 0, 0)).isEqualTo(RedFix.at(100))
        assertWithMessage("a pending set has no time").that(doneAt(s, 0, 1)).isNull()
    }

    @Test
    fun testLogSetStampsTheNamedSet() {
        val start = RedFix.designState()
        val s = RedFix.reduced(start, RedFix.log(start, 1, 2), 250)
        assertThat(doneAt(s, 1, 2)).isEqualTo(RedFix.at(250))
        assertThat(doneAt(s, 0, 0)).isNull()
    }

    @Test
    fun testToggleSetStampsAPendingSetAndClearsALoggedOne() {
        var s = RedFix.designState()
        val toggle = RedFix.toggle(s, 0, 2)
        s = RedFix.reduced(s, toggle, 10)
        assertThat(s.exercises[0].sets[2].isDone).isTrue()
        assertThat(doneAt(s, 0, 2)).isEqualTo(RedFix.at(10))
        s = RedFix.reduced(s, WorkoutAction.SetRIR(RedFix.ex(s, 0), RedFix.setID(s, 0, 2), 2), 15)
        s = RedFix.reduced(s, toggle, 20)
        assertThat(s.exercises[0].sets[2].isDone).isFalse()
        assertWithMessage("a set that is pending again has no time").that(doneAt(s, 0, 2)).isNull()
        assertWithMessage("the RIR is kept, as before").that(s.exercises[0].sets[2].rir).isEqualTo(2)
    }

    @Test
    fun testLoggingASetAgainAfterTogglingItBackStampsTheNewTime() {
        var s = RedFix.designState()
        val toggle = RedFix.toggle(s, 0, 3)
        s = RedFix.reduced(s, toggle, 10)
        s = RedFix.reduced(s, toggle, 20)
        s = RedFix.reduced(s, toggle, 30)
        assertThat(doneAt(s, 0, 3)).isEqualTo(RedFix.at(30))
    }

    @Test
    fun testLoggingASetThatIsAlreadyLoggedKeepsTheFirstTime() {
        val start = RedFix.designState()
        val once = RedFix.reduced(start, RedFix.log(start, 0, 2), 10)
        val twice = RedFix.reduced(once, RedFix.log(start, 0, 2), 99)
        assertWithMessage("logSet on a logged set is a no-op").that(twice).isEqualTo(once)
        assertThat(doneAt(twice, 0, 2)).isEqualTo(RedFix.at(10))
    }

    @Test
    fun testEverySetTypeIsStamped() {
        for (type in SetType.entries) {
            var s = RedFix.designState()
            s = RedFix.reduced(s, WorkoutAction.SetSetType(RedFix.ex(s, 1), RedFix.setID(s, 1, 0), type), 1)
            s = RedFix.reduced(s, RedFix.log(s, 1, 0), 5)
            assertWithMessage(type.toString()).that(doneAt(s, 1, 0)).isEqualTo(RedFix.at(5))
        }
    }

    @Test
    fun testOtherEditsLeaveTheTimeAlone() {
        var s = RedFix.reduced(RedFix.designState(), WorkoutAction.LogNextSet, 100)
        val exerciseID = RedFix.ex(s, 0)
        val setID = RedFix.setID(s, 0, 0)
        val edits = listOf(
            WorkoutAction.SetWeight(exerciseID, setID, 52.5), WorkoutAction.SetReps(exerciseID, setID, 9),
            WorkoutAction.SetRIR(exerciseID, setID, 3), WorkoutAction.ToggleLastSetRIR(2),
            WorkoutAction.SetSetType(exerciseID, setID, SetType.DROP), WorkoutAction.SetNote(exerciseID, "easy"),
            WorkoutAction.NudgeNextSet(1, 1), WorkoutAction.AdjustRest(15), WorkoutAction.Pause, WorkoutAction.Resume,
            WorkoutAction.SkipRest, WorkoutAction.GoTo(2), WorkoutAction.AddSet(exerciseID), WorkoutAction.SetRest(exerciseID, 90),
            WorkoutAction.UpdateHeartRate(120), WorkoutAction.Rename("Push"),
        )
        for ((offset, action) in edits.withIndex()) {
            s = RedFix.reduced(s, action, 200 + offset)
            assertWithMessage(action.toString()).that(doneAt(s, 0, 0)).isEqualTo(RedFix.at(100))
        }
    }

    @Test
    fun testADeletedSetComesBackWithItsTimeWhenTheDeletionIsUndone() {
        var s = RedFix.reduced(RedFix.designState(), WorkoutAction.LogNextSet, 100)
        val logged = s.exercises[0].sets[0]
        s = RedFix.reduced(s, WorkoutAction.DeleteSet(RedFix.ex(s, 0), logged.id), 110)
        assertThat(s.exercises[0].sets).hasSize(4)
        s = RedFix.reduced(s, WorkoutAction.Undo, 112)
        assertThat(s.exercises[0].sets[0]).isEqualTo(logged)
        assertThat(doneAt(s, 0, 0)).isEqualTo(RedFix.at(100))
    }

    @Test
    fun testARemovedExerciseComesBackWithTheTimesOfItsSets() {
        var s = RedFix.designState()
        s = RedFix.reduced(s, listOf(WorkoutAction.LogNextSet, WorkoutAction.LogNextSet), 100)
        val bench = s.exercises[0]
        s = RedFix.reduced(s, WorkoutAction.RemoveExercise(bench.id), 120)
        s = RedFix.reduced(s, WorkoutAction.Undo, 122)
        assertThat(s.exercises[0]).isEqualTo(bench)
        assertThat(s.exercises[0].sets.take(2).map { it.doneAt }).containsExactly(RedFix.at(100), RedFix.at(101)).inOrder()
    }

    @Test
    fun testSupersetMembersAreStampedWhenTheyAreLogged() {
        var s = RedFix.reduced(RedFix.designState(), WorkoutAction.GoTo(3))
        s = RedFix.reduced(s, WorkoutAction.LogNextSet, 100) // lateral raise, the superset moves on to the pushdown
        s = RedFix.reduced(s, WorkoutAction.LogNextSet, 105)
        assertThat(doneAt(s, 3, 0)).isEqualTo(RedFix.at(100))
        assertThat(doneAt(s, 4, 0)).isEqualTo(RedFix.at(105))
    }

    @Test
    fun testReplacingAnExerciseStartsItsSetsWithoutTimes() {
        var s = RedFix.reduced(RedFix.designState(), WorkoutAction.LogNextSet, 100)
        s = RedFix.reduced(s, WorkoutAction.ReplaceExercise(RedFix.ex(s, 0), RedFix.incline), 110)
        assertThat(s.exercises[0].sets.all { !it.isDone && it.doneAt == null }).isTrue()
    }

    @Test
    fun testAnAddedSetStartsWithoutATime() {
        var s = RedFix.designState()
        s = RedFix.reduced(
            s,
            listOf(WorkoutAction.GoTo(1), WorkoutAction.LogNextSet, WorkoutAction.LogNextSet, WorkoutAction.LogNextSet),
            10,
        )
        s = RedFix.reduced(s, WorkoutAction.AddSet(RedFix.ex(s, 1)), 40)
        val added = s.exercises[1].sets[3]
        assertThat(added.isDone).isFalse()
        assertThat(added.doneAt).isNull()
    }

    @Test
    fun testEachLoggedSetStillBumpsTheRevisionOnce() {
        var s = RedFix.designState().copy(revision = 5)
        val toggle = RedFix.toggle(s, 0, 2)
        s = RedFix.reduced(s, toggle, 1)
        assertThat(s.revision).isEqualTo(6)
        s = RedFix.reduced(s, toggle, 2)
        assertThat(s.revision).isEqualTo(7)
        s = RedFix.reduced(s, WorkoutAction.LogNextSet, 3)
        assertThat(s.revision).isEqualTo(8)
    }
}

// endregion

// region WorkoutState.heartRateSeries (reducer)

class HeartRateSeriesTests {
    /** [on] after one `UpdateHeartRate` per entry of [samples], each at `t0 + seconds`. */
    private fun feed(samples: List<Pair<Double, Int?>>, on: WorkoutState = RedFix.designState()): WorkoutState {
        var copy = on
        for ((seconds, bpm) in samples) copy = WorkoutReducer.reduce(copy, WorkoutAction.UpdateHeartRate(bpm), RedFix.at(seconds))
        return copy
    }

    @Test
    fun testTheFirstSampleIsKeptWithTheReducersNow() {
        val s = feed(listOf(5.0 to 120))
        assertThat(s.heartRateSeries).containsExactly(HeartRateSample(120, RedFix.at(5)))
    }

    @Test
    fun testASampleLessThanThirtySecondsAfterTheLastKeptOneIsNotKept() {
        val s = feed(listOf(0.0 to 120, 29.9 to 130))
        assertThat(s.heartRateSeries).containsExactly(HeartRateSample(120, RedFix.at(0)))
        assertWithMessage("the current heart rate follows every sample").that(s.heartRate).isEqualTo(130)
        assertThat(s.heartRateSum).isEqualTo(250)
        assertWithMessage("so does the average").that(s.heartRateCount).isEqualTo(2)
    }

    @Test
    fun testASampleExactlyThirtySecondsAfterTheLastKeptOneIsKept() {
        val s = feed(listOf(0.0 to 120, 30.0 to 130))
        assertThat(s.heartRateSeries.map { it.bpm }).containsExactly(120, 130).inOrder()
        assertThat(s.heartRateSeries.last().at).isEqualTo(RedFix.at(30))
    }

    @Test
    fun testTheSpacingCountsFromTheLastKeptSampleNotFromTheLastReceivedOne() {
        val s = feed(listOf(0.0 to 100, 20.0 to 110, 40.0 to 120, 60.0 to 130, 70.0 to 140))
        assertThat(s.heartRateSeries)
            .containsExactly(HeartRateSample(100, RedFix.at(0)), HeartRateSample(120, RedFix.at(40)), HeartRateSample(140, RedFix.at(70)))
            .inOrder()
        assertThat(s.heartRateCount).isEqualTo(5)
    }

    @Test
    fun testTheSeriesStopsAtThreeHundredSixtySamplesButTheAverageKeepsCounting() {
        assertThat(WorkoutReducer.maximumHeartRateSamples).isEqualTo(360)
        assertThat(WorkoutReducer.heartRateSampleInterval).isEqualTo(30.0)
        val samples = (0 until 400).map { it * 30.0 to (100 + it % 50) }
        val s = feed(samples)
        assertThat(s.heartRateSeries).hasSize(360)
        assertWithMessage("the series keeps the start of the workout").that(s.heartRateSeries.last().at).isEqualTo(RedFix.at(359 * 30))
        assertThat(s.heartRateSeries.map { it.bpm }).isEqualTo(samples.take(360).map { it.second })
        assertThat(s.heartRateCount).isEqualTo(400)
        assertThat(s.heartRateSum).isEqualTo(samples.sumOf { it.second })
    }

    @Test
    fun testSamplesOutsideThirtyToTwoHundredFortyAreNeverKeptAndDoNotUseUpTheSpacing() {
        val s = feed(listOf(0.0 to 29, 10.0 to 241, 20.0 to 0, 30.0 to null, 40.0 to 120))
        assertThat(s.heartRateSeries).containsExactly(HeartRateSample(120, RedFix.at(40)))
        assertThat(s.heartRate).isEqualTo(120)
        assertThat(s.heartRateCount).isEqualTo(1)
        assertWithMessage("both ends of the range are valid")
            .that(feed(listOf(0.0 to 30, 30.0 to 240)).heartRateSeries.map { it.bpm })
            .containsExactly(30, 240).inOrder()
    }

    @Test
    fun testASampleNeverBumpsTheRevision() {
        var s = RedFix.designState().copy(revision = 7)
        s = feed(listOf(0.0 to 120, 40.0 to 125), on = s)
        assertThat(s.heartRateSeries).hasSize(2)
        assertThat(s.revision).isEqualTo(7)
        s = RedFix.reduced(s, WorkoutAction.Rename("x"), 50)
        assertWithMessage("the next real change bumps by exactly one").that(s.revision).isEqualTo(8)
    }

    @Test
    fun testAClockThatMovedBackKeepsNothingUntilItPassesTheLastSampleByThirtySeconds() {
        val s = feed(listOf(100.0 to 120, 50.0 to 121, 129.9 to 122, 130.0 to 123))
        assertThat(s.heartRateSeries.map { it.bpm }).containsExactly(120, 123).inOrder()
    }

    @Test
    fun testOtherActionsLeaveTheSeriesAlone() {
        var s = feed(listOf(0.0 to 120, 40.0 to 125))
        val series = s.heartRateSeries
        s = RedFix.reduced(
            s,
            listOf(
                WorkoutAction.LogNextSet, WorkoutAction.LogNextSet, WorkoutAction.Pause, WorkoutAction.Resume,
                WorkoutAction.AdjustRest(15), WorkoutAction.Rename("Push"), WorkoutAction.Undo,
            ),
            100,
        )
        assertThat(s.heartRateSeries).isEqualTo(series)
    }

    @Test
    fun testTheSeriesIsKeptForAnEmptyWorkoutToo() {
        val empty = WorkoutState(name = "Empty", startedAt = RedFix.t0)
        assertThat(feed(listOf(3.0 to 90), on = empty).heartRateSeries).containsExactly(HeartRateSample(90, RedFix.at(3)))
    }
}

// endregion

// region The summary carries both

class LoggedTimesInTheSummaryTests {
    private fun build(state: WorkoutState): CompletedWorkout = SummaryBuilder.build(state, RedFix.at(900))

    @Test
    fun testEveryLoggedSetCarriesTheTimeItWasLogged() {
        val s = RedFix.reduced(RedFix.designState(), listOf(WorkoutAction.LogNextSet, WorkoutAction.LogNextSet, WorkoutAction.LogNextSet), 100)
        val summary = build(s)
        assertThat(summary.exercises[0].sets.map { it.loggedAt }).containsExactly(RedFix.at(100), RedFix.at(101), RedFix.at(102)).inOrder()
    }

    @Test
    fun testASetThatIsPendingAgainIsLeftOutAndNoStaleTimeSurvives() {
        var s = RedFix.reduced(RedFix.designState(), listOf(WorkoutAction.LogNextSet, WorkoutAction.LogNextSet), 100)
        s = RedFix.reduced(s, RedFix.toggle(s, 0, 0), 110)
        val sets = build(s).exercises[0].sets
        assertThat(sets).hasSize(1)
        assertThat(sets[0].loggedAt).isEqualTo(RedFix.at(101))
    }

    @Test
    fun testALoggedSetWithoutATimeGivesNoLoggedAt() {
        // A workout restored from a file written before the time was recorded.
        val s = RedFix.editSet(RedFix.designState(), 0, 0) { it.copy(isDone = true) }
        assertThat(build(s).exercises[0].sets[0].loggedAt).isNull()
    }

    @Test
    fun testTheHeartRateSeriesGoesToTheFinishedWorkout() {
        var s = RedFix.designState()
        for ((seconds, bpm) in listOf(0.0 to 100, 35.0 to 120, 70.0 to 140)) {
            s = WorkoutReducer.reduce(s, WorkoutAction.UpdateHeartRate(bpm), RedFix.at(seconds))
        }
        s = RedFix.reduced(s, WorkoutAction.LogNextSet, 80)
        val summary = build(s)
        assertThat(summary.heartRateSeries).isEqualTo(s.heartRateSeries)
        assertThat(summary.heartRateSeries?.map { it.bpm }).containsExactly(100, 120, 140).inOrder()
        assertThat(summary.averageHeartRate).isEqualTo(120)
    }

    @Test
    fun testNoSamplesGiveNullNotAnEmptyList() {
        val s = RedFix.reduced(RedFix.designState(), WorkoutAction.LogNextSet, 100)
        assertThat(build(s).heartRateSeries).isNull()
    }
}

// endregion

// region Files and payloads written before the fields existed

class PersistedFieldsCodingTests {
    @get:Rule
    val folder = TemporaryFolder()

    private val moment = Instant.ofEpochSecond(1_791_919_800L)
    private val format = StrengthJson.format

    private fun stateWithTimes(): WorkoutState {
        var state = RedFix.reduced(RedFix.designState(), listOf(WorkoutAction.LogNextSet, WorkoutAction.LogNextSet), 100)
        state = WorkoutReducer.reduce(state, WorkoutAction.UpdateHeartRate(130), RedFix.at(120))
        return state
    }

    /** [element] without the given keys at any depth. */
    private fun removing(keys: Set<String>, element: JsonElement): JsonElement = when (element) {
        is JsonObject -> JsonObject(element.filterKeys { it !in keys }.mapValues { removing(keys, it.value) })
        is JsonArray -> JsonArray(element.map { removing(keys, it) })
        else -> element
    }

    private fun withoutTimes(state: WorkoutState): WorkoutState =
        state.copy(exercises = state.exercises.map { entry -> entry.copy(sets = entry.sets.map { it.copy(doneAt = null) }) })

    // region Legacy JSON

    @Test
    fun testALoggedSetWrittenWithoutDoneAtDecodes() {
        val json = """{"id":"00000000-0000-4000-8000-000000000001","type":"normal","weightKg":80,"reps":6,"isDone":true,"rir":2}"""
        val set = format.decodeFromString(LoggedSet.serializer(), json)
        assertThat(set.weightKg).isEqualTo(80.0)
        assertThat(set.isDone).isTrue()
        assertThat(set.rir).isEqualTo(2)
        assertThat(set.doneAt).isNull()
    }

    @Test
    fun testACompletedSetWrittenWithoutLoggedAtDecodes() {
        val json = """{"type":"warmup","weightKg":50,"reps":8}"""
        val set = format.decodeFromString(CompletedSet.serializer(), json)
        assertThat(set).isEqualTo(CompletedSet(SetType.WARMUP, 50.0, 8))
        assertThat(set.loggedAt).isNull()
    }

    @Test
    fun testAWorkoutStateWrittenWithoutASeriesDecodesWithAnEmptyOne() {
        val state = stateWithTimes()
        assertThat(state.heartRateSeries).hasSize(1)
        val legacy = removing(setOf("heartRateSeries", "doneAt"), format.encodeToJsonElement(WorkoutState.serializer(), state))
        val decoded = format.decodeFromJsonElement(WorkoutState.serializer(), legacy)
        assertThat(decoded).isEqualTo(withoutTimes(state).copy(heartRateSeries = emptyList()))
        assertThat(decoded.heartRateSeries).isEmpty()
    }

    @Test
    fun testAWorkoutStateStillNeedsTheKeysItAlwaysNeeded() {
        val encoded = format.encodeToJsonElement(WorkoutState.serializer(), RedFix.designState())
        for (key in listOf("name", "startedAt")) {
            val broken = JsonObject(encoded.jsonObject.filterKeys { it != key })
            assertThrows("without $key", SerializationException::class.java) { format.decodeFromJsonElement(WorkoutState.serializer(), broken) }
        }
    }

    @Test
    fun testACompletedWorkoutWrittenWithoutTheNewKeysDecodes() {
        val completed = SampleData.history(moment)[0].let { workout ->
            workout.copy(
                exercises = workout.exercises.mapIndexed { index, entry ->
                    if (index == 0) entry.copy(sets = entry.sets.mapIndexed { i, set -> if (i == 0) set.copy(loggedAt = moment) else set }) else entry
                },
                heartRateSeries = listOf(HeartRateSample(120, moment)),
            )
        }
        val legacy = removing(setOf("heartRateSeries", "loggedAt"), format.encodeToJsonElement(CompletedWorkout.serializer(), completed))
        val decoded = format.decodeFromJsonElement(CompletedWorkout.serializer(), legacy)
        assertThat(decoded.heartRateSeries).isNull()
        assertThat(decoded.exercises.all { entry -> entry.sets.all { it.loggedAt == null } }).isTrue()
        assertThat(decoded.id).isEqualTo(completed.id)
        assertThat(decoded.exercises.map { it.sets.size }).isEqualTo(completed.exercises.map { it.sets.size })
    }

    // endregion

    // region Round trips and the shape on disk

    @Test
    fun testTheNewFieldsRoundTrip() {
        val state = stateWithTimes()
        val decodedState = format.decodeFromString(WorkoutState.serializer(), format.encodeToString(WorkoutState.serializer(), state))
        assertThat(decodedState).isEqualTo(state)
        assertThat(decodedState.exercises[0].sets[1].doneAt).isEqualTo(RedFix.at(101))

        val completed = SummaryBuilder.build(state, RedFix.at(300))
        val decodedCompleted =
            format.decodeFromString(CompletedWorkout.serializer(), format.encodeToString(CompletedWorkout.serializer(), completed))
        assertThat(decodedCompleted).isEqualTo(completed)
        assertThat(decodedCompleted.exercises[0].sets.map { it.loggedAt }).containsExactly(RedFix.at(100), RedFix.at(101)).inOrder()
        assertThat(decodedCompleted.heartRateSeries).isEqualTo(state.heartRateSeries)
    }

    @Test
    fun testAnUnsetTimeAndAMissingSeriesWriteNoKeysSoOldFilesStayTheSame() {
        fun keys(set: LoggedSet) = format.encodeToJsonElement(LoggedSet.serializer(), set).jsonObject
        fun keys(set: CompletedSet) = format.encodeToJsonElement(CompletedSet.serializer(), set).jsonObject
        assertThat(keys(LoggedSet(weightKg = 50.0, reps = 8)).containsKey("doneAt")).isFalse()
        assertThat(keys(LoggedSet(weightKg = 50.0, reps = 8, isDone = true, doneAt = moment)).containsKey("doneAt")).isTrue()
        assertThat(keys(CompletedSet(SetType.NORMAL, 50.0, 8)).containsKey("loggedAt")).isFalse()
        assertThat(keys(CompletedSet(SetType.NORMAL, 50.0, 8, loggedAt = moment)).containsKey("loggedAt")).isTrue()

        val completed = SampleData.history(moment)[0]
        assertThat(format.encodeToJsonElement(CompletedWorkout.serializer(), completed).jsonObject.containsKey("heartRateSeries")).isFalse()
        val withSeries = completed.copy(heartRateSeries = listOf(HeartRateSample(120, moment)))
        assertThat(format.encodeToJsonElement(CompletedWorkout.serializer(), withSeries).jsonObject.containsKey("heartRateSeries")).isTrue()
    }

    @Test
    fun testTheFilesOnDiskKeepTheNewFields() {
        val persistence = FileStrengthPersistence(folder.newFolder())
        val state = stateWithTimes()
        persistence.saveActiveWorkout(state)
        assertThat(persistence.loadActiveWorkout()).isEqualTo(state)

        val completed = SummaryBuilder.build(state, RedFix.at(300))
        persistence.saveHistory(listOf(completed))
        assertThat(persistence.loadHistory()).containsExactly(completed)
        assertThat(persistence.loadHistory().first().exercises.first().sets.first().loggedAt).isEqualTo(RedFix.at(100))
    }

    // endregion
}

// endregion
