package health.pulse.strength.live

import health.pulse.strength.core.widgets.DeepLinks
import health.pulse.strength.core.widgets.WidgetCommand

/** The notification channels of the app (res/values/strings.xml names them). Importance and sound are set in [LiveUpdateNotifier]. */
internal enum class LiveChannel(val id: String) {
    /** The running workout, the planned-session countdown and the finish card: default importance, no sound, no vibration. */
    WORKOUT("workout"),

    /** "Time to train": the one notification of the app that is meant to be heard. */
    REMINDER("workout_reminder"),
}

/** The fixed notification ids of the app. */
internal object LiveIds {
    /** The one ongoing workout card; every phase of a running workout replaces it in place. */
    const val LIVE = 4101
    const val FINISH = 4102
    const val PLANNED = 4103
    const val PLANNED_DUE = 4104
}

/** Which notification a [LiveUpdateModel] is. The five states of a running workout share one id, so a state change replaces the card. */
internal enum class LiveKind(val notificationId: Int, val channel: LiveChannel) {
    LOGGING(LiveIds.LIVE, LiveChannel.WORKOUT),
    RESTING(LiveIds.LIVE, LiveChannel.WORKOUT),
    REST_OVER(LiveIds.LIVE, LiveChannel.WORKOUT),
    PAUSED(LiveIds.LIVE, LiveChannel.WORKOUT),
    COMPLETE(LiveIds.LIVE, LiveChannel.WORKOUT),
    FINISH(LiveIds.FINISH, LiveChannel.WORKOUT),
    PLANNED(LiveIds.PLANNED, LiveChannel.WORKOUT),
    PLANNED_DUE(LiveIds.PLANNED_DUE, LiveChannel.REMINDER),
}

/** Which of the brand colours accents the card; [LiveUpdateNotifier] maps it to light and dark values. */
internal enum class LiveAccent { GREEN, GOLD, BLUE }

/** The time the system draws for the card (and in the status-bar chip when no chip text is set). */
internal sealed interface LiveClock {
    data object None : LiveClock

    /** Counts up from [sinceMillis]. */
    data class Elapsed(val sinceMillis: Long) : LiveClock

    /** Counts down to [untilMillis]. */
    data class Countdown(val untilMillis: Long) : LiveClock
}

/** The segmented bar of the Android 16 progress style: [value] of the sum of [segments], each segment at least 1. */
internal data class LiveProgress(val value: Int, val segments: List<Int>) {
    val max: Int get() = segments.sum()
}

/** The buttons of the cards. Each owns a fixed request code, because pending intents that differ only in their extras would collapse into one. */
internal enum class LiveActionId(val requestCode: Int) {
    LOG_SET(1),
    NUDGE_DOWN(2),
    NUDGE_UP(3),
    REST_DOWN(4),
    REST_UP(5),
    SKIP_REST(6),
    APPLY_TIP(7),
    KEEP_TIP(8),
    RESUME(9),
    FINISH(10),
    SHARE(11),
    START_PLANNED(12),
    SNOOZE_PLANNED(13),
}

/** What a button does. */
internal sealed interface LiveTarget {
    /** Runs a command through `StrengthRuntime.commands` without opening the app. */
    data class Command(val command: WidgetCommand) : LiveTarget

    /** Opens the app on a `pulse-strength://` link. */
    data class Link(val url: String) : LiveTarget

    /** Answers "Keep 80": only the tip for [setId] disappears, nothing is sent to the engine. */
    data class KeepCoachTip(val setId: String) : LiveTarget

    /** Opens the share sheet with [text]. */
    data class Share(val text: String) : LiveTarget

    /** Moves the planned session by [minutes]. */
    data class Snooze(val minutes: Int) : LiveTarget
}

internal data class LiveAction(val id: LiveActionId, val title: String, val target: LiveTarget)

/**
 * Everything a card says, as plain data. [LiveUpdateModels] decides it from a snapshot, [LiveUpdateNotifier] only draws it, and the tests
 * read it directly.
 *
 * @property text the one line under the title; on every Android version this is what the collapsed card shows.
 * @property overlayLines the superset members and the plate line (LA-02, LA-03): they need the big-text style, because the progress
 * style of Android 16 has no room for more than [text].
 * @property detailLines further lines of the big-text style: totals, heart rate.
 * @property chipText the status-bar chip of Android 16 (at most [LiveUpdateModels.MAX_CHIP_LENGTH] characters); null lets the system
 * draw the card's clock there.
 */
internal data class LiveUpdateModel(
    val kind: LiveKind,
    val title: String,
    val text: String,
    val subText: String? = null,
    val overlayLines: List<String> = emptyList(),
    val detailLines: List<String> = emptyList(),
    val chipText: String? = null,
    val clock: LiveClock = LiveClock.None,
    val progress: LiveProgress? = null,
    val actions: List<LiveAction> = emptyList(),
    val accent: LiveAccent = LiveAccent.GREEN,
    val contentLink: String = DeepLinks.workout,
    val ongoing: Boolean = true,
    val timeoutMillis: Long? = null,
) {
    /** The expanded text: the headline, the overlay lines, then the details. */
    val bigText: String get() = (listOf(text) + overlayLines + detailLines).joinToString("\n")

    /** True when the card cannot do without its big text, so Android 16 uses the big-text style instead of the progress style. */
    val needsBigText: Boolean get() = overlayLines.isNotEmpty()
}
