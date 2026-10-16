package health.pulse.strength.widgets.extras

import android.content.Context
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.updateAll
import health.pulse.strength.widgets.lock.refreshQuietly

/** Owner: glance-extras. Refreshes every "wilder idea" widget after the snapshot changed (see Surfaces). */
object ExtrasWidgets {
    private const val TAG = "ExtrasWidgets"

    suspend fun refresh(context: Context) {
        val widgets: List<GlanceAppWidget> = listOf(
            BodyMapWidget(),
            LogSetWidget(),
            PartnerWidget(),
            FormCueWidget(),
            LoadedBarWidget(),
            RestDayWidget(),
            StrengthRatioWidget(),
            YearInIronWidget(),
            ReadinessWidget(),
            PlateauWidget(),
            SessionTimelineWidget(),
        )
        for (widget in widgets) refreshQuietly(TAG) { widget.updateAll(context) }
    }
}
