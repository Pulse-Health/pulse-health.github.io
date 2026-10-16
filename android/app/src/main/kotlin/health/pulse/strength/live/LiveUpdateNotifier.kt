package health.pulse.strength.live

import android.Manifest
import android.app.Notification
import android.content.Context
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.os.Build
import androidx.core.app.NotificationChannelCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import health.pulse.strength.R

/**
 * Draws a [LiveUpdateModel] as a notification; it decides nothing.
 *
 * On Android 16 (API 36) a running workout is a Live Update: the notification is ongoing, asks to be promoted, shows the status-bar chip
 * ([LiveUpdateModel.chipText]) and, unless it needs its big text, a segmented progress bar of the sets (`ProgressStyle`, through the
 * compat class that hands over to the platform's `Notification.ProgressStyle`). Older versions get the same texts and buttons in the
 * big-text style of an ordinary ongoing notification.
 */
internal object LiveUpdateNotifier {
    private val GreenLight = 0xFF1B8448.toInt()
    private val GreenDark = 0xFF30D158.toInt()
    private val GoldLight = 0xFF7A5200.toInt()
    private val GoldDark = 0xFFFFD60A.toInt()
    private val BlueLight = 0xFF0066D6.toInt()
    private val BlueDark = 0xFF0A84FF.toInt()

    /** Posts or replaces the card of [model.kind][LiveUpdateModel.kind]. A no-op while the user keeps notifications off. */
    fun post(context: Context, model: LiveUpdateModel) {
        if (!canPost(context)) return
        ensureChannels(context)
        NotificationManagerCompat.from(context).notify(model.kind.notificationId, build(context, model))
    }

    fun cancel(context: Context, notificationId: Int) {
        NotificationManagerCompat.from(context).cancel(notificationId)
    }

    fun build(context: Context, model: LiveUpdateModel): Notification {
        val color = accentColor(model.accent, isNight(context))
        val builder = NotificationCompat.Builder(context, model.kind.channel.id)
            .setSmallIcon(R.drawable.ic_stat_workout)
            .setContentTitle(model.title)
            .setContentText(model.text)
            .setSubText(model.subText)
            .setCategory(if (model.kind == LiveKind.PLANNED || model.kind == LiveKind.PLANNED_DUE) NotificationCompat.CATEGORY_REMINDER else NotificationCompat.CATEGORY_WORKOUT)
            .setColor(color)
            .setOngoing(model.ongoing)
            .setAutoCancel(!model.ongoing)
            .setOnlyAlertOnce(true)
            // The watch has its own tile and Ongoing Activity for the same workout; a mirrored card would only repeat it.
            .setLocalOnly(true)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setContentIntent(LiveIntents.link(context, model.contentLink))
        model.timeoutMillis?.let { builder.setTimeoutAfter(it) }
        model.actions.forEach { builder.addAction(0, it.title, LiveIntents.pendingIntent(context, it)) }
        applyClock(builder, model)

        val progress = model.progress
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.BAKLAVA) {
            if (model.ongoing) builder.setRequestPromotedOngoing(true)
            model.chipText?.let { builder.setShortCriticalText(it) }
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.BAKLAVA && progress != null && !model.needsBigText) {
            builder.setStyle(
                NotificationCompat.ProgressStyle()
                    .setProgressSegments(progress.segments.map { NotificationCompat.ProgressStyle.Segment(it).setColor(color) })
                    .setProgress(progress.value),
            )
        } else {
            builder.setStyle(NotificationCompat.BigTextStyle().bigText(model.bigText))
        }
        return builder.build()
    }

    /** The countdown or elapsed time that the shade, the lock screen and (without chip text) the status-bar chip draw. */
    private fun applyClock(builder: NotificationCompat.Builder, model: LiveUpdateModel) {
        when (val clock = model.clock) {
            LiveClock.None -> builder.setShowWhen(model.kind == LiveKind.FINISH || model.kind == LiveKind.PLANNED_DUE)
            is LiveClock.Elapsed -> builder.setShowWhen(true).setWhen(clock.sinceMillis).setUsesChronometer(true).setChronometerCountDown(false)
            is LiveClock.Countdown -> builder.setShowWhen(true).setWhen(clock.untilMillis).setUsesChronometer(true).setChronometerCountDown(true)
        }
    }

    /** "Workout" is silent (importance default, no sound, no vibration); "Workout reminders" is the one channel that makes noise. */
    fun ensureChannels(context: Context) {
        val manager = NotificationManagerCompat.from(context)
        manager.createNotificationChannel(
            NotificationChannelCompat.Builder(LiveChannel.WORKOUT.id, NotificationManagerCompat.IMPORTANCE_DEFAULT)
                .setName(context.getString(R.string.live_channel_workout))
                .setDescription(context.getString(R.string.live_channel_workout_description))
                .setSound(null, null)
                .setVibrationEnabled(false)
                .setLightsEnabled(false)
                .setShowBadge(false)
                .build(),
        )
        manager.createNotificationChannel(
            NotificationChannelCompat.Builder(LiveChannel.REMINDER.id, NotificationManagerCompat.IMPORTANCE_HIGH)
                .setName(context.getString(R.string.live_channel_reminder))
                .setDescription(context.getString(R.string.live_channel_reminder_description))
                .build(),
        )
    }

    private fun canPost(context: Context): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            return false
        }
        return NotificationManagerCompat.from(context).areNotificationsEnabled()
    }

    private fun isNight(context: Context): Boolean =
        context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK == Configuration.UI_MODE_NIGHT_YES

    private fun accentColor(accent: LiveAccent, night: Boolean): Int = when (accent) {
        LiveAccent.GREEN -> if (night) GreenDark else GreenLight
        LiveAccent.GOLD -> if (night) GoldDark else GoldLight
        LiveAccent.BLUE -> if (night) BlueDark else BlueLight
    }
}
