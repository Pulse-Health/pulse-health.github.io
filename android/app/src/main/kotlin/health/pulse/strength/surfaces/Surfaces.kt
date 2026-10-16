package health.pulse.strength.surfaces

import android.content.Context
import health.pulse.strength.controls.Controls
import health.pulse.strength.live.LiveUpdates
import health.pulse.strength.widgets.extras.ExtrasWidgets
import health.pulse.strength.widgets.home.HomeWidgets
import health.pulse.strength.widgets.lock.LockWidgets
import health.pulse.strength.widgets.tablet.TabletWidgets

/**
 * Tells every surface that the snapshot changed. The runtime calls [refreshAll] after it publishes a new snapshot; each owner
 * implements the `refresh` of its own object (widgets: `GlanceAppWidget.updateAll`, tiles: `TileService.getUpdater`, ...).
 */
object Surfaces {
    suspend fun refreshAll(context: Context) {
        HomeWidgets.refresh(context)
        LockWidgets.refresh(context)
        TabletWidgets.refresh(context)
        ExtrasWidgets.refresh(context)
        Controls.refresh(context)
        LiveUpdates.refresh(context)
    }
}
