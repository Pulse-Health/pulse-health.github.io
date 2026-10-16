package health.pulse.strength.core

import java.util.UUID

/**
 * Everything the active-workout screen needs, derived from a [WorkoutState] by
 * `WorkoutPresenter.present(state, now, recovery)`. Views render this and never recompute it.
 * All strings are display-ready (locale independent: "." decimal, "," thousands).
 */
data class ActiveWorkoutPresentation(
    val header: Header,
    val navigator: Navigator? = null,
    val card: Card? = null,
    val dock: Dock? = null,
    /** Undo snackbar text ("Removed Cable crossover") while an undo entry is still valid. */
    val undoText: String? = null,
    val isEmpty: Boolean,
    val totals: Totals,
    val finishCheck: FinishCheck,
) {
    data class Segment(
        /** 0...1 share of this exercise's sets that are logged. */
        val fraction: Double,
        val isCurrent: Boolean,
    )

    data class Header(
        val title: String,
        /** "24:18", "1:02:03" or, when paused, "Paused · 24:18". */
        val clockText: String,
        val isPaused: Boolean,
        /** Logged volume without the unit, e.g. "1,980" (warm-up sets excluded). */
        val volumeText: String,
        /** "7 of 19" */
        val setsText: String,
        /** "128" or "–" when unknown. */
        val heartRateText: String,
        val hasHeartRate: Boolean,
        val segments: List<Segment>,
    )

    data class Navigator(
        /** 1-based. */
        val position: Int,
        val total: Int,
        val canGoPrevious: Boolean,
        val canGoNext: Boolean,
    )

    enum class RecoveryLevel {
        /** >= 80 % */
        GOOD,

        /** 60...79 % */
        FAIR,

        /** < 60 % */
        LOW,
    }

    data class SetRow(
        val id: UUID,
        /** "1", "2", ... for normal sets (numbered in order), "W", "D" or "F". */
        val number: String,
        val type: SetType,
        /** "80 × 6", "8 reps", "45 s" or "–". */
        val previousText: String,
        /** "82.5", "BW" (repsOnly) or "–" (duration). */
        val weightText: String,
        /** Reps or seconds as text. */
        val repsText: String,
        val weightEditable: Boolean,
        val isDone: Boolean,
        /** The first pending set of the current exercise (highlighted). */
        val isNext: Boolean,
        val isPersonalRecord: Boolean,
        val estimated1RM: Int? = null,
        val rir: Int? = null,
        /** "RIR 3" / "RIR 4+" when recorded on a done set. */
        val rirText: String? = null,
        val accessibilityLabel: String,
    )

    data class Card(
        val exerciseID: UUID,
        val exercise: Exercise,
        val recoveryPercent: Int,
        val recoveryLevel: RecoveryLevel,
        /** "Superset A" or null. */
        val supersetLabel: String? = null,
        val restSeconds: Int,
        /** "2:30" or "Off". */
        val restText: String,
        val note: String,
        /** "kg", "Added" (repsOnly) or "" (duration). */
        val weightColumnTitle: String,
        /** "Reps" or "Sec". */
        val repsColumnTitle: String,
        /** Coach suggestion shown while no rest timer is running (null otherwise). */
        val coachTip: String? = null,
        val rows: List<SetRow>,
    )

    enum class DockPhase { RUNNING, FINISHED }

    data class Dock(
        val phase: DockPhase,
        val remainingSeconds: Int,
        val totalSeconds: Int,
        /** Remaining / total (1 when finished), clamped 0...1. */
        val fraction: Double,
        /** "1:12", or "Go" when finished. */
        val remainingText: String,
        /** "Next · Set 4 · 82.5 kg × 6" or "All sets logged". */
        val nextSetText: String,
        /** Shows the "Reps left" selector (last logged set exists, is done and is not a warm-up). */
        val showsRIR: Boolean,
        val rirSelection: Int? = null,
        val isPaused: Boolean,
    )

    data class Totals(
        val loggedSets: Int,
        val totalSets: Int,
        val volumeKg: Double,
        val completedExercises: Int,
    )

    data class FinishCheck(
        val loggedSets: Int,
        val unloggedSets: Int,
        /** Nothing logged: only "Keep training" / "Discard" make sense. */
        val canFinish: Boolean,
        val title: String,
        val message: String,
        val templateDiff: TemplateDiff,
        /** "Changes: 1 added, 1 removed." (or "none"). */
        val diffMessage: String,
        /** Offer "Update template?" after finishing. */
        val asksToUpdateTemplate: Boolean,
    )
}

/** What changed relative to the template the workout was started from. */
@kotlinx.serialization.Serializable
data class TemplateDiff(
    val added: Int = 0,
    val removed: Int = 0,
    val reordered: Boolean = false,
) {
    val isEmpty: Boolean get() = added == 0 && removed == 0 && !reordered

    /** "1 added, 1 removed, new order" ("none" when empty). */
    val summary: String
        get() {
            val parts = mutableListOf<String>()
            if (added > 0) parts.add("$added added")
            if (removed > 0) parts.add("$removed removed")
            if (reordered) parts.add("new order")
            return if (parts.isEmpty()) "none" else parts.joinToString(", ")
        }

    companion object {
        /**
         * What changed in [state] relative to the template it was started from (added, removed and reordered exercises).
         *
         * An exercise counts as added when it has no template entry, its entry is not in the baseline, or another exercise
         * already claims that entry; a baseline entry counts as removed when no exercise refers to it; the exercises that
         * remain are reordered when their relative order differs from the baseline.
         */
        fun compute(state: WorkoutState): TemplateDiff {
            val baseline = state.templateBaseline
            val baselineSet = baseline.toSet()

            val claimed = mutableSetOf<UUID>()
            var added = 0
            val common = mutableListOf<UUID>()
            for (entry in state.exercises) {
                val entryID = entry.templateEntryID
                if (entryID != null && entryID in baselineSet && entryID !in claimed) {
                    claimed.add(entryID)
                    common.add(entryID)
                } else {
                    added += 1
                }
            }

            val removed = baseline.count { it !in claimed }
            val baselineCommon = baseline.filter { it in claimed }
            return TemplateDiff(added = added, removed = removed, reordered = common != baselineCommon)
        }
    }
}

/** Muscle recovery lookup (percent 0...100). The Pulse app injects its real model; this is the demo data. */
typealias RecoveryProvider = (MuscleGroup) -> Int

object DemoRecovery {
    val provider: RecoveryProvider = { muscle ->
        when (muscle) {
            MuscleGroup.CHEST -> 88
            MuscleGroup.BACK -> 100
            MuscleGroup.SHOULDERS -> 82
            MuscleGroup.ARMS -> 79
            MuscleGroup.LEGS -> 64
            MuscleGroup.CORE -> 100
        }
    }
}
