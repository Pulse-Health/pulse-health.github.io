package health.pulse.strength.wear.tiles

import android.app.Application
import android.content.Context
import android.graphics.BitmapFactory
import androidx.test.core.app.ApplicationProvider
import com.google.common.truth.Truth.assertThat
import health.pulse.strength.wear.WearFixtures
import health.pulse.strength.wear.WearFixtures.now
import health.pulse.strength.wear.data.WearView
import kotlinx.coroutines.test.runTest
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner

/** WA-08 Lift trend: the layout, the lift that a tap moves to, and the picture of the line. */
@RunWith(RobolectricTestRunner::class)
class LiftTrendTileTest {
    private val context = ApplicationProvider.getApplicationContext<Application>()

    @Before
    fun setUp() {
        context.getSharedPreferences("lift_trend_tile", Context.MODE_PRIVATE).edit().clear().commit()
    }

    private fun inspect(view: WearView) = LiftTrendTile().plan(tileUi(context), view, now).entries().single().second.inspect()

    // region Layout

    @Test
    fun theTileShowsTheLiftsEstimatedMaxItsChangeAndTheLine() {
        val inspected = inspect(WearFixtures.view())

        assertThat(inspected.textValues).containsAtLeast("Bench Press", "96", "kg e1RM", "3 sessions · −3 kg")
        assertThat(inspected.images).containsExactly("sparkline")
    }

    @Test
    fun theTileIsReadAsOneSentenceAndTellsHowToChangeTheLift() {
        val description = inspect(WearFixtures.view()).descriptions.single()

        assertThat(description).startsWith("Bench Press estimated one rep max 96 kilograms")
        assertThat(description).contains("record in session 2 of 3")
        assertThat(description).endsWith("Tap for the next lift.")
    }

    @Test
    fun aTapMovesToTheNextLiftWhenThereAreSeveral() {
        val click = inspect(WearFixtures.view()).clicks.single()

        assertThat(click.kind).isEqualTo(LayoutInspector.Kind.LOAD)
        assertThat(TileClicks.actionOf(click.id)).isEqualTo("nextLift")
    }

    @Test
    fun withASingleLiftATapOpensTheAppInstead() {
        val only = WearFixtures.preview.copy(lifts = WearFixtures.preview.lifts.take(1))

        val inspected = inspect(WearFixtures.view(only))

        assertThat(inspected.clicks.single().kind).isEqualTo(LayoutInspector.Kind.LAUNCH)
        assertThat(inspected.descriptions.single()).doesNotContain("Tap for the next lift")
    }

    @Test
    fun withoutLiftsAndBeforeTheFirstSyncTheTileSaysSo() {
        assertThat(inspect(WearFixtures.view(WearFixtures.preview.copy(lifts = emptyList()))).textValues).contains("No trend yet")
        assertThat(inspect(WearFixtures.view(isPlaceholder = true)).textValues).contains("Waiting for your phone")
    }

    // endregion

    // region Choosing the lift

    @Test
    fun theTileRemembersWhichLiftWasChosen() = runTest {
        val service = Robolectric.setupService(LiftTrendTile::class.java)

        service.onClick("nextLift")
        val inspected = service.plan(tileUi(context), WearFixtures.view(), now).entries().single().second.inspect()

        assertThat(inspected.textValues).contains("Back Squat")
    }

    @Test
    fun tappingThroughAllLiftsComesBackToTheFirst() = runTest {
        val service = Robolectric.setupService(LiftTrendTile::class.java)

        repeat(5) { service.onClick("nextLift") }
        val inspected = service.plan(tileUi(context), WearFixtures.view(), now).entries().single().second.inspect()

        assertThat(inspected.textValues).contains("Bench Press")
    }

    @Test
    fun anotherActionDoesNotMoveTheLift() = runTest {
        val service = Robolectric.setupService(LiftTrendTile::class.java)

        service.onClick("open")
        val inspected = service.plan(tileUi(context), WearFixtures.view(), now).entries().single().second.inspect()

        assertThat(inspected.textValues).contains("Bench Press")
    }

    // endregion

    // region Picture

    @Test
    fun theImageResourceIsAPngOfTheSizeTheLayoutAsksFor() {
        val service = Robolectric.setupService(LiftTrendTile::class.java)
        val device = deviceParameters(widthDp = 200, heightDp = 200, density = 2f)

        val resources = service.resources("v", device, WearFixtures.view())

        val inline = resources.idToImageMapping.getValue("sparkline").inlineResource!!
        // 62 % of 200 dp, capped at 140 dp, by 40 dp, at 2x.
        assertThat(inline.widthPx).isEqualTo(248)
        assertThat(inline.heightPx).isEqualTo(80)
        val bitmap = BitmapFactory.decodeByteArray(inline.data, 0, inline.data.size)
        assertThat(bitmap.width).isEqualTo(248)
        assertThat(bitmap.height).isEqualTo(80)
    }

    @Test
    fun theRecordIsAGoldDotAndTheOtherPointsAreGreen() {
        val service = Robolectric.setupService(LiftTrendTile::class.java)
        val resources = service.resources("v", deviceParameters(), WearFixtures.view())
        val png = resources.idToImageMapping.getValue("sparkline").inlineResource!!.data
        val bitmap = BitmapFactory.decodeByteArray(png, 0, png.size)

        val values = listOf(93.0, 99.0, 96.0)
        val points = Sparkline.points(values, bitmap.width.toFloat(), bitmap.height.toFloat(), inset = 4.5f * 2f + 1f)

        assertThat(bitmap.getPixel(points[1].x.toInt(), points[1].y.toInt())).isEqualTo(TileColors.GOLD)
        assertThat(bitmap.getPixel(points[0].x.toInt(), points[0].y.toInt())).isEqualTo(TileColors.GREEN)
        assertThat(bitmap.getPixel(points[2].x.toInt(), points[2].y.toInt())).isEqualTo(TileColors.GREEN)
        assertThat(bitmap.getPixel(2, 2)).isEqualTo(0)
    }

    @Test
    fun theImageVersionChangesWithTheLiftAndTheScreenButNotWithTheClock() {
        val tile = LiftTrendTile()
        val first = tile.plan(tileUi(context), WearFixtures.view(), now).resourcesVersion
        val again = tile.plan(tileUi(context), WearFixtures.view(), now.plusSeconds(30)).resourcesVersion
        val otherLift = WearFixtures.preview.copy(lifts = WearFixtures.preview.lifts.drop(1))
        val other = tile.plan(tileUi(context), WearFixtures.view(otherLift), now).resourcesVersion
        val denser = tile.plan(TileUi(context, deviceParameters(density = 3f)), WearFixtures.view(), now).resourcesVersion

        assertThat(again).isEqualTo(first)
        assertThat(other).isNotEqualTo(first)
        assertThat(denser).isNotEqualTo(first)
    }

    @Test
    fun withoutALiftThereIsNoImageToShip() {
        val service = Robolectric.setupService(LiftTrendTile::class.java)

        val resources = service.resources("v", deviceParameters(), WearFixtures.view(WearFixtures.preview.copy(lifts = emptyList())))

        assertThat(resources.idToImageMapping).doesNotContainKey("sparkline")
        assertThat(resources.idToImageMapping).containsKey(TileIcons.DUMBBELL)
    }

    // endregion

    // region Geometry

    @Test
    fun theHighestValueIsAtTheTopAndTheLowestAtTheBottom() {
        val points = Sparkline.points(listOf(93.0, 99.0, 96.0), width = 100f, height = 40f, inset = 4f)

        assertThat(points.map { it.x }).containsExactly(4f, 50f, 96f).inOrder()
        assertThat(points[1].y).isEqualTo(4f)
        assertThat(points[0].y).isEqualTo(36f)
        assertThat(points[2].y).isWithin(0.01f).of(20f)
    }

    @Test
    fun aFlatSeriesSitsAtHalfHeight() {
        val points = Sparkline.points(listOf(58.4, 58.4, 58.4), width = 100f, height = 40f, inset = 4f)

        assertThat(points.map { it.y }.toSet()).containsExactly(20f)
    }

    @Test
    fun oneValueIsAloneInTheMiddle() {
        val points = Sparkline.points(listOf(80.0), width = 100f, height = 40f, inset = 4f)

        assertThat(points).containsExactly(Sparkline.Point(50f, 20f))
        assertThat(Sparkline.points(emptyList(), 100f, 40f, 4f)).isEmpty()
    }

    // endregion
}
