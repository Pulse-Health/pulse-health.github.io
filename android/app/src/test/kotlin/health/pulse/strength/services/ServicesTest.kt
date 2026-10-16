package health.pulse.strength.services

import android.Manifest
import android.app.Application
import android.app.Notification
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import androidx.test.core.app.ApplicationProvider
import com.google.common.truth.Truth.assertThat
import health.pulse.strength.PulseStrengthApplication
import health.pulse.strength.StrengthAppEnvironment
import health.pulse.strength.core.ExerciseLibrary
import health.pulse.strength.core.SnapshotBuilder
import health.pulse.strength.core.SnapshotPhase
import health.pulse.strength.core.WorkoutAction
import java.time.Instant
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/** The platform services, run against the real application object: notification content, buttons, rest alerts, manifest policy. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class ServicesTest {
    private lateinit var app: PulseStrengthApplication
    private lateinit var environment: StrengthAppEnvironment
    private lateinit var manager: NotificationManager

    @Before
    fun setUp() {
        app = ApplicationProvider.getApplicationContext<Application>() as PulseStrengthApplication
        shadowOf(app).grantPermissions(Manifest.permission.POST_NOTIFICATIONS)
        environment = app.environment
        manager = app.getSystemService(NotificationManager::class.java)
    }

    private fun startBenchWorkout() {
        val controller = environment.controller
        controller.startWorkout(null, "Push day")
        controller.send(WorkoutAction.AddExercises(listOf(ExerciseLibrary.exercise("bench")!!)))
    }

    private fun ongoing(): Notification = shadowOf(manager).getNotification(WorkoutNotifications.ONGOING_ID)!!

    private fun title(n: Notification) = n.extras.getCharSequence(Notification.EXTRA_TITLE).toString()
    private fun text(n: Notification) = n.extras.getCharSequence(Notification.EXTRA_TEXT).toString()
    private fun actionTitles(n: Notification) = (n.actions ?: emptyArray()).map { it.title.toString() }

    // region Manifest policy

    @Test
    fun theAppHasNoNetworkPermission() {
        val info = app.packageManager.getPackageInfo(app.packageName, PackageManager.GET_PERMISSIONS)
        val permissions = info.requestedPermissions?.toList() ?: emptyList()
        // The privacy policy and the Play data-safety answers say the app cannot reach the network: keep it true.
        assertThat(permissions).containsNoneOf(
            Manifest.permission.INTERNET,
            Manifest.permission.ACCESS_NETWORK_STATE,
            Manifest.permission.ACCESS_WIFI_STATE,
            Manifest.permission.READ_EXTERNAL_STORAGE,
            Manifest.permission.WRITE_EXTERNAL_STORAGE,
            Manifest.permission.ACCESS_FINE_LOCATION,
            Manifest.permission.READ_CONTACTS,
            Manifest.permission.CAMERA,
            Manifest.permission.RECORD_AUDIO,
        )
        assertThat(permissions).contains(Manifest.permission.POST_NOTIFICATIONS)
    }

    @Test
    fun theApplicationStartsAndRestoresNothing() {
        assertThat(environment.controller.state.value).isNull()
        assertThat(environment.services).isNotNull()
    }

    // endregion

    // region Ongoing notification

    @Test
    fun noNotificationWithoutAWorkout() {
        assertThat(shadowOf(manager).getNotification(WorkoutNotifications.ONGOING_ID)).isNull()
    }

    @Test
    fun loggingPhaseShowsTheNextSetAndTheLogButtons() {
        startBenchWorkout()
        val n = ongoing()
        assertThat(title(n)).isEqualTo("Barbell bench press")
        assertThat(text(n)).isEqualTo("Set 1 of 3 · 60 kg × 8")
        assertThat(actionTitles(n)).containsExactly("Log set", "Weight −", "Weight +").inOrder()
        assertThat(n.flags and Notification.FLAG_ONGOING_EVENT).isNotEqualTo(0)
        assertThat(n.extras.getBoolean(Notification.EXTRA_SHOW_CHRONOMETER)).isTrue()
    }

    @Test
    fun aWorkoutWithoutExercisesSaysSoInsteadOfAllSetsLogged() {
        environment.controller.startWorkout(null, "Empty one")
        val n = ongoing()
        assertThat(title(n)).isEqualTo("Empty one")
        assertThat(text(n)).isEqualTo("No exercises yet. Open the app to add some.")
        assertThat(actionTitles(n)).isEmpty()
    }

    @Test
    fun finishingEverySetShowsTheTotalsWithTheRightPlural() {
        environment.controller.startWorkout(null, "One set")
        val ex = ExerciseLibrary.exercise("bench")!!.copy(defaults = ExerciseLibrary.exercise("bench")!!.defaults.copy(sets = 1, restSeconds = 0))
        environment.controller.send(WorkoutAction.AddExercises(listOf(ex)))
        val entry = environment.controller.state.value!!.exercises[0]
        environment.controller.send(WorkoutAction.LogSet(entry.id, entry.sets[0].id))
        val n = ongoing()
        assertThat(title(n)).isEqualTo("All sets logged")
        assertThat(text(n)).isEqualTo("1 set · 480 kg")
    }

    @Test
    fun loggingASetStartsARestWithACountdownAndRestButtons() {
        startBenchWorkout()
        val state = environment.controller.state.value!!
        val entry = state.exercises[0]
        environment.controller.send(WorkoutAction.LogSet(entry.id, entry.sets[0].id))

        val n = ongoing()
        assertThat(title(n)).isEqualTo("Rest")
        assertThat(text(n)).isEqualTo("Next: Set 2 · 60 kg × 8")
        assertThat(n.extras.getBoolean(Notification.EXTRA_CHRONOMETER_COUNT_DOWN)).isTrue()
        assertThat(actionTitles(n)).containsExactly("−15 s", "+15 s", "Skip").inOrder()
    }

    @Test
    fun aBodyweightExerciseNudgesTheRepsNotTheWeight() {
        environment.controller.startWorkout(null, "Calisthenics")
        environment.controller.send(WorkoutAction.AddExercises(listOf(ExerciseLibrary.exercise("pushup")!!)))
        val n = ongoing()
        assertThat(text(n)).isEqualTo("Set 1 of 3 · 12 reps")
        assertThat(actionTitles(n)).containsExactly("Log set", "Reps −", "Reps +").inOrder()
    }

    @Test
    fun aRestartedProcessRestoresTheWorkoutAndPostsItsNotificationAgain() {
        startBenchWorkout()
        manager.cancelAll()
        assertThat(shadowOf(manager).getNotification(WorkoutNotifications.ONGOING_ID)).isNull()

        // What Application.onCreate does in a new process (the system killed the old one): a fresh environment on the same files, then
        // the restore. The services are registered before the restore, so they see the workout that comes back.
        val restarted = StrengthAppEnvironment.live(app)
        assertThat(restarted.controller.state.value).isNull()
        restarted.controller.restoreFromDisk()

        assertThat(restarted.controller.state.value?.name).isEqualTo("Push day")
        assertThat(restarted.controller.state.value?.exercises?.single()?.exercise?.id).isEqualTo("bench")
        assertThat(title(ongoing())).isEqualTo("Barbell bench press")
    }

    @Test
    fun finishingOrDiscardingRemovesTheNotifications() {
        startBenchWorkout()
        assertThat(shadowOf(manager).getNotification(WorkoutNotifications.ONGOING_ID)).isNotNull()
        environment.controller.discard()
        assertThat(shadowOf(manager).getNotification(WorkoutNotifications.ONGOING_ID)).isNull()
    }

    @Test
    fun withoutTheNotificationPermissionNothingIsPostedAndTheAppStillWorks() {
        shadowOf(app).denyPermissions(Manifest.permission.POST_NOTIFICATIONS)
        startBenchWorkout()
        assertThat(shadowOf(manager).getNotification(WorkoutNotifications.ONGOING_ID)).isNull()
        assertThat(environment.controller.state.value).isNotNull()
    }

    // endregion

    // region Buttons

    private fun broadcast(action: Intent) {
        NotificationActionReceiver().onReceive(app, action)
    }

    @Test
    fun theLogSetButtonLogsTheTargetSetOnce() {
        startBenchWorkout()
        val before = environment.controller.state.value!!
        val snapshot = SnapshotBuilder.make(before, Instant.now())
        val intent = Intent(WorkoutNotifications.ACTION_LOG_SET)
            .putExtra(WorkoutNotifications.EXTRA_EXERCISE_ID, snapshot.targetExerciseID.toString())
            .putExtra(WorkoutNotifications.EXTRA_SET_ID, snapshot.targetSetID.toString())
        broadcast(intent)
        broadcast(intent) // a stale second tap must not log the next set
        val after = environment.controller.state.value!!
        assertThat(after.exercises[0].sets.map { it.isDone }).containsExactly(true, false, false).inOrder()
    }

    private fun logSetButton(n: Notification): android.app.PendingIntent = n.actions.first { it.title == "Log set" }.actionIntent

    /** A tap on a notification button: the system fires its PendingIntent and the receiver runs on the main thread. */
    private fun tap(button: android.app.PendingIntent) {
        button.send()
        shadowOf(android.os.Looper.getMainLooper()).idle()
    }

    @Test
    fun everySetGetsItsOwnLogSetButtonSoAStaleTapCannotLogTheNextSet() {
        startBenchWorkout()
        val first = logSetButton(ongoing())
        assertThat(shadowOf(first).savedIntent.data.toString()).startsWith("pulse-strength://log/")

        // The real button, fired the way the system fires it, logs the first set and starts the rest.
        tap(first)
        assertThat(environment.controller.state.value!!.exercises[0].sets.map { it.isDone }).containsExactly(true, false, false).inOrder()
        environment.controller.send(WorkoutAction.SkipRest)

        // The notification now offers the second set through a different PendingIntent.
        val second = logSetButton(ongoing())
        assertThat(second).isNotEqualTo(first)
        assertThat(shadowOf(second).savedIntent.data).isNotEqualTo(shadowOf(first).savedIntent.data)

        // A late tap on the old button must not log the second set.
        tap(first)
        assertThat(environment.controller.state.value!!.exercises[0].sets.map { it.isDone }).containsExactly(true, false, false).inOrder()
        tap(second)
        assertThat(environment.controller.state.value!!.exercises[0].sets.map { it.isDone }).containsExactly(true, true, false).inOrder()
    }

    @Test
    fun theWeightButtonsMoveTheNextSetByOneStep() {
        startBenchWorkout()
        broadcast(Intent(WorkoutNotifications.ACTION_NUDGE).putExtra(WorkoutNotifications.EXTRA_WEIGHT_STEPS, 1))
        assertThat(environment.controller.state.value!!.exercises[0].sets[0].weightKg).isEqualTo(62.5)
        broadcast(Intent(WorkoutNotifications.ACTION_NUDGE).putExtra(WorkoutNotifications.EXTRA_WEIGHT_STEPS, -1))
        assertThat(environment.controller.state.value!!.exercises[0].sets[0].weightKg).isEqualTo(60.0)
    }

    @Test
    fun theRestButtonsAdjustAndSkipTheRest() {
        startBenchWorkout()
        val entry = environment.controller.state.value!!.exercises[0]
        environment.controller.send(WorkoutAction.LogSet(entry.id, entry.sets[0].id))
        val total = environment.controller.state.value!!.rest!!.totalSeconds
        broadcast(Intent(WorkoutNotifications.ACTION_ADJUST_REST).putExtra(WorkoutNotifications.EXTRA_SECONDS, 15))
        assertThat(environment.controller.state.value!!.rest!!.totalSeconds).isEqualTo(total + 15)
        broadcast(Intent(WorkoutNotifications.ACTION_SKIP_REST))
        assertThat(environment.controller.state.value!!.rest).isNull()
    }

    @Test
    fun aMalformedOrForeignIntentIsIgnored() {
        startBenchWorkout()
        val before = environment.controller.state.value
        broadcast(Intent(WorkoutNotifications.ACTION_LOG_SET).putExtra(WorkoutNotifications.EXTRA_EXERCISE_ID, "not-a-uuid"))
        broadcast(Intent("some.other.ACTION"))
        assertThat(environment.controller.state.value).isEqualTo(before)
    }

    // endregion

    // region Rest alert

    @Test
    fun aRestThatEndedInTheBackgroundSoundsTheAlertOnceAndFlipsTheOngoingNotification() {
        startBenchWorkout()
        val entry = environment.controller.state.value!!.exercises[0]
        environment.controller.send(WorkoutAction.LogSet(entry.id, entry.sets[0].id))
        val rest = environment.controller.state.value!!.rest!!

        // The app is in the background (no started activity) and the rest end has passed.
        val clock = object { var now: Instant = rest.endsAt.plusSeconds(1) }
        val alerts = RestAlerts(app, environment.controller, AppForegroundTracker(), PulseSettings(app)) { clock.now }
        alerts.onRestEnded(rest.endsAt.toEpochMilli())

        val alert = shadowOf(manager).getNotification(WorkoutNotifications.REST_ALERT_ID)
        assertThat(alert).isNotNull()
        assertThat(title(alert!!)).isEqualTo("Rest over · Go")
        assertThat(title(ongoing())).isEqualTo("Rest over · Go")

        // The second alarm path (the PendingIntent backup) must not alert again.
        manager.cancel(WorkoutNotifications.REST_ALERT_ID)
        alerts.onRestEnded(rest.endsAt.toEpochMilli())
        assertThat(shadowOf(manager).getNotification(WorkoutNotifications.REST_ALERT_ID)).isNull()
    }

    @Test
    fun noAlertWhileTheAppIsOnScreenOrWhenAlertsAreOff() {
        startBenchWorkout()
        val entry = environment.controller.state.value!!.exercises[0]
        environment.controller.send(WorkoutAction.LogSet(entry.id, entry.sets[0].id))
        val rest = environment.controller.state.value!!.rest!!
        val later = rest.endsAt.plusSeconds(1)

        val foreground = AppForegroundTracker().also { it.onActivityStarted(android.app.Activity()) }
        RestAlerts(app, environment.controller, foreground, PulseSettings(app)) { later }.onRestEnded(rest.endsAt.toEpochMilli())
        assertThat(shadowOf(manager).getNotification(WorkoutNotifications.REST_ALERT_ID)).isNull()

        environment.controller.send(WorkoutAction.SetAlertWhenRestEnds(false))
        val newest = environment.controller.state.value!!.rest!!
        RestAlerts(app, environment.controller, AppForegroundTracker(), PulseSettings(app)) { newest.endsAt.plusSeconds(1) }
            .onRestEnded(newest.endsAt.toEpochMilli())
        assertThat(shadowOf(manager).getNotification(WorkoutNotifications.REST_ALERT_ID)).isNull()
    }

    @Test
    fun aStaleAlarmForASkippedRestDoesNothing() {
        startBenchWorkout()
        val entry = environment.controller.state.value!!.exercises[0]
        environment.controller.send(WorkoutAction.LogSet(entry.id, entry.sets[0].id))
        val rest = environment.controller.state.value!!.rest!!
        environment.controller.send(WorkoutAction.SkipRest)
        RestAlerts(app, environment.controller, AppForegroundTracker(), PulseSettings(app)) { rest.endsAt.plusSeconds(1) }
            .onRestEnded(rest.endsAt.toEpochMilli())
        assertThat(shadowOf(manager).getNotification(WorkoutNotifications.REST_ALERT_ID)).isNull()
    }

    @Test
    fun theSnapshotPhaseOfAnEndedRestIsRestOver() {
        startBenchWorkout()
        val entry = environment.controller.state.value!!.exercises[0]
        environment.controller.send(WorkoutAction.LogSet(entry.id, entry.sets[0].id))
        val state = environment.controller.state.value!!
        val snapshot = SnapshotBuilder.make(state, state.rest!!.endsAt.plusSeconds(1))
        assertThat(snapshot.phase).isEqualTo(SnapshotPhase.REST_OVER)
        val n = WorkoutNotifications.ongoing(app as Context, SnapshotBuilder.make(state, Instant.now()), state.rest!!.endsAt.plusSeconds(1))
        assertThat(title(n)).isEqualTo("Rest over · Go")
    }

    // endregion
}
