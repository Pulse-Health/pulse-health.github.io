package health.pulse.strength.widgets.extras

import com.google.common.truth.Truth.assertThat
import health.pulse.strength.core.SnapshotPhase
import health.pulse.strength.core.TrackingKind
import health.pulse.strength.core.WorkoutSnapshot
import health.pulse.strength.widgets.WidgetFixtures
import org.junit.Test

/** Which controls the log-a-set widget (WI-02) offers for which state of the running workout. */
class LogSetModelTest {
    private val now = WidgetFixtures.now.toEpochMilli()

    private fun view(active: WorkoutSnapshot?, at: Long = now): LogSetView =
        LogSetModel.of(WidgetFixtures.preview.copy(active = active), at)

    // No workout

    @Test
    fun withoutAWorkoutTheWidgetOffersTheNextTemplate() {
        val idle = view(null) as LogSetView.Idle
        assertThat(idle.title).isEqualTo("Upper A · Push")
        assertThat(idle.detail).isEqualTo("6 exercises · ~55 min")
        assertThat(idle.canStart).isTrue()
    }

    @Test
    fun withoutAWorkoutOrATemplateThereIsNothingToStart() {
        val idle = LogSetModel.of(WidgetFixtures.empty(), now) as LogSetView.Idle
        assertThat(idle.title).isEqualTo("No workout yet")
        assertThat(idle.canStart).isFalse()
    }

    // Logging

    @Test
    fun aWeightSetOffersAWeightStepperAndARepsStepper() {
        val logging = view(WidgetFixtures.active()) as LogSetView.Logging
        assertThat(logging.exercise).isEqualTo("Bench Press")
        assertThat(logging.setLabel).isEqualTo("Set 2 of 5")
        assertThat(logging.weight).isEqualTo(StepperView("82.5 kg", "82.5", "Decrease weight", "Increase weight"))
        assertThat(logging.reps).isEqualTo(StepperView("6 reps", "6", "Fewer reps", "More reps"))
        assertThat(logging.dots).containsExactly(
            DotState.DONE,
            DotState.CURRENT,
            DotState.PENDING,
            DotState.PENDING,
            DotState.PENDING,
        ).inOrder()
        assertThat(logging.progress).containsExactly("6 of 20 sets logged", "6 of 20 sets").inOrder()
    }

    @Test
    fun aBodyweightSetOffersOnlyTheRepsStepper() {
        val logging = view(WidgetFixtures.active(tracking = TrackingKind.REPS_ONLY)) as LogSetView.Logging
        assertThat(logging.exercise).isEqualTo("Pull-up")
        assertThat(logging.weight).isNull()
        assertThat(logging.reps.label).isEqualTo("6 reps")
    }

    @Test
    fun aTimedSetAdjustsSecondsNotReps() {
        val logging = view(WidgetFixtures.active(tracking = TrackingKind.DURATION)) as LogSetView.Logging
        assertThat(logging.weight).isNull()
        assertThat(logging.reps).isEqualTo(StepperView("45 sec", "45", "Less time", "More time"))
    }

    // Resting

    @Test
    fun whileRestingTheCountdownHasTheTimeThatIsLeft() {
        val resting = view(WidgetFixtures.active(SnapshotPhase.RESTING, restRemainingSeconds = 75)) as LogSetView.Resting
        assertThat(resting.remainingMillis).isEqualTo(75_000L)
        assertThat(resting.exercise).isEqualTo("Bench Press")
        assertThat(resting.nextSet).isEqualTo("Set 3 · 82.5 kg × 6")
    }

    @Test
    fun theCountdownFollowsTheClockTheWidgetIsDrawnAt() {
        val active = WidgetFixtures.active(SnapshotPhase.RESTING, restRemainingSeconds = 75)
        assertThat((view(active, now + 15_000) as LogSetView.Resting).remainingMillis).isEqualTo(60_000L)
    }

    @Test
    fun aSnapshotThatOutlivedItsRestReadsAsRestOverNotAsANegativeCountdown() {
        val active = WidgetFixtures.active(SnapshotPhase.RESTING, restRemainingSeconds = 75)
        assertThat(view(active, now + 75_000)).isInstanceOf(LogSetView.RestOver::class.java)
        assertThat(view(active, now + 200_000)).isInstanceOf(LogSetView.RestOver::class.java)
    }

    @Test
    fun aRestWithoutAnEndIsOver() {
        val endless = WidgetFixtures.active(SnapshotPhase.RESTING).copy(restEndsAt = null)
        assertThat(view(endless)).isInstanceOf(LogSetView.RestOver::class.java)
    }

    @Test
    fun whenTheRestIsOverTheNextSetIsOffered() {
        val over = view(WidgetFixtures.active(SnapshotPhase.REST_OVER)) as LogSetView.RestOver
        assertThat(over.nextSet).isEqualTo("Set 3 · 82.5 kg × 6")
    }

    // Paused, complete

    @Test
    fun aPausedWorkoutOffersToResumeAndShowsTheFrozenRest() {
        val paused = view(WidgetFixtures.active(SnapshotPhase.RESTING, isPaused = true, restRemainingSeconds = 42)) as LogSetView.Paused
        assertThat(paused.workout).isEqualTo("Upper A · Push")
        assertThat(paused.detail).isEqualTo("Rest paused at 0:42")
    }

    @Test
    fun aPausedWorkoutWithoutARestShowsItsProgress() {
        val paused = view(WidgetFixtures.active(isPaused = true)) as LogSetView.Paused
        assertThat(paused.detail).isEqualTo("6 of 20 sets logged")
    }

    @Test
    fun aFinishedSetListOffersToOpenTheWorkout() {
        val complete = view(WidgetFixtures.active(SnapshotPhase.COMPLETE)) as LogSetView.Complete
        assertThat(complete.workout).isEqualTo("Upper A · Push")
        assertThat(complete.summary).isEqualTo("20 of 20 sets logged")
    }

    // Dots

    @Test
    fun dotsMarkLoggedCurrentAndPendingSets() {
        assertThat(LogSetModel.dots(2, 4)).containsExactly(DotState.DONE, DotState.DONE, DotState.CURRENT, DotState.PENDING).inOrder()
        assertThat(LogSetModel.dots(0, 2)).containsExactly(DotState.CURRENT, DotState.PENDING).inOrder()
    }

    @Test
    fun dotsHandleUnknownCountsAndAreCapped() {
        assertThat(LogSetModel.dots(1, null)).isEmpty()
        assertThat(LogSetModel.dots(null, 0)).isEmpty()
        assertThat(LogSetModel.dots(0, 12)).hasSize(10)
        assertThat(LogSetModel.dots(7, 5)).containsExactly(DotState.DONE, DotState.DONE, DotState.DONE, DotState.DONE, DotState.DONE)
    }

    @Test
    fun dotsShrinkToShareTheSpaceBetween8And22Dp() {
        assertThat(LogSetModel.dotWidth(5, 100f)).isEqualTo(16f)
        assertThat(LogSetModel.dotWidth(10, 100f)).isEqualTo(8f)
        assertThat(LogSetModel.dotWidth(2, 400f)).isEqualTo(22f)
        assertThat(LogSetModel.dotWidth(0, 100f)).isEqualTo(22f)
    }
}
