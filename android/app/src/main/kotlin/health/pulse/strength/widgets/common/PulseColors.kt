package health.pulse.strength.widgets.common

import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.ui.graphics.Color
import androidx.glance.color.ColorProviders
import androidx.glance.material3.ColorProviders

/**
 * The brand colours of widgets/SPEC.md section 7 as a Glance colour set (light and dark). Widgets that should follow the user's wallpaper
 * colours (the "themed" variants, HS-06) use `GlanceTheme.colors` of the default, dynamic theme instead.
 */
object PulseColors {
    val GreenLight = Color(0xFF1B8448)
    val GreenDark = Color(0xFF30D158)
    val ProgressLight = Color(0xFF2EC76B)
    val ProgressDark = Color(0xFF30D158)
    val GoldFill = Color(0xFFFFF6D6)
    val GoldFillDark = Color(0xFF3A2E00)
    val GoldText = Color(0xFF7A5200)
    val GoldTextDark = Color(0xFFFFD60A)
    val Gold = Color(0xFFFFCC00)
    val Ready = Color(0xFF34C759)
    val Recovering = Color(0xFFFFCC00)
    val Worked = Color(0xFFFF3B30)
    val Heart = Color(0xFFFF3B30)
    val BlueLight = Color(0xFF0066D6)
    val BlueDark = Color(0xFF0A84FF)

    private val light = lightColorScheme(
        primary = GreenLight,
        onPrimary = Color.White,
        primaryContainer = Color(0xFFE4F2EA),
        onPrimaryContainer = Color(0xFF146638),
        secondary = ProgressLight,
        onSecondary = Color.White,
        background = Color(0xFFF2F2F7),
        onBackground = Color.Black,
        surface = Color.White,
        onSurface = Color.Black,
        surfaceVariant = Color(0xFFF2F2F7),
        onSurfaceVariant = Color(0xFF6B6B70),
        outline = Color(0xFFE5E5EA),
        tertiary = BlueLight,
        tertiaryContainer = GoldFill,
        onTertiaryContainer = GoldText,
        error = Worked,
    )

    private val dark = darkColorScheme(
        primary = GreenDark,
        onPrimary = Color.Black,
        primaryContainer = Color(0xFF16301F),
        onPrimaryContainer = GreenDark,
        secondary = ProgressDark,
        onSecondary = Color.Black,
        background = Color.Black,
        onBackground = Color.White,
        surface = Color(0xFF1C1C1E),
        onSurface = Color.White,
        surfaceVariant = Color(0xFF2C2C2E),
        onSurfaceVariant = Color(0xFF98989D),
        outline = Color(0xFF3A3A3C),
        tertiary = BlueDark,
        tertiaryContainer = GoldFillDark,
        onTertiaryContainer = GoldTextDark,
        error = Color(0xFFFF453A),
    )

    /** `GlanceTheme(colors = PulseColors.colors)`. */
    val colors: ColorProviders = ColorProviders(light = light, dark = dark)
}
