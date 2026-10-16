package health.pulse.strength.widgets.extras

import android.os.SystemClock
import android.util.TypedValue
import android.widget.RemoteViews
import androidx.annotation.DrawableRes
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceModifier
import androidx.glance.GlanceTheme
import androidx.glance.LocalContext
import androidx.glance.action.Action
import androidx.glance.action.clickable
import androidx.glance.appwidget.AndroidRemoteViews
import androidx.glance.appwidget.cornerRadius
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.size
import androidx.glance.layout.width
import androidx.glance.semantics.contentDescription
import androidx.glance.semantics.semantics
import androidx.glance.text.FontWeight
import androidx.glance.text.TextAlign
import androidx.glance.unit.ColorProvider
import health.pulse.strength.R
import health.pulse.strength.core.widgets.TimelineKind
import health.pulse.strength.core.widgets.TrendStatus
import health.pulse.strength.widgets.common.PulseColors
import health.pulse.strength.widgets.common.dayNight
import health.pulse.strength.widgets.lock.FitSafety
import health.pulse.strength.widgets.lock.Glyph
import health.pulse.strength.widgets.lock.PulseText
import health.pulse.strength.widgets.lock.TextFit
import health.pulse.strength.widgets.lock.rememberTextMeter

/** Colours the theme does not carry: heat levels, plates, timeline stretches, status. Each is a light/dark pair the launcher resolves live. */
internal object ExtrasPalette {
    val track = dayNight(Color(0xFFE5E5EA), Color(0xFF3A3A3C))
    val trackStrong = dayNight(Color(0xFFC7C7CC), Color(0xFF636366))
    val stepperButton = dayNight(Color.White, Color(0xFF3A3A3C))
    val iron = dayNight(Color(0xFF8E8E93), Color(0xFF636366))
    val blueText = dayNight(Color(0xFF0057B8), Color(0xFF64D2FF))
    val risingText = dayNight(Color(0xFF146638), Color(0xFF30D158))
    val flatText = dayNight(PulseColors.GoldText, PulseColors.GoldTextDark)
    val fallingText = dayNight(Color(0xFFD70015), Color(0xFFFF453A))
    private val good = dayNight(PulseColors.Ready, Color(0xFF30D158))
    private val fair = dayNight(PulseColors.Recovering, Color(0xFFFFD60A))
    private val low = dayNight(PulseColors.Worked, Color(0xFFFF453A))

    /** The four steps of the body map: untouched, light, medium, high. */
    fun heat(level: Int): ColorProvider = when (level) {
        1 -> dayNight(Color(0xFFB9E7C8), Color(0xFF1E5A34))
        2 -> dayNight(Color(0xFF5BC783), Color(0xFF2F9B55))
        3 -> dayNight(Color(0xFF1B8448), Color(0xFF30D158))
        else -> track
    }

    fun plate(color: PlateColor): ColorProvider = when (color) {
        PlateColor.RED -> dayNight(Color(0xFFD70015), Color(0xFFFF453A))
        PlateColor.BLUE -> dayNight(PulseColors.BlueLight, PulseColors.BlueDark)
        PlateColor.YELLOW -> dayNight(PulseColors.Gold, Color(0xFFFFD60A))
        PlateColor.GREEN -> dayNight(PulseColors.GreenLight, PulseColors.GreenDark)
        PlateColor.WHITE -> dayNight(Color(0xFF8E8E93), Color(0xFFC7C7CC))
    }

    fun timeline(kind: TimelineKind): ColorProvider = when (kind) {
        TimelineKind.LIFTING -> dayNight(PulseColors.GreenLight, PulseColors.GreenDark)
        TimelineKind.REST -> track
        TimelineKind.LONG_REST -> dayNight(PulseColors.Recovering, Color(0xFFFFD60A))
    }

    fun tier(tier: ReadinessTier?): ColorProvider = when (tier) {
        ReadinessTier.GOOD -> good
        ReadinessTier.FAIR -> fair
        ReadinessTier.LOW -> low
        null -> track
    }

    /** The dot in front of a lift on the plateau watch. */
    fun trend(status: TrendStatus): ColorProvider = when (status) {
        TrendStatus.RISING -> good
        TrendStatus.FLAT -> fair
        TrendStatus.FALLING -> low
    }

    /** The word after it ("rising", "flat 3×"), in a shade that is legible as text on the card. */
    fun trendText(status: TrendStatus): ColorProvider = when (status) {
        TrendStatus.RISING -> risingText
        TrendStatus.FLAT -> flatText
        TrendStatus.FALLING -> fallingText
    }

    fun dot(state: DotState): ColorProvider = when (state) {
        DotState.DONE -> dayNight(PulseColors.ProgressLight, PulseColors.ProgressDark)
        DotState.CURRENT -> trackStrong
        DotState.PENDING -> track
    }
}

/** The dark "Year in iron" card keeps its look in light mode too, as on the canvas. */
internal object IronCard {
    val background: ColorProvider = ColorProvider(Color(0xFF1C1C1E))
    val text: ColorProvider = ColorProvider(Color.White)
    val secondary: ColorProvider = ColorProvider(Color(0xFF98989D))
    val accent: ColorProvider = ColorProvider(Color(0xFF30D158))

    /**
     * The accent at half strength on the card, worked out as an opaque colour: a mask is tinted by blending the tint over it, so a
     * translucent tint would come out lighter than the accent instead of dimmer.
     */
    val dimAccent: ColorProvider = ColorProvider(Color(0xFF266E3B))
}

/**
 * A pill-shaped button at least 48 dp high. With an [action] the pill itself is the tap target; with null it only looks like a button
 * (the card around it is the tap target, as in the rest-day widget). [description] is what a screen reader says.
 */
@Composable
internal fun PillButton(
    label: String,
    action: Action?,
    modifier: GlanceModifier = GlanceModifier,
    fill: ColorProvider = GlanceTheme.colors.primary,
    textColor: ColorProvider = GlanceTheme.colors.onPrimary,
    height: Dp = 48.dp,
    @DrawableRes icon: Int? = null,
    description: String = label,
) {
    val tappable = if (action != null) GlanceModifier.semantics { contentDescription = description }.clickable(action) else GlanceModifier
    Box(
        modifier = modifier.height(height).cornerRadius(height / 2).background(fill).then(tappable),
        contentAlignment = Alignment.Center,
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            if (icon != null) {
                Glyph(icon, 12.dp, textColor)
                Spacer(GlanceModifier.width(6.dp))
            }
            PulseText(label, 16.sp, weight = FontWeight.Medium, color = textColor, align = TextAlign.Center)
        }
    }
}

/**
 * "− 82.5 kg +": a value between two round buttons, each a full 48 dp tap target, in a pill of [width]. When the unit does not fit
 * between the buttons the bare number is shown.
 */
@Composable
internal fun StepperPill(view: StepperView, less: Action, more: Action, width: Dp, modifier: GlanceModifier = GlanceModifier) {
    val valueWidth = width - STEP_BUTTON * 2 - FitSafety
    val label = TextFit.firstFitting(listOf(view.label, view.shortLabel), valueWidth.value, rememberTextMeter(16.sp, bold = true))
    Row(
        modifier = modifier.width(width).height(48.dp).cornerRadius(24.dp).background(GlanceTheme.colors.surfaceVariant),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        StepButton("−", view.lessDescription, less)
        Box(modifier = GlanceModifier.defaultWeight(), contentAlignment = Alignment.Center) {
            PulseText(label, 16.sp, weight = FontWeight.Bold, align = TextAlign.Center)
        }
        StepButton("+", view.moreDescription, more)
    }
}

/** The width of one of a stepper's buttons: the minimum tap target. */
internal val STEP_BUTTON = 48.dp

@Composable
private fun StepButton(glyph: String, description: String, action: Action) {
    Box(
        modifier = GlanceModifier.size(STEP_BUTTON).semantics { contentDescription = description }.clickable(action),
        contentAlignment = Alignment.Center,
    ) {
        Box(
            modifier = GlanceModifier.size(40.dp).cornerRadius(20.dp).background(ExtrasPalette.stepperButton),
            contentAlignment = Alignment.Center,
        ) {
            PulseText(glyph, 20.sp, weight = FontWeight.Medium, align = TextAlign.Center)
        }
    }
}

/** A filled circle with a short [label] (initials, or "You") inside. */
@Composable
internal fun Avatar(label: String, fill: ColorProvider, textColor: ColorProvider, size: Dp = 30.dp) {
    Box(modifier = GlanceModifier.size(size).cornerRadius(size / 2).background(fill), contentAlignment = Alignment.Center) {
        PulseText(label, 12.sp, weight = FontWeight.Bold, color = textColor, align = TextAlign.Center)
    }
}

/** A small filled circle; the word next to it carries the meaning, the colour only repeats it. */
@Composable
internal fun StatusDot(color: ColorProvider, size: Dp = 10.dp) {
    Box(modifier = GlanceModifier.size(size).cornerRadius(size / 2).background(color)) {}
}

/**
 * One short bar of [dotWidth] per set of the exercise: logged, the one to log now, still to come. The gap is padding around each bar, not
 * a spacer between them: Glance draws at most ten children per row, and ten bars with their gaps would be nineteen.
 */
@Composable
internal fun SetDots(dots: List<DotState>, dotWidth: Dp) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        for (state in dots) {
            Box(modifier = GlanceModifier.padding(end = DOT_GAP)) {
                Box(modifier = GlanceModifier.size(dotWidth, 6.dp).cornerRadius(3.dp).background(ExtrasPalette.dot(state))) {}
            }
        }
    }
}

/** The gap after each set dot. */
internal val DOT_GAP = LogSetModel.DOT_GAP_DP.dp

/**
 * The rest countdown as a system `Chronometer`: the launcher redraws it every second without the app running, so the widget needs no
 * updates while resting. Glance cannot host a `Chronometer` itself, so it is embedded as a remote layout (`widget_rest_chronometer`).
 * The base is `elapsedRealtime` plus the time that is left, because a chronometer counting down reads `base - now`.
 */
@Composable
internal fun RestCountdown(remainingMillis: Long, textSizeSp: Float, modifier: GlanceModifier = GlanceModifier) {
    val views = RemoteViews(LocalContext.current.packageName, R.layout.widget_rest_chronometer)
    views.setTextViewTextSize(R.id.rest_chronometer, TypedValue.COMPLEX_UNIT_SP, textSizeSp)
    views.setChronometerCountDown(R.id.rest_chronometer, true)
    views.setChronometer(R.id.rest_chronometer, SystemClock.elapsedRealtime() + remainingMillis, null, true)
    AndroidRemoteViews(remoteViews = views, modifier = modifier)
}
