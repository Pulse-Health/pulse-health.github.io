package health.pulse.strength.controls

import health.pulse.strength.core.SnapshotPhase
import health.pulse.strength.core.WorkoutSnapshot
import health.pulse.strength.core.widgets.DeepLinks
import health.pulse.strength.core.widgets.WidgetCommand
import health.pulse.strength.core.widgets.WidgetCommands
import health.pulse.strength.core.widgets.WidgetSnapshot
import health.pulse.strength.live.LiveText
import health.pulse.strength.live.displayPhase
import health.pulse.strength.live.restRemainingSeconds
import java.time.Instant

/** CT-01 ... CT-08: the Quick Settings tiles. */
enum class Control { START_NEXT, LOG_SET, REST, ADD_REST, PLATES, PAUSE, FINISH, NEXT_UP }

/** The three looks of a tile: highlighted (something to do now), normal, and greyed out and not clickable (nothing to do). */
internal enum class TileStatus { ACTIVE, INACTIVE, UNAVAILABLE }

internal enum class TileIcon { START, LOG, REST, ADD_REST, PLATES, PAUSE, RESUME, FINISH, NEXT_UP }

/** What a click does. */
internal sealed interface TileAction {
    data object None : TileAction

    /** Runs a command through `StrengthRuntime.commands`; the tile stays closed and updates itself. */
    data class Command(val command: WidgetCommand) : TileAction

    /** Collapses the panel and opens the app on a `pulse-strength://` link. */
    data class Link(val url: String) : TileAction

    /** Collapses the panel and opens bench mode. */
    data object OpenBench : TileAction
}

/**
 * What one tile shows and does, as plain data.
 *
 * @property stateDescription spoken state of the toggle (Android 11 and later); null for tiles that are no toggle.
 */
internal data class TileModel(
    val control: Control,
    val label: String,
    val subtitle: String?,
    val status: TileStatus,
    val icon: TileIcon,
    val action: TileAction,
    val stateDescription: String? = null,
) {
    /** What TalkBack says: the label and the subtitle, which is the value (a toggle says its state instead). */
    val contentDescription: String get() = if (subtitle == null || stateDescription != null) label else "$label, $subtitle"
}

/** The state of every tile as a function of the snapshot (unit-tested; the tile services only draw it). */
internal object TileModels {
    fun of(control: Control, snapshot: WidgetSnapshot, now: Instant): TileModel {
        val active = snapshot.active
        return when (control) {
            Control.START_NEXT -> startNext(snapshot, active)
            Control.LOG_SET -> logSet(active, now)
            Control.REST -> rest(active, now)
            Control.ADD_REST -> addRest(active, now)
            Control.PLATES -> plates(active)
            Control.PAUSE -> pause(active)
            Control.FINISH -> finish(active, now)
            Control.NEXT_UP -> nextUp(snapshot, active)
        }
    }

    /** CT-01: starts the next workout (the app opens on it); while one runs the tile opens that workout instead. */
    private fun startNext(snapshot: WidgetSnapshot, active: WorkoutSnapshot?): TileModel {
        val nextUp = snapshot.nextUp
        return when {
            active != null -> TileModel(Control.START_NEXT, "Start workout", "In progress · open", TileStatus.INACTIVE, TileIcon.START, TileAction.Link(DeepLinks.workout))
            nextUp != null -> TileModel(Control.START_NEXT, "Start workout", nextUp.name, TileStatus.ACTIVE, TileIcon.START, TileAction.Link(DeepLinks.startNext))
            else -> TileModel(Control.START_NEXT, "Start workout", "No template yet", TileStatus.UNAVAILABLE, TileIcon.START, TileAction.None)
        }
    }

    /** CT-02: logs the next pending set. */
    private fun logSet(active: WorkoutSnapshot?, now: Instant): TileModel {
        val unavailable = { why: String -> TileModel(Control.LOG_SET, "Log set", why, TileStatus.UNAVAILABLE, TileIcon.LOG, TileAction.None) }
        if (active == null) return unavailable("No workout")
        if (active.isPaused) return unavailable("Paused")
        if (active.displayPhase(now) == SnapshotPhase.COMPLETE) return unavailable(if (active.totalSets == 0) "No sets yet" else "All sets logged")
        return TileModel(
            Control.LOG_SET,
            "Log set",
            active.nextSetText,
            TileStatus.ACTIVE,
            TileIcon.LOG,
            TileAction.Command(WidgetCommand.of(WidgetCommands.LOG_NEXT_SET)),
        )
    }

    /** CT-03: the rest countdown as the value; a click opens bench mode, the big rest timer. */
    private fun rest(active: WorkoutSnapshot?, now: Instant): TileModel {
        val unavailable = { why: String -> TileModel(Control.REST, "Rest", why, TileStatus.UNAVAILABLE, TileIcon.REST, TileAction.None) }
        if (active == null) return unavailable("No workout")
        if (active.isPaused) {
            return if (active.phase == SnapshotPhase.RESTING) {
                TileModel(Control.REST, "Rest", "${LiveText.clock(active.restRemainingSeconds(now))} · paused", TileStatus.INACTIVE, TileIcon.REST, TileAction.OpenBench)
            } else {
                unavailable("Paused")
            }
        }
        return when (active.displayPhase(now)) {
            SnapshotPhase.RESTING ->
                TileModel(Control.REST, "Rest", LiveText.clock(active.restRemainingSeconds(now)), TileStatus.ACTIVE, TileIcon.REST, TileAction.OpenBench)
            SnapshotPhase.REST_OVER ->
                TileModel(Control.REST, "Rest", "Go", TileStatus.ACTIVE, TileIcon.REST, TileAction.OpenBench)
            else -> unavailable("Not resting")
        }
    }

    /** CT-04: +30 s on the running rest. */
    private fun addRest(active: WorkoutSnapshot?, now: Instant): TileModel {
        val unavailable = { why: String -> TileModel(Control.ADD_REST, "+30 s rest", why, TileStatus.UNAVAILABLE, TileIcon.ADD_REST, TileAction.None) }
        if (active == null) return unavailable("No workout")
        if (active.isPaused || active.displayPhase(now) != SnapshotPhase.RESTING) return unavailable("Not resting")
        return TileModel(
            Control.ADD_REST,
            "+30 s rest",
            null,
            TileStatus.ACTIVE,
            TileIcon.ADD_REST,
            TileAction.Command(WidgetCommand.of(WidgetCommands.ADJUST_REST, WidgetCommands.ARG_SECONDS to "30")),
        )
    }

    /** CT-05: the plate calculator; with a barbell set pending the tile shows the plates for it. */
    private fun plates(active: WorkoutSnapshot?): TileModel {
        val summary = active?.plates?.let { it.summary.ifBlank { null } }
        return TileModel(
            Control.PLATES,
            "Plates",
            if (summary != null) "$summary per side" else "Calculator",
            if (summary != null) TileStatus.ACTIVE else TileStatus.INACTIVE,
            TileIcon.PLATES,
            TileAction.Link(DeepLinks.plates),
        )
    }

    /** CT-06: a toggle that is on while the workout is paused. */
    private fun pause(active: WorkoutSnapshot?): TileModel {
        if (active == null) {
            return TileModel(Control.PAUSE, "Pause workout", "No workout", TileStatus.UNAVAILABLE, TileIcon.PAUSE, TileAction.None, stateDescription = "Off")
        }
        return if (active.isPaused) {
            TileModel(
                Control.PAUSE,
                "Resume workout",
                "Paused · ${LiveText.clock(active.elapsedWhenPaused)}",
                TileStatus.ACTIVE,
                TileIcon.RESUME,
                TileAction.Command(WidgetCommand.of(WidgetCommands.RESUME)),
                stateDescription = "Paused",
            )
        } else {
            TileModel(
                Control.PAUSE,
                "Pause workout",
                "Running",
                TileStatus.INACTIVE,
                TileIcon.PAUSE,
                TileAction.Command(WidgetCommand.of(WidgetCommands.PAUSE)),
                stateDescription = "Running",
            )
        }
    }

    /** CT-07: finishing needs the confirmation of the app, so the tile opens the workout; it is highlighted once every set is logged. */
    private fun finish(active: WorkoutSnapshot?, now: Instant): TileModel {
        if (active == null) {
            return TileModel(Control.FINISH, "Finish workout", "No workout", TileStatus.UNAVAILABLE, TileIcon.FINISH, TileAction.None)
        }
        val complete = active.displayPhase(now) == SnapshotPhase.COMPLETE && active.totalSets > 0
        return TileModel(
            Control.FINISH,
            "Finish workout",
            if (complete) "All sets logged" else "${active.loggedSets} of ${active.totalSets} sets",
            if (complete) TileStatus.ACTIVE else TileStatus.INACTIVE,
            TileIcon.FINISH,
            TileAction.Link(DeepLinks.workout),
        )
    }

    /** CT-08: the label is the split ("Push day"); a click starts it, or opens the running workout. */
    private fun nextUp(snapshot: WidgetSnapshot, active: WorkoutSnapshot?): TileModel {
        val nextUp = snapshot.nextUp ?: return TileModel(Control.NEXT_UP, "Next up", "No template yet", TileStatus.UNAVAILABLE, TileIcon.NEXT_UP, TileAction.None)
        val size = buildList {
            if (nextUp.exerciseCount > 0) add(if (nextUp.exerciseCount == 1) "1 exercise" else "${nextUp.exerciseCount} exercises")
            if (nextUp.estimatedMinutes > 0) add("~${nextUp.estimatedMinutes} min")
        }.joinToString(" · ").ifBlank { nextUp.name }
        return if (active != null) {
            TileModel(Control.NEXT_UP, nextUp.splitLabel, "Workout running · open", TileStatus.INACTIVE, TileIcon.NEXT_UP, TileAction.Link(DeepLinks.workout))
        } else {
            TileModel(Control.NEXT_UP, nextUp.splitLabel, size, TileStatus.ACTIVE, TileIcon.NEXT_UP, TileAction.Link(DeepLinks.startNext))
        }
    }
}
