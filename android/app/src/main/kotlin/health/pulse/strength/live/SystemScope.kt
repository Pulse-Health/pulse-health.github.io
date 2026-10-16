package health.pulse.strength.live

import android.content.BroadcastReceiver
import android.util.Log
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull

/** Where the receivers, tiles and shortcut activities run commands: work that must not die with the component that started it. */
internal object SystemScope {
    val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    /** The system gives a broadcast about ten seconds; stay below that so `finish()` always runs. */
    private const val BROADCAST_BUDGET_MS = 8_000L
    private const val TAG = "PulseSystem"

    /** Runs [block] after `goAsync()`, so a receiver can call suspending code. Failures are logged, never thrown into the system. */
    fun runAsync(receiver: BroadcastReceiver, block: suspend () -> Unit) {
        val pending = receiver.goAsync()
        scope.launch {
            try {
                if (withTimeoutOrNull(BROADCAST_BUDGET_MS) { block() } == null) Log.w(TAG, "Broadcast work timed out")
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                Log.w(TAG, "Broadcast work failed", e)
            } finally {
                pending.finish()
            }
        }
    }

    /** Runs [block] on the app scope with failures logged; for tiles and activities, which have no `goAsync()`. */
    fun launch(block: suspend () -> Unit) {
        scope.launch {
            try {
                block()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                Log.w(TAG, "Command failed", e)
            }
        }
    }
}
