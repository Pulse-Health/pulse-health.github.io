package health.pulse.strength.widgets.home

import android.content.Context
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.test.core.app.ApplicationProvider
import com.google.common.truth.Truth.assertThat
import health.pulse.strength.core.widgets.WidgetSnapshot
import kotlinx.coroutines.test.runTest
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * What each widget actually shows once Glance has translated it to views: the texts and the click targets at the sizes of a phone
 * launcher, with the preview snapshot and with no history. A text missing here is a text the user would not see (a container that is over
 * Glance's limit drops its extra children silently).
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], qualifiers = "xxhdpi")
class HomeWidgetContentTest {
    private val context: Context get() = ApplicationProvider.getApplicationContext()
    private val preview = HomeFixtures.preview
    private val empty = HomeFixtures.empty

    private suspend fun render(name: String, width: Int, height: Int, snapshot: WidgetSnapshot): Rendered {
        val case = WidgetCases.named(name)
        return GlanceHarness.inflate(context, DpSize(width.dp, height.dp), snapshot, case.dynamic, case.content)
    }

    private fun Rendered.assertShows(vararg expected: String) {
        assertThat(texts).containsAtLeastElementsIn(expected.toList())
    }

    private fun Rendered.assertHides(vararg unexpected: String) {
        unexpected.forEach { assertThat(texts).doesNotContain(it) }
    }

    // region Next up

    @Test
    fun nextUpCompactShowsTheTemplateAndAStartButton() = runTest {
        val rendered = render("next-up", 160, 160, preview)
        rendered.assertShows("NEXT UP", "Upper A · Push", "6 exercises · ~55 min", "Start")
        assertThat(rendered.descriptions).contains("Start Upper A · Push")
        // The card opens the app, the button starts the workout.
        assertThat(rendered.clickable).isEqualTo(2)
    }

    @Test
    fun nextUpAtTheSmallestSizeDropsTheSummaryButKeepsTheButton() = runTest {
        val rendered = render("next-up", 110, 110, preview)
        rendered.assertShows("NEXT UP", "Upper A · Push", "Start")
        rendered.assertHides("6 exercises · ~55 min")
    }

    @Test
    fun nextUpWideListsTheFirstExercisesWithTheirPlan() = runTest {
        val rendered = render("next-up", 320, 150, preview)
        rendered.assertShows(
            "NEXT UP", "Upper A · Push", "Done 5 days ago", "Upper / Lower · workout 1 of 3", "Start",
            "Bench Press", "3 × 85", "Incline Dumbbell Press", "3 × 28", "Overhead Press", "3 × 45", "Lateral Raise", "3 × 8", "+ 2 more",
        )
        rendered.assertHides("Triceps Pushdown")
    }

    @Test
    fun nextUpWithoutTemplatesSaysWhatToDoAndOffersNoStart() = runTest {
        val rendered = render("next-up", 160, 160, empty)
        rendered.assertShows("No workouts yet", "Open Pulse Strength to create a workout")
        rendered.assertHides("Start")
        assertThat(rendered.clickable).isEqualTo(1)
    }

    // endregion

    // region Weekly goal

    @Test
    fun weeklyGoalShowsAllSevenDaysAndTheRing() = runTest {
        // Regression: seven dots plus six spacers were 13 children in one Row, and Glance silently drops everything past the tenth.
        val rendered = render("weekly-goal", 160, 160, preview)
        assertThat(rendered.texts).containsExactly("3/4", "this week", "M", "T", "W", "T", "F", "S", "S").inOrder()
        assertThat(rendered.descriptions).contains("3 of 4 workouts this week")
        assertThat(rendered.descriptions).contains("3 of 4 workouts this week, 6 week streak")
    }

    @Test
    fun weeklyGoalWideSaysHowManyAreToGo() = runTest {
        val rendered = render("weekly-goal", 320, 150, preview)
        rendered.assertShows("3/4", "1 to go", "6 week streak", "M", "S")
        val reached = render("weekly-goal", 320, 150, preview.copy(week = preview.week.copy(completed = 4)))
        reached.assertShows("4/4", "Goal reached")
    }

    @Test
    fun weeklyGoalAtTheSmallestSizeShrinksTheRingAndDropsItsCaption() = runTest {
        val rendered = render("weekly-goal", 110, 110, preview)
        assertThat(rendered.texts.first()).isEqualTo("3/4")
        rendered.assertHides("this week")
        assertThat(rendered.texts.drop(1)).containsExactly("M", "T", "W", "T", "F", "S", "S").inOrder()
    }

    @Test
    fun theThemedVariantShowsTheSameContent() = runTest {
        val rendered = render("weekly-goal-themed", 160, 160, preview)
        assertThat(rendered.texts).containsExactly("3/4", "this week", "M", "T", "W", "T", "F", "S", "S").inOrder()
    }

    @Test
    fun weeklyGoalWithNoHistoryShowsZeros() = runTest {
        val rendered = render("weekly-goal", 160, 160, empty)
        rendered.assertShows("0/4", "this week")
    }

    // endregion

    // region Small cards

    @Test
    fun prSpotlightShowsTheRecord() = runTest {
        render("pr-spotlight", 160, 160, preview).assertShows("NEW PR", "Bench Press", "85 × 5", "e1RM 99 kg · +4")
        render("pr-spotlight", 110, 110, preview).assertHides("e1RM 99 kg · +4")
        render("pr-spotlight", 160, 160, empty).assertShows("PERSONAL RECORD", "No records yet", "Your first record shows up here.")
    }

    @Test
    fun muscleFreshnessListsTheFourLongestRested() = runTest {
        render("muscle-freshness", 160, 160, preview)
            .assertShows("READY TO TRAIN", "Core", "never", "Legs", "7d", "Chest", "5d", "Shoulders")
        // Never trained: every group is "never".
        val none = render("muscle-freshness", 160, 160, empty)
        assertThat(none.texts.count { it == "never" }).isEqualTo(4)
        // Fewer rows on a short widget.
        val short = render("muscle-freshness", 110, 110, preview)
        assertThat(short.texts.count { it == "never" || it.endsWith("d") }).isEqualTo(2)
    }

    @Test
    fun overloadShowsLastTimeAndTheTarget() = runTest {
        render("overload", 160, 160, preview).assertShows("5d ago", "Last time", "Bench Press", "80 × 6", "Try 82.5 today")
        val medium = render("overload", 160, 130, preview)
        medium.assertShows("5d ago", "Bench Press", "80 × 6", "Try 82.5 today")
        medium.assertHides("Last time")
        render("overload", 160, 160, empty).assertShows("No target yet", "Finish a workout to get one")
    }

    // endregion

    // region 4x2

    @Test
    fun weeklySetsShowsFourBarsAndTheTargetRange() = runTest {
        val rendered = render("weekly-sets", 320, 130, preview)
        rendered.assertShows("Sets this week", "target 10–14", "Chest", "12", "Back", "10", "Shoulders", "9", "Legs", "6")
        rendered.assertHides("Arms", "Core")
        // Tall enough for all six groups: the caption turns into the week's total.
        val tall = render("weekly-sets", 320, 200, preview)
        tall.assertShows("37 of 48 sets", "Arms", "Core")
        render("weekly-sets", 320, 130, empty).assertShows("Chest", "0", "target 10–14")
    }

    @Test
    fun liftTrendShowsTheCurrentValueTheChangeAndTheRecordLabel() = runTest {
        val rendered = render("lift-trend", 320, 150, preview)
        rendered.assertShows("Bench Press", "Estimated 1RM · 3 sessions", "96", "−3 kg vs last", "PR", "10d", "today")
        assertThat(rendered.descriptions).contains("Estimated one-rep max over the last 3 sessions: 93, 99, 96 kilograms")
        // A short widget leaves out the day labels, a tiny one the "PR" tag.
        render("lift-trend", 320, 130, preview).assertHides("10d")
        render("lift-trend", 250, 110, preview).assertHides("PR", "10d")
        render("lift-trend", 320, 150, empty).assertShows("No lifts yet", "Train a lift in a few workouts and its estimated 1RM shows up here.")
    }

    @Test
    fun liftTrendShowsTheChosenLift() = runTest {
        val rendered = GlanceHarness.inflate(context, DpSize(320.dp, 150.dp), preview) { LiftTrendContent(it, "squat") }
        rendered.assertShows("Back Squat", "124", "+3 kg vs last")
        rendered.assertHides("Bench Press")
    }

    // endregion

    // region 4x4 and 6x4

    @Test
    fun trainingWeekShowsEverySectionOnAFullSizeWidget() = runTest {
        val rendered = render("training-week", 320, 320, preview)
        rendered.assertShows(
            "This week", "3 of 4", "M", "T", "W", "F", "S", "UA", "LA", "UB",
            "LAST SESSION", "Upper B · Pull", "Wed", "51", " min", "18", "8.4", " t", "Duration", "Sets", "Volume",
            "Bench Press PR", "85 × 5", "Start Upper A · Push",
        )
        assertThat(rendered.descriptions).contains("Start Upper A · Push")
    }

    @Test
    fun trainingWeekDropsTheLastSessionThenTheRecordOnShorterWidgets() = runTest {
        val noSession = render("training-week", 250, 250, preview)
        noSession.assertShows("This week", "UA", "Bench Press PR", "Start Upper A · Push")
        noSession.assertHides("LAST SESSION")
        val short = render("training-week", 250, 180, preview)
        short.assertShows("This week", "UA", "Start Upper A · Push")
        short.assertHides("LAST SESSION", "Bench Press PR")
    }

    @Test
    fun trainingWeekWithNoHistoryExplainsAndOffersTheApp() = runTest {
        val rendered = render("training-week", 320, 320, empty)
        rendered.assertShows(
            "0 of 4", "No sessions yet", "Your first workout shows up here.",
            "Open Pulse Strength to create a workout", "Open Pulse Strength",
        )
        rendered.assertHides("Bench Press PR")
    }

    @Test
    fun templateLauncherListsEveryTemplateAndTheEmptyWorkout() = runTest {
        val rendered = render("template-launcher", 320, 320, preview)
        rendered.assertShows(
            "Start a workout",
            "Upper A · Push", "6 exercises · ~55 min · 5d ago",
            "Lower A · Quads", "5 exercises · ~50 min · 4d ago",
            "Upper B · Pull", "6 exercises · ~55 min · 3d ago",
            "Empty workout", "Add exercises as you go", "Filled button: next in your rotation",
        )
        // The card, three templates and the empty workout.
        assertThat(rendered.clickable).isEqualTo(5)
        assertThat(rendered.descriptions).containsAtLeast("Start Upper A · Push, next in your rotation", "Start Lower A · Quads", "Start an empty workout")
    }

    @Test
    fun templateLauncherNamesTheTemplatesThatDoNotFit() = runTest {
        val rendered = render("template-launcher", 250, 250, preview)
        rendered.assertShows("Upper A · Push", "Empty workout")
        assertThat(rendered.texts.any { it.startsWith("+ ") && it.endsWith(" more in Pulse Strength") }).isTrue()
    }

    @Test
    fun templateLauncherWithoutTemplatesStillStartsAnEmptyWorkout() = runTest {
        val rendered = render("template-launcher", 320, 320, empty)
        rendered.assertShows("Start a workout", "Open Pulse Strength to create a workout", "Empty workout")
        assertThat(rendered.clickable).isEqualTo(2)
    }

    @Test
    fun monthHeatmapShowsTheWholeMonthMondayFirst() = runTest {
        val rendered = render("month-heatmap", 320, 320, preview)
        rendered.assertShows("October", "7", " sessions", "M", "T", "W", "F", "S", "Volume", "more")
        (1..31).forEach { assertThat(rendered.texts).contains(it.toString()) }
        assertThat(rendered.descriptions.first()).isEqualTo("October: 7 sessions. Trained on days 2, 5, 7, 9, 12, 13 and 14.")
        val none = render("month-heatmap", 320, 320, empty)
        none.assertShows("October", "0")
        assertThat(none.descriptions.first()).isEqualTo("October: 0 sessions. No training days yet.")
    }

    @Test
    fun trainingBlockShowsTheGridAndTheTiles() = runTest {
        val rendered = render("training-block", 480, 300, preview)
        rendered.assertShows(
            "Block 2 · Week 3 of 4", "Upper / Lower", "Wk 1", "Wk 2", "Wk 3", "Wk 4", "Push", "Legs", "Pull",
            "10 / 12", "Sessions done", "+4 kg", "Bench Press e1RM", "1", "Missed",
        )
        // Every cell carries a glyph or a ring besides its colour: 7 done, 1 missed and the images of the cells.
        assertThat(rendered.images).isAtLeast(8)
        assertThat(rendered.descriptions.first()).startsWith("Training block, Block 2 · Week 3 of 4. 10 of 12 sessions done, 1 missed.")
    }

    @Test
    fun trainingBlockOnAShortWidgetLeavesOutTheTiles() = runTest {
        val rendered = render("training-block", 320, 180, preview)
        rendered.assertShows("Block 2 · Week 3 of 4", "Push")
        rendered.assertHides("Sessions done")
    }

    @Test
    fun trainingBlockWithoutHistoryExplainsWhatStartsOne() = runTest {
        render("training-block", 480, 300, preview.copy(block = null))
            .assertShows("No block yet", "Finish your first workout to start a four-week training block.")
        render("training-block", 480, 300, empty).assertShows("No block yet", "Open Pulse Strength to create a workout")
    }

    // endregion
}
