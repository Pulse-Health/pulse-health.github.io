package health.pulse.strength.widgets.home

import android.content.Context
import androidx.glance.appwidget.updateAll

/** Owner: glance-home. Refreshes every Home Screen widget after the snapshot changed (see Surfaces). */
object HomeWidgets {
    suspend fun refresh(context: Context) {
        WeeklyGoalWidget().updateAll(context)
    }
}
