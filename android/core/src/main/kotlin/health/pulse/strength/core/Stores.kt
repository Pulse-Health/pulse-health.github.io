package health.pulse.strength.core

import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.nio.file.AtomicMoveNotSupportedException
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.util.UUID
import kotlinx.serialization.KSerializer
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject

/**
 * Stores the strength feature's data as JSON files in one directory (atomic writes).
 *
 * A missing or corrupt file reads as an empty value and never crashes; in a list or dictionary file an element that cannot be
 * decoded is skipped and the readable ones are kept. All file access is serialised by a lock, so one instance can be shared.
 */
class FileStrengthPersistence(val directory: File) {
    private val lock = Any()

    private object FileName {
        const val activeWorkout = "active-workout.json"
        const val templates = "templates.json"
        const val history = "history.json"
        const val customExercises = "custom-exercises.json"
        const val personalBests = "personal-bests.json"
    }

    /** Where a write is staged before it is moved over its target: a subfolder the Android backup rules leave out. */
    private val stagingDirectory = File(directory, STAGING_DIRECTORY)

    init {
        runCatching { directory.mkdirs() }
        sweepStaging()
    }

    // region Active workout

    /** The workout in progress, or null when there is none or the file is unreadable. */
    fun loadActiveWorkout(): WorkoutState? {
        val text = read(FileName.activeWorkout) ?: return null
        return runCatching { StrengthJson.format.decodeFromString(WorkoutState.serializer(), text) }.getOrNull()
    }

    /** Saves the workout in progress; null deletes the file. */
    @Throws(IOException::class)
    fun saveActiveWorkout(state: WorkoutState?) {
        if (state == null) {
            remove(FileName.activeWorkout)
            return
        }
        write(StrengthJson.format.encodeToString(WorkoutState.serializer(), state), FileName.activeWorkout)
    }

    // endregion

    // region Templates, history, custom exercises, personal bests

    /** The saved workout templates (empty when none or unreadable). */
    fun loadTemplates(): List<WorkoutTemplate> = readList(FileName.templates, WorkoutTemplate.serializer())

    /** Replaces the saved workout templates. */
    @Throws(IOException::class)
    fun saveTemplates(templates: List<WorkoutTemplate>) = writeList(FileName.templates, WorkoutTemplate.serializer(), templates)

    /** The finished workouts, newest first (empty when none or unreadable). */
    fun loadHistory(): List<CompletedWorkout> = readList(FileName.history, CompletedWorkout.serializer())

    /** Replaces the finished workouts (newest first). */
    @Throws(IOException::class)
    fun saveHistory(history: List<CompletedWorkout>) = writeList(FileName.history, CompletedWorkout.serializer(), history)

    /** The user's own exercises (empty when none or unreadable). */
    fun loadCustomExercises(): List<Exercise> = readList(FileName.customExercises, Exercise.serializer())

    /** Replaces the user's own exercises. */
    @Throws(IOException::class)
    fun saveCustomExercises(exercises: List<Exercise>) = writeList(FileName.customExercises, Exercise.serializer(), exercises)

    /** The personal bests by exercise id (empty when none or unreadable). */
    fun loadPersonalBests(): Map<String, PersonalBest> {
        val text = read(FileName.personalBests) ?: return emptyMap()
        val root = runCatching { StrengthJson.format.parseToJsonElement(text) }.getOrNull() as? JsonObject ?: return emptyMap()
        val result = linkedMapOf<String, PersonalBest>()
        for ((key, element) in root) {
            val best = runCatching { StrengthJson.format.decodeFromJsonElement(PersonalBest.serializer(), element) }.getOrNull()
            if (best != null) result[key] = best
        }
        return result
    }

    /** Replaces the personal bests. The keys are written in sorted order (as the Swift core's `.sortedKeys` does): the same value gives the same bytes. */
    @Throws(IOException::class)
    fun savePersonalBests(bests: Map<String, PersonalBest>) {
        write(
            StrengthJson.format.encodeToString(MapSerializer(String.serializer(), PersonalBest.serializer()), bests.toSortedMap()),
            FileName.personalBests,
        )
    }

    // endregion

    // region File access

    private fun file(name: String): File = File(directory, name)

    private fun read(name: String): String? = synchronized(lock) {
        val target = file(name)
        if (!target.isFile) return null
        return runCatching { target.readText(Charsets.UTF_8) }.getOrNull()
    }

    private fun <T> readList(name: String, serializer: KSerializer<T>): List<T> {
        val text = read(name) ?: return emptyList()
        val root = runCatching { StrengthJson.format.parseToJsonElement(text) }.getOrNull() as? JsonArray ?: return emptyList()
        return root.mapNotNull { element -> runCatching { StrengthJson.format.decodeFromJsonElement(serializer, element) }.getOrNull() }
    }

    private fun <T> writeList(name: String, serializer: KSerializer<T>, values: List<T>) {
        write(StrengthJson.format.encodeToString(ListSerializer(serializer), values), name)
    }

    /** Writes [text] to a temporary file next to the target, flushes it to disk and moves it over the target. */
    private fun write(text: String, name: String) {
        synchronized(lock) {
            stagingDirectory.mkdirs()
            val target = file(name)
            val temporary = File(stagingDirectory, "$name.${UUID.randomUUID()}.tmp")
            try {
                FileOutputStream(temporary).use { stream ->
                    stream.write(text.toByteArray(Charsets.UTF_8))
                    stream.fd.sync()
                }
                try {
                    Files.move(temporary.toPath(), target.toPath(), StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
                } catch (_: AtomicMoveNotSupportedException) {
                    Files.move(temporary.toPath(), target.toPath(), StandardCopyOption.REPLACE_EXISTING)
                }
            } finally {
                if (temporary.exists()) temporary.delete()
            }
        }
    }

    /**
     * Deletes what a killed write left in the staging folder (the process died between creating the temporary file and moving it).
     * Only files older than a minute go, so a write in progress in another instance is never touched.
     */
    private fun sweepStaging() {
        val cutoff = System.currentTimeMillis() - STALE_STAGING_MILLIS
        runCatching {
            stagingDirectory.listFiles()?.forEach { if (it.isFile && it.lastModified() < cutoff) it.delete() }
        }
    }

    private fun remove(name: String) {
        synchronized(lock) {
            val target = file(name)
            if (!target.exists()) return
            if (!target.delete()) throw IOException("Could not delete ${target.path}")
        }
    }

    // endregion

    companion object {
        /** The subfolder of [directory] where writes are staged; the app's backup rules exclude `PulseStrength/tmp`. */
        const val STAGING_DIRECTORY = "tmp"

        private const val STALE_STAGING_MILLIS = 60_000L

        private val temporaryDirectories = java.util.concurrent.ConcurrentLinkedQueue<File>()

        private val shutdownHookAdded = java.util.concurrent.atomic.AtomicBoolean(false)

        private fun removeTemporaryDirectoriesAtExit() {
            if (!shutdownHookAdded.compareAndSet(false, true)) return
            Runtime.getRuntime().addShutdownHook(
                Thread {
                    while (true) {
                        val directory = temporaryDirectories.poll() ?: break
                        directory.deleteRecursively()
                    }
                },
            )
        }

        /** Persistence in a new, unique directory inside the system temporary directory (tests, previews); removed when the JVM ends. */
        fun temporary(): FileStrengthPersistence {
            val directory = Files.createTempDirectory("PulseStrength-").toFile()
            temporaryDirectories.add(directory)
            removeTemporaryDirectoriesAtExit()
            return FileStrengthPersistence(directory)
        }
    }
}
