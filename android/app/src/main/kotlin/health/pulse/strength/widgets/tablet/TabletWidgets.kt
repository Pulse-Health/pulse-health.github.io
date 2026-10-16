package health.pulse.strength.widgets.tablet

import android.content.Context
import androidx.glance.appwidget.GlanceAppWidget
import health.pulse.strength.widgets.home.updateAllSafely

/** Owner: glance-home. Refreshes the tablet widgets after the snapshot changed (see Surfaces). */
object TabletWidgets {
    /** One instance of every widget of this folder. */
    internal fun all(): List<GlanceAppWidget> = listOf(TrainingBlockWidget())

    suspend fun refresh(context: Context) {
        updateAllSafely(context, all())
    }
}
