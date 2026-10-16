package health.pulse.strength.ui.detail

import com.google.common.truth.Truth.assertThat
import health.pulse.strength.core.CompletedSet
import health.pulse.strength.core.SetType
import health.pulse.strength.core.TrackingKind
import java.time.Instant
import java.time.ZoneId
import org.junit.Test

/** The hand-made date, duration and set text shared by the detail and the summary: identical in every locale. */
class StrengthResultTextTest {
    private val utc: ZoneId = ZoneId.of("UTC")
    private val now: Instant = Instant.parse("2026-01-12T18:30:00Z")

    private fun set(kg: Double, reps: Int, type: SetType = SetType.NORMAL, rir: Int? = null) =
        CompletedSet(type = type, weightKg = kg, reps = reps, rir = rir)

    // region Dates

    @Test
    fun monthDayOmitsTheYearOfNow() {
        assertThat(StrengthResultText.monthDay(Instant.parse("2026-01-02T10:00:00Z"), now, utc)).isEqualTo("Jan 2")
        assertThat(StrengthResultText.monthDay(Instant.parse("2025-10-03T10:00:00Z"), now, utc)).isEqualTo("Oct 3, 2025")
    }

    @Test
    fun weekdayMonthDayStartsTheWeekOnSunday() {
        assertThat(StrengthResultText.weekdayMonthDay(Instant.parse("2026-01-02T10:00:00Z"), now, utc)).isEqualTo("Fri, Jan 2")
        assertThat(StrengthResultText.weekdayMonthDay(Instant.parse("2026-01-04T10:00:00Z"), now, utc)).isEqualTo("Sun, Jan 4")
        assertThat(StrengthResultText.weekdayMonthDay(Instant.parse("2026-01-05T10:00:00Z"), now, utc)).isEqualTo("Mon, Jan 5")
        assertThat(StrengthResultText.weekdayMonthDay(Instant.parse("2026-01-10T10:00:00Z"), now, utc)).isEqualTo("Sat, Jan 10")
    }

    @Test
    fun datesAreLocalCalendarDays() {
        val lateEvening = Instant.parse("2026-01-02T23:30:00Z")
        assertThat(StrengthResultText.monthDay(lateEvening, now, utc)).isEqualTo("Jan 2")
        // Already the 3rd, a Saturday, in New Zealand.
        assertThat(StrengthResultText.weekdayMonthDay(lateEvening, now, ZoneId.of("Pacific/Auckland"))).isEqualTo("Sat, Jan 3")
        // Still the 2nd (a Friday) in Los Angeles.
        assertThat(StrengthResultText.monthDay(lateEvening, now, ZoneId.of("America/Los_Angeles"))).isEqualTo("Jan 2")
    }

    // endregion

    // region Durations

    @Test
    fun durationTileUsesTheShortestUnits() {
        assertThat(StrengthResultText.durationTile(-5)).isEqualTo("0s")
        assertThat(StrengthResultText.durationTile(45)).isEqualTo("45s")
        assertThat(StrengthResultText.durationTile(3_120)).isEqualTo("52m")
        assertThat(StrengthResultText.durationTile(3_900)).isEqualTo("1h 5m")
        assertThat(StrengthResultText.durationTile(7_200)).isEqualTo("2h")
    }

    @Test
    fun durationSubtitleIsInWholeMinutes() {
        assertThat(StrengthResultText.durationSubtitle(30)).isEqualTo("< 1 min")
        assertThat(StrengthResultText.durationSubtitle(3_120)).isEqualTo("52 min")
        assertThat(StrengthResultText.durationSubtitle(3_900)).isEqualTo("65 min")
    }

    @Test
    fun durationSpokenIsInWords() {
        assertThat(StrengthResultText.durationSpoken(1)).isEqualTo("1 second")
        assertThat(StrengthResultText.durationSpoken(45)).isEqualTo("45 seconds")
        assertThat(StrengthResultText.durationSpoken(3_120)).isEqualTo("52 minutes")
        assertThat(StrengthResultText.durationSpoken(3_900)).isEqualTo("1 hour 5 minutes")
        assertThat(StrengthResultText.durationSpoken(3_660)).isEqualTo("1 hour 1 minute")
        assertThat(StrengthResultText.durationSpoken(7_200)).isEqualTo("2 hours")
    }

    @Test
    fun oneDecimalUsesADotAndClamps() {
        assertThat(StrengthResultText.oneDecimal(2.14)).isEqualTo("2.1")
        assertThat(StrengthResultText.oneDecimal(2.0)).isEqualTo("2.0")
        assertThat(StrengthResultText.oneDecimal(1.75)).isEqualTo("1.8")
        assertThat(StrengthResultText.oneDecimal(-1.0)).isEqualTo("0.0")
        assertThat(StrengthResultText.oneDecimal(Double.NaN)).isEqualTo("0.0")
    }

    // endregion

    // region Sets

    @Test
    fun compactTextPerTrackingKind() {
        assertThat(StrengthResultText.compactText(set(80.0, 6), TrackingKind.WEIGHT_REPS)).isEqualTo("80×6")
        assertThat(StrengthResultText.compactText(set(82.5, 5), TrackingKind.WEIGHT_REPS)).isEqualTo("82.5×5")
        assertThat(StrengthResultText.compactText(set(50.0, 8, SetType.WARMUP), TrackingKind.WEIGHT_REPS)).isEqualTo("W 50×8")
        assertThat(StrengthResultText.compactText(set(0.0, 8), TrackingKind.REPS_ONLY)).isEqualTo("8 reps")
        assertThat(StrengthResultText.compactText(set(10.0, 8), TrackingKind.REPS_ONLY)).isEqualTo("+10×8")
        assertThat(StrengthResultText.compactText(set(0.0, 45), TrackingKind.DURATION)).isEqualTo("45 s")
        assertThat(StrengthResultText.compactText(set(30.0, 10, SetType.DROP), TrackingKind.WEIGHT_REPS)).isEqualTo("D 30×10")
        assertThat(StrengthResultText.compactText(set(30.0, 10, SetType.FAILURE), TrackingKind.WEIGHT_REPS)).isEqualTo("F 30×10")
    }

    @Test
    fun setsLineJoinsWithMiddleDots() {
        val sets = listOf(set(50.0, 8, SetType.WARMUP), set(80.0, 6), set(80.0, 5))
        assertThat(StrengthResultText.setsLine(sets, TrackingKind.WEIGHT_REPS)).isEqualTo("W 50×8 · 80×6 · 80×5")
        assertThat(StrengthResultText.setsLine(emptyList(), TrackingKind.WEIGHT_REPS)).isEmpty()
    }

    @Test
    fun detailTextPerTrackingKind() {
        assertThat(StrengthResultText.detailText(set(80.0, 6), TrackingKind.WEIGHT_REPS)).isEqualTo("80 kg × 6")
        assertThat(StrengthResultText.detailText(set(0.0, 1), TrackingKind.REPS_ONLY)).isEqualTo("1 rep")
        assertThat(StrengthResultText.detailText(set(0.0, 8), TrackingKind.REPS_ONLY)).isEqualTo("8 reps")
        assertThat(StrengthResultText.detailText(set(10.0, 8), TrackingKind.REPS_ONLY)).isEqualTo("+10 kg × 8")
        assertThat(StrengthResultText.detailText(set(0.0, 45), TrackingKind.DURATION)).isEqualTo("45 s")
    }

    @Test
    fun rirTextCapsAtFourPlus() {
        assertThat(StrengthResultText.rirText(null)).isNull()
        assertThat(StrengthResultText.rirText(0)).isEqualTo("RIR 0")
        assertThat(StrengthResultText.rirText(3)).isEqualTo("RIR 3")
        assertThat(StrengthResultText.rirText(4)).isEqualTo("RIR 4+")
        assertThat(StrengthResultText.rirText(9)).isEqualTo("RIR 4+")
    }

    @Test
    fun setLinesNumberOnlyTheNormalSets() {
        val lines = StrengthResultText.setLines(
            listOf(set(50.0, 8, SetType.WARMUP), set(80.0, 6, rir = 3), set(80.0, 5, SetType.FAILURE, rir = 0), set(70.0, 8, SetType.DROP), set(80.0, 5)),
            TrackingKind.WEIGHT_REPS,
        )
        assertThat(lines.map { it.badge }).containsExactly("W", "1", "F", "D", "2").inOrder()
        assertThat(lines.map { it.detailText }).containsExactly("50 kg × 8", "80 kg × 6", "80 kg × 5", "70 kg × 8", "80 kg × 5").inOrder()
        assertThat(lines.map { it.rirText }).containsExactly(null, "RIR 3", "RIR 0", null, null).inOrder()
        assertThat(lines.map { it.id }).containsExactly(0, 1, 2, 3, 4).inOrder()
    }

    @Test
    fun spokenSetLineNamesTheSetType() {
        val lines = StrengthResultText.setLines(
            listOf(set(50.0, 8, SetType.WARMUP), set(80.0, 6, rir = 3), set(30.0, 10, SetType.DROP), set(30.0, 8, SetType.FAILURE)),
            TrackingKind.WEIGHT_REPS,
        )
        assertThat(lines[0].spokenText).isEqualTo("Warm-up set, 50 kg × 8")
        assertThat(lines[1].spokenText).isEqualTo("Set 1, 80 kg × 6, RIR 3")
        assertThat(lines[2].spokenText).isEqualTo("Drop set, 30 kg × 10")
        assertThat(lines[3].spokenText).isEqualTo("Set to failure, 30 kg × 8")
    }

    // endregion
}
