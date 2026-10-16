package health.pulse.strength.ui.detail

import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import health.pulse.strength.core.Exercise
import health.pulse.strength.core.StrengthStore

/** The exercise detail screen (OWNER: detail+summary agent; placeholder until the screen is ported). */
@Composable
fun ExerciseDetailScreen(exercise: Exercise, store: StrengthStore, onBack: () -> Unit, modifier: Modifier = Modifier) {
    Text(exercise.name, modifier)
}
