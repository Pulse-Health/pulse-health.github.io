package health.pulse.strength.core.widgets

import health.pulse.strength.core.CompletedWorkout
import health.pulse.strength.core.Estimated1RM
import health.pulse.strength.core.SetType
import health.pulse.strength.core.TrackingKind
import health.pulse.strength.core.addingTimeInterval
import java.time.Instant

/**
 * The lifts the user trains most, their estimated-1RM trends, plateaus and strength ratio
 * (widgets/SPEC.md section 2: lifts, plateaus, strengthRatio).
 */
internal object WidgetLifts {
    /** How far back a lift has to have been trained to be listed. */
    const val windowDays = 90

    /** Most lifts listed. */
    const val maximumLifts = 8

    /** Most sessions in a lift's trend. */
    const val maximumPoints = 6

    /** Plateaus listed. */
    const val maximumPlateaus = 4

    /** The tip on the first lift that went flat. */
    const val plateauTip = "Try 3 × 8 at about 90% for two weeks."

    /** One day of one lift: its best estimated 1RM of a workout (rounded to 0.1) and the day that workout belongs to. */
    class Session(val date: Instant, val day: Long, val value: Double)

    /** A listed lift with every session of the history, oldest first (the block uses them all, the trend only the last few). */
    class Series(val trend: LiftTrend, val sessions: List<Session>)

    private class Collected(var name: String, val sessions: MutableList<Session> = mutableListOf())

    // region Lifts

    /**
     * Up to 8 weight-tracking exercises that were trained in the last 90 days, most workouts first (then the most recent, then the
     * smaller id).
     *
     * A session is a workout with at least one set of the exercise that has an estimate above zero; its value is the greatest
     * `CompletedExercise.bestE1RM` of the exercise in that workout, or, when that is 0, the best Epley estimate of its non-warm-up
     * sets. `points` are the last 6 sessions of the whole history, oldest first, rounded to 0.1. `bestE1RM` is the best of those
     * points; `prIndex` marks it when it is later than the first point and beat every earlier one. `sessionCount` counts the sessions
     * of the last 90 days (a day count from `now`, no upper bound).
     */
    fun lifts(history: WidgetHistory): List<Series> {
        val byExercise = HashMap<String, Collected>()
        // Oldest first; a tie keeps the older position of the history (which is newest first).
        val ordered = history.entries.withIndex().sortedWith(
            compareBy<IndexedValue<WidgetHistory.Entry>> { it.value.workout.finishedAt }.thenByDescending { it.index },
        )
        for ((_, entry) in ordered) {
            val seen = HashSet<String>()
            for (exercise in entry.workout.exercises) {
                if (exercise.tracking != TrackingKind.WEIGHT_REPS) continue
                // The same exercise twice in one workout is one session.
                if (!seen.add(exercise.exerciseID)) continue
                val value = sessionValue(exercise.exerciseID, entry.workout)
                if (value <= 0) continue
                val item = byExercise.getOrPut(exercise.exerciseID) { Collected(exercise.name) }
                item.name = exercise.name
                item.sessions.add(Session(entry.workout.finishedAt, entry.day, WidgetText.tenth(value)))
            }
        }

        val cutoff = history.now.addingTimeInterval(-windowDays * 86_400.0)
        class Ranked(val id: String, val item: Collected, val recent: Int)
        val ranked = byExercise.mapNotNull { (id, item) ->
            val recent = item.sessions.count { !it.date.isBefore(cutoff) }
            if (recent > 0) Ranked(id, item, recent) else null
        }.sortedWith { lhs, rhs ->
            when {
                lhs.recent != rhs.recent -> rhs.recent.compareTo(lhs.recent)
                lhs.item.sessions.last().date != rhs.item.sessions.last().date ->
                    rhs.item.sessions.last().date.compareTo(lhs.item.sessions.last().date)
                else -> lhs.id.compareTo(rhs.id)
            }
        }
        return ranked.take(maximumLifts).map { Series(trend(it.id, it.item, it.recent), it.item.sessions.toList()) }
    }

    /** The value of one lift in one workout: the greatest recorded `bestE1RM` of the exercise, else the best Epley estimate of its non-warm-up sets. */
    private fun sessionValue(exerciseID: String, workout: CompletedWorkout): Double {
        val entries = workout.exercises.filter { it.exerciseID == exerciseID }
        val recorded = entries.maxOfOrNull { it.bestE1RM } ?: 0.0
        if (recorded > 0) return recorded
        var best = 0.0
        for (entry in entries) {
            for (set in entry.sets) {
                if (set.type == SetType.WARMUP) continue
                best = maxOf(best, Estimated1RM.epley(set.weightKg, set.reps))
            }
        }
        return best
    }

    private fun trend(id: String, item: Collected, recent: Int): LiftTrend {
        val points = item.sessions.takeLast(maximumPoints).map { TrendPoint(date = it.date, value = it.value) }
        val values = points.map { it.value }
        val best = values.maxOrNull() ?: 0.0
        val firstBest = values.indexOf(best)
        return LiftTrend(
            exerciseID = id,
            name = item.name,
            points = points,
            currentE1RM = values.lastOrNull() ?: 0.0,
            bestE1RM = best,
            prIndex = firstBest.takeIf { it > 0 },
            sessionCount = recent,
            deltaKg = if (values.size > 1) WidgetText.tenth(values[values.size - 1] - values[values.size - 2]) else 0.0,
        )
    }

    // endregion

    // region Plateaus

    /**
     * The first 4 lifts with at least 3 points, each as rising, flat or falling.
     *
     * `p` is the latest point that set a new best (strictly above every earlier point; the first point counts) and `flatSessions` is
     * `count - p`. With 3 or more of them and the last point within 3 % of the best the lift is flat; with 2 or more and the last
     * point more than 3 % below the best it is falling; otherwise it is rising. The first flat lift carries the tip.
     */
    fun plateaus(lifts: List<Series>): List<PlateauFlag> {
        val flags = ArrayList<PlateauFlag>()
        var tipGiven = false
        for (lift in lifts.map { it.trend }) {
            if (lift.points.size < 3) continue
            if (flags.size >= maximumPlateaus) break
            val values = lift.points.map { it.value }
            val best = values.max()
            var latestBest = 0
            var runningBest = Double.NEGATIVE_INFINITY
            for ((index, value) in values.withIndex()) {
                if (value > runningBest) {
                    runningBest = value
                    latestBest = index
                }
            }
            val flatSessions = values.size - latestBest
            val last = values.last()
            val status = when {
                flatSessions >= 3 && last >= 0.97 * best -> TrendStatus.FLAT
                flatSessions >= 2 && last < 0.97 * best -> TrendStatus.FALLING
                else -> TrendStatus.RISING
            }
            var tip: String? = null
            if (status == TrendStatus.FLAT && !tipGiven) {
                tip = plateauTip
                tipGiven = true
            }
            flags.add(PlateauFlag(exerciseID = lift.exerciseID, name = lift.name, status = status, flatSessions = flatSessions, tip = tip))
        }
        return flags
    }

    // endregion

    // region Strength ratio

    /** The main lifts and the bodyweight multiple the app suggests as a goal for each. */
    private val goalRatios: Map<String, Double> = mapOf("bench" to 1.5, "squat" to 2.0, "deadlift" to 2.5, "ohp" to 1.0)

    /**
     * The first listed lift that is bench press, squat, deadlift or overhead press against [bodyweightKg] (null when unknown or not
     * above zero): the best estimated 1RM, the ratio to the body weight rounded to 0.01 and the goal ratio of that lift.
     */
    fun strengthRatio(lifts: List<Series>, bodyweightKg: Double?): StrengthRatio? {
        val lift = lifts.map { it.trend }.firstOrNull { it.exerciseID in goalRatios } ?: return null
        val weight = bodyweightKg?.takeIf { it.isFinite() && it > 0 }
        return StrengthRatio(
            exerciseID = lift.exerciseID,
            exerciseName = lift.name,
            estimated1RM = lift.bestE1RM,
            bodyweightKg = weight,
            ratio = weight?.let { WidgetText.hundredth(lift.bestE1RM / it) },
            goalRatio = goalRatios[lift.exerciseID] ?: 1.5,
        )
    }

    // endregion
}
