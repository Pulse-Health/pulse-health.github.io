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

    suspend fun hasWritePermission(context: Context): Boolean = runCatching {
        HealthConnectClient.getOrCreate(context).permissionController.getGrantedPermissions().contains(writePermission)
    }.getOrDefault(false)
}
