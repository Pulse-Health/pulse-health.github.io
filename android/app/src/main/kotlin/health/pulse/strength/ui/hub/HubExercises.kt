package health.pulse.strength.ui.hub

import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import health.pulse.strength.core.ExerciseLibrary
import health.pulse.strength.core.MuscleGroup
import health.pulse.strength.core.StrengthStore
import health.pulse.strength.ui.sheets.CreateExerciseSheet
import health.pulse.strength.ui.theme.PulseChip
import health.pulse.strength.ui.theme.PulseTheme

// "Exercise Library": search, muscle filter and "create your own"; each row opens the exercise detail (HubExerciseLibraryView).

@Composable
internal fun HubLibraryScreen(store: StrengthStore, actions: HubActions, modifier: Modifier = Modifier) {
    val colors = PulseTheme.colors
    val data by store.data.collectAsState()
    var query by rememberSaveable { mutableStateOf("") }
    var muscle by rememberSaveable { mutableStateOf<MuscleGroup?>(null) }
    var showsCreate by rememberSaveable { mutableStateOf(false) }
    val results = remember(data, query, muscle) { ExerciseLibrary.filter(store.exercises, query, muscle, equipment = null) }

    HubScreenFrame(
        title = "Exercise Library",
        onBack = actions.pop,
        modifier = modifier,
        actions = {
            IconButton(onClick = { showsCreate = true }) {
                Icon(Icons.Rounded.Add, contentDescription = "Create exercise", tint = colors.ink)
            }
        },
    ) { inner ->
        HubContentBox(Modifier.hubScreenPadding(inner).fillMaxSize()) { gutter ->
            LazyColumn(Modifier.fillMaxSize(), contentPadding = hubContentPadding(gutter, bottom = hubBottomPadding(inner))) {
                item(key = "search") {
                    HubSearchField(value = query, onValueChange = { query = it })
                }
                item(key = "muscles") {
                    Row(
                        Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(top = 12.dp, bottom = 12.dp),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        PulseChip("All", isSelected = muscle == null, onClick = { muscle = null })
                        for (group in MuscleGroup.entries) {
                            PulseChip(group.title, isSelected = muscle == group, onClick = { muscle = if (muscle == group) null else group })
                        }
                    }
                }
                if (results.isEmpty()) {
                    item(key = "none") { HubMessage("No exercises found") }
                }
                itemsIndexed(results, key = { _, exercise -> exercise.id }) { index, exercise ->
                    Box(Modifier.fillMaxWidth().background(colors.card, groupedShape(index, results.size))) {
                        HubExerciseEntryRow(
                            mediaKey = exercise.mediaKey,
                            name = exercise.name,
                            detail = exercise.muscle.title + " · " + exercise.equipment.title,
                            onClick = { actions.push(HubRoute.Exercise(exercise.id)) },
                        )
                        if (index > 0) HubDivider(Modifier.align(Alignment.TopStart), inset = 68.dp)
                    }
                }
            }
        }
    }

    if (showsCreate) {
        CreateExerciseSheet(
            initialName = query,
            onCreate = { exercise ->
                store.addCustomExercise(exercise)
                showsCreate = false
            },
            onDismiss = { showsCreate = false },
        )
    }
}
