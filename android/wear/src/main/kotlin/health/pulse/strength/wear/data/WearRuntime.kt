package health.pulse.strength.wear.data

import android.content.Context
import android.util.Log
import health.pulse.strength.core.widgets.WearProtocol
import health.pulse.strength.core.widgets.WidgetCommand
import health.pulse.strength.core.widgets.WidgetJson
import health.pulse.strength.core.widgets.WidgetSnapshot
import health.pulse.strength.core.widgets.preview
import java.io.File
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/** A snapshot together with whether it is real data: what a surface needs to choose between content and the "waiting" state. */
data class WearView(val snapshot: WidgetSnapshot, val isPlaceholder: Boolean)

/** How [WearRuntime.accept] treated a snapshot that arrived from the phone. */
enum class AcceptResult {
    /** Not a snapshot this build understands (garbled, or written by a newer schema); nothing changed. */
    REJECTED,

    /** The same content as the snapshot already shown. */
    UNCHANGED,

    /** Stored and published. */
    UPDATED,
}

/**
 * The watch's single source of truth: the last snapshot the phone pushed (the preview until one arrives, flagged by [isPlaceholder])
 * and the way to send a command to the phone. Tiles, complications and the app read it; `SnapshotIngest` feeds it.
 */
object WearRuntime {
    private const val TAG = "WearRuntime"

    private val lock = Any()
    private val snapshotFlow = MutableStateFlow(WidgetSnapshot.preview)
    private val placeholderFlow = MutableStateFlow(true)
    private var store: SnapshotStore? = null
    private var link: PhoneLink? = null
    private var initialised = false

    /** The snapshot to show. While [isPlaceholder] it is the idealised preview, sample data that must not be presented as the user's own. */
    val snapshot: StateFlow<WidgetSnapshot> = snapshotFlow.asStateFlow()

    /** True until a snapshot from the phone has arrived (or was stored by an earlier run). */
    val isPlaceholder: StateFlow<Boolean> = placeholderFlow.asStateFlow()

    fun current(): WidgetSnapshot = snapshotFlow.value

    /** Snapshot and placeholder flag read together, so a surface never pairs real data with the wrong flag. */
    fun view(): WearView = synchronized(lock) { WearView(snapshotFlow.value, placeholderFlow.value) }

    /** Loads the stored snapshot (if any) and prepares the Data Layer link. Safe to call again; the first call wins. */
    fun init(context: Context) {
        val app = context.applicationContext
        synchronized(lock) {
            if (initialised) return
            initialised = true
            val file = SnapshotStore(File(app.filesDir, SnapshotStore.FILE_NAME))
            store = file
            link = GmsPhoneLink(app)
            WidgetJson.decodeSnapshotOrNull(file.read())?.let { publishLocked(it) }
        }
    }

    /**
     * Sends [command] to the phone (fire and forget). Returns whether a phone was reachable and the message was handed to the Data
     * Layer; failures are logged and swallowed, so a missing phone never crashes a tile or a button.
     */
    suspend fun send(command: WidgetCommand): Boolean {
        val phone = synchronized(lock) { link } ?: return false
        return try {
            val delivered = phone.sendMessage(WearProtocol.COMMAND_PATH, WearCommandCodec.encode(command))
            if (!delivered) Log.w(TAG, "No phone is reachable; dropped ${command.name}")
            delivered
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (error: Exception) {
            Log.w(TAG, "Could not send ${command.name} to the phone", error)
            false
        }
    }

    /** The JSON the phone last stored in the Data Layer, for a start that missed the change callback. Null when unavailable. */
    internal suspend fun latestJsonFromPhone(): String? {
        val phone = synchronized(lock) { link } ?: return null
        return try {
            phone.latestSnapshotJson()
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (error: Exception) {
            Log.w(TAG, "Could not read the stored snapshot from the Data Layer", error)
            null
        }
    }

    /** Decodes [json] from the phone and, when it is a new snapshot, stores and publishes it. */
    internal fun accept(json: String?): AcceptResult {
        val text = json ?: return AcceptResult.REJECTED
        val decoded = WidgetJson.decodeSnapshotOrNull(text) ?: return AcceptResult.REJECTED
        synchronized(lock) {
            if (!placeholderFlow.value && snapshotFlow.value == decoded) return AcceptResult.UNCHANGED
            store?.write(text)
            publishLocked(decoded)
        }
        return AcceptResult.UPDATED
    }

    private fun publishLocked(snapshot: WidgetSnapshot) {
        snapshotFlow.value = snapshot
        placeholderFlow.value = false
    }

    /** Test hook: forgets everything and installs the given store and link (null means in-memory only), as if [init] had run. */
    internal fun installForTest(store: SnapshotStore?, link: PhoneLink?) {
        synchronized(lock) {
            this.store = store
            this.link = link
            initialised = true
            snapshotFlow.value = WidgetSnapshot.preview
            placeholderFlow.value = true
        }
    }

    /** Test hook: back to the state of a process that has not run [init] yet. */
    internal fun resetForTest() {
        synchronized(lock) {
            store = null
            link = null
            initialised = false
            snapshotFlow.value = WidgetSnapshot.preview
            placeholderFlow.value = true
        }
    }
}
