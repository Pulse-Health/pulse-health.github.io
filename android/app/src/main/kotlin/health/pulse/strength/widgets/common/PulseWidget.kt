package health.pulse.strength.widgets.common

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.glance.GlanceId
import androidx.glance.GlanceTheme
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.provideContent
import health.pulse.strength.core.widgets.WidgetSnapshot
import health.pulse.strength.runtime.StrengthRuntime

/**
 * Base of every Glance widget of the app. It reads the current [WidgetSnapshot] once per update and lays [Content] out inside the Pulse
 * theme (brand colours; override [useDynamicColors] for the wallpaper-coloured "themed" variants). Update with `MyWidget().updateAll(context)`;
 * `Surfaces.refreshAll` does that for every widget after the snapshot changed.
 *
 * Sizes: [sizeMode] is Exact by default, so [Content] reads `LocalSize.current` and chooses its layout; use the helpers in [WidgetSizes].
 */
abstract class PulseWidget : GlanceAppWidget() {
    override val sizeMode: SizeMode = SizeMode.Exact

    /** True for variants that follow the system's dynamic (wallpaper) colours instead of the brand colours. */
    protected open val useDynamicColors: Boolean = false

    /** The snapshot the widget shows; tests override it. */
    protected open fun snapshot(context: Context): WidgetSnapshot = StrengthRuntime.snapshots.current()

    final override suspend fun provideGlance(context: Context, id: GlanceId) {
        val snapshot = snapshot(context)
        provideContent {
            if (useDynamicColors) {
                GlanceTheme { Content(snapshot) }
            } else {
                GlanceTheme(colors = PulseColors.colors) { Content(snapshot) }
            }
        }
    }

    @Composable
    abstract fun Content(snapshot: WidgetSnapshot)
}

/** Cell-count thresholds for choosing a layout from `LocalSize.current` (a launcher cell is about 70 dp square). */
object WidgetSizes {
    val Compact = DpSize(110.dp, 110.dp)

    fun isWide(size: DpSize): Boolean = size.width >= 220.dp
    fun isTall(size: DpSize): Boolean = size.height >= 220.dp
    fun isCompactHeight(size: DpSize): Boolean = size.height < 100.dp
}
