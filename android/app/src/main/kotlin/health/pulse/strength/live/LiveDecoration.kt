package health.pulse.strength.live

import health.pulse.strength.core.NumberText
import health.pulse.strength.core.SnapshotPhase
import health.pulse.strength.core.WorkoutSnapshot
import health.pulse.strength.core.widgets.CoachTipBrief
import health.pulse.strength.core.widgets.PRMoment
import health.pulse.strength.core.widgets.PlateBrief
import health.pulse.strength.core.widgets.SupersetBrief
import health.pulse.strength.core.widgets.WidgetCommand
import health.pulse.strength.core.widgets.WidgetCommands
import health.pulse.strength.services.WorkoutNotifications
import java.time.Instant

/** Which of the brand colours accents a notification; [LiveCards] maps it to light and dark values. */
internal enum class LiveAccent { GREEN, GOLD }

/** The segmented bar of the Android 16 progress style: [value] of the sum of [segments], each segment at least 1. */
internal data class LiveProgress(val value: Int, val segments: List<Int>)

/**
 * What LA-01 ... LA-10 add to the ongoing workout notification, which `WorkoutNotifications.ongoing` builds. A null or empty field
 * leaves the base notification alone, so a workout without live moments looks exactly as before.
 *
 * @property title replaces the title (the PR moment).
 * @property text replaces the one line under the title (the PR moment, the coach tip).
 * @property bigText the expanded text; present when the card needs lines that one line cannot hold (superset members, plates, the tip).
 * It starts with the line the collapsed card shows. On Android 16 a card with big text uses the big-text style instead of the
 * progress style, which has no room for it.
 * @property chipText the status-bar chip of Android 16 (at most [LiveDecorations.MAX_CHIP_LENGTH] characters); null leaves the clock.
 * @property progress the segmented progress of Android 16, for a card without [bigText].
 * @property actions replaces ALL buttons of the base notification (the superset's "Log A2", the coach tip's answers).
 * @property opensBenchMode a tap opens bench mode, the big rest timer, instead of the workout.
 * @property finish the workout is over: the notification turns into this summary card.
 */
internal data class LiveDecoration(
    val title: String? = null,
    val text: String? = null,
    val bigText: String? = null,
    val chipText: String? = null,
    val progress: LiveProgress? = null,
    val actions: List<LiveAction>? = null,
    val accent: LiveAccent? = null,
    val opensBenchMode: Boolean = false,
    val finish: LiveCard? = null,
)

/**
 * LA-01 ... LA-05 and LA-07 ... LA-10: the decision "snapshot -> what to add to the notification". A pure function of the snapshot and
 * the clock, unit-tested for every state; [LiveUpdates.decorate] only applies the result to the builder.
 *
 * Layering of a running workout: the phase (logging, resting, rest over, paused, complete) is drawn by the base notification; the live
 * moments decorate it (PR moment, superset, plate math, coach tip); the chip text follows the compact priority of widgets/SPEC.md:
 * `moment` > resting countdown > `superset` > logging.
 */
internal object LiveDecorations {
    /** Android 16 truncates or drops longer chip texts. */
    const val MAX_CHIP_LENGTH = 7

    /** The line `WorkoutNotifications` shows while a rest runs or is over ("Next: Set 2 · 60 kg × 8"); a test keeps the two equal. */
    private const val NEXT_PREFIX = "Next: "

    fun of(snapshot: WorkoutSnapshot, now: Instant, dismissedTipSetId: String? = null): LiveDecoration {
        snapshot.finish?.let { return LiveDecoration(finish = LiveCards.finish(it)) }

        val phase = snapshot.displayPhase(now)
        val paused = snapshot.isPaused
        val pending = !paused && phase != SnapshotPhase.COMPLETE
        val moment = snapshot.moment?.takeIf { !paused && now.isBefore(it.expiresAt) }
        val superset = snapshot.superset?.takeIf { pending && it.members.isNotEmpty() }
        val plates = snapshot.plates?.takeIf { pending }
        val tip = snapshot.coachTip?.takeIf { !paused && phase == SnapshotPhase.RESTING && it.targetSetID != dismissedTipSetId }

        val momentText = moment?.let(::momentText)
        val base = baseText(snapshot, phase, paused)
        val overlay = buildList {
            superset?.let {
                add("Superset · round ${it.round}/${it.rounds}")
                addAll(memberLines(it))
            }
            plates?.let { add(platesLine(it)) }
        }
        // The line the collapsed card shows; the expanded card starts with it and adds what does not fit on one line.
        val headline = momentText ?: tip?.text ?: base
        val bigText = headline?.takeIf { overlay.isNotEmpty() || tip != null }?.let { expandedText(snapshot, it, base, tip, overlay) }

        return LiveDecoration(
            title = moment?.let { "New record: ${it.exerciseName}" },
            text = momentText ?: tip?.text,
            bigText = bigText,
            chipText = chipText(snapshot, phase, moment, superset),
            progress = if (bigText == null) progressOf(snapshot) else null,
            actions = when {
                tip != null -> tipActions(tip)
                superset != null && phase != SnapshotPhase.RESTING -> logActions(snapshot, superset)
                else -> null
            },
            accent = if (moment != null) LiveAccent.GOLD else null,
            opensBenchMode = !paused && (phase == SnapshotPhase.RESTING || phase == SnapshotPhase.REST_OVER),
        )
    }

    /** When the PR flash of [snapshot] ends, if one is showing at [now]: the instant the notification has to be drawn again. */
    fun flashEnd(snapshot: WorkoutSnapshot, now: Instant): Instant? =
        snapshot.moment?.expiresAt?.takeIf { snapshot.finish == null && !snapshot.isPaused && now.isBefore(it) }

    // ---------------------------------------------------------------------------------------------------------------- text

    /** The line that the base notification shows under the title for this state; null where this package does not restate it. */
    private fun baseText(snapshot: WorkoutSnapshot, phase: SnapshotPhase, paused: Boolean): String? = when {
        paused || phase == SnapshotPhase.COMPLETE -> null
        phase == SnapshotPhase.RESTING || phase == SnapshotPhase.REST_OVER -> NEXT_PREFIX + snapshot.nextSetText
        else -> "${snapshot.setLabel} · ${WorkoutNotifications.workText(snapshot)}"
    }

    private fun expandedText(
        snapshot: WorkoutSnapshot,
        headline: String,
        base: String?,
        tip: CoachTipBrief?,
        overlay: List<String>,
    ): String {
        val lines = mutableListOf(headline)
        if (tip != null) {
            if (tip.text != headline) lines += tip.text
            if (tip.subtitle.isNotBlank()) lines += tip.subtitle
        }
        if (base != null && base != headline) lines += base
        lines += overlay
        if (snapshot.totalSets > 0) lines += LiveText.progress(snapshot)
        snapshot.heartRate?.let { lines += "Heart rate $it bpm" }
        return lines.joinToString("\n")
    }

    /** LA-01: "85 × 5 · e1RM 99 kg (+4)". */
    private fun momentText(moment: PRMoment): String = buildString {
        append("${moment.weightText} × ${moment.repsText}")
        if (moment.estimated1RM > 0) {
            append(" · e1RM ${moment.estimated1RM} kg")
            if (moment.deltaKg > 0) append(" (+${moment.deltaKg})")
        }
    }

    /** LA-02: "A1 Lateral Raise · 10 × 12 (done)", "A2 Triceps Pushdown · 25 × 12 (now)". The state is in words, never only in a mark. */
    private fun memberLines(superset: SupersetBrief): List<String> = superset.members.map { member ->
        val detail = if (member.detail.isBlank()) "" else " · ${member.detail}"
        val state = when {
            member.isCurrent -> " (now)"
            member.isDone -> " (done)"
            else -> ""
        }
        "${member.tag} ${member.name}$detail$state"
    }

    /** LA-03: "Per side: 20 + 10 + 2.5". */
    private fun platesLine(plates: PlateBrief): String {
        val loaded = plates.summary.ifBlank { plates.perSide.joinToString(" + ") { NumberText.kg(it) } }
        val line = "Per side: " + loaded.ifBlank { "bar only" }
        return if (plates.leftoverKg > 0) "$line · ${NumberText.kg(plates.leftoverKg)} kg short" else line
    }

    // ------------------------------------------------------------------------------------------------------------------ chip

    /** LA-07 ... LA-10: the status-bar chip. Null leaves the clock of the card (the rest countdown, or the elapsed time) in the chip. */
    private fun chipText(snapshot: WorkoutSnapshot, phase: SnapshotPhase, moment: PRMoment?, superset: SupersetBrief?): String? = when {
        moment != null -> "PR"
        snapshot.isPaused -> "Paused"
        phase == SnapshotPhase.RESTING -> null
        phase == SnapshotPhase.REST_OVER -> "Go"
        phase == SnapshotPhase.COMPLETE -> if (snapshot.totalSets == 0) null else "Done"
        superset != null -> supersetChip(superset)
        // One value fits the chip: the heart rate is live, the set count is in the card.
        else -> snapshot.heartRate?.toString() ?: setDots(snapshot)
    }

    /** "A2 2/3"; without the tag when a long round count would not fit. */
    private fun supersetChip(superset: SupersetBrief): String {
        val rounds = "${superset.round}/${superset.rounds}"
        val tag = currentTag(superset) ?: return rounds
        val full = "$tag $rounds"
        return if (full.length <= MAX_CHIP_LENGTH) full else rounds
    }

    /** "3/4": the set being logged out of the sets of the shown exercise. */
    private fun setDots(snapshot: WorkoutSnapshot): String? {
        val count = snapshot.exerciseSetCount ?: return null
        if (count <= 0) return null
        val current = ((snapshot.exerciseDoneSets ?: 0) + 1).coerceIn(1, count)
        return "$current/$count".takeIf { it.length <= MAX_CHIP_LENGTH }
    }

    private fun currentTag(superset: SupersetBrief): String? =
        (superset.members.firstOrNull { it.isCurrent } ?: superset.members.firstOrNull { !it.isDone })?.tag

    // --------------------------------------------------------------------------------------------------------------- progress

    /**
     * The segmented bar of Android 16: the whole workout, with the sets of the shown exercise as single segments in front of the
     * earlier sets and behind the later ones. Null for a workout without sets.
     */
    fun progressOf(snapshot: WorkoutSnapshot): LiveProgress? {
        val total = snapshot.totalSets
        if (total <= 0) return null
        val logged = snapshot.loggedSets.coerceIn(0, total)
        val count = snapshot.exerciseSetCount
        if (count == null || count <= 0 || count > total) return LiveProgress(logged, listOf(total))
        val done = (snapshot.exerciseDoneSets ?: 0).coerceIn(0, count)
        val before = (logged - done).coerceIn(0, total - count)
        val after = total - before - count
        val segments = buildList {
            if (before > 0) add(before)
            repeat(count) { add(1) }
            if (after > 0) add(after)
        }
        return LiveProgress(logged, segments)
    }

    // -------------------------------------------------------------------------------------------------------------- actions

    /**
     * The buttons of a superset round: "Log A2" (the current member's tag) and the stepper, as the base notification has them. The
     * explicit set makes a late tap harmless: that set is logged once, whatever the card shows by then.
     */
    private fun logActions(snapshot: WorkoutSnapshot, superset: SupersetBrief): List<LiveAction> {
        val exerciseId = snapshot.targetExerciseID
        val setId = snapshot.targetSetID
        val log = if (exerciseId != null && setId != null) {
            WidgetCommand.of(
                WidgetCommands.LOG_SET,
                WidgetCommands.ARG_EXERCISE_ID to exerciseId.toString(),
                WidgetCommands.ARG_SET_ID to setId.toString(),
            )
        } else {
            WidgetCommand.of(WidgetCommands.LOG_NEXT_SET)
        }
        val weight = snapshot.showsWeight
        val noun = if (weight) "Weight" else "Reps"
        return listOf(
            LiveAction(LiveActionId.LOG_SET, currentTag(superset)?.let { "Log $it" } ?: "Log set", LiveTarget.Command(log)),
            LiveAction(LiveActionId.NUDGE_DOWN, "$noun −", LiveTarget.Command(nudge(if (weight) -1 else 0, if (weight) 0 else -1))),
            LiveAction(LiveActionId.NUDGE_UP, "$noun +", LiveTarget.Command(nudge(if (weight) 1 else 0, if (weight) 0 else 1))),
        )
    }

    private fun nudge(weightSteps: Int, repsSteps: Int): WidgetCommand = WidgetCommand.of(
        WidgetCommands.NUDGE,
        WidgetCommands.ARG_WEIGHT_STEPS to weightSteps.toString(),
        WidgetCommands.ARG_REPS_STEPS to repsSteps.toString(),
    )

    /** LA-04: "82.5 kg" applies the suggestion, "Keep 80" only clears the tip, "Skip" stays within reach. */
    private fun tipActions(tip: CoachTipBrief): List<LiveAction> = listOf(
        LiveAction(
            LiveActionId.APPLY_TIP,
            tip.suggestedWeightText,
            LiveTarget.Command(
                WidgetCommand.of(
                    WidgetCommands.APPLY_COACH_TIP,
                    WidgetCommands.ARG_SET_ID to tip.targetSetID,
                    WidgetCommands.ARG_WEIGHT_KG to tip.suggestedWeightKg.toString(),
                ),
            ),
        ),
        LiveAction(LiveActionId.KEEP_TIP, tip.keepWeightText, LiveTarget.KeepCoachTip(tip.targetSetID)),
        LiveAction(LiveActionId.SKIP_REST, "Skip", LiveTarget.Command(WidgetCommand.of(WidgetCommands.SKIP_REST))),
    )
}
