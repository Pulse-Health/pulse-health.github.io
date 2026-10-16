package health.pulse.strength.core.widgets

import health.pulse.strength.core.CompletedWorkout
import health.pulse.strength.core.WorkoutTemplate

/**
 * The derived 4-week training block of the iPad and tablet widgets (widgets/SPEC.md section 2: block). The app has no block concept:
 * blocks are counted in four-week steps from the week of the first workout ever finished.
 */
internal object WidgetBlock {
    /** Weeks in a block. */
    const val weeks = 4

    /**
     * The block that contains the current week; null without history.
     *
     * The anchor is the Monday of the week of the earliest workout and `n` the whole weeks from it to this week's Monday (never below
     * 0). The block is number `n / 4 + 1` and this is its week `n % 4 + 1`. Its rows are the first four templates in store order, one
     * cell per week of the block: a week after the current one is `upcoming`; an earlier or current week is `done` when a workout of
     * that template finished in it (matched by `templateID`, or by name for a workout that has none), else `planned` for the current
     * week and `missed` for an earlier one. `sessionsDone` counts the workouts since the block began, `sessionsPlanned` is the goal
     * times the weeks so far. The lift is the first of [lifts]: how its value changed from the last session before the block (its
     * first session inside it when it had none before) to its latest, null for a lift with fewer than two sessions.
     */
    fun block(history: WidgetHistory, templates: List<WorkoutTemplate>, goal: Int, lifts: List<WidgetLifts.Series>): TrainingBlock? {
        val earliest = history.entries.minOfOrNull { it.day } ?: return null
        val anchor = WidgetCalendar.mondayOnOrBefore(earliest)
        val elapsed = maxOf(0L, (history.weekStart - anchor) / 7)
        val weekIndex = (elapsed % weeks).toInt() + 1
        val blockStart = anchor + (elapsed / weeks) * weeks * 7

        val rows = templates.take(4).map { template ->
            val cells = (1..weeks).map { week ->
                if (week > weekIndex) return@map BlockCell(BlockCellState.UPCOMING)
                val start = blockStart + (week - 1) * 7
                val done = history.inDays(start until start + 7).any { belongs(it.workout, template) }
                when {
                    done -> BlockCell(BlockCellState.DONE)
                    week == weekIndex -> BlockCell(BlockCellState.PLANNED)
                    else -> BlockCell(BlockCellState.MISSED)
                }
            }
            BlockRow(label = WidgetText.rowLabel(template.name), cells = cells)
        }
        val missed = rows.sumOf { row -> row.cells.count { it.state == BlockCellState.MISSED } }
        val change = liftChange(lifts.firstOrNull(), blockStart)
        return TrainingBlock(
            name = "Block ${elapsed / weeks + 1}",
            weekIndex = weekIndex,
            weekCount = weeks,
            rows = rows,
            sessionsDone = history.entries.count { it.day >= blockStart },
            sessionsPlanned = goal * weekIndex,
            sessionsMissed = missed,
            liftName = if (change == null) null else lifts.first().trend.name,
            liftDeltaKg = change,
        )
    }

    /** True when [workout] is a workout of [template]: the same `templateID`, or the same name for a workout without one. */
    private fun belongs(workout: CompletedWorkout, template: WorkoutTemplate): Boolean {
        val templateID = workout.templateID ?: return workout.name == template.name
        return templateID == template.id
    }

    /** The change of the lift's value from the baseline to its latest session, rounded to 0.1; null with fewer than two sessions. */
    private fun liftChange(lift: WidgetLifts.Series?, blockStart: Long): Double? {
        if (lift == null || lift.sessions.size < 2) return null
        val latest = lift.sessions.last()
        val baseline = lift.sessions.lastOrNull { it.day < blockStart } ?: lift.sessions.firstOrNull { it.day >= blockStart } ?: return null
        return WidgetText.tenth(latest.value - baseline.value)
    }
}
