package health.pulse.strength.wear.ongoing

import android.Manifest
import android.annotation.SuppressLint
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.wear.ongoing.OngoingActivity
import androidx.wear.ongoing.Status
import health.pulse.strength.core.WorkoutSnapshot
import health.pulse.strength.wear.R
import health.pulse.strength.wear.WearMainActivity
import health.pulse.strength.wear.model.OngoingModel
import health.pulse.strength.wear.model.OngoingStatus
import java.time.Instant

/**
 * WA-02: while a workout runs the watch face shows an Ongoing Activity chip (the workout clock, or the rest countdown), and a tap on it
 * opens the watch app. The chip is the status of a low-importance ongoing notification; `SnapshotIngest` starts, updates and removes it
 * whenever the phone pushes a snapshot. Without the notification permission the chip is skipped (Wear OS 4 asks for it at runtime).
 */
internal object OngoingWorkout {
    const val CHANNEL_ID = "workout"
    const val NOTIFICATION_ID = 4711

    /** Posts or updates the chip for [active], or removes it when no workout runs. */
    @SuppressLint("MissingPermission")
    fun sync(context: Context, active: WorkoutSnapshot?, now: Instant = Instant.now()) {
        val manager = NotificationManagerCompat.from(context)
        if (active == null || !mayNotify(context)) {
            manager.cancel(NOTIFICATION_ID)
            return
        }
        createChannel(context)
        val model = OngoingModel.of(active, now)
        val touchIntent = PendingIntent.getActivity(
            context,
            0,
            Intent(context, WearMainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_dumbbell)
            .setContentTitle(model.title)
            .setContentText(model.text)
            .setCategory(NotificationCompat.CATEGORY_WORKOUT)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(touchIntent)
        OngoingActivity.Builder(context, NOTIFICATION_ID, notification)
            .setStaticIcon(R.drawable.ic_dumbbell)
            .setCategory(NotificationCompat.CATEGORY_WORKOUT)
            .setTitle(model.title)
            .setContentDescription(model.description)
            .setStatus(status(model.status))
            .setTouchIntent(touchIntent)
            .build()
            .apply(context)
        manager.notify(NOTIFICATION_ID, notification.build())
    }

    /** The status text of the chip; the parts tick by themselves on the watch face. */
    fun status(status: OngoingStatus): Status = when (status) {
        is OngoingStatus.Elapsed -> Status.Builder()
            .addTemplate("#time#")
            .addPart("time", Status.StopwatchPart(status.startMillis))
            .build()
        is OngoingStatus.ElapsedPaused -> Status.Builder()
            .addTemplate("Paused #time#")
            .addPart("time", Status.StopwatchPart(status.startMillis, status.pausedAtMillis))
            .build()
        is OngoingStatus.Rest -> Status.Builder()
            .addTemplate("Rest #time#")
            .addPart("time", Status.TimerPart(status.endsAtMillis))
            .build()
        is OngoingStatus.RestPaused -> {
            val pausedAt = System.currentTimeMillis()
            Status.Builder()
                .addTemplate("Paused #time#")
                .addPart("time", Status.TimerPart(pausedAt + status.remainingSeconds * MILLIS_PER_SECOND, pausedAt))
                .build()
        }
        OngoingStatus.RestOver -> Status.forPart(Status.TextPart("Rest over"))
        OngoingStatus.Complete -> Status.forPart(Status.TextPart("All sets logged"))
    }

    /** True when the app may post notifications: always before Android 13, else when the runtime permission is granted. */
    fun mayNotify(context: Context): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED

    private fun createChannel(context: Context) {
        val channel = NotificationChannel(
            CHANNEL_ID,
            context.getString(R.string.channel_workout_name),
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = context.getString(R.string.channel_workout_description)
            setShowBadge(false)
        }
        NotificationManagerCompat.from(context).createNotificationChannel(channel)
    }

    private const val MILLIS_PER_SECOND = 1000L
}
