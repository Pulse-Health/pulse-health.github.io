package health.pulse.strength.widgets.extras

import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceModifier
import androidx.glance.GlanceTheme
import androidx.glance.LocalSize
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.cornerRadius
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.size
import androidx.glance.layout.width
import androidx.glance.text.FontWeight
import health.pulse.strength.core.widgets.DeepLinks
import health.pulse.strength.core.widgets.TimelineKind
import health.pulse.strength.core.widgets.TimelineSegment
import health.pulse.strength.core.widgets.WidgetSnapshot
import health.pulse.strength.widgets.common.MaskImage
import health.pulse.strength.widgets.common.PulseWidget
import health.pulse.strength.widgets.common.WidgetDimens
import health.pulse.strength.widgets.common.toPx
import health.pulse.strength.widgets.lock.FitSafety
import health.pulse.strength.widgets.lock.PulseText
import health.pulse.strength.widgets.lock.TextFit
import health.pulse.strength.widgets.lock.WidgetCard
import health.pulse.strength.widgets.lock.rememberTextMeter
import health.pulse.strength.widgets.lock.textHeight

/**
 * WI-11 Session timeline (4x2): how the time of the last workout was spent as one bar of lifting, rest and long-rest stretches, a legend
 * of the kinds present, and "51 min · 38% under tension · 1 long break" (the longest part of it that fits). Without set times it says so
 * instead of drawing a bar.
 */
class SessionTimelineWidget : PulseWidget() {
    @Composable
    override fun Content(snapshot: WidgetSnapshot) {
        val session = snapshot.lastSession
        val model = ExtrasText.sessionTimeline(session)
        val size = LocalSize.current
        val height = textHeight()
        val tight = height < ExtrasText.COMPACT_BELOW_DP.dp
        val padding = if (tight) 12.dp else WidgetDimens.padding
        val gap = if (tight) 6.dp else 8.dp
        val barHeight = if (tight) 22.dp else 26.dp
        // The summary line goes when the title, the bar, the legend and the summary together do not fit (large text in a short widget).
        val summaryNeeds = TextFit.height(15f) + TextFit.height(12f) + TextFit.height(13f) + (gap * 2 + barHeight).value
        val showsSummary = (height - padding * 2).value + SLACK_DP >= summaryNeeds
        val innerWidth = size.width - padding * 2
        // The name of the session follows the title. Where the whole name fits only after the title is shortened, it is; a name that is too
        // long either way is cut with an ellipsis behind the whole title.
        val titleMeter = rememberTextMeter(15.sp, bold = true)
        val nameWidth = model.name?.let { rememberTextMeter(15.sp, bold = false).width(" · $it") } ?: 0f
        val titleRoom = (innerWidth - FitSafety).value - nameWidth
        val title = if (titleMeter.width("Session timeline") > titleRoom && titleMeter.width("Timeline") <= titleRoom) "Timeline" else "Session timeline"
        val tailRoom = innerWidth - FitSafety - rememberTextMeter(13.sp, bold = true).width(model.headline).dp
        val tail = TextFit.firstFitting(model.tails, tailRoom.value, rememberTextMeter(13.sp, bold = false))
        WidgetCard(description = model.description, link = DeepLinks.hub, padding = padding, contentAlignment = Alignment.TopStart) {
            Column(modifier = GlanceModifier.fillMaxSize()) {
                Row(modifier = GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    PulseText(title, 15.sp, weight = FontWeight.Medium)
                    model.name?.let { PulseText(" · $it", 15.sp, GlanceModifier.defaultWeight(), color = GlanceTheme.colors.onSurfaceVariant) }
                }
                Spacer(GlanceModifier.height(gap))
                if (model.hasBar && session != null) {
                    TimelineBar(session.timeline, model.kinds, innerWidth, barHeight, model.description)
                    Spacer(GlanceModifier.height(gap))
                    Legend(model.kinds)
                } else {
                    PulseText(model.message.orEmpty(), 13.sp, color = GlanceTheme.colors.onSurfaceVariant, maxLines = 3)
                }
                Spacer(GlanceModifier.defaultWeight())
                if (showsSummary && model.headline.isNotEmpty()) {
                    Row(modifier = GlanceModifier.fillMaxWidth()) {
                        PulseText(model.headline, 13.sp, weight = FontWeight.Bold)
                        PulseText(tail, 13.sp, color = GlanceTheme.colors.onSurfaceVariant)
                    }
                }
            }
        }
    }

    /** One rounded bar of [width] by [height]: a mask per kind, so lifting, rest and long rest each keep their own day/night colour. */
    @Composable
    private fun TimelineBar(segments: List<TimelineSegment>, kinds: List<TimelineKind>, width: Dp, height: Dp, description: String) {
        val widthPx = width.toPx()
        val heightPx = height.toPx()
        val masks = ExtrasCharts.timelineMasks(kinds, ExtrasText.timelineSpans(segments, widthPx), widthPx, heightPx, radiusPx = 8.dp.toPx().toFloat())
        val modifier = GlanceModifier.size(width, height)
        Box(modifier = modifier) {
            kinds.forEachIndexed { index, kind ->
                MaskImage(masks.getValue(kind), ExtrasPalette.timeline(kind), modifier, contentDescription = if (index == 0) description else null)
            }
        }
    }

    /** The kinds present, each a swatch and its word. An item is a row of its own: a flat row of all of them would pass Glance's ten children. */
    @Composable
    private fun Legend(kinds: List<TimelineKind>) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            kinds.forEachIndexed { index, kind ->
                if (index > 0) Spacer(GlanceModifier.width(14.dp))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(modifier = GlanceModifier.size(10.dp).cornerRadius(3.dp).background(ExtrasPalette.timeline(kind))) {}
                    Spacer(GlanceModifier.width(5.dp))
                    PulseText(ExtrasText.timelineLabel(kind), 12.sp, color = GlanceTheme.colors.onSurfaceVariant)
                }
            }
        }
    }

    private companion object {
        /** The room a height may lack against the line heights counted by [TextFit]: those are a little generous. */
        const val SLACK_DP = 2f
    }
}

class SessionTimelineReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget = SessionTimelineWidget()
}
