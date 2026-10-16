package health.pulse.strength.wear

import android.content.Context
import android.util.Log
import com.google.android.gms.wearable.PutDataMapRequest
import com.google.android.gms.wearable.PutDataRequest
import com.google.android.gms.wearable.Wearable
import health.pulse.strength.core.widgets.WearProtocol
import health.pulse.strength.core.widgets.WidgetJson
import health.pulse.strength.core.widgets.WidgetSnapshot
import health.pulse.strength.runtime.StrengthRuntime
import java.time.Instant
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withTimeoutOrNull

/**
 * Phone side of the Wearable Data Layer (widgets/SPEC.md section 3): pushes the snapshot to the watch app at `WearProtocol.SNAPSHOT_PATH`
 * and, through [PhoneWearListenerService], executes the commands the watch sends back at `WearProtocol.COMMAND_PATH`.
 *
 * The Data Layer keeps the last item for a watch that connects (or gets the app installed) later, so nothing is queued here.
 */
object PhoneWearSync {
    private const val TAG = "PhoneWearSync"

    /** The Data Layer answers a write at once (it stores the item locally); a call that is still open after this has hung. */
    private const val WRITE_TIMEOUT_MILLIS = 10_000L

    @Volatile
    private var lock = Mutex()
    private var lastPushed: WidgetSnapshot? = null

    /** Called by `Surfaces.refreshAll` after the snapshot changed. Writes the current snapshot unless the watch already has its content. */
    suspend fun refresh(context: Context) {
        val client = Wearable.getDataClient(context.applicationContext)
        push(StrengthRuntime.snapshots.current()) { request -> client.putDataItem(request).await() }
    }

    /**
     * Writes [snapshot] through [put] as an urgent item (delivered at once, not batched), unless it only differs from the last one written
     * by its `generatedAt` time: a rebuilt but unchanged snapshot would otherwise wake the watch for nothing. A failed or hung write is
     * logged and retried by the next refresh, because the snapshot is only remembered once it went through; a write that does not return
     * within [WRITE_TIMEOUT_MILLIS] is given up, so that a stuck Play services call cannot hold up every later refresh.
     */
    internal suspend fun push(snapshot: WidgetSnapshot, put: suspend (PutDataRequest) -> Unit) {
        val content = snapshot.copy(generatedAt = Instant.EPOCH)
        lock.withLock {
            if (content == lastPushed) return
            try {
                val written = withTimeoutOrNull(WRITE_TIMEOUT_MILLIS) {
                    put(request(snapshot))
                    true
                }
                if (written == true) lastPushed = content else Log.w(TAG, "The Data Layer did not take the snapshot for the watch in time")
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Exception) {
                Log.w(TAG, "Could not write the snapshot for the watch", error)
            }
        }
    }

    /** The Data Layer item for [snapshot]: its JSON under `WearProtocol.KEY_JSON`, flagged urgent. */
    internal fun request(snapshot: WidgetSnapshot): PutDataRequest =
        PutDataMapRequest.create(WearProtocol.SNAPSHOT_PATH).apply {
            dataMap.putString(WearProtocol.KEY_JSON, WidgetJson.encodeSnapshot(snapshot))
        }.asPutDataRequest().setUrgent()

    /** Test hook: forgets what was written and abandons a write that never returned (its lock is not waited for any more). */
    internal fun resetForTest() {
        lock = Mutex()
        lastPushed = null
    }
}
