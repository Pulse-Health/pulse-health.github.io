package health.pulse.strength.wear.tiles

import androidx.wear.protolayout.LayoutElementBuilders.LayoutElement
import androidx.wear.protolayout.material.Typography
import health.pulse.strength.core.widgets.WidgetCommands
import health.pulse.strength.wear.data.WearView
import health.pulse.strength.wear.model.NextUpTileModel
import java.time.Instant

/**
 * WA-03 Smart Stack: Next up. The split, the template name, how long it takes, and a Start button. Start opens the watch app, which asks
 * the phone to start the workout and shows it (so the tap has visible feedback).
 */
class NextUpTile : PulseTileService() {
    override fun plan(ui: TileUi, view: WearView, now: Instant): TilePlan = TilePlan(NextUpLayouts.build(ui, NextUpTileModel.of(view)))
}

/** The Next up page, shared with the idle state of the workout tile. */
internal object NextUpLayouts {
    const val ACTION_START = "start"

    fun build(ui: TileUi, model: NextUpTileModel): LayoutElement = when (model) {
        is NextUpTileModel.Ready -> ui.screen(
            label = ui.label(model.split, TileColors.GREEN, Typography.TYPOGRAPHY_CAPTION1, icon = TileIcons.DUMBBELL),
            content = ui.column(
                ui.text(model.name, Typography.TYPOGRAPHY_TITLE3, TileColors.INK, maxLines = 2, bold = true),
                ui.text(model.detail, Typography.TYPOGRAPHY_CAPTION2, TileColors.SECONDARY),
            ),
            chip = ui.chip(
                label = "Start",
                description = "Start ${model.name}",
                clickable = ui.launchClickable(ACTION_START, WidgetCommands.START_NEXT),
            ),
        )
        is NextUpTileModel.Running -> ui.screen(
            label = ui.label("In progress", TileColors.GREEN, Typography.TYPOGRAPHY_CAPTION1, icon = TileIcons.DUMBBELL),
            content = ui.column(
                ui.text(model.name, Typography.TYPOGRAPHY_TITLE3, TileColors.INK, maxLines = 2, bold = true),
                ui.text(model.detail, Typography.TYPOGRAPHY_CAPTION2, TileColors.SECONDARY),
            ),
            chip = open(ui, "Open ${model.name}"),
        )
        NextUpTileModel.NoWorkout -> ui.message("Next up", "No workout yet", "Add one in Pulse on your phone.")
        NextUpTileModel.Waiting -> ui.message("Pulse Strength", "Waiting for your phone", "Open Pulse on your phone to sync.")
    }

    /** The secondary "Open" chip that every state without a Start button ends in. */
    fun open(ui: TileUi, description: String): LayoutElement =
        ui.chip("Open", description, ui.launchClickable(TileUi.ACTION_OPEN), ChipStyle.SECONDARY)
}
