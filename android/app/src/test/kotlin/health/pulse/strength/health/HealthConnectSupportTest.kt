package health.pulse.strength.health

import com.google.common.truth.Truth.assertThat
import health.pulse.strength.core.CompletedWorkout
import health.pulse.strength.health.HealthConnectSupport.Availability
import health.pulse.strength.health.HealthConnectSupport.PermissionState
import java.time.Instant
import java.time.ZoneOffset
import java.util.UUID
import org.junit.Test

/** The Health Connect rules that do not need Health Connect itself: when the "save workouts" switch is wrong, and the session record. */
class HealthConnectSupportTest {
    @Test
    fun aSwitchThatIsOnButCannotWorkIsExplained() {
        assertThat(HealthConnectSupport.problem(Availability.AVAILABLE, PermissionState.MISSING)).contains("no longer has permission")
        assertThat(HealthConnectSupport.problem(Availability.UNAVAILABLE, PermissionState.UNKNOWN)).contains("not available")
        assertThat(HealthConnectSupport.problem(Availability.UPDATE_REQUIRED, PermissionState.GRANTED)).contains("needs an update")
    }

    @Test
    fun nothingIsWrongWhenItWorksOrCannotBeTold() {
        assertThat(HealthConnectSupport.problem(Availability.AVAILABLE, PermissionState.GRANTED)).isNull()
        // A failed question is not an answer: the switch stays as the user left it.
        assertThat(HealthConnectSupport.problem(Availability.AVAILABLE, PermissionState.UNKNOWN)).isNull()
    }

    private fun workout(sets: Int, volume: Double) = CompletedWorkout(
        id = UUID.randomUUID(),
        name = "Push day",
        templateID = null,
        startedAt = Instant.parse("2026-03-02T17:00:00Z"),
        finishedAt = Instant.parse("2026-03-02T17:50:00Z"),
        durationSeconds = 3000,
        volumeKg = volume,
        loggedSets = sets,
        averageHeartRate = null,
        averageRIR = null,
        exercises = emptyList(),
        personalRecords = emptyList(),
        muscleSets = emptyList(),
    )

    @Test
    fun theSessionNoteCountsSetsInTheRightPluralWithLatinDigits() {
        val zone = ZoneOffset.UTC
        assertThat(HealthConnectWorkoutWriter.record(workout(1, 60.0), zone).notes).isEqualTo("1 set · 60 kg")
        assertThat(HealthConnectWorkoutWriter.record(workout(21, 4_200.0), zone).notes).isEqualTo("21 sets · 4,200 kg")
    }

    @Test
    fun theSessionIsTheRealWorkoutAndNeverDuplicates() {
        val completed = workout(3, 1_000.0)
        val record = HealthConnectWorkoutWriter.record(completed, ZoneOffset.UTC)
        assertThat(record.startTime).isEqualTo(completed.startedAt)
        assertThat(record.endTime).isEqualTo(completed.finishedAt)
        assertThat(record.title).isEqualTo("Push day")
        assertThat(record.metadata.clientRecordId).isEqualTo(completed.id.toString())
    }
}
