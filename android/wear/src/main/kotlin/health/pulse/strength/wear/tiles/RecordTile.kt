package health.pulse.strength.wear.tiles

import androidx.wear.protolayout.LayoutElementBuilders.LayoutElement
import androidx.wear.protolayout.material.Typography
import health.pulse.strength.wear.data.WearView
import health.pulse.strength.wear.model.RecordTileModel
import java.time.Instant

/**
 * WA-06 Record card: the newest personal record. For the 24 hours after the lift (`PRSummary.isFresh`) it is the gold "NEW RECORD" card
 * of the canvas; afterwards it stays as the quieter "LATEST RECORD" (a tile cannot hide itself, unlike the iOS widget that retires).
 * Tapping it opens the app.
 */
class RecordTile : PulseTileService() {
    override fun plan(ui: TileUi, view: WearView, now: Instant): TilePlan = TilePlan(layout(ui, RecordTileModel.of(view)))

    internal fun layout(ui: TileUi, model: RecordTileModel): LayoutElement = when (model) {
        is RecordTileModel.Record -> ui.root(
            element = ui.screen(
                label = ui.label(model.badge, TileColors.GOLD, Typography.TYPOGRAPHY_CAPTION1, icon = TileIcons.TROPHY),
                content = ui.column(
                    ui.text(model.exercise, Typography.TYPOGRAPHY_BODY1, TileColors.INK, bold = true),
                    ui.text(model.lift, Typography.TYPOGRAPHY_TITLE1, TileColors.INK, bold = true),
                    ui.text(listOfNotNull(model.estimate, model.improvement).joinToString(" · "), Typography.TYPOGRAPHY_CAPTION2, TileColors.GOLD),
                ),
            ),
            description = model.description,
            clickable = ui.launchClickable(TileUi.ACTION_OPEN),
            background = if (model.isFresh) GOLD_FILL else null,
        )
        RecordTileModel.NoRecords -> ui.message(
            label = "Latest record",
            title = "No records yet",
            hint = "Your first personal record shows up here.",
            icon = TileIcons.TROPHY,
            accent = TileColors.GOLD,
        )
        RecordTileModel.Waiting -> ui.message(
            label = "Latest record",
            title = "Waiting for your phone",
            hint = "Open Pulse on your phone to sync.",
            icon = TileIcons.TROPHY,
            accent = TileColors.GOLD,
        )
    }

    private companion object {
        /** The dark gold of the fresh record card (canvas board "Apple Watch", item 6). */
        const val GOLD_FILL = 0xFF3A2E00.toInt()
    }
}
