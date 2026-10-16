package health.pulse.strength.widgets.home

import androidx.compose.ui.graphics.Color
import com.google.common.truth.Truth.assertThat
import health.pulse.strength.core.widgets.BlockCell
import health.pulse.strength.core.widgets.BlockCellState
import health.pulse.strength.core.widgets.BlockRow
import health.pulse.strength.core.widgets.MonthDay
import health.pulse.strength.widgets.tablet.BlockModel
import health.pulse.strength.widgets.tablet.BlockStat
import kotlin.math.pow
import org.junit.Test

/** Month heatmap (HS-12) and the training block (SB-03). */
class MonthAndBlockModelsTest {
    private val preview = HomeFixtures.preview
    private val empty = HomeFixtures.empty

    // region Month heatmap

    @Test
    fun theMonthStartsOnItsWeekdayAndFillsWholeWeeks() {
        val grid = MonthModel.grid(preview.month)
        // October 2026 starts on a Thursday: three blanks, then the 1st.
        assertThat(grid.weeks).hasSize(5)
        assertThat(grid.weeks.all { it.size == 7 }).isTrue()
        assertThat(grid.weeks[0].map { it.day }).containsExactly(null, null, null, 1, 2, 3, 4).inOrder()
        assertThat(grid.weeks[4].map { it.day }).containsExactly(26, 27, 28, 29, 30, 31, null).inOrder()
        assertThat(grid.title).isEqualTo("October")
        assertThat(grid.sessions).isEqualTo(7)
    }

    @Test
    fun everyDayKeepsItsLevelAndFlags() {
        val cells = MonthModel.grid(preview.month).weeks.flatten().filter { it.day != null }
        assertThat(cells).hasSize(31)
        val fifth = cells.first { it.day == 5 }
        assertThat(fifth.level).isEqualTo(3)
        assertThat(fifth.trained).isTrue()
        val today = cells.first { it.day == 17 }
        assertThat(today.isToday).isTrue()
        assertThat(today.trained).isFalse()
        assertThat(cells.filter { it.isFuture }.map { it.day }).containsExactlyElementsIn(18..31).inOrder()
    }

    @Test
    fun aMonthCanNeedSixWeeksAndABlankCountIsClamped() {
        val long = preview.month.copy(leadingBlankDays = 6)
        assertThat(MonthModel.grid(long).weeks).hasSize(6)
        assertThat(MonthModel.grid(preview.month.copy(leadingBlankDays = 9)).weeks.first().count { it.day == null }).isEqualTo(6)
        val february = preview.month.copy(leadingBlankDays = 0, days = preview.month.days.take(28))
        assertThat(MonthModel.grid(february).weeks).hasSize(4)
    }

    @Test
    fun aLevelOutsideTheScaleIsClamped() {
        val odd = preview.month.copy(days = listOf(MonthDay(1, level = 7, sessions = 1), MonthDay(2, level = -1)))
        assertThat(MonthModel.grid(odd).weeks.flatten().filter { it.day != null }.map { it.level }).containsExactly(3, 0).inOrder()
    }

    @Test
    fun theMonthReadsAsASentenceListingItsTrainingDays() {
        assertThat(MonthModel.grid(preview.month).description)
            .isEqualTo("October: 7 sessions. Trained on days 2, 5, 7, 9, 12, 13 and 14.")
        assertThat(MonthModel.grid(empty.month).description).isEqualTo("October: 0 sessions. No training days yet.")
        val one = preview.month.copy(sessionCount = 1, days = preview.month.days.map { it.copy(sessions = if (it.day == 3) 1 else 0) })
        assertThat(MonthModel.grid(one).description).isEqualTo("October: 1 session. Trained on day 3.")
    }

    @Test
    fun theWeekRowsShareTheHeightThatIsLeftWithinLimits() {
        assertThat(MonthModel.cellHeight(320f, 5)).isEqualTo(40f)
        assertThat(MonthModel.cellHeight(320f, 6)).isWithin(0.01f).of((320f - 98f) / 6f)
        assertThat(MonthModel.cellHeight(180f, 6)).isEqualTo(20f)
        assertThat(MonthModel.cellHeight(250f, 6)).isWithin(0.01f).of((250f - 98f) / 6f)
    }

    @Test
    fun everyDayNumberIsReadableOnItsHeatColourInBothAppearances() {
        HeatTones.forEachIndexed { level, tone ->
            assertThat(contrast(tone.ink.light, tone.fill.light)).isAtLeast(4.5)
            assertThat(contrast(tone.ink.dark, tone.fill.dark)).isAtLeast(4.5)
            assertThat(level).isIn(0..3)
        }
        assertThat(HeatTones).hasSize(4)
    }

    @Test
    fun theHeatFillsAreTheOnesOfTheIosTheme() {
        assertThat(HeatTones.map { it.fill.light }).containsExactly(
            Color(0xFFF2F2F7), Color(0xFFB9E7C8), Color(0xFF5BC783), Color(0xFF1B8448),
        ).inOrder()
        assertThat(HeatTones.map { it.fill.dark }).containsExactly(
            Color(0xFF2C2C2E), Color(0xFF1E5A34), Color(0xFF2F9B55), Color(0xFF30D158),
        ).inOrder()
    }

    /** WCAG contrast ratio of two opaque sRGB colours. */
    private fun contrast(a: Color, b: Color): Double {
        val high = maxOf(luminance(a), luminance(b))
        val low = minOf(luminance(a), luminance(b))
        return (high + 0.05) / (low + 0.05)
    }

    private fun luminance(color: Color): Double {
        fun channel(value: Float): Double = value.toDouble().let { if (it <= 0.03928) it / 12.92 else ((it + 0.055) / 1.055).pow(2.4) }
        return 0.2126 * channel(color.red) + 0.7152 * channel(color.green) + 0.0722 * channel(color.blue)
    }

    // endregion

    // region Training block

    @Test
    fun theBlockHasAWeekPerColumnAndATemplatePerRow() {
        val card = BlockModel.card(preview.block, "Upper / Lower")!!
        assertThat(card.title).isEqualTo("Block 2 · Week 3 of 4")
        assertThat(card.plan).isEqualTo("Upper / Lower")
        assertThat(card.weekHeaders).containsExactly("Wk 1", "Wk 2", "Wk 3", "Wk 4").inOrder()
        assertThat(card.currentWeek).isEqualTo(3)
        assertThat(card.rows.map { it.label }).containsExactly("Push", "Legs", "Pull").inOrder()
        assertThat(card.rows[0].cells).containsExactly(
            BlockCellState.DONE, BlockCellState.DONE, BlockCellState.DONE, BlockCellState.UPCOMING,
        ).inOrder()
        assertThat(card.rows[1].cells[2]).isEqualTo(BlockCellState.PLANNED)
        assertThat(card.rows[2].cells[1]).isEqualTo(BlockCellState.MISSED)
    }

    @Test
    fun theThreeTilesAreSessionsLiftChangeAndMisses() {
        val card = BlockModel.card(preview.block)!!
        assertThat(card.stats).containsExactly(
            BlockStat("10 / 12", "Sessions done"),
            BlockStat("+4 kg", "Bench Press e1RM"),
            BlockStat("1", "Missed"),
        ).inOrder()
        assertThat(card.plan).isNull()
    }

    @Test
    fun withoutALiftChangeTheTileIsADashNamingTheLiftIfThereIsOne() {
        val noDelta = preview.block!!.copy(liftDeltaKg = null)
        assertThat(BlockModel.card(noDelta)!!.stats[1]).isEqualTo(BlockStat("–", "Bench Press e1RM"))
        val noLift = noDelta.copy(liftName = null)
        assertThat(BlockModel.card(noLift)!!.stats[1]).isEqualTo(BlockStat("–", "Top lift e1RM"))
        val down = preview.block!!.copy(liftDeltaKg = -2.5)
        assertThat(BlockModel.card(down)!!.stats[1].value).isEqualTo("−2.5 kg")
    }

    @Test
    fun theColumnsAreWeekCountWideAndShortRowsArePaddedWithUpcoming() {
        val short = preview.block!!.copy(rows = listOf(BlockRow("Push", listOf(BlockCell(BlockCellState.DONE)))))
        val card = BlockModel.card(short)!!
        assertThat(card.rows.single().cells).containsExactly(
            BlockCellState.DONE, BlockCellState.UPCOMING, BlockCellState.UPCOMING, BlockCellState.UPCOMING,
        ).inOrder()
        // A row holds at most ten children in Glance: a label and eight weeks is the most the grid will draw.
        val long = preview.block!!.copy(weekCount = 12)
        assertThat(BlockModel.card(long)!!.weekHeaders).hasSize(8)
    }

    @Test
    fun theWholeBlockReadsAsOneParagraph() {
        assertThat(BlockModel.card(preview.block)!!.description).isEqualTo(
            "Training block, Block 2 · Week 3 of 4. 10 of 12 sessions done, 1 missed. " +
                "Bench Press estimated one-rep max up 4 kilograms. " +
                "Push: week 1 done, week 2 done, week 3 done, week 4 upcoming. " +
                "Legs: week 1 done, week 2 done, week 3 planned, week 4 upcoming. " +
                "Pull: week 1 done, week 2 missed, week 3 done, week 4 upcoming",
        )
    }

    @Test
    fun withoutHistoryThereIsNoBlock() {
        assertThat(BlockModel.card(empty.block)).isNull()
    }

    @Test
    fun theTilesNeedTheirRoomAndTheGridTakesWhatIsLeft() {
        assertThat(BlockModel.showStats(229f)).isFalse()
        assertThat(BlockModel.showStats(230f)).isTrue()
        assertThat(BlockModel.cellHeight(300f, 3, stats = true)).isEqualTo(40f)
        assertThat(BlockModel.cellHeight(180f, 4, stats = true)).isEqualTo(24f)
        assertThat(BlockModel.cellHeight(180f, 3, stats = false)).isWithin(0.01f).of((180f - 94f) / 3f)
    }

    // endregion
}
