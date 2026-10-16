package health.pulse.strength.widgets.common

import android.graphics.Bitmap
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.glance.ColorFilter
import androidx.glance.GlanceModifier
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.LocalContext
import androidx.glance.unit.ColorProvider
import androidx.compose.ui.graphics.Color

/** A chart mask from [ChartBitmaps], tinted with a (day/night aware) colour. */
@Composable
fun MaskImage(bitmap: Bitmap, tint: ColorProvider, modifier: GlanceModifier = GlanceModifier, contentDescription: String? = null) {
    Image(
        provider = ImageProvider(bitmap),
        contentDescription = contentDescription,
        modifier = modifier,
        colorFilter = ColorFilter.tint(tint),
    )
}

/** Pixels of a dp value on this display (bitmaps are drawn in pixels). */
@Composable
fun Dp.toPx(): Int {
    val density = LocalContext.current.resources.displayMetrics.density
    return (value * density).toInt().coerceAtLeast(1)
}

/** A colour that is [light] by day and [dark] at night (resolved by the launcher, so it follows the system theme live). */
fun dayNight(light: Color, dark: Color): ColorProvider = androidx.glance.color.ColorProvider(day = light, night = dark)

/** Dimensions used across the widgets. */
object WidgetDimens {
    val corner = 22.dp
    val padding = 14.dp
    val paddingCompact = 10.dp
}
