package health.pulse.strength.widgets.lock

import android.content.Context
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.updateAll

/** Owner: glance-extras. Refreshes every lock screen / glanceable hub widget after the snapshot changed (see Surfaces). */
object LockWidgets {
    private const val TAG = "LockWidgets"

    suspend fun refresh(context: Context) {
        val widgets: List<GlanceAppWidget> = listOf(
            WeeklyGoalCompactWidget(),
            DaysSinceWidget(),
            StreakWidget(),
            QuickStartWidget(),
            NextUpCompactWidget(),
            WeeklySetsCompactWidget(),
            PrCompactWidget(),
            OverloadCompactWidget(),
        )
        for (widget in widgets) refreshQuietly(TAG) { widget.updateAll(context) }
        refreshQuietly(TAG) { InlineStatusWidget.updateAllModes(context) }
    }
}
