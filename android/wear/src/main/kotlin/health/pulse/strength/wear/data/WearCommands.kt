package health.pulse.strength.wear.data

import health.pulse.strength.core.widgets.WidgetCommand
import health.pulse.strength.core.widgets.WidgetCommands

/** The commands the watch sends to the phone (widgets/SPEC.md section 5), built in one place for the tiles and the app. */
internal object WearCommands {
    /** Seconds one tap on "+15 s" / "-15 s" moves the rest. */
    const val REST_STEP_SECONDS = 15

    fun startNext() = WidgetCommand.of(WidgetCommands.START_NEXT)

    fun logNextSet() = WidgetCommand.of(WidgetCommands.LOG_NEXT_SET)

    fun nudge(weightSteps: Int, repsSteps: Int) = WidgetCommand.of(
        WidgetCommands.NUDGE,
        WidgetCommands.ARG_WEIGHT_STEPS to weightSteps.toString(),
        WidgetCommands.ARG_REPS_STEPS to repsSteps.toString(),
    )

    fun adjustRest(seconds: Int) = WidgetCommand.of(WidgetCommands.ADJUST_REST, WidgetCommands.ARG_SECONDS to seconds.toString())

    fun skipRest() = WidgetCommand.of(WidgetCommands.SKIP_REST)

    fun pause() = WidgetCommand.of(WidgetCommands.PAUSE)

    fun resume() = WidgetCommand.of(WidgetCommands.RESUME)

    fun finish() = WidgetCommand.of(WidgetCommands.FINISH)
}
