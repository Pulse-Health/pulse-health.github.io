package health.pulse.strength.wear.ui

import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import androidx.wear.compose.material.Colors
import androidx.wear.compose.material.MaterialTheme

/** The watch is always dark: these are the dark values of the canvas (widgets/SPEC.md section 7). */
internal object WearColors {
    val Green = Color(0xFF30D158)
    val GreenTrack = Color(0x3830D158)
    val OnGreen = Color.Black
    val Ink = Color.White
    val Secondary = Color(0xFF98989D)
    val Surface = Color(0xFF1C1C1E)
    val Raised = Color(0xFF3A3A3C)
    val Gold = Color(0xFFFFD60A)
    val Red = Color(0xFFFF453A)
}

private val colors = Colors(
    primary = WearColors.Green,
    primaryVariant = WearColors.Green,
    secondary = WearColors.Green,
    secondaryVariant = WearColors.Green,
    background = Color.Black,
    surface = WearColors.Surface,
    error = WearColors.Red,
    onPrimary = WearColors.OnGreen,
    onSecondary = WearColors.OnGreen,
    onBackground = WearColors.Ink,
    onSurface = WearColors.Ink,
    onSurfaceVariant = WearColors.Secondary,
    onError = WearColors.OnGreen,
)

@Composable
internal fun PulseWearTheme(content: @Composable () -> Unit) {
    MaterialTheme(colors = colors, content = content)
}

/** Rounded, tabular numerals for every figure (the canvas' `.num` style): digits keep their width while a clock ticks. */
internal fun numberStyle(size: Float, weight: FontWeight = FontWeight.Bold, color: Color = WearColors.Ink): TextStyle = TextStyle(
    color = color,
    fontSize = size.sp,
    fontWeight = weight,
    fontFeatureSettings = "tnum",
)
