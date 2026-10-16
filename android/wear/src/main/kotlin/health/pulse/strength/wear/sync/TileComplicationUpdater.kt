package health.pulse.strength.wear.sync

import android.content.ComponentName
import android.content.Context
import android.util.Log
import androidx.wear.tiles.TileService
import androidx.wear.watchface.complications.datasource.ComplicationDataSourceService
import androidx.wear.watchface.complications.datasource.ComplicationDataSourceUpdateRequester
import health.pulse.strength.wear.complications.DaysSinceComplicationService
import health.pulse.strength.wear.complications.NextUpComplicationService
import health.pulse.strength.wear.complications.RestComplicationService
import health.pulse.strength.wear.complications.StartComplicationService
import health.pulse.strength.wear.complications.StreakComplicationService
import health.pulse.strength.wear.complications.WeeklyGoalComplicationService
import health.pulse.strength.wear.complications.WeeklySetsComplicationService
import health.pulse.strength.wear.tiles.HeartRateTile
import health.pulse.strength.wear.tiles.LiftTrendTile
import health.pulse.strength.wear.tiles.NextUpTile
import health.pulse.strength.wear.tiles.RecordTile
import health.pulse.strength.wear.tiles.WorkoutTile

/**
 * Tells the system that every tile and complication of the app has new data. The system only calls the services that are in use (a tile
 * in the carousel, a complication on a face), so asking for all of them costs nothing for the rest.
 */
internal object TileComplicationUpdater {
    /** Every tile service of the manifest. */
    val tiles: List<Class<out TileService>> = listOf(
        NextUpTile::class.java,
        WorkoutTile::class.java,
        RecordTile::class.java,
        LiftTrendTile::class.java,
        HeartRateTile::class.java,
    )

    /** Every complication data source of the manifest. */
    val complications: List<Class<out ComplicationDataSourceService>> = listOf(
        WeeklyGoalComplicationService::class.java,
        DaysSinceComplicationService::class.java,
        NextUpComplicationService::class.java,
        StartComplicationService::class.java,
        RestComplicationService::class.java,
        StreakComplicationService::class.java,
        WeeklySetsComplicationService::class.java,
    )

    fun requestAll(context: Context) {
        val app = context.applicationContext
        val updater = TileService.getUpdater(app)
        tiles.forEach { tile ->
            try {
                updater.requestUpdate(tile)
            } catch (error: RuntimeException) {
                Log.w(TAG, "Could not ask for a new ${tile.simpleName}", error)
            }
        }
        complications.forEach { source ->
            try {
                ComplicationDataSourceUpdateRequester.create(app, ComponentName(app, source)).requestUpdateAll()
            } catch (error: RuntimeException) {
                Log.w(TAG, "Could not ask for new data of ${source.simpleName}", error)
            }
        }
    }

    private const val TAG = "TileComplicationUpdater"
}
