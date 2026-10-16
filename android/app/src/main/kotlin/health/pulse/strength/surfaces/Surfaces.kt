package health.pulse.strength.surfaces

import android.content.Context
import android.util.Log
import health.pulse.strength.controls.Controls
import health.pulse.strength.live.LiveUpdates
import health.pulse.strength.wear.PhoneWearSync
import health.pulse.strength.widgets.extras.ExtrasWidgets
import health.pulse.strength.widgets.home.HomeWidgets
import health.pulse.strength.widgets.lock.LockWidgets
import health.pulse.strength.widgets.tablet.TabletWidgets
import kotlinx.coroutines.CancellationException

/**
 * Tells every surface that the snapshot changed. The runtime calls [refreshAll] after it publishes a new snapshot; each owner
 * implements the `refresh` of its own object (widgets: `GlanceAppWidget.updateAll`, tiles: `TileService.getUpdater`, ...).
 *
 * The surfaces are refreshed one after the other, and one that fails is logged and skipped: the widgets must not stay out of date
 * because a tile failed, and the watch (last in the list) must still get its snapshot.
 */
object Surfaces {
    internal class Step(val name: String, val refresh: suspend (Context) -> Unit)

    internal val steps: List<Step> = listOf(
        Step("Home Screen widgets", HomeWidgets::refresh),
        Step("Lock Screen widgets", LockWidgets::refresh),
        Step("tablet widgets", TabletWidgets::refresh),
        Step("extra widgets", ExtrasWidgets::refresh),
        Step("Quick Settings tiles", Controls::refresh),
        Step("live notifications", LiveUpdates::refresh),
        Step("watch", PhoneWearSync::refresh),
    )

    suspend fun refreshAll(context: Context) = refresh(context, steps)

    internal suspend fun refresh(context: Context, steps: List<Step>) {
        for (step in steps) {
            try {
                step.refresh(context)
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Exception) {
                Log.w(TAG, "The ${step.name} could not be refreshed", error)
            }
        }
    }

    private const val TAG = "Surfaces"
}
