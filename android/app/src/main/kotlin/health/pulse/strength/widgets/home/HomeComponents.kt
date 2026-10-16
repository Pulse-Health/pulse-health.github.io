package health.pulse.strength.widgets.home

import android.graphics.Bitmap
import android.graphics.Canvas
import androidx.annotation.DrawableRes
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.graphics.createBitmap
import androidx.glance.ColorFilter
import androidx.glance.GlanceModifier
import androidx.glance.GlanceTheme
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.action.Action
import androidx.glance.action.clickable
import androidx.glance.appwidget.appWidgetBackground
import androidx.glance.appwidget.cornerRadius
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.size
import androidx.glance.layout.width
import androidx.glance.semantics.contentDescription
import androidx.glance.semantics.semantics
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextAlign
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import health.pulse.strength.R
import health.pulse.strength.core.widgets.DeepLinks
import health.pulse.strength.widgets.common.PulseActions
import health.pulse.strength.widgets.common.PulseColors
import health.pulse.strength.widgets.common.WidgetDimens
import health.pulse.strength.widgets.common.dayNight

/**
 * Colours the brand [androidx.glance.color.ColorProviders] of the app do not name. The values are the ones of the iOS `WidgetTheme`
 * (widgets/SPEC.md section 7), so a widget looks the same on both platforms. Text, card and accent colours come from `GlanceTheme.colors`
 * (that is what lets the themed variant follow the wallpaper); these are the status, heat and gold tones that always stay brand colours.
 */
internal object HomeColors {
    val separator: ColorProvider = dayNight(Color(0xFFDADADF), Color(0xFF38383A))
    val trackStrong: ColorProvider = dayNight(Color(0xFFC7C7CC), Color(0xFF636366))
    val rowFill: ColorProvider = dayNight(Color(0xFFF7F7FA), Color(0xFF2C2C2E))
    val progress: ColorProvider = dayNight(PulseColors.ProgressLight, PulseColors.ProgressDark)
    val gold: ColorProvider = dayNight(PulseColors.Gold, Color(0xFFFFD60A))
    val goldFill: ColorProvider = dayNight(PulseColors.GoldFill, PulseColors.GoldFillDark)
    val goldText: ColorProvider = dayNight(PulseColors.GoldText, PulseColors.GoldTextDark)
    val goldChip: ColorProvider = dayNight(Color(0x3DFFCC00), Color(0x3DFFD60A))
    val ready: ColorProvider = dayNight(PulseColors.Ready, Color(0xFF30D158))
    val recovering: ColorProvider = dayNight(PulseColors.Recovering, Color(0xFFFFD60A))
    val worked: ColorProvider = dayNight(PulseColors.Worked, Color(0xFFFF453A))

    /** Heat level 0...3 of the month heatmap: the fill, and the colour of the day number on it (every pair has a contrast of at least 4.5). */
    fun heatFill(level: Int): ColorProvider = heatProvider(HeatTones[level.coerceIn(0, 3)].fill)

    fun heatInk(level: Int): ColorProvider = heatProvider(HeatTones[level.coerceIn(0, 3)].ink)

    private fun heatProvider(pair: ToneColors) = dayNight(pair.light, pair.dark)

    /** The fixed tones of the card that is dark in both appearances (HS-05). */
    object DarkCard {
        val surface: ColorProvider = ColorProvider(Color(0xFF1C1C1E))
        val ink: ColorProvider = ColorProvider(Color.White)
        val inkSecondary: ColorProvider = ColorProvider(Color(0xFF98989D))
        val accent: ColorProvider = ColorProvider(Color(0xFF30D158))
        val onAccent: ColorProvider = ColorProvider(Color.Black)
    }
}

/** A colour for the light and one for the dark appearance. */
internal data class ToneColors(val light: Color, val dark: Color)

/** A heatmap level: the cell fill and the ink of the day number on it. */
internal data class HeatTone(val fill: ToneColors, val ink: ToneColors)

/** Level 0 is an empty day; 1...3 are the volume thirds (widgets/SPEC.md section 2, "month"). */
internal val HeatTones: List<HeatTone> = listOf(
    HeatTone(fill = ToneColors(Color(0xFFF2F2F7), Color(0xFF2C2C2E)), ink = ToneColors(Color(0xFF6B6B70), Color(0xFF98989D))),
    HeatTone(fill = ToneColors(Color(0xFFB9E7C8), Color(0xFF1E5A34)), ink = ToneColors(Color(0xFF0B3D20), Color.White)),
    HeatTone(fill = ToneColors(Color(0xFF5BC783), Color(0xFF2F9B55)), ink = ToneColors(Color.Black, Color.Black)),
    HeatTone(fill = ToneColors(Color(0xFF1B8448), Color(0xFF30D158)), ink = ToneColors(Color.White, Color.Black)),
)

/** Sizes and fits shared by the layouts. All values are dp. */
internal object HomeLayout {
    /** Smallest touch target of a button (widgets/SPEC.md section 7). */
    val TouchTarget = 48.dp

    /** The painted height of a pill button inside its [TouchTarget]. */
    val PillHeight = 40.dp

    /** How many rows of [rowDp] fit into [availableDp] after [reserveDp] is set aside, between 0 and [max]. */
    fun rowsThatFit(availableDp: Float, rowDp: Float, reserveDp: Float = 0f, max: Int = Int.MAX_VALUE): Int =
        ((availableDp - reserveDp) / rowDp).toInt().coerceIn(0, max)

    /**
     * A font size in sp that lets [text] fit into [widthDp], never above [baseSp] nor below [minSp]. The estimate assumes bold digits
     * and capitals advance by about 0.58 of the font size, which holds for the system sans.
     */
    fun fittedSp(text: String, widthDp: Float, baseSp: Float, minSp: Float): Float {
        if (text.isEmpty()) return baseSp
        return (widthDp / (text.length * 0.58f)).coerceIn(minSp, baseSp)
    }
}

/** `contentDescription` for TalkBack on a container; null leaves the children to speak for themselves. */
internal fun GlanceModifier.describe(description: String?): GlanceModifier =
    if (description == null) this else semantics { contentDescription = description }

/**
 * The root of a widget: the rounded card that is also the click target (the whole widget opens the app on [onClick]). [bottomPadding]
 * can be smaller than [padding] when the last child is a button whose transparent touch margin supplies the visual space, and
 * [horizontalPadding] differs when the content needs the height more than the width.
 */
@Composable
internal fun WidgetCard(
    background: ColorProvider = GlanceTheme.colors.surface,
    padding: Dp = WidgetDimens.padding,
    horizontalPadding: Dp = padding,
    bottomPadding: Dp = padding,
    description: String? = null,
    onClick: Action = PulseActions.link(DeepLinks.hub),
    contentAlignment: Alignment = Alignment.TopStart,
    content: @Composable () -> Unit,
) {
    Box(
        modifier = GlanceModifier
            .fillMaxSize()
            .appWidgetBackground()
            .background(background)
            .cornerRadius(WidgetDimens.corner)
            .padding(start = horizontalPadding, top = padding, end = horizontalPadding, bottom = bottomPadding)
            .clickable(onClick)
            .describe(description),
        contentAlignment = contentAlignment,
        content = content,
    )
}

/** One line of text that ends in an ellipsis instead of overflowing. */
@Composable
internal fun Label(
    text: String,
    size: TextUnit,
    color: ColorProvider,
    weight: FontWeight = FontWeight.Normal,
    modifier: GlanceModifier = GlanceModifier,
    maxLines: Int = 1,
    align: TextAlign? = null,
) {
    Text(
        text = text,
        modifier = modifier,
        style = TextStyle(color = color, fontSize = size, fontWeight = weight, textAlign = align),
        maxLines = maxLines,
    )
}

/** The small upper-case label above a value ("NEXT UP"). */
@Composable
internal fun Eyebrow(text: String, color: ColorProvider = GlanceTheme.colors.onPrimaryContainer, modifier: GlanceModifier = GlanceModifier) {
    Label(HomeText.eyebrow(text), 11.sp, color, FontWeight.Bold, modifier)
}

/** A tinted vector icon from `res/drawable`; decorative unless [description] is given. */
@Composable
internal fun Icon(@DrawableRes resource: Int, tint: ColorProvider, size: Dp, description: String? = null) {
    Image(
        provider = ImageProvider(resource),
        contentDescription = description,
        modifier = GlanceModifier.size(size),
        colorFilter = ColorFilter.tint(tint),
    )
}

/**
 * A pill-shaped text button. The whole [HomeLayout.TouchTarget] high box is the click target, the painted pill is
 * [HomeLayout.PillHeight] high inside it.
 */
@Composable
internal fun PillButton(
    label: String,
    action: Action,
    modifier: GlanceModifier = GlanceModifier,
    @DrawableRes icon: Int? = null,
    container: ColorProvider = GlanceTheme.colors.primary,
    content: ColorProvider = GlanceTheme.colors.onPrimary,
    description: String = label,
) {
    Box(
        modifier = modifier.height(HomeLayout.TouchTarget).clickable(action).describe(description),
        contentAlignment = Alignment.Center,
    ) {
        Row(
            modifier = GlanceModifier
                .fillMaxWidth()
                .height(HomeLayout.PillHeight)
                .background(container)
                .cornerRadius(HomeLayout.PillHeight / 2),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            if (icon != null) {
                Icon(icon, content, 12.dp)
                Spacer(GlanceModifier.width(6.dp))
            }
            Label(label, 15.sp, content, FontWeight.Medium)
        }
    }
}

/** A rounded square with a glyph (the icon tile of the dark card). */
@Composable
internal fun IconBadge(@DrawableRes icon: Int, container: ColorProvider, tint: ColorProvider, size: Dp = 30.dp, radius: Dp = 8.dp, iconSize: Dp = 17.dp) {
    Box(
        modifier = GlanceModifier.size(size).background(container).cornerRadius(radius),
        contentAlignment = Alignment.Center,
    ) {
        Icon(icon, tint, iconSize)
    }
}

/** A one dp line across the available width. */
@Composable
internal fun HorizontalRule(modifier: GlanceModifier = GlanceModifier, color: ColorProvider = HomeColors.separator) {
    Box(modifier = modifier.fillMaxWidth().height(1.dp).background(color)) {}
}

/** A horizontal meter: [fraction] (0...1) of [width] in [fill] over [track]; a non-zero fraction is at least as wide as the bar is high. */
@Composable
internal fun Meter(width: Dp, height: Dp, fraction: Float, fill: ColorProvider, track: ColorProvider) {
    Box(modifier = GlanceModifier.width(width).height(height).background(track).cornerRadius(height / 2)) {
        if (fraction > 0f) {
            Box(
                modifier = GlanceModifier
                    .width(maxOf(height, width * fraction.coerceAtMost(1f)))
                    .height(height)
                    .background(fill)
                    .cornerRadius(height / 2),
            ) {}
        }
    }
}

/** Draws [parts] one over the other into a new mask, so a chart that needs one tint costs one bitmap in the widget. */
internal fun mergeMasks(vararg parts: Bitmap): Bitmap {
    val first = parts.first()
    val merged = createBitmap(first.width, first.height)
    val canvas = Canvas(merged)
    parts.forEach { canvas.drawBitmap(it, 0f, 0f, null) }
    return merged
}

/** The glyph resources of the widgets of this folder, named once (resource ids are not compile-time constants since AGP 8). */
internal object HomeIcons {
    val Play = R.drawable.ic_home_play
    val Trophy = R.drawable.ic_home_trophy
    val Dumbbell = R.drawable.ic_home_dumbbell
    val Plus = R.drawable.ic_home_plus
    val Check = R.drawable.ic_home_check
    val Close = R.drawable.ic_home_close
}
