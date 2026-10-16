package health.pulse.strength.wear.sync

import android.content.Context
import health.pulse.strength.core.widgets.WidgetSnapshot
import health.pulse.strength.wear.data.AcceptResult
import health.pulse.strength.wear.data.WearRuntime
import health.pulse.strength.wear.ongoing.OngoingWorkout
import java.util.concurrent.atomic.AtomicLong
import kotlinx.coroutines.withTimeoutOrNull

/**
 * Everything that happens when the phone's snapshot reaches the watch: decode and store it in [WearRuntime], then bring the Ongoing
 * Activity and every tile and complication up to date. The Data Layer listener and the start-up pull both come through here.
 */
internal object SnapshotIngest {
    /** What a new snapshot sets in motion besides being stored; tests replace it. */
    interface Effects {
        fun snapshotChanged(context: Context, snapshot: WidgetSnapshot)
    }

    private object SystemEffects : Effects {
        override fun snapshotChanged(context: Context, snapshot: WidgetSnapshot) {
            OngoingWorkout.sync(context, snapshot.active)
            TileComplicationUpdater.requestAll(context)
        }
    }

    @Volatile
    var effects: Effects = SystemEffects

    private val lastPull = AtomicLong(NEVER)

    /** Stores [json] if it is a new snapshot of a schema this build reads, and runs the [effects]. */
    fun accept(context: Context, json: String?): AcceptResult {
        val app = context.applicationContext
        WearRuntime.init(app)
        val result = WearRuntime.accept(json)
        if (result == AcceptResult.UPDATED) effects.snapshotChanged(app, WearRuntime.current())
        return result
    }

    /** Reads the snapshot the phone stored in the Data Layer, for a start that missed the change callback (the app was installed later). */
    suspend fun pull(context: Context): AcceptResult = accept(context, WearRuntime.latestJsonFromPhone())

    /**
     * Makes sure the surfaces have data when they are asked for it: while only the placeholder exists, tries the Data Layer once a minute
     * at most, and waits no longer than [PULL_TIMEOUT_MS] so that a missing phone never holds a tile back.
     */
    suspend fun ensureData(context: Context, nowMillis: Long = System.currentTimeMillis()) {
        WearRuntime.init(context)
        if (!WearRuntime.isPlaceholder.value) return
        val previous = lastPull.get()
        if (previous != NEVER && nowMillis - previous < PULL_INTERVAL_MS) return
        if (!lastPull.compareAndSet(previous, nowMillis)) return
        withTimeoutOrNull(PULL_TIMEOUT_MS) { pull(context) }
    }

    /** Test hook. */
    fun resetForTest() {
        effects = SystemEffects
        lastPull.set(NEVER)
    }

    private const val NEVER = Long.MIN_VALUE
    private const val PULL_INTERVAL_MS = 60_000L
    private const val PULL_TIMEOUT_MS = 3_000L
}
