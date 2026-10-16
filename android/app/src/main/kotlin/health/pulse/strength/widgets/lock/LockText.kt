package health.pulse.strength.widgets.lock

import health.pulse.strength.core.widgets.DeepLinks
import health.pulse.strength.core.widgets.NextUpSummary
import health.pulse.strength.core.widgets.OverloadTarget
import health.pulse.strength.core.widgets.PRSummary
import health.pulse.strength.core.widgets.WeekSummary
import health.pulse.strength.core.widgets.WeeklySetsSummary
import health.pulse.strength.core.widgets.WidgetSnapshot
import kotlin.math.abs

/** The text and numbers of a 1x1 gauge: "3/4" on a gauge filled to [fraction]. */
internal data class GaugeModel(val label: String, val fraction: Float, val description: String)

/** A figure with a small caption below it ("3d" over "SINCE"). */
internal data class CaptionedValue(val value: String, val caption: String, val description: String)

internal data class StreakModel(val label: String, val isActive: Boolean, val description: String)

/** Where a tap on a one-button widget goes, and what a screen reader says about it. */
internal data class QuickStartModel(val link: String, val description: String)

/**
 * The three lines of a 3x1 widget. [titleSuffix] holds figures that must stay visible when a long [title] is shortened ("85 × 5" after
 * "Incline Dumbbell Press"); [isHighlighted] tints the icon (a personal record set in the last 24 hours).
 */
internal data class CompactCard(
    val eyebrow: String,
    val title: String,
    val titleSuffix: String,
    val detail: String,
    val link: String,
    val description: String,
    val isHighlighted: Boolean = false,
)

/** A labelled figure over a meter ("Sets this week 37", the bar at 77%, "11 to go · legs lagging"). */
internal data class MeterCard(
    val title: String,
    val value: String,
    val fraction: Float,
    val detail: String,
    val description: String,
)

/** A line of text in two parts: the [lead] may be shortened with an ellipsis to make room, the [trail] never is. */
internal data class TextLine(val lead: String, val trail: String = "") {
    val text: String get() = lead + trail
}

/** The single line of a 4x1 widget. */
internal data class InlineModel(val line: TextLine, val link: String, val showsIcon: Boolean) {
    val text: String get() = line.text
}

/** Which text each lock / glanceable-hub widget shows for a snapshot (LS-01 ... LS-11). Pure, so the rules are unit-tested. */
internal object LockText {
    private fun ratio(done: Int, total: Int): Float = if (total > 0) (done.toFloat() / total).coerceIn(0f, 1f) else 0f

    private fun workouts(goal: Int): String = if (goal == 1) "workout" else "workouts"

    /** Where "start" goes: the running workout, else the next template, else the hub (nothing to start). */
    fun startLink(snapshot: WidgetSnapshot): String = when {
        snapshot.active != null -> DeepLinks.workout
        snapshot.nextUp != null -> DeepLinks.startNext
        else -> DeepLinks.hub
    }

    /** LS-01: completed over goal, the gauge clamped to a full circle when the goal is exceeded. */
    fun weeklyGoal(week: WeekSummary): GaugeModel = GaugeModel(
        label = "${week.completed}/${week.goal}",
        fraction = ratio(week.completed, week.goal),
        description = "${week.completed} of ${week.goal} ${workouts(week.goal)} this week",
    )

    /** LS-02: whole days since the last workout ("3d"); an en dash when there is no history. */
    fun daysSince(week: WeekSummary): CaptionedValue {
        val days = week.daysSinceLastWorkout
        val description = when {
            days == null -> "No workouts logged yet"
            days <= 0 -> "You trained today"
            days == 1 -> "1 day since your last workout"
            else -> "$days days since your last workout"
        }
        return CaptionedValue(PulseFormat.daysShort(days), "since", description)
    }

    /** LS-03: the run of weeks that met the goal ("6 wk"); the flame is dimmed at 0. */
    fun streak(week: WeekSummary): StreakModel {
        val weeks = week.streakWeeks
        return StreakModel(
            label = "$weeks wk",
            isActive = weeks > 0,
            description = if (weeks > 0) "$weeks-week streak" else "No week streak yet",
        )
    }

    /** LS-04: the play button starts the next workout, or opens the one that is already running. */
    fun quickStart(snapshot: WidgetSnapshot): QuickStartModel {
        val next = snapshot.nextUp
        return when {
            snapshot.active != null -> QuickStartModel(DeepLinks.workout, "Open the running workout")
            next != null -> QuickStartModel(DeepLinks.startNext, "Start ${next.name}")
            else -> QuickStartModel(DeepLinks.hub, "Open Pulse Strength to create a workout")
        }
    }

    /** "6 exercises · ~55 min": what a template holds; the duration is left out when the template has no estimate. */
    fun templateDetail(template: NextUpSummary): String = listOfNotNull(
        PulseFormat.exercises(template.exerciseCount),
        template.estimatedMinutes.takeIf { it > 0 }?.let { PulseFormat.minutes(it) },
    ).joinToString(" · ")

    /** LS-05: the next template ("Upper A · Push", "6 exercises · ~55 min"); while a workout runs, that workout. */
    fun nextUp(snapshot: WidgetSnapshot): CompactCard {
        val active = snapshot.active
        val next = snapshot.nextUp
        return when {
            active != null -> {
                val progress = "${active.loggedSets} of ${active.totalSets} sets"
                CompactCard(
                    eyebrow = "In progress",
                    title = active.workoutName,
                    titleSuffix = "",
                    detail = progress,
                    link = DeepLinks.workout,
                    description = "Workout in progress: ${active.workoutName}, $progress logged",
                )
            }
            next != null -> {
                val detail = templateDetail(next)
                CompactCard(
                    eyebrow = "Next up",
                    title = next.name,
                    titleSuffix = "",
                    detail = detail,
                    link = DeepLinks.startNext,
                    description = "Next workout: ${next.name}, $detail",
                )
            }
            else -> CompactCard(
                eyebrow = "Next up",
                title = "No workout planned",
                titleSuffix = "",
                detail = "Create a template to begin",
                link = DeepLinks.hub,
                description = "No workout planned. Open Pulse Strength to create a template",
            )
        }
    }

    /** LS-06: working sets this week against the 48-set target, and the lagging muscle group. */
    fun weeklySets(summary: WeeklySetsSummary): MeterCard {
        val lagging = summary.laggingMuscle
        val detail = when {
            summary.setsToGo <= 0 -> "Target reached"
            summary.totalSets == 0 || lagging == null -> "${summary.setsToGo} to go"
            else -> "${summary.setsToGo} to go · ${lagging.title.lowercase()} lagging"
        }
        return MeterCard(
            title = "Sets this week",
            value = summary.totalSets.toString(),
            fraction = ratio(summary.totalSets, summary.totalTarget),
            detail = detail,
            description = "${summary.totalSets} of ${summary.totalTarget} sets this week. $detail",
        )
    }

    /** LS-07: the newest personal record ("Bench Press" "85 × 5", "e1RM 99 kg · +4 kg"). */
    fun latestRecord(pr: PRSummary?): CompactCard {
        if (pr == null) {
            return CompactCard(
                eyebrow = "Latest PR",
                title = "No records yet",
                titleSuffix = "",
                detail = "Lift heavier to set one",
                link = DeepLinks.hub,
                description = "No personal records yet",
            )
        }
        val sets = PulseFormat.weightReps(pr.weightKg, pr.reps)
        val estimate = "e1RM ${PulseFormat.kg(pr.estimated1RM)} kg"
        val gain = if (pr.deltaKg >= 0.005) " · ${PulseFormat.signed(pr.deltaKg)} kg" else ""
        return CompactCard(
            eyebrow = if (pr.isFresh) "New PR" else "Latest PR",
            title = pr.exerciseName,
            titleSuffix = sets,
            detail = estimate + gain,
            link = DeepLinks.exercise(pr.exerciseID),
            description = "${if (pr.isFresh) "New" else "Latest"} personal record: ${pr.exerciseName}, " +
                "${PulseFormat.kg(pr.weightKg)} kilograms for ${pr.reps} reps, estimated one-rep max ${PulseFormat.kg(pr.estimated1RM)} kilograms",
            isHighlighted = pr.isFresh,
        )
    }

    /** LS-08: what to lift today to beat last time ("Bench Press" "4 × 6", "82.5 kg · +2.5 vs last"). */
    fun overload(target: OverloadTarget?): CompactCard {
        if (target == null) {
            return CompactCard(
                eyebrow = "Today's target",
                title = "Nothing to beat yet",
                titleSuffix = "",
                detail = "Finish a workout first",
                link = DeepLinks.hub,
                description = "No overload target yet. Finish a workout first",
            )
        }
        val sets = "${target.targetSets} × ${target.targetReps}"
        val detail = "${PulseFormat.kg(target.targetWeightKg)} kg · ${overloadChange(target)}"
        return CompactCard(
            eyebrow = "Today's target",
            title = target.exerciseName,
            titleSuffix = sets,
            detail = detail,
            link = DeepLinks.exercise(target.exerciseID),
            description = "Today's target: ${target.exerciseName}, ${target.targetSets} sets of ${target.targetReps}, $detail",
        )
    }

    /** How the target differs from last time: heavier, more reps, or the same. */
    internal fun overloadChange(target: OverloadTarget): String {
        val extraReps = target.targetReps - target.lastReps
        return when {
            abs(target.deltaKg) >= 0.005 -> "${PulseFormat.signed(target.deltaKg)} vs last"
            extraReps > 0 -> "+$extraReps ${if (extraReps == 1) "rep" else "reps"} vs last"
            else -> "same as last"
        }
    }

    /** "Push day" and " · last 5 days ago": the next split and how long ago it was trained. */
    fun splitLine(snapshot: WidgetSnapshot): TextLine {
        val next = snapshot.nextUp ?: return TextLine("No workout planned")
        val days = next.daysSince
        val last = when {
            days == null -> "not done yet"
            days <= 0 -> "last today"
            days == 1 -> "last yesterday"
            else -> "last $days days ago"
        }
        return TextLine(next.splitLabel, " · $last")
    }

    fun splitText(snapshot: WidgetSnapshot): String = splitLine(snapshot).text

    /** "Rest day" and " · back on Sun", or null when today is not a rest day. */
    fun restLine(snapshot: WidgetSnapshot): TextLine? {
        val rest = snapshot.restDay ?: return null
        val reason = rest.reason.ifBlank { "Rest day" }
        val back = snapshot.tomorrow?.weekday?.trim()?.take(3)?.takeIf { it.isNotEmpty() }
        return TextLine(reason, if (back == null) "" else " · back on $back")
    }

    fun restText(snapshot: WidgetSnapshot): String? = restLine(snapshot)?.text

    /** LS-09 / LS-10 / LS-11: the line of the inline widget of [mode]; the rest mode falls back to the split line on a training day. */
    fun inlineStatus(mode: InlineStatusWidget.Mode, snapshot: WidgetSnapshot): InlineModel = when (mode) {
        InlineStatusWidget.Mode.WEEK -> {
            val week = snapshot.week
            InlineModel(TextLine("${week.completed} of ${week.goal} ${workouts(week.goal)} this week"), DeepLinks.hub, showsIcon = true)
        }
        InlineStatusWidget.Mode.SPLIT -> InlineModel(splitLine(snapshot), startLink(snapshot), showsIcon = false)
        InlineStatusWidget.Mode.REST -> {
            val rest = restLine(snapshot)
            if (rest != null) InlineModel(rest, DeepLinks.hub, showsIcon = false) else inlineStatus(InlineStatusWidget.Mode.SPLIT, snapshot)
        }
    }
}
