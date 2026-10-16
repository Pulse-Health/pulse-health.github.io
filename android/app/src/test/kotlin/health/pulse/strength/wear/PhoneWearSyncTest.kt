package health.pulse.strength.wear

import com.google.android.gms.wearable.DataMap
import com.google.android.gms.wearable.PutDataRequest
import com.google.common.truth.Truth.assertThat
import health.pulse.strength.core.widgets.WearProtocol
import health.pulse.strength.core.widgets.WidgetJson
import health.pulse.strength.core.widgets.WidgetSnapshot
import health.pulse.strength.core.widgets.preview
import java.io.IOException
import java.time.Instant
import kotlin.test.assertFailsWith
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/** The phone's push of the snapshot to the watch (the Data Layer item). */
@RunWith(RobolectricTestRunner::class)
class PhoneWearSyncTest {
    private val written = mutableListOf<PutDataRequest>()

    @Before
    fun setUp() = PhoneWearSync.resetForTest()

    @After
    fun tearDown() = PhoneWearSync.resetForTest()

    private val preview get() = WidgetSnapshot.preview

    private fun otherWeek() = preview.copy(week = preview.week.copy(completed = 2))

    private suspend fun push(snapshot: WidgetSnapshot) = PhoneWearSync.push(snapshot) { written += it }

    @Test
    fun theItemIsUrgentAtTheSnapshotPathWithTheJsonUnderItsKey() {
        val request = PhoneWearSync.request(preview)

        assertThat(request.uri.path).isEqualTo(WearProtocol.SNAPSHOT_PATH)
        assertThat(request.isUrgent).isTrue()
        val json = DataMap.fromByteArray(request.data!!).getString(WearProtocol.KEY_JSON)
        assertThat(json).isEqualTo(WidgetJson.encodeSnapshot(preview))
        assertThat(WidgetJson.decodeSnapshot(json!!)).isEqualTo(preview)
    }

    @Test
    fun theFirstSnapshotIsWritten() = runTest {
        push(preview)

        assertThat(written).hasSize(1)
    }

    @Test
    fun theSameContentIsNotWrittenAgain() = runTest {
        push(preview)
        push(preview)

        assertThat(written).hasSize(1)
    }

    @Test
    fun aSnapshotThatOnlyHasANewGenerationTimeIsNotWrittenAgain() = runTest {
        push(preview)
        push(preview.copy(generatedAt = preview.generatedAt.plusSeconds(90)))

        assertThat(written).hasSize(1)
    }

    @Test
    fun aChangedSnapshotIsWrittenWithItsOwnGenerationTime() = runTest {
        push(preview)
        val later = otherWeek().copy(generatedAt = preview.generatedAt.plusSeconds(90))

        push(later)

        assertThat(written).hasSize(2)
        val json = DataMap.fromByteArray(written.last().data!!).getString(WearProtocol.KEY_JSON)
        assertThat(WidgetJson.decodeSnapshot(json!!)).isEqualTo(later)
    }

    @Test
    fun goingBackToAnEarlierContentIsWrittenAgain() = runTest {
        push(preview)
        push(otherWeek())
        push(preview)

        assertThat(written).hasSize(3)
    }

    @Test
    fun aFailedWriteIsRetriedByTheNextRefresh() = runTest {
        var attempts = 0
        PhoneWearSync.push(preview) {
            attempts++
            throw IOException("watch not connected")
        }

        push(preview)

        assertThat(attempts).isEqualTo(1)
        assertThat(written).hasSize(1)
    }

    @Test
    fun aWriteThatNeverReturnsIsGivenUpAndTheNextRefreshWritesAgain() = runTest {
        PhoneWearSync.push(preview) { awaitCancellation() }

        push(preview)

        assertThat(written).hasSize(1)
    }

    @Test
    fun cancellingTheCallerCancelsTheWriteAndForgetsIt() = runTest {
        assertFailsWith<CancellationException> { PhoneWearSync.push(preview) { throw CancellationException("scope is gone") } }

        push(preview)

        assertThat(written).hasSize(1)
    }

    @Test
    fun theGenerationTimeIsTheOnlyFieldTheComparisonIgnores() = runTest {
        push(preview.copy(generatedAt = Instant.parse("2026-01-01T00:00:00Z")))
        push(preview.copy(generatedAt = Instant.parse("2026-01-01T00:00:00Z"), timeZoneID = "Europe/Berlin"))

        assertThat(written).hasSize(2)
    }
}
