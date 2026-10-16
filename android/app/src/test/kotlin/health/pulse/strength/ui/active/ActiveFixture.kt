package health.pulse.strength.ui.active

import health.pulse.strength.core.ActiveWorkoutPresentation
import health.pulse.strength.core.Exercise
import health.pulse.strength.core.FileStrengthPersistence
import health.pulse.strength.core.StrengthStore
import health.pulse.strength.core.WorkoutAction
import health.pulse.strength.core.WorkoutController
import health.pulse.strength.core.WorkoutTemplate
import health.pulse.strength.core.addingTimeInterval
import health.pulse.strength.ui.ScreenshotSupport
import java.time.Instant
import java.util.UUID

/**
 * A real store + controller with the demo data and a controllable clock, for the active-workout tests. The workout is started
 * [elapsedSeconds] before [ScreenshotSupport.fixedNow], and the clock then stands at that time, so the screen (which is rendered
 * at the fixed time) shows "24:18" and the rest countdowns the test sets up.
 */
internal class ActiveFixture(
    template: String? = "Upper A · Push",
    elapsedSeconds: Int = 24 * 60 + 18,
    startWorkout: Boolean = true,
) {
    /** The controller's clock; tests move it to set up rests, then leave it at [ScreenshotSupport.fixedNow]. */
    var now: Instant = ScreenshotSupport.fixedNow.addingTimeInterval(-elapsedSeconds.toDouble())

    val persistence: FileStrengthPersistence = FileStrengthPersistence.temporary()
    val store: StrengthStore = StrengthStore(persistence, seedDemoData = true)
    val controller: WorkoutController = WorkoutController(store, persistence, clock = { now })

    init {
        if (startWorkout) {
            controller.startWorkout(template?.let { name -> store.templates.first { it.name == name } })
        }
        now = ScreenshotSupport.fixedNow
    }

    val template: WorkoutTemplate? get() = store.templates.firstOrNull { it.id == controller.state.value?.templateID }

    /** The presentation at the screen's time. */
    fun presentation(): ActiveWorkoutPresentation = controller.presentation(ScreenshotSupport.fixedNow)!!

    fun send(action: WorkoutAction) = controller.send(action)

    /** Id of the exercise at [index] of the workout. */
    fun exerciseID(index: Int): UUID = controller.state.value!!.exercises[index].id

    fun setID(exerciseIndex: Int, setIndex: Int): UUID = controller.state.value!!.exercises[exerciseIndex].sets[setIndex].id

    /** Logs the sets [setIndices] of the exercise at [exerciseIndex], [secondsAgo] seconds before the screen's time (so a rest is already running). */
    fun log(exerciseIndex: Int, setIndices: IntRange, secondsAgo: Int = 0) {
        val ago = ScreenshotSupport.fixedNow.addingTimeInterval(-secondsAgo.toDouble())
        for (index in setIndices) {
            now = ago
            send(WorkoutAction.ToggleSet(exerciseID(exerciseIndex), setID(exerciseIndex, index)))
        }
        now = ScreenshotSupport.fixedNow
    }

    fun exercise(id: String): Exercise = store.exercise(id)!!
}
