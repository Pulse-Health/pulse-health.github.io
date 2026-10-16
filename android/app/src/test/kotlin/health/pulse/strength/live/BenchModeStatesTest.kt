package health.pulse.strength.live

import com.google.common.truth.Truth.assertThat
import health.pulse.strength.core.TrackingKind
import health.pulse.strength.core.WorkoutSnapshot
import health.pulse.strength.core.widgets.TomorrowPlan
import java.time.LocalTime
import org.junit.Test

/** SB-02 / SB-04: what bench mode shows for every state of the snapshot, and when the night look is on. */
class BenchModeStatesTest {
    private fun state(snapshot: WorkoutSnapshot?, is24Hour: Boolean = true) =
        BenchModeStates.of(previewWith(snapshot), NOW, is24Hour)

    @Test
    fun restingShowsTheRingAndTheNextSet() {
        val s = state(restingSnapshot(remaining = 84)) as BenchState.Resting
        assertThat(s.exercise).isEqualTo("Bench Press")
        assertThat(s.remainingSeconds).isEqualTo(84)
        assertThat(s.totalSeconds).isEqualTo(120)
        assertThat(s.fraction).isWithin(0.0001f).of(0.7f)
        assertThat(s.next).isEqualTo(NextSet("Set 4", "82.5 kg × 6"))
    }

    @Test
    fun theRingNeverLeavesItsRange() {
        assertThat(BenchState.Resting("x", 10, 0, NextSet("Set 1", null)).fraction).isEqualTo(0f)
        assertThat(BenchState.Resting("x", 200, 120, NextSet("Set 1", null)).fraction).isEqualTo(1f)
        assertThat(BenchState.Resting("x", -5, 120, NextSet("Set 1", null)).fraction).isEqualTo(0f)
    }

    @Test
    fun aRestWhoseTimeRanOutIsGo() {
        assertThat(state(restingSnapshot(remaining = -1))).isInstanceOf(BenchState.RestOver::class.java)
    }

    @Test
    fun theNextSetSplitsAtTheMiddleDot() {
        assertThat(NextSet.of("Set 4 · 82.5 kg × 6")).isEqualTo(NextSet("Set 4", "82.5 kg × 6"))
        assertThat(NextSet.of("Warm-up · 50 kg × 8")).isEqualTo(NextSet("Warm-up", "50 kg × 8"))
        assertThat(NextSet.of("All sets logged")).isEqualTo(NextSet("All sets logged", null))
    }

    @Test
    fun loggingShowsTheWeightAndTheReps() {
        val s = state(loggingSnapshot()) as BenchState.Logging
        assertThat(s).isEqualTo(BenchState.Logging("Bench Press", "Set 4 of 5", "82.5", "6", "reps"))
    }

    @Test
    fun anExerciseWithoutWeightShowsOnlyTheReps() {
        val reps = state(loggingSnapshot().copy(tracking = TrackingKind.REPS_ONLY, showsWeight = false, weightText = "BW")) as BenchState.Logging
        assertThat(reps.weight).isNull()
        assertThat(reps.repsUnit).isEqualTo("reps")
        val seconds = state(loggingSnapshot().copy(tracking = TrackingKind.DURATION, showsWeight = false, weightText = "–", repsText = "45")) as BenchState.Logging
        assertThat(seconds.weight).isNull()
        assertThat(seconds.repsUnit).isEqualTo("s")
    }

    @Test
    fun pausedShowsTheFrozenClock() {
        assertThat(state(pausedSnapshot())).isEqualTo(BenchState.Paused("Bench Press", "24:18"))
    }

    @Test
    fun completeShowsTheTotalsOrWhatToDo() {
        assertThat(state(completeSnapshot())).isEqualTo(BenchState.Complete("All sets logged", "20 of 20 sets · 4,980 kg"))
        assertThat(state(completeSnapshot().copy(totalSets = 0, exerciseCount = 0)))
            .isEqualTo(BenchState.Complete("No exercises yet", "Add exercises in Pulse Strength"))
        assertThat(state(completeSnapshot().copy(totalSets = 0, exerciseCount = 2)))
            .isEqualTo(BenchState.Complete("No sets yet", "Add sets in Pulse Strength"))
    }

    // region SB-04 no workout

    @Test
    fun withoutAWorkoutTomorrowsSessionIsShownBesideTheClock() {
        val s = state(null) as BenchState.Idle
        assertThat(s.headline).isEqualTo("Morning session")
        assertThat(s.title).isEqualTo("Lower A · Quads")
        assertThat(s.detail).isEqualTo("Planned 7:00 · Gym bag ready?")
    }

    @Test
    fun theTimeFollowsThePhonesClockStyle() {
        assertThat((state(null, is24Hour = false) as BenchState.Idle).detail).isEqualTo("Planned 7:00 AM · Gym bag ready?")
        val evening = previewWith(null).copy(tomorrow = TomorrowPlan("Lower A", plannedMinuteOfDay = 18 * 60 + 5, weekday = "Sunday"))
        val s = BenchModeStates.of(evening, NOW, is24Hour = false) as BenchState.Idle
        assertThat(s.headline).isEqualTo("Evening session")
        assertThat(s.detail).isEqualTo("Planned 6:05 PM · Gym bag ready?")
    }

    @Test
    fun withoutAPlannedTimeTheHeadlineNamesTheDay() {
        val plan = previewWith(null).copy(tomorrow = TomorrowPlan("Lower A", plannedMinuteOfDay = null, weekday = "Sunday", note = ""))
        val s = BenchModeStates.of(plan, NOW, is24Hour = true) as BenchState.Idle
        assertThat(s.headline).isEqualTo("Sunday session")
        assertThat(s.detail).isNull()
    }

    @Test
    fun withoutTomorrowTheNextTemplateIsShownAndWithoutThatAHint() {
        val next = BenchModeStates.of(previewWith(null).copy(tomorrow = null), NOW, true) as BenchState.Idle
        assertThat(next).isEqualTo(BenchState.Idle("Next up", "Upper A · Push", "6 exercises · about 55 min"))
        val none = BenchModeStates.of(previewWith(null).copy(tomorrow = null, nextUp = null), NOW, true) as BenchState.Idle
        assertThat(none).isEqualTo(BenchState.Idle("No workout planned", null, "Plan your next session in Pulse Strength"))
    }

    @Test
    fun aFinishedWorkoutIsShownAsNoWorkout() {
        assertThat(state(loggingSnapshot().copy(finish = finishBrief()))).isInstanceOf(BenchState.Idle::class.java)
    }

    @Test
    fun theNightLookIsOnFrom22To06UnlessForced() {
        assertThat(BenchModeStates.isNight(null, LocalTime.of(22, 0))).isTrue()
        assertThat(BenchModeStates.isNight(null, LocalTime.of(23, 59))).isTrue()
        assertThat(BenchModeStates.isNight(null, LocalTime.of(0, 0))).isTrue()
        assertThat(BenchModeStates.isNight(null, LocalTime.of(5, 59))).isTrue()
        assertThat(BenchModeStates.isNight(null, LocalTime.of(6, 0))).isFalse()
        assertThat(BenchModeStates.isNight(null, LocalTime.of(12, 0))).isFalse()
        assertThat(BenchModeStates.isNight(null, LocalTime.of(21, 59))).isFalse()
        assertThat(BenchModeStates.isNight(true, LocalTime.of(12, 0))).isTrue()
        assertThat(BenchModeStates.isNight(false, LocalTime.of(23, 0))).isFalse()
    }

    // endregion

    @Test
    fun theClockTextHasBothStyles() {
        assertThat(LiveText.timeParts(0, is24Hour = false)).isEqualTo("12:00" to "AM")
        assertThat(LiveText.timeParts(12 * 60 + 30, is24Hour = false)).isEqualTo("12:30" to "PM")
        assertThat(LiveText.timeParts(13 * 60 + 5, is24Hour = false)).isEqualTo("1:05" to "PM")
        assertThat(LiveText.timeParts(6 * 60 + 12, is24Hour = true)).isEqualTo("6:12" to null)
        assertThat(LiveText.timeOfDay(7 * 60, is24Hour = false)).isEqualTo("7:00 AM")
        assertThat(LiveText.timeOfDay(25 * 60, is24Hour = true)).isEqualTo("1:00")
    }

    @Test
    fun aDurationIsSpokenInWords() {
        assertThat(spokenDuration(84)).isEqualTo("1 minute 24 seconds")
        assertThat(spokenDuration(120)).isEqualTo("2 minutes")
        assertThat(spokenDuration(1)).isEqualTo("1 second")
        assertThat(spokenDuration(0)).isEqualTo("0 seconds")
    }
}
