package health.pulse.strength.widgets.home

import com.google.common.truth.Truth.assertThat
import java.time.Instant
import java.time.ZoneId
import org.junit.Test

class HomeTextTest {
    @Test
    fun kilogramsHaveAtMostTwoDecimalsAndNoTrailingZeros() {
        assertThat(HomeText.kg(82.5)).isEqualTo("82.5")
        assertThat(HomeText.kg(80.0)).isEqualTo("80")
        assertThat(HomeText.kg(82.50001)).isEqualTo("82.5")
        assertThat(HomeText.kg(2.05)).isEqualTo("2.05")
        assertThat(HomeText.kg(0.04)).isEqualTo("0.04")
        assertThat(HomeText.kg(1234.5)).isEqualTo("1234.5")
        assertThat(HomeText.kg(-2.5)).isEqualTo("-2.5")
    }

    @Test
    fun zeroNeverCarriesASignAndNonFiniteValuesAreZero() {
        assertThat(HomeText.kg(0.0)).isEqualTo("0")
        assertThat(HomeText.kg(-0.001)).isEqualTo("0")
        assertThat(HomeText.kg(Double.NaN)).isEqualTo("0")
        assertThat(HomeText.kg(Double.POSITIVE_INFINITY)).isEqualTo("0")
    }

    @Test
    fun weightTimesRepsUsesTheMultiplicationSign() {
        assertThat(HomeText.weightReps(85.0, 5)).isEqualTo("85 × 5")
        assertThat(HomeText.weightReps(82.5, 6)).isEqualTo("82.5 × 6")
    }

    @Test
    fun spokenKilogramsAgreeWithTheNumber() {
        assertThat(HomeText.kilograms(1.0)).isEqualTo("1 kilogram")
        assertThat(HomeText.kilograms(82.5)).isEqualTo("82.5 kilograms")
        assertThat(HomeText.kilograms(0.0)).isEqualTo("0 kilograms")
    }

    @Test
    fun signedValuesUseARealMinus() {
        assertThat(HomeText.signed(2.5)).isEqualTo("+2.5")
        assertThat(HomeText.signed(-3.0)).isEqualTo("−3")
        assertThat(HomeText.signed(0.001)).isEqualTo("0")
    }

    @Test
    fun shortDayCounts() {
        assertThat(HomeText.daysShort(5)).isEqualTo("5d")
        assertThat(HomeText.daysShort(0)).isEqualTo("0d")
        assertThat(HomeText.daysShort(-2)).isEqualTo("0d")
    }

    @Test
    fun trainedWeekdaysAreNamedInWeekOrder() {
        val week = HomeFixtures.preview.week
        assertThat(HomeText.trainedWeekdays(week.days)).containsExactly("Monday", "Tuesday", "Wednesday").inOrder()
        assertThat(HomeText.trainedWeekdays(HomeFixtures.empty.week.days)).isEmpty()
    }

    @Test
    fun countsAgreeWithTheirNouns() {
        assertThat(HomeText.exercises(1)).isEqualTo("1 exercise")
        assertThat(HomeText.exercises(6)).isEqualTo("6 exercises")
        assertThat(HomeText.sessions(1)).isEqualTo("1 session")
        assertThat(HomeText.sessions(0)).isEqualTo("0 sessions")
        assertThat(HomeText.sets(1)).isEqualTo("1 set")
        assertThat(HomeText.sets(18)).isEqualTo("18 sets")
        assertThat(HomeText.minutes(55)).isEqualTo("~55 min")
    }

    @Test
    fun volumeSwitchesToTonnesAtOneThousandKilograms() {
        assertThat(HomeText.volume(8400.0)).isEqualTo("8.4 t")
        assertThat(HomeText.volume(1000.0)).isEqualTo("1 t")
        assertThat(HomeText.volume(12345.0)).isEqualTo("12.3 t")
        assertThat(HomeText.volume(850.0)).isEqualTo("850 kg")
        assertThat(HomeText.volume(999.5)).isEqualTo("999.5 kg")
        assertThat(HomeText.volume(0.0)).isEqualTo("0 kg")
    }

    @Test
    fun listsReadAsASentence() {
        assertThat(HomeText.list(emptyList())).isEmpty()
        assertThat(HomeText.list(listOf("2"))).isEqualTo("2")
        assertThat(HomeText.list(listOf("2", "5"))).isEqualTo("2 and 5")
        assertThat(HomeText.list(listOf("2", "5", "7"))).isEqualTo("2, 5 and 7")
    }

    @Test
    fun dottedSkipsBlankParts() {
        assertThat(HomeText.dotted("6 exercises", null, "~55 min")).isEqualTo("6 exercises · ~55 min")
        assertThat(HomeText.dotted(null, "")).isEmpty()
    }

    @Test
    fun eyebrowsAreUpperCaseAndWeekdaysAreEnglish() {
        assertThat(HomeText.eyebrow("Next up")).isEqualTo("NEXT UP")
        assertThat(HomeText.weekdayName(0)).isEqualTo("Monday")
        assertThat(HomeText.weekdayName(6)).isEqualTo("Sunday")
    }

    @Test
    fun calendarDaysCountLocalMidnights() {
        val berlin = ZoneId.of("Europe/Berlin")
        val late = Instant.parse("2026-10-16T23:30:00Z")
        val morning = Instant.parse("2026-10-17T09:41:00Z")
        // 23:30 UTC is already the 17th in Berlin (UTC+2): the same local day as the morning.
        assertThat(HomeDates.daysBetween(late, morning, ZoneId.of("UTC"))).isEqualTo(1)
        assertThat(HomeDates.daysBetween(late, morning, berlin)).isEqualTo(0)
        // 23:50 yesterday is one day ago, a date in the future counts as 0.
        assertThat(HomeDates.daysBetween(Instant.parse("2026-10-16T23:50:00Z"), Instant.parse("2026-10-17T00:10:00Z"), ZoneId.of("UTC"))).isEqualTo(1)
        assertThat(HomeDates.daysBetween(morning, late, ZoneId.of("UTC"))).isEqualTo(0)
    }

    @Test
    fun dayLabelsNameTheWeekdayWithinAWeekAndTheDateBeyond() {
        val utc = ZoneId.of("UTC")
        val now = Instant.parse("2026-10-17T09:41:00Z")
        assertThat(HomeDates.dayLabel(Instant.parse("2026-10-17T07:00:00Z"), now, utc)).isEqualTo("Today")
        assertThat(HomeDates.dayLabel(Instant.parse("2026-10-16T22:00:00Z"), now, utc)).isEqualTo("Yesterday")
        assertThat(HomeDates.dayLabel(Instant.parse("2026-10-14T10:02:00Z"), now, utc)).isEqualTo("Wed")
        assertThat(HomeDates.dayLabel(Instant.parse("2026-10-11T10:02:00Z"), now, utc)).isEqualTo("Sun")
        assertThat(HomeDates.dayLabel(Instant.parse("2026-10-10T10:02:00Z"), now, utc)).isEqualTo("Oct 10")
        assertThat(HomeDates.dayLabel(Instant.parse("2026-09-03T10:02:00Z"), now, utc)).isEqualTo("Sep 3")
    }

    @Test
    fun shortAndSpokenAgoPhrases() {
        assertThat(HomeDates.shortAgo(0)).isEqualTo("today")
        assertThat(HomeDates.shortAgo(1)).isEqualTo("yesterday")
        assertThat(HomeDates.shortAgo(3)).isEqualTo("3d ago")
        assertThat(HomeDates.daysAgoLower(3)).isEqualTo("3 days ago")
    }

    @Test
    fun anUnknownTimeZoneFallsBackToUtc() {
        val snapshot = HomeFixtures.preview.copy(timeZoneID = "Not/AZone")
        assertThat(HomeDates.zoneOf(snapshot)).isEqualTo(java.time.ZoneOffset.UTC)
        assertThat(HomeDates.zoneOf(HomeFixtures.preview.copy(timeZoneID = "Europe/Berlin"))).isEqualTo(ZoneId.of("Europe/Berlin"))
    }

    @Test
    fun fittedFontSizesShrinkLongTextButNeverBelowTheMinimum() {
        assertThat(HomeLayout.fittedSp("85 × 5", 118f, baseSp = 30f, minSp = 20f)).isEqualTo(30f)
        val long = HomeLayout.fittedSp("102.5 × 12", 118f, baseSp = 30f, minSp = 20f)
        assertThat(long).isLessThan(30f)
        assertThat(long).isAtLeast(20f)
        assertThat(HomeLayout.fittedSp("a very long caption indeed", 118f, baseSp = 30f, minSp = 20f)).isEqualTo(20f)
        assertThat(HomeLayout.fittedSp("", 118f, baseSp = 30f, minSp = 20f)).isEqualTo(30f)
    }

    @Test
    fun rowsThatFitAreBoundedAtBothEnds() {
        assertThat(HomeLayout.rowsThatFit(100f, 24f)).isEqualTo(4)
        assertThat(HomeLayout.rowsThatFit(100f, 24f, reserveDp = 18f)).isEqualTo(3)
        assertThat(HomeLayout.rowsThatFit(100f, 24f, max = 2)).isEqualTo(2)
        assertThat(HomeLayout.rowsThatFit(10f, 24f)).isEqualTo(0)
        assertThat(HomeLayout.rowsThatFit(10f, 24f, reserveDp = 50f)).isEqualTo(0)
    }
}
