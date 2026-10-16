package health.pulse.strength.core.widgets

import com.google.common.truth.Truth.assertThat
import com.google.common.truth.Truth.assertWithMessage
import health.pulse.strength.core.StrengthData
import java.time.Duration
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZoneOffset
import org.junit.Test

/** widgets/SPEC.md section 2, "Calendar": days and weeks in the snapshot's time zone. */
class WidgetCalendarTests {
    private fun calendar(zone: String): WidgetCalendar = WidgetCalendar(ZoneId.of(zone))

    // region Civil dates

    @Test
    fun testCivilDatesAndDayNumbersAreInverseForAWideRangeOfDays() {
        for (day in -800_000L..800_000L step 37) {
            val civil = WidgetCalendar.civil(day)
            assertWithMessage("day $day").that(WidgetCalendar.dayNumber(civil.year, civil.monthValue, civil.dayOfMonth)).isEqualTo(day)
            assertThat(civil.monthValue).isIn(1..12)
            assertThat(civil.dayOfMonth).isIn(1..WidgetCalendar.daysInMonth(civil.year, civil.monthValue))
        }
    }

    @Test
    fun testTheWeekdayIndexAgreesWithJavaTimeAndMondayIsZero() {
        for (day in 0L..60_000L step 101) {
            assertWithMessage("weekday of day $day").that(WidgetCalendar.weekdayIndex(day)).isEqualTo(LocalDate.ofEpochDay(day).dayOfWeek.value - 1)
        }
    }

    @Test
    fun testKnownDays() {
        assertThat(WidgetCalendar.dayNumber(1970, 1, 1)).isEqualTo(0)
        assertWithMessage("1970-01-01 was a Thursday").that(WidgetCalendar.weekdayIndex(0)).isEqualTo(3)
        val friday = WidgetCalendar.dayNumber(2026, 10, 16)
        assertThat(friday).isEqualTo(20_742)
        assertThat(WidgetCalendar.weekdayIndex(friday)).isEqualTo(4)
        assertThat(WidgetCalendar.mondayOnOrBefore(friday)).isEqualTo(WidgetCalendar.dayNumber(2026, 10, 12))
        val monday = WidgetCalendar.dayNumber(2026, 10, 12)
        assertWithMessage("a Monday starts its own week").that(WidgetCalendar.mondayOnOrBefore(monday)).isEqualTo(monday)
        assertWithMessage("Sunday belongs to the week before").that(WidgetCalendar.mondayOnOrBefore(monday - 1)).isEqualTo(monday - 7)
        assertWithMessage("1969-12-31 was a Wednesday").that(WidgetCalendar.weekdayIndex(-1)).isEqualTo(2)
    }

    @Test
    fun testMonthLengthsIncludingLeapYears() {
        assertThat((1..12).map { WidgetCalendar.daysInMonth(2026, it) }).containsExactly(31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31).inOrder()
        assertThat(WidgetCalendar.daysInMonth(2024, 2)).isEqualTo(29)
        assertThat(WidgetCalendar.daysInMonth(2100, 2)).isEqualTo(28)
        assertThat(WidgetCalendar.daysInMonth(2000, 2)).isEqualTo(29)
    }

    @Test
    fun testDayOfYear() {
        assertThat(WidgetCalendar.dayOfYear(WidgetCalendar.dayNumber(2026, 1, 1))).isEqualTo(1)
        assertThat(WidgetCalendar.dayOfYear(WidgetCalendar.dayNumber(2026, 10, 16))).isEqualTo(289)
        assertThat(WidgetCalendar.dayOfYear(WidgetCalendar.dayNumber(2026, 12, 31))).isEqualTo(365)
        assertThat(WidgetCalendar.dayOfYear(WidgetCalendar.dayNumber(2024, 12, 31))).isEqualTo(366)
    }

    @Test
    fun testNamesAreEnglishAndMondayFirst() {
        assertThat(WidgetCalendar.weekdayLetters).containsExactly("M", "T", "W", "T", "F", "S", "S").inOrder()
        assertThat(WidgetCalendar.weekdayNames.first()).isEqualTo("Monday")
        assertThat(WidgetCalendar.weekdayNames.last()).isEqualTo("Sunday")
        assertThat(WidgetCalendar.monthNames).hasSize(12)
        assertThat(WidgetCalendar.monthNames[9]).isEqualTo("October")
    }

    // endregion

    // region Local days

    @Test
    fun testADayIsTheLocalDateNotTheUTCDate() {
        val instant = WidFix.date(2026, 10, 16, 11, 30) // 2026-10-16T11:30:00Z
        assertThat(calendar("UTC").day(instant)).isEqualTo(20_742)
        assertWithMessage("00:30 on the 17th in New Zealand (UTC+13)").that(calendar("Pacific/Auckland").day(instant)).isEqualTo(20_743)
        assertWithMessage("04:30 on the 16th in California (UTC-7)").that(calendar("America/Los_Angeles").day(instant)).isEqualTo(20_742)
        assertWithMessage("20:00 on the 15th in California")
            .that(calendar("America/Los_Angeles").day(WidFix.date(2026, 10, 16, 3, 0)))
            .isEqualTo(20_741)
    }

    @Test
    fun testDaysBetweenCountsTheLocalMidnightsCrossed() {
        val utc = calendar("UTC")
        val today = WidFix.date(2026, 10, 16, 9, 41)
        assertWithMessage("23:50 yesterday is 1 day ago").that(utc.daysBetween(WidFix.date(2026, 10, 15, 23, 50), today)).isEqualTo(1)
        assertThat(utc.daysBetween(WidFix.date(2026, 10, 16, 0, 0), today)).isEqualTo(0)
        assertThat(utc.daysBetween(WidFix.date(2026, 10, 16, 9, 40), today)).isEqualTo(0)
        assertThat(utc.daysBetween(WidFix.date(2026, 10, 13, 9, 41), today)).isEqualTo(3)
        assertWithMessage("two minutes apart, one midnight")
            .that(utc.daysBetween(WidFix.date(2026, 10, 13, 23, 59), WidFix.date(2026, 10, 14, 0, 1)))
            .isEqualTo(1)
        assertWithMessage("a date in the future counts as 0").that(utc.daysBetween(WidFix.date(2026, 10, 17, 9, 41), today)).isEqualTo(0)
        assertThat(utc.daysBetween(today, today)).isEqualTo(0)
    }

    @Test
    fun testDaysBetweenFollowsTheZoneOfTheSnapshot() {
        val earlier = WidFix.date(2026, 10, 15, 22, 0) // 15 Oct 22:00Z
        val later = WidFix.date(2026, 10, 16, 1, 0) // 16 Oct 01:00Z
        assertThat(calendar("UTC").daysBetween(earlier, later)).isEqualTo(1)
        assertWithMessage("both are the 16th in New Zealand (UTC+13)").that(calendar("Pacific/Auckland").daysBetween(earlier, later)).isEqualTo(0)
    }

    @Test
    fun testAnInstantTooFarFromTheEpochCountsAsTheEpochDay() {
        assertThat(calendar("UTC").day(Instant.MAX)).isEqualTo(0)
        assertThat(calendar("Europe/Berlin").day(Instant.MIN)).isEqualTo(0)
        assertThat(calendar("UTC").minuteOfDay(Instant.MAX)).isEqualTo(0)
        assertThat(calendar("UTC").daysBetween(Instant.MIN, Instant.MAX)).isEqualTo(0)
    }

    // endregion

    // region Start of day and daylight saving

    @Test
    fun testStartOfDayIsLocalMidnight() {
        assertThat(calendar("UTC").startOfDay(20_742)).isEqualTo(WidFix.date(2026, 10, 16))
        assertThat(calendar("Pacific/Auckland").startOfDay(20_742)).isEqualTo(WidFix.date(2026, 10, 16, zone = "Pacific/Auckland"))
        assertThat(calendar("America/Los_Angeles").startOfDay(20_742)).isEqualTo(WidFix.date(2026, 10, 16, zone = "America/Los_Angeles"))
        assertThat(calendar("Asia/Kolkata").startOfDay(20_742)).isEqualTo(WidFix.date(2026, 10, 16, zone = "Asia/Kolkata"))
    }

    @Test
    fun testADaylightSavingDayIsOneDayLongAndStillBucketsCorrectly() {
        val berlin = calendar("Europe/Berlin")
        val day = WidgetCalendar.dayNumber(2026, 10, 25) // clocks go back at 03:00: a 25 hour day
        assertThat(Duration.between(berlin.startOfDay(day), berlin.startOfDay(day + 1))).isEqualTo(Duration.ofHours(25))
        assertThat(berlin.day(WidFix.date(2026, 10, 25, 0, 30, zone = "Europe/Berlin"))).isEqualTo(day)
        assertThat(berlin.day(WidFix.date(2026, 10, 25, 23, 59, 59, zone = "Europe/Berlin"))).isEqualTo(day)
        assertThat(berlin.day(WidFix.date(2026, 10, 26, 0, 0, zone = "Europe/Berlin"))).isEqualTo(day + 1)
        val spring = WidgetCalendar.dayNumber(2026, 3, 29) // clocks go forward: a 23 hour day
        assertThat(Duration.between(berlin.startOfDay(spring), berlin.startOfDay(spring + 1))).isEqualTo(Duration.ofHours(23))

        val losAngeles = calendar("America/Los_Angeles")
        val fall = WidgetCalendar.dayNumber(2026, 11, 1)
        assertThat(Duration.between(losAngeles.startOfDay(fall), losAngeles.startOfDay(fall + 1))).isEqualTo(Duration.ofHours(25))
        val crossed = losAngeles.daysBetween(
            WidFix.date(2026, 10, 31, 23, 0, zone = "America/Los_Angeles"),
            WidFix.date(2026, 11, 2, 0, 30, zone = "America/Los_Angeles"),
        )
        assertThat(crossed).isEqualTo(2)
    }

    @Test
    fun testMinuteOfDayIsLocal() {
        val instant = WidFix.date(2026, 10, 16, 11, 30)
        assertThat(calendar("UTC").minuteOfDay(instant)).isEqualTo(11 * 60 + 30)
        assertWithMessage("00:30 local").that(calendar("Pacific/Auckland").minuteOfDay(instant)).isEqualTo(30)
        assertThat(calendar("America/Los_Angeles").minuteOfDay(instant)).isEqualTo(4 * 60 + 30)
        assertThat(calendar("UTC").minuteOfDay(WidFix.date(2026, 10, 16, 23, 59, 59))).isEqualTo(1_439)
        assertThat(calendar("UTC").minuteOfDay(WidFix.date(2026, 10, 16, 0, 0, 0))).isEqualTo(0)
    }

    @Test
    fun testTheSnapshotReportsTheZoneItWasBuiltIn() {
        assertThat(WidFix.snapshot(StrengthData(), WidFix.context("Pacific/Auckland")).timeZoneID).isEqualTo("Pacific/Auckland")
        assertThat(WidFix.snapshot(StrengthData(), WidFix.context("UTC")).timeZoneID).isEqualTo("UTC")
        assertWithMessage("the zone offset Z is reported as UTC")
            .that(WidFix.snapshot(StrengthData(), WidgetContext(zone = ZoneOffset.UTC)).timeZoneID)
            .isEqualTo("UTC")
    }

    // endregion
}

/** widgets/SPEC.md section 2: initials(name) and the labels cut out of template names. */
class WidgetNameRuleTests {
    @Test
    fun testInitialsOfTwoOrMoreTokensAreTheFirstCharacterOfTheFirstTwo() {
        assertWithMessage("the dot has no letter or digit and is dropped").that(WidgetText.initials("Upper A · Push")).isEqualTo("UA")
        assertThat(WidgetText.initials("Lower A · Quads")).isEqualTo("LA")
        assertWithMessage("upper case").that(WidgetText.initials("push day")).isEqualTo("PD")
        assertThat(WidgetText.initials("Full Body Workout")).isEqualTo("FB")
    }

    @Test
    fun testInitialsOfOneTokenAreItsFirstTwoCharacters() {
        assertThat(WidgetText.initials("Legs")).isEqualTo("LE")
        assertThat(WidgetText.initials("x")).isEqualTo("X")
        assertThat(WidgetText.initials("  Pull  ")).isEqualTo("PU")
        assertWithMessage("only one token is left").that(WidgetText.initials("· Push ·")).isEqualTo("PU")
    }

    @Test
    fun testInitialsWithoutAnyTokenAreWO() {
        assertThat(WidgetText.initials("")).isEqualTo("WO")
        assertThat(WidgetText.initials("   ")).isEqualTo("WO")
        assertThat(WidgetText.initials("· - ·")).isEqualTo("WO")
    }

    @Test
    fun testInitialsKeepDigitsAndSplitOnAnyWhitespace() {
        assertThat(WidgetText.initials("5x5 Strength")).isEqualTo("5S")
        assertThat(WidgetText.initials("Upper\tB\nPull")).isEqualTo("UB")
        assertThat(WidgetText.initials("Ärm Tag")).isEqualTo("ÄT")
    }

    @Test
    fun testInitialsTakeWholeCharactersNotHalvesOfASurrogatePair() {
        assertThat(WidgetText.initials("𝐀bc Def")).isEqualTo("𝐀D")
        assertThat(WidgetText.initials("𝐀𝐁c")).isEqualTo("𝐀𝐁")
    }

    @Test
    fun testSplitLabelIsTheTextAfterTheLastDotPlusDay() {
        assertThat(WidgetText.splitLabel("Upper A · Push")).isEqualTo("Push day")
        assertWithMessage("the last dot").that(WidgetText.splitLabel("Upper · A · Pull ")).isEqualTo("Pull day")
        assertWithMessage("without a dot it is the name").that(WidgetText.splitLabel("Full body")).isEqualTo("Full body")
        assertWithMessage("nothing after the dot: the name").that(WidgetText.splitLabel("Legs ·")).isEqualTo("Legs ·")
        assertThat(WidgetText.splitLabel("Legs ·   ")).isEqualTo("Legs ·   ")
    }

    @Test
    fun testRowLabelIsTheTextAfterTheDotOrTheName() {
        assertThat(WidgetText.rowLabel("Lower A · Quads")).isEqualTo("Quads")
        assertThat(WidgetText.rowLabel("Cardio")).isEqualTo("Cardio")
    }

    @Test
    fun testShortNameIsTheNameUpToTheFirstSpaceDot() {
        assertThat(WidgetText.shortName("Lower A · Quads")).isEqualTo("Lower A")
        assertThat(WidgetText.shortName("A · B · C")).isEqualTo("A")
        assertThat(WidgetText.shortName("Cardio")).isEqualTo("Cardio")
        assertWithMessage("an empty start falls back to the name").that(WidgetText.shortName(" · Odd")).isEqualTo(" · Odd")
    }

    @Test
    fun testRoundingHelpers() {
        assertThat(WidgetText.tenth(99.1666)).isEqualTo(99.2)
        assertThat(WidgetText.tenth(58.36)).isEqualTo(58.4)
        assertThat(WidgetText.tenth(58.34)).isEqualTo(58.3)
        assertThat(WidgetText.tenth(-3.2000000000000028)).isEqualTo(-3.2)
        assertThat(WidgetText.hundredth(1.2399)).isEqualTo(1.24)
        assertThat(WidgetText.hundredth(1.2451)).isEqualTo(1.25)
        assertThat(WidgetText.hundredth(1.2449)).isEqualTo(1.24)
        assertThat(WidgetText.platesText(listOf(25.0, 5.0, 2.5))).isEqualTo("25 + 5 + 2.5")
        assertThat(WidgetText.platesText(emptyList())).isEqualTo("")
    }
}
