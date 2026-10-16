package health.pulse.strength.ui.sheets

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.ModalBottomSheetProperties
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import health.pulse.strength.ui.theme.PulseFont
import health.pulse.strength.ui.theme.PulseMetrics
import health.pulse.strength.ui.theme.PulseTheme
import health.pulse.strength.ui.theme.pulseClickable
import health.pulse.strength.ui.theme.pulseMinHeight
import kotlinx.coroutines.launch

// Shared pieces of the workout sheets: the modal bottom sheet shell, the 56 dp title bar, section labels, the segmented control with
// spoken labels. The sheets themselves are split into a window part (the `...Sheet` composable the screens call) and a `...Content`
// composable that holds everything inside the window, so it can be rendered and checked without one.

/** Top corners of every sheet (the design's 26 dp). */
internal val SheetShape = RoundedCornerShape(topStart = PulseMetrics.sheetRadius, topEnd = PulseMetrics.sheetRadius)

/** True from the "largest" system font size on: the title bars stack their buttons above the title. */
@Composable
@ReadOnlyComposable
internal fun isAccessibilityFontScale(): Boolean = LocalDensity.current.fontScale >= 1.3f

/** True above the default font size (iOS `dynamicTypeSize > .large`): single lines may take a second one. */
@Composable
@ReadOnlyComposable
internal fun isLargerFontScale(): Boolean = LocalDensity.current.fontScale > 1.05f

/** A design size that grows with the user's font size (iOS `@PulseScaled`): the design value at the default font size. */
@Composable
@ReadOnlyComposable
internal fun Dp.scaledWithFont(maxScale: Float = 1.6f): Dp = this * LocalDensity.current.fontScale.coerceIn(1f, maxScale)

/**
 * The modal bottom sheet shell of every workout sheet: 26 dp top corners, the grouped-grey ground, a compact drag handle, at most
 * [PulseMetrics.maxContentWidth] wide (centred on wide windows) and edge-to-edge (the body pads itself with the navigation bar and
 * keyboard insets and stays below the status bar). [content] receives `dismiss`, which slides the sheet away and then calls
 * [onDismiss]; system back, a tap on the scrim and a swipe down call [onDismiss] too (unless [dismissOnBack] is off: the content
 * handles back itself).
 *
 * [fullHeight] sheets (lists, forms) take the whole window below the status bar; the others are as tall as their content and
 * their content scrolls when the window is short.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun PulseSheet(
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier,
    fullHeight: Boolean = false,
    gesturesEnabled: Boolean = true,
    dismissOnBack: Boolean = true,
    content: @Composable (dismiss: () -> Unit) -> Unit,
) {
    val colors = PulseTheme.colors
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val scope = rememberCoroutineScope()
    val currentOnDismiss by rememberUpdatedState(onDismiss)
    var dismissing by remember { mutableStateOf(false) }
    val dismiss: () -> Unit = remember(sheetState, scope) {
        {
            if (!dismissing) {
                dismissing = true
                scope.launch { sheetState.hide() }.invokeOnCompletion { currentOnDismiss() }
            }
        }
    }
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        modifier = modifier,
        sheetState = sheetState,
        sheetMaxWidth = PulseMetrics.maxContentWidth,
        sheetGesturesEnabled = gesturesEnabled,
        shape = SheetShape,
        containerColor = colors.ground,
        contentColor = colors.ink,
        tonalElevation = 0.dp,
        dragHandle = { SheetHandle() },
        // The body applies the insets itself (see SheetBody), so the sheet must not pad its content as well.
        contentWindowInsets = { WindowInsets(0.dp) },
        properties = ModalBottomSheetProperties(shouldDismissOnBackPress = dismissOnBack),
    ) {
        SheetBody(fullHeight = fullHeight) { content(dismiss) }
    }
}

/** The grabber at the top of a sheet: smaller than the Material default (48 dp) because the title bar brings its own space. */
@Composable
internal fun SheetHandle() {
    Box(Modifier.padding(top = 10.dp, bottom = 2.dp)) {
        Box(Modifier.size(width = 32.dp, height = 4.dp).background(PulseTheme.colors.inkTertiary.copy(alpha = 0.55f), CircleShape))
    }
}

/**
 * The content area of a sheet. It leaves the system bars alone: the bottom (navigation bar, keyboard) and side insets become
 * padding, the status bar becomes a limit for the height, so a tall sheet never slides under it. Full height sheets fill that
 * limit, the others wrap their content up to it. The insets are consumed, so nested screens do not apply them a second time.
 */
@Composable
internal fun SheetBody(fullHeight: Boolean, content: @Composable ColumnScope.() -> Unit) {
    val topInset = WindowInsets.statusBars.asPaddingValues().calculateTopPadding()
    BoxWithConstraints(
        Modifier
            .fillMaxWidth()
            .windowInsetsPadding(WindowInsets.safeDrawing.only(WindowInsetsSides.Horizontal + WindowInsetsSides.Bottom))
            .consumeWindowInsets(WindowInsets.safeDrawing.only(WindowInsetsSides.Top)),
    ) {
        val limit = (maxHeight - topInset - SheetTopGap).coerceAtLeast(160.dp)
        Column(
            Modifier
                .fillMaxWidth()
                .then(if (fullHeight) Modifier.height(limit) else Modifier.heightIn(max = limit)),
            content = content,
        )
    }
}

/** What stays visible of the screen behind a sheet that takes the whole height. */
private val SheetTopGap = 8.dp

/** A text button of a title bar ("Done", "Cancel", "Save"). */
internal class SheetBarButton(val title: String, val semibold: Boolean = true, val onClick: () -> Unit)

/**
 * The 56 dp title bar of the sheets: the title centred with a green text button at each side. From the largest font sizes on the
 * buttons sit on one line and the title (any number of lines) under them, so nothing overlaps.
 */
@Composable
internal fun SheetTitleBar(
    title: String,
    modifier: Modifier = Modifier,
    leading: SheetBarButton? = null,
    trailing: SheetBarButton? = null,
) {
    val colors = PulseTheme.colors
    if (isAccessibilityFontScale()) {
        Column(
            modifier
                .fillMaxWidth()
                .heightIn(min = 56.dp)
                .padding(start = 16.dp, end = 16.dp, bottom = 8.dp),
        ) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                if (leading != null) SheetBarTextButton(leading, Alignment.CenterStart)
                Spacer(Modifier.weight(1f))
                if (trailing != null) SheetBarTextButton(trailing, Alignment.CenterEnd)
            }
            Text(
                title,
                style = PulseFont.headline,
                color = colors.ink,
                textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth().semantics { heading() },
            )
        }
    } else {
        Box(
            modifier
                .fillMaxWidth()
                .heightIn(min = 56.dp)
                .padding(horizontal = 16.dp),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                title,
                style = PulseFont.headline,
                color = colors.ink,
                textAlign = TextAlign.Center,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier
                    .padding(horizontal = if (leading != null) 88.dp else 72.dp, vertical = 4.dp)
                    .semantics { heading() },
            )
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                if (leading != null) SheetBarTextButton(leading, Alignment.CenterStart)
                Spacer(Modifier.weight(1f))
                if (trailing != null) SheetBarTextButton(trailing, Alignment.CenterEnd)
            }
        }
    }
}

@Composable
private fun SheetBarTextButton(button: SheetBarButton, alignment: Alignment) {
    Box(
        Modifier
            .defaultMinSize(minWidth = 48.dp, minHeight = 48.dp)
            .pulseClickable(role = Role.Button, onClick = button.onClick),
        contentAlignment = alignment,
    ) {
        Text(
            button.title,
            style = PulseFont.text(17.sp, if (button.semibold) FontWeight.SemiBold else FontWeight.Normal),
            color = PulseTheme.colors.greenText,
            maxLines = 1,
        )
    }
}

/** The small grey caption above a group ("Set type", "Reps in reserve", "Name"). */
@Composable
internal fun SheetSectionLabel(text: String, modifier: Modifier = Modifier) {
    Text(
        text,
        style = PulseFont.footnote,
        color = PulseTheme.colors.inkSecondary,
        modifier = modifier.padding(start = 4.dp).semantics { heading() },
    )
}

/** One option of a [SegmentedOptions]: [title] is what is drawn, [spoken] what a screen reader says. */
internal class SegmentOption<T>(val value: T, val title: String, val spoken: String = title)

/**
 * The design's segmented control (a grey track with a raised white thumb on the selected segment) with a screen reader label per
 * segment. [groupLabel] names the group for screen readers. Segments are at least [minHeight] tall (48 dp: a comfortable touch
 * target) and grow with the font size.
 */
@Composable
internal fun <T> SegmentedOptions(
    options: List<SegmentOption<T>>,
    selection: T,
    onSelect: (T) -> Unit,
    groupLabel: String,
    modifier: Modifier = Modifier,
    minHeight: Dp = 48.dp,
    vertical: Boolean = false,
    textStyle: androidx.compose.ui.text.TextStyle = PulseFont.number(15.sp, FontWeight.Medium),
) {
    val colors = PulseTheme.colors
    val segment: @Composable (SegmentOption<T>, Modifier) -> Unit = { option, segmentModifier ->
        val isSelected = option.value == selection
        Box(
            segmentModifier
                .pulseMinHeight(minHeight)
                .then(
                    if (isSelected) {
                        Modifier
                            .shadow(2.dp, RoundedCornerShape(7.dp), clip = false)
                            .background(colors.card, RoundedCornerShape(7.dp))
                    } else {
                        Modifier
                    },
                )
                .semantics {
                    selected = isSelected
                    contentDescription = option.spoken
                }
                .pulseClickable(role = Role.RadioButton, onClick = { onSelect(option.value) })
                .padding(horizontal = 4.dp),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                option.title,
                style = textStyle.copy(fontWeight = if (isSelected) FontWeight.Bold else FontWeight.Medium),
                color = colors.ink,
                textAlign = TextAlign.Center,
            )
        }
    }
    val trackModifier = modifier
        .fillMaxWidth()
        .background(colors.chipFill, RoundedCornerShape(9.dp))
        .padding(2.dp)
        .selectableGroup()
        .semantics { contentDescription = groupLabel }
    if (vertical) {
        Column(trackModifier) { for (option in options) segment(option, Modifier.fillMaxWidth()) }
    } else {
        Row(trackModifier, horizontalArrangement = Arrangement.Start) {
            for (option in options) segment(option, Modifier.weight(1f))
        }
    }
}
