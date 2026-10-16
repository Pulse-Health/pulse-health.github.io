package health.pulse.strength.wear.model

import com.google.common.truth.Truth.assertThat
import health.pulse.strength.core.SnapshotPhase
import health.pulse.strength.wear.WearFixtures
import health.pulse.strength.wear.WearFixtures.now
import org.junit.Test

/** WA-01, WA-02, WA-07, WA-10: what each complication shows for a snapshot. */
class ComplicationModelsTest {
    private val view = WearFixtures.view()
    private val waiting = WearFixtures.view(isPlaceholder = true)
    private val empty = WearFixtures.view(
        WearFixtures.preview.copy(
            nextUp = null,
            latestPR = null,
            week = WearFixtures.preview.week.copy(completed = 0, streakWeeks = 0, daysSinceLastWorkout = null, lastWorkoutAt = null),
            weeklySets = WearFixtures.preview.weeklySets.copy(totalSets = 0),
        ),
    )

    // region Weekly goal

    @Test
    fun theWeeklyGoalGaugeShowsWorkoutsAgainstTheGoalWithTheNextSplitAsItsTitle() {
        assertThat(ComplicationModels.weeklyGoalRanged(view)).isEqualTo(
            RangedContent(
                value = 3f,
                max = 4f,
                text = "3/4",
                title = "PUSH",
                description = "3 of 4 workouts this week",
            ),
        )
    }

    @Test
    fun theWeeklyGoalGaugeNeverOverflowsWhenTheGoalIsBeaten() {
        val week = WearFixtures.preview.week.copy(completed = 6)

        val content = ComplicationModels.weeklyGoalRanged(WearFixtures.view(WearFixtures.preview.copy(week = week)))

        assertThat(content.value).isEqualTo(4f)
        assertThat(content.text).isEqualTo("6/4")
    }

    @Test
    fun theWeeklyGoalTextIsThreeOfFour() {
        assertThat(ComplicationModels.weeklyGoalText(view)).isEqualTo(
            TextContent(text = "3/4", title = "WEEK", description = "3 of 4 workouts this week"),
        )
    }

    @Test
    fun theWeeklyGoalWithoutHistoryIsZeroOfTheGoalWithNoTitle() {
        assertThat(ComplicationModels.weeklyGoalRanged(empty).value).isEqualTo(0f)
        assertThat(ComplicationModels.weeklyGoalRanged(empty).text).isEqualTo("0/4")
        assertThat(ComplicationModels.weeklyGoalRanged(empty).title).isNull()
    }

    // endregion

    // region Days since

    @Test
    fun daysSinceIsThreeDAgo() {
        assertThat(ComplicationModels.daysSince(view)).isEqualTo(
            TextContent(text = "3d", title = "ago", description = "Last workout 3 days ago"),
        )
    }

    @Test
    fun daysSinceWithoutHistoryHasNoNumber() {
        assertThat(ComplicationModels.daysSince(empty)).isEqualTo(
            TextContent(text = "--", title = null, description = "No workouts yet"),
        )
    }

    // endregion

    // region Next up

    @Test
    fun nextUpNamesTheWorkoutAndItsSize() {
        assertThat(ComplicationModels.nextUpLong(view)).isEqualTo(
            TextContent(
                text = "Upper A · Push",
                title = "6 exercises",
                description = "Next up: Upper A · Push, 6 exercises · ~55 min",
            ),
        )
    }

    @Test
    fun nextUpAsShortTextIsTheSplitReminder() {
        val content = ComplicationModels.nextUpShort(view)

        assertThat(content.text).isEqualTo("PUSH")
        assertThat(content.title).isEqualTo("5d ago")
        assertThat(content.description).isEqualTo("Next up: Push day, last done 5 days ago")
    }

    @Test
    fun nextUpShowsTheRunningWorkoutWhileOneRuns() {
        val running = WearFixtures.view(WearFixtures.withWorkout(WearFixtures.workout()))

        val long = ComplicationModels.nextUpLong(running)
        val short = ComplicationModels.nextUpShort(running)

        assertThat(long.text).isEqualTo("Upper A · Push")
        assertThat(long.title).isEqualTo("7 of 20 sets")
        assertThat(short.text).isEqualTo("7/20")
        assertThat(short.title).isEqualTo("SETS")
    }

    @Test
    fun nextUpWithoutTemplatesAsksForOne() {
        assertThat(ComplicationModels.nextUpLong(empty).text).isEqualTo("No workout planned")
        assertThat(ComplicationModels.nextUpLong(empty).title).isEqualTo("Add one on your phone")
        assertThat(ComplicationModels.nextUpShort(empty).text).isEqualTo("--")
    }

    // endregion

    // region Start

    @Test
    fun startBeginsTheNextWorkout() {
        assertThat(ComplicationModels.start(view)).isEqualTo(
            TextContent(text = "Start", title = null, description = "Start Upper A · Push", glyph = Glyph.PLAY, tap = Tap.START_NEXT),
        )
    }

    @Test
    fun startOpensTheAppWhenThereIsNothingToStart() {
        assertThat(ComplicationModels.start(empty).tap).isEqualTo(Tap.OPEN_APP)
        assertThat(ComplicationModels.start(waiting).tap).isEqualTo(Tap.OPEN_APP)
        val running = ComplicationModels.start(WearFixtures.view(WearFixtures.withWorkout(WearFixtures.workout())))
        assertThat(running.tap).isEqualTo(Tap.OPEN_APP)
        assertThat(running.text).isEqualTo("Open")
    }

    // endregion

    // region Streak and weekly sets

    @Test
    fun theStreakIsSixWeeksWithAFlame() {
        assertThat(ComplicationModels.streak(view)).isEqualTo(
            TextContent(text = "6wk", title = null, description = "6 week streak", glyph = Glyph.FLAME),
        )
        assertThat(ComplicationModels.streak(empty).text).isEqualTo("0wk")
        assertThat(ComplicationModels.streak(WearFixtures.view(WearFixtures.preview.copy(week = WearFixtures.preview.week.copy(streakWeeks = 1)))).description)
            .isEqualTo("1 week streak")
    }

    @Test
    fun weeklySetsShowsWorkingSetsAgainstTheTarget() {
        assertThat(ComplicationModels.weeklySets(view)).isEqualTo(
            RangedContent(value = 37f, max = 48f, text = "37", title = "SETS", description = "37 of 48 working sets this week"),
        )
        assertThat(ComplicationModels.weeklySets(empty).value).isEqualTo(0f)
    }

    @Test
    fun weeklySetsBeyondTheTargetFillTheGaugeButKeepTheTrueCount() {
        val sets = WearFixtures.preview.weeklySets.copy(totalSets = 55)

        val content = ComplicationModels.weeklySets(WearFixtures.view(WearFixtures.preview.copy(weeklySets = sets)))

        assertThat(content.value).isEqualTo(48f)
        assertThat(content.text).isEqualTo("55")
    }

    // endregion

    // region Waiting for the phone

    @Test
    fun beforeTheFirstSyncEveryComplicationSaysItIsWaiting() {
        assertThat(ComplicationModels.weeklyGoalRanged(waiting).description).isEqualTo("Waiting for your phone")
        assertThat(ComplicationModels.weeklyGoalText(waiting).text).isEqualTo("--")
        assertThat(ComplicationModels.daysSince(waiting).text).isEqualTo("--")
        assertThat(ComplicationModels.nextUpLong(waiting).text).isEqualTo("Waiting for your phone")
        assertThat(ComplicationModels.nextUpShort(waiting).text).isEqualTo("--")
        assertThat(ComplicationModels.start(waiting).description).isEqualTo("Waiting for your phone")
        assertThat(ComplicationModels.streak(waiting).text).isEqualTo("--")
        assertThat(ComplicationModels.weeklySets(waiting).text).isEqualTo("--")
    }

    // endregion

    // region Rest

    @Test
    fun noRestRunsWhenNoWorkoutDoesOrASetIsDue() {
        assertThat(RestContent.of(view, now)).isEqualTo(RestContent.Idle)
        assertThat(RestContent.of(WearFixtures.view(WearFixtures.withWorkout(WearFixtures.workout())), now)).isEqualTo(RestContent.Idle)
        assertThat(RestContent.of(WearFixtures.view(WearFixtures.withWorkout(WearFixtures.workout(phase = SnapshotPhase.COMPLETE))), now))
            .isEqualTo(RestContent.Idle)
        assertThat(RestContent.of(waiting, now)).isEqualTo(RestContent.Waiting)
    }

    @Test
    fun aRunningRestCountsDownToItsEnd() {
        val state = RestContent.of(WearFixtures.view(WearFixtures.withWorkout(WearFixtures.resting(seconds = 84, total = 120))), now)

        assertThat(state).isEqualTo(
            RestContent.Counting(startedAt = now.minusSeconds(36), endsAt = now.plusSeconds(84), totalSeconds = 120, remainingSeconds = 84),
        )
    }

    @Test
    fun aRestThatRanOutIsOver() {
        val ranOut = WearFixtures.workout(phase = SnapshotPhase.RESTING, restEndsAt = now.minusSeconds(1))

        assertThat(RestContent.of(WearFixtures.view(WearFixtures.withWorkout(ranOut)), now)).isEqualTo(RestContent.Over)
        assertThat(RestContent.of(WearFixtures.view(WearFixtures.withWorkout(WearFixtures.workout(phase = SnapshotPhase.REST_OVER))), now))
            .isEqualTo(RestContent.Over)
    }

    @Test
    fun aPausedRestIsFrozenAtItsRemainingTime() {
        val paused = WearFixtures.resting().copy(isPaused = true, restFrozenRemaining = 61)

        assertThat(RestContent.of(WearFixtures.view(WearFixtures.withWorkout(paused)), now)).isEqualTo(RestContent.Frozen(61, 120))
    }

    // endregion
}
