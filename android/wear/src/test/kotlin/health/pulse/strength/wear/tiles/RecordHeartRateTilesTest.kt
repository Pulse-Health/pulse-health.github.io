package health.pulse.strength.wear.tiles

import android.app.Application
import androidx.test.core.app.ApplicationProvider
import com.google.common.truth.Truth.assertThat
import health.pulse.strength.wear.WearFixtures
import health.pulse.strength.wear.WearFixtures.now
import health.pulse.strength.wear.WearMainActivity
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/** WA-06 Record card and WA-09 Set-by-set heart rate. */
@RunWith(RobolectricTestRunner::class)
class RecordHeartRateTilesTest {
    private val context = ApplicationProvider.getApplicationContext<Application>()
    private val ui = tileUi(context)

    private fun record(view: health.pulse.strength.wear.data.WearView) = RecordTile().plan(ui, view, now).entries().single().second.inspect()

    private fun heartRate(view: health.pulse.strength.wear.data.WearView) = HeartRateTile().plan(ui, view, now).entries().single().second.inspect()

    // region Record

    @Test
    fun aFreshRecordIsAGoldCard() {
        val inspected = record(WearFixtures.view())

        assertThat(inspected.textValues).containsAtLeast("NEW RECORD", "Bench Press", "85 × 5", "e1RM 99 kg · +4 kg")
        assertThat(inspected.images).contains(TileIcons.TROPHY)
        assertThat(inspected.boxBackgrounds).containsExactly(0xFF3A2E00.toInt())
    }

    @Test
    fun aRecordIsReadAsOneSentenceAndATapOpensTheApp() {
        val inspected = record(WearFixtures.view())

        assertThat(inspected.descriptions).contains("NEW RECORD. Bench Press, 85 × 5, e1RM 99 kg, +4 kg")
        val click = inspected.clicks.single()
        assertThat(click.kind).isEqualTo(LayoutInspector.Kind.LAUNCH)
        assertThat(click.className).isEqualTo(WearMainActivity::class.java.name)
    }

    @Test
    fun anOlderRecordIsTheQuieterLatestRecordOnBlack() {
        val snapshot = WearFixtures.preview.copy(latestPR = WearFixtures.preview.latestPR!!.copy(isFresh = false, deltaKg = 0.0))

        val inspected = record(WearFixtures.view(snapshot))

        assertThat(inspected.textValues).contains("LATEST RECORD")
        assertThat(inspected.textValues).contains("e1RM 99 kg")
        assertThat(inspected.boxBackgrounds).isEmpty()
    }

    @Test
    fun withoutRecordsAndBeforeTheFirstSyncTheTileSaysSo() {
        assertThat(record(WearFixtures.view(WearFixtures.preview.copy(latestPR = null))).textValues).contains("No records yet")
        assertThat(record(WearFixtures.view(isPlaceholder = true)).textValues).contains("Waiting for your phone")
    }

    // endregion

    // region Heart rate

    @Test
    fun theHeartRateTileShowsTheAverageThePeakAndTheSession() {
        val inspected = heartRate(WearFixtures.view())

        assertThat(inspected.textValues).containsAtLeast("Heart rate", "avg 118 · peak 151", "Upper B · Pull")
        assertThat(inspected.images).contains(TileIcons.HEART)
    }

    @Test
    fun theHeartRateIsReadBucketByBucketAndATapOpensTheApp() {
        val inspected = heartRate(WearFixtures.view())

        assertThat(inspected.descriptions.single()).contains("131 beats per minute, effort")
        assertThat(inspected.clicks.single().kind).isEqualTo(LayoutInspector.Kind.LAUNCH)
    }

    @Test
    fun withoutACurveTheTileSaysNoneWasRecordedInThatSession() {
        val session = WearFixtures.preview.lastSession!!.copy(heartRateBars = emptyList())

        val inspected = heartRate(WearFixtures.view(WearFixtures.preview.copy(lastSession = session)))

        assertThat(inspected.textValues).containsAtLeast("No heart rate yet", "None was recorded in Upper B · Pull.")
    }

    @Test
    fun withoutASessionTheTileAsksForOne() {
        val inspected = heartRate(WearFixtures.view(WearFixtures.preview.copy(lastSession = null)))

        assertThat(inspected.textValues).contains("Finish a workout to see it here.")
        assertThat(heartRate(WearFixtures.view(isPlaceholder = true)).textValues).contains("Waiting for your phone")
    }

    // endregion
}
