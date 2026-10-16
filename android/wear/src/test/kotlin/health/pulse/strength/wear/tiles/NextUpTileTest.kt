package health.pulse.strength.wear.tiles

import android.app.Application
import androidx.test.core.app.ApplicationProvider
import com.google.common.truth.Truth.assertThat
import health.pulse.strength.core.widgets.WidgetCommands
import health.pulse.strength.wear.WearFixtures
import health.pulse.strength.wear.WearFixtures.now
import health.pulse.strength.wear.WearMainActivity
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/** WA-03 Smart Stack: Next up. */
@RunWith(RobolectricTestRunner::class)
class NextUpTileTest {
    private val context = ApplicationProvider.getApplicationContext<Application>()
    private val ui = tileUi(context)
    private val tile = NextUpTile()

    private fun layout(view: health.pulse.strength.wear.data.WearView): LayoutInspector {
        val plan = tile.plan(ui, view, now)
        assertThat(plan.timeline.timelineEntries).hasSize(1)
        return plan.entries().single().second.inspect()
    }

    @Test
    fun theTileShowsTheSplitTheNameAndTheSizeOfTheNextWorkout() {
        val inspected = layout(WearFixtures.view())

        assertThat(inspected.textValues).containsAtLeast("Push day", "Upper A · Push", "6 exercises · ~55 min", "Start")
    }

    @Test
    fun startOpensTheWatchAppWithTheStartNextCommand() {
        val click = layout(WearFixtures.view()).clicks.single()

        assertThat(click.kind).isEqualTo(LayoutInspector.Kind.LAUNCH)
        assertThat(click.className).isEqualTo(WearMainActivity::class.java.name)
        assertThat(click.extras).containsExactly(WearMainActivity.EXTRA_COMMAND, WidgetCommands.START_NEXT)
    }

    @Test
    fun startIsDescribedForScreenReadersWithTheNameOfTheWorkout() {
        assertThat(layout(WearFixtures.view()).descriptions).contains("Start Upper A · Push")
    }

    @Test
    fun whileAWorkoutRunsTheTileOffersToOpenItInsteadOfStartingAnother() {
        val inspected = layout(WearFixtures.view(WearFixtures.withWorkout(WearFixtures.workout())))

        assertThat(inspected.textValues).containsAtLeast("In progress", "Upper A · Push", "7 of 20 sets", "Open")
        assertThat(inspected.textValues).doesNotContain("Start")
        assertThat(inspected.clicks.single().extras).isEmpty()
    }

    @Test
    fun withoutTemplatesTheTileSaysWhereToAddOne() {
        val inspected = layout(WearFixtures.view(WearFixtures.preview.copy(nextUp = null)))

        assertThat(inspected.textValues).containsAtLeast("No workout yet", "Add one in Pulse on your phone.", "Open")
        assertThat(inspected.clicks.single().kind).isEqualTo(LayoutInspector.Kind.LAUNCH)
    }

    @Test
    fun beforeTheFirstSyncTheTileIsNotMistakenForRealData() {
        val inspected = layout(WearFixtures.view(isPlaceholder = true))

        assertThat(inspected.textValues).containsAtLeast("Waiting for your phone", "Open")
        assertThat(inspected.textValues).doesNotContain("Upper A · Push")
    }

    @Test
    fun aLongNameStaysCompleteInTheLayoutAndTheRendererEllipsizesIt() {
        val long = "Upper Body Hypertrophy Block with Extra Accessories and Mobility"
        val snapshot = WearFixtures.preview.copy(nextUp = WearFixtures.preview.nextUp!!.copy(name = long))

        val inspected = layout(WearFixtures.view(snapshot))

        assertThat(inspected.textValues).contains(long)
    }

    @Test
    fun theTileIsRefreshedEveryHalfHour() {
        val plan = tile.plan(ui, WearFixtures.view(), now)

        assertThat(plan.freshnessMillis).isEqualTo(30 * 60 * 1000L)
        assertThat(plan.resourcesVersion).isEqualTo(TileIcons.VERSION)
    }
}
