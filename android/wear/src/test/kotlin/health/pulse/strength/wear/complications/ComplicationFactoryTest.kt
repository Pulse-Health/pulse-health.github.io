package health.pulse.strength.wear.complications

import android.app.Application
import android.content.res.Resources
import androidx.test.core.app.ApplicationProvider
import androidx.wear.watchface.complications.data.ComplicationData
import androidx.wear.watchface.complications.data.ComplicationText
import androidx.wear.watchface.complications.data.ComplicationType
import androidx.wear.watchface.complications.data.LongTextComplicationData
import androidx.wear.watchface.complications.data.MonochromaticImageComplicationData
import androidx.wear.watchface.complications.data.NoDataComplicationData
import androidx.wear.watchface.complications.data.PlainComplicationText
import androidx.wear.watchface.complications.data.RangedValueComplicationData
import androidx.wear.watchface.complications.data.ShortTextComplicationData
import androidx.wear.watchface.complications.data.SmallImageComplicationData
import androidx.wear.watchface.complications.data.TimeDifferenceComplicationText
import com.google.common.truth.Truth.assertThat
import health.pulse.strength.core.SnapshotPhase
import health.pulse.strength.core.widgets.WidgetCommands
import health.pulse.strength.wear.WearFixtures
import health.pulse.strength.wear.WearFixtures.now
import health.pulse.strength.wear.WearMainActivity
import health.pulse.strength.wear.data.WearView
import health.pulse.strength.wear.model.RestContent
import java.time.Instant
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf

/** WA-01, WA-02, WA-07, WA-10: the data every complication hands to the watch face. */
@RunWith(RobolectricTestRunner::class)
class ComplicationFactoryTest {
    private val context = ApplicationProvider.getApplicationContext<Application>()
    private val factory = ComplicationFactory(context)
    private val resources: Resources = context.resources
    private val view = WearFixtures.view()

    private fun ComplicationData.textOf(text: ComplicationText?, at: Instant = now): String =
        text!!.getTextAt(resources, at).toString()

    // region Weekly goal

    @Test
    fun theWeeklyGoalGaugeCarriesTheCountTheSplitAndADescription() {
        val data = factory.weeklyGoal(ComplicationType.RANGED_VALUE, view) as RangedValueComplicationData

        assertThat(data.value).isEqualTo(3f)
        assertThat(data.min).isEqualTo(0f)
        assertThat(data.max).isEqualTo(4f)
        assertThat(data.textOf(data.text)).isEqualTo("3/4")
        assertThat(data.textOf(data.title)).isEqualTo("PUSH")
        assertThat(data.textOf(data.contentDescription)).isEqualTo("3 of 4 workouts this week")
        assertThat(data.tapAction).isNotNull()
    }

    @Test
    fun theWeeklyGoalAlsoComesAsShortText() {
        val data = factory.weeklyGoal(ComplicationType.SHORT_TEXT, view) as ShortTextComplicationData

        assertThat(data.textOf(data.text)).isEqualTo("3/4")
        assertThat(data.textOf(data.title)).isEqualTo("WEEK")
    }

    @Test
    fun aTypeTheComplicationDoesNotDeclareGetsNoData() {
        assertThat(factory.weeklyGoal(ComplicationType.LONG_TEXT, view)).isInstanceOf(NoDataComplicationData::class.java)
        assertThat(factory.daysSince(ComplicationType.RANGED_VALUE, view)).isInstanceOf(NoDataComplicationData::class.java)
        assertThat(factory.weeklySets(ComplicationType.SHORT_TEXT, view)).isInstanceOf(NoDataComplicationData::class.java)
        assertThat(factory.streak(ComplicationType.LONG_TEXT, view)).isInstanceOf(NoDataComplicationData::class.java)
        assertThat(factory.nextUp(ComplicationType.RANGED_VALUE, view)).isInstanceOf(NoDataComplicationData::class.java)
        assertThat(factory.start(ComplicationType.LONG_TEXT, view)).isInstanceOf(NoDataComplicationData::class.java)
    }

    // endregion

    // region Days since, next up, streak, weekly sets

    @Test
    fun daysSinceIsThreeDAndAgo() {
        val data = factory.daysSince(ComplicationType.SHORT_TEXT, view) as ShortTextComplicationData

        assertThat(data.textOf(data.text)).isEqualTo("3d")
        assertThat(data.textOf(data.title)).isEqualTo("ago")
        assertThat(data.textOf(data.contentDescription)).isEqualTo("Last workout 3 days ago")
    }

    @Test
    fun nextUpIsTheNameWithTheExerciseCount() {
        val data = factory.nextUp(ComplicationType.LONG_TEXT, view) as LongTextComplicationData

        assertThat(data.textOf(data.text)).isEqualTo("Upper A · Push")
        assertThat(data.textOf(data.title)).isEqualTo("6 exercises")
    }

    @Test
    fun nextUpAsShortTextIsTheSplitWordWithTheDaysSince() {
        val data = factory.nextUp(ComplicationType.SHORT_TEXT, view) as ShortTextComplicationData

        assertThat(data.textOf(data.text)).isEqualTo("PUSH")
        assertThat(data.textOf(data.title)).isEqualTo("5d ago")
    }

    @Test
    fun aVeryLongWorkoutNameIsNotCutForTheLongTextComplication() {
        val name = "Upper Body Hypertrophy Block with Extra Accessories and Mobility"
        val snapshot = WearFixtures.preview.copy(nextUp = WearFixtures.preview.nextUp!!.copy(name = name))

        val data = factory.nextUp(ComplicationType.LONG_TEXT, WearFixtures.view(snapshot)) as LongTextComplicationData

        assertThat(data.textOf(data.text)).isEqualTo(name)
    }

    @Test
    fun shortTextNeverExceedsTheSevenCharactersAComplicationHolds() {
        val snapshot = WearFixtures.preview.copy(nextUp = WearFixtures.preview.nextUp!!.copy(splitLabel = "Shoulders day", daysSince = 120))

        val data = factory.nextUp(ComplicationType.SHORT_TEXT, WearFixtures.view(snapshot)) as ShortTextComplicationData

        assertThat(data.textOf(data.text)).isEqualTo("SHOULDE")
        assertThat(data.textOf(data.title)).isEqualTo("120d")
    }

    @Test
    fun theStreakIsSixWeeksWithAFlame() {
        val data = factory.streak(ComplicationType.SHORT_TEXT, view) as ShortTextComplicationData

        assertThat(data.textOf(data.text)).isEqualTo("6wk")
        assertThat(data.monochromaticImage).isNotNull()
        assertThat(data.textOf(data.contentDescription)).isEqualTo("6 week streak")
    }

    @Test
    fun weeklySetsIsAGaugeOfWorkingSets() {
        val data = factory.weeklySets(ComplicationType.RANGED_VALUE, view) as RangedValueComplicationData

        assertThat(data.value).isEqualTo(37f)
        assertThat(data.max).isEqualTo(48f)
        assertThat(data.textOf(data.text)).isEqualTo("37")
        assertThat(data.textOf(data.title)).isEqualTo("SETS")
    }

    // endregion

    // region Start

    @Test
    fun startComesAsShortTextAndAsBothImageTypes() {
        val short = factory.start(ComplicationType.SHORT_TEXT, view) as ShortTextComplicationData
        val mono = factory.start(ComplicationType.MONOCHROMATIC_IMAGE, view) as MonochromaticImageComplicationData
        val small = factory.start(ComplicationType.SMALL_IMAGE, view) as SmallImageComplicationData

        assertThat(short.textOf(short.text)).isEqualTo("Start")
        assertThat(short.monochromaticImage).isNotNull()
        assertThat(mono.textOf(mono.contentDescription)).isEqualTo("Start Upper A · Push")
        assertThat(small.smallImage.image).isNotNull()
    }

    @Test
    fun tappingStartOpensTheWatchAppWithTheStartNextCommand() {
        val data = factory.start(ComplicationType.MONOCHROMATIC_IMAGE, view)

        val intent = shadowOf(data.tapAction!!).savedIntent
        assertThat(intent.component?.className).isEqualTo(WearMainActivity::class.java.name)
        assertThat(intent.getStringExtra(WearMainActivity.EXTRA_COMMAND)).isEqualTo(WidgetCommands.START_NEXT)
    }

    @Test
    fun theOtherComplicationsOnlyOpenTheApp() {
        val data = factory.weeklyGoal(ComplicationType.RANGED_VALUE, view)

        val intent = shadowOf(data.tapAction!!).savedIntent
        assertThat(intent.component?.className).isEqualTo(WearMainActivity::class.java.name)
        assertThat(intent.hasExtra(WearMainActivity.EXTRA_COMMAND)).isFalse()
    }

    @Test
    fun theStartAndTheOpenTapsAreDistinctPendingIntents() {
        val start = factory.start(ComplicationType.SHORT_TEXT, view).tapAction!!
        val open = factory.daysSince(ComplicationType.SHORT_TEXT, view).tapAction!!

        assertThat(start).isNotEqualTo(open)
    }

    @Test
    fun startDoesNotStartAnythingWhenAWorkoutRunsOrWhenWaiting() {
        val running = factory.start(ComplicationType.SHORT_TEXT, WearFixtures.view(WearFixtures.withWorkout(WearFixtures.workout())))
        val waiting = factory.start(ComplicationType.SHORT_TEXT, WearFixtures.view(isPlaceholder = true))

        assertThat(shadowOf(running.tapAction!!).savedIntent.hasExtra(WearMainActivity.EXTRA_COMMAND)).isFalse()
        assertThat(shadowOf(waiting.tapAction!!).savedIntent.hasExtra(WearMainActivity.EXTRA_COMMAND)).isFalse()
    }

    // endregion

    // region Waiting for the phone

    @Test
    fun beforeTheFirstSyncTheComplicationsAreDashesThatOpenTheApp() {
        val waiting = WearFixtures.view(isPlaceholder = true)

        val goal = factory.weeklyGoal(ComplicationType.RANGED_VALUE, waiting) as RangedValueComplicationData
        val days = factory.daysSince(ComplicationType.SHORT_TEXT, waiting) as ShortTextComplicationData

        assertThat(goal.textOf(goal.text)).isEqualTo("--")
        assertThat(goal.value).isEqualTo(0f)
        assertThat(goal.textOf(goal.contentDescription)).isEqualTo("Waiting for your phone")
        assertThat(days.textOf(days.text)).isEqualTo("--")
        assertThat(days.tapAction).isNotNull()
    }

    // endregion

    // region Rest

    private fun restTimeline(type: ComplicationType, snapshot: WearView) = factory.rest(type, snapshot, now)!!

    private fun resting() = WearFixtures.view(WearFixtures.withWorkout(WearFixtures.resting(seconds = 84, total = 120)))

    @Test
    fun aRunningRestIsACountdownUntilItsEndFollowedByGo() {
        val timeline = restTimeline(ComplicationType.SHORT_TEXT, resting())

        val entries = timeline.timelineEntries.toList()
        assertThat(entries).hasSize(2)
        assertThat(entries[0].validity.start).isEqualTo(now)
        assertThat(entries[0].validity.end).isEqualTo(now.plusSeconds(84))
        assertThat(entries[1].validity.start).isEqualTo(now.plusSeconds(84))
        val over = entries[1].complicationData as ShortTextComplicationData
        assertThat(over.textOf(over.text)).isEqualTo("GO")
        val idle = timeline.defaultComplicationData as ShortTextComplicationData
        assertThat(idle.textOf(idle.text)).isEqualTo("--")
    }

    @Test
    fun theCountdownTextIsDrawnByTheWatchFaceFromTheEndTime() {
        val entries = restTimeline(ComplicationType.SHORT_TEXT, resting()).timelineEntries.toList()

        val counting = entries[0].complicationData as ShortTextComplicationData

        assertThat(counting.text).isInstanceOf(TimeDifferenceComplicationText::class.java)
        assertThat(counting.textOf(counting.text, at = now)).contains("1:24")
        assertThat(counting.textOf(counting.text, at = now.plusSeconds(24))).contains("1:00")
        assertThat(counting.textOf(counting.title)).isEqualTo("REST")
    }

    @Test
    fun theRestGaugeFillsWithTheElapsedTimeThroughADynamicValue() {
        val entries = restTimeline(ComplicationType.RANGED_VALUE, resting()).timelineEntries.toList()

        val counting = entries[0].complicationData as RangedValueComplicationData

        assertThat(counting.dynamicValue).isNotNull()
        assertThat(counting.value).isEqualTo(36f)
        assertThat(counting.min).isEqualTo(0f)
        assertThat(counting.max).isEqualTo(120f)
    }

    @Test
    fun beforeWearOs4TheRestGaugeShowsTheElapsedTimeAsOfTheUpdate() {
        val state = RestContent.Counting(
            startedAt = now.minusSeconds(36),
            endsAt = now.plusSeconds(84),
            totalSeconds = 120,
            remainingSeconds = 84,
        )

        val gauge = factory.staticRestGauge(state, PlainComplicationText.Builder("Rest timer").build()).build()

        assertThat(gauge.dynamicValue).isNull()
        assertThat(gauge.value).isEqualTo(36f)
        assertThat(gauge.min).isEqualTo(0f)
        assertThat(gauge.max).isEqualTo(120f)
    }

    @Test
    fun whenTheRestIsOverTheGaugeIsFullAndSaysGo() {
        val over = WearFixtures.view(WearFixtures.withWorkout(WearFixtures.workout(phase = SnapshotPhase.REST_OVER)))

        val timeline = restTimeline(ComplicationType.RANGED_VALUE, over)

        val entry = timeline.timelineEntries.single()
        val data = entry.complicationData as RangedValueComplicationData
        assertThat(data.value).isEqualTo(data.max)
        assertThat(data.textOf(data.text)).isEqualTo("GO")
        assertThat(entry.validity.end).isEqualTo(now.plusSeconds(600))
    }

    @Test
    fun withoutARestTheComplicationIsAnIdleDash() {
        val timeline = restTimeline(ComplicationType.SHORT_TEXT, view)

        assertThat(timeline.timelineEntries).isEmpty()
        val idle = timeline.defaultComplicationData as ShortTextComplicationData
        assertThat(idle.textOf(idle.text)).isEqualTo("--")
        assertThat(idle.textOf(idle.contentDescription)).isEqualTo("No rest running")
    }

    @Test
    fun aPausedWorkoutFreezesTheRestAtWhatWasLeft() {
        val paused = WearFixtures.view(WearFixtures.withWorkout(WearFixtures.resting().copy(isPaused = true, restFrozenRemaining = 61)))

        val timeline = restTimeline(ComplicationType.SHORT_TEXT, paused)

        val frozen = timeline.defaultComplicationData as ShortTextComplicationData
        assertThat(frozen.textOf(frozen.text)).isEqualTo("1:01")
        assertThat(frozen.textOf(frozen.title)).isEqualTo("PAUSED")
        assertThat(timeline.timelineEntries).isEmpty()
    }

    @Test
    fun theRestComplicationAnswersOnlyItsTwoTypes() {
        assertThat(factory.rest(ComplicationType.LONG_TEXT, view, now)).isNull()
        assertThat(factory.rest(ComplicationType.SMALL_IMAGE, view, now)).isNull()
        assertThat(factory.restPreview(ComplicationType.LONG_TEXT)).isNull()
    }

    @Test
    fun theRestPreviewShowsOneMinuteTwentyFourOfTwoMinutes() {
        val preview = factory.restPreview(ComplicationType.RANGED_VALUE) as RangedValueComplicationData

        assertThat(preview.textOf(preview.text)).isEqualTo("1:24")
        assertThat(preview.value).isEqualTo(36f)
        assertThat(preview.max).isEqualTo(120f)
    }

    // endregion
}
