package health.pulse.strength.widgets.lock

import com.google.common.truth.Truth.assertThat
import org.junit.Test

/** The hand-written number and day text of the widgets: English, never locale dependent. */
class PulseFormatTest {
    @Test
    fun kilogramsKeepAtMostTwoDecimalsAndNoTrailingZeros() {
        assertThat(PulseFormat.kg(82.5)).isEqualTo("82.5")
        assertThat(PulseFormat.kg(80.0)).isEqualTo("80")
        assertThat(PulseFormat.kg(82.50001)).isEqualTo("82.5")
        assertThat(PulseFormat.kg(2.25)).isEqualTo("2.25")
        assertThat(PulseFormat.kg(1234.5)).isEqualTo("1234.5")
        assertThat(PulseFormat.kg(-2.5)).isEqualTo("-2.5")
    }

    @Test
    fun kilogramsRoundHalfAwayFromZeroAndNeverShowANegativeZero() {
        assertThat(PulseFormat.kg(0.125)).isEqualTo("0.13")
        assertThat(PulseFormat.kg(-0.125)).isEqualTo("-0.13")
        assertThat(PulseFormat.kg(0.0)).isEqualTo("0")
        assertThat(PulseFormat.kg(-0.0)).isEqualTo("0")
        assertThat(PulseFormat.kg(-0.001)).isEqualTo("0")
    }

    @Test
    fun aValueThatIsNotANumberReadsAsZero() {
        assertThat(PulseFormat.kg(Double.NaN)).isEqualTo("0")
        assertThat(PulseFormat.kg(Double.POSITIVE_INFINITY)).isEqualTo("0")
        assertThat(PulseFormat.fixed(Double.NaN)).isEqualTo("0")
    }

    @Test
    fun oneDecimalForTonnes() {
        assertThat(PulseFormat.number(186.4, 1)).isEqualTo("186.4")
        assertThat(PulseFormat.number(190.0, 1)).isEqualTo("190")
        assertThat(PulseFormat.number(0.04, 1)).isEqualTo("0")
    }

    @Test
    fun fixedKeepsTheTrailingZeros() {
        assertThat(PulseFormat.fixed(1.2)).isEqualTo("1.20")
        assertThat(PulseFormat.fixed(1.236)).isEqualTo("1.24")
        assertThat(PulseFormat.fixed(0.0)).isEqualTo("0.00")
        assertThat(PulseFormat.fixed(12.0, 0)).isEqualTo("12")
        assertThat(PulseFormat.fixed(-0.001)).isEqualTo("0.00")
    }

    @Test
    fun signedChangesUseARealMinusSign() {
        assertThat(PulseFormat.signed(2.5)).isEqualTo("+2.5")
        assertThat(PulseFormat.signed(-3.0)).isEqualTo("−3")
        assertThat(PulseFormat.signed(0.004)).isEqualTo("0")
        assertThat(PulseFormat.signed(0.0)).isEqualTo("0")
    }

    @Test
    fun aComputedWeightKeepsOneDecimalAndAPlateLoadKeepsTwo() {
        assertThat(PulseFormat.estimate(99.1666)).isEqualTo("99.2")
        assertThat(PulseFormat.estimate(99.0)).isEqualTo("99")
        assertThat(PulseFormat.estimate(99.04)).isEqualTo("99")
        assertThat(PulseFormat.kg(83.75)).isEqualTo("83.75")
        assertThat(PulseFormat.signed(4.1666, maxDecimals = 1)).isEqualTo("+4.2")
        assertThat(PulseFormat.signed(-0.04, maxDecimals = 1)).isEqualTo("0")
        assertThat(PulseFormat.signed(1.25)).isEqualTo("+1.25")
    }

    @Test
    fun setsAndDurationsRead() {
        assertThat(PulseFormat.weightReps(85.0, 5)).isEqualTo("85 × 5")
        assertThat(PulseFormat.weightReps(82.5, 6)).isEqualTo("82.5 × 6")
        assertThat(PulseFormat.minutes(55)).isEqualTo("~55 min")
        assertThat(PulseFormat.exercises(6)).isEqualTo("6 exercises")
        assertThat(PulseFormat.exercises(1)).isEqualTo("1 exercise")
    }

    @Test
    fun daysAreCountedInWordsAndShortForm() {
        assertThat(PulseFormat.daysShort(3)).isEqualTo("3d")
        assertThat(PulseFormat.daysShort(-2)).isEqualTo("0d")
        assertThat(PulseFormat.daysShort(null)).isEqualTo("–")
        assertThat(PulseFormat.daysAgo(null)).isEqualTo("Never")
        assertThat(PulseFormat.daysAgo(0)).isEqualTo("Today")
        assertThat(PulseFormat.daysAgo(1)).isEqualTo("Yesterday")
        assertThat(PulseFormat.daysAgo(5)).isEqualTo("5 days ago")
    }

    @Test
    fun clockShowsMinutesAndSecondsAndHoursFromOneHour() {
        assertThat(PulseFormat.clock(5)).isEqualTo("0:05")
        assertThat(PulseFormat.clock(72)).isEqualTo("1:12")
        assertThat(PulseFormat.clock(3723)).isEqualTo("1:02:03")
        assertThat(PulseFormat.clock(-5)).isEqualTo("0:00")
    }
}
