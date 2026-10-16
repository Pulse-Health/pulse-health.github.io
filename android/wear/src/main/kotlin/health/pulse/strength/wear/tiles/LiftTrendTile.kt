package health.pulse.strength.wear.tiles

import android.content.Context
import androidx.wear.protolayout.DeviceParametersBuilders.DeviceParameters
import androidx.wear.protolayout.DimensionBuilders.dp
import androidx.wear.protolayout.LayoutElementBuilders
import androidx.wear.protolayout.LayoutElementBuilders.LayoutElement
import androidx.wear.protolayout.ResourceBuilders
import androidx.wear.protolayout.material.Typography
import health.pulse.strength.wear.data.WearView
import health.pulse.strength.wear.model.LiftTrendTileModel
import java.time.Instant
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * WA-08 Lift trend: the estimated 1RM of one lift over its last sessions, the personal record in gold.
 *
 * The line is a PNG made from the lift's points ([Sparkline]) and shipped as an inline image resource: a tile has no polyline element,
 * and bars would not show the shape of the trend. The snapshot lists up to eight lifts, most trained first; a tap moves to the next one
 * and the tile remembers the choice.
 */
class LiftTrendTile : PulseTileService() {
    override fun plan(ui: TileUi, view: WearView, now: Instant): TilePlan {
        val model = LiftTrendTileModel.of(view, selectedLift(ui.context))
        val version = if (model is LiftTrendTileModel.Lift) sparklineVersion(model, ui.device) else TileIcons.VERSION
        return TilePlan(layout(ui, model), resourcesVersion = version)
    }

    override fun resources(version: String, device: DeviceParameters, view: WearView): ResourceBuilders.Resources {
        val builder = TileIcons.resources(version)
        val model = LiftTrendTileModel.of(view, selectedLift(applicationContext))
        if (model is LiftTrendTileModel.Lift) builder.addIdToImageMapping(SPARKLINE, sparklineImage(model, device))
        return builder.build()
    }

    override suspend fun onClick(action: String) {
        if (action == ACTION_NEXT_LIFT) {
            prefs(applicationContext).edit().putInt(KEY_LIFT, selectedLift(applicationContext) + 1).apply()
        }
    }

    internal fun layout(ui: TileUi, model: LiftTrendTileModel): LayoutElement = when (model) {
        is LiftTrendTileModel.Lift -> ui.root(
            element = ui.screen(
                label = ui.label(model.name, TileColors.GREEN, Typography.TYPOGRAPHY_CAPTION1),
                content = ui.column(
                    ui.row(
                        4f,
                        ui.text(model.current, Typography.TYPOGRAPHY_TITLE1, TileColors.INK, bold = true),
                        ui.text("kg e1RM", Typography.TYPOGRAPHY_CAPTION2, TileColors.SECONDARY),
                    ),
                    ui.spacer(height = 4f),
                    LayoutElementBuilders.Image.Builder()
                        .setResourceId(SPARKLINE)
                        .setWidth(dp(sparklineSize(ui.device).first))
                        .setHeight(dp(sparklineSize(ui.device).second))
                        .build(),
                ),
                secondary = ui.text(model.summary, Typography.TYPOGRAPHY_CAPTION2, TileColors.SECONDARY),
            ),
            description = if (model.count > 1) "${model.description}. Tap for the next lift." else model.description,
            clickable = if (model.count > 1) ui.loadClickable(ACTION_NEXT_LIFT) else ui.launchClickable(TileUi.ACTION_OPEN),
        )
        LiftTrendTileModel.NoLifts -> ui.message(
            label = "Lift trend",
            title = "No trend yet",
            hint = "Log a few sessions of a lift to see it here.",
            icon = TileIcons.DUMBBELL,
        )
        LiftTrendTileModel.Waiting -> ui.message(
            label = "Lift trend",
            title = "Waiting for your phone",
            hint = "Open Pulse on your phone to sync.",
            icon = TileIcons.DUMBBELL,
        )
    }

    private fun sparklineImage(model: LiftTrendTileModel.Lift, device: DeviceParameters): ResourceBuilders.ImageResource {
        val (widthDp, heightDp) = sparklineSize(device)
        val density = device.screenDensity
        val widthPx = (widthDp * density).roundToInt()
        val heightPx = (heightDp * density).roundToInt()
        return ResourceBuilders.ImageResource.Builder()
            .setInlineResource(
                ResourceBuilders.InlineImageResource.Builder()
                    .setData(Sparkline.png(model.values, model.recordIndex, widthPx, heightPx, density))
                    .setWidthPx(widthPx)
                    .setHeightPx(heightPx)
                    .setFormat(ResourceBuilders.IMAGE_FORMAT_UNDEFINED)
                    .build(),
            )
            .build()
    }

    /** Changes with everything the picture depends on, so the system fetches the image again exactly when it differs. */
    private fun sparklineVersion(model: LiftTrendTileModel.Lift, device: DeviceParameters): String =
        "lift-${(model.values to model.recordIndex).hashCode()}-${sparklineSize(device)}-${device.screenDensity}"

    private fun sparklineSize(device: DeviceParameters): Pair<Float, Float> =
        min(device.screenWidthDp * WIDTH_SHARE, MAX_WIDTH) to HEIGHT

    private companion object {
        const val SPARKLINE = "sparkline"
        const val ACTION_NEXT_LIFT = "nextLift"
        const val PREFS = "lift_trend_tile"
        const val KEY_LIFT = "lift"
        const val WIDTH_SHARE = 0.62f
        const val MAX_WIDTH = 140f
        const val HEIGHT = 40f

        fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

        fun selectedLift(context: Context): Int = prefs(context).getInt(KEY_LIFT, 0)
    }
}
