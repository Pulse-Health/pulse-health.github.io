package health.pulse.strength.wear.data

import android.util.AtomicFile
import android.util.Log
import java.io.File
import java.io.FileNotFoundException
import java.io.IOException

/**
 * The last snapshot the phone pushed, kept as the JSON text it arrived in so a tile or complication that starts in a fresh process
 * (the system binds them without the activity) still has data. Writes go through [AtomicFile], so a power loss mid-write leaves the
 * previous file intact.
 */
internal class SnapshotStore(file: File) {
    private val atomic = AtomicFile(file)

    /** The stored JSON, or null when nothing was stored yet or the file cannot be read. */
    fun read(): String? = try {
        String(atomic.readFully(), Charsets.UTF_8)
    } catch (_: FileNotFoundException) {
        null
    } catch (error: IOException) {
        Log.w(TAG, "Could not read the stored snapshot", error)
        null
    }

    /** Replaces the stored JSON. A failure is logged and swallowed: the in-memory snapshot is still current. */
    fun write(json: String) {
        val stream = try {
            atomic.startWrite()
        } catch (error: IOException) {
            Log.w(TAG, "Could not store the snapshot", error)
            return
        }
        try {
            stream.write(json.toByteArray(Charsets.UTF_8))
            atomic.finishWrite(stream)
        } catch (error: IOException) {
            atomic.failWrite(stream)
            Log.w(TAG, "Could not store the snapshot", error)
        }
    }

    companion object {
        /** Same file name as the phone's snapshot file (widgets/SPEC.md section 3). */
        const val FILE_NAME = "widget-snapshot.json"
        private const val TAG = "SnapshotStore"
    }
}
