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
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.flow.conflate
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.merge
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
 * A snapshot is published only when it shows something new (everything but its time stamp and the workout's revision), and every
 * publication refreshes the surfaces after [refreshDelay] without another one, so a burst of changes redraws them once.
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

    override val snapshots: SnapshotSource = object : SnapshotSource {
        override val snapshot: StateFlow<WidgetSnapshot> = published.asStateFlow()
    }

    override val commands: WorkoutCommands = LiveCommands(store, controller, main, clock) { publish(force = false) }

    init {
        scope.launch { changes().conflate().collect { rebuildNow(force = false) } }
        scope.launch { clockChanges().collect { rebuildNow(force = true) } }
        scope.launch { refreshAfterPublications() }
    }

    override suspend fun rebuild() = publish(force = true)

    /** Stops following the app; the surfaces keep the last snapshot. */
    fun close() {
        scope.cancel()
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
        val context = WidgetContext(
            weeklyGoal = weeklyGoal.value,
            zone = zone(),
            active = controller.state.value?.let { SnapshotBuilder.make(it, now) },
        )
        return WidgetSnapshotBuilder.make(store.data.value, context, now)
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

    /** Emits when the system says that the date, the time or the time zone was set. */
    private fun clockChanges(): Flow<Unit> = callbackFlow<Unit> {
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                trySend(Unit)
            }
        }
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_DATE_CHANGED)
            addAction(Intent.ACTION_TIME_CHANGED)
            addAction(Intent.ACTION_TIMEZONE_CHANGED)
        }
        ContextCompat.registerReceiver(appContext, receiver, filter, ContextCompat.RECEIVER_NOT_EXPORTED)
        awaitClose { appContext.unregisterReceiver(receiver) }
    }.conflate()

    // endregion

    /** Refreshes the surfaces once the snapshot has not changed for [refreshDelay]. A surface that fails must not stop the following ones. */
    @OptIn(FlowPreview::class)
    private suspend fun refreshAfterPublications() {
        published.debounce(refreshDelay).collect {
            try {
                refreshSurfaces(appContext)
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
