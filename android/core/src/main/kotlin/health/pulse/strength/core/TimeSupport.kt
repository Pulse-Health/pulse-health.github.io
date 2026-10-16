package health.pulse.strength.core

import java.time.Duration
import java.time.Instant
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.floor

// Small helpers that give java.time and Double the behaviour the workout rules were written against
// (Foundation's Date arithmetic and its rounding modes), so the Kotlin port matches the Swift core number for number.

/** Seconds from [other] to this instant, negative when this instant is earlier (Foundation `timeIntervalSince`). */
fun Instant.timeIntervalSince(other: Instant): Double {
    val duration = Duration.between(other, this)
    return duration.seconds.toDouble() + duration.nano / 1_000_000_000.0
}

/** This instant moved by [seconds] (Foundation `addingTimeInterval`); a fractional value keeps its sub-second part. */
fun Instant.addingTimeInterval(seconds: Double): Instant {
    if (!seconds.isFinite()) return this
    val whole = floor(seconds)
    val nanos = ((seconds - whole) * 1_000_000_000.0).toLong()
    return plusSeconds(whole.toLong()).plusNanos(nanos)
}

/** Rounds half away from zero (Swift `rounded()` / `.toNearestOrAwayFromZero`); NaN and infinity are returned unchanged. */
fun Double.roundedAwayFromZero(): Double {
    if (!isFinite()) return this
    val magnitude = abs(this)
    val base = floor(magnitude)
    val rounded = if (magnitude - base >= 0.5) base + 1.0 else base
    return if (this < 0) -rounded else rounded
}

/** Rounds toward negative infinity (Swift `rounded(.down)`). */
fun Double.roundedDown(): Double = floor(this)

/** Rounds toward positive infinity (Swift `rounded(.up)`). */
fun Double.roundedUp(): Double = ceil(this)
