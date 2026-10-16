package health.pulse.strength.wear.complications

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.drawable.Icon
import androidx.wear.protolayout.expression.DynamicBuilders.DynamicFloat
import androidx.wear.protolayout.expression.DynamicBuilders.DynamicInstant
import androidx.wear.watchface.complications.data.ComplicationData
import androidx.wear.watchface.complications.data.ComplicationText
import androidx.wear.watchface.complications.data.ComplicationType
import androidx.wear.watchface.complications.data.CountDownTimeReference
import androidx.wear.watchface.complications.data.LongTextComplicationData
import androidx.wear.watchface.complications.data.MonochromaticImage
import androidx.wear.watchface.complications.data.MonochromaticImageComplicationData
import androidx.wear.watchface.complications.data.NoDataComplicationData
import androidx.wear.watchface.complications.data.PlainComplicationText
import androidx.wear.watchface.complications.data.RangedValueComplicationData
import androidx.wear.watchface.complications.data.ShortTextComplicationData
import androidx.wear.watchface.complications.data.SmallImage
import androidx.wear.watchface.complications.data.SmallImageComplicationData
import androidx.wear.watchface.complications.data.SmallImageType
import androidx.wear.watchface.complications.data.TimeDifferenceComplicationText
import androidx.wear.watchface.complications.data.TimeDifferenceStyle
import androidx.wear.watchface.complications.datasource.ComplicationDataTimeline
import androidx.wear.watchface.complications.datasource.TimeInterval
import androidx.wear.watchface.complications.datasource.TimelineEntry
import health.pulse.strength.core.widgets.WidgetCommands
import health.pulse.strength.wear.R
import health.pulse.strength.wear.WearMainActivity
import health.pulse.strength.wear.data.WearView
import health.pulse.strength.wear.model.ComplicationModels
import health.pulse.strength.wear.model.Glyph
import health.pulse.strength.wear.model.RangedContent
import health.pulse.strength.wear.model.RestContent
import health.pulse.strength.wear.model.Tap
import health.pulse.strength.wear.model.TextContent
import health.pulse.strength.wear.model.WearText
import java.time.Duration
import java.time.Instant
import java.util.concurrent.TimeUnit

/**
 * Turns the plain complication models into the watch face's `ComplicationData`. One function per complication service, each answering
 * only the types that service declares in the manifest; any other type gets `NoDataComplicationData`.
 */
internal class ComplicationFactory(context: Context) {
    private val context = context.applicationContext

    fun weeklyGoal(type: ComplicationType, view: WearView): ComplicationData = when (type) {
        ComplicationType.RANGED_VALUE -> ranged(ComplicationModels.weeklyGoalRanged(view))
        ComplicationType.SHORT_TEXT -> short(ComplicationModels.weeklyGoalText(view))
        else -> NoDataComplicationData()
    }

    fun daysSince(type: ComplicationType, view: WearView): ComplicationData = when (type) {
        ComplicationType.SHORT_TEXT -> short(ComplicationModels.daysSince(view))
        else -> NoDataComplicationData()
    }

    fun nextUp(type: ComplicationType, view: WearView): ComplicationData = when (type) {
        ComplicationType.LONG_TEXT -> long(ComplicationModels.nextUpLong(view))
        ComplicationType.SHORT_TEXT -> short(ComplicationModels.nextUpShort(view))
        else -> NoDataComplicationData()
    }

    fun start(type: ComplicationType, view: WearView): ComplicationData {
        val content = ComplicationModels.start(view)
        return when (type) {
            ComplicationType.SHORT_TEXT -> short(content)
            ComplicationType.MONOCHROMATIC_IMAGE -> MonochromaticImageComplicationData.Builder(
                MonochromaticImage.Builder(icon(Glyph.PLAY)).build(),
                described(content.description),
            ).setTapAction(tapAction(content.tap)).build()
            ComplicationType.SMALL_IMAGE -> SmallImageComplicationData.Builder(
                SmallImage.Builder(Icon.createWithResource(context, R.drawable.ic_play_color), SmallImageType.ICON).build(),
                described(content.description),
            ).setTapAction(tapAction(content.tap)).build()
            else -> NoDataComplicationData()
        }
    }

    fun streak(type: ComplicationType, view: WearView): ComplicationData = when (type) {
        ComplicationType.SHORT_TEXT -> short(ComplicationModels.streak(view))
        else -> NoDataComplicationData()
    }

    fun weeklySets(type: ComplicationType, view: WearView): ComplicationData = when (type) {
        ComplicationType.RANGED_VALUE -> ranged(ComplicationModels.weeklySets(view))
        else -> NoDataComplicationData()
    }

    /**
     * The rest timer. While a rest runs the timeline holds the countdown until it ends and then "GO" for [OVER_WINDOW]; the watch face
     * switches between them by itself. The gauge and the digits are driven by the face from the end time (dynamic value, time
     * difference text), so nothing needs to be pushed while the seconds tick.
     */
    fun rest(type: ComplicationType, view: WearView, now: Instant): ComplicationDataTimeline? {
        if (type != ComplicationType.RANGED_VALUE && type != ComplicationType.SHORT_TEXT) return null
        return when (val state = RestContent.of(view, now)) {
            RestContent.Waiting, RestContent.Idle -> ComplicationDataTimeline(restPlain(type, REST_IDLE, 0f, 1f, description = IDLE_DESCRIPTION), emptyList())
            RestContent.Over -> ComplicationDataTimeline(
                restPlain(type, REST_IDLE, 0f, 1f, description = IDLE_DESCRIPTION),
                listOf(TimelineEntry(TimeInterval(now, now.plus(OVER_WINDOW)), restOver(type))),
            )
            is RestContent.Frozen -> ComplicationDataTimeline(
                restPlain(
                    type,
                    text = WearText.clock(state.remainingSeconds),
                    value = (state.totalSeconds - state.remainingSeconds).toFloat(),
                    max = state.totalSeconds.toFloat(),
                    title = "PAUSED",
                    description = "Workout paused, ${WearText.spoken(state.remainingSeconds)} of rest left",
                ),
                emptyList(),
            )
            is RestContent.Counting -> ComplicationDataTimeline(
                restPlain(type, REST_IDLE, 0f, 1f, description = IDLE_DESCRIPTION),
                listOf(
                    TimelineEntry(TimeInterval(now, state.endsAt), restCounting(type, state)),
                    TimelineEntry(TimeInterval(state.endsAt, state.endsAt.plus(OVER_WINDOW)), restOver(type)),
                ),
            )
        }
    }

    /** The sample the watch face editor shows for the rest timer: 1:24 of a 2:00 rest. */
    fun restPreview(type: ComplicationType): ComplicationData? = when (type) {
        ComplicationType.RANGED_VALUE, ComplicationType.SHORT_TEXT ->
            restPlain(type, "1:24", 36f, 120f, description = "Rest timer, 1 minute 24 seconds left")
        else -> null
    }

    private fun restCounting(type: ComplicationType, state: RestContent.Counting): ComplicationData {
        val countdown = TimeDifferenceComplicationText.Builder(TimeDifferenceStyle.STOPWATCH, CountDownTimeReference(state.endsAt))
            .setMinimumTimeUnit(TimeUnit.SECONDS)
            .build()
        val description = described("Rest timer")
        val elapsedNow = (state.totalSeconds - state.remainingSeconds).toFloat()
        return when (type) {
            ComplicationType.RANGED_VALUE -> {
                val remaining = DynamicInstant.platformTimeWithSecondsPrecision()
                    .durationUntil(DynamicInstant.withSecondsPrecision(state.endsAt))
                    .toIntSeconds()
                    .asFloat()
                val elapsed = DynamicFloat.constant(state.totalSeconds.toFloat()).minus(remaining)
                RangedValueComplicationData.Builder(elapsed, elapsedNow, 0f, state.totalSeconds.toFloat(), description)
                    .setText(countdown)
                    .setTitle(plain(REST_TITLE))
                    .setTapAction(tapAction(Tap.OPEN_APP))
                    .build()
            }
            else -> ShortTextComplicationData.Builder(countdown, description)
                .setTitle(plain(REST_TITLE))
                .setTapAction(tapAction(Tap.OPEN_APP))
                .build()
        }
    }

    private fun restOver(type: ComplicationType): ComplicationData =
        restPlain(type, REST_OVER, 1f, 1f, description = "Rest is over, the next set is due")

    private fun restPlain(
        type: ComplicationType,
        text: String,
        value: Float,
        max: Float,
        title: String = REST_TITLE,
        description: String,
    ): ComplicationData = when (type) {
        ComplicationType.RANGED_VALUE -> RangedValueComplicationData.Builder(value.coerceIn(0f, max), 0f, max, described(description))
            .setText(plain(text))
            .setTitle(plain(title))
            .setTapAction(tapAction(Tap.OPEN_APP))
            .build()
        else -> ShortTextComplicationData.Builder(plain(text), described(description))
            .setTitle(plain(title))
            .setTapAction(tapAction(Tap.OPEN_APP))
            .build()
    }

    /** A gauge complication. */
    fun ranged(content: RangedContent): ComplicationData {
        val builder = RangedValueComplicationData.Builder(content.value, 0f, content.max, described(content.description))
            .setText(plain(WearText.short(content.text)))
            .setTapAction(tapAction(content.tap))
        content.title?.let { builder.setTitle(plain(WearText.short(it))) }
        return builder.build()
    }

    fun short(content: TextContent): ComplicationData {
        val builder = ShortTextComplicationData.Builder(plain(WearText.short(content.text)), described(content.description))
            .setTapAction(tapAction(content.tap))
        content.title?.let { builder.setTitle(plain(WearText.short(it))) }
        content.glyph?.let { builder.setMonochromaticImage(MonochromaticImage.Builder(icon(it)).build()) }
        return builder.build()
    }

    fun long(content: TextContent): ComplicationData {
        val builder = LongTextComplicationData.Builder(plain(content.text), described(content.description))
            .setTapAction(tapAction(content.tap))
        content.title?.let { builder.setTitle(plain(it)) }
        content.glyph?.let { builder.setMonochromaticImage(MonochromaticImage.Builder(icon(it)).build()) }
        return builder.build()
    }

    private fun plain(text: String): ComplicationText = PlainComplicationText.Builder(text).build()

    private fun described(description: String): ComplicationText = PlainComplicationText.Builder(description).build()

    private fun icon(glyph: Glyph): Icon = Icon.createWithResource(
        context,
        when (glyph) {
            Glyph.PLAY -> R.drawable.ic_play
            Glyph.FLAME -> R.drawable.ic_flame
        },
    )

    /** Opens the watch app; [Tap.START_NEXT] also asks it to start the next workout. */
    fun tapAction(tap: Tap): PendingIntent {
        val intent = Intent(context, WearMainActivity::class.java)
        if (tap == Tap.START_NEXT) intent.putExtra(WearMainActivity.EXTRA_COMMAND, WidgetCommands.START_NEXT)
        return PendingIntent.getActivity(context, tap.ordinal, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
    }

    private companion object {
        const val REST_TITLE = "REST"
        const val REST_IDLE = "--"
        const val REST_OVER = "GO"
        const val IDLE_DESCRIPTION = "No rest running"

        /** How long "GO" stays after a rest ran out, if the phone sends nothing newer. */
        val OVER_WINDOW: Duration = Duration.ofMinutes(10)
    }
}
