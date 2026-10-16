package health.pulse.strength.widgets.extras

import com.google.common.truth.Truth.assertThat
import health.pulse.strength.core.widgets.BodyMap
import health.pulse.strength.core.widgets.DeepLinks
import health.pulse.strength.core.widgets.PartnerWeek
import health.pulse.strength.core.widgets.PlateauFlag
import health.pulse.strength.core.widgets.TimelineKind
import health.pulse.strength.core.widgets.TimelineSegment
import health.pulse.strength.core.widgets.TrendStatus
import health.pulse.strength.widgets.WidgetFixtures
import java.time.Instant
import org.junit.Test

/** Which text, fraction or bar each "wilder idea" widget (WI-01 ... WI-11) shows for which snapshot. */
class ExtrasTextTest {
    private val preview = WidgetFixtures.preview
    private val empty = WidgetFixtures.empty()

    // WI-01 body map

    @Test
    fun theBodyMapIsDescribedInWordsForAScreenReader() {
        assertThat(ExtrasText.bodyDescription(preview.bodyMap)).isEqualTo(
            "Body map, front and back. Chest: high. Back: medium. Shoulders: medium. Arms: light. Legs: untouched. Core: untouched.",
        )
    }

    @Test
    fun theBodyMapMessageIsSplitAfterItsFirstSentence() {
        val message = ExtrasText.bodyMessage(preview.bodyMap)
        assertThat(message.headline).isEqualTo("Legs untouched.")
        assertThat(message.detail).isEqualTo("Lower A is next in line.")
    }

    @Test
    fun aSingleSentenceMessageHasNoDetailAndAnEmptyOneFallsBack() {
        val single = ExtrasText.bodyMessage(BodyMap(message = "Every major group has been trained this week."))
        assertThat(single.headline).isEqualTo("Every major group has been trained this week.")
        assertThat(single.detail).isEmpty()
        val none = ExtrasText.bodyMessage(empty.bodyMap)
        assertThat(none.headline).isEqualTo("No sets yet.")
        assertThat(none.detail).isNotEmpty()
    }

    // WI-03 gym partner

    private val sam = PartnerWeek(name = "Sam", initials = "S", completed = 4, goal = 4, closedWeek = true)

    @Test
    fun partnerRowsListYouFirstThenThePartners() {
        val rows = ExtrasText.partnerRows(preview.week, preview.partners, maxRows = 4)
        assertThat(rows.map { it.label }).containsExactly("You", "S").inOrder()
        assertThat(rows[0].isYou).isTrue()
        assertThat(rows[0].fraction).isEqualTo(0.75f)
        assertThat(rows[1].fraction).isEqualTo(1f)
        assertThat(rows[1].completed).isEqualTo(4)
    }

    @Test
    fun partnerRowsAreLimitedToTheSpaceAndAlwaysIncludeYou() {
        val partners = listOf(sam, sam.copy(name = "Lee", initials = "L"), sam.copy(name = "Kim", initials = "K"))
        assertThat(ExtrasText.partnerRows(preview.week, partners, maxRows = 3).map { it.label }).containsExactly("You", "S", "L").inOrder()
        assertThat(ExtrasText.partnerRows(preview.week, partners, maxRows = 1).map { it.label }).containsExactly("You")
        assertThat(ExtrasText.partnerRows(preview.week, partners, maxRows = 0).map { it.label }).containsExactly("You")
    }

    @Test
    fun aPartnerWithoutInitialsShowsTheFirstLetterOfTheName() {
        val rows = ExtrasText.partnerRows(preview.week, listOf(sam.copy(initials = "")), maxRows = 2)
        assertThat(rows[1].label).isEqualTo("S")
    }

    @Test
    fun theRowCapacityGrowsWithTheHeightBetweenTwoAndFour() {
        assertThat(ExtrasText.partnerLayout(110f).rows).isEqualTo(2)
        assertThat(ExtrasText.partnerLayout(146f).rows).isEqualTo(2)
        assertThat(ExtrasText.partnerLayout(190f).rows).isEqualTo(3)
        assertThat(ExtrasText.partnerLayout(400f).rows).isEqualTo(4)
        assertThat(ExtrasText.partnerLayout(20f).rows).isEqualTo(2)
    }

    @Test
    fun theTitleGoesBeforeALineWhenLargeTextLeavesNoRoomForBoth() {
        // 110 dp leaves 67.8 dp under the title for two lines of 32 dp.
        assertThat(ExtrasText.partnerLayout(110f).showsTitle).isTrue()
        assertThat(ExtrasText.partnerLayout(146f).showsTitle).isTrue()
        // The same widget at a font scale of 1.3 counts as 85 dp: two lines still fit (65 dp), the title no longer does.
        val large = ExtrasText.partnerLayout(85f)
        assertThat(large.showsTitle).isFalse()
        assertThat(large.rows).isEqualTo(2)
    }

    @Test
    fun aShortPartnerWidgetUsesSmallerAvatarsAndDropsTheSentence() {
        val compact = ExtrasText.partnerLayout(110f)
        val regular = ExtrasText.partnerLayout(146f)
        assertThat(compact.showsFooter).isFalse()
        assertThat(regular.showsFooter).isTrue()
        assertThat(compact.avatar).isLessThan(regular.avatar)
        assertThat(compact.padding).isLessThan(regular.padding)
        // Every slot holds its avatar, and two lines with the title above them fit the compact height.
        assertThat(compact.rowSlot).isAtLeast(compact.avatar)
        assertThat(regular.rowSlot).isAtLeast(regular.avatar)
    }

    @Test
    fun theFooterNamesWhoClosedTheWeekAndWhoseTurnItIs() {
        assertThat(ExtrasText.partnerFooter(preview.week, preview.partners)).isEqualTo("Sam closed their week. Your turn.")
        val reached = preview.week.copy(completed = 4)
        assertThat(ExtrasText.partnerFooter(reached, preview.partners)).isEqualTo("You and Sam closed the week.")
        val two = listOf(sam, sam.copy(name = "Lee"))
        assertThat(ExtrasText.partnerFooter(preview.week, two)).isEqualTo("2 partners closed their week. Your turn.")
        assertThat(ExtrasText.partnerFooter(reached, two)).isEqualTo("You and 2 partners closed the week.")
    }

    @Test
    fun theFooterReportsTheLeaderWithoutRankingWhenNobodyClosed() {
        val open = listOf(sam.copy(completed = 2, closedWeek = false), sam.copy(name = "Lee", completed = 3, closedWeek = false))
        assertThat(ExtrasText.partnerFooter(preview.week, open)).isEqualTo("Lee is at 3 of 4 this week.")
        assertThat(ExtrasText.partnerFooter(preview.week, emptyList())).isEmpty()
    }

    // WI-04 form cue

    @Test
    fun theCueMayBeSetInAFewSizesLargestFirstAndASmallWidgetStartsSmaller() {
        assertThat(ExtrasText.cueTextSizes(roomy = true)).containsExactly(17f, 15f, 14f, 13f, 12f).inOrder()
        assertThat(ExtrasText.cueTextSizes(roomy = false)).containsExactly(15f, 14f, 13f, 12f).inOrder()
    }

    @Test
    fun theFormCueShowsTheCueAndItsPlace() {
        val cue = ExtrasText.formCue(preview.formCue)
        assertThat(cue.eyebrow).isEqualTo("Form cue · Bench Press")
        assertThat(cue.shortEyebrow).isEqualTo("Bench Press")
        assertThat(cue.cue).isEqualTo("Shoulder blades back and down.")
        assertThat(cue.footer).isEqualTo("1 of 4 cues")
        assertThat(cue.link).isEqualTo(DeepLinks.exercise("bench"))
        assertThat(ExtrasText.formCue(preview.formCue!!.copy(count = 1)).footer).isEqualTo("1 of 1 cue")
    }

    @Test
    fun withoutACueTheWidgetSaysWhereCuesComeFrom() {
        val cue = ExtrasText.formCue(null)
        assertThat(cue.eyebrow).isEqualTo("Form cue")
        assertThat(cue.shortEyebrow).isEqualTo("Form cue")
        assertThat(cue.cue).isEqualTo("Cues for your next workout show up here.")
        assertThat(cue.link).isEqualTo(DeepLinks.hub)
    }

    // WI-05 loaded bar

    @Test
    fun theLoadedBarShowsTheTotalAndThePlatesPerSide() {
        val bar = ExtrasText.loadedBar(preview.loadedBar)!!
        assertThat(bar.total).isEqualTo("85 kg")
        assertThat(bar.perSide).isEqualTo("20 + 10 + 2.5 a side")
        assertThat(bar.note).isNull()
        assertThat(bar.layout.plates).hasSize(3)
        assertThat(bar.description).isEqualTo("Top set Bench Press, 85 kilograms: 20 + 10 + 2.5 a side")
    }

    @Test
    fun aLeftoverWeightIsReportedAndABarWithoutPlatesIsJustTheBar() {
        val leftover = ExtrasText.loadedBar(preview.loadedBar!!.copy(leftoverKg = 0.5))!!
        assertThat(leftover.note).isEqualTo("0.5 kg can't be loaded")
        assertThat(leftover.description).endsWith("0.5 kg can't be loaded")
        val bare = ExtrasText.loadedBar(preview.loadedBar!!.copy(totalKg = 20.0, platesPerSide = emptyList(), summary = ""))!!
        assertThat(bare.perSide).isEqualTo("Bar only")
        assertThat(bare.layout.plates).isEmpty()
    }

    @Test
    fun aBlankSummaryIsBuiltFromThePlates() {
        val bar = ExtrasText.loadedBar(preview.loadedBar!!.copy(summary = " "))!!
        assertThat(bar.perSide).isEqualTo("20 + 10 + 2.5 a side")
    }

    @Test
    fun withoutABarbellLiftThereIsNoLoadedBar() {
        assertThat(ExtrasText.loadedBar(null)).isNull()
    }

    // WI-06 rest day

    @Test
    fun aRestDayOffersTheRoutineAndStartOpensAnEmptyWorkoutNamedAfterIt() {
        val card = ExtrasText.restDayCard(preview) as ExtrasText.RestDayCard.Rest
        assertThat(card.reason).isEqualTo("Rest day")
        assertThat(card.title).isEqualTo("10-min mobility")
        assertThat(card.focus).isEqualTo("Hips and T-spine")
        assertThat(card.link).isEqualTo(DeepLinks.startEmpty("10-min mobility"))
        assertThat(card.link).isEqualTo("pulse-strength://start-empty?name=10-min%20mobility")
    }

    @Test
    fun aTrainingDayOffersTheNextWorkoutInstead() {
        val card = ExtrasText.restDayCard(preview.copy(restDay = null)) as ExtrasText.RestDayCard.Training
        assertThat(card.name).isEqualTo("Upper A · Push")
        assertThat(card.detail).isEqualTo("6 exercises · ~55 min")
        assertThat(card.link).isEqualTo(DeepLinks.startNext)
        val running = ExtrasText.restDayCard(preview.copy(restDay = null, active = WidgetFixtures.active()))
        assertThat(running.link).isEqualTo(DeepLinks.workout)
    }

    @Test
    fun withNeitherARoutineNorATemplateTheCardIsEmpty() {
        val card = ExtrasText.restDayCard(empty)
        assertThat(card).isEqualTo(ExtrasText.RestDayCard.Empty)
        assertThat(card.link).isEqualTo(DeepLinks.hub)
    }

    // WI-07 strength ratio

    @Test
    fun theStrengthRatioShowsTheFigureAndTheBarTowardTheGoal() {
        val ratio = ExtrasText.strengthRatio(preview.strengthRatio)
        assertThat(ratio.eyebrow).isEqualTo("Bench Press / bodyweight")
        assertThat(ratio.shortEyebrow).isEqualTo("Bench Press")
        assertThat(ratio.figure).isEqualTo("1.24×")
        assertThat(ratio.fraction!!).isWithin(0.0001f).of(1.24f / 1.5f)
        assertThat(ratio.footer).isEqualTo("Goal 1.5× · 80 kg")
        assertThat(ratio.link).isEqualTo(DeepLinks.exercise("bench"))
    }

    @Test
    fun theRatioBarStopsAtTheGoalAndGoalsReadWithoutTrailingZeros() {
        val beyond = ExtrasText.strengthRatio(preview.strengthRatio!!.copy(ratio = 1.8))
        assertThat(beyond.fraction).isEqualTo(1f)
        val squat = ExtrasText.strengthRatio(preview.strengthRatio!!.copy(ratio = 1.5, goalRatio = 2.0))
        assertThat(squat.footer).isEqualTo("Goal 2× · 80 kg")
        assertThat(squat.figure).isEqualTo("1.50×")
    }

    @Test
    fun withoutABodyweightTheWidgetAsksForItInHealthConnect() {
        val ratio = ExtrasText.strengthRatio(preview.strengthRatio!!.copy(bodyweightKg = null, ratio = null))
        assertThat(ratio.figure).isEqualTo("99 kg")
        assertThat(ratio.fraction).isNull()
        assertThat(ratio.footer).isEqualTo("Add your bodyweight in Health Connect")
        // The app has its own body weight entry, which the missing weight leads to.
        assertThat(ratio.link).isEqualTo(DeepLinks.weight)
    }

    @Test
    fun withoutAMainLiftThereIsNoRatio() {
        val ratio = ExtrasText.strengthRatio(null)
        assertThat(ratio.eyebrow).isEqualTo("Strength ratio")
        assertThat(ratio.shortEyebrow).isEqualTo("Strength")
        assertThat(ratio.figure).isEqualTo("–")
        assertThat(ratio.fraction).isNull()
        assertThat(ratio.link).isEqualTo(DeepLinks.hub)
    }

    @Test
    fun theRatioFooterHasShorterWordingsForASmallWidget() {
        val ratio = ExtrasText.strengthRatio(preview.strengthRatio!!.copy(ratio = 1.75, goalRatio = 2.0, bodyweightKg = 102.5))
        assertThat(ratio.footers).containsExactly("Goal 2× · 102.5 kg", "Goal 2×").inOrder()
        val none = ExtrasText.strengthRatio(null)
        assertThat(none.footer).isEqualTo("Log bench, squat, deadlift or press to see your ratio.")
        assertThat(none.footers.last()).isEqualTo("Log a main lift.")
        val noBodyweight = ExtrasText.strengthRatio(preview.strengthRatio!!.copy(bodyweightKg = null, ratio = null))
        assertThat(noBodyweight.footers).containsExactly("Add your bodyweight in Health Connect", "Add your bodyweight", "Add weight").inOrder()
    }

    // WI-08 year in iron

    @Test
    fun theYearShowsTonnesSessionsAndTwelveMonthlyBars() {
        val year = ExtrasText.yearInIron(preview.year, currentMonth = 9)
        assertThat(year.eyebrow).isEqualTo("Lifted in 2026")
        assertThat(year.eyebrows).containsExactly("Lifted in 2026", "Lifted 2026", "2026").inOrder()
        assertThat(year.tonnes).isEqualTo("186.4")
        assertThat(year.captions).containsExactly("across 74 sessions", "74 sessions").inOrder()
        assertThat(year.caption).isEqualTo("across 74 sessions")
        assertThat(year.bars).hasSize(12)
        assertThat(year.bars[8].fraction).isEqualTo(1f)
        assertThat(year.bars[0].fraction).isWithin(0.0001f).of(14.2f / 21.3f)
        assertThat(year.bars.withIndex().filter { it.value.isCurrent }.map { it.index }).containsExactly(9)
    }

    @Test
    fun anEmptyMonthHasNoBarAndATinyMonthKeepsASliver() {
        val year = ExtrasText.yearInIron(preview.year, currentMonth = 9)
        assertThat(year.bars[10].fraction).isEqualTo(0f)
        assertThat(year.bars[11].fraction).isEqualTo(0f)
        val tiny = ExtrasText.yearInIron(preview.year.copy(monthlyTonnes = listOf(100.0, 0.1) + List(10) { 0.0 }), currentMonth = 1)
        assertThat(tiny.bars[1].fraction).isGreaterThan(0.1f)
    }

    @Test
    fun aYearWithoutSessionsSaysSoAndDrawsNoBars() {
        val year = ExtrasText.yearInIron(empty.year, currentMonth = 9)
        assertThat(year.tonnes).isEqualTo("0")
        assertThat(year.captions).containsExactly("no sessions yet", "no sessions").inOrder()
        assertThat(year.bars.all { it.fraction == 0f }).isTrue()
        val single = ExtrasText.yearInIron(preview.year.copy(sessionCount = 1), currentMonth = 9)
        assertThat(single.captions).containsExactly("across 1 session", "1 session").inOrder()
    }

    @Test
    fun aShortMonthListIsPaddedToTwelveBars() {
        assertThat(ExtrasText.yearInIron(preview.year.copy(monthlyTonnes = listOf(5.0)), currentMonth = 0).bars).hasSize(12)
    }

    @Test
    fun theCurrentMonthComesFromTheSnapshotsOwnTimeZone() {
        assertThat(ExtrasText.currentMonthIndex(preview)).isEqualTo(9)
        // 23:30 UTC on 31 December is already 1 January in Berlin: another year than the totals, so no month is current.
        val newYear = preview.copy(generatedAt = Instant.parse("2026-12-31T23:30:00Z"), timeZoneID = "Europe/Berlin")
        assertThat(ExtrasText.currentMonthIndex(newYear)).isEqualTo(-1)
        val lateDecember = preview.copy(generatedAt = Instant.parse("2026-12-31T23:30:00Z"), timeZoneID = "UTC")
        assertThat(ExtrasText.currentMonthIndex(lateDecember)).isEqualTo(11)
    }

    @Test
    fun anUnknownTimeZoneFallsBackToUtc() {
        assertThat(ExtrasText.currentMonthIndex(preview.copy(timeZoneID = "Not/AZone"))).isEqualTo(9)
    }

    // WI-09 readiness

    @Test
    fun readinessIsGoodFromTwoThirdsFairFromOneThirdAndLowBelow() {
        assertThat(ExtrasText.readinessTier(100)).isEqualTo(ReadinessTier.GOOD)
        assertThat(ExtrasText.readinessTier(67)).isEqualTo(ReadinessTier.GOOD)
        assertThat(ExtrasText.readinessTier(66)).isEqualTo(ReadinessTier.FAIR)
        assertThat(ExtrasText.readinessTier(34)).isEqualTo(ReadinessTier.FAIR)
        assertThat(ExtrasText.readinessTier(33)).isEqualTo(ReadinessTier.LOW)
        assertThat(ExtrasText.readinessTier(0)).isEqualTo(ReadinessTier.LOW)
    }

    @Test
    fun readinessShowsTheScoreTheWordAndTheAdvice() {
        val model = ExtrasText.readiness(preview.readiness)
        assertThat(model.tier).isEqualTo(ReadinessTier.GOOD)
        assertThat(model.score).isEqualTo("82")
        assertThat(model.caption).isEqualTo("ready")
        assertThat(model.headline).isEqualTo("Good sleep, steady HRV. Go for the top set.")
        assertThat(model.detail).isEqualTo("From Pulse")
        assertThat(model.fraction).isWithin(0.0001f).of(0.82f)
    }

    @Test
    fun readinessFallsBackToTheLabelAndClampsTheRing() {
        val noMessage = ExtrasText.readiness(preview.readiness!!.copy(message = "", score = 130))
        assertThat(noMessage.headline).isEqualTo("Ready")
        assertThat(noMessage.fraction).isEqualTo(1f)
    }

    @Test
    fun withoutPulseDataTheWidgetInvitesToConnect() {
        val model = ExtrasText.readiness(null)
        assertThat(model.tier).isNull()
        assertThat(model.score).isEqualTo("–")
        assertThat(model.headline).isEqualTo("Connect Pulse")
        assertThat(model.fraction).isEqualTo(0f)
    }

    @Test
    fun theAdviceIsSetAtTheLargestSizeThatLeavesRoomForTheWholeAdvice() {
        // Room for the eyebrow (15.6), a gap, three lines of 17 sp (66.3), a gap and one line of 13 sp (16.9): 107 dp.
        val layout = ExtrasText.adviceLayout(room = 110f, adviceLines = { 3 }, detailLines = { 1 })
        assertThat(layout.style).isEqualTo(ExtrasText.AdviceStyle(17f, 13f))
        assertThat(layout.maxLines).isEqualTo(3)
    }

    @Test
    fun aShorterWidgetSetsTheAdviceSmallerBeforeItDropsTheLineUnderIt() {
        // At 17 sp the advice takes four lines (88.4 dp: too much), at 15 sp three (58.5 dp) with the source line: 98 dp.
        val lines = mapOf(17f to 4, 15f to 3, 13f to 3, 12f to 3)
        val smaller = ExtrasText.adviceLayout(room = 100f, adviceLines = { lines.getValue(it) }, detailLines = { 1 })
        assertThat(smaller.style).isEqualTo(ExtrasText.AdviceStyle(15f, 12f))
        // 78 dp: the three lines at 15 sp leave no room for the source, and the advice keeps its size without it.
        val dropped = ExtrasText.adviceLayout(room = 78.2f, adviceLines = { lines.getValue(it) }, detailLines = { 1 })
        assertThat(dropped.style).isEqualTo(ExtrasText.AdviceStyle(15f, null))
        assertThat(dropped.maxLines).isEqualTo(3)
    }

    @Test
    fun aLineUnderTheAdviceThatNeedsMoreThanTwoLinesIsLeftOut() {
        val layout = ExtrasText.adviceLayout(room = 200f, adviceLines = { 1 }, detailLines = { 3 })
        assertThat(layout.style.detailSp).isNull()
    }

    @Test
    fun anAdviceTooLongForAnyStyleIsCutAtTheSmallestSizeInTheLinesThereAre() {
        val layout = ExtrasText.adviceLayout(room = 78f, adviceLines = { 9 }, detailLines = { 1 })
        assertThat(layout.style).isEqualTo(ExtrasText.adviceStyles.last())
        // (78 - 15.6 - 4) / 15.6 = 3.7: three lines.
        assertThat(layout.maxLines).isEqualTo(3)
        assertThat(ExtrasText.adviceLayout(room = 10f, adviceLines = { 9 }, detailLines = { 1 }).maxLines).isEqualTo(1)
    }

    // WI-10 plateau watch

    @Test
    fun theTrendIsWrittenInWordsNotJustColour() {
        val flags = preview.plateaus
        assertThat(flags.map { ExtrasText.plateauStatusText(it) }).containsExactly("rising", "flat 3×", "rising").inOrder()
        assertThat(ExtrasText.plateauStatusText(PlateauFlag("x", "Squat", TrendStatus.FALLING))).isEqualTo("falling")
    }

    @Test
    fun plateauShowsTheLiftsInOrderWithTheTip() {
        val model = ExtrasText.plateau(preview.plateaus, maxRows = 3)
        assertThat(model.rows.map { it.name }).containsExactly("Bench Press", "Overhead Press", "Back Squat").inOrder()
        assertThat(model.tip).isEqualTo("Try 3 × 8 at about 90% for two weeks.")
        assertThat(model.description).isEqualTo(
            "Plateau watch: Bench Press rising, Overhead Press flat 3×, Back Squat rising. Tip: Try 3 × 8 at about 90% for two weeks.",
        )
    }

    @Test
    fun plateauAlwaysKeepsTheLiftTheTipIsAbout() {
        val two = ExtrasText.plateau(preview.plateaus, maxRows = 2)
        assertThat(two.rows.map { it.name }).containsExactly("Bench Press", "Overhead Press").inOrder()
        // With room for one lift only, the flat lift replaces the rising one rather than the tip hanging in the air.
        val one = ExtrasText.plateau(preview.plateaus, maxRows = 1)
        assertThat(one.rows.map { it.name }).containsExactly("Overhead Press")
        val lastFlat = listOf(preview.plateaus[0], preview.plateaus[2], preview.plateaus[1])
        assertThat(ExtrasText.plateau(lastFlat, maxRows = 2).rows.map { it.name }).containsExactly("Bench Press", "Overhead Press").inOrder()
    }

    @Test
    fun plateauWithoutHistoryHasNoRows() {
        val model = ExtrasText.plateau(empty.plateaus, maxRows = 3)
        assertThat(model.rows).isEmpty()
        assertThat(model.tip).isNull()
        assertThat(model.description).isEqualTo("Plateau watch: not enough history yet")
    }

    // WI-11 session timeline

    @Test
    fun theTimelineSpansTileTheBarInProportionToTheirSeconds() {
        val spans = ExtrasText.timelineSpans(preview.lastSession!!.timeline, widthPx = 1000)
        assertThat(spans).hasSize(13)
        assertThat(spans.first().start).isEqualTo(0)
        assertThat(spans.last().end).isEqualTo(1000)
        spans.zipWithNext { first, second -> assertThat(second.start).isEqualTo(first.end) }
        // The first stretch is 160 of the 1,860 seconds.
        assertThat(spans.first().kind).isEqualTo(TimelineKind.LIFTING)
        assertThat(spans.first().end).isEqualTo(86)
    }

    @Test
    fun timelineSpansSkipEmptyStretchesAndHandleNothingToDraw() {
        val segments = listOf(TimelineSegment(TimelineKind.LIFTING, 30), TimelineSegment(TimelineKind.REST, 0), TimelineSegment(TimelineKind.LONG_REST, 30))
        val spans = ExtrasText.timelineSpans(segments, widthPx = 101)
        assertThat(spans.map { it.kind }).containsExactly(TimelineKind.LIFTING, TimelineKind.LONG_REST).inOrder()
        assertThat(spans.last().end).isEqualTo(101)
        assertThat(ExtrasText.timelineSpans(emptyList(), 100)).isEmpty()
        assertThat(ExtrasText.timelineSpans(segments, 0)).isEmpty()
    }

    @Test
    fun theTimelineSummaryNamesDurationTensionAndLongBreaks() {
        val model = ExtrasText.sessionTimeline(preview.lastSession)
        assertThat(model.name).isEqualTo("Upper B · Pull")
        assertThat(model.hasBar).isTrue()
        assertThat(model.headline).isEqualTo("51 min")
        assertThat(model.tail).isEqualTo(" · 38% under tension · 1 long break")
        // Shorter wordings, longest first, for a narrower widget: the last detail goes first, then all of them.
        assertThat(model.tails).containsExactly(" · 38% under tension · 1 long break", " · 38% under tension", "").inOrder()
        assertThat(model.kinds).containsExactly(TimelineKind.LIFTING, TimelineKind.REST, TimelineKind.LONG_REST).inOrder()
        assertThat(model.description).isEqualTo("Session timeline for Upper B · Pull: 51 min · 38% under tension · 1 long break")
    }

    @Test
    fun theLegendListsOnlyTheKindsThatOccurAndPluralisesBreaks() {
        val session = preview.lastSession!!
        val noLongRest = session.copy(
            timeline = session.timeline.filter { it.kind != TimelineKind.LONG_REST },
            longBreakCount = 0,
            underTensionPercent = null,
        )
        val model = ExtrasText.sessionTimeline(noLongRest)
        assertThat(model.kinds).containsExactly(TimelineKind.LIFTING, TimelineKind.REST).inOrder()
        assertThat(model.tails).containsExactly("")
        assertThat(model.tail).isEmpty()
        assertThat(ExtrasText.sessionTimeline(session.copy(longBreakCount = 2)).tail).endsWith("2 long breaks")
    }

    @Test
    fun withoutSetTimesTheWidgetSaysSoInsteadOfDrawingABar() {
        val untimed = preview.lastSession!!.copy(timeline = emptyList(), underTensionPercent = null, longBreakCount = 0)
        val model = ExtrasText.sessionTimeline(untimed)
        assertThat(model.hasBar).isFalse()
        assertThat(model.kinds).isEmpty()
        assertThat(model.tail).isEqualTo(" · 18 sets")
        assertThat(model.tails).containsExactly(" · 18 sets", "").inOrder()
        assertThat(model.message).isEqualTo("No set times were recorded for this workout.")
        assertThat(ExtrasText.sessionTimeline(untimed.copy(loggedSets = 1)).tail).isEqualTo(" · 1 set")
    }

    @Test
    fun withoutAWorkoutTheTimelineAsksForOne() {
        val model = ExtrasText.sessionTimeline(empty.lastSession)
        assertThat(model.name).isNull()
        assertThat(model.hasBar).isFalse()
        assertThat(model.headline).isEmpty()
        assertThat(model.message).isEqualTo("Finish a workout to see how its time was spent.")
    }

    @Test
    fun theLegendWordsMatchTheKinds() {
        assertThat(TimelineKind.entries.map { ExtrasText.timelineLabel(it) }).containsExactly("Lifting", "Rest", "Long rest").inOrder()
    }
}
