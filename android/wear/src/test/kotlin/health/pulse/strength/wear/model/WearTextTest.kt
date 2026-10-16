package health.pulse.strength.wear.model

import com.google.common.truth.Truth.assertThat
import health.pulse.strength.core.SnapshotPhase
import health.pulse.strength.core.TrackingKind
import health.pulse.strength.wear.WearFixtures
import org.junit.Test

class WearTextTest {
    @Test
    fun kilogramsDropTrailingZerosAndKeepTwoDecimals() {
        assertThat(WearText.kg(85.0)).isEqualTo("85")
        assertThat(WearText.kg(82.5)).isEqualTo("82.5")
        assertThat(WearText.kg(80.25)).isEqualTo("80.25")
        assertThat(WearText.kg(80.05)).isEqualTo("80.05")
        assertThat(WearText.kg(0.0)).isEqualTo("0")
        assertThat(WearText.kg(-2.5)).isEqualTo("-2.5")
    }

    @Test
    fun aChangeInKilogramsCarriesItsSign() {
        assertThat(WearText.deltaKg(4.0)).isEqualTo("+4 kg")
        assertThat(WearText.deltaKg(-3.0)).isEqualTo("−3 kg")
        assertThat(WearText.deltaKg(2.5)).isEqualTo("+2.5 kg")
        assertThat(WearText.deltaKg(0.0)).isEqualTo("no change")
    }

    @Test
    fun theClockShowsMinutesAndFromAnHourOnHours() {
        assertThat(WearText.clock(84)).isEqualTo("1:24")
        assertThat(WearText.clock(5)).isEqualTo("0:05")
        assertThat(WearText.clock(0)).isEqualTo("0:00")
        assertThat(WearText.clock(3723)).isEqualTo("1:02:03")
        assertThat(WearText.clock(-9)).isEqualTo("0:00")
    }

    @Test
    fun theSpokenClockUsesWords() {
        assertThat(WearText.spoken(84)).isEqualTo("1 minute 24 seconds")
        assertThat(WearText.spoken(61)).isEqualTo("1 minute 1 second")
        assertThat(WearText.spoken(3600)).isEqualTo("1 hour")
        assertThat(WearText.spoken(0)).isEqualTo("0 seconds")
    }

    @Test
    fun countsAreSingularOnlyForOne() {
        assertThat(WearText.exercises(1)).isEqualTo("1 exercise")
        assertThat(WearText.exercises(6)).isEqualTo("6 exercises")
        assertThat(WearText.exercises(0)).isEqualTo("0 exercises")
    }

    @Test
    fun daysAreShortForComplicationsAndSpokenForScreenReaders() {
        assertThat(WearText.daysShort(3)).isEqualTo("3d")
        assertThat(WearText.daysShort(0)).isEqualTo("0d")
        assertThat(WearText.daysShort(null)).isEqualTo("--")
        assertThat(WearText.daysSpoken(3)).isEqualTo("Last workout 3 days ago")
        assertThat(WearText.daysSpoken(1)).isEqualTo("Last workout yesterday")
        assertThat(WearText.daysSpoken(0)).isEqualTo("Last workout today")
        assertThat(WearText.daysSpoken(null)).isEqualTo("No workouts yet")
        assertThat(WearText.daysAgo(5)).isEqualTo("5 days ago")
        assertThat(WearText.daysAgo(1)).isEqualTo("Yesterday")
        assertThat(WearText.daysAgo(0)).isEqualTo("Today")
    }

    @Test
    fun thePlanSummaryOmitsAnUnknownDuration() {
        assertThat(WearText.planSummary(6, 55)).isEqualTo("6 exercises · ~55 min")
        assertThat(WearText.planSummary(1, 0)).isEqualTo("1 exercise")
    }

    @Test
    fun theSplitBecomesOneShortWordInCapitals() {
        assertThat(WearText.splitWord("Push day")).isEqualTo("PUSH")
        assertThat(WearText.splitWord("Upper A")).isEqualTo("UPPER")
        assertThat(WearText.splitWord("Shoulders day")).isEqualTo("SHOULDE")
        assertThat(WearText.splitWord("  ")).isEqualTo("")
        assertThat(WearText.short("12345678")).hasLength(WearText.SHORT_LIMIT)
    }

    @Test
    fun theWorkTextFollowsHowTheExerciseIsTracked() {
        assertThat(WearText.work(WearFixtures.workout())).isEqualTo("80 kg × 6")
        assertThat(WearText.work(WearFixtures.workout(tracking = TrackingKind.REPS_ONLY))).isEqualTo("6 reps")
        assertThat(WearText.work(WearFixtures.workout(tracking = TrackingKind.DURATION))).isEqualTo("6 s")
    }

    @Test
    fun theNextSetLineNamesWhatFollowsTheRest() {
        assertThat(WearText.nextSet(WearFixtures.workout())).isEqualTo("Next · 80 kg × 6")
        assertThat(WearText.nextSet(WearFixtures.workout(phase = SnapshotPhase.COMPLETE))).isEqualTo("All sets logged")
    }
}
