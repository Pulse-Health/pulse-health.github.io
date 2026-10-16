package health.pulse.strength.wear.tiles

import androidx.wear.protolayout.ColorBuilders.argb
import androidx.wear.protolayout.DimensionBuilders.dp
import androidx.wear.protolayout.DimensionBuilders.wrap
import androidx.wear.protolayout.LayoutElementBuilders
import androidx.wear.protolayout.LayoutElementBuilders.LayoutElement
import androidx.wear.protolayout.ModifiersBuilders
import androidx.wear.protolayout.material.Typography
import health.pulse.strength.wear.data.WearView
import health.pulse.strength.wear.model.HeartRateTileModel
import java.time.Instant
import kotlin.math.roundToInt

/**
 * WA-09 Set-by-set heart rate: the last session as bars (`SessionSummary.heartRateBars`). Effort buckets are tall and solid, rests
 * short and faded, so the rhythm reads from the shapes and the opacity, with the average and peak written underneath. Tapping opens the app.
 */
class HeartRateTile : PulseTileService() {
    override fun plan(ui: TileUi, view: WearView, now: Instant): TilePlan = TilePlan(layout(ui, HeartRateTileModel.of(view)))

    internal fun layout(ui: TileUi, model: HeartRateTileModel): LayoutElement = when (model) {
        is HeartRateTileModel.Bars -> ui.root(
            element = ui.screen(
                label = ui.label("Heart rate", TileColors.HEART, Typography.TYPOGRAPHY_CAPTION1, icon = TileIcons.HEART),
                content = ui.column(
                    bars(ui, model),
                    ui.spacer(height = 6f),
                    ui.text(model.summary, Typography.TYPOGRAPHY_CAPTION2, TileColors.INK, bold = true),
                ),
                secondary = ui.text(model.workout, Typography.TYPOGRAPHY_CAPTION3, TileColors.SECONDARY),
            ),
            description = model.description,
            clickable = ui.launchClickable(TileUi.ACTION_OPEN),
        )
        is HeartRateTileModel.NoData -> ui.message(
            label = "Heart rate",
            title = "No heart rate yet",
            hint = model.workout?.let { "None was recorded in $it." } ?: "Finish a workout to see it here.",
            icon = TileIcons.HEART,
            accent = TileColors.HEART,
        )
        HeartRateTileModel.Waiting -> ui.message(
            label = "Heart rate",
            title = "Waiting for your phone",
            hint = "Open Pulse on your phone to sync.",
            icon = TileIcons.HEART,
            accent = TileColors.HEART,
        )
    }

    /** One column per bucket, bottom-aligned; the width follows the number of buckets so 8 and 16 both fill the same span. */
    private fun bars(ui: TileUi, model: HeartRateTileModel.Bars): LayoutElement {
        val count = model.bars.size
        val barWidth = ((SPAN - GAP * (count - 1)) / count).coerceIn(MIN_BAR_WIDTH, MAX_BAR_WIDTH)
        val row = LayoutElementBuilders.Row.Builder()
            .setWidth(wrap())
            .setHeight(dp(MAX_BAR_HEIGHT))
            .setVerticalAlignment(LayoutElementBuilders.VERTICAL_ALIGN_BOTTOM)
        model.bars.forEachIndexed { index, bar ->
            if (index > 0) row.addContent(ui.spacer(width = GAP))
            row.addContent(
                LayoutElementBuilders.Box.Builder()
                    .setWidth(dp(barWidth))
                    .setHeight(dp((MAX_BAR_HEIGHT * bar.height).roundToInt().toFloat()))
                    .setModifiers(
                        ModifiersBuilders.Modifiers.Builder()
                            .setBackground(
                                ModifiersBuilders.Background.Builder()
                                    .setColor(argb(if (bar.isEffort) TileColors.HEART else REST_COLOR))
                                    .setCorner(ModifiersBuilders.Corner.Builder().setRadius(dp(CORNER)).build())
                                    .build(),
                            )
                            .build(),
                    )
                    .build(),
            )
        }
        return row.build()
    }

    private companion object {
        const val SPAN = 124f
        const val GAP = 3f
        const val MIN_BAR_WIDTH = 4f
        const val MAX_BAR_WIDTH = 14f
        const val MAX_BAR_HEIGHT = 54f
        const val CORNER = 2f

        /** The heart red at half opacity: the rest buckets of the canvas. */
        const val REST_COLOR = 0x80FF453A.toInt()
    }
}
