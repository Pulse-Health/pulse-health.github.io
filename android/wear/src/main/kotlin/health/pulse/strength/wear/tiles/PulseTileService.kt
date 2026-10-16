package health.pulse.strength.wear.tiles

import androidx.wear.protolayout.DeviceParametersBuilders.DeviceParameters
import androidx.wear.protolayout.LayoutElementBuilders
import androidx.wear.protolayout.LayoutElementBuilders.LayoutElement
import androidx.wear.protolayout.ResourceBuilders
import androidx.wear.protolayout.TimelineBuilders
import androidx.wear.tiles.RequestBuilders
import androidx.wear.tiles.TileBuilders
import androidx.wear.tiles.TileService
import com.google.common.util.concurrent.ListenableFuture
import health.pulse.strength.wear.data.WearRuntime
import health.pulse.strength.wear.data.WearView
import health.pulse.strength.wear.sync.SnapshotIngest
import java.time.Instant
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.guava.future

/** What a tile shows from now on: its [timeline], how long the system may keep it and which version of the image resources it uses. */
internal class TilePlan(
    val timeline: TimelineBuilders.Timeline,
    val freshnessMillis: Long = THIRTY_MINUTES,
    val resourcesVersion: String = TileIcons.VERSION,
) {
    /** A tile that looks the same until it is refreshed. */
    constructor(
        root: LayoutElement,
        freshnessMillis: Long = THIRTY_MINUTES,
        resourcesVersion: String = TileIcons.VERSION,
    ) : this(TimelineBuilders.Timeline.fromLayoutElement(root), freshnessMillis, resourcesVersion)

    companion object {
        val THIRTY_MINUTES: Long = TimeUnit.MINUTES.toMillis(30)

        /** How often a tile with a live countdown asks for a fresh layout. */
        val ONE_MINUTE: Long = TimeUnit.MINUTES.toMillis(1)

        /** The layout shown from [start] on (or always); with [end] it is shown only until then. */
        fun entry(root: LayoutElement, start: Instant? = null, end: Instant? = null): TimelineBuilders.TimelineEntry {
            val entry = TimelineBuilders.TimelineEntry.Builder().setLayout(LayoutElementBuilders.Layout.fromLayoutElement(root))
            if (start != null || end != null) {
                val validity = TimelineBuilders.TimeInterval.Builder()
                start?.let { validity.setStartMillis(it.toEpochMilli()) }
                end?.let { validity.setEndMillis(it.toEpochMilli()) }
                entry.setValidity(validity.build())
            }
            return entry.build()
        }
    }
}

/**
 * Base of the Pulse tiles. A request first runs the command of the clickable that caused it (if any), then builds the layout from the
 * current [WearView]. The subclasses only describe the layout ([plan]) and the commands of their clickables ([onClick]).
 */
abstract class PulseTileService : TileService() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    /** The layout for [view]. Called on a background thread for every request. */
    internal abstract fun plan(ui: TileUi, view: WearView, now: Instant): TilePlan

    /** The image resources of [version]; the icons by default. */
    internal open fun resources(version: String, device: DeviceParameters, view: WearView): ResourceBuilders.Resources =
        TileIcons.resources(version).build()

    /** Runs the command behind the clickable [action] (the id without its generation). */
    internal open suspend fun onClick(action: String) = Unit

    /** Answers one tile request: runs the command of [lastClickableId] (empty when no click caused the request), then builds the tile. */
    internal suspend fun respond(device: DeviceParameters, lastClickableId: String): TileBuilders.Tile {
        if (TileClicks.firstTime(lastClickableId)) onClick(TileClicks.actionOf(lastClickableId))
        SnapshotIngest.ensureData(applicationContext)
        val plan = plan(TileUi(applicationContext, device), WearRuntime.view(), Instant.now())
        return TileBuilders.Tile.Builder()
            .setResourcesVersion(plan.resourcesVersion)
            .setTileTimeline(plan.timeline)
            .setFreshnessIntervalMillis(plan.freshnessMillis)
            .build()
    }

    final override fun onTileRequest(requestParams: RequestBuilders.TileRequest): ListenableFuture<TileBuilders.Tile> = scope.future {
        respond(requestParams.deviceConfiguration, requestParams.currentState.lastClickableId)
    }

    final override fun onTileResourcesRequest(requestParams: RequestBuilders.ResourcesRequest): ListenableFuture<ResourceBuilders.Resources> =
        scope.future { resources(requestParams.version, requestParams.deviceConfiguration, WearRuntime.view()) }

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }
}
