package health.pulse.strength.wear.complications

import androidx.wear.watchface.complications.data.ComplicationData
import androidx.wear.watchface.complications.data.ComplicationType
import androidx.wear.watchface.complications.data.NoDataComplicationData
import androidx.wear.watchface.complications.datasource.ComplicationDataTimeline
import androidx.wear.watchface.complications.datasource.ComplicationRequest
import androidx.wear.watchface.complications.datasource.SuspendingComplicationDataSourceService
import androidx.wear.watchface.complications.datasource.SuspendingTimelineComplicationDataSourceService
import health.pulse.strength.core.widgets.WidgetSnapshot
import health.pulse.strength.core.widgets.preview
import health.pulse.strength.wear.data.WearRuntime
import health.pulse.strength.wear.data.WearView
import health.pulse.strength.wear.sync.SnapshotIngest
import java.time.Instant

/*
 * The complication data sources of the watch (WA-01, WA-02, WA-07, WA-10). Each one declares its types in the manifest
 * (`SUPPORTED_TYPES`) and answers them from the snapshot the phone pushed; `TileComplicationUpdater` asks for fresh data whenever a new
 * snapshot arrives, so none of them polls (`UPDATE_PERIOD_SECONDS` is 0).
 */

/** The idealised preview snapshot as the data the watch face editor shows while a complication is being chosen. */
internal object ComplicationPreview {
    val view: WearView get() = WearView(WidgetSnapshot.preview, isPlaceholder = false)
}

/** Base of the complications that answer from a single [WearView]. */
abstract class PulseComplicationService : SuspendingComplicationDataSourceService() {
    internal abstract fun data(factory: ComplicationFactory, type: ComplicationType, view: WearView): ComplicationData

    final override suspend fun onComplicationRequest(request: ComplicationRequest): ComplicationData {
        SnapshotIngest.ensureData(applicationContext)
        return data(ComplicationFactory(this), request.complicationType, WearRuntime.view())
    }

    /** Sample data for the types the service supports; null for any other type. */
    final override fun getPreviewData(type: ComplicationType): ComplicationData? =
        data(ComplicationFactory(this), type, ComplicationPreview.view).takeUnless { it is NoDataComplicationData }
}

/** WA-01 and WA-07: workouts finished this week against the goal, as a gauge (with the next split as its short title) or as "3/4". */
class WeeklyGoalComplicationService : PulseComplicationService() {
    override fun data(factory: ComplicationFactory, type: ComplicationType, view: WearView) = factory.weeklyGoal(type, view)
}

/** WA-01: days since the last workout, "3d". */
class DaysSinceComplicationService : PulseComplicationService() {
    override fun data(factory: ComplicationFactory, type: ComplicationType, view: WearView) = factory.daysSince(type, view)
}

/** WA-01 and WA-10: the next workout by name and size (LONG_TEXT), or the split as a short reminder (SHORT_TEXT). */
class NextUpComplicationService : PulseComplicationService() {
    override fun data(factory: ComplicationFactory, type: ComplicationType, view: WearView) = factory.nextUp(type, view)
}

/** WA-01: a play button that starts the next workout. */
class StartComplicationService : PulseComplicationService() {
    override fun data(factory: ComplicationFactory, type: ComplicationType, view: WearView) = factory.start(type, view)
}

/** WA-10: the week streak, "6wk". */
class StreakComplicationService : PulseComplicationService() {
    override fun data(factory: ComplicationFactory, type: ComplicationType, view: WearView) = factory.streak(type, view)
}

/** WA-10: working sets this week against the target, as a gauge. */
class WeeklySetsComplicationService : PulseComplicationService() {
    override fun data(factory: ComplicationFactory, type: ComplicationType, view: WearView) = factory.weeklySets(type, view)
}

/**
 * WA-02: the rest timer on any watch face. A timeline answers it: the countdown until the rest ends, then "GO", so the face changes at the
 * right second even when the phone sends nothing in between.
 */
class RestComplicationService : SuspendingTimelineComplicationDataSourceService() {
    override suspend fun onComplicationRequest(request: ComplicationRequest): ComplicationDataTimeline? {
        SnapshotIngest.ensureData(applicationContext)
        return ComplicationFactory(this).rest(request.complicationType, WearRuntime.view(), Instant.now())
    }

    override fun getPreviewData(type: ComplicationType): ComplicationData? = ComplicationFactory(this).restPreview(type)
}
