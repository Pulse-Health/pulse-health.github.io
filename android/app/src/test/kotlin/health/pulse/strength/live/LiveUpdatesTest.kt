package health.pulse.strength.live

import android.Manifest
import android.app.AlarmManager
import android.app.Application
import android.app.Notification
import android.app.NotificationManager
import android.content.Intent
import androidx.test.core.app.ApplicationProvider
import com.google.common.truth.Truth.assertThat
import health.pulse.strength.R
import health.pulse.strength.core.WorkoutSnapshot
import health.pulse.strength.core.widgets.DeepLinks
import health.pulse.strength.core.widgets.WidgetCommand
import health.pulse.strength.core.widgets.WidgetCommands
import health.pulse.strength.runtime.PreviewRuntime
import health.pulse.strength.runtime.StrengthRuntime
import health.pulse.strength.services.WorkoutNotifications
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowAlarmManager

/**
 * LA-01 ... LA-05 on the real ongoing notification: `WorkoutNotifications.ongoing` builds it, `LiveUpdates.decorate` (its last step)
 * decorates it. Android 14 here; the Android 16 style is in [LiveUpdatesAndroid16Test].
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class LiveUpdatesTest {
    private lateinit var app: Application
    private lateinit var manager: NotificationManager
    private lateinit var runtime: PreviewRuntime

    @Before
    fun setUp() {
        app = ApplicationProvider.getApplicationContext()
        shadowOf(app).grantPermissions(Manifest.permission.POST_NOTIFICATIONS)
        manager = app.getSystemService(NotificationManager::class.java)
        runtime = PreviewRuntime()
        StrengthRuntime.installForTest(runtime)
    }

    @After
    fun restore() {
        StrengthRuntime.installForTest(PreviewRuntime())
    }

    private fun ongoing(snapshot: WorkoutSnapshot): Notification = WorkoutNotifications.ongoing(app, snapshot, NOW)

    private fun title(n: Notification) = n.extras.getCharSequence(Notification.EXTRA_TITLE).toString()
    private fun text(n: Notification) = n.extras.getCharSequence(Notification.EXTRA_TEXT).toString()
    private fun bigText(n: Notification) = n.extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()
    private fun actionTitles(n: Notification) = (n.actions ?: emptyArray()).map { it.title.toString() }
    private fun tapTarget(n: Notification) = shadowOf(n.contentIntent).savedIntent.component?.className

    /** The command that a button of [n] sends, as the receiver decodes it. */
    private fun commandOf(n: Notification, title: String): WidgetCommand {
        val action = n.actions.single { it.title.toString() == title }
        return WorkoutActionReceiver.decode(shadowOf(action.actionIntent).savedIntent.getStringExtra(WorkoutActionReceiver.EXTRA_COMMAND)!!)!!
    }

    private fun alarms() = shadowOf(app.getSystemService(AlarmManager::class.java)).scheduledAlarms

    /** The intent that the alarm delivers; Robolectric offers no other accessor than the field it deprecated. */
    @Suppress("DEPRECATION")
    private fun intentOf(alarm: ShadowAlarmManager.ScheduledAlarm): Intent = shadowOf(alarm.operation).savedIntent

    /** The receiver finishes its work on the app scope; wait for the engine to see the command. */
    private fun awaitReceived(entry: String) {
        repeat(500) {
            if (entry in runtime.received) return
            Thread.sleep(10)
        }
        assertThat(runtime.received).contains(entry)
    }

    // region A workout without live moments

    @Test
    fun aPlainWorkoutKeepsTheBaseNotificationAsItWas() {
        val n = ongoing(loggingSnapshot())
        assertThat(title(n)).isEqualTo("Bench Press")
        assertThat(text(n)).isEqualTo("Set 4 of 5 · 82.5 kg × 6")
        assertThat(actionTitles(n)).containsExactly("Log set", "Weight −", "Weight +").inOrder()
        assertThat(bigText(n)).isNull()
        assertThat(tapTarget(n)).isEqualTo("health.pulse.strength.MainActivity")
        assertThat(n.flags and Notification.FLAG_ONGOING_EVENT).isNotEqualTo(0)
        assertThat(alarms()).isEmpty()
    }

    @Test
    fun aRestOpensBenchModeWhenTheNotificationIsTapped() {
        val resting = ongoing(restingSnapshot())
        assertThat(title(resting)).isEqualTo("Rest")
        assertThat(actionTitles(resting)).containsExactly("−15 s", "+15 s", "Skip").inOrder()
        assertThat(tapTarget(resting)).isEqualTo(BenchModeActivity::class.java.name)
        assertThat(tapTarget(ongoing(restingSnapshot(remaining = -2)))).isEqualTo(BenchModeActivity::class.java.name)
        assertThat(tapTarget(ongoing(loggingSnapshot()))).isEqualTo("health.pulse.strength.MainActivity")
        assertThat(tapTarget(ongoing(pausedSnapshot()))).isEqualTo("health.pulse.strength.MainActivity")
    }

    // endregion

    // region LA-01 PR moment

    @Test
    fun aRecordFlashesAndAnAlarmEndsTheFlash() {
        val n = ongoing(restingSnapshot().copy(moment = moment()))
        assertThat(title(n)).isEqualTo("New record: Bench Press")
        assertThat(text(n)).isEqualTo("85 × 5 · e1RM 99 kg (+4)")
        assertThat(n.color).isEqualTo(0xFF7A5200.toInt())
        // The rest buttons stay: the flash replaces words, not controls.
        assertThat(actionTitles(n)).containsExactly("−15 s", "+15 s", "Skip").inOrder()
        val alarm = alarms().single()
        assertThat(alarm.triggerAtMs).isEqualTo(NOW.plusSeconds(4).toEpochMilli())
        assertThat(intentOf(alarm).action).isEqualTo(LiveAlarmReceiver.ACTION_MOMENT_END)
        assertThat(alarm.isAllowWhileIdle).isTrue()
    }

    @Test
    fun theFlashAlarmGoesWhenTheNotificationIsDrawnWithoutTheFlash() {
        ongoing(restingSnapshot().copy(moment = moment()))
        assertThat(alarms()).hasSize(1)
        val n = ongoing(restingSnapshot().copy(moment = moment(expiresIn = 0)))
        assertThat(title(n)).isEqualTo("Rest")
        assertThat(alarms()).isEmpty()
    }

    @Test
    fun theFlashAlarmReceiverRedrawsNothingWithoutAWorkoutAndDoesNotCrash() {
        LiveAlarmReceiver().onReceive(app, Intent(LiveAlarmReceiver.ACTION_MOMENT_END))
        assertThat(shadowOf(manager).getNotification(WorkoutNotifications.ONGOING_ID)).isNull()
    }

    // endregion

    // region LA-02 superset and LA-03 plates

    @Test
    fun aSupersetListsItsMembersAndLogA2LogsExactlyThatSet() {
        val n = ongoing(loggingSnapshot().copy(superset = superset()))
        assertThat(title(n)).isEqualTo("Bench Press")
        assertThat(text(n)).isEqualTo("Set 4 of 5 · 82.5 kg × 6")
        assertThat(bigText(n)!!.lines()).containsAtLeast(
            "Set 4 of 5 · 82.5 kg × 6",
            "A1 Lateral Raise · 10 × 12 (done)",
            "A2 Triceps Pushdown · 25 × 12 (now)",
        ).inOrder()
        assertThat(actionTitles(n)).containsExactly("Log A2", "Weight −", "Weight +").inOrder()
        assertThat(commandOf(n, "Log A2")).isEqualTo(
            WidgetCommand.of(WidgetCommands.LOG_SET, WidgetCommands.ARG_EXERCISE_ID to EXERCISE_ID.toString(), WidgetCommands.ARG_SET_ID to SET_ID.toString()),
        )
    }

    @Test
    fun theButtonsOfASupersetReachTheEngine() {
        val n = ongoing(loggingSnapshot().copy(superset = superset()))
        val intent = shadowOf(n.actions.single { it.title == "Log A2" }.actionIntent).savedIntent
        assertThat(intent.component?.className).isEqualTo(WorkoutActionReceiver::class.java.name)
        WorkoutActionReceiver().onReceive(app, intent)
        awaitReceived("logSet:$EXERCISE_ID:$SET_ID")
        val up = shadowOf(n.actions.single { it.title == "Weight +" }.actionIntent).savedIntent
        WorkoutActionReceiver().onReceive(app, up)
        awaitReceived("nudge:1:0")
    }

    @Test
    fun thePlatesAreALineOfTheExpandedText() {
        val n = ongoing(loggingSnapshot().copy(plates = plates()))
        assertThat(text(n)).isEqualTo("Set 4 of 5 · 82.5 kg × 6")
        assertThat(bigText(n)!!.lines()).containsAtLeast("Set 4 of 5 · 82.5 kg × 6", "Per side: 20 + 10 + 2.5").inOrder()
        assertThat(actionTitles(n)).containsExactly("Log set", "Weight −", "Weight +").inOrder()
    }

    @Test
    fun theLineTheDecorationRestatesIsTheLineTheBaseShows() {
        // The expanded text of a decorated card starts with the text of the plain one, in every phase that has a target set.
        listOf(loggingSnapshot(), restingSnapshot(), restingSnapshot(remaining = -2)).forEach { plain ->
            val decorated = ongoing(plain.copy(plates = plates()))
            assertThat(bigText(decorated)!!.lines().first()).isEqualTo(text(ongoing(plain)))
            assertThat(text(decorated)).isEqualTo(text(ongoing(plain)))
        }
    }

    @Test
    fun theLabelsOfTheReplacedButtonsAreTheBaseLabels() {
        assertThat(app.getString(R.string.action_weight_minus)).isEqualTo("Weight −")
        assertThat(app.getString(R.string.action_weight_plus)).isEqualTo("Weight +")
        assertThat(app.getString(R.string.action_reps_minus)).isEqualTo("Reps −")
        assertThat(app.getString(R.string.action_reps_plus)).isEqualTo("Reps +")
        assertThat(app.getString(R.string.action_skip)).isEqualTo("Skip")
        assertThat(app.getString(R.string.notification_next, "x")).isEqualTo("Next: x")
    }

    // endregion

    // region LA-04 coach tip

    @Test
    fun theCoachTipReplacesTheButtonsWithItsAnswers() {
        val n = ongoing(restingSnapshot().copy(coachTip = coachTip()))
        assertThat(text(n)).isEqualTo("Coach: add 2.5 kg for set 3 to stay at 1–2 RIR.")
        assertThat(actionTitles(n)).containsExactly("82.5 kg", "Keep 80", "Skip").inOrder()
        assertThat(commandOf(n, "82.5 kg")).isEqualTo(
            WidgetCommand.of(WidgetCommands.APPLY_COACH_TIP, WidgetCommands.ARG_SET_ID to SET_ID.toString(), WidgetCommands.ARG_WEIGHT_KG to "82.5"),
        )
        assertThat(bigText(n)!!.lines()).contains("3 reps in reserve on set 2")
    }

    @Test
    fun applyingTheTipSendsItToTheEngine() {
        val n = ongoing(restingSnapshot().copy(coachTip = coachTip()))
        WorkoutActionReceiver().onReceive(app, shadowOf(n.actions.single { it.title == "82.5 kg" }.actionIntent).savedIntent)
        awaitReceived("applyCoachTip:$SET_ID:82.5")
    }

    @Test
    fun keepingTheWeightOnlyDismissesTheTip() {
        val tipped = restingSnapshot().copy(coachTip = coachTip())
        val n = ongoing(tipped)
        WorkoutActionReceiver().onReceive(app, shadowOf(n.actions.single { it.title == "Keep 80" }.actionIntent).savedIntent)
        repeat(500) { if (LiveState.of(app).dismissedCoachTip == null) Thread.sleep(10) }
        assertThat(LiveState.of(app).dismissedCoachTip).isEqualTo(SET_ID.toString())
        // Nothing was sent to the engine, and the next drawing of the same snapshot has no tip any more.
        assertThat(runtime.received).isEmpty()
        val after = ongoing(tipped)
        assertThat(text(after)).isEqualTo("Next: Set 4 · 82.5 kg × 6")
        assertThat(actionTitles(after)).containsExactly("−15 s", "+15 s", "Skip").inOrder()
    }

    @Test
    fun aDamagedButtonDoesNothing() {
        WorkoutActionReceiver().onReceive(app, Intent(WorkoutActionReceiver.ACTION_COMMAND).putExtra(WorkoutActionReceiver.EXTRA_COMMAND, "{not json"))
        WorkoutActionReceiver().onReceive(app, Intent(WorkoutActionReceiver.ACTION_COMMAND))
        WorkoutActionReceiver().onReceive(app, Intent("some.other.ACTION"))
        Thread.sleep(50)
        assertThat(runtime.received).isEmpty()
        assertThat(WorkoutActionReceiver.decode("{not json")).isNull()
    }

    // endregion

    // region LA-05 finish

    @Test
    fun aFinishedWorkoutTurnsTheNotificationIntoTheSummary() {
        val n = ongoing(loggingSnapshot().copy(finish = finishBrief()))
        assertThat(title(n)).isEqualTo("Upper A · Push done")
        assertThat(text(n)).isEqualTo("52 min · 22 sets · 9.1 t · 1 PR")
        assertThat(n.extras.getCharSequence(Notification.EXTRA_SUB_TEXT).toString()).isEqualTo("Saved to Health")
        assertThat(n.flags and Notification.FLAG_ONGOING_EVENT).isEqualTo(0)
        assertThat(n.flags and Notification.FLAG_AUTO_CANCEL).isNotEqualTo(0)
        assertThat(n.timeoutAfter).isEqualTo(2 * 60 * 60 * 1000L)
        assertThat(actionTitles(n)).containsExactly("Share")
        assertThat(shadowOf(n.contentIntent).savedIntent.dataString).isEqualTo(DeepLinks.hub)
        assertThat(n.extras.getBoolean(Notification.EXTRA_SHOW_CHRONOMETER)).isFalse()
    }

    @Test
    fun theShareButtonOpensTheShareSheetWithTheSummary() {
        val n = ongoing(loggingSnapshot().copy(finish = finishBrief()))
        val chooser = shadowOf(n.actions.single().actionIntent).savedIntent
        assertThat(chooser.action).isEqualTo(Intent.ACTION_CHOOSER)
        @Suppress("DEPRECATION")
        val send = chooser.getParcelableExtra<Intent>(Intent.EXTRA_INTENT)!!
        assertThat(send.action).isEqualTo(Intent.ACTION_SEND)
        assertThat(send.getStringExtra(Intent.EXTRA_TEXT)).isEqualTo("Upper A · Push: 52 min, 22 sets, 9.1 t, 1 PR")
    }

    @Test
    fun showFinishPostsTheSummaryCardThatLeavesAfterTwoHours() {
        LiveUpdates.showFinish(app, finishBrief().copy(personalRecordCount = 0, sets = 1, savedToHealth = false))
        val n = shadowOf(manager).getNotification(FINISH_NOTIFICATION_ID)!!
        assertThat(title(n)).isEqualTo("Upper A · Push done")
        assertThat(text(n)).isEqualTo("52 min · 1 set · 9.1 t")
        assertThat(n.extras.getCharSequence(Notification.EXTRA_SUB_TEXT)).isNull()
        assertThat(n.timeoutAfter).isEqualTo(2 * 60 * 60 * 1000L)
        assertThat(n.flags and Notification.FLAG_ONGOING_EVENT).isEqualTo(0)
        assertThat(n.channelId).isEqualTo("workout_summary")
        assertThat(manager.getNotificationChannel("workout_summary")).isNotNull()
    }

    @Test
    fun showFinishNeedsTheNotificationPermission() {
        shadowOf(app).denyPermissions(Manifest.permission.POST_NOTIFICATIONS)
        LiveUpdates.showFinish(app, finishBrief())
        assertThat(shadowOf(manager).getNotification(FINISH_NOTIFICATION_ID)).isNull()
    }

    // endregion

    // region Planned sessions and the running workout

    @Test
    fun aRunningWorkoutEndsAPlannedSession() {
        PlannedSessions.schedule(app, "template", System.currentTimeMillis() + 3 * 60 * 60 * 1000L)
        assertThat(alarms()).hasSize(2)
        ongoing(loggingSnapshot())
        assertThat(alarms()).isEmpty()
        assertThat(PlannedSessionStore(app.getSharedPreferences("pulse_planned_session", 0)).read()).isNull()
    }

    @Test
    fun refreshEndsAPlannedSessionOnlyWhileAWorkoutRuns() {
        PlannedSessions.schedule(app, "template", System.currentTimeMillis() + 3 * 60 * 60 * 1000L)
        runBlocking { LiveUpdates.refresh(app) }
        assertThat(alarms()).hasSize(2)
        runtime.publish(previewWith(loggingSnapshot()))
        runBlocking { LiveUpdates.refresh(app) }
        assertThat(alarms()).isEmpty()
    }

    @Test
    fun repostWithoutAWorkoutPostsNothing() {
        LiveUpdates.repost(app)
        assertThat(shadowOf(manager).getNotification(WorkoutNotifications.ONGOING_ID)).isNull()
    }

    // endregion

    private companion object {
        /** `CardKind.FINISH.notificationId`, spelled out so a change of the id is noticed. */
        const val FINISH_NOTIFICATION_ID = 4102
    }
}
