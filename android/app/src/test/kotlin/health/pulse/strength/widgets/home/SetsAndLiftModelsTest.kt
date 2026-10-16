package health.pulse.strength.widgets.home

import com.google.common.truth.Truth.assertThat
import health.pulse.strength.core.widgets.LiftTrend
import health.pulse.strength.core.widgets.MuscleSetsProgress
import health.pulse.strength.core.widgets.SetsStatus
import health.pulse.strength.core.widgets.TrendPoint
import java.time.Instant
import org.junit.Test

/** Weekly sets (HS-08) and lift trend (HS-09): what is drawn and where. */
class SetsAndLiftModelsTest {
    private val preview = HomeFixtures.preview

    // region Weekly sets

    @Test
    fun theFourMajorGroupsFillTheirBarsTowardTheTopOfTheTarget() {
        val card = SetsModel.card(preview, maxRows = 4)
        assertThat(card.rows.map { it.muscle }).containsExactly("Chest", "Back", "Shoulders", "Legs").inOrder()
        assertThat(card.rows.map { it.sets }).containsExactly(12, 10, 9, 6).inOrder()
        assertThat(card.rows[0].fraction).isWithin(0.001f).of(12f / 14f)
        assertThat(card.rows[3].fraction).isWithin(0.001f).of(6f / 14f)
        assertThat(card.rows.map { it.status }).containsExactly(
            SetsStatus.ON_TARGET, SetsStatus.ON_TARGET, SetsStatus.UNDER, SetsStatus.UNDER,
        ).inOrder()
        assertThat(card.caption).isEqualTo("target 10–14")
    }

    @Test
    fun armsAndCoreFollowTheMajorsAndTheCaptionThenNamesTheWeekInstead() {
        val card = SetsModel.card(preview, maxRows = 6)
        assertThat(card.rows.map { it.muscle }).containsExactly("Chest", "Back", "Shoulders", "Legs", "Arms", "Core").inOrder()
        assertThat(card.caption).isEqualTo("37 of 48 sets")
    }

    @Test
    fun theBarNeverOverflowsAndAnEmptyWeekIsAllZeros() {
        val over = MuscleSetsProgress(preview.weeklySets.muscles[0].muscle, sets = 20, targetLow = 10, targetHigh = 14, status = SetsStatus.OVER)
        val overCard = SetsModel.card(preview.copy(weeklySets = preview.weeklySets.copy(muscles = listOf(over))), 4)
        assertThat(overCard.rows.single().fraction).isEqualTo(1f)
        val empty = SetsModel.card(HomeFixtures.empty, maxRows = 4)
        assertThat(empty.rows.map { it.sets }.distinct()).containsExactly(0)
        assertThat(empty.rows.map { it.fraction }.distinct()).containsExactly(0f)
        assertThat(empty.caption).isEqualTo("target 10–14")
    }

    @Test
    fun everyRowIsDescribedWithItsStatusInWords() {
        val card = SetsModel.card(preview, maxRows = 4)
        assertThat(card.rows[2].description).isEqualTo("Shoulders: 9 sets, under target, target 10 to 14")
        assertThat(card.rows[0].description).isEqualTo("Chest: 12 sets, on target, target 10 to 14")
        assertThat(card.description).startsWith("Sets this week, 37 of 48. Chest: 12 sets")
    }

    @Test
    fun theRowCountFollowsTheHeight() {
        assertThat(SetsModel.rowCount(130f)).isEqualTo(4)
        assertThat(SetsModel.rowCount(110f)).isEqualTo(3)
        assertThat(SetsModel.rowCount(200f)).isEqualTo(6)
        assertThat(SetsModel.rowCount(40f)).isEqualTo(0)
    }

    // endregion

    // region Lift trend

    @Test
    fun theChosenLiftIsShownAndAnUnknownOrMissingChoiceFallsBackToTheFirst() {
        assertThat(LiftTrendModel.select(preview.lifts, "squat")?.name).isEqualTo("Back Squat")
        assertThat(LiftTrendModel.select(preview.lifts, "gone")?.name).isEqualTo("Bench Press")
        assertThat(LiftTrendModel.select(preview.lifts, null)?.name).isEqualTo("Bench Press")
        assertThat(LiftTrendModel.select(emptyList(), "squat")).isNull()
    }

    @Test
    fun theCardNamesTheCurrentValueTheChangeAndTheRecord() {
        val card = LiftTrendModel.card(preview, "bench")!!
        assertThat(card.name).isEqualTo("Bench Press")
        assertThat(card.subtitle).isEqualTo("Estimated 1RM · 3 sessions")
        assertThat(card.value).isEqualTo("96")
        assertThat(card.delta).isEqualTo("−3 kg vs last")
        assertThat(card.values).containsExactly(93.0, 99.0, 96.0).inOrder()
        assertThat(card.prIndex).isEqualTo(1)
        assertThat(card.firstLabel).isEqualTo("10d")
        assertThat(card.lastLabel).isEqualTo("today")
        assertThat(card.description).isEqualTo(
            "Bench Press: estimated one-rep max 96 kilograms, down 3 kilograms since the last session, personal record 99 kilograms. " +
                "Last 3 sessions: 93, 99, 96 kilograms",
        )
        assertThat(card.chartDescription).isEqualTo("Estimated one-rep max over the last 3 sessions: 93, 99, 96 kilograms")
    }

    @Test
    fun aLiftAtItsBestHasTheRecordOnTheLastPoint() {
        val squat = LiftTrendModel.card(preview, "squat")!!
        assertThat(squat.prIndex).isEqualTo(2)
        assertThat(squat.delta).isEqualTo("+3 kg vs last")
    }

    @Test
    fun aFlatLiftHasNoRecordAndNoChange() {
        val ohp = LiftTrendModel.card(preview, "ohp")!!
        assertThat(ohp.prIndex).isNull()
        assertThat(ohp.delta).isEqualTo("No change")
        assertThat(ohp.description).doesNotContain("personal record")
    }

    @Test
    fun aSingleSessionHasNoLineLabelsOrChange() {
        val single = LiftTrend("bench", "Bench Press", listOf(TrendPoint(Instant.parse("2026-10-17T09:41:00Z"), 96.0)), currentE1RM = 96.0, bestE1RM = 96.0)
        val card = LiftTrendModel.card(preview.copy(lifts = listOf(single)), null)!!
        assertThat(card.subtitle).isEqualTo("Estimated 1RM")
        assertThat(card.delta).isNull()
        assertThat(card.firstLabel).isNull()
        assertThat(card.lastLabel).isNull()
        assertThat(card.prIndex).isNull()
    }

    @Test
    fun withoutLiftsThereIsNoCard() {
        assertThat(LiftTrendModel.card(HomeFixtures.empty, null)).isNull()
    }

    @Test
    fun changeTextsForSightedAndSpokenUse() {
        assertThat(LiftTrendModel.deltaText(2.5)).isEqualTo("+2.5 kg vs last")
        assertThat(LiftTrendModel.deltaText(0.0)).isEqualTo("No change")
        assertThat(LiftTrendModel.deltaWords(2.5)).isEqualTo(", up 2.5 kilograms since the last session")
        assertThat(LiftTrendModel.deltaWords(-1.0)).isEqualTo(", down 1 kilogram since the last session")
        assertThat(LiftTrendModel.deltaWords(0.0)).isEqualTo(", unchanged since the last session")
        assertThat(LiftTrendModel.ageLabel(0)).isEqualTo("today")
        assertThat(LiftTrendModel.ageLabel(12)).isEqualTo("12d")
    }

    @Test
    fun theSparklineSpansTheInsetAreaFromLowestToHighest() {
        val points = SparklineGeometry.points(widthDp = 300f, heightDp = 60f, values = listOf(93.0, 99.0, 96.0), insetDp = 8f)
        assertThat(points).hasSize(3)
        assertThat(points[0].first).isWithin(0.001f).of(8f)
        assertThat(points[1].first).isWithin(0.001f).of(150f)
        assertThat(points[2].first).isWithin(0.001f).of(292f)
        // The lowest value sits on the bottom edge of the inset area, the highest on the top edge, 96 halfway.
        assertThat(points[0].second).isWithin(0.001f).of(52f)
        assertThat(points[1].second).isWithin(0.001f).of(8f)
        assertThat(points[2].second).isWithin(0.001f).of(30f)
    }

    @Test
    fun aSinglePointIsCentredAndASmallRangeIsNotStretched() {
        val single = SparklineGeometry.points(300f, 60f, listOf(96.0), 8f)
        assertThat(single.single().first).isEqualTo(150f)
        // A range below one kilogram is drawn as if it were one kilogram, like ChartBitmaps does.
        val nearlyFlat = SparklineGeometry.points(300f, 60f, listOf(96.0, 96.5), 8f)
        assertThat(nearlyFlat[1].second).isWithin(0.001f).of(52f - 44f * 0.5f)
        assertThat(SparklineGeometry.points(300f, 60f, emptyList(), 8f)).isEmpty()
    }

    @Test
    fun theChartGivesWayToTheLabelsOnShortWidgets() {
        val roomy = LiftChartPlan.forHeight(150f, hasPr = true)
        assertThat(roomy.showAxis).isTrue()
        assertThat(roomy.showPrBand).isTrue()
        assertThat(roomy.chartHeight).isEqualTo(150f - 76f - 32f)
        val medium = LiftChartPlan.forHeight(130f, hasPr = true)
        assertThat(medium.showAxis).isFalse()
        assertThat(medium.showPrBand).isTrue()
        assertThat(medium.showChart).isTrue()
        val short = LiftChartPlan.forHeight(110f, hasPr = true)
        assertThat(short.showPrBand).isFalse()
        assertThat(short.showChart).isTrue()
        val tiny = LiftChartPlan.forHeight(95f, hasPr = true)
        assertThat(tiny.showChart).isFalse()
        val noRecord = LiftChartPlan.forHeight(150f, hasPr = false)
        assertThat(noRecord.showPrBand).isFalse()
        assertThat(noRecord.showAxis).isTrue()
    }

    @Test
    fun thePrLabelStaysInsideTheChart() {
        assertThat(LiftTrendModel.prLabelStart(pointX = 8f, widthDp = 300f, labelWidthDp = 20f)).isEqualTo(0f)
        assertThat(LiftTrendModel.prLabelStart(pointX = 150f, widthDp = 300f, labelWidthDp = 20f)).isEqualTo(140f)
        assertThat(LiftTrendModel.prLabelStart(pointX = 292f, widthDp = 300f, labelWidthDp = 20f)).isEqualTo(280f)
    }

    @Test
    fun theConfigurationListNamesValueAndSessions() {
        val bench = preview.lifts.first()
        assertThat(liftPickerSummary(bench)).isEqualTo("Estimated 1RM 96 kg · 3 sessions")
    }

    // endregion
}
