package health.pulse.strength.ui.hub

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.MoreVert
import androidx.compose.material.icons.rounded.RadioButtonUnchecked
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.SheetState
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Stable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.listSaver
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import health.pulse.strength.core.Exercise
import health.pulse.strength.core.ExerciseLibrary
import health.pulse.strength.core.PlannedSet
import health.pulse.strength.core.SetType
import health.pulse.strength.core.StrengthJson
import health.pulse.strength.core.StrengthStore
import health.pulse.strength.core.TemplateEntry
import health.pulse.strength.core.WorkoutTemplate
import health.pulse.strength.ui.components.DumbbellGlyph
import health.pulse.strength.ui.components.ExerciseMediaView
import health.pulse.strength.ui.components.rememberPulseHaptics
import health.pulse.strength.ui.theme.PulseFont
import health.pulse.strength.ui.theme.PulseMetrics
import health.pulse.strength.ui.theme.PulsePrimaryButton
import health.pulse.strength.ui.theme.PulseTheme
import health.pulse.strength.ui.theme.pulseClickable
import java.util.UUID
import kotlinx.coroutines.launch
import kotlinx.serialization.builtins.ListSerializer

// Templates: the rows of the hub, "Templates > See All", the template detail, the editor sheet and the exercise chooser
// (the "Rows and cards", "Templates" and "Template editor" parts of StrengthHubView.swift).

// region Rows

@Composable
internal fun HubTemplateRow(template: WorkoutTemplate, subtitle: String, onClick: () -> Unit, modifier: Modifier = Modifier) {
    val colors = PulseTheme.colors
    Row(
        modifier
            .fillMaxWidth()
            .heightIn(min = 56.dp)
            .pulseClickable(onClick = onClick)
            .hubRowBackground()
            .padding(12.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        HubIconBox(fill = hubBlueFill()) { DumbbellGlyph(size = 18.dp, color = colors.blue, strokeWidth = 2.dp) }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(
                template.name,
                style = PulseFont.text(15.sp, FontWeight.SemiBold),
                color = colors.ink,
                maxLines = lineLimit(),
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                subtitle,
                style = PulseFont.footnote,
                color = colors.inkSecondary,
                maxLines = lineLimit(),
                overflow = TextOverflow.Ellipsis,
            )
        }
        HubChevron()
    }
}

@Composable
internal fun HubNewTemplateRow(onClick: () -> Unit, modifier: Modifier = Modifier) {
    val colors = PulseTheme.colors
    Row(
        modifier
            .fillMaxWidth()
            .heightIn(min = 56.dp)
            .pulseClickable(onClick = onClick)
            .hubRowBackground()
            .padding(12.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        HubIconBox(fill = colors.greenTint) {
            Icon(Icons.Rounded.Add, contentDescription = null, modifier = Modifier.size(18.dp), tint = colors.green)
        }
        Text("New Template", style = PulseFont.text(15.sp, FontWeight.SemiBold), color = colors.greenText)
    }
}

/** The blue wash behind a dumbbell glyph (the iOS hub's own blue, a little stronger in dark mode). */
@Composable
internal fun hubBlueFill(): Color = PulseTheme.colors.blue.copy(alpha = if (PulseTheme.colors.isDark) 0.20f else 0.10f)

/** A row of "Templates > See All": the "Next up" pill after the name, the subtitle and the exercise names. */
@Composable
private fun HubTemplateListRow(template: WorkoutTemplate, time: HubTime, isNext: Boolean, onClick: () -> Unit) {
    val colors = PulseTheme.colors
    val subtitle = HubFormat.templateSubtitle(template, HubFormat.lastDoneSuffix(template, time.today, time.zone))
    val names = remember(template) { template.entries.joinToString(", ") { it.exercise.name } }
    Row(
        Modifier
            .fillMaxWidth()
            .heightIn(min = 56.dp)
            .pulseClickable(onClick = onClick)
            .hubRowBackground()
            .padding(12.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        HubIconBox(fill = hubBlueFill()) { DumbbellGlyph(size = 18.dp, color = colors.blue, strokeWidth = 2.dp) }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(
                    template.name,
                    modifier = Modifier.weight(1f, fill = false),
                    style = PulseFont.text(15.sp, FontWeight.SemiBold),
                    color = colors.ink,
                    maxLines = lineLimit(),
                    overflow = TextOverflow.Ellipsis,
                )
                if (isNext) {
                    // A pill of its own so the tag is never cut off at the end of the subtitle; the name gives way first.
                    Text(
                        "Next up",
                        modifier = Modifier.background(colors.greenTint, CircleShape).padding(horizontal = 7.dp, vertical = 2.dp),
                        style = PulseFont.text(11.sp, FontWeight.Bold),
                        color = colors.greenText,
                        maxLines = 1,
                    )
                }
            }
            Text(subtitle, style = PulseFont.footnote, color = colors.inkSecondary)
            if (names.isNotEmpty()) {
                Text(
                    names,
                    style = PulseFont.footnote,
                    color = colors.inkSecondary,
                    maxLines = if (isLargerText()) 4 else 2,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
        HubChevron()
    }
}

// endregion

// region Templates > See All

@Composable
internal fun HubTemplateListScreen(home: HubHomeData, time: HubTime, actions: HubActions, modifier: Modifier = Modifier) {
    HubScreenFrame(title = "Templates", onBack = actions.pop, modifier = modifier) { inner ->
        HubContentBox(Modifier.hubScreenPadding(inner).fillMaxSize()) { gutter ->
            LazyColumn(
                Modifier.fillMaxSize(),
                contentPadding = hubContentPadding(gutter, bottom = hubBottomPadding(inner)),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                items(home.templates, key = { it.id }) { template ->
                    HubTemplateListRow(
                        template = template,
                        time = time,
                        isNext = template.id == home.recommended?.id,
                        onClick = { actions.push(HubRoute.Template(template.id)) },
                    )
                }
                if (home.templates.isEmpty()) {
                    item(key = "empty") {
                        HubMessage("No templates yet. A template saves the exercises, sets and weights you repeat.")
                    }
                }
                item(key = "new") { HubNewTemplateRow(onClick = { actions.edit(HubEditorTarget.New) }) }
            }
        }
    }
}

// endregion

// region Template detail

/**
 * A template at a glance: its exercises (each opens the exercise detail) and the Start button. While a workout runs the button reads
 * "Resume Workout" for that workout's own template; any other start is answered by the hub's "Workout in progress" dialog.
 */
@Composable
internal fun HubTemplateDetailScreen(
    templateID: UUID,
    home: HubHomeData,
    time: HubTime,
    actions: HubActions,
    modifier: Modifier = Modifier,
) {
    val template = home.templates.firstOrNull { it.id == templateID }
    HubScreenFrame(
        title = template?.name ?: "Template",
        onBack = actions.pop,
        modifier = modifier,
        actions = {
            TextButton(onClick = { actions.edit(HubEditorTarget.Existing(templateID)) }, enabled = template != null) {
                Text("Edit", style = PulseFont.text(17.sp, FontWeight.SemiBold))
            }
        },
        bottomBar = {
            if (template != null) {
                val runsThis = home.runningTemplateID == template.id
                HubBottomBar {
                    PulsePrimaryButton(
                        text = if (runsThis) "Resume Workout" else "Start Workout",
                        onClick = { if (runsThis) actions.resume() else actions.requestStart(template) },
                        modifier = Modifier.widthIn(max = PulseMetrics.maxContentWidth - 32.dp),
                    )
                }
            }
        },
    ) { inner ->
        if (template == null) {
            Box(Modifier.padding(inner).fillMaxSize(), contentAlignment = Alignment.Center) {
                HubMessage("This template is no longer available.")
            }
        } else {
            HubContentBox(Modifier.padding(inner).fillMaxSize()) { gutter ->
                Column(
                    Modifier
                        .fillMaxSize()
                        .verticalScroll(rememberScrollState())
                        .padding(start = gutter, end = gutter, top = 8.dp, bottom = 24.dp),
                    verticalArrangement = Arrangement.spacedBy(16.dp),
                ) {
                    HubTemplateHeader(template, time)
                    HubTemplateEntriesCard(template, actions)
                }
            }
        }
    }
}

@Composable
private fun HubTemplateHeader(template: WorkoutTemplate, time: HubTime) {
    val colors = PulseTheme.colors
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(template.name, style = PulseFont.number(28.sp), color = colors.ink)
        Text(
            HubFormat.templateSubtitle(template, HubFormat.lastDoneSuffix(template, time.today, time.zone)),
            style = PulseFont.subhead,
            color = colors.inkSecondary,
        )
    }
}

@Composable
private fun HubTemplateEntriesCard(template: WorkoutTemplate, actions: HubActions) {
    if (template.entries.isEmpty()) {
        Text(
            "This template has no exercises yet. Tap Edit to add some.",
            style = PulseFont.subhead,
            color = PulseTheme.colors.inkSecondary,
        )
        return
    }
    Column(Modifier.fillMaxWidth().hubRowBackground()) {
        for ((index, entry) in template.entries.withIndex()) {
            Box {
                HubExerciseEntryRow(
                    mediaKey = entry.exercise.mediaKey,
                    name = entry.exercise.name,
                    detail = HubFormat.planSummary(entry),
                    onClick = { actions.push(HubRoute.Exercise(entry.exercise.id)) },
                )
                if (index > 0) HubDivider(Modifier.align(Alignment.TopStart), inset = 68.dp)
            }
        }
    }
}

/** An exercise row with a 44 dp form demo, a name, a detail line and a chevron. */
@Composable
internal fun HubExerciseEntryRow(mediaKey: String?, name: String, detail: String, onClick: (() -> Unit)?, modifier: Modifier = Modifier) {
    val colors = PulseTheme.colors
    Row(
        modifier
            .fillMaxWidth()
            .heightIn(min = 64.dp)
            .then(if (onClick != null) Modifier.pulseClickable(onClick = onClick) else Modifier)
            .padding(horizontal = 12.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        ExerciseMediaView(mediaKey = mediaKey, modifier = Modifier.size(44.dp), cornerRadius = 10.dp)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(
                name,
                style = PulseFont.text(15.sp, FontWeight.SemiBold),
                color = colors.ink,
                maxLines = lineLimit(),
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                detail,
                style = PulseFont.footnote,
                color = colors.inkSecondary,
                maxLines = lineLimit(),
                overflow = TextOverflow.Ellipsis,
            )
        }
        if (onClick != null) HubChevron()
    }
}

// endregion

// region Editor

/** The editor's work in progress: nothing is saved until Save. Survives rotation (the entries are kept as JSON). */
@Stable
internal class HubEditorDraft(name: String, entries: List<TemplateEntry>) {
    var name by mutableStateOf(name)
    var entries by mutableStateOf(entries)

    val canSave: Boolean get() = name.trim().isNotEmpty() && entries.isNotEmpty()

    /** Appends the chosen exercises with their default sets (at least one), weight, reps and rest. */
    fun add(exercises: List<Exercise>) {
        entries = entries + exercises.map(::makeEntry)
    }

    fun move(index: Int, by: Int) {
        val target = index + by
        if (index !in entries.indices || target !in entries.indices) return
        val updated = entries.toMutableList()
        updated.add(target, updated.removeAt(index))
        entries = updated
    }

    fun remove(index: Int) {
        if (index !in entries.indices) return
        entries = entries.toMutableList().also { it.removeAt(index) }
    }

    /** The template to save, or null while it is incomplete. [existing] keeps its id and its "last performed" date. */
    fun toTemplate(existing: WorkoutTemplate?): WorkoutTemplate? {
        val trimmed = name.trim()
        if (trimmed.isEmpty() || entries.isEmpty()) return null
        return WorkoutTemplate(
            id = existing?.id ?: UUID.randomUUID(),
            name = trimmed,
            entries = entries,
            lastPerformed = existing?.lastPerformed,
        )
    }

    companion object {
        fun makeEntry(exercise: Exercise): TemplateEntry {
            val defaults = exercise.defaults
            val planned = List(maxOf(1, defaults.sets)) { PlannedSet(SetType.NORMAL, defaults.weightKg, defaults.reps) }
            return TemplateEntry(exercise = exercise, plannedSets = planned, restSeconds = defaults.restSeconds)
        }

        private val entriesSerializer = ListSerializer(TemplateEntry.serializer())

        val Saver = listSaver<HubEditorDraft, String>(
            save = { draft -> listOf(draft.name, StrengthJson.format.encodeToString(entriesSerializer, draft.entries)) },
            restore = { saved ->
                val entries = runCatching { StrengthJson.format.decodeFromString(entriesSerializer, saved[1]) }.getOrDefault(emptyList())
                HubEditorDraft(saved[0], entries)
            },
        )
    }
}

/** Runs [onDismiss] once the sheet has slid away. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun rememberSheetDismisser(sheetState: SheetState, onDismiss: () -> Unit): () -> Unit {
    val scope = rememberCoroutineScope()
    return {
        scope.launch { sheetState.hide() }.invokeOnCompletion { onDismiss() }
    }
}

/**
 * "New Template" / "Edit Plan": name, exercises (move up / down, remove) and "Add Exercises". Nothing is saved until Save, which
 * writes the template with [StrengthStore.saveTemplate].
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun HubTemplateEditorSheet(store: StrengthStore, template: WorkoutTemplate?, onDismiss: () -> Unit) {
    val colors = PulseTheme.colors
    val haptics = rememberPulseHaptics()
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val draft = rememberSaveable(saver = HubEditorDraft.Saver) { HubEditorDraft(template?.name ?: "", template?.entries ?: emptyList()) }
    var showsChooser by rememberSaveable { mutableStateOf(false) }
    val close = rememberSheetDismisser(sheetState, onDismiss)

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = colors.ground,
        contentColor = colors.ink,
    ) {
        HubTemplateEditorContent(
            isNew = template == null,
            draft = draft,
            onCancel = close,
            onSave = {
                // The current stored template wins over the one the sheet was opened with (its "last performed" date may have moved).
                val current = template?.let { opened -> store.templates.firstOrNull { it.id == opened.id } ?: opened }
                val saved = draft.toTemplate(current)
                if (saved != null) {
                    store.saveTemplate(saved)
                    haptics.success()
                    close()
                }
            },
            onAddExercises = { showsChooser = true },
        )
    }
    if (showsChooser) {
        HubExerciseChooserSheet(
            store = store,
            onAdd = { draft.add(it) },
            onDismiss = { showsChooser = false },
        )
    }
}

/** The body of the editor sheet (separate from the sheet so it can be rendered and tested on its own). */
@Composable
internal fun HubTemplateEditorContent(
    isNew: Boolean,
    draft: HubEditorDraft,
    onCancel: () -> Unit,
    onSave: () -> Unit,
    onAddExercises: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = PulseTheme.colors
    Column(modifier.fillMaxSize().imePadding()) {
        HubSheetBar(
            title = if (isNew) "New Template" else "Edit Plan",
            cancelTitle = "Cancel",
            onCancel = onCancel,
            confirmTitle = "Save",
            confirmEnabled = draft.canSave,
            onConfirm = onSave,
        )
        HubContentBox(Modifier.weight(1f).fillMaxWidth()) { gutter ->
            LazyColumn(Modifier.fillMaxSize(), contentPadding = hubContentPadding(gutter, top = 4.dp, bottom = 24.dp)) {
                item(key = "name-header") { HubFormHeader("Name") }
                item(key = "name") { HubTemplateNameField(draft) }
                item(key = "exercises-header") { HubFormHeader("Exercises", Modifier.padding(top = 16.dp)) }
                val entries = draft.entries
                itemsIndexed(entries, key = { _, entry -> entry.id }) { index, entry ->
                    Box(
                        Modifier
                            .fillMaxWidth()
                            .background(colors.card, groupedShape(index, count = entries.size + 1)),
                    ) {
                        HubEditorEntryRow(
                            entry = entry,
                            index = index,
                            count = entries.size,
                            onMove = { draft.move(index, it) },
                            onRemove = { draft.remove(index) },
                        )
                        if (index > 0) HubDivider(Modifier.align(Alignment.TopStart), inset = 68.dp)
                    }
                }
                item(key = "add") {
                    Box(Modifier.fillMaxWidth().background(colors.card, groupedShape(entries.size, count = entries.size + 1))) {
                        HubAddExercisesRow(onClick = onAddExercises)
                        if (entries.isNotEmpty()) HubDivider(Modifier.align(Alignment.TopStart), inset = 16.dp)
                    }
                }
            }
        }
    }
}

@Composable
private fun HubFormHeader(title: String, modifier: Modifier = Modifier) {
    Text(
        title,
        modifier = modifier.padding(start = 16.dp, bottom = 8.dp, top = 4.dp).semantics { heading() },
        style = PulseFont.text(13.sp, FontWeight.SemiBold),
        color = PulseTheme.colors.inkSecondary,
    )
}

@Composable
private fun HubTemplateNameField(draft: HubEditorDraft) {
    val colors = PulseTheme.colors
    TextField(
        value = draft.name,
        onValueChange = { draft.name = it },
        modifier = Modifier.fillMaxWidth(),
        singleLine = true,
        shape = RoundedCornerShape(12.dp),
        textStyle = PulseFont.body,
        placeholder = { Text("Template name", style = PulseFont.body, color = colors.inkSecondary) },
        keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Words, imeAction = ImeAction.Done),
        colors = TextFieldDefaults.colors(
            focusedContainerColor = colors.card,
            unfocusedContainerColor = colors.card,
            focusedIndicatorColor = Color.Transparent,
            unfocusedIndicatorColor = Color.Transparent,
            focusedTextColor = colors.ink,
            unfocusedTextColor = colors.ink,
            cursorColor = colors.green,
        ),
    )
}

@Composable
private fun HubAddExercisesRow(onClick: () -> Unit) {
    val colors = PulseTheme.colors
    Row(
        Modifier
            .fillMaxWidth()
            .heightIn(min = 56.dp)
            .pulseClickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(Icons.Rounded.Add, contentDescription = null, modifier = Modifier.size(22.dp), tint = colors.green)
        Text("Add Exercises", style = PulseFont.body, color = colors.greenText)
    }
}

/** An exercise of the plan: its form demo, name and plan summary, and a menu with Move up, Move down and Remove. */
@Composable
private fun HubEditorEntryRow(entry: TemplateEntry, index: Int, count: Int, onMove: (Int) -> Unit, onRemove: () -> Unit) {
    val colors = PulseTheme.colors
    var menuOpen by remember { mutableStateOf(false) }
    Row(
        Modifier.fillMaxWidth().heightIn(min = 64.dp).padding(start = 12.dp, end = 4.dp, top = 6.dp, bottom = 6.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        ExerciseMediaView(mediaKey = entry.exercise.mediaKey, modifier = Modifier.size(40.dp), cornerRadius = 8.dp, animated = false)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(
                entry.exercise.name,
                style = PulseFont.text(15.sp, FontWeight.SemiBold),
                color = colors.ink,
                maxLines = lineLimit(),
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                HubFormat.planSummary(entry),
                style = PulseFont.footnote,
                color = colors.inkSecondary,
                maxLines = lineLimit(),
                overflow = TextOverflow.Ellipsis,
            )
        }
        Box {
            IconButton(onClick = { menuOpen = true }) {
                Icon(Icons.Rounded.MoreVert, contentDescription = "Options for ${entry.exercise.name}", tint = colors.inkSecondary)
            }
            DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
                DropdownMenuItem(
                    text = { Text("Move up") },
                    enabled = index > 0,
                    onClick = {
                        menuOpen = false
                        onMove(-1)
                    },
                )
                DropdownMenuItem(
                    text = { Text("Move down") },
                    enabled = index < count - 1,
                    onClick = {
                        menuOpen = false
                        onMove(1)
                    },
                )
                DropdownMenuItem(
                    text = { Text("Remove", color = colors.destructive) },
                    onClick = {
                        menuOpen = false
                        onRemove()
                    },
                )
            }
        }
    }
}

/** The bar of a sheet: Cancel, title, confirm action (the title moves to its own line at the largest font sizes). */
@Composable
internal fun HubSheetBar(
    title: String,
    cancelTitle: String,
    onCancel: () -> Unit,
    confirmTitle: String,
    confirmEnabled: Boolean,
    onConfirm: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = PulseTheme.colors
    val titleText: @Composable (Modifier) -> Unit = { titleModifier ->
        Text(
            title,
            modifier = titleModifier.semantics { heading() },
            style = PulseFont.text(17.sp, FontWeight.SemiBold),
            color = colors.ink,
            textAlign = TextAlign.Center,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
        )
    }
    Column(modifier.fillMaxWidth().padding(horizontal = 8.dp)) {
        Row(Modifier.fillMaxWidth().heightIn(min = 52.dp), verticalAlignment = Alignment.CenterVertically) {
            TextButton(onClick = onCancel) { Text(cancelTitle, style = PulseFont.body) }
            if (isAccessibilityText()) {
                Box(Modifier.weight(1f))
            } else {
                titleText(Modifier.weight(1f).padding(horizontal = 4.dp))
            }
            TextButton(onClick = onConfirm, enabled = confirmEnabled) {
                Text(confirmTitle, style = PulseFont.text(17.sp, FontWeight.SemiBold))
            }
        }
        if (isAccessibilityText()) titleText(Modifier.fillMaxWidth().padding(bottom = 8.dp))
    }
}

// endregion

// region Exercise chooser

/** Multi-select exercise list used by the template editor: tap rows to select, "Add (n)" appends them. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun HubExerciseChooserSheet(store: StrengthStore, onAdd: (List<Exercise>) -> Unit, onDismiss: () -> Unit) {
    val colors = PulseTheme.colors
    val haptics = rememberPulseHaptics()
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    var query by rememberSaveable { mutableStateOf("") }
    var selected by rememberSaveable(stateSaver = listSaver<List<String>, String>(save = { it }, restore = { it })) {
        mutableStateOf(emptyList<String>())
    }
    val data by store.data.collectAsState()
    val results = remember(data, query) { ExerciseLibrary.filter(store.exercises, query, muscle = null, equipment = null) }
    val close = rememberSheetDismisser(sheetState, onDismiss)

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = colors.card,
        contentColor = colors.ink,
    ) {
        HubExerciseChooserContent(
            results = results,
            query = query,
            onQueryChange = { query = it },
            selected = selected,
            onToggle = { exercise ->
                haptics.selection()
                selected = if (exercise.id in selected) selected - exercise.id else selected + exercise.id
            },
            onCancel = close,
            onConfirm = {
                val all = store.exercises
                onAdd(selected.mapNotNull { id -> all.firstOrNull { it.id == id } })
                close()
            },
        )
    }
}

/** The body of the chooser sheet (separate from the sheet so it can be rendered and tested on its own). */
@Composable
internal fun HubExerciseChooserContent(
    results: List<Exercise>,
    query: String,
    onQueryChange: (String) -> Unit,
    selected: List<String>,
    onToggle: (Exercise) -> Unit,
    onCancel: () -> Unit,
    onConfirm: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(modifier.fillMaxSize().imePadding()) {
        HubSheetBar(
            title = "Add Exercises",
            cancelTitle = "Cancel",
            onCancel = onCancel,
            confirmTitle = if (selected.isEmpty()) "Add" else "Add (${selected.size})",
            confirmEnabled = selected.isNotEmpty(),
            onConfirm = onConfirm,
        )
        HubContentBox(Modifier.weight(1f).fillMaxWidth()) { gutter ->
            LazyColumn(Modifier.fillMaxSize(), contentPadding = hubContentPadding(gutter, top = 0.dp, bottom = 24.dp)) {
                item(key = "search") {
                    HubSearchField(value = query, onValueChange = onQueryChange, modifier = Modifier.padding(bottom = 8.dp))
                }
                if (results.isEmpty()) {
                    item(key = "none") { HubMessage("No exercises found") }
                }
                itemsIndexed(results, key = { _, exercise -> exercise.id }) { index, exercise ->
                    HubChooserRow(
                        exercise = exercise,
                        isSelected = exercise.id in selected,
                        showsDivider = index > 0,
                        onToggle = { onToggle(exercise) },
                    )
                }
            }
        }
    }
}

@Composable
private fun HubChooserRow(exercise: Exercise, isSelected: Boolean, showsDivider: Boolean, onToggle: () -> Unit) {
    val colors = PulseTheme.colors
    Box {
        Row(
            Modifier
                .fillMaxWidth()
                .heightIn(min = 56.dp)
                .toggleable(value = isSelected, role = Role.Checkbox, onValueChange = { onToggle() })
                .padding(horizontal = 4.dp, vertical = 8.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            ExerciseMediaView(mediaKey = exercise.mediaKey, modifier = Modifier.size(40.dp), cornerRadius = 8.dp, animated = false)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(
                    exercise.name,
                    style = PulseFont.text(15.sp, FontWeight.SemiBold),
                    color = colors.ink,
                    maxLines = lineLimit(),
                    overflow = TextOverflow.Ellipsis,
                )
                Text(
                    exercise.muscle.title + " · " + exercise.equipment.title,
                    style = PulseFont.footnote,
                    color = colors.inkSecondary,
                    maxLines = lineLimit(),
                    overflow = TextOverflow.Ellipsis,
                )
            }
            Icon(
                imageVector = if (isSelected) Icons.Rounded.CheckCircle else Icons.Rounded.RadioButtonUnchecked,
                contentDescription = null,
                modifier = Modifier.size(fontScaledDp(26f)),
                tint = if (isSelected) colors.green else colors.inkTertiary,
            )
        }
        if (showsDivider) HubDivider(Modifier.align(Alignment.TopStart), inset = 56.dp)
    }
}

// endregion
