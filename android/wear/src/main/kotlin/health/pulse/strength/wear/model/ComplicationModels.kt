package health.pulse.strength.wear.model

import health.pulse.strength.core.SnapshotPhase
import health.pulse.strength.core.WorkoutSnapshot
import health.pulse.strength.wear.data.WearView
import java.time.Duration
import java.time.Instant
import kotlin.math.ceil
import kotlin.math.max

/*
 * What each complication shows, as plain data. `ComplicationFactory` turns these into the watch face's `ComplicationData` types, so a
 * service only chooses which model fits the type it was asked for.
 */

/** What tapping a complication does. */
internal enum class Tap {
    /** Opens the watch app. */
    OPEN_APP,

    /** Opens the watch app and asks the phone to start the next workout. */
    START_NEXT,
}

/** A monochrome symbol that accompanies the text of a complication. */
internal enum class Glyph { PLAY, FLAME }

/** A complication with a gauge (RANGED_VALUE). */
internal data class RangedContent(
    val value: Float,
    val max: Float,
    val text: String,
    val title: String?,
    val description: String,
    val tap: Tap = Tap.OPEN_APP,
)

/** A complication that is text (SHORT_TEXT, LONG_TEXT) or just a symbol (the image types use [description] and [glyph]). */
internal data class TextContent(
    val text: String,
    val title: String?,
    val description: String,
    val glyph: Glyph? = null,
    val tap: Tap = Tap.OPEN_APP,
)

internal object ComplicationModels {
    private const val WAITING = "Waiting for your phone"
    private const val NO_VALUE = "--"

    /** WA-01 / WA-07: workouts finished against the goal, with the next split as the short title of the corner gauge. */
    fun weeklyGoalRanged(view: WearView): RangedContent {
        val week = view.snapshot.week
        val goal = max(week.goal, 1)
        if (view.isPlaceholder) return RangedContent(0f, goal.toFloat(), NO_VALUE, null, WAITING)
        return RangedContent(
            value = week.completed.coerceIn(0, goal).toFloat(),
            max = goal.toFloat(),
            text = "${week.completed}/$goal",
            title = view.snapshot.nextUp?.let { WearText.splitWord(it.splitLabel) },
            description = "${week.completed} of $goal workouts this week",
        )
    }

    fun weeklyGoalText(view: WearView): TextContent {
        val week = view.snapshot.week
        if (view.isPlaceholder) return TextContent(NO_VALUE, null, WAITING)
        val goal = max(week.goal, 1)
        return TextContent("${week.completed}/$goal", "WEEK", "${week.completed} of $goal workouts this week")
    }

    /** WA-01: days since the last workout. */
    fun daysSince(view: WearView): TextContent {
        if (view.isPlaceholder) return TextContent(NO_VALUE, null, WAITING)
        val days = view.snapshot.week.daysSinceLastWorkout
        return TextContent(WearText.daysShort(days), if (days != null) "ago" else null, WearText.daysSpoken(days))
    }

    /** WA-01: the next workout by name (LONG_TEXT); while a workout runs, its progress instead. */
    fun nextUpLong(view: WearView): TextContent {
        if (view.isPlaceholder) return TextContent(WAITING, "Pulse", WAITING)
        val active = view.snapshot.active
        val nextUp = view.snapshot.nextUp
        return when {
            active != null -> {
                val progress = progress(active)
                TextContent(active.workoutName, progress, "${active.workoutName} in progress, $progress")
            }
            nextUp == null -> TextContent("No workout planned", "Add one on your phone", "No workout planned")
            else -> TextContent(
                text = nextUp.name,
                title = WearText.exercises(nextUp.exerciseCount),
                description = "Next up: ${nextUp.name}, ${WearText.planSummary(nextUp.exerciseCount, nextUp.estimatedMinutes)}",
            )
        }
    }

    /** WA-10: the split as a short reminder ("PUSH", "5d ago"); while a workout runs, its set count. */
    fun nextUpShort(view: WearView): TextContent {
        if (view.isPlaceholder) return TextContent(NO_VALUE, null, WAITING)
        val active = view.snapshot.active
        val nextUp = view.snapshot.nextUp
        return when {
            active != null -> TextContent(
                text = WearText.short("${active.loggedSets}/${active.totalSets}"),
                title = "SETS",
                description = "${active.workoutName} in progress, ${progress(active)}",
            )
            nextUp == null -> TextContent(NO_VALUE, null, "No workout planned")
            else -> TextContent(
                text = WearText.splitWord(nextUp.splitLabel),
                title = nextUp.daysSince?.let { WearText.daysAgoShort(it) },
                description = "Next up: ${nextUp.splitLabel}" + (nextUp.daysSince?.let { ", last done ${WearText.daysAgo(it).lowercase()}" } ?: ""),
            )
        }
    }

    /** WA-01: the play button. Starts the next workout when there is one to start and none is running. */
    fun start(view: WearView): TextContent {
        if (view.isPlaceholder) return TextContent("Start", null, WAITING, Glyph.PLAY)
        val active = view.snapshot.active
        val nextUp = view.snapshot.nextUp
        return when {
            active != null -> TextContent("Open", null, "Open ${active.workoutName}", Glyph.PLAY)
            nextUp == null -> TextContent("Start", null, "Open Pulse Strength", Glyph.PLAY)
            else -> TextContent("Start", null, "Start ${nextUp.name}", Glyph.PLAY, Tap.START_NEXT)
        }
    }

    /** WA-10: the week streak. */
    fun streak(view: WearView): TextContent {
        if (view.isPlaceholder) return TextContent(NO_VALUE, null, WAITING, Glyph.FLAME)
        val weeks = view.snapshot.week.streakWeeks
        return TextContent("${weeks}wk", null, if (weeks == 1) "1 week streak" else "$weeks week streak", Glyph.FLAME)
    }

    /** WA-10: working sets this week against the target of the four major groups. */
    fun weeklySets(view: WearView): RangedContent {
        val sets = view.snapshot.weeklySets
        val target = max(sets.totalTarget, 1)
        if (view.isPlaceholder) return RangedContent(0f, target.toFloat(), NO_VALUE, "SETS", WAITING)
        return RangedContent(
            value = sets.totalSets.coerceIn(0, target).toFloat(),
            max = target.toFloat(),
            text = sets.totalSets.toString(),
            title = "SETS",
            description = "${sets.totalSets} of $target working sets this week",
        )
    }

    private fun progress(active: WorkoutSnapshot): String =
        if (active.phase == SnapshotPhase.COMPLETE) "all sets logged" else "${active.loggedSets} of ${active.totalSets} sets"
}

/** WA-02: the state of the rest timer, which decides what the rest complication shows and until when. */
internal sealed interface RestContent {
    /** Only the preview exists. */
    data object Waiting : RestContent

    /** No rest is running (logging, finished, or no workout). */
    data object Idle : RestContent

    /** Counting down until [endsAt]; the countdown itself is drawn by the watch face from the timestamps. */
    data class Counting(
        val startedAt: Instant,
        val endsAt: Instant,
        val totalSeconds: Int,
        val remainingSeconds: Int,
    ) : RestContent

    /** The rest ran out and the next set is due. */
    data object Over : RestContent

    /** The workout is paused: the rest is frozen with [remainingSeconds] left. */
    data class Frozen(val remainingSeconds: Int, val totalSeconds: Int) : RestContent

    companion object {
        fun of(view: WearView, now: Instant): RestContent {
            val active = view.snapshot.active
            return when {
                view.isPlaceholder -> Waiting
                active == null || active.phase == SnapshotPhase.COMPLETE || active.phase == SnapshotPhase.LOGGING -> Idle
                active.phase == SnapshotPhase.REST_OVER -> Over
                else -> resting(active, now)
            }
        }

        private fun resting(active: WorkoutSnapshot, now: Instant): RestContent {
            val total = max(active.restTotalSeconds, 1)
            val frozen = active.restFrozenRemaining
            val endsAt = active.restEndsAt
            return when {
                active.isPaused && frozen != null -> Frozen(frozen.coerceAtLeast(0), total)
                endsAt == null -> Idle
                !endsAt.isAfter(now) -> Over
                else -> {
                    val remaining = ceil(Duration.between(now, endsAt).toMillis() / 1000.0).toInt()
                    val length = max(total, remaining)
                    Counting(endsAt.minusSeconds(length.toLong()), endsAt, length, remaining)
                }
            }
        }
    }
}
