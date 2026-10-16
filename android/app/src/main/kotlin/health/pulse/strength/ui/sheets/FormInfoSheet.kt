package health.pulse.strength.ui.sheets

import androidx.compose.runtime.Composable
import health.pulse.strength.core.Exercise
import health.pulse.strength.core.StrengthStore

/**
 * Form demo, muscles and how-to cues of one exercise (OWNER: sheets agent; placeholder until ported). Shows its own modal bottom
 * sheet. "History & records" is offered only when [onShowHistory] is set.
 */
@Composable
fun FormInfoSheet(exercise: Exercise, onShowHistory: (() -> Unit)?, onDismiss: () -> Unit) {}

/**
 * [FormInfoSheet] hosted so that "History & records" opens the exercise detail screen inside the sheet (OWNER: sheets agent;
 * placeholder until ported). Used wherever the form sheet is opened from (the active workout, the exercise list).
 */
@Composable
fun FormInfoHost(exercise: Exercise, store: StrengthStore, onDismiss: () -> Unit) {}
