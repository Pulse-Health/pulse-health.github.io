package health.pulse.strength.wear.tiles

import androidx.wear.protolayout.LayoutElementBuilders
import androidx.wear.protolayout.TypeBuilders
import androidx.wear.protolayout.expression.DynamicBuilders
import androidx.wear.protolayout.expression.DynamicBuilders.DynamicInt32.IntFormatter
import androidx.wear.protolayout.expression.DynamicBuilders.DynamicInstant
import androidx.wear.protolayout.expression.DynamicBuilders.DynamicString
import health.pulse.strength.wear.model.WearText
import java.time.Instant
import java.time.temporal.ChronoUnit

/**
 * A rest countdown the tile renderer keeps ticking by itself, from the platform clock and the end time (ProtoLayout dynamic types), so the
 * service does not have to be asked every second. Every dynamic value carries a static fallback computed when the layout was made, which
 * is what a renderer without dynamic support shows until the next refresh.
 */
internal object RestCountdown {
    /** Reserves the width of the widest countdown so the digits ticking over do not move the layout. */
    private const val WIDEST = "00:00"

    /** The end of the rest, rounded up to a whole second like the visible countdown. */
    private fun wholeSecond(endsAt: Instant): Instant {
        val truncated = endsAt.truncatedTo(ChronoUnit.SECONDS)
        return if (truncated.isBefore(endsAt)) truncated.plusSeconds(1) else truncated
    }

    private fun remaining(endsAt: Instant): DynamicBuilders.DynamicDuration =
        DynamicInstant.platformTimeWithSecondsPrecision().durationUntil(DynamicInstant.withSecondsPrecision(wholeSecond(endsAt)))

    /** "1:24" counting down to [endsAt]; [fallbackSeconds] is the remaining time when the layout was made. */
    fun text(endsAt: Instant, fallbackSeconds: Int): TypeBuilders.StringProp {
        val remaining = remaining(endsAt)
        val twoDigits = IntFormatter.Builder().setMinIntegerDigits(2).build()
        val dynamic = remaining.toIntMinutes().format()
            .concat(DynamicString.constant(":"))
            .concat(remaining.getSecondsPart().format(twoDigits))
        return TypeBuilders.StringProp.Builder(WearText.clock(fallbackSeconds)).setDynamicValue(dynamic).build()
    }

    /** The share of the rest that is still to come, 1 at the start and 0 at [endsAt]. */
    fun remainingFraction(endsAt: Instant, totalSeconds: Int, fallbackFraction: Float): TypeBuilders.FloatProp {
        val seconds = remaining(endsAt).toIntSeconds().asFloat()
        val dynamic = seconds.div(totalSeconds.coerceAtLeast(1).toFloat())
        return TypeBuilders.FloatProp.Builder(fallbackFraction).setDynamicValue(dynamic).build()
    }

    fun widthConstraint(): TypeBuilders.StringLayoutConstraint =
        TypeBuilders.StringLayoutConstraint.Builder(WIDEST).setAlignment(LayoutElementBuilders.TEXT_ALIGN_CENTER).build()
}
