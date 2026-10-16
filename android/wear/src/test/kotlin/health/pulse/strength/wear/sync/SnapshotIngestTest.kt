package health.pulse.strength.wear.sync

import android.app.Application
import android.content.Context
import androidx.test.core.app.ApplicationProvider
import com.google.common.truth.Truth.assertThat
import health.pulse.strength.core.widgets.WidgetJson
import health.pulse.strength.core.widgets.WidgetSnapshot
import health.pulse.strength.wear.WearFixtures
import health.pulse.strength.wear.data.AcceptResult
import health.pulse.strength.wear.data.FakePhoneLink
import health.pulse.strength.wear.data.PhoneLink
import health.pulse.strength.wear.data.WearRuntime
import kotlinx.coroutines.delay
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/** What happens when the phone's snapshot reaches the watch: stored, published, and every surface told. */
@RunWith(RobolectricTestRunner::class)
class SnapshotIngestTest {
    private val context: Context = ApplicationProvider.getApplicationContext<Application>()
    private val link = FakePhoneLink()
    private val changes = mutableListOf<WidgetSnapshot>()

    @Before
    fun setUp() {
        SnapshotIngest.resetForTest()
        WearRuntime.installForTest(null, link)
        SnapshotIngest.effects = object : SnapshotIngest.Effects {
            override fun snapshotChanged(context: Context, snapshot: WidgetSnapshot) {
                changes += snapshot
            }
        }
    }

    @After
    fun tearDown() {
        SnapshotIngest.resetForTest()
        WearRuntime.resetForTest()
    }

    private fun json(snapshot: WidgetSnapshot) = WidgetJson.encodeSnapshot(snapshot)

    private fun otherWeek() = WearFixtures.preview.copy(week = WearFixtures.preview.week.copy(completed = 2))

    @Test
    fun aNewSnapshotIsPublishedAndEverySurfaceIsToldOnce() {
        val result = SnapshotIngest.accept(context, json(otherWeek()))

        assertThat(result).isEqualTo(AcceptResult.UPDATED)
        assertThat(WearRuntime.current()).isEqualTo(otherWeek())
        assertThat(changes).containsExactly(otherWeek())
    }

    @Test
    fun theSameSnapshotAgainTellsNobody() {
        SnapshotIngest.accept(context, json(otherWeek()))

        val result = SnapshotIngest.accept(context, json(otherWeek()))

        assertThat(result).isEqualTo(AcceptResult.UNCHANGED)
        assertThat(changes).hasSize(1)
    }

    @Test
    fun garbageAndNewerSchemasTellNobodyAndChangeNothing() {
        assertThat(SnapshotIngest.accept(context, "{not json")).isEqualTo(AcceptResult.REJECTED)
        assertThat(SnapshotIngest.accept(context, null)).isEqualTo(AcceptResult.REJECTED)
        val newer = json(WearFixtures.preview.copy(schemaVersion = WidgetSnapshot.CURRENT_SCHEMA_VERSION + 1))
        assertThat(SnapshotIngest.accept(context, newer)).isEqualTo(AcceptResult.REJECTED)

        assertThat(changes).isEmpty()
        assertThat(WearRuntime.isPlaceholder.value).isTrue()
    }

    @Test
    fun aRunningWorkoutReachesTheSurfaces() {
        val running = WearFixtures.withWorkout(WearFixtures.workout())

        SnapshotIngest.accept(context, json(running))

        assertThat(changes.single().active).isEqualTo(WearFixtures.workout())
    }

    // region Catching up

    @Test
    fun withOnlyThePlaceholderTheStoredItemOfTheDataLayerIsPulled() = runTest {
        link.stored = json(otherWeek())

        SnapshotIngest.ensureData(context)

        assertThat(WearRuntime.isPlaceholder.value).isFalse()
        assertThat(changes).containsExactly(otherWeek())
    }

    @Test
    fun withRealDataNothingIsPulled() = runTest {
        SnapshotIngest.accept(context, json(otherWeek()))
        link.stored = json(WearFixtures.preview)

        SnapshotIngest.ensureData(context)

        assertThat(WearRuntime.current()).isEqualTo(otherWeek())
    }

    @Test
    fun theDataLayerIsAskedOnceAMinuteAtMost() = runTest {
        SnapshotIngest.ensureData(context, nowMillis = 1_000_000L)
        link.stored = json(otherWeek())

        SnapshotIngest.ensureData(context, nowMillis = 1_000_000L + 30_000L)
        assertThat(WearRuntime.isPlaceholder.value).isTrue()

        SnapshotIngest.ensureData(context, nowMillis = 1_000_000L + 61_000L)
        assertThat(WearRuntime.isPlaceholder.value).isFalse()
    }

    @Test
    fun aPhoneThatNeverAnswersDoesNotHoldASurfaceBack() = runTest {
        WearRuntime.installForTest(
            null,
            object : PhoneLink {
                override suspend fun sendMessage(path: String, payload: ByteArray): Boolean = false

                override suspend fun latestSnapshotJson(): String? {
                    delay(60_000)
                    return null
                }
            },
        )

        SnapshotIngest.ensureData(context)

        assertThat(WearRuntime.isPlaceholder.value).isTrue()
    }

    @Test
    fun aFailingDataLayerLeavesThePlaceholderAlone() = runTest {
        link.failure = java.io.IOException("no play services")

        SnapshotIngest.ensureData(context)

        assertThat(WearRuntime.isPlaceholder.value).isTrue()
        assertThat(changes).isEmpty()
    }

    // endregion
}
