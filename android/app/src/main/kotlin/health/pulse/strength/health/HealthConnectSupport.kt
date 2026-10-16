package health.pulse.strength.health

import android.content.Context
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.ExerciseSessionRecord

/** What the app needs from Health Connect: it only ever WRITES finished workouts as exercise sessions; it reads nothing. */
object HealthConnectSupport {
    /** The single permission the app asks for. */
    val writePermission: String = HealthPermission.getWritePermission(ExerciseSessionRecord::class)

    val permissions: Set<String> = setOf(writePermission)

    enum class Availability { AVAILABLE, UPDATE_REQUIRED, UNAVAILABLE }

    fun availability(context: Context): Availability = when (HealthConnectClient.getSdkStatus(context)) {
        HealthConnectClient.SDK_AVAILABLE -> Availability.AVAILABLE
        HealthConnectClient.SDK_UNAVAILABLE_PROVIDER_UPDATE_REQUIRED -> Availability.UPDATE_REQUIRED
        else -> Availability.UNAVAILABLE
    }

    suspend fun hasWritePermission(context: Context): Boolean = permissionState(context) == PermissionState.GRANTED

    /** Whether the write permission is held right now; [PermissionState.UNKNOWN] when Health Connect could not be asked. */
    enum class PermissionState { GRANTED, MISSING, UNKNOWN }

    suspend fun permissionState(context: Context): PermissionState = try {
        if (HealthConnectClient.getOrCreate(context).permissionController.getGrantedPermissions().contains(writePermission)) {
            PermissionState.GRANTED
        } else {
            PermissionState.MISSING
        }
    } catch (e: Exception) {
        PermissionState.UNKNOWN
    }

    /**
     * Why "Save workouts to Health Connect" cannot work right now although the user turned it on, or null when nothing is wrong (or
     * it cannot be told). The switch is turned off in that case, so it shows the truth and turning it on asks for the permission again.
     */
    fun problem(availability: Availability, permission: PermissionState): String? = when {
        availability == Availability.UNAVAILABLE -> "Health Connect is not available on this device, so workouts are not saved there."
        availability == Availability.UPDATE_REQUIRED -> "Health Connect needs an update, so workouts are not saved there."
        permission == PermissionState.MISSING ->
            "Pulse Strength no longer has permission to write to Health Connect, so workouts are not saved there. " +
                "Turn the switch on to allow it again."
        else -> null
    }
}
