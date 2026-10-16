package health.pulse.strength.ui.active

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.isImeVisible
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.Delete
import androidx.compose.material.icons.rounded.Menu
import androidx.compose.material.icons.rounded.Pause
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Timer
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.MenuDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.Saver
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import health.pulse.strength.core.ActiveWorkoutPresentation
import health.pulse.strength.core.CompletedWorkout
import health.pulse.strength.core.Exercise
import health.pulse.strength.core.SetRef
import health.pulse.strength.core.StrengthStore
import health.pulse.strength.core.WorkoutAction
import health.pulse.strength.core.WorkoutController
import health.pulse.strength.ui.ExerciseCardActions
import health.pulse.strength.ui.KeypadField
import health.pulse.strength.ui.PickerMode
import health.pulse.strength.ui.components.DumbbellGlyph
import health.pulse.strength.ui.components.KeepScreenOn
import health.pulse.strength.ui.components.rememberNow
import health.pulse.strength.ui.sheets.ExerciseListSheet
import health.pulse.strength.ui.sheets.ExerciseOptionsDialog
import health.pulse.strength.ui.sheets.ExercisePickerSheet
import health.pulse.strength.ui.sheets.FormInfoHost
import health.pulse.strength.ui.sheets.KeypadSheet
import health.pulse.strength.ui.sheets.RestSettingsSheet
import health.pulse.strength.ui.sheets.SetDetailSheet
import health.pulse.strength.ui.theme.PulseFont
import health.pulse.strength.ui.theme.PulseMetrics
import health.pulse.strength.ui.theme.PulseTheme
import health.pulse.strength.ui.theme.pulseCard
import health.pulse.strength.ui.theme.pulseClickable
import health.pulse.strength.ui.theme.pulseMinHeight
import java.util.UUID

// region Sheets and UI state

/** Everything the active-workout screen presents in a sheet. One sheet at a time. */
internal sealed interface ActiveSheet {
    /** A stable identity: a sheet for another set or exercise is a different sheet. */
    val id: String

    /** Edit exercises: reorder, options, "Add Exercise". */
    data object ExerciseList : ActiveSheet {
        override val id: String = "list"
    }

    /** Add exercises, or replace one exercise. */
    data class Picker(val mode: PickerMode) : ActiveSheet {
        override val id: String = when (mode) {
            PickerMode.Add -> "picker-add"
            is PickerMode.Replace -> "picker-replace-" + mode.exerciseID
        }
    }

    /** Weight / reps keypad for one set. */
    data class Keypad(val ref: SetRef, val field: KeypadField) : ActiveSheet {
        override val id: String = "keypad-" + ref.exerciseID + "-" + ref.setID
    }

    /** Set type, reps in reserve, delete. */
    data class SetDetail(val ref: SetRef) : ActiveSheet {
        override val id: String = "set-" + ref.exerciseID + "-" + ref.setID
    }

    /** Rest timer presets for one workout exercise (plus the two workout-wide toggles). */
    data class RestSettings(val exerciseID: UUID) : ActiveSheet {
        override val id: String = "rest-$exerciseID"
    }

    /** Form demo and cues. */
    data class Info(val exercise: Exercise) : ActiveSheet {
        override val id: String = "info-" + exercise.id
    }
}

/**
 * What the active-workout screen has open: the sheet, the exercise options dialog and the finish / template / discard dialogs.
 * Kept in one holder (and saved across rotation) so the wiring is one place and can be inspected by tests.
 */
internal class ActiveWorkoutUiState {
    var sheet by mutableStateOf<ActiveSheet?>(null)
    var optionsExerciseID by mutableStateOf<UUID?>(null)
    var showFinishDialog by mutableStateOf(false)
    var showDiscardDialog by mutableStateOf(false)
    var showTemplateDialog by mutableStateOf(false)

    companion object {
        /** Saves the state for a configuration change; [exercise] finds an exercise of the form sheet again from its id. */
        fun saver(exercise: (String) -> Exercise?): Saver<ActiveWorkoutUiState, Any> = Saver(
            save = { state ->
                listOf(
                    encode(state.sheet),
                    state.optionsExerciseID?.toString(),
                    state.showFinishDialog,
                    state.showDiscardDialog,
                    state.showTemplateDialog,
                )
            },
            restore = { saved ->
                val values = saved as List<*>
                ActiveWorkoutUiState().apply {
                    sheet = decode(values[0] as? List<*>, exercise)
                    optionsExerciseID = (values[1] as? String)?.let(UUID::fromString)
                    showFinishDialog = values[2] as? Boolean ?: false
                    showDiscardDialog = values[3] as? Boolean ?: false
                    showTemplateDialog = values[4] as? Boolean ?: false
                }
            },
        )

        private fun encode(sheet: ActiveSheet?): List<String>? = when (sheet) {
            null -> null
            ActiveSheet.ExerciseList -> listOf("list")
            is ActiveSheet.Picker -> when (val mode = sheet.mode) {
                PickerMode.Add -> listOf("picker-add")
                is PickerMode.Replace -> listOf("picker-replace", mode.exerciseID.toString())
            }
            is ActiveSheet.Keypad -> listOf("keypad", sheet.ref.exerciseID.toString(), sheet.ref.setID.toString(), sheet.field.name)
            is ActiveSheet.SetDetail -> listOf("set", sheet.ref.exerciseID.toString(), sheet.ref.setID.toString())
            is ActiveSheet.RestSettings -> listOf("rest", sheet.exerciseID.toString())
            is ActiveSheet.Info -> listOf("info", sheet.exercise.id)
        }

        private fun decode(values: List<*>?, exercise: (String) -> Exercise?): ActiveSheet? {
            if (values.isNullOrEmpty()) return null
            return runCatching {
                when (values[0]) {
                    "list" -> ActiveSheet.ExerciseList
                    "picker-add" -> ActiveSheet.Picker(PickerMode.Add)
                    "picker-replace" -> ActiveSheet.Picker(PickerMode.Replace(UUID.fromString(values[1] as String)))
                    "keypad" -> ActiveSheet.Keypad(
                        SetRef(UUID.fromString(values[1] as String), UUID.fromString(values[2] as String)),
                        KeypadField.valueOf(values[3] as String),
                    )
                    "set" -> ActiveSheet.SetDetail(SetRef(UUID.fromString(values[1] as String), UUID.fromString(values[2] as String)))
                    "rest" -> ActiveSheet.RestSettings(UUID.fromString(values[1] as String))
                    "info" -> exercise(values[1] as String)?.let { ActiveSheet.Info(it) }
                    else -> null
                }
            }.getOrNull()
        }
    }
}

@Composable
internal fun rememberActiveWorkoutUiState(store: StrengthStore): ActiveWorkoutUiState =
    rememberSaveable(saver = ActiveWorkoutUiState.saver { id -> store.exercise(id) }) { ActiveWorkoutUiState() }

// endregion

/**
 * The active-workout screen: header, exercise navigator, the exercise card, the rest dock and the undo toast, plus every sheet,
 * dialog and menu of the feature. It only renders `ActiveWorkoutPresentation` and dispatches `WorkoutAction`s.
 *
 * [onMinimise] is called when the workout ends elsewhere (the screen has nothing to show); [onFinished] gets the finished workout,
 * or null when it was discarded. Back-press handling for minimising belongs to the host.
 */
@Composable
fun ActiveWorkoutScreen(
    controller: WorkoutController,
    store: StrengthStore,
    onMinimise: () -> Unit,
    onFinished: (CompletedWorkout?) -> Unit,
    modifier: Modifier = Modifier,
) {
    ActiveWorkoutHost(
        controller = controller,
        store = store,
        uiState = rememberActiveWorkoutUiState(store),
        onMinimise = onMinimise,
        onFinished = onFinished,
        modifier = modifier,
    )
}

/** [ActiveWorkoutScreen] with its UI state handed in (tests inspect it). */
@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun ActiveWorkoutHost(
    controller: WorkoutController,
    store: StrengthStore,
    uiState: ActiveWorkoutUiState,
    onMinimise: () -> Unit,
    onFinished: (CompletedWorkout?) -> Unit,
    modifier: Modifier = Modifier,
) {
    KeepScreenOn()

    val colors = PulseTheme.colors
    val workoutState by controller.state.collectAsState()
    val nowState = rememberNow()
    val now = nowState.value
    val presentation = remember(workoutState, now) { controller.presentation(now) }
    val onAction = remember(controller) { { action: WorkoutAction -> controller.send(action) } }

    // Set once the workout is finished or discarded here, so the empty state that follows does not minimise as well.
    var didEnd by remember { mutableStateOf(false) }

    RestEndFeedbackEffect(
        phase = presentation?.dock?.phase,
        alertsEnabled = workoutState?.settings?.alertWhenRestEnds ?: true,
    )

    fun completeFinish(updateTemplate: Boolean) {
        didEnd = true
        uiState.showTemplateDialog = false
        uiState.showFinishDialog = false
        onFinished(controller.finish(updateTemplate))
    }

    fun confirmFinish() {
        uiState.showFinishDialog = false
        val check = controller.presentation(nowState.value)?.finishCheck ?: return
        if (!check.canFinish) return
        if (check.asksToUpdateTemplate) uiState.showTemplateDialog = true else completeFinish(updateTemplate = false)
    }

    fun performDiscard() {
        didEnd = true
        uiState.showDiscardDialog = false
        uiState.showFinishDialog = false
        controller.discard()
        onFinished(null)
    }

    // The exercise options dialog goes away when its exercise does (it removed it).
    LaunchedEffect(workoutState) {
        val optionsID = uiState.optionsExerciseID
        val stillThere = workoutState?.exercises?.any { it.id == optionsID } == true
        if (optionsID != null && !stillThere) uiState.optionsExerciseID = null
    }

    Box(modifier.fillMaxSize().background(colors.ground)) {
        if (presentation == null) {
            // No active workout (finished or discarded elsewhere): leave the screen.
            LaunchedEffect(Unit) { if (!didEnd) onMinimise() }
        } else {
            ActiveContent(
                presentation = presentation,
                workoutState = workoutState,
                uiState = uiState,
                onAction = onAction,
                onMinimise = onMinimise,
            )
        }

        // Dialogs and sheets are windows of their own; they sit above the screen.
        val check = presentation?.finishCheck
        if (presentation != null && check != null) {
            if (uiState.showFinishDialog) {
                FinishDialog(
                    check = check,
                    onFinish = ::confirmFinish,
                    onKeepTraining = { uiState.showFinishDialog = false },
                    onDiscard = {
                        uiState.showFinishDialog = false
                        uiState.showDiscardDialog = true
                    },
                )
            }
            if (uiState.showTemplateDialog) {
                TemplateDialog(
                    name = presentation.header.title,
                    check = check,
                    onUpdateTemplate = { completeFinish(updateTemplate = true) },
                    onOnlyThisWorkout = { completeFinish(updateTemplate = false) },
                    onBack = { uiState.showTemplateDialog = false },
                )
            }
            if (uiState.showDiscardDialog) {
                DiscardDialog(
                    loggedSets = presentation.totals.loggedSets,
                    onDiscard = ::performDiscard,
                    onCancel = { uiState.showDiscardDialog = false },
                )
            }
        }

        uiState.optionsExerciseID?.let { exerciseID ->
            ExerciseOptionsDialog(
                controller = controller,
                exerciseID = exerciseID,
                onShowInfo = { exercise ->
                    uiState.optionsExerciseID = null
                    uiState.sheet = ActiveSheet.Info(exercise)
                },
                onShowRestSettings = { id ->
                    uiState.optionsExerciseID = null
                    uiState.sheet = ActiveSheet.RestSettings(id)
                },
                onReplace = { id ->
                    uiState.optionsExerciseID = null
                    uiState.sheet = ActiveSheet.Picker(PickerMode.Replace(id))
                },
                onDismiss = { uiState.optionsExerciseID = null },
            )
        }

        uiState.sheet?.let { sheet ->
            key(sheet.id) {
                val dismiss = { if (uiState.sheet?.id == sheet.id) uiState.sheet = null }
                when (sheet) {
                    ActiveSheet.ExerciseList -> ExerciseListSheet(controller = controller, store = store, onDismiss = dismiss)
                    is ActiveSheet.Picker -> ExercisePickerSheet(store = store, controller = controller, mode = sheet.mode, onDismiss = dismiss)
                    is ActiveSheet.Keypad -> KeypadSheet(controller = controller, ref = sheet.ref, initialField = sheet.field, onDismiss = dismiss)
                    is ActiveSheet.SetDetail -> SetDetailSheet(controller = controller, ref = sheet.ref, onDismiss = dismiss)
                    is ActiveSheet.RestSettings -> RestSettingsSheet(controller = controller, exerciseID = sheet.exerciseID, onDismiss = dismiss)
                    is ActiveSheet.Info -> FormInfoHost(exercise = sheet.exercise, store = store, onDismiss = dismiss)
                }
            }
        }
    }
}

// region Content

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun ActiveContent(
    presentation: ActiveWorkoutPresentation,
    workoutState: health.pulse.strength.core.WorkoutState?,
    uiState: ActiveWorkoutUiState,
    onAction: (WorkoutAction) -> Unit,
    onMinimise: () -> Unit,
) {
    // Parts of the presentation that rarely change keep their instance, so only the header and the dock redraw every second.
    val navigator = rememberEqual(presentation.navigator)
    val card = rememberEqual(presentation.card)
    val dock = rememberEqual(presentation.dock)
    val isPaused = presentation.header.isPaused
    val currentExerciseID = workoutState?.currentExercise?.id
    val imeVisible = WindowInsets.isImeVisible

    val actions = remember(uiState) {
        ExerciseCardActions(
            openKeypad = { ref, field -> uiState.sheet = ActiveSheet.Keypad(ref, field) },
            openSetDetail = { ref -> uiState.sheet = ActiveSheet.SetDetail(ref) },
            showInfo = { exercise -> uiState.sheet = ActiveSheet.Info(exercise) },
            showOptions = { id -> uiState.optionsExerciseID = id },
            showRestSettings = { id -> uiState.sheet = ActiveSheet.RestSettings(id) },
        )
    }

    // The dock hides while the keyboard is up (typing a note): the keyboard and the dock together would leave no room.
    val shownDock = if (imeVisible) null else dock

    val header: @Composable () -> Unit = {
        ActiveHeader(
            header = presentation.header,
            onMinimise = onMinimise,
            onFinish = { uiState.showFinishDialog = true },
        ) { dismiss ->
            MoreMenuItems(
                isPaused = isPaused,
                hasCurrentExercise = currentExerciseID != null,
                onTogglePause = { onAction(if (isPaused) WorkoutAction.Resume else WorkoutAction.Pause) },
                onEditExercises = { uiState.sheet = ActiveSheet.ExerciseList },
                onAddExercise = { uiState.sheet = ActiveSheet.Picker(PickerMode.Add) },
                onRestSettings = { currentExerciseID?.let { uiState.sheet = ActiveSheet.RestSettings(it) } },
                onDiscard = { uiState.showDiscardDialog = true },
                dismiss = dismiss,
            )
        }
    }

    // The keyboard pushes everything up; the navigation bar is handled where the content ends (the dock, or the scrolling page).
    BoxWithConstraints(Modifier.fillMaxSize().imePadding()) {
        // Three arrangements, chosen from the window:
        //  * side dock (a phone held sideways, a tablet in landscape): the rest dock moves to the right, so the card keeps the height;
        //  * pinned (the normal case): header on top, dock at the bottom, the card between them;
        //  * scrolling header (little height left for the card, e.g. a small phone with big text): the header scrolls away with
        //    the page so the card and the dock keep the room.
        val fontScale = LocalDensity.current.fontScale.coerceIn(1f, 2f)
        val sideDock = maxWidth >= SideDockMinWidth && maxWidth > maxHeight
        val insets = WindowInsets.safeDrawing.asPaddingValues()
        val headerEstimate = 100.dp + 45.dp * (fontScale - 1f) + insets.calculateTopPadding()
        val dockEstimate = when {
            shownDock == null -> 0.dp
            shownDock.showsRIR -> 135.dp + 150.dp * (fontScale - 1f) + insets.calculateBottomPadding()
            else -> 80.dp + 100.dp * (fontScale - 1f) + insets.calculateBottomPadding()
        }
        val pinHeader = sideDock || maxHeight - headerEstimate - dockEstimate >= MinPinnedMainHeight

        val dockContent: @Composable (ActiveWorkoutPresentation.Dock) -> Unit = { visibleDock ->
            RestDock(
                dock = visibleDock,
                onAdjust = { seconds -> onAction(WorkoutAction.AdjustRest(seconds)) },
                onSkip = { onAction(WorkoutAction.SkipRest) },
                onSelectRIR = { value -> onAction(WorkoutAction.ToggleLastSetRIR(value)) },
                modifier = Modifier.widthIn(max = if (sideDock) SideDockWidth else PulseMetrics.maxContentWidth),
            )
        }
        val dockBelowMain = shownDock != null && !sideDock
        val navigatorBar: @Composable (ActiveWorkoutPresentation.Navigator) -> Unit = { shownNavigator ->
            NavigatorBar(
                navigator = shownNavigator,
                onPrevious = { onAction(WorkoutAction.PreviousExercise) },
                onNext = { onAction(WorkoutAction.NextExercise) },
                onEdit = { uiState.sheet = ActiveSheet.ExerciseList },
            )
        }
        val main: @Composable (Modifier) -> Unit = { modifier ->
            // With the dock below, the page ends at the dock; otherwise it runs to the bottom edge and scrolls under the navigation bar.
            val bottomPadding = if (dockBelowMain) 10.dp else if (sideDock) 12.dp else 24.dp
            Box(modifier.fillMaxWidth()) {
                MainArea(
                    // Beside the dock the navigator sits above it, not above the card.
                    navigator = if (sideDock) null else navigator,
                    navigatorBar = navigatorBar,
                    card = card,
                    isEmpty = presentation.isEmpty,
                    bottomPadding = bottomPadding,
                    insetBottom = !dockBelowMain,
                    scrollingHeader = if (pinHeader) null else header,
                    actions = actions,
                    onAction = onAction,
                    onAdd = { uiState.sheet = ActiveSheet.Picker(PickerMode.Add) },
                )
                // The toast floats over the bottom of the main area, just above the dock (whatever height the dock has).
                AnimatedAppearance(
                    value = presentation.undoText,
                    modifier = Modifier.align(Alignment.BottomCenter),
                ) { text ->
                    Box(
                        Modifier
                            .fillMaxWidth()
                            .windowInsetsPadding(
                                WindowInsets.safeDrawing.only(
                                    if (dockBelowMain) WindowInsetsSides.Horizontal else WindowInsetsSides.Horizontal + WindowInsetsSides.Bottom,
                                ),
                            )
                            .padding(
                                start = PulseMetrics.screenInset,
                                end = PulseMetrics.screenInset,
                                bottom = if (dockBelowMain) 10.dp else 24.dp,
                            ),
                        contentAlignment = Alignment.Center,
                    ) {
                        UndoToast(text = text, onUndo = { onAction(WorkoutAction.Undo) }, modifier = Modifier.widthIn(max = PulseMetrics.maxContentWidth))
                    }
                }
            }
        }

        Column(Modifier.fillMaxSize()) {
            if (pinHeader) header()
            if (sideDock) {
                Row(Modifier.weight(1f).fillMaxWidth()) {
                    main(Modifier.weight(1f).fillMaxHeight())
                    // The side pane: the navigator and the rest dock, one above the other (they scroll when the window is very short).
                    Column(
                        Modifier
                            .width(SideDockWidth + 14.dp)
                            .fillMaxHeight()
                            .windowInsetsPadding(WindowInsets.safeDrawing.only(WindowInsetsSides.End + WindowInsetsSides.Bottom))
                            .verticalScroll(rememberScrollState())
                            .padding(end = 14.dp, top = 10.dp, bottom = 8.dp),
                        verticalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        navigator?.let { navigatorBar(it) }
                        AnimatedAppearance(value = shownDock) { visibleDock -> dockContent(visibleDock) }
                    }
                }
            } else {
                main(Modifier.weight(1f))
                AnimatedAppearance(value = shownDock) { visibleDock ->
                    Box(
                        Modifier
                            .fillMaxWidth()
                            .windowInsetsPadding(WindowInsets.safeDrawing.only(WindowInsetsSides.Horizontal + WindowInsetsSides.Bottom))
                            .padding(start = 14.dp, end = 14.dp, bottom = 8.dp),
                        contentAlignment = Alignment.Center,
                    ) { dockContent(visibleDock) }
                }
            }
        }
    }
}

/** Narrowest window that puts the rest dock beside the card (when it is also wider than tall). */
private val SideDockMinWidth = 560.dp

/** Width of the rest dock when it sits beside the card. */
private val SideDockWidth = 340.dp

/** Height the card area must keep (beside a pinned header and dock) before the header is allowed to scroll away instead. */
private val MinPinnedMainHeight = 220.dp

/**
 * Navigator ([navigator], drawn by [navigatorBar]), exercise card (or the empty state) in a column that scrolls only when the window
 * is too short for the card, centred and at most [PulseMetrics.maxContentWidth] wide. On a normal phone the card gets the rest of the
 * height and only its set rows scroll. With [scrollingHeader] the header is the first thing of the scrolling page and the card takes
 * its natural height. The page ends [bottomPadding] below the card, and above the navigation bar when [insetBottom] is set (it runs
 * to the bottom edge of the window).
 */
@Composable
private fun MainArea(
    navigator: ActiveWorkoutPresentation.Navigator?,
    navigatorBar: @Composable (ActiveWorkoutPresentation.Navigator) -> Unit,
    card: ActiveWorkoutPresentation.Card?,
    isEmpty: Boolean,
    bottomPadding: Dp,
    insetBottom: Boolean,
    scrollingHeader: (@Composable () -> Unit)?,
    actions: ExerciseCardActions,
    onAction: (WorkoutAction) -> Unit,
    onAdd: () -> Unit,
) {
    val scroll = rememberScrollState()
    // A different exercise starts at the top of the page.
    LaunchedEffect(card?.exerciseID) { scroll.scrollTo(0) }

    BoxWithConstraints(Modifier.fillMaxSize()) {
        val topPadding = 10.dp
        val bottomInset = if (insetBottom) WindowInsets.safeDrawing.asPaddingValues().calculateBottomPadding() else 0.dp
        val navigatorSpace: Dp = if (navigator != null) 48.dp.fontScaled() + 10.dp else 0.dp
        val cardViewport = if (scrollingHeader != null) {
            Dp.Infinity
        } else {
            (maxHeight - topPadding - bottomPadding - bottomInset - navigatorSpace).coerceAtLeast(0.dp)
        }

        Column(Modifier.fillMaxSize().verticalScroll(scroll)) {
            scrollingHeader?.invoke()
            Column(
                Modifier
                    .fillMaxWidth()
                    .windowInsetsPadding(
                        WindowInsets.safeDrawing.only(
                            if (insetBottom) WindowInsetsSides.Horizontal + WindowInsetsSides.Bottom else WindowInsetsSides.Horizontal,
                        ),
                    )
                    .padding(start = PulseMetrics.screenInset, end = PulseMetrics.screenInset, top = topPadding, bottom = bottomPadding),
            ) {
                Column(
                    Modifier
                        .widthIn(max = PulseMetrics.maxContentWidth)
                        .fillMaxWidth()
                        .align(Alignment.CenterHorizontally),
                    verticalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    if (navigator != null) navigatorBar(navigator)
                    if (card != null) {
                        ExerciseCard(card = card, onAction = onAction, actions = actions, viewportHeight = cardViewport)
                    } else if (isEmpty) {
                        ActiveEmptyStateCard(onAdd = onAdd, modifier = Modifier.padding(top = 30.dp))
                    }
                }
            }
        }
    }
}

/** "No exercises yet" card with the Add Exercise button, shown when the workout has no exercises. */
@Composable
private fun ActiveEmptyStateCard(onAdd: () -> Unit, modifier: Modifier = Modifier) {
    val colors = PulseTheme.colors
    Column(
        modifier = modifier
            .fillMaxWidth()
            .testTag("active-empty")
            .pulseCard()
            .padding(horizontal = 24.dp, vertical = 32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Box(Modifier.size(64.dp).background(colors.greenTint, CircleShape), contentAlignment = Alignment.Center) {
            DumbbellGlyph(size = 30.dp, color = colors.green, strokeWidth = 1.8.dp)
        }
        Text(
            "No exercises yet",
            style = PulseFont.text(20.sp, FontWeight.Bold),
            color = colors.ink,
            textAlign = TextAlign.Center,
            modifier = Modifier.semantics { heading() },
        )
        Text(
            "Add an exercise from the library, or create your own, to start logging sets.",
            style = PulseFont.subhead,
            color = colors.inkSecondary,
            textAlign = TextAlign.Center,
        )
        Row(
            modifier = Modifier
                .padding(top = 6.dp)
                .pulseMinHeight(48.dp)
                .background(colors.green, RoundedCornerShape(PulseMetrics.rowRadius))
                .testTag("empty-add")
                .pulseClickable(onClick = onAdd)
                .padding(horizontal = 24.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(Icons.Rounded.Add, contentDescription = null, tint = colors.onGreen, modifier = Modifier.size(20.dp))
            Text("Add Exercise", style = PulseFont.headline, color = colors.onGreen, maxLines = 1)
        }
    }
}

// endregion

// region More menu

@Composable
private fun ColumnScope.MoreMenuItems(
    isPaused: Boolean,
    hasCurrentExercise: Boolean,
    onTogglePause: () -> Unit,
    onEditExercises: () -> Unit,
    onAddExercise: () -> Unit,
    onRestSettings: () -> Unit,
    onDiscard: () -> Unit,
    dismiss: () -> Unit,
) {
    val colors = PulseTheme.colors
    val item = MenuDefaults.itemColors(
        textColor = colors.ink,
        leadingIconColor = colors.green,
    )
    DropdownMenuItem(
        text = { Text(if (isPaused) "Resume workout" else "Pause workout") },
        leadingIcon = { Icon(if (isPaused) Icons.Rounded.PlayArrow else Icons.Rounded.Pause, contentDescription = null) },
        colors = item,
        onClick = { dismiss(); onTogglePause() },
        modifier = Modifier.testTag("menu-pause"),
    )
    DropdownMenuItem(
        text = { Text("Edit exercises") },
        leadingIcon = { Icon(Icons.Rounded.Menu, contentDescription = null) },
        colors = item,
        onClick = { dismiss(); onEditExercises() },
        modifier = Modifier.testTag("menu-edit"),
    )
    DropdownMenuItem(
        text = { Text("Add exercise") },
        leadingIcon = { Icon(Icons.Rounded.Add, contentDescription = null) },
        colors = item,
        onClick = { dismiss(); onAddExercise() },
        modifier = Modifier.testTag("menu-add"),
    )
    if (hasCurrentExercise) {
        DropdownMenuItem(
            text = { Text("Rest timer settings") },
            leadingIcon = { Icon(Icons.Rounded.Timer, contentDescription = null) },
            colors = item,
            onClick = { dismiss(); onRestSettings() },
            modifier = Modifier.testTag("menu-rest"),
        )
    }
    DropdownMenuItem(
        text = { Text("Discard workout") },
        leadingIcon = { Icon(Icons.Rounded.Delete, contentDescription = null) },
        colors = MenuDefaults.itemColors(textColor = colors.destructive, leadingIconColor = colors.destructive),
        onClick = { dismiss(); onDiscard() },
        modifier = Modifier.testTag("menu-discard"),
    )
}

// endregion

// region Finish and discard dialogs

/** One button of a dialog; [destructive] ones are red. */
private class DialogAction(val label: String, val tag: String, val destructive: Boolean = false, val onClick: () -> Unit)

/** An AlertDialog whose buttons are stacked, so three choices with long names fit on any window. */
@Composable
private fun StackedAlertDialog(title: String, message: String, actions: List<DialogAction>, onDismiss: () -> Unit) {
    val colors = PulseTheme.colors
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = colors.card,
        titleContentColor = colors.ink,
        textContentColor = colors.inkSecondary,
        shape = RoundedCornerShape(22.dp),
        title = { Text(title) },
        text = { Text(message) },
        confirmButton = {
            Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.End) {
                for (action in actions) {
                    TextButton(onClick = action.onClick, modifier = Modifier.testTag(action.tag)) {
                        Text(
                            action.label,
                            color = if (action.destructive) colors.destructive else colors.greenText,
                            style = PulseFont.headline,
                        )
                    }
                }
            }
        },
    )
}

/** Finish Workout / Keep Training / Discard Workout. Nothing logged: only Keep Training and Discard Workout. */
@Composable
private fun FinishDialog(
    check: ActiveWorkoutPresentation.FinishCheck,
    onFinish: () -> Unit,
    onKeepTraining: () -> Unit,
    onDiscard: () -> Unit,
) {
    val actions = buildList {
        if (check.canFinish) add(DialogAction("Finish Workout", "finish-confirm", onClick = onFinish))
        add(DialogAction("Keep Training", "finish-keep", onClick = onKeepTraining))
        add(DialogAction("Discard Workout", "finish-discard", destructive = true, onClick = onDiscard))
    }
    StackedAlertDialog(title = check.title, message = check.message, actions = actions, onDismiss = onKeepTraining)
}

/** "Update “Upper A · Push”?" after a workout whose exercise list differs from its template. */
@Composable
private fun TemplateDialog(
    name: String,
    check: ActiveWorkoutPresentation.FinishCheck,
    onUpdateTemplate: () -> Unit,
    onOnlyThisWorkout: () -> Unit,
    onBack: () -> Unit,
) {
    StackedAlertDialog(
        title = "Update “$name”?",
        message = check.diffMessage + " Save this exercise list for your next workouts?",
        actions = listOf(
            DialogAction("Update Template", "template-update", onClick = onUpdateTemplate),
            DialogAction("Only This Workout", "template-only", onClick = onOnlyThisWorkout),
            DialogAction("Back to Workout", "template-back", onClick = onBack),
        ),
        onDismiss = onBack,
    )
}

@Composable
private fun DiscardDialog(loggedSets: Int, onDiscard: () -> Unit, onCancel: () -> Unit) {
    val message = if (loggedSets == 0) {
        "Nothing has been logged yet."
    } else {
        "You will lose $loggedSets logged " + (if (loggedSets == 1) "set." else "sets.")
    }
    StackedAlertDialog(
        title = "Discard workout?",
        message = message,
        actions = listOf(
            DialogAction("Discard", "discard-confirm", destructive = true, onClick = onDiscard),
            DialogAction("Cancel", "discard-cancel", onClick = onCancel),
        ),
        onDismiss = onCancel,
    )
}

// endregion
