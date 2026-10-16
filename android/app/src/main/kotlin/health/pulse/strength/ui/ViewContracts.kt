package health.pulse.strength.ui

import health.pulse.strength.core.Exercise
import health.pulse.strength.core.SetRef
import java.util.UUID

// Types shared between the independently written screens, sheets and the app environment.

/** What the "Add exercise" picker does with the selection. */
sealed interface PickerMode {
    /** Append the selected exercises to the workout. */
    data object Add : PickerMode

    /** Replace the given workout exercise with the single selected exercise. */
    data class Replace(val exerciseID: UUID) : PickerMode
}

/** Which value of a set the keypad edits. */
enum class KeypadField { WEIGHT, REPS }

/** Callbacks of the exercise card (the active-workout screen presents the sheets). */
class ExerciseCardActions(
    /** Open the keypad for a set's weight or reps. */
    val openKeypad: (SetRef, KeypadField) -> Unit,
    /** Open the set type / RIR / delete sheet. */
    val openSetDetail: (SetRef) -> Unit,
    /** Open the form & instructions sheet (media tile tap). */
    val showInfo: (Exercise) -> Unit,
    /** Open the exercise options dialog for a workout exercise id. */
    val showOptions: (UUID) -> Unit,
    /** Open the rest timer settings of a workout exercise id. */
    val showRestSettings: (UUID) -> Unit,
)
