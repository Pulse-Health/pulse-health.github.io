package health.pulse.strength.core

// region Estimated one-rep max

/** Estimated one-rep max formulas. */
object Estimated1RM {
    /** Epley estimate `kg * (1 + reps / 30)`; 0 when the weight or the reps are zero or negative. */
    fun epley(weightKg: Double, reps: Int): Double {
        if (!(weightKg > 0 && weightKg.isFinite() && reps > 0)) return 0.0
        return weightKg * (1 + reps.toDouble() / 30)
    }
}

// endregion

// region Plate calculator

/** The plates to load on each side of the bar, heaviest first, and the weight that cannot be matched. */
data class PlatePlan(
    /** Plates for one side of the bar, heaviest first, in kilograms. */
    val perSide: List<Double>,
    /** Weight per side that the available plates cannot make up, rounded to 0.01 kg. */
    val leftoverKg: Double,
)

/** Works out which plates to load on a barbell. */
object PlateCalculator {
    /** The plate sizes in kilograms that are on offer, heaviest first. */
    val availablePlates: List<Double> = listOf(25.0, 20.0, 15.0, 10.0, 5.0, 2.5, 1.25)

    /** Heaviest total weight the calculator plans for; anything above is treated as invalid input. */
    private const val maximumTotalKg = 100_000.0

    /**
     * Greedy plate plan for one side of the bar, or null when [totalKg] is below [barKg] (or an input is invalid).
     *
     * The leftover is the per-side weight the plates cannot make up (rounded to 0.01 kg), for example 0.5 kg for 21 kg on a 20 kg bar.
     */
    fun plan(totalKg: Double, barKg: Double): PlatePlan? {
        if (!(totalKg.isFinite() && barKg.isFinite() && barKg >= 0 && totalKg <= maximumTotalKg)) return null
        var remaining = (totalKg - barKg) / 2
        if (remaining < -0.001) return null
        val plates = mutableListOf<Double>()
        for (plate in availablePlates) {
            while (remaining + 0.0001 >= plate) {
                plates.add(plate)
                remaining -= plate
            }
        }
        val leftover = if (remaining > 0) remaining else 0.0
        return PlatePlan(perSide = plates, leftoverKg = (leftover * 100).roundedAwayFromZero() / 100)
    }
}

// endregion

// region Number text

/** Locale independent number and time text, formatted by hand so the output is identical on every platform. */
object NumberText {
    /** Largest magnitude (in the unit being formatted) that is converted to an integer; larger values clamp. */
    private const val integerLimit = 9_000_000_000_000_000.0

    /**
     * Kilograms with at most two decimals and no trailing zeros: 82.5 gives "82.5", 80 gives "80", 82.50001 gives "82.5".
     *
     * Ties round away from zero, a result of zero never carries a sign, and a non-finite value gives "0".
     */
    fun kg(value: Double): String {
        val hundredths = roundedInteger(value * 100) ?: return "0"
        if (hundredths == 0L) return "0"
        val magnitude = if (hundredths < 0) -hundredths else hundredths
        val whole = magnitude / 100
        val fraction = magnitude % 100
        val text = StringBuilder()
        if (hundredths < 0) text.append('-')
        text.append(whole)
        if (fraction % 10 == 0L) {
            if (fraction != 0L) text.append('.').append(fraction / 10)
        } else if (fraction < 10) {
            text.append(".0").append(fraction)
        } else {
            text.append('.').append(fraction)
        }
        return text.toString()
    }

    /** A value rounded to a whole number with "," grouping: 1980.4 gives "1,980" and 1979.5 gives "1,980". */
    fun thousands(value: Double): String {
        val rounded = roundedInteger(value)
        if (rounded == null || rounded == 0L) return "0"
        val digits = (if (rounded < 0) -rounded else rounded).toString()
        val text = StringBuilder()
        if (rounded < 0) text.append('-')
        for ((index, digit) in digits.withIndex()) {
            if (index > 0 && (digits.length - index) % 3 == 0) text.append(',')
            text.append(digit)
        }
        return text.toString()
    }

    /** An elapsed time as "m:ss", or "h:mm:ss" from one hour on: 72 gives "1:12" and 3723 gives "1:02:03". Negative counts as zero. */
    fun clock(seconds: Int): String {
        val total = maxOf(0, seconds)
        val hours = total / 3600
        val minutes = (total % 3600) / 60
        val secs = total % 60
        if (hours > 0) return "$hours:${twoDigits(minutes)}:${twoDigits(secs)}"
        return "$minutes:${twoDigits(secs)}"
    }

    /** A rest time as "m:ss" (minutes are not wrapped into hours), or "Off" when there is none: 0 gives "Off" and 150 gives "2:30". */
    fun rest(seconds: Int): String {
        if (seconds <= 0) return "Off"
        return "${seconds / 60}:${twoDigits(seconds % 60)}"
    }

    /** Rounds half away from zero; null for NaN or infinity, clamped to +/- [integerLimit] beyond that. */
    private fun roundedInteger(value: Double): Long? {
        if (!value.isFinite()) return null
        val rounded = value.roundedAwayFromZero()
        if (rounded >= integerLimit) return integerLimit.toLong()
        if (rounded <= -integerLimit) return -integerLimit.toLong()
        return rounded.toLong()
    }

    private fun twoDigits(value: Int): String = if (value < 10) "0$value" else value.toString()
}

// endregion
