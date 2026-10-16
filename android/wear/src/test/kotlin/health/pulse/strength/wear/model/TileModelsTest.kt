package health.pulse.strength.wear.model

import com.google.common.truth.Truth.assertThat
import health.pulse.strength.core.SnapshotPhase
import health.pulse.strength.core.widgets.HeartRateBar
import health.pulse.strength.wear.WearFixtures
import health.pulse.strength.wear.WearFixtures.now
import org.junit.Test

/** WA-03, WA-04, WA-05, WA-06, WA-08, WA-09: what each tile shows for a snapshot. */
class TileModelsTest {
    // region Next up

    @Test
    fun nextUpShowsTheSplitTheNameAndHowBigItIs() {
        val model = NextUpTileModel.of(WearFixtures.view())

        assertThat(model).isEqualTo(
            NextUpTileModel.Ready(split = "Push day", name = "Upper A · Push", detail = "6 exercises · ~55 min"),
        )
    }

    @Test
    fun nextUpWaitsForThePhoneWhileOnlyThePreviewExists() {
        assertThat(NextUpTileModel.of(WearFixtures.view(isPlaceholder = true))).isEqualTo(NextUpTileModel.Waiting)
    }

    @Test
    fun nextUpWithoutTemplatesHasNothingToStart() {
        val model = NextUpTileModel.of(WearFixtures.view(WearFixtures.preview.copy(nextUp = null)))

        assertThat(model).isEqualTo(NextUpTileModel.NoWorkout)
    }

    @Test
    fun nextUpOffersToOpenTheRunningWorkoutInsteadOfStartingAnother() {
        val model = NextUpTileModel.of(WearFixtures.view(WearFixtures.withWorkout(WearFixtures.workout())))

        assertThat(model).isEqualTo(NextUpTileModel.Running(name = "Upper A · Push", detail = "7 of 20 sets"))
    }

    // endregion

    // region Workout

    @Test
    fun theWorkoutTileOffersTheNextWorkoutWhenNoneRuns() {
        val model = WorkoutTileModel.of(WearFixtures.view(), now)

        assertThat(model).isEqualTo(WorkoutTileModel.Idle(NextUpTileModel.of(WearFixtures.view())))
    }

    @Test
    fun theWorkoutTileWaitsForThePhoneToo() {
        assertThat(WorkoutTileModel.of(WearFixtures.view(isPlaceholder = true), now)).isEqualTo(WorkoutTileModel.Waiting)
    }

    @Test
    fun loggingShowsTheExerciseTheSetAndWhatToLift() {
        val model = WorkoutTileModel.of(WearFixtures.view(WearFixtures.withWorkout(WearFixtures.workout())), now)

        assertThat(model).isEqualTo(
            WorkoutTileModel.Logging(exercise = "Bench Press", setLabel = "Set 3 of 4", work = "80 kg × 6", restOver = false),
        )
        assertThat((model as WorkoutTileModel.Logging).description).isEqualTo("Log set. Bench Press, Set 3 of 4, 80 kg × 6")
    }

    @Test
    fun restingCountsDownToTheEndOfTheRest() {
        val model = WorkoutTileModel.of(WearFixtures.view(WearFixtures.withWorkout(WearFixtures.resting(seconds = 84, total = 120))), now)

        model as WorkoutTileModel.Resting
        assertThat(model.endsAt).isEqualTo(now.plusSeconds(84))
        assertThat(model.startedAt).isEqualTo(now.minusSeconds(36))
        assertThat(model.totalSeconds).isEqualTo(120)
        assertThat(model.remainingSeconds).isEqualTo(84)
        assertThat(model.elapsedFraction).isWithin(0.001f).of(0.3f)
        assertThat(model.next).isEqualTo("Next · 80 kg × 6")
    }

    @Test
    fun whenTheRestEndsTheTileShowsTheLogSetPageWithARestOverMark() {
        val model = WorkoutTileModel.of(WearFixtures.view(WearFixtures.withWorkout(WearFixtures.resting())), now) as WorkoutTileModel.Resting

        assertThat(model.afterRest.restOver).isTrue()
        assertThat(model.afterRest.work).isEqualTo("80 kg × 6")
    }

    @Test
    fun aRestThatAlreadyRanOutCountsAsOver() {
        val snapshot = WearFixtures.withWorkout(WearFixtures.workout(phase = SnapshotPhase.RESTING, restEndsAt = now.minusSeconds(2)))

        val model = WorkoutTileModel.of(WearFixtures.view(snapshot), now)

        assertThat(model).isEqualTo(
            WorkoutTileModel.Logging(exercise = "Bench Press", setLabel = "Set 3 of 4", work = "80 kg × 6", restOver = true),
        )
    }

    @Test
    fun theRestOverPhaseIsRestOver() {
        val snapshot = WearFixtures.withWorkout(WearFixtures.workout(phase = SnapshotPhase.REST_OVER))

        val model = WorkoutTileModel.of(WearFixtures.view(snapshot), now) as WorkoutTileModel.Logging

        assertThat(model.restOver).isTrue()
    }

    @Test
    fun aRestLongerThanPlannedKeepsTheRemainingTimeAsItsLength() {
        val snapshot = WearFixtures.withWorkout(WearFixtures.resting(seconds = 150, total = 120))

        val model = WorkoutTileModel.of(WearFixtures.view(snapshot), now) as WorkoutTileModel.Resting

        assertThat(model.totalSeconds).isEqualTo(150)
        assertThat(model.elapsedFraction).isEqualTo(0f)
    }

    @Test
    fun aPausedWorkoutOffersResumeWhateverItWasDoing() {
        val snapshot = WearFixtures.withWorkout(WearFixtures.resting().copy(isPaused = true, elapsedWhenPaused = 1480))

        val model = WorkoutTileModel.of(WearFixtures.view(snapshot), now)

        assertThat(model).isEqualTo(WorkoutTileModel.Paused("Upper A · Push", 1480))
    }

    @Test
    fun afterTheLastSetOnlyOpeningTheAppRemains() {
        val snapshot = WearFixtures.withWorkout(WearFixtures.workout(phase = SnapshotPhase.COMPLETE, loggedSets = 20))

        val model = WorkoutTileModel.of(WearFixtures.view(snapshot), now)

        assertThat(model).isEqualTo(WorkoutTileModel.Complete("Upper A · Push", "20 sets logged"))
    }

    // endregion

    // region Record

    @Test
    fun aFreshRecordIsTheNewRecordCard() {
        val model = RecordTileModel.of(WearFixtures.view())

        assertThat(model).isEqualTo(
            RecordTileModel.Record(
                badge = "NEW RECORD",
                isFresh = true,
                exercise = "Bench Press",
                lift = "85 × 5",
                estimate = "e1RM 99 kg",
                improvement = "+4 kg",
            ),
        )
        assertThat((model as RecordTileModel.Record).description).isEqualTo("NEW RECORD. Bench Press, 85 × 5, e1RM 99 kg, +4 kg")
    }

    @Test
    fun anOlderRecordStaysAsTheLatestRecord() {
        val snapshot = WearFixtures.preview.copy(latestPR = WearFixtures.preview.latestPR!!.copy(isFresh = false, deltaKg = 0.0))

        val model = RecordTileModel.of(WearFixtures.view(snapshot)) as RecordTileModel.Record

        assertThat(model.badge).isEqualTo("LATEST RECORD")
        assertThat(model.isFresh).isFalse()
        assertThat(model.improvement).isNull()
    }

    @Test
    fun aRepsOnlyRecordShowsTheRepsInsteadOfAWeight() {
        val snapshot = WearFixtures.preview.copy(latestPR = WearFixtures.preview.latestPR!!.copy(weightKg = 0.0, reps = 14))

        val model = RecordTileModel.of(WearFixtures.view(snapshot)) as RecordTileModel.Record

        assertThat(model.lift).isEqualTo("14 reps")
    }

    @Test
    fun withoutRecordsAndBeforeTheFirstSyncTheTileSaysSo() {
        assertThat(RecordTileModel.of(WearFixtures.view(WearFixtures.preview.copy(latestPR = null)))).isEqualTo(RecordTileModel.NoRecords)
        assertThat(RecordTileModel.of(WearFixtures.view(isPlaceholder = true))).isEqualTo(RecordTileModel.Waiting)
    }

    // endregion

    // region Lift trend

    @Test
    fun theLiftTrendStartsWithTheMostTrainedLift() {
        val model = LiftTrendTileModel.of(WearFixtures.view(), requestedIndex = 0) as LiftTrendTileModel.Lift

        assertThat(model.name).isEqualTo("Bench Press")
        assertThat(model.current).isEqualTo("96")
        assertThat(model.summary).isEqualTo("3 sessions · −3 kg")
        assertThat(model.values).containsExactly(93.0, 99.0, 96.0).inOrder()
        assertThat(model.recordIndex).isEqualTo(1)
        assertThat(model.index).isEqualTo(0)
        assertThat(model.count).isEqualTo(5)
    }

    @Test
    fun theSelectedLiftWrapsAroundTheList() {
        val last = LiftTrendTileModel.of(WearFixtures.view(), requestedIndex = 4) as LiftTrendTileModel.Lift
        val wrapped = LiftTrendTileModel.of(WearFixtures.view(), requestedIndex = 5) as LiftTrendTileModel.Lift
        val negative = LiftTrendTileModel.of(WearFixtures.view(), requestedIndex = -1) as LiftTrendTileModel.Lift

        assertThat(last.name).isEqualTo("Deadlift")
        assertThat(wrapped.name).isEqualTo("Bench Press")
        assertThat(negative.name).isEqualTo("Deadlift")
    }

    @Test
    fun aLiftWithoutARecordHasNoGoldDot() {
        val model = LiftTrendTileModel.of(WearFixtures.view(), requestedIndex = 3) as LiftTrendTileModel.Lift

        assertThat(model.name).isEqualTo("Overhead Press")
        assertThat(model.recordIndex).isNull()
        assertThat(model.summary).isEqualTo("3 sessions · no change")
    }

    @Test
    fun aLiftWithOneSessionShowsNoChange() {
        val single = WearFixtures.preview.lifts[0].copy(points = WearFixtures.preview.lifts[0].points.take(1), sessionCount = 1, prIndex = null)
        val snapshot = WearFixtures.preview.copy(lifts = listOf(single))

        val model = LiftTrendTileModel.of(WearFixtures.view(snapshot), 0) as LiftTrendTileModel.Lift

        assertThat(model.summary).isEqualTo("1 session")
    }

    @Test
    fun withoutLiftsAndBeforeTheFirstSyncTheTileSaysSo() {
        assertThat(LiftTrendTileModel.of(WearFixtures.view(WearFixtures.preview.copy(lifts = emptyList())), 0)).isEqualTo(LiftTrendTileModel.NoLifts)
        assertThat(LiftTrendTileModel.of(WearFixtures.view(isPlaceholder = true), 0)).isEqualTo(LiftTrendTileModel.Waiting)
    }

    // endregion

    // region Heart rate

    @Test
    fun theHeartRateTileDrawsOneBarPerBucketWithTheAverageAndPeak() {
        val model = HeartRateTileModel.of(WearFixtures.view()) as HeartRateTileModel.Bars

        assertThat(model.workout).isEqualTo("Upper B · Pull")
        assertThat(model.summary).isEqualTo("avg 118 · peak 151")
        assertThat(model.bars.map { it.bpm }).containsExactly(96, 131, 104, 146, 101, 151, 108, 140).inOrder()
        assertThat(model.bars.map { it.isEffort }).containsExactly(false, true, false, true, false, true, false, true).inOrder()
    }

    @Test
    fun theTallestBarIsFullHeightAndTheShortestStaysVisible() {
        val bars = HeartRateTileModel.bars(listOf(HeartRateBar(60, false), HeartRateBar(100, true), HeartRateBar(150, true)))

        assertThat(bars.map { it.height }.max()).isWithin(0.0001f).of(1f)
        assertThat(bars.map { it.height }.min()).isAtLeast(0.2f)
        assertThat(bars.map { it.height }).isInOrder()
    }

    @Test
    fun equalBucketsAreAllFullHeight() {
        val bars = HeartRateTileModel.bars(listOf(HeartRateBar(120, false), HeartRateBar(120, true)))

        assertThat(bars.map { it.height }.toSet()).hasSize(1)
        assertThat(bars.first().height).isAtLeast(0.2f)
    }

    @Test
    fun withoutAHeartRateCurveTheTileSaysNoneWasRecorded() {
        val session = WearFixtures.preview.lastSession!!.copy(heartRateBars = emptyList())

        val model = HeartRateTileModel.of(WearFixtures.view(WearFixtures.preview.copy(lastSession = session)))

        assertThat(model).isEqualTo(HeartRateTileModel.NoData("Upper B · Pull"))
        assertThat(HeartRateTileModel.of(WearFixtures.view(WearFixtures.preview.copy(lastSession = null)))).isEqualTo(HeartRateTileModel.NoData(null))
        assertThat(HeartRateTileModel.of(WearFixtures.view(isPlaceholder = true))).isEqualTo(HeartRateTileModel.Waiting)
    }

    @Test
    fun theHeartRateDescriptionNamesEveryBucketAsEffortOrRest() {
        val model = HeartRateTileModel.of(WearFixtures.view()) as HeartRateTileModel.Bars

        assertThat(model.description).startsWith("Heart rate across Upper B · Pull, avg 118 · peak 151.")
        assertThat(model.description).contains("131 beats per minute, effort")
        assertThat(model.description).contains("96 beats per minute, rest")
    }

    // endregion
}
