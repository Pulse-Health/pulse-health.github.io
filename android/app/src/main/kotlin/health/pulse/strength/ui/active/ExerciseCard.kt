package health.pulse.strength.ui.active

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.Edit
import androidx.compose.material.icons.rounded.Link
import androidx.compose.material.icons.rounded.OpenInFull
import androidx.compose.material.icons.rounded.Timer
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.isSpecified
import androidx.compose.ui.unit.sp
import health.pulse.strength.core.ActiveWorkoutPresentation
import health.pulse.strength.core.SetRef
import health.pulse.strength.core.WorkoutAction
import health.pulse.strength.ui.ExerciseCardActions
import health.pulse.strength.ui.components.ExerciseMediaView
import health.pulse.strength.ui.components.rememberPulseHaptics
import health.pulse.strength.ui.theme.PulseFont
import health.pulse.strength.ui.theme.PulseMetrics
import health.pulse.strength.ui.theme.PulseTheme
import health.pulse.strength.ui.theme.PulseTintButton
import health.pulse.strength.ui.theme.pulseCard
import health.pulse.strength.ui.theme.pulseClickable
import health.pulse.strength.ui.theme.pulseMinHeight

/** The row area's height when it is not limited (pixels; far more than any list of sets). */
private const val UnlimitedRowsHeight = 1 shl 17

/** Rows that always stay visible in the card before the page scrolls instead of the list (two rows and the gap between them). */
private val MinVisibleRows: Dp = SetRowHeight * 2 + SetRowGap

/**
 * The exercise card of the active-workout screen: media tile, name, recovery, superset pill, options button, set table, "Add Set" /
 * rest chip / note buttons, note field and coach tip.
 *
 * It renders [card] and reports changes through [onAction]; sheets are opened through [actions]. The card hugs its content.
 * [viewportHeight] is the height the page offers it: when the set rows do not fit in that, only the rows scroll (inside the card).
 * When even a couple of rows do not fit (a short window, big text) the card takes its natural height and the page scrolls instead.
 * [Dp.Infinity] means "no limit".
 */
@Composable
internal fun ExerciseCard(
    card: ActiveWorkoutPresentation.Card,
    onAction: (WorkoutAction) -> Unit,
    actions: ExerciseCardActions,
    viewportHeight: Dp,
    modifier: Modifier = Modifier,
) {
    // A new exercise starts with a fresh card (note field closed, list at the top).
    key(card.exerciseID) {
        ExerciseCardContent(card, onAction, actions, viewportHeight, modifier)
    }
}

@Composable
private fun ExerciseCardContent(
    card: ActiveWorkoutPresentation.Card,
    onAction: (WorkoutAction) -> Unit,
    actions: ExerciseCardActions,
    viewportHeight: Dp,
    modifier: Modifier,
) {
    val haptics = rememberPulseHaptics()
    var isNoteOpen by rememberSaveable { mutableStateOf(false) }
    val repsName = if (card.repsColumnTitle.equals("sec", ignoreCase = true)) "seconds" else "reps"

    CardLayout(
        viewportHeight = viewportHeight,
        minRowsHeight = MinVisibleRows,
        modifier = modifier
            .fillMaxWidth()
            .testTag("active-card")
            .pulseCard(),
        top = { CardHeader(card, actions) },
        tableHeader = { SetTableHeader(card.weightColumnTitle, card.repsColumnTitle) },
        rows = {
            SetRowList(
                rows = card.rows,
                repsAccessibilityName = repsName,
                visibilityKey = viewportHeight,
                onToggle = { row ->
                    if (row.isDone) haptics.light() else haptics.medium()
                    onAction(WorkoutAction.ToggleSet(card.exerciseID, row.id))
                },
                onOpenDetail = { row -> actions.openSetDetail(SetRef(card.exerciseID, row.id)) },
                onOpenKeypad = { row, field -> actions.openKeypad(SetRef(card.exerciseID, row.id), field) },
            )
        },
        bottom = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                ControlsRow(
                    card = card,
                    isNoteOpen = isNoteOpen,
                    onAddSet = { onAction(WorkoutAction.AddSet(card.exerciseID)) },
                    onRestSettings = { actions.showRestSettings(card.exerciseID) },
                    onToggleNote = { isNoteOpen = !isNoteOpen },
                )
                if (isNoteOpen) {
                    NoteField(note = card.note, onCommit = { text -> onAction(WorkoutAction.SetNote(card.exerciseID, text)) })
                } else if (card.note.isNotEmpty()) {
                    NoteLine(card.note)
                }
                card.coachTip?.let { tip -> CoachTip(tip, Modifier.testTag("coach-tip")) }
            }
        },
    )
}

// region Layout

/**
 * Stacks the card's four parts (12 dp padding, 10 dp between the parts) and decides how tall the set rows may be: the natural
 * height of the rows, limited to what is left of [viewportHeight] after the other parts, but only while that is at least
 * [minRowsHeight]; otherwise the rows keep their natural height and the page scrolls.
 */
@Composable
private fun CardLayout(
    viewportHeight: Dp,
    minRowsHeight: Dp,
    modifier: Modifier,
    top: @Composable () -> Unit,
    tableHeader: @Composable () -> Unit,
    rows: @Composable () -> Unit,
    bottom: @Composable () -> Unit,
) {
    Layout(contents = listOf(top, tableHeader, rows, bottom), modifier = modifier) { measurables, constraints ->
        val padding = 12.dp.roundToPx()
        val gap = 10.dp.roundToPx()
        val small = SetRowGap.roundToPx()
        val innerWidth = (constraints.maxWidth - 2 * padding).coerceAtLeast(0)
        val fixedWidth = Constraints.fixedWidth(innerWidth)

        val topP = measurables[0].map { it.measure(fixedWidth) }
        val headerP = measurables[1].map { it.measure(fixedWidth) }
        val bottomP = measurables[3].map { it.measure(fixedWidth) }
        val topH = topP.sumOf { it.height }
        val headerH = headerP.sumOf { it.height }
        val bottomH = bottomP.sumOf { it.height }
        val chrome = padding * 2 + topH + gap + headerH + small + gap + bottomH

        // A scroll container refuses an infinite height, so "no limit" is a height no list of sets reaches.
        val rowsMax = if (viewportHeight != Dp.Infinity && viewportHeight.isSpecified) {
            val available = viewportHeight.roundToPx() - chrome
            if (available >= minRowsHeight.roundToPx()) available else UnlimitedRowsHeight
        } else {
            UnlimitedRowsHeight
        }
        val rowsP = measurables[2].map { it.measure(Constraints(minWidth = innerWidth, maxWidth = innerWidth, maxHeight = rowsMax)) }
        val rowsH = rowsP.sumOf { it.height }

        layout(constraints.maxWidth, chrome + rowsH) {
            var y = padding
            topP.forEach { it.placeRelative(padding, y) }
            y += topH + gap
            headerP.forEach { it.placeRelative(padding, y) }
            y += headerH + small
            rowsP.forEach { it.placeRelative(padding, y) }
            y += rowsH + gap
            bottomP.forEach { it.placeRelative(padding, y) }
        }
    }
}

// endregion

// region Header

@Composable
private fun CardHeader(card: ActiveWorkoutPresentation.Card, actions: ExerciseCardActions) {
    Box(Modifier.fillMaxWidth()) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.Top) {
            MediaTile(card, actions)
            TitleBlock(card, Modifier.weight(1f).padding(top = 2.dp, end = 36.dp))
        }
        // The 48 dp button overhangs the header by 8 dp at the top and 10 dp at the trailing edge (as the design's 44 pt one does).
        ActiveTapTarget(
            label = "Exercise options",
            onClick = { actions.showOptions(card.exerciseID) },
            modifier = Modifier.align(Alignment.TopEnd).offset(x = 10.dp, y = (-8).dp),
            tag = "exercise-options",
        ) {
            EllipsisCircleIcon(tint = PulseTheme.colors.green, size = 26.dp)
        }
    }
}

/** The 60 dp demo tile; tapping opens the form & instructions sheet. */
@Composable
private fun MediaTile(card: ActiveWorkoutPresentation.Card, actions: ExerciseCardActions) {
    Box(
        modifier = Modifier
            .size(60.dp)
            .clip(RoundedCornerShape(12.dp))
            .testTag("active-media")
            .pulseClickable(onClick = { actions.showInfo(card.exercise) })
            .semantics { contentDescription = "Show form demo" },
    ) {
        ExerciseMediaView(mediaKey = card.exercise.mediaKey, modifier = Modifier.fillMaxSize(), cornerRadius = 12.dp)
        Box(
            modifier = Modifier
                .align(Alignment.BottomEnd)
                .padding(4.dp)
                .size(18.dp)
                .background(Color.Black.copy(alpha = 0.55f), CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            Icon(Icons.Rounded.OpenInFull, contentDescription = null, tint = Color.White, modifier = Modifier.size(10.dp))
        }
    }
}

@Composable
private fun TitleBlock(card: ActiveWorkoutPresentation.Card, modifier: Modifier) {
    val colors = PulseTheme.colors
    val largeText = isLargeText()
    Column(modifier, verticalArrangement = Arrangement.spacedBy(3.dp)) {
        Text(
            text = card.exercise.name,
            style = PulseFont.text(20.sp, FontWeight.Bold).copy(letterSpacing = 0.2.sp),
            color = colors.ink,
            maxLines = if (largeText) 3 else 2,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.testTag("active-exercise-name"),
        )
        RecoveryLine(card)
        card.supersetLabel?.let { SupersetPill(it) }
    }
}

@Composable
private fun RecoveryLine(card: ActiveWorkoutPresentation.Card) {
    val colors = PulseTheme.colors
    Row(
        modifier = Modifier.semantics(mergeDescendants = true) { },
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalAlignment = Alignment.Top,
    ) {
        Box(
            Modifier
                .padding(top = 6.dp)
                .size(8.dp)
                .background(colors.recoveryColor(card.recoveryLevel), CircleShape),
        )
        Text(
            text = card.exercise.muscle.title + " · " + card.recoveryPercent + "% recovered",
            style = PulseFont.subhead,
            color = colors.inkSecondary,
            maxLines = if (isLargeText()) 2 else 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.testTag("active-recovery"),
        )
    }
}

@Composable
private fun SupersetPill(label: String) {
    val colors = PulseTheme.colors
    Row(
        modifier = Modifier
            .padding(top = 2.dp)
            .background(colors.supersetFill, CircleShape)
            .padding(horizontal = 8.dp, vertical = 3.dp)
            .semantics(mergeDescendants = true) { }
            .testTag("active-superset"),
        horizontalArrangement = Arrangement.spacedBy(5.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(Icons.Rounded.Link, contentDescription = null, tint = colors.blueText, modifier = Modifier.size(14.dp))
        Text(label, style = PulseFont.text(12.sp, FontWeight.SemiBold), color = colors.blueText, maxLines = 1)
    }
}

// endregion

// region Controls, note, tip

/** "Add Set", the rest chip and the note button under the table. */
@Composable
private fun ControlsRow(
    card: ActiveWorkoutPresentation.Card,
    isNoteOpen: Boolean,
    onAddSet: () -> Unit,
    onRestSettings: () -> Unit,
    onToggleNote: () -> Unit,
) {
    val colors = PulseTheme.colors
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
        PulseTintButton(onClick = onAddSet, modifier = Modifier.weight(1f).testTag("add-set")) {
            Icon(Icons.Rounded.Add, contentDescription = null, tint = colors.greenText, modifier = Modifier.size(18.dp))
            Spacer(Modifier.width(6.dp))
            Text("Add Set", style = PulseFont.text(15.sp, FontWeight.SemiBold), color = colors.greenText, maxLines = 2)
        }
        // Timer icon plus the exercise's rest time ("2:30" or "Off"); opens the rest timer settings.
        PulseTintButton(
            onClick = onRestSettings,
            modifier = Modifier
                .testTag("rest-chip")
                .semantics(mergeDescendants = true) {
                    contentDescription = "Rest timer"
                    stateDescription = card.restText
                },
        ) {
            Icon(Icons.Rounded.Timer, contentDescription = null, tint = colors.greenText, modifier = Modifier.size(20.dp))
            Spacer(Modifier.width(6.dp))
            Text(card.restText, style = PulseFont.number(15.sp, FontWeight.SemiBold), color = colors.greenText, maxLines = 1)
        }
        Box(
            modifier = Modifier
                .width(48.dp)
                .pulseMinHeight(48.dp)
                .background(
                    if (isNoteOpen) colors.green.copy(alpha = 0.16f) else colors.cellFill,
                    RoundedCornerShape(PulseMetrics.rowRadius),
                )
                .testTag("note-button")
                .pulseClickable(onClick = onToggleNote)
                .semantics {
                    contentDescription = "Exercise note"
                    selected = isNoteOpen
                },
            contentAlignment = Alignment.Center,
        ) {
            Icon(Icons.Rounded.Edit, contentDescription = null, tint = colors.greenText, modifier = Modifier.size(20.dp))
        }
    }
}

/**
 * The note text field (48 dp tall, 10 dp radius). The text is kept locally while typing and written to the workout on "Done", when
 * the field loses focus and when it goes away (exercise change, pencil toggle).
 */
@Composable
private fun NoteField(note: String, onCommit: (String) -> Unit) {
    val colors = PulseTheme.colors
    val focusManager = LocalFocusManager.current
    val focusRequester = remember { FocusRequester() }
    var draft by rememberSaveable { mutableStateOf(note) }
    var committed by remember { mutableStateOf(note) }
    var focused by remember { mutableStateOf(false) }
    val commit by rememberUpdatedState {
        if (draft != committed) {
            committed = draft
            onCommit(draft)
        }
    }

    // The workout's note changed from outside (not by this field): adopt it unless the user is typing.
    LaunchedEffect(note) {
        if (note == draft) {
            committed = note
        } else if (!focused) {
            draft = note
            committed = note
        }
    }
    LaunchedEffect(Unit) { focusRequester.requestFocus() }
    DisposableEffect(Unit) { onDispose { commit() } }

    BasicTextField(
        value = draft,
        onValueChange = { draft = it },
        singleLine = true,
        textStyle = PulseFont.body.copy(color = colors.ink),
        cursorBrush = SolidColor(colors.green),
        keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences, imeAction = ImeAction.Done),
        keyboardActions = KeyboardActions(onDone = {
            commit()
            focusManager.clearFocus()
        }),
        modifier = Modifier
            .fillMaxWidth()
            .focusRequester(focusRequester)
            .onFocusChanged { state ->
                if (focused && !state.isFocused) commit()
                focused = state.isFocused
            }
            .testTag("note-field")
            .semantics { contentDescription = "Exercise note" },
        decorationBox = { inner ->
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .pulseMinHeight(48.dp)
                    .background(colors.cellFill, RoundedCornerShape(PulseMetrics.rowRadius))
                    .padding(horizontal = 12.dp),
                contentAlignment = Alignment.CenterStart,
            ) {
                if (draft.isEmpty()) {
                    Text("Add a note, e.g. seat height 4", style = PulseFont.body, color = colors.inkTertiary, maxLines = 1)
                }
                inner()
            }
        },
    )
}

/** The saved note shown under the buttons while the text field is closed. */
@Composable
private fun NoteLine(text: String) {
    val colors = PulseTheme.colors
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 2.dp)
            .testTag("note-line")
            .semantics(mergeDescendants = true) { contentDescription = "Note: $text" },
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.Top,
    ) {
        Icon(Icons.Rounded.Edit, contentDescription = null, tint = colors.inkSecondary, modifier = Modifier.padding(top = 2.dp).size(14.dp))
        Text(
            text = text,
            style = PulseFont.text(13.sp).copy(lineHeight = 18.sp),
            color = colors.ink.copy(alpha = 0.75f),
            maxLines = 3,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f),
        )
    }
}

// endregion
