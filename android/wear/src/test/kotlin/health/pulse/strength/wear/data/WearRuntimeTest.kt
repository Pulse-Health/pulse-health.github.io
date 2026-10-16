package health.pulse.strength.wear.data

import android.app.Application
import androidx.test.core.app.ApplicationProvider
import com.google.common.truth.Truth.assertThat
import health.pulse.strength.core.widgets.WearProtocol
import health.pulse.strength.core.widgets.WidgetCommand
import health.pulse.strength.core.widgets.WidgetJson
import health.pulse.strength.core.widgets.WidgetSnapshot
import health.pulse.strength.wear.WearFixtures
import java.io.File
import java.io.IOException
import kotlin.test.assertFailsWith
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/** The watch's source of truth: the stored snapshot, what is accepted from the phone, and how commands leave. */
@RunWith(RobolectricTestRunner::class)
class WearRuntimeTest {
    private lateinit var app: Application
    private lateinit var file: File
    private val link = FakePhoneLink()

    @Before
    fun setUp() {
        app = ApplicationProvider.getApplicationContext()
        file = File(app.filesDir, SnapshotStore.FILE_NAME).also { it.delete() }
        WearRuntime.installForTest(SnapshotStore(file), link)
    }

    @After
    fun tearDown() {
        file.delete()
        WearRuntime.resetForTest()
    }

    private fun json(snapshot: WidgetSnapshot) = WidgetJson.encodeSnapshot(snapshot)

    private fun otherWeek() = WearFixtures.preview.copy(week = WearFixtures.preview.week.copy(completed = 2))

    // region Snapshot

    @Test
    fun beforeAnythingArrivesTheRuntimeHoldsThePreviewAsAPlaceholder() {
        assertThat(WearRuntime.isPlaceholder.value).isTrue()
        assertThat(WearRuntime.current()).isEqualTo(WearFixtures.preview)
        assertThat(WearRuntime.view().isPlaceholder).isTrue()
    }

    @Test
    fun aSnapshotFromThePhoneIsPublishedStoredAndEndsThePlaceholder() {
        val snapshot = otherWeek()

        val result = WearRuntime.accept(json(snapshot))

        assertThat(result).isEqualTo(AcceptResult.UPDATED)
        assertThat(WearRuntime.current()).isEqualTo(snapshot)
        assertThat(WearRuntime.isPlaceholder.value).isFalse()
        assertThat(WearRuntime.view()).isEqualTo(WearView(snapshot, isPlaceholder = false))
        assertThat(file.readText()).isEqualTo(json(snapshot))
    }

    @Test
    fun theSameSnapshotAgainChangesNothing() {
        WearRuntime.accept(json(otherWeek()))
        file.delete()

        val result = WearRuntime.accept(json(otherWeek()))

        assertThat(result).isEqualTo(AcceptResult.UNCHANGED)
        assertThat(file.exists()).isFalse()
    }

    @Test
    fun thePreviewSentAsRealDataStillEndsThePlaceholder() {
        val result = WearRuntime.accept(json(WearFixtures.preview))

        assertThat(result).isEqualTo(AcceptResult.UPDATED)
        assertThat(WearRuntime.isPlaceholder.value).isFalse()
    }

    @Test
    fun garbageAndSnapshotsOfANewerSchemaAreRejectedAndKeepWhatWasThere() {
        val good = otherWeek()
        WearRuntime.accept(json(good))

        assertThat(WearRuntime.accept("{not json")).isEqualTo(AcceptResult.REJECTED)
        assertThat(WearRuntime.accept(null)).isEqualTo(AcceptResult.REJECTED)
        assertThat(WearRuntime.accept("")).isEqualTo(AcceptResult.REJECTED)
        val newer = json(good.copy(schemaVersion = WidgetSnapshot.CURRENT_SCHEMA_VERSION + 1))
        assertThat(WearRuntime.accept(newer)).isEqualTo(AcceptResult.REJECTED)

        assertThat(WearRuntime.current()).isEqualTo(good)
        assertThat(file.readText()).isEqualTo(json(good))
    }

    @Test
    fun aRejectedSnapshotKeepsThePlaceholderFlag() {
        WearRuntime.accept("{not json")

        assertThat(WearRuntime.isPlaceholder.value).isTrue()
    }

    @Test
    fun aNewProcessStartsFromTheStoredSnapshot() {
        val stored = otherWeek()
        file.writeText(json(stored))
        WearRuntime.resetForTest()

        WearRuntime.init(app)

        assertThat(WearRuntime.current()).isEqualTo(stored)
        assertThat(WearRuntime.isPlaceholder.value).isFalse()
    }

    @Test
    fun aNewProcessWithoutAStoredSnapshotKeepsThePlaceholder() {
        WearRuntime.resetForTest()

        WearRuntime.init(app)

        assertThat(WearRuntime.isPlaceholder.value).isTrue()
    }

    @Test
    fun aGarbledStoredFileIsIgnored() {
        file.writeText("{\"schemaVersion\":1,")
        WearRuntime.resetForTest()

        WearRuntime.init(app)

        assertThat(WearRuntime.isPlaceholder.value).isTrue()
    }

    // endregion

    // region Commands

    @Test
    fun aCommandLeavesAsJsonAtTheCommandPath() = runTest {
        val command = WearCommands.adjustRest(15)

        val delivered = WearRuntime.send(command)

        assertThat(delivered).isTrue()
        val (path, payload) = link.sent.single()
        assertThat(path).isEqualTo(WearProtocol.COMMAND_PATH)
        assertThat(WidgetJson.json.decodeFromString(WidgetCommand.serializer(), String(payload, Charsets.UTF_8))).isEqualTo(command)
    }

    @Test
    fun withoutAReachablePhoneTheCommandIsDroppedAndReported() = runTest {
        link.reachable = false

        assertThat(WearRuntime.send(WearCommands.logNextSet())).isFalse()
        assertThat(link.sent).isEmpty()
    }

    @Test
    fun aFailingDataLayerIsLoggedAndSwallowed() = runTest {
        link.failure = IOException("bluetooth is off")

        assertThat(WearRuntime.send(WearCommands.logNextSet())).isFalse()
    }

    @Test
    fun cancellingTheCallerCancelsTheSend() = runTest {
        link.failure = CancellationException("scope is gone")

        assertFailsWith<CancellationException> { WearRuntime.send(WearCommands.logNextSet()) }
    }

    @Test
    fun beforeInitNoCommandCanLeave() = runTest {
        WearRuntime.resetForTest()

        assertThat(WearRuntime.send(WearCommands.logNextSet())).isFalse()
    }

    @Test
    fun theStoredItemOfTheDataLayerIsPassedThrough() = runTest {
        link.stored = "{\"x\":1}"

        assertThat(WearRuntime.latestJsonFromPhone()).isEqualTo("{\"x\":1}")
    }

    @Test
    fun aFailingDataLayerHasNoStoredItem() = runTest {
        link.failure = IOException("no play services")

        assertThat(WearRuntime.latestJsonFromPhone()).isNull()
    }

    // endregion
}

/** A phone that records what is sent to it. */
internal class FakePhoneLink : PhoneLink {
    val sent = mutableListOf<Pair<String, ByteArray>>()
    var reachable = true
    var failure: Throwable? = null
    var stored: String? = null

    override suspend fun sendMessage(path: String, payload: ByteArray): Boolean {
        failure?.let { throw it }
        if (!reachable) return false
        sent += path to payload
        return true
    }

    override suspend fun latestSnapshotJson(): String? {
        failure?.let { throw it }
        return stored
    }
}
