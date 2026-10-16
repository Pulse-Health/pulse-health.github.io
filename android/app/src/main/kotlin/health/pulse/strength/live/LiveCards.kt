package health.pulse.strength.live

import android.app.Notification
import android.content.Context
import android.content.res.Configuration
import android.os.Build
import androidx.core.app.NotificationChannelCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import health.pulse.strength.R
import health.pulse.strength.core.widgets.DeepLinks
import health.pulse.strength.core.widgets.FinishBrief
import health.pulse.strength.services.WorkoutNotifications
import java.time.Instant

/** The notification channels of this package (the workout and rest channels belong to `NotificationChannels`). */
internal enum class LiveChannel(val id: String) {
    /** The finish card and the planned-session countdown: shown, never heard. */
    SUMMARY("workout_summary"),

    /** "Time to train": the one notification of this package that is meant to be heard. */
    REMINDER("workout_reminder"),
}

/** The notifications that are no part of the ongoing workout card. Each owns a fixed id, so a second post replaces the first. */
internal enum class CardKind(val notificationId: Int, val channel: LiveChannel) {
    /** LA-05: the summary of a finished workout. */
    FINISH(4102, LiveChannel.SUMMARY),

    /** LA-06: the countdown to a planned session. */
    PLANNED(4103, LiveChannel.SUMMARY),

    /** LA-06: the planned session starts now. */
    PLANNED_DUE(4104, LiveChannel.REMINDER),
}

/**
 * A notification of [CardKind], as plain data. [LiveCards] draws it; the models of the finish summary and the planned session
 * produce it, and the tests read it directly.
 *
 * @property countdownToMillis the instant a chronometer counts down to, or null for a card with the time it was posted.
 * @property timeoutMillis the system removes the card after this long.
 */
internal data class LiveCard(
    val kind: CardKind,
    val title: String,
    val text: String,
    val subText: String? = null,
    val detailLines: List<String> = emptyList(),
    val countdownToMillis: Long? = null,
    val actions: List<LiveAction> = emptyList(),
    val ongoing: Boolean = false,
    val timeoutMillis: Long? = null,
    val accent: LiveAccent = LiveAccent.GREEN,
    val contentLink: String = DeepLinks.hub,
)

internal object LiveCards {
    /** LA-05: the finish card stays two hours (iOS ends the activity with `dismissalPolicy .after`). */
    const val FINISH_LIFETIME_MILLIS: Long = 2 * 60 * 60 * 1000L

    private val GreenLight = 0xFF1B8448.toInt()
    private val GreenDark = 0xFF30D158.toInt()
    private val GoldLight = 0xFF7A5200.toInt()
    private val GoldDark = 0xFFFFD60A.toInt()

    /** LA-05: "Upper A · Push done", "52 min · 22 sets · 9.1 t · 1 PR", "Saved to Health", and a share button. */
    fun finish(brief: FinishBrief): LiveCard {
        val stats = buildList {
            add("${brief.durationMinutes} min")
            add(if (brief.sets == 1) "1 set" else "${brief.sets} sets")
            add("${brief.volumeText} t")
            if (brief.personalRecordCount > 0) add(LiveText.records(brief.personalRecordCount))
        }
        return LiveCard(
            kind = CardKind.FINISH,
            title = "${brief.workoutName} done",
            text = stats.joinToString(" · "),
            subText = if (brief.savedToHealth) "Saved to Health" else null,
            actions = listOf(LiveAction(LiveActionId.SHARE, "Share", LiveTarget.Share("${brief.workoutName}: ${stats.joinToString(", ")}"))),
            timeoutMillis = FINISH_LIFETIME_MILLIS,
            accent = if (brief.personalRecordCount > 0) LiveAccent.GOLD else LiveAccent.GREEN,
        )
    }

    /** Posts or replaces [card]. Does nothing while the person keeps notifications off. */
    fun post(context: Context, card: LiveCard) {
        if (!WorkoutNotifications.canNotify(context)) return
        ensureChannels(context)
        @Suppress("MissingPermission") // canNotify() checked the runtime permission
        NotificationManagerCompat.from(context).notify(card.kind.notificationId, build(context, card))
    }

    fun cancel(context: Context, kind: CardKind) {
        NotificationManagerCompat.from(context).cancel(kind.notificationId)
    }

    fun build(context: Context, card: LiveCard): Notification {
        val builder = NotificationCompat.Builder(context, card.kind.channel.id).setSmallIcon(R.drawable.ic_stat_workout)
        apply(context, builder, card, Instant.now())
        return builder.build()
    }

    /**
     * Writes [card] onto [builder]: a new one for a standalone card, or the ongoing workout notification when the finished workout's
     * summary takes its place.
     */
    fun apply(context: Context, builder: NotificationCompat.Builder, card: LiveCard, now: Instant) {
        builder.setContentTitle(card.title)
            .setContentText(card.text)
            .setSubText(card.subText)
            .setCategory(if (card.kind == CardKind.FINISH) NotificationCompat.CATEGORY_STATUS else NotificationCompat.CATEGORY_REMINDER)
            .setColor(accentColor(context, card.accent))
            .setOngoing(card.ongoing)
            .setAutoCancel(!card.ongoing)
            .setOnlyAlertOnce(true)
            // The watch has its own tile and Ongoing Activity; a mirrored card would only repeat them.
            .setLocalOnly(true)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setContentIntent(LiveIntents.link(context, card.contentLink))
            .clearActions()
        card.actions.forEach { builder.addAction(0, it.title, LiveIntents.pendingIntent(context, it)) }
        card.timeoutMillis?.let { builder.setTimeoutAfter(it) }
        val countdownTo = card.countdownToMillis
        if (countdownTo != null) {
            builder.setShowWhen(true).setWhen(countdownTo).setUsesChronometer(true).setChronometerCountDown(true)
        } else {
            builder.setShowWhen(true).setWhen(now.toEpochMilli()).setUsesChronometer(false)
        }
        if (card.detailLines.isNotEmpty()) {
            builder.setStyle(NotificationCompat.BigTextStyle().bigText((listOf(card.text) + card.detailLines).joinToString("\n")))
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.BAKLAVA) builder.setRequestPromotedOngoing(card.ongoing)
    }

    /** The colour of an accent: the light and dark values of widgets/SPEC.md section 7, by the current appearance. */
    fun accentColor(context: Context, accent: LiveAccent): Int {
        val night = context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK == Configuration.UI_MODE_NIGHT_YES
        return when (accent) {
            LiveAccent.GREEN -> if (night) GreenDark else GreenLight
            LiveAccent.GOLD -> if (night) GoldDark else GoldLight
        }
    }

    /** "Workout summary" is silent (the countdown and the finish card); "Workout reminders" is the one channel that makes noise. */
    fun ensureChannels(context: Context) {
        val manager = NotificationManagerCompat.from(context)
        manager.createNotificationChannel(
            NotificationChannelCompat.Builder(LiveChannel.SUMMARY.id, NotificationManagerCompat.IMPORTANCE_LOW)
                .setName(context.getString(R.string.live_channel_summary))
                .setDescription(context.getString(R.string.live_channel_summary_description))
                .setShowBadge(false)
                .build(),
        )
        manager.createNotificationChannel(
            NotificationChannelCompat.Builder(LiveChannel.REMINDER.id, NotificationManagerCompat.IMPORTANCE_HIGH)
                .setName(context.getString(R.string.live_channel_reminder))
                .setDescription(context.getString(R.string.live_channel_reminder_description))
                .setShowBadge(false)
                .build(),
        )
    }
}
