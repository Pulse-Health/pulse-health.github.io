package health.pulse.strength.wear.tiles

import androidx.wear.protolayout.ColorBuilders.argb
import androidx.wear.protolayout.DeviceParametersBuilders.DeviceParameters
import androidx.wear.protolayout.DimensionBuilders.dp
import androidx.wear.protolayout.LayoutElementBuilders
import androidx.wear.protolayout.LayoutElementBuilders.LayoutElement
import androidx.wear.protolayout.TimelineBuilders
import androidx.wear.protolayout.material.CircularProgressIndicator
import androidx.wear.protolayout.material.ProgressIndicatorColors
import androidx.wear.protolayout.material.Text
import androidx.wear.protolayout.material.Typography
import health.pulse.strength.core.widgets.WidgetCommand
import health.pulse.strength.wear.data.WearCommands
import health.pulse.strength.wear.data.WearRuntime
import health.pulse.strength.wear.data.WearView
import health.pulse.strength.wear.model.NextUpTileModel
import health.pulse.strength.wear.model.WearText
import health.pulse.strength.wear.model.WorkoutTileModel
import java.time.Instant

/**
 * WA-04 Log set and WA-05 Rest: one tile that follows the running workout.
 *
 * * Logging: the exercise, the set label, the weight and reps, and a large "Log set" chip. The chip is the first clickable of the
 *   layout, which is the element Wear OS 5 triggers with the double-tap gesture, so a lifter can log a set without letting go of the bar.
 * * Resting: a draining ring around the countdown, the next set, and Skip / +15 s. Skip comes first, so a double tap skips the rest, the
 *   same meaning `primaryAction` has everywhere else. The countdown is drawn by the renderer (dynamic types); the timeline switches to
 *   the "rest over" layout at the exact end time, even if the phone says nothing.
 * * Paused, finished, and no workout: Resume, "open the app", and the Next up page.
 */
class WorkoutTile : PulseTileService() {
    override fun plan(ui: TileUi, view: WearView, now: Instant): TilePlan = when (val model = WorkoutTileModel.of(view, now)) {
        is WorkoutTileModel.Resting -> TilePlan(
            timeline = TimelineBuilders.Timeline.Builder()
                .addTimelineEntry(TilePlan.entry(resting(ui, model), end = model.endsAt))
                .addTimelineEntry(TilePlan.entry(logging(ui, model.afterRest)))
                .build(),
            freshnessMillis = TilePlan.ONE_MINUTE,
        )
        else -> TilePlan(layout(ui, model))
    }

    override suspend fun onClick(action: String) {
        commandFor(action)?.let { WearRuntime.send(it) }
    }

    internal fun layout(ui: TileUi, model: WorkoutTileModel): LayoutElement = when (model) {
        is WorkoutTileModel.Logging -> logging(ui, model)
        is WorkoutTileModel.Resting -> resting(ui, model)
        is WorkoutTileModel.Paused -> ui.screen(
            label = ui.text("Paused", Typography.TYPOGRAPHY_CAPTION1, TileColors.GOLD, bold = true),
            content = ui.column(
                ui.text(model.workoutName, Typography.TYPOGRAPHY_TITLE3, TileColors.INK, maxLines = 2, bold = true),
                ui.text("${WearText.clock(model.elapsedSeconds)} elapsed", Typography.TYPOGRAPHY_CAPTION2, TileColors.SECONDARY),
            ),
            chip = ui.chip("Resume", "Resume ${model.workoutName}", ui.loadClickable(ACTION_RESUME)),
        )
        is WorkoutTileModel.Complete -> ui.screen(
            label = ui.label("All sets logged", TileColors.GREEN, Typography.TYPOGRAPHY_CAPTION1),
            content = ui.column(
                ui.text(model.workoutName, Typography.TYPOGRAPHY_TITLE3, TileColors.INK, maxLines = 2, bold = true),
                ui.text(model.sets, Typography.TYPOGRAPHY_CAPTION2, TileColors.SECONDARY),
            ),
            chip = NextUpLayouts.open(ui, "Open ${model.workoutName} to finish"),
        )
        is WorkoutTileModel.Idle -> NextUpLayouts.build(ui, model.next)
        WorkoutTileModel.Waiting -> NextUpLayouts.build(ui, NextUpTileModel.Waiting)
    }

    private fun logging(ui: TileUi, model: WorkoutTileModel.Logging): LayoutElement {
        val lines = buildList {
            add(ui.text(model.exercise, Typography.TYPOGRAPHY_BODY1, TileColors.INK, bold = true))
            add(ui.text(model.work, Typography.TYPOGRAPHY_TITLE1, TileColors.INK, bold = true))
            if (model.restOver) add(ui.text(model.setLabel, Typography.TYPOGRAPHY_CAPTION2, TileColors.SECONDARY))
        }
        val label = if (model.restOver) {
            ui.text("Rest over", Typography.TYPOGRAPHY_CAPTION1, TileColors.GREEN, bold = true)
        } else {
            ui.text(model.setLabel, Typography.TYPOGRAPHY_CAPTION1, TileColors.SECONDARY)
        }
        return ui.screen(
            label = label,
            content = ui.column(*lines.toTypedArray()),
            chip = ui.chip(
                label = "Log set",
                description = model.description,
                clickable = ui.loadClickable(ACTION_LOG),
                icon = TileIcons.HAND,
            ),
        )
    }

    private fun resting(ui: TileUi, model: WorkoutTileModel.Resting): LayoutElement = ui.screen(
        label = ui.text(model.next, Typography.TYPOGRAPHY_CAPTION1, TileColors.SECONDARY),
        content = ring(ui, model),
        chip = ui.row(
            BUTTON_GAP,
            ui.roundButton("Skip", "Skip rest", ui.loadClickable(ACTION_SKIP_REST), ChipStyle.PRIMARY),
            ui.roundButton("+15 s", "Add 15 seconds to the rest", ui.loadClickable(ACTION_ADD_REST), ChipStyle.SECONDARY),
        ),
    )

    /** The draining ring with the live countdown in its middle. */
    private fun ring(ui: TileUi, model: WorkoutTileModel.Resting): LayoutElement {
        val size = ringSize(ui.device)
        val indicator = CircularProgressIndicator.Builder()
            .setProgress(RestCountdown.remainingFraction(model.endsAt, model.totalSeconds, 1f - model.elapsedFraction))
            .setStartAngle(0f)
            .setEndAngle(FULL_CIRCLE)
            .setStrokeWidth(RING_STROKE)
            .setOuterMarginApplied(false)
            .setCircularProgressIndicatorColors(ProgressIndicatorColors(TileColors.GREEN, TileColors.TRACK))
            .setContentDescription("Rest timer")
            .build()
        val countdown = Text.Builder(ui.context, RestCountdown.text(model.endsAt, model.remainingSeconds), RestCountdown.widthConstraint())
            .setTypography(Typography.TYPOGRAPHY_TITLE2)
            .setColor(argb(TileColors.INK))
            .setWeight(LayoutElementBuilders.FONT_WEIGHT_BOLD)
            .build()
        return LayoutElementBuilders.Box.Builder()
            .setWidth(dp(size))
            .setHeight(dp(size))
            .setHorizontalAlignment(LayoutElementBuilders.HORIZONTAL_ALIGN_CENTER)
            .setVerticalAlignment(LayoutElementBuilders.VERTICAL_ALIGN_CENTER)
            .addContent(indicator)
            .addContent(countdown)
            .build()
    }

    private fun ringSize(device: DeviceParameters): Float = (device.screenHeightDp * RING_SHARE).coerceIn(RING_MIN, RING_MAX)

    internal companion object {
        const val ACTION_LOG = "log"
        const val ACTION_SKIP_REST = "skipRest"
        const val ACTION_ADD_REST = "addRest"
        const val ACTION_RESUME = "resume"

        private const val BUTTON_GAP = 8f
        private const val RING_STROKE = 5f
        private const val FULL_CIRCLE = 360f
        private const val RING_SHARE = 0.34f
        private const val RING_MIN = 60f
        private const val RING_MAX = 96f

        /** The command behind a clickable of this tile; null for an action that is not a command. */
        fun commandFor(action: String): WidgetCommand? = when (action) {
            ACTION_LOG -> WearCommands.logNextSet()
            ACTION_SKIP_REST -> WearCommands.skipRest()
            ACTION_ADD_REST -> WearCommands.adjustRest(WearCommands.REST_STEP_SECONDS)
            ACTION_RESUME -> WearCommands.resume()
            else -> null
        }
    }
}
