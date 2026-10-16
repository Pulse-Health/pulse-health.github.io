package health.pulse.strength.live

import health.pulse.strength.core.SnapshotPhase
import health.pulse.strength.core.TrackingKind
import health.pulse.strength.core.WorkoutSnapshot
import health.pulse.strength.core.widgets.CoachTipBrief
import health.pulse.strength.core.widgets.DeepLinks
import health.pulse.strength.core.widgets.FinishBrief
import health.pulse.strength.core.widgets.PRMoment
import health.pulse.strength.core.widgets.PlateBrief
import health.pulse.strength.core.widgets.SupersetBrief
import health.pulse.strength.core.widgets.WidgetCommand
import health.pulse.strength.core.widgets.WidgetCommands
import java.time.Instant

/**
 * LA-01 ... LA-05 and LA-07 ... LA-10: the decision "snapshot -> what the notification says". Pure functions of the snapshot and the
 * clock, so every state is unit-tested; [LiveUpdateNotifier] only draws the result.
 *
 * Layering of a running workout: the phase (logging, resting, rest over, paused, complete) sets the base card; the live moments
 * overlay it (PR moment, superset, plate math, coach tip); the chip text follows the compact priority of widgets/SPEC.md:
 * `moment` > resting countdown > `superset` > logging.
 */
internal object LiveUpdateModels {
    /** Android 16 truncates or drops longer chip texts. */
    const val MAX_CHIP_LENGTH = 7

    /** LA-05: the finish card stays two hours (the notification times out; iOS ends the activity with `dismissalPolicy .after`). */
    const val FINISH_LIFETIME_MILLIS: Long = 2 * 60 * 60 * 1000L

    private const val NEXT_PREFIX = "Next · "

    /** The card for a running workout; [dismissedTipSetId] is the coach tip the user answered with "Keep". */
    fun workout(snapshot: WorkoutSnapshot, now: Instant, dismissedTipSetId: String? = null): LiveUpdateModel {
        snapshot.finish?.let { return finish(it) }
        val phase = snapshot.displayPhase(now)
        val moment = snapshot.moment?.takeIf { !snapshot.isPaused && now.isBefore(it.expiresAt) }
        val superset = snapshot.superset?.takeIf { it.members.isNotEmpty() }
        val tip = snapshot.coachTip?.takeIf { it.targetSetID != dismissedTipSetId }

        val card = when {
            snapshot.isPaused -> paused(snapshot, superset)
            phase == SnapshotPhase.COMPLETE -> complete(snapshot)
            phase == SnapshotPhase.RESTING -> resting(snapshot, superset, tip)
            phase == SnapshotPhase.REST_OVER -> restOver(snapshot, superset)
            else -> logging(snapshot, superset)
        }.copy(chipText = chipText(snapshot, phase, moment, superset))
        return if (moment == null) card else withMoment(card, moment)
    }

    /** LA-05: the summary card of a finished workout. */
    fun finish(brief: FinishBrief): LiveUpdateModel {
        val stats = buildList {
            add("${brief.durationMinutes} min")
            add(if (brief.sets == 1) "1 set" else "${brief.sets} sets")
            add("${brief.volumeText} t")
            if (brief.personalRecordCount > 0) add(LiveText.records(brief.personalRecordCount))
        }
        return LiveUpdateModel(
            kind = LiveKind.FINISH,
            title = "${brief.workoutName} done",
            text = stats.joinToString(" · "),
            subText = if (brief.savedToHealth) "Saved to Health" else null,
            actions = listOf(
                LiveAction(LiveActionId.SHARE, "Share", LiveTarget.Share("${brief.workoutName}: ${stats.joinToString(", ")}")),
            ),
            accent = if (brief.personalRecordCount > 0) LiveAccent.GOLD else LiveAccent.GREEN,
            contentLink = DeepLinks.hub,
            ongoing = false,
            timeoutMillis = FINISH_LIFETIME_MILLIS,
        )
    }

    // ---------------------------------------------------------------------------------------------------------- phases

    private fun logging(snapshot: WorkoutSnapshot, superset: SupersetBrief?): LiveUpdateModel = LiveUpdateModel(
        kind = LiveKind.LOGGING,
        title = titleOf(snapshot),
        text = setLine(snapshot, superset),
        subText = snapshot.workoutName,
        overlayLines = overlayLines(snapshot, superset),
        detailLines = details(snapshot),
        clock = LiveClock.Elapsed(snapshot.activeStart.toEpochMilli()),
        progress = progressOf(snapshot),
        actions = logActions(snapshot, superset),
        accent = accentOf(superset),
    )

    private fun restOver(snapshot: WorkoutSnapshot, superset: SupersetBrief?): LiveUpdateModel = LiveUpdateModel(
        kind = LiveKind.REST_OVER,
        title = "Rest over · ${titleOf(snapshot)}",
        text = setLine(snapshot, superset),
        subText = snapshot.workoutName,
        overlayLines = overlayLines(snapshot, superset),
        detailLines = details(snapshot),
        clock = LiveClock.Elapsed(snapshot.activeStart.toEpochMilli()),
        progress = progressOf(snapshot),
        actions = logActions(snapshot, superset),
        accent = accentOf(superset),
    )

    private fun resting(snapshot: WorkoutSnapshot, superset: SupersetBrief?, tip: CoachTipBrief?): LiveUpdateModel {
        val next = NEXT_PREFIX + snapshot.nextSetText
        val end = snapshot.restEndsAt
        val restLine = if (snapshot.restTotalSeconds > 0) listOf("Rest · ${LiveText.clock(snapshot.restTotalSeconds)}") else emptyList()
        return LiveUpdateModel(
            kind = LiveKind.RESTING,
            title = "Rest · ${titleOf(snapshot)}",
            text = tip?.text ?: next,
            subText = snapshot.workoutName,
            overlayLines = overlayLines(snapshot, superset),
            detailLines = (if (tip == null) restLine else listOf(tip.subtitle, next)).filter { it.isNotBlank() } + details(snapshot),
            clock = if (end != null) LiveClock.Countdown(end.toEpochMilli()) else LiveClock.None,
            progress = progressOf(snapshot),
            actions = if (tip != null) tipActions(tip) else restActions(),
            accent = accentOf(superset),
        )
    }

    private fun paused(snapshot: WorkoutSnapshot, superset: SupersetBrief?): LiveUpdateModel {
        val frozenRest = snapshot.phase == SnapshotPhase.RESTING
        return LiveUpdateModel(
            kind = LiveKind.PAUSED,
            title = "Paused · ${titleOf(snapshot)}",
            text = if (frozenRest) "Rest paused · ${LiveText.clock(snapshot.restFrozenRemaining ?: 0)} left" else setLine(snapshot, superset),
            subText = "${snapshot.workoutName} · ${LiveText.clock(snapshot.elapsedWhenPaused)}",
            detailLines = details(snapshot),
            progress = progressOf(snapshot),
            actions = listOf(
                LiveAction(LiveActionId.RESUME, "Resume", LiveTarget.Command(WidgetCommand.of(WidgetCommands.RESUME))),
                finishAction(),
            ),
        )
    }

    private fun complete(snapshot: WorkoutSnapshot): LiveUpdateModel {
        val empty = snapshot.totalSets == 0
        return LiveUpdateModel(
            kind = LiveKind.COMPLETE,
            title = when {
                !empty -> "All sets logged"
                snapshot.exerciseCount == 0 -> "No exercises yet"
                else -> "No sets yet"
            },
            text = when {
                !empty -> LiveText.progress(snapshot)
                snapshot.exerciseCount == 0 -> "Add exercises in Pulse Strength"
                else -> "Add sets in Pulse Strength"
            },
            subText = snapshot.workoutName,
            detailLines = details(snapshot, withTotals = false),
            clock = LiveClock.Elapsed(snapshot.activeStart.toEpochMilli()),
            progress = progressOf(snapshot),
            actions = if (empty) emptyList() else listOf(finishAction()),
        )
    }

    // ----------------------------------------------------------------------------------------------------------- moments

    /** LA-01: the PR flash replaces title, text and chip for the few seconds until `expiresAt`; the card's own line moves to the details. */
    private fun withMoment(card: LiveUpdateModel, moment: PRMoment): LiveUpdateModel = card.copy(
        title = "New record: ${moment.exerciseName}",
        text = momentText(moment),
        detailLines = listOf(card.text) + card.detailLines,
        accent = LiveAccent.GOLD,
    )

    private fun momentText(moment: PRMoment): String = buildString {
        append("${moment.weightText} × ${moment.repsText}")
        if (moment.estimated1RM > 0) {
            append(" · e1RM ${moment.estimated1RM} kg")
            if (moment.deltaKg > 0) append(" (+${moment.deltaKg})")
        }
    }

    /** LA-07 ... LA-10: the status-bar chip. Null leaves the clock of the card (the rest countdown, or the elapsed time) in the chip. */
    private fun chipText(snapshot: WorkoutSnapshot, phase: SnapshotPhase, moment: PRMoment?, superset: SupersetBrief?): String? = when {
        moment != null -> "PR"
        snapshot.isPaused -> "Paused"
        phase == SnapshotPhase.RESTING -> null
        phase == SnapshotPhase.REST_OVER -> "Go"
        phase == SnapshotPhase.COMPLETE -> if (snapshot.totalSets == 0) null else "Done"
        superset != null -> supersetChip(superset)
        else -> snapshot.heartRate?.toString() ?: setDots(snapshot)
    }

    /** "A2 2/3"; without the tag when a long round count would not fit. */
    private fun supersetChip(superset: SupersetBrief): String {
        val rounds = "${superset.round}/${superset.rounds}"
        val tag = superset.currentTag() ?: return rounds
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

    // ------------------------------------------------------------------------------------------------------------ pieces

    /** The superset round is blue, like the current member's ring in the canvas. */
    private fun accentOf(superset: SupersetBrief?): LiveAccent = if (superset != null) LiveAccent.BLUE else LiveAccent.GREEN

    private fun titleOf(snapshot: WorkoutSnapshot): String = snapshot.exerciseName.ifBlank { snapshot.workoutName }

    /** "Set 4 of 5 · 82.5 kg × 6", or "Superset round 2/3 · 25 kg × 12" (the round is the set number of a superset). */
    private fun setLine(snapshot: WorkoutSnapshot, superset: SupersetBrief?): String =
        if (superset != null) "Superset round ${superset.round}/${superset.rounds} · ${LiveText.work(snapshot)}"
        else "${snapshot.setLabel} · ${LiveText.work(snapshot)}"

    /** LA-02 members and LA-03 plates: lines the progress style cannot show. */
    private fun overlayLines(snapshot: WorkoutSnapshot, superset: SupersetBrief?): List<String> =
        superset?.memberLines().orEmpty() + listOfNotNull(snapshot.plates?.let(::platesLine))

    private fun details(snapshot: WorkoutSnapshot, withTotals: Boolean = true): List<String> = listOfNotNull(
        if (withTotals && snapshot.totalSets > 0) LiveText.progress(snapshot) else null,
        snapshot.heartRate?.let { "Heart rate $it bpm" },
    )

    /** LA-03: "Per side: 20 + 10 + 2.5". */
    private fun platesLine(plates: PlateBrief): String {
        val loaded = plates.summary.ifBlank { plates.perSide.joinToString(" + ") { LiveText.kg(it) } }
        val line = "Per side: " + loaded.ifBlank { "bar only" }
        return if (plates.leftoverKg > 0) "$line · ${LiveText.kg(plates.leftoverKg)} kg short" else line
    }

    private fun SupersetBrief.memberLines(): List<String> = members.map { member ->
        val detail = if (member.detail.isBlank()) "" else " · ${member.detail}"
        val state = when {
            member.isCurrent -> " (now)"
            member.isDone -> " (done)"
            else -> ""
        }
        "${member.tag} ${member.name}$detail$state"
    }

    private fun SupersetBrief.currentTag(): String? = (members.firstOrNull { it.isCurrent } ?: members.firstOrNull { !it.isDone })?.tag

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

    // ----------------------------------------------------------------------------------------------------------- actions

    /** "Log set" ("Log A2" in a superset), then the weight (or reps, or time) stepper as "−" and "+". */
    private fun logActions(snapshot: WorkoutSnapshot, superset: SupersetBrief?): List<LiveAction> {
        val exerciseId = snapshot.targetExerciseID
        val setId = snapshot.targetSetID
        // The explicit set makes a late tap harmless: the set is logged once, whatever the card shows by then.
        val log = if (exerciseId != null && setId != null) {
            WidgetCommand.of(WidgetCommands.LOG_SET, WidgetCommands.ARG_EXERCISE_ID to exerciseId, WidgetCommands.ARG_SET_ID to setId)
        } else {
            WidgetCommand.of(WidgetCommands.LOG_NEXT_SET)
        }
        val weight = snapshot.tracking == TrackingKind.WEIGHT_REPS
        val noun = when (snapshot.tracking) {
            TrackingKind.WEIGHT_REPS -> "Weight"
            TrackingKind.REPS_ONLY -> "Reps"
            TrackingKind.DURATION -> "Time"
        }
        return listOf(
            LiveAction(LiveActionId.LOG_SET, superset?.currentTag()?.let { "Log $it" } ?: "Log set", LiveTarget.Command(log)),
            LiveAction(LiveActionId.NUDGE_DOWN, "− $noun", LiveTarget.Command(nudge(if (weight) -1 else 0, if (weight) 0 else -1))),
            LiveAction(LiveActionId.NUDGE_UP, "+ $noun", LiveTarget.Command(nudge(if (weight) 1 else 0, if (weight) 0 else 1))),
        )
    }

    private fun nudge(weightSteps: Int, repsSteps: Int): WidgetCommand = WidgetCommand.of(
        WidgetCommands.NUDGE,
        WidgetCommands.ARG_WEIGHT_STEPS to weightSteps.toString(),
        WidgetCommands.ARG_REPS_STEPS to repsSteps.toString(),
    )

    private fun restActions(): List<LiveAction> = listOf(
        LiveAction(LiveActionId.REST_DOWN, "−15 s", LiveTarget.Command(adjustRest(-15))),
        LiveAction(LiveActionId.REST_UP, "+15 s", LiveTarget.Command(adjustRest(15))),
        skipAction(),
    )

    /** LA-04: "82.5 kg" applies the suggestion, "Keep 80" only clears the tip. */
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
        skipAction(),
    )

    private fun adjustRest(seconds: Int): WidgetCommand =
        WidgetCommand.of(WidgetCommands.ADJUST_REST, WidgetCommands.ARG_SECONDS to seconds.toString())

    private fun skipAction(): LiveAction =
        LiveAction(LiveActionId.SKIP_REST, "Skip", LiveTarget.Command(WidgetCommand.of(WidgetCommands.SKIP_REST)))

    /** Finishing needs the confirmation of the app, so the button only opens the workout. */
    private fun finishAction(): LiveAction = LiveAction(LiveActionId.FINISH, "Finish", LiveTarget.Link(DeepLinks.workout))
}
