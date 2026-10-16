package health.pulse.strength.ui.detail

import com.google.common.truth.Truth.assertThat
import health.pulse.strength.core.E1RMPoint
import health.pulse.strength.core.addingTimeInterval
import java.time.Instant
import java.time.ZoneId
import org.junit.Test

/** The numbers and texts behind the exercise detail: pure Kotlin, no UI. */
class ExerciseDetailModelTest {
    private val utc: ZoneId = ZoneId.of("UTC")
    private val now: Instant = Instant.parse("2026-01-12T18:30:00Z")

    private fun daysAgo(days: Double): Instant = now.addingTimeInterval(-days * 86_400)

    private fun point(daysAgo: Double, value: Double) = E1RMPoint(daysAgo(daysAgo), value)

    private fun progress(range: ExerciseDetailRange, vararg points: E1RMPoint) =
        ExerciseDetailProgress(points.toList(), range, now, utc)

    // region Axis

    @Test
    fun axisUsesTwoGridIntervalsAtMost() {
        val axis = ExerciseDetailAxis.make(listOf(93.0, 99.17, 96.0))
        assertThat(axis.lower).isEqualTo(90.0)
        assertThat(axis.upper).isEqualTo(100.0)
        assertThat(axis.ticks).containsExactly(90.0, 95.0, 100.0).inOrder()
    }

    @Test
    fun axisWithoutValuesIsZeroToHundred() {
        val axis = ExerciseDetailAxis.make(emptyList())
        assertThat(axis.ticks).containsExactly(0.0, 50.0, 100.0).inOrder()
    }

    @Test
    fun axisAroundASingleValueIsCentredOnIt() {
        val axis = ExerciseDetailAxis.make(listOf(80.0))
        assertThat(axis.lower).isEqualTo(77.5)
        assertThat(axis.upper).isEqualTo(82.5)
        assertThat(axis.ticks).containsExactly(77.5, 80.0, 82.5).inOrder()
    }

    @Test
    fun axisForAWideRangePicksACoarseStep() {
        val axis = ExerciseDetailAxis.make(listOf(20.0, 140.0))
        // 120 kg of spread needs steps of 100 or more.
        assertThat(axis.ticks.first()).isAtMost(20.0)
        assertThat(axis.ticks.last()).isAtLeast(140.0)
        assertThat(axis.ticks.size).isAtMost(3)
    }

    // endregion

    // region Span

    @Test
    fun spanIsInDaysBelowAWeekAndInWeeksFromThen() {
        assertThat(ExerciseDetailSpan(daysAgo(5.0), now).short).isEqualTo("5 d")
        assertThat(ExerciseDetailSpan(daysAgo(5.0), now).spoken).isEqualTo("5 days")
        assertThat(ExerciseDetailSpan(daysAgo(7.0), now).short).isEqualTo("1 wk")
        assertThat(ExerciseDetailSpan(daysAgo(7.0), now).spoken).isEqualTo("1 week")
        assertThat(ExerciseDetailSpan(daysAgo(20.0), now).short).isEqualTo("3 wk")
        assertThat(ExerciseDetailSpan(daysAgo(20.0), now).spoken).isEqualTo("3 weeks")
    }

    @Test
    fun spanIsNeverLessThanOneDay() {
        assertThat(ExerciseDetailSpan(now, now).short).isEqualTo("1 d")
        assertThat(ExerciseDetailSpan(now, now).spoken).isEqualTo("1 day")
    }

    // endregion

    // region Progress

    @Test
    fun progressWithoutSessionsHasNothingToShow() {
        val progress = progress(ExerciseDetailRange.TWELVE_WEEKS)
        assertThat(progress.points).isEmpty()
        assertThat(progress.best).isNull()
        assertThat(progress.bestText).isEqualTo("–")
        assertThat(progress.trendText).isEqualTo("–")
        assertThat(progress.direction).isEqualTo(ExerciseDetailProgress.Direction.UNKNOWN)
        assertThat(progress.summary).isEqualTo("No estimated one-rep max in this range")
        // 84 days before the 12th of January 2026.
        assertThat(progress.startLabel).isEqualTo("Oct 20, 2025")
        assertThat(progress.endLabel).isEqualTo("Jan 12")
    }

    @Test
    fun risingProgressNamesTheGainTheSpanAndBothDates() {
        val progress = progress(
            ExerciseDetailRange.TWELVE_WEEKS,
            point(15.0, 93.0), point(10.0, 99.17), point(5.0, 96.0),
        )
        assertThat(progress.direction).isEqualTo(ExerciseDetailProgress.Direction.UP)
        assertThat(progress.best).isWithin(1e-9).of(99.17)
        assertThat(progress.bestText).isEqualTo("99 kg")
        assertThat(progress.trendText).isEqualTo("6 kg · 5 d")
        assertThat(progress.spokenTrend).isEqualTo("up 6 kilograms over 5 days")
        assertThat(progress.summary).isEqualTo(
            "Estimated one-rep max rising from 93 kilograms on Dec 28, 2025 to 99 kilograms on Jan 2, over 5 days, " +
                "latest 96 kilograms, 3 sessions",
        )
        assertThat(progress.points.map { it.isLast }).containsExactly(false, false, true).inOrder()
        assertThat(progress.rangeLabel).isEqualTo("Oct 20, 2025 – Jan 12")
    }

    @Test
    fun aSingleSessionHasNoTrend() {
        val progress = progress(ExerciseDetailRange.TWELVE_WEEKS, point(10.0, 99.17))
        assertThat(progress.direction).isEqualTo(ExerciseDetailProgress.Direction.UNKNOWN)
        assertThat(progress.trendText).isEqualTo("–")
        assertThat(progress.summary).isEqualTo("Estimated one-rep max 99 kilograms on Jan 2, 1 session")
    }

    @Test
    fun aFallingLatestSessionOnTopOfTheFirstOneIsNoChange() {
        val progress = progress(ExerciseDetailRange.TWELVE_WEEKS, point(20.0, 100.0), point(5.0, 95.0))
        assertThat(progress.direction).isEqualTo(ExerciseDetailProgress.Direction.FLAT)
        assertThat(progress.trendText).isEqualTo("No change")
        assertThat(progress.spokenTrend).isNull()
        assertThat(progress.summary).isEqualTo(
            "Estimated one-rep max steady at 100 kilograms from Dec 23, 2025 to Jan 7, over 2 weeks, latest 95 kilograms, 2 sessions",
        )
    }

    @Test
    fun rangeCutsOffOlderSessions() {
        val series = arrayOf(point(100.0, 80.0), point(30.0, 85.0), point(3.0, 90.0))
        assertThat(progress(ExerciseDetailRange.FOUR_WEEKS, *series).points).hasSize(1)
        assertThat(progress(ExerciseDetailRange.TWELVE_WEEKS, *series).points).hasSize(2)
        assertThat(progress(ExerciseDetailRange.ONE_YEAR, *series).points).hasSize(3)
        assertThat(progress(ExerciseDetailRange.ALL, *series).points).hasSize(3)
    }

    @Test
    fun allTimeStartsAtTheFirstSession() {
        val progress = progress(ExerciseDetailRange.ALL, point(100.0, 80.0), point(3.0, 90.0))
        assertThat(progress.start).isEqualTo(daysAgo(100.0))
        assertThat(progress.startLabel).isEqualTo("Oct 4, 2025")
    }

    @Test
    fun theDomainIsAtLeastOneDayWide() {
        // One session today with "All time": start = today, the domain must not collapse to a point.
        val progress = progress(ExerciseDetailRange.ALL, E1RMPoint(now, 90.0))
        assertThat(progress.end.isAfter(progress.start)).isTrue()
    }

    @Test
    fun aSessionAfterNowExtendsTheEndLabel() {
        val future = E1RMPoint(now.plusSeconds(3 * 86_400), 90.0)
        val progress = progress(ExerciseDetailRange.TWELVE_WEEKS, future)
        assertThat(progress.endLabel).isEqualTo("Jan 15")
    }

    @Test
    fun nonFinitePointsAreIgnored() {
        val progress = progress(ExerciseDetailRange.TWELVE_WEEKS, point(10.0, Double.NaN), point(5.0, 90.0))
        assertThat(progress.points).hasSize(1)
    }

    @Test
    fun theBestPointIsTheEarliestOnATie() {
        val progress = progress(ExerciseDetailRange.TWELVE_WEEKS, point(20.0, 100.0), point(10.0, 100.0))
        // Equal values: no gain over the first session.
        assertThat(progress.direction).isEqualTo(ExerciseDetailProgress.Direction.FLAT)
    }

    @Test
    fun theWindowFollowsTheLocalCalendarDay() {
        // 18:30 UTC on 12 January is already the 13th in Auckland, so the window and the labels move with the zone.
        val auckland = ExerciseDetailProgress(emptyList(), ExerciseDetailRange.FOUR_WEEKS, now, ZoneId.of("Pacific/Auckland"))
        assertThat(auckland.endLabel).isEqualTo("Jan 13")
        assertThat(auckland.startLabel).isEqualTo("Dec 16, 2025")
    }

    // endregion

    // region Formats

    @Test
    fun e1RMShowsWholeKilogramsOrADash() {
        assertThat(ExerciseDetailFormat.e1RM(98.6)).isEqualTo("99 kg")
        assertThat(ExerciseDetailFormat.e1RM(0.0)).isEqualTo("–")
        assertThat(ExerciseDetailFormat.e1RM(Double.NaN)).isEqualTo("–")
    }

    @Test
    fun bestSetDropsTheKilogramUnit() {
        assertThat(ExerciseDetailFormat.bestSet("85 kg × 5")).isEqualTo("85 × 5")
        assertThat(ExerciseDetailFormat.bestSet("12 reps")).isEqualTo("12 reps")
        assertThat(ExerciseDetailFormat.bestSet("45 s")).isEqualTo("45 s")
        assertThat(ExerciseDetailFormat.bestSet(null)).isEqualTo("–")
        assertThat(ExerciseDetailFormat.bestSet("")).isEqualTo("–")
    }

    @Test
    fun volumeSwitchesToTonnesFromOneTonne() {
        assertThat(ExerciseDetailFormat.volume(0.0)).isEqualTo("0 kg")
        assertThat(ExerciseDetailFormat.volume(840.0)).isEqualTo("840 kg")
        assertThat(ExerciseDetailFormat.volume(1000.0)).isEqualTo("1 t")
        assertThat(ExerciseDetailFormat.volume(12_480.0)).isEqualTo("12.5 t")
    }

    @Test
    fun sessionCountIsSingularForOne() {
        assertThat(ExerciseDetailFormat.sessionCount(0)).isEqualTo("0 sessions")
        assertThat(ExerciseDetailFormat.sessionCount(1)).isEqualTo("1 session")
        assertThat(ExerciseDetailFormat.sessionCount(3)).isEqualTo("3 sessions")
    }

    // endregion
}
