package health.pulse.strength.runtime

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.util.Log
import androidx.core.content.ContextCompat
import health.pulse.strength.core.SnapshotBuilder
import health.pulse.strength.core.SnapshotPhase
import health.pulse.strength.core.StrengthStore
import health.pulse.strength.core.WorkoutController
import health.pulse.strength.core.WorkoutEngine
import health.pulse.strength.core.timeIntervalSince
import health.pulse.strength.core.widgets.WidgetContext
import health.pulse.strength.core.widgets.WidgetSnapshot
import health.pulse.strength.core.widgets.WidgetSnapshotBuilder
import health.pulse.strength.core.widgets.hasSameContentAs
import health.pulse.strength.surfaces.Surfaces
import java.time.Instant
import java.time.ZoneId
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.conflate
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.merge
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.flow.transformLatest
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * The runtime of the running app (widgets/SPEC.md sections 3 and 5): it keeps one [WidgetSnapshot] in step with the strength data, the
 * workout in progress and the weekly goal, runs the commands of the surfaces, and tells the surfaces when the snapshot changed.
 * Nothing is written to disk; the snapshot lives in memory and is built again when the process starts.
 *
 * The snapshot is built again when
 * * the templates, the history or the exercises change (`store.data`),
 * * the workout changes (`controller.state`); a change that only brings a new heart-rate reading passes at most every
 *   [WorkoutEngine.heartRateInterval] seconds,
 * * the weekly goal changes,
 * * a rest ends, since `phase` turns from `resting` to `restOver` then without any other change,
 * * the date, the time or the time zone is set ([rebuild] is for whoever learns of that outside this process),
 * * a command of a surface was applied, so the snapshot shows its effect when the command returns.
 *
 * A snapshot is published only when it shows something new (everything but its time stamp and the workout's revision). The surfaces are
 * refreshed once the snapshot has not changed for [refreshDelay] and differs from the one they show (at first the snapshot of the start,
 * which they draw from when they are created; later the one they were last refreshed for), so a burst of changes redraws them once.
 *
 * The runtime lives as long as the process. [close] ends it for a test: it stops the coroutines and unregisters the receiver.
 */
class LiveRuntime(
    context: Context,
    private val store: StrengthStore,
    private val controller: WorkoutController,
    private val weeklyGoal: StateFlow<Int>,
    private val clock: () -> Instant = { Instant.now() },
    private val zone: () -> ZoneId = { ZoneId.systemDefault() },
    /** Where snapshots are built and the surfaces refreshed. */
    private val compute: CoroutineDispatcher = Dispatchers.Default,
    /** Where the commands change the workout: the store and the controller belong to the main thread. */
    main: CoroutineDispatcher = Dispatchers.Main.immediate,
    private val refreshDelay: Duration = 1.seconds,
    private val refreshSurfaces: suspend (Context) -> Unit = Surfaces::refreshAll,
) : StrengthRuntime.Runtime {
    private val appContext = context.applicationContext
    private val scope = CoroutineScope(SupervisorJob() + compute)
    private val lock = Any()
    private val published = MutableStateFlow(build())

    /** One tick per notice that the date, the time or the time zone was set (several at once count as one). */
    private val clockTicks = Channel<Unit>(Channel.CONFLATED)

    private val clockReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            clockTicks.trySend(Unit)
        }
    }

    override val snapshots: SnapshotSource = object : SnapshotSource {
        override val snapshot: StateFlow<WidgetSnapshot> = published.asStateFlow()
    }

    override val commands: WorkoutCommands = LiveCommands(store, controller, main, clock) { publish(force = false) }

    init {
        val clockChanges = IntentFilter().apply {
            addAction(Intent.ACTION_DATE_CHANGED)
            addAction(Intent.ACTION_TIME_CHANGED)
            addAction(Intent.ACTION_TIMEZONE_CHANGED)
        }
        ContextCompat.registerReceiver(appContext, clockReceiver, clockChanges, ContextCompat.RECEIVER_NOT_EXPORTED)
        val atStart = published.value
        scope.launch { changes().conflate().collect { rebuildNow(force = false) } }
        scope.launch { clockTicks.receiveAsFlow().collect { rebuildNow(force = true) } }
        scope.launch { refreshAfterPublications(shown = atStart) }
    }

    override suspend fun rebuild() = publish(force = true)

    /**
     * Stops following the app: ends the coroutines and unregisters the receiver right away, on the calling thread, rather than in a
     * clean-up that a coroutine would run later, when the context may be gone. The surfaces keep the last snapshot. Closing twice, or
     * after the context lost the receiver, is fine.
     */
    fun close() {
        scope.cancel()
        try {
            appContext.unregisterReceiver(clockReceiver)
        } catch (_: IllegalArgumentException) {
            // The platform's way of saying that the receiver is not registered (any more).
        }
    }

    private suspend fun publish(force: Boolean) = withContext(compute) { rebuildNow(force) }

    /**
     * Builds the snapshot from the current data, workout, goal, time and zone, and publishes it when it shows something new, or always
     * with [force], which also gives the snapshot a new time stamp. A failure is logged and leaves the last snapshot in place.
     */
    private fun rebuildNow(force: Boolean) {
        try {
            synchronized(lock) {
                val fresh = build()
                if (force || !fresh.hasSameContentAs(published.value)) published.value = fresh
            }
        } catch (error: Exception) {
            Log.w(TAG, "The widget snapshot could not be built", error)
        }
    }

    private fun build(): WidgetSnapshot {
        val now = clock()
        val widgetContext = WidgetContext(
            weeklyGoal = weeklyGoal.value,
            zone = zone(),
            active = controller.state.value?.let { SnapshotBuilder.make(it, now) },
        )
        return WidgetSnapshotBuilder.make(store.data.value, widgetContext, now)
    }

    // region What triggers a new snapshot

    private fun changes(): Flow<Unit> = merge(
        store.data.map { Unit },
        controller.state.heartRateThrottled(WorkoutEngine.heartRateInterval, clock).map { Unit },
        weeklyGoal.map { Unit },
        restEnds(),
    )

    /** Emits when the rest of the published snapshot ends (never while it is paused: the rest is frozen then). */
    @OptIn(ExperimentalCoroutinesApi::class)
    private fun restEnds(): Flow<Unit> = published.transformLatest { snapshot ->
        val active = snapshot.active ?: return@transformLatest
        val endsAt = active.restEndsAt ?: return@transformLatest
        if (active.phase != SnapshotPhase.RESTING || active.restFrozenRemaining != null) return@transformLatest
        delay((endsAt.timeIntervalSince(clock()) * 1_000).toLong().coerceAtLeast(0) + restEndMarginMillis)
        emit(Unit)
    }

    // endregion

    /**
     * Refreshes the surfaces once the snapshot has not changed for [refreshDelay], unless it shows what they show already: [shown] to
     * begin with, then the snapshot they were last refreshed for (a new time stamp alone is no reason). A surface that fails must not
     * stop the following ones, and a refresh that failed is tried again with the next publication.
     */
    @OptIn(FlowPreview::class)
    private suspend fun refreshAfterPublications(shown: WidgetSnapshot) {
        var refreshedFor = shown
        published.debounce(refreshDelay).collect { snapshot ->
            if (refreshedFor.hasSameContentAs(snapshot)) return@collect
            try {
                refreshSurfaces(appContext)
                refreshedFor = snapshot
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Exception) {
                Log.w(TAG, "The surfaces could not be refreshed", error)
            }
        }
    }

    private companion object {
        const val TAG = "LiveRuntime"

        /** Added to the end of a rest, so that the clock has passed it when the snapshot is built again. */
        const val restEndMarginMillis = 50L
    }
}
