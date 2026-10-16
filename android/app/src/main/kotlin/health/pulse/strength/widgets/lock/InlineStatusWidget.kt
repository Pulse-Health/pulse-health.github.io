package health.pulse.strength.widgets.lock

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceModifier
import androidx.glance.GlanceTheme
import androidx.glance.LocalSize
import androidx.glance.appwidget.GlanceAppWidgetManager
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.layout.Alignment
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.width
import androidx.glance.text.FontWeight
import health.pulse.strength.R
import health.pulse.strength.core.widgets.WidgetSnapshot
import health.pulse.strength.widgets.common.PulseWidget

/**
 * LS-09 / LS-10 / LS-11 Inline status (4x1): one line of text on a pill, the Android form of the iOS inline accessories. One class draws
 * all three; each [Mode] is placed from its own receiver (and so has its own picker entry and size info):
 *
 * * [Mode.WEEK]: "3 of 4 workouts this week"
 * * [Mode.SPLIT]: "Push day · last 5 days ago"
 * * [Mode.REST]: "Rest day · back on Sun"; on a training day it shows the split line instead.
 */
class InlineStatusWidget(private val mode: Mode) : PulseWidget() {
    enum class Mode(internal val receiver: Class<out GlanceAppWidgetReceiver>) {
        WEEK(InlineStatusWeekReceiver::class.java),
        SPLIT(InlineStatusSplitReceiver::class.java),
        REST(InlineStatusRestReceiver::class.java),
    }

    @Composable
    override fun Content(snapshot: WidgetSnapshot) {
        val status = LockText.inlineStatus(mode, snapshot)
        val height = LocalSize.current.height
        val tight = height < 48.dp
        WidgetCard(
            description = status.text,
            link = status.link,
            cornerRadius = height / 2,
            padding = if (tight) 6.dp else 10.dp,
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                if (status.showsIcon) {
                    Glyph(R.drawable.ic_lock_dumbbell, 14.dp, GlanceTheme.colors.onSurface)
                    Spacer(GlanceModifier.width(6.dp))
                }
                PulseText(status.text, if (tight) 13.sp else 15.sp, weight = FontWeight.Medium)
            }
        }
    }

    companion object {
        /**
         * Redraws every placed instance of the three modes. The modes share this class, and Glance finds widgets by class, so the
         * instances are looked up by the receiver they were placed from instead, and each is drawn with the mode of its own receiver.
         */
        suspend fun updateAllModes(context: Context) {
            val appWidgets = AppWidgetManager.getInstance(context)
            val glance = GlanceAppWidgetManager(context)
            for (mode in Mode.entries) {
                val widget = InlineStatusWidget(mode)
                for (appWidgetId in appWidgets.getAppWidgetIds(ComponentName(context, mode.receiver))) {
                    widget.update(context, glance.getGlanceIdBy(appWidgetId))
                }
            }
        }
    }
}

class InlineStatusWeekReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget = InlineStatusWidget(InlineStatusWidget.Mode.WEEK)
}

class InlineStatusSplitReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget = InlineStatusWidget(InlineStatusWidget.Mode.SPLIT)
}

class InlineStatusRestReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget = InlineStatusWidget(InlineStatusWidget.Mode.REST)
}
