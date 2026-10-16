package health.pulse.strength.widgets.lock

import kotlin.math.abs
import kotlin.math.floor
import kotlin.math.pow

/**
 * Hand-formatted English text shared by the lock and extras widgets (the counterpart of the iOS `WidgetText` and `NumberText`). Nothing
 * here depends on the device locale, so a German phone still shows "82.5 kg" and "1.24".
 */
internal object PulseFormat {
    /** [value] rounded half away from zero to at most [maxDecimals] places and written without trailing zeros: 82.5 gives "82.5", 80.0 gives "80". */
    fun number(value: Double, maxDecimals: Int = 2): String {
        if (!value.isFinite()) return "0"
        val units = scaledUnits(value, maxDecimals)
        if (units == 0L) return "0"
        val divisor = 10.0.pow(maxDecimals).toLong()
        val fraction = (units % divisor).toString().padStart(maxDecimals, '0').trimEnd('0')
        val sign = if (value < 0) "-" else ""
        return sign + (units / divisor) + if (fraction.isEmpty()) "" else ".$fraction"
    }

    /** [value] rounded half away from zero to exactly [decimals] places: 1.2 gives "1.20". */
    fun fixed(value: Double, decimals: Int = 2): String {
        if (!value.isFinite()) return "0"
        val units = scaledUnits(value, decimals)
        val sign = if (value < 0 && units != 0L) "-" else ""
        if (decimals == 0) return sign + units
        val divisor = 10.0.pow(decimals).toLong()
        return sign + (units / divisor) + "." + (units % divisor).toString().padStart(decimals, '0')
    }

    /** |[value]| × 10^[decimals], rounded half away from zero (so 0.5 gives 1 and 0.49999999999999994 gives 0). */
    private fun scaledUnits(value: Double, decimals: Int): Long {
        val scaled = abs(value) * 10.0.pow(decimals)
        val whole = floor(scaled)
        return (if (scaled - whole >= 0.5) whole + 1 else whole).toLong()
    }

    /** "82.5", "80": kilograms with at most two decimals. */
    fun kg(value: Double): String = number(value, 2)

    /** "99.2": a computed weight (an estimated one-rep max) with at most one decimal, not the two decimals a plate load can need. */
    fun estimate(value: Double): String = number(value, 1)

    /** "+2.5", "−3" (a real minus sign) or "0" for a change too small to show at [maxDecimals] places. */
    fun signed(value: Double, maxDecimals: Int = 2): String {
        val text = number(abs(value), maxDecimals)
        if (text == "0") return "0"
        return (if (value > 0) "+" else "−") + text
    }

    /** "85 × 5". */
    fun weightReps(weightKg: Double, reps: Int): String = kg(weightKg) + " × " + reps

    /** "~55 min". */
    fun minutes(minutes: Int): String = "~$minutes min"

    /** "6 exercises", "1 exercise". */
    fun exercises(count: Int): String = if (count == 1) "1 exercise" else "$count exercises"

    /** "5d", or an en dash when there is nothing to count. */
    fun daysShort(days: Int?): String = if (days == null) "–" else "${maxOf(0, days)}d"

    /** "Never", "Today", "Yesterday", "5 days ago". */
    fun daysAgo(days: Int?): String = when {
        days == null -> "Never"
        days <= 0 -> "Today"
        days == 1 -> "Yesterday"
        else -> "$days days ago"
    }

    /** "1:12", and "1:02:03" from one hour on. */
    fun clock(seconds: Int): String {
        val total = maxOf(0, seconds)
        val hours = total / 3600
        val minutes = total % 3600 / 60
        val rest = (total % 60).toString().padStart(2, '0')
        return if (hours > 0) "$hours:${minutes.toString().padStart(2, '0')}:$rest" else "$minutes:$rest"
    }
}
