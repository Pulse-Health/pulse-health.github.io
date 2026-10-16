package health.pulse.strength.ui.theme

import android.provider.Settings
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.remember
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import health.pulse.strength.core.ActiveWorkoutPresentation
import health.pulse.strength.core.SetType

// Design tokens of the Pulse look (port of PulseTheme.swift: the "Pulse Gym & Strength" canvas): grouped grey ground, white 20 dp
// cards, green Fitness accent, blue Finish pill. Light values equal the design; dark values are the matching dark-mode values.

/** The colours of the Pulse look for one interface style. Read them with `PulseTheme.colors`. */
@Immutable
class PulseColors(
    // Surfaces
    val ground: Color,
    val card: Color,
    /** Row background inside a card (pending set). */
    val rowFill: Color,
    /** Cells, small buttons and inputs inside a card. */
    val cellFill: Color,
    /** A pending-set cell sitting on a tinted (done) row. */
    val cellOnTint: Color,
    /** Background of an exercise media tile (behind the demo frames and the placeholder glyph). */
    val mediaTile: Color,
    val chipFill: Color,
    val separator: Color,
    // Text
    val ink: Color,
    val inkSecondary: Color,
    val inkTertiary: Color,
    // Accents
    val green: Color,
    /** Green text on grey fills (higher contrast than [green]). */
    val greenText: Color,
    val greenTint: Color,
    /** The lighter green wash behind the coach tip. */
    val coachTipFill: Color,
    /** Text / icon colour on a [green] fill. */
    val onGreen: Color,
    val blue: Color,
    val blueText: Color,
    val blueTint: Color,
    /** The superset pill's wash; [blueTint] is the stronger picker-chip value. */
    val supersetFill: Color,
    val destructive: Color,
    val heart: Color,
    // Data marks
    val progress: Color,
    val progressTrack: Color,
    val progressTrackCurrent: Color,
    val recoveryGood: Color,
    val recoveryFair: Color,
    val recoveryLow: Color,
    val prFill: Color,
    val prText: Color,
    val doneRowFill: Color,
    val nextRowRing: Color,
    val toastFill: Color,
    val toastAction: Color,
    // Set type badges
    val warmupBadgeBackground: Color,
    val warmupBadgeForeground: Color,
    val dropBadgeBackground: Color,
    val dropBadgeForeground: Color,
    val failureBadgeBackground: Color,
    val failureBadgeForeground: Color,
    val isDark: Boolean,
) {
    fun recoveryColor(level: ActiveWorkoutPresentation.RecoveryLevel): Color = when (level) {
        ActiveWorkoutPresentation.RecoveryLevel.GOOD -> recoveryGood
        ActiveWorkoutPresentation.RecoveryLevel.FAIR -> recoveryFair
        ActiveWorkoutPresentation.RecoveryLevel.LOW -> recoveryLow
    }
}

private fun hex(value: Int, alpha: Float = 1f): Color = Color(0xFF000000.toInt() or value).copy(alpha = alpha)

val LightPulseColors = PulseColors(
    ground = hex(0xF2F2F7),
    card = hex(0xFFFFFF),
    rowFill = hex(0xF7F7FA),
    cellFill = hex(0xF2F2F7),
    cellOnTint = hex(0xFFFFFF),
    mediaTile = hex(0xF4F4F7),
    chipFill = hex(0x767680, 0.12f),
    separator = hex(0x3C3C43, 0.18f),
    ink = hex(0x000000),
    inkSecondary = hex(0x6B6B70),
    inkTertiary = hex(0x8E8E93),
    green = hex(0x1B8448),
    greenText = hex(0x146638),
    greenTint = hex(0x1B8448, 0.10f),
    coachTipFill = hex(0x1B8448, 0.08f),
    onGreen = hex(0xFFFFFF),
    blue = hex(0x0066D6),
    blueText = hex(0x0057B8),
    blueTint = hex(0x007AFF, 0.15f),
    supersetFill = hex(0x007AFF, 0.12f),
    destructive = hex(0xD70015),
    heart = hex(0xFF3B30),
    progress = hex(0x2EC76B),
    progressTrack = hex(0xE5E5EA),
    progressTrackCurrent = hex(0xC7C7CC),
    recoveryGood = hex(0x34C759),
    recoveryFair = hex(0xFFCC00),
    recoveryLow = hex(0xFF3B30),
    prFill = hex(0xFFCC00, 0.24f),
    prText = hex(0x7A5200),
    doneRowFill = hex(0x34C759, 0.10f),
    nextRowRing = hex(0x1B8448, 0.55f),
    toastFill = hex(0x1C1C1E),
    toastAction = hex(0x7BE495),
    warmupBadgeBackground = hex(0xFF9500, 0.16f),
    warmupBadgeForeground = hex(0x9A4A00),
    dropBadgeBackground = hex(0x9B3FC9, 0.14f),
    dropBadgeForeground = hex(0x7A2FA3),
    failureBadgeBackground = hex(0xFF3B30, 0.14f),
    failureBadgeForeground = hex(0xB3261E),
    isDark = false,
)

val DarkPulseColors = PulseColors(
    ground = hex(0x000000),
    card = hex(0x1C1C1E),
    rowFill = hex(0x2C2C2E),
    cellFill = hex(0x2C2C2E),
    cellOnTint = hex(0x3A3A3C),
    mediaTile = hex(0x2C2C2E),
    chipFill = hex(0x767680, 0.24f),
    separator = hex(0x545458, 0.65f),
    ink = hex(0xFFFFFF),
    inkSecondary = hex(0x98989D),
    inkTertiary = hex(0x636366),
    green = hex(0x30D158),
    greenText = hex(0x30D158),
    greenTint = hex(0x30D158, 0.18f),
    coachTipFill = hex(0x30D158, 0.18f),
    onGreen = hex(0x000000),
    blue = hex(0x0A84FF),
    blueText = hex(0x64D2FF),
    blueTint = hex(0x0A84FF, 0.28f),
    supersetFill = hex(0x0A84FF, 0.28f),
    destructive = hex(0xFF453A),
    heart = hex(0xFF453A),
    progress = hex(0x30D158),
    progressTrack = hex(0x3A3A3C),
    progressTrackCurrent = hex(0x636366),
    recoveryGood = hex(0x30D158),
    recoveryFair = hex(0xFFD60A),
    recoveryLow = hex(0xFF453A),
    prFill = hex(0xFFD60A, 0.24f),
    prText = hex(0xFFD60A),
    doneRowFill = hex(0x30D158, 0.18f),
    nextRowRing = hex(0x30D158, 0.7f),
    toastFill = hex(0x3A3A3C),
    toastAction = hex(0x7BE495),
    warmupBadgeBackground = hex(0xFF9F0A, 0.24f),
    warmupBadgeForeground = hex(0xFF9F0A),
    dropBadgeBackground = hex(0xBF5AF2, 0.24f),
    dropBadgeForeground = hex(0xBF5AF2),
    failureBadgeBackground = hex(0xFF453A, 0.24f),
    failureBadgeForeground = hex(0xFF453A),
    isDark = true,
)

val LocalPulseColors = compositionLocalOf { LightPulseColors }

/** True when the user turned animations off in the system settings (the Android counterpart of "Reduce Motion"). */
val LocalReduceMotion = compositionLocalOf { false }

/** Shape and spacing metrics of the design. */
object PulseMetrics {
    val cardRadius: Dp = 20.dp
    val listRadius: Dp = 12.dp
    val rowRadius: Dp = 10.dp
    val sheetRadius: Dp = 26.dp
    val screenInset: Dp = 16.dp

    /** Widest a screen's content grows on a tablet or in landscape: wider windows centre the content. */
    val maxContentWidth: Dp = 640.dp
}

object PulseTheme {
    val colors: PulseColors
        @Composable @ReadOnlyComposable get() = LocalPulseColors.current
}

/** Type styles (sizes in sp, so they follow the user's font size, like Dynamic Type on iOS). */
object PulseFont {
    val largeTitle = TextStyle(fontSize = 34.sp, fontWeight = FontWeight.Bold)
    val title = TextStyle(fontSize = 22.sp, fontWeight = FontWeight.Bold)
    val headline = TextStyle(fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
    val body = TextStyle(fontSize = 17.sp)
    val subhead = TextStyle(fontSize = 15.sp)
    val footnote = TextStyle(fontSize = 13.sp)
    val caption = TextStyle(fontSize = 12.sp)
    val caption2 = TextStyle(fontSize = 11.sp)

    /** Figure text: bold with equal-width digits (the design's rounded numerals). */
    fun number(size: TextUnit, weight: FontWeight = FontWeight.Bold): TextStyle =
        TextStyle(fontSize = size, fontWeight = weight, fontFeatureSettings = "tnum")

    /** A design text size with a weight, for the many fixed sizes of the design. */
    fun text(size: TextUnit, weight: FontWeight = FontWeight.Normal): TextStyle = TextStyle(fontSize = size, fontWeight = weight)
}

/** Colours of a set type's badge. */
@Composable
@ReadOnlyComposable
fun SetType.badgeBackground(): Color = when (this) {
    SetType.NORMAL -> PulseTheme.colors.cellFill
    SetType.WARMUP -> PulseTheme.colors.warmupBadgeBackground
    SetType.DROP -> PulseTheme.colors.dropBadgeBackground
    SetType.FAILURE -> PulseTheme.colors.failureBadgeBackground
}

@Composable
@ReadOnlyComposable
fun SetType.badgeForeground(): Color = when (this) {
    SetType.NORMAL -> PulseTheme.colors.ink
    SetType.WARMUP -> PulseTheme.colors.warmupBadgeForeground
    SetType.DROP -> PulseTheme.colors.dropBadgeForeground
    SetType.FAILURE -> PulseTheme.colors.failureBadgeForeground
}

/**
 * Applies the Pulse look to [content]: the colours of the current interface style (or [darkTheme]), a Material colour scheme built
 * from them (so sheets, dialogs and system widgets match) and the "reduce motion" flag.
 */
@Composable
fun PulseTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    reduceMotion: Boolean = systemReducesMotion(),
    content: @Composable () -> Unit,
) {
    val colors = if (darkTheme) DarkPulseColors else LightPulseColors
    val scheme = if (darkTheme) {
        darkColorScheme(
            primary = colors.green, onPrimary = colors.onGreen, secondary = colors.blue, onSecondary = Color.White,
            background = colors.ground, onBackground = colors.ink, surface = colors.card, onSurface = colors.ink,
            surfaceVariant = colors.cellFill, onSurfaceVariant = colors.inkSecondary, outline = colors.inkTertiary,
            outlineVariant = colors.separator, error = colors.destructive, onError = Color.White,
            surfaceContainerLow = colors.card, surfaceContainer = colors.card, surfaceContainerHigh = colors.card,
            surfaceContainerHighest = colors.card, scrim = Color.Black,
        )
    } else {
        lightColorScheme(
            primary = colors.green, onPrimary = colors.onGreen, secondary = colors.blue, onSecondary = Color.White,
            background = colors.ground, onBackground = colors.ink, surface = colors.card, onSurface = colors.ink,
            surfaceVariant = colors.cellFill, onSurfaceVariant = colors.inkSecondary, outline = colors.inkTertiary,
            outlineVariant = colors.separator, error = colors.destructive, onError = Color.White,
            surfaceContainerLow = colors.card, surfaceContainer = colors.card, surfaceContainerHigh = colors.card,
            surfaceContainerHighest = colors.card, scrim = Color.Black,
        )
    }
    CompositionLocalProvider(LocalPulseColors provides colors, LocalReduceMotion provides reduceMotion) {
        MaterialTheme(colorScheme = scheme, content = content)
    }
}

/** True when the system animator scale is 0 ("Remove animations" / reduced motion). */
@Composable
fun systemReducesMotion(): Boolean {
    val context = LocalContext.current
    return remember(context) {
        runCatching { Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f }
            .getOrDefault(false)
    }
}
