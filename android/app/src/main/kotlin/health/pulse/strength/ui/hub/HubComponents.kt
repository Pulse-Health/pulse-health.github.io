package health.pulse.strength.ui.hub

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.layout.sizeIn
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.rounded.ChevronRight
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import health.pulse.strength.ui.theme.PulseFont
import health.pulse.strength.ui.theme.PulseMetrics
import health.pulse.strength.ui.theme.PulseTheme
import health.pulse.strength.ui.theme.pulseClickable
import kotlin.math.max

// Small building blocks of the hub screens (the "Small building blocks" part of StrengthHubView.swift).

/** True once the user chose a larger font than the default: one-line texts may then wrap (hubLineLimit(1, whenLarger:) of the iOS hub). */
@Composable
internal fun isLargerText(): Boolean = LocalDensity.current.fontScale > 1.05f

/** True at the largest font sizes (the iOS "accessibility sizes"): side-by-side columns are stacked, one figure per line. */
@Composable
internal fun isAccessibilityText(): Boolean = LocalDensity.current.fontScale >= 1.5f

/** The line limit of a text that stays on one line at the default size but may wrap at larger sizes ([maxLarger] null = no limit). */
@Composable
internal fun lineLimit(maxLarger: Int? = null): Int = if (isLargerText()) maxLarger ?: Int.MAX_VALUE else 1

/** A design size in dp that grows with the font size, like `@PulseScaled` (ring, dots next to text). */
@Composable
internal fun fontScaledDp(design: Float): Dp = with(LocalDensity.current) { design.sp.toDp() }

internal val HubRowShape = RoundedCornerShape(12.dp)
internal val HubIconShape = RoundedCornerShape(8.dp)

/** White 12 dp row / card background of the hub lists. */
@Composable
internal fun Modifier.hubRowBackground(): Modifier = this.background(PulseTheme.colors.card, HubRowShape)

/** The shape of row [index] of [count] in one grouped card: only the outer corners of the first and last row are round. */
internal fun groupedShape(index: Int, count: Int, radius: Dp = 12.dp): Shape = RoundedCornerShape(
    topStart = if (index == 0) radius else 0.dp,
    topEnd = if (index == 0) radius else 0.dp,
    bottomStart = if (index == count - 1) radius else 0.dp,
    bottomEnd = if (index == count - 1) radius else 0.dp,
)

/** The thickness of a hairline: half a dp, never thinner than one pixel (`Dp.Hairline` only means something to borders). */
@Composable
internal fun hairline(): Dp = with(LocalDensity.current) { maxOf(0.5.dp, 1.toDp()) }

/** The hairline between two rows (not drawn above the first row of a list); [inset] keeps it clear of the thumbnail. */
@Composable
internal fun HubDivider(modifier: Modifier = Modifier, inset: Dp = 0.dp) {
    Box(modifier.fillMaxWidth().padding(start = inset).height(hairline()).background(PulseTheme.colors.separator))
}

/** A text that is shrunk, down to [minScale] of its size, until it fits one line (SwiftUI `minimumScaleFactor`). */
@Composable
internal fun ShrinkToFitText(
    text: String,
    style: TextStyle,
    color: Color,
    modifier: Modifier = Modifier,
    minScale: Float = 0.7f,
) {
    var scale by remember(text, style) { mutableFloatStateOf(1f) }
    Text(
        text = text,
        modifier = modifier,
        color = color,
        style = style.copy(fontSize = style.fontSize * scale),
        maxLines = 1,
        softWrap = false,
        overflow = if (scale <= minScale) TextOverflow.Ellipsis else TextOverflow.Clip,
        onTextLayout = { layout ->
            if (layout.didOverflowWidth && scale > minScale) scale = max(minScale, scale * 0.92f)
        },
    )
}

/**
 * A section title with an optional action ("See All") at the trailing edge. At the largest font sizes the action moves under the
 * title (two long texts do not fit one line). The row is 48 dp tall when it has an action, so the action is an easy target.
 */
@Composable
internal fun HubSectionHeader(
    title: String,
    modifier: Modifier = Modifier,
    actionTitle: String? = null,
    onAction: () -> Unit = {},
) {
    val colors = PulseTheme.colors
    val titleText: @Composable (Modifier) -> Unit = { titleModifier ->
        Text(
            title,
            modifier = titleModifier.semantics { heading() },
            style = PulseFont.headline,
            color = colors.ink,
        )
    }
    val action: @Composable () -> Unit = {
        if (actionTitle != null) {
            Box(
                Modifier
                    .sizeIn(minWidth = 48.dp, minHeight = 48.dp)
                    .pulseClickable(onClick = onAction)
                    // Two buttons that both read "See All" are ambiguous for a screen reader: name the section too.
                    .semantics { contentDescription = "$actionTitle $title" },
                contentAlignment = if (isAccessibilityText()) Alignment.CenterStart else Alignment.CenterEnd,
            ) {
                Text(actionTitle, style = PulseFont.footnote, color = colors.blueText)
            }
        }
    }
    if (isAccessibilityText()) {
        Column(modifier.fillMaxWidth()) {
            titleText(Modifier.fillMaxWidth().padding(top = 4.dp, bottom = if (actionTitle == null) 12.dp else 4.dp))
            if (actionTitle != null) Box(Modifier.align(Alignment.Start)) { action() }
        }
    } else {
        Row(
            modifier.fillMaxWidth().heightIn(min = if (actionTitle != null) 48.dp else 24.dp).padding(bottom = if (actionTitle != null) 0.dp else 12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            titleText(Modifier.weight(1f))
            action()
        }
    }
}

/** Keeps a top bar clear of the status bar and of display cutouts at the sides. */
@Composable
internal fun Modifier.hubTopInsets(): Modifier =
    this.windowInsetsPadding(WindowInsets.safeDrawing.only(WindowInsetsSides.Top + WindowInsetsSides.Horizontal))

/** The 32 dp rounded square behind a row's glyph. */
@Composable
internal fun HubIconBox(fill: Color, modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    Box(modifier.size(32.dp).background(fill, HubIconShape), contentAlignment = Alignment.Center) { content() }
}

@Composable
internal fun HubChevron(modifier: Modifier = Modifier) {
    Icon(
        imageVector = Icons.Rounded.ChevronRight,
        contentDescription = null,
        modifier = modifier.size(22.dp),
        tint = PulseTheme.colors.inkTertiary,
    )
}

/** A 6 dp progress bar on the grey track. */
@Composable
internal fun HubBar(fraction: Double, color: Color, modifier: Modifier = Modifier) {
    val colors = PulseTheme.colors
    Box(modifier.fillMaxWidth().height(6.dp).background(colors.progressTrack, CircleShape)) {
        Box(
            Modifier
                .fillMaxWidth(fraction.coerceIn(0.0, 1.0).toFloat())
                .fillMaxHeight()
                .background(color, CircleShape),
        )
    }
}

internal class HubStat(val title: String, val value: String)

/**
 * One row of figures: small caption over a 20 sp value, thin dividers between the columns. At the largest font sizes the columns
 * no longer fit side by side and are stacked, one figure per line.
 */
@Composable
internal fun HubStatRow(stats: List<HubStat>, modifier: Modifier = Modifier) {
    if (isAccessibilityText()) {
        Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            for (stat in stats) HubStatColumn(stat, showsDivider = false, Modifier.fillMaxWidth())
        }
    } else {
        Row(modifier.fillMaxWidth().height(IntrinsicSize.Min), horizontalArrangement = Arrangement.spacedBy(16.dp)) {
            for ((index, stat) in stats.withIndex()) HubStatColumn(stat, showsDivider = index > 0, Modifier.weight(1f))
        }
    }
}

@Composable
private fun HubStatColumn(stat: HubStat, showsDivider: Boolean, modifier: Modifier) {
    val colors = PulseTheme.colors
    Box(modifier.semantics(mergeDescendants = true) {}) {
        if (showsDivider) {
            Box(
                Modifier
                    .align(Alignment.CenterStart)
                    .offset(x = (-8).dp)
                    .width(hairline())
                    .fillMaxHeight()
                    .background(colors.separator),
            )
        }
        Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(
                stat.title,
                style = PulseFont.footnote,
                color = colors.inkSecondary,
                maxLines = if (isLargerText()) 2 else 1,
                overflow = TextOverflow.Ellipsis,
            )
            ShrinkToFitText(
                text = stat.value,
                style = PulseFont.number(20.sp, FontWeight.SemiBold),
                color = colors.ink,
                minScale = 0.7f,
            )
        }
    }
}

/** A short centred message ("This template is no longer available.", "Finished workouts appear here."). */
@Composable
internal fun HubMessage(text: String, modifier: Modifier = Modifier) {
    Text(
        text,
        modifier = modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 24.dp),
        style = PulseFont.subhead,
        color = PulseTheme.colors.inkSecondary,
    )
}

/**
 * The top bar of a pushed screen: back arrow, the title (wraps to a second line instead of being cut off at larger font sizes) and
 * the [actions] at the trailing edge. It stays clear of the status bar and display cutouts.
 */
@Composable
internal fun HubTopBar(
    title: String,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
    actions: @Composable RowScope.() -> Unit = {},
) {
    val colors = PulseTheme.colors
    Row(
        modifier
            .fillMaxWidth()
            .background(colors.ground)
            .hubTopInsets()
            .heightIn(min = 56.dp)
            .padding(horizontal = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        IconButton(onClick = onBack) {
            Icon(Icons.AutoMirrored.Rounded.ArrowBack, contentDescription = "Back", tint = colors.ink)
        }
        Text(
            title,
            modifier = Modifier.weight(1f).padding(horizontal = 4.dp).semantics { heading() },
            style = PulseFont.text(20.sp, FontWeight.SemiBold),
            color = colors.ink,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
        )
        actions()
    }
}

/**
 * The page gutter of a content column that is at most [PulseMetrics.maxContentWidth] wide and centred: the list or scroll area itself
 * spans the window (so it scrolls from every point of it) and this padding keeps the content in the middle.
 */
@Composable
internal fun HubContentBox(
    modifier: Modifier = Modifier,
    maxContentWidth: Dp = PulseMetrics.maxContentWidth,
    content: @Composable (gutter: Dp) -> Unit,
) {
    BoxWithConstraints(modifier) {
        val gutter = ((maxWidth - maxContentWidth) / 2).coerceAtLeast(PulseMetrics.screenInset)
        content(gutter)
    }
}

/**
 * The insets of a [HubScreenFrame] as a modifier for its scrolling content: the top bar and the sides, but not the bottom. The bottom
 * inset (navigation bar, keyboard) goes into the scroll area's own padding ([hubBottomPadding]), so the content can scroll under a
 * transparent navigation bar and still end above it.
 */
internal fun Modifier.hubScreenPadding(inner: PaddingValues): Modifier = this.padding(WithoutBottom(inner))

private class WithoutBottom(private val base: PaddingValues) : PaddingValues {
    override fun calculateLeftPadding(layoutDirection: LayoutDirection): Dp = base.calculateLeftPadding(layoutDirection)
    override fun calculateTopPadding(): Dp = base.calculateTopPadding()
    override fun calculateRightPadding(layoutDirection: LayoutDirection): Dp = base.calculateRightPadding(layoutDirection)
    override fun calculateBottomPadding(): Dp = 0.dp
}

/** The padding below the last item of a screen: the design's 24 dp plus the bottom inset of the frame. */
internal fun hubBottomPadding(inner: PaddingValues): Dp = 24.dp + inner.calculateBottomPadding()

internal fun hubContentPadding(gutter: Dp, top: Dp = 8.dp, bottom: Dp = 24.dp): PaddingValues =
    PaddingValues(start = gutter, end = gutter, top = top, bottom = bottom)

/** A search field in the grey capsule of the system search bars. */
@Composable
internal fun HubSearchField(
    value: String,
    onValueChange: (String) -> Unit,
    modifier: Modifier = Modifier,
    placeholder: String = "Search exercises",
) {
    val colors = PulseTheme.colors
    val focusManager = LocalFocusManager.current
    TextField(
        value = value,
        onValueChange = onValueChange,
        modifier = modifier.fillMaxWidth(),
        singleLine = true,
        shape = RoundedCornerShape(12.dp),
        textStyle = PulseFont.body,
        placeholder = { Text(placeholder, style = PulseFont.body, color = colors.inkSecondary) },
        leadingIcon = { Icon(Icons.Rounded.Search, contentDescription = null, tint = colors.inkSecondary) },
        trailingIcon = {
            if (value.isNotEmpty()) {
                IconButton(onClick = { onValueChange("") }) {
                    Icon(Icons.Rounded.Close, contentDescription = "Clear search", tint = colors.inkSecondary)
                }
            }
        },
        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
        keyboardActions = KeyboardActions(onSearch = { focusManager.clearFocus() }),
        colors = TextFieldDefaults.colors(
            focusedContainerColor = colors.chipFill,
            unfocusedContainerColor = colors.chipFill,
            disabledContainerColor = colors.chipFill,
            focusedIndicatorColor = Color.Transparent,
            unfocusedIndicatorColor = Color.Transparent,
            disabledIndicatorColor = Color.Transparent,
            focusedTextColor = colors.ink,
            unfocusedTextColor = colors.ink,
            cursorColor = colors.green,
        ),
    )
}

/** Space between the sections of the hub's home screen. */
internal val HubSectionSpacing = 20.dp

/** A wide-window content width: the width of one of the two hub columns. */
internal val HubColumnMaxWidth = 560.dp

/** Whether a window is wide enough for the home screen's two columns (a tablet or a phone in landscape). */
internal const val HUB_TWO_COLUMN_MIN_WIDTH_DP = 840

/**
 * The frame of a pushed screen: the top bar (back arrow, title, [actions]), an optional [bottomBar] and the grey ground. The content
 * receives the insets (status bar, display cutouts, keyboard) as padding and must apply them.
 */
@Composable
internal fun HubScreenFrame(
    title: String,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
    actions: @Composable RowScope.() -> Unit = {},
    bottomBar: @Composable () -> Unit = {},
    content: @Composable (PaddingValues) -> Unit,
) {
    Scaffold(
        modifier = modifier,
        containerColor = PulseTheme.colors.ground,
        contentWindowInsets = WindowInsets.safeDrawing,
        topBar = { HubTopBar(title = title, onBack = onBack, actions = actions) },
        bottomBar = bottomBar,
        content = content,
    )
}

/** A pinned bar at the bottom of a screen (the template's Start button), centred and clear of the navigation bar. */
@Composable
internal fun HubBottomBar(content: @Composable () -> Unit) {
    Box(
        Modifier
            .fillMaxWidth()
            .background(PulseTheme.colors.ground)
            .windowInsetsPadding(WindowInsets.safeDrawing.only(WindowInsetsSides.Bottom + WindowInsetsSides.Horizontal))
            .padding(horizontal = PulseMetrics.screenInset, vertical = 8.dp),
        contentAlignment = Alignment.Center,
    ) { content() }
}
