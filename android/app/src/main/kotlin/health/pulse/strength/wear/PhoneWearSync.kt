package health.pulse.strength.wear

import android.content.Context

/**
 * Owner: wear. Phone side of the Wearable Data Layer: pushes the snapshot to the watch (`WearProtocol.SNAPSHOT_PATH`) and executes the
 * commands the watch sends (`WearProtocol.COMMAND_PATH`, a `WearableListenerService` registered in the manifest region `wear`).
 */
object PhoneWearSync {
    /** Called by `Surfaces.refreshAll` after the snapshot changed. */
    suspend fun refresh(context: Context) {
        // Replaced by the owner.
    }
}
