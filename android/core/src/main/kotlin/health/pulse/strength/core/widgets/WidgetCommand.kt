package health.pulse.strength.core.widgets

import kotlinx.serialization.Serializable

/**
 * One command a surface (widget, tile, complication, notification action, Wear message) asks the workout engine to run.
 * The vocabulary is widgets/SPEC.md section 5; the same names travel from the watch to the phone.
 */
@Serializable
data class WidgetCommand(
    val name: String,
    val args: Map<String, String> = emptyMap(),
) {
    companion object {
        fun of(name: String, vararg args: Pair<String, String>) = WidgetCommand(name, args.toMap())
    }
}

/** Command names (widgets/SPEC.md section 5) and the names of their arguments. */
object WidgetCommands {
    const val START_NEXT = "startNext"
    /** args: [ARG_TEMPLATE_ID] */
    const val START_TEMPLATE = "startTemplate"
    /** args: [ARG_NAME] (optional) */
    const val START_EMPTY = "startEmpty"
    const val LOG_NEXT_SET = "logNextSet"
    /** args: [ARG_EXERCISE_ID], [ARG_SET_ID] */
    const val LOG_SET = "logSet"
    /** args: [ARG_WEIGHT_STEPS], [ARG_REPS_STEPS] (integers as text, default "0") */
    const val NUDGE = "nudge"
    /** args: [ARG_SECONDS] */
    const val ADJUST_REST = "adjustRest"
    const val SKIP_REST = "skipRest"
    const val PAUSE = "pause"
    const val RESUME = "resume"
    const val FINISH = "finish"
    /** args: [ARG_SET_ID], [ARG_WEIGHT_KG] */
    const val APPLY_COACH_TIP = "applyCoachTip"
    /** Log set while logging, skip rest while resting, start next with no workout. */
    const val PRIMARY_ACTION = "primaryAction"

    const val ARG_TEMPLATE_ID = "templateId"
    const val ARG_NAME = "name"
    const val ARG_EXERCISE_ID = "exerciseId"
    const val ARG_SET_ID = "setId"
    const val ARG_WEIGHT_STEPS = "weightSteps"
    const val ARG_REPS_STEPS = "repsSteps"
    const val ARG_SECONDS = "seconds"
    const val ARG_WEIGHT_KG = "weightKg"
}

/** The Wearable Data Layer contract between the phone app and the watch app. */
object WearProtocol {
    /** DataItem path; the phone writes [KEY_JSON] = `WidgetJson.encodeSnapshot(...)`. */
    const val SNAPSHOT_PATH = "/pulse/widget-snapshot"
    /** Message path; the watch sends `WidgetJson.json.encodeToString(WidgetCommand.serializer(), command)` as UTF-8 bytes. */
    const val COMMAND_PATH = "/pulse/command"
    const val KEY_JSON = "json"
    /** Capability the phone app advertises (res/values/wear.xml `android_wear_capabilities`). */
    const val PHONE_CAPABILITY = "pulse_strength_phone"
}
