package health.pulse.strength.widgets.home

import android.content.Context
import android.util.Log
import androidx.glance.GlanceId
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.updateAll
import kotlinx.coroutines.CancellationException

/** Owner: glance-home. Refreshes every Home Screen widget after the snapshot changed (see Surfaces). */
object HomeWidgets {
    /**
     * One instance of every widget of this folder. `updateAll` finds the placed instances through the receivers that name the widget class,
     * so [NextUpWidget] (placed through two providers) appears once.
     */
    internal fun all(): List<GlanceAppWidget> = listOf(
        NextUpWidget(),
        WeeklyGoalWidget(),
        WeeklyGoalThemedWidget(),
        PrSpotlightWidget(),
        MuscleFreshnessWidget(),
        OverloadWidget(),
        WeeklySetsWidget(),
        LiftTrendWidget(),
        TrainingWeekWidget(),
        TemplateLauncherWidget(),
        MonthHeatmapWidget(),
    )

    suspend fun refresh(context: Context) {
        updateAllSafely(context, all())
    }
}

private const val TAG = "HomeWidgets"

/**
 * Updates every placed instance of [widgets]. A widget that fails to update must not keep the others (or the surfaces that follow in
 * `Surfaces.refreshAll`) from updating, so a failure is logged and the loop goes on; cancellation still propagates.
 */
internal suspend fun updateAllSafely(context: Context, widgets: List<GlanceAppWidget>) {
    widgets.forEach { widget -> logFailure(widget) { widget.updateAll(context) } }
}

/**
 * Draws the placed instance [glanceId] of [widget]. A configuration screen calls it right before it closes: a widget that cannot be
 * drawn at this moment is logged and the system draws it with its next update, but the user is not kept on the screen.
 */
internal suspend fun updateSafely(context: Context, widget: GlanceAppWidget, glanceId: GlanceId) {
    logFailure(widget) { widget.update(context, glanceId) }
}

private suspend fun logFailure(widget: GlanceAppWidget, update: suspend () -> Unit) {
    try {
        update()
    } catch (cancelled: CancellationException) {
        throw cancelled
    } catch (failure: Exception) {
        Log.w(TAG, "Could not update ${widget.javaClass.simpleName}", failure)
    }
}
