package health.pulse.strength.health

import android.content.Context
import android.util.Log
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.records.ExerciseSessionRecord
import androidx.health.connect.client.records.metadata.Metadata
import health.pulse.strength.core.CompletedWorkout
import health.pulse.strength.core.NumberText
import health.pulse.strength.core.WorkoutSideEffect
import health.pulse.strength.core.WorkoutState
import health.pulse.strength.services.PulseSettings
import java.time.ZoneId
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/**
 * Saves a finished workout to Health Connect as one strength-training exercise session (the Android counterpart of the iOS
 * HealthKit writer), when the user turned it on and granted the permission.
 *
 * The record carries the workout id as its client record id, so saving the same workout twice (a failed history write that is retried
 * after a relaunch) replaces the record instead of duplicating it. A failure is logged and never reaches the user's workflow.
 */
class HealthConnectWorkoutWriter(
    private val context: Context,
    private val settings: PulseSettings,
    private val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Default),
) : WorkoutSideEffect {
    override fun workoutEnded(state: WorkoutState, completed: CompletedWorkout?) {
        if (completed == null || !settings.healthConnectEnabled.value) return
        scope.launch { save(completed) }
    }

    internal suspend fun save(completed: CompletedWorkout) {
        if (HealthConnectSupport.availability(context) != HealthConnectSupport.Availability.AVAILABLE) return
        runCatching {
            if (!HealthConnectSupport.hasWritePermission(context)) return
            HealthConnectClient.getOrCreate(context).insertRecords(listOf(record(completed)))
        }.onFailure { Log.w(TAG, "Could not save the workout to Health Connect", it) }
    }

    companion object {
        private const val TAG = "PulseHealthConnect"

        /** The exercise session of [completed]: its real start and end, title, and a short note with the totals. */
        fun record(completed: CompletedWorkout, zone: ZoneId = ZoneId.systemDefault()): ExerciseSessionRecord {
            val rules = zone.rules
            return ExerciseSessionRecord(
                startTime = completed.startedAt,
                startZoneOffset = rules.getOffset(completed.startedAt),
                endTime = completed.finishedAt,
                endZoneOffset = rules.getOffset(completed.finishedAt),
                metadata = Metadata.manualEntry(clientRecordId = completed.id.toString()),
                exerciseType = ExerciseSessionRecord.EXERCISE_TYPE_STRENGTH_TRAINING,
                title = completed.name,
                notes = "${completed.loggedSets} sets · ${NumberText.thousands(completed.volumeKg)} kg",
            )
        }
    }
}
