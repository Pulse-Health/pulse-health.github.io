package health.pulse.strength.wear.sync

import android.app.Application
import android.content.Context
import android.net.Uri
import androidx.test.core.app.ApplicationProvider
import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataItem
import com.google.android.gms.wearable.DataItemAsset
import com.google.android.gms.wearable.PutDataMapRequest
import com.google.common.truth.Truth.assertThat
import health.pulse.strength.core.widgets.WearProtocol
import health.pulse.strength.core.widgets.WidgetJson
import health.pulse.strength.core.widgets.WidgetSnapshot
import health.pulse.strength.wear.WearFixtures
import health.pulse.strength.wear.data.FakePhoneLink
import health.pulse.strength.wear.data.WearRuntime
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner

/** The Data Layer listener of the watch: which changes it takes, and what it hands on. */
@RunWith(RobolectricTestRunner::class)
class WearSnapshotListenerServiceTest {
    private val context: Context = ApplicationProvider.getApplicationContext<Application>()
    private val changes = mutableListOf<WidgetSnapshot>()
    private lateinit var service: WearSnapshotListenerService

    @Before
    fun setUp() {
        SnapshotIngest.resetForTest()
        WearRuntime.installForTest(null, FakePhoneLink())
        SnapshotIngest.effects = object : SnapshotIngest.Effects {
            override fun snapshotChanged(context: Context, snapshot: WidgetSnapshot) {
                changes += snapshot
            }
        }
        service = Robolectric.setupService(WearSnapshotListenerService::class.java)
    }

    @After
    fun tearDown() {
        SnapshotIngest.resetForTest()
        WearRuntime.resetForTest()
    }

    private fun item(path: String, json: String?): DataItem {
        val request = PutDataMapRequest.create(path)
        if (json != null) request.dataMap.putString(WearProtocol.KEY_JSON, json)
        val put = request.asPutDataRequest()
        return object : DataItem {
            override fun getUri(): Uri = put.uri
            override fun getData(): ByteArray = put.data!!
            override fun setData(data: ByteArray?): DataItem = this
            override fun getAssets(): MutableMap<String, DataItemAsset> = mutableMapOf()
            override fun freeze(): DataItem = this
            override fun isDataValid(): Boolean = true
        }
    }

    private fun event(type: Int, item: DataItem): DataEvent = object : DataEvent {
        override fun getType(): Int = type
        override fun getDataItem(): DataItem = item
        override fun freeze(): DataEvent = this
        override fun isDataValid(): Boolean = true
    }

    private fun json(snapshot: WidgetSnapshot) = WidgetJson.encodeSnapshot(snapshot)

    private fun otherWeek() = WearFixtures.preview.copy(week = WearFixtures.preview.week.copy(completed = 2))

    @Test
    fun aChangedSnapshotItemIsStoredAndPublished() {
        service.handle(listOf(event(DataEvent.TYPE_CHANGED, item(WearProtocol.SNAPSHOT_PATH, json(otherWeek())))))

        assertThat(WearRuntime.current()).isEqualTo(otherWeek())
        assertThat(changes).containsExactly(otherWeek())
    }

    @Test
    fun aDeletedItemIsIgnored() {
        service.handle(listOf(event(DataEvent.TYPE_DELETED, item(WearProtocol.SNAPSHOT_PATH, json(otherWeek())))))

        assertThat(WearRuntime.isPlaceholder.value).isTrue()
        assertThat(changes).isEmpty()
    }

    @Test
    fun anItemOfAnotherPathIsIgnored() {
        service.handle(listOf(event(DataEvent.TYPE_CHANGED, item("/pulse/something-else", json(otherWeek())))))

        assertThat(WearRuntime.isPlaceholder.value).isTrue()
    }

    @Test
    fun anItemWithoutTheJsonKeyChangesNothing() {
        service.handle(listOf(event(DataEvent.TYPE_CHANGED, item(WearProtocol.SNAPSHOT_PATH, null))))

        assertThat(WearRuntime.isPlaceholder.value).isTrue()
        assertThat(changes).isEmpty()
    }

    @Test
    fun anItemWithGarbageInsideChangesNothing() {
        service.handle(listOf(event(DataEvent.TYPE_CHANGED, item(WearProtocol.SNAPSHOT_PATH, "{not json"))))

        assertThat(WearRuntime.isPlaceholder.value).isTrue()
    }

    @Test
    fun severalChangesAreAppliedInOrder() {
        val first = otherWeek()
        val second = WearFixtures.withWorkout(WearFixtures.workout())

        service.handle(
            listOf(
                event(DataEvent.TYPE_CHANGED, item(WearProtocol.SNAPSHOT_PATH, json(first))),
                event(DataEvent.TYPE_CHANGED, item(WearProtocol.SNAPSHOT_PATH, json(second))),
            ),
        )

        assertThat(WearRuntime.current()).isEqualTo(second)
        assertThat(changes).containsExactly(first, second).inOrder()
    }
}
