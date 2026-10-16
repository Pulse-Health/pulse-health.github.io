package health.pulse.strength.core

import com.google.common.truth.Truth.assertThat
import com.google.common.truth.Truth.assertWithMessage
import java.time.Instant
import java.util.UUID
import org.junit.Test

// Port of PublicInitializerTests.swift (Swift: 6 tests).
//
// The presentation, snapshot and history value types have explicit public initializers in Swift (code outside the module cannot use an
// internal memberwise initializer). Kotlin data classes always have a public primary constructor, so what remains of these tests is
// the part that still means something: they rebuild real values field by field through the constructors, so a field that a
// constructor forgets, swaps or does not default shows up as a difference.

class PublicInitializerTests {
    /** Fixtures of the sync tests used here (Swift `SvcSyncFix`), kept private to this class. */
    private object Fix {
        /** 2026-10-13T19:30:00Z. */
        val epoch: Instant = Instant.ofEpochSecond(1_791_919_800L)

        fun at(offset: Double): Instant = epoch.addingTimeInterval(offset)

        fun uuid(n: Int): UUID {
            var hex = n.toString(16).uppercase()
            hex = "0".repeat(12 - hex.length) + hex
            return UUID.fromString("0000FEED-0000-4000-8000-$hex")
        }
    }

    // region Rebuilding

    private fun rebuilt(segment: ActiveWorkoutPresentation.Segment): ActiveWorkoutPresentation.Segment =
        ActiveWorkoutPresentation.Segment(fraction = segment.fraction, isCurrent = segment.isCurrent)

    private fun rebuilt(header: ActiveWorkoutPresentation.Header): ActiveWorkoutPresentation.Header =
        ActiveWorkoutPresentation.Header(
            title = header.title, clockText = header.clockText, isPaused = header.isPaused, volumeText = header.volumeText,
            setsText = header.setsText, heartRateText = header.heartRateText, hasHeartRate = header.hasHeartRate,
            segments = header.segments.map { rebuilt(it) },
        )

    private fun rebuilt(navigator: ActiveWorkoutPresentation.Navigator): ActiveWorkoutPresentation.Navigator =
        ActiveWorkoutPresentation.Navigator(
            position = navigator.position, total = navigator.total, canGoPrevious = navigator.canGoPrevious, canGoNext = navigator.canGoNext,
        )

    private fun rebuilt(row: ActiveWorkoutPresentation.SetRow): ActiveWorkoutPresentation.SetRow =
        ActiveWorkoutPresentation.SetRow(
            id = row.id, number = row.number, type = row.type, previousText = row.previousText, weightText = row.weightText,
            repsText = row.repsText, weightEditable = row.weightEditable, isDone = row.isDone, isNext = row.isNext,
            isPersonalRecord = row.isPersonalRecord, estimated1RM = row.estimated1RM, rir = row.rir, rirText = row.rirText,
            accessibilityLabel = row.accessibilityLabel,
        )

    private fun rebuilt(card: ActiveWorkoutPresentation.Card): ActiveWorkoutPresentation.Card =
        ActiveWorkoutPresentation.Card(
            exerciseID = card.exerciseID, exercise = card.exercise, recoveryPercent = card.recoveryPercent,
            recoveryLevel = card.recoveryLevel, supersetLabel = card.supersetLabel, restSeconds = card.restSeconds,
            restText = card.restText, note = card.note, weightColumnTitle = card.weightColumnTitle,
            repsColumnTitle = card.repsColumnTitle, coachTip = card.coachTip, rows = card.rows.map { rebuilt(it) },
        )

    private fun rebuilt(dock: ActiveWorkoutPresentation.Dock): ActiveWorkoutPresentation.Dock =
        ActiveWorkoutPresentation.Dock(
            phase = dock.phase, remainingSeconds = dock.remainingSeconds, totalSeconds = dock.totalSeconds, fraction = dock.fraction,
            remainingText = dock.remainingText, nextSetText = dock.nextSetText, showsRIR = dock.showsRIR,
            rirSelection = dock.rirSelection, isPaused = dock.isPaused,
        )

    private fun rebuilt(presentation: ActiveWorkoutPresentation): ActiveWorkoutPresentation {
        val totals = presentation.totals
        val check = presentation.finishCheck
        return ActiveWorkoutPresentation(
            header = rebuilt(presentation.header),
            navigator = presentation.navigator?.let { rebuilt(it) },
            card = presentation.card?.let { rebuilt(it) },
            dock = presentation.dock?.let { rebuilt(it) },
            undoText = presentation.undoText,
            isEmpty = presentation.isEmpty,
            totals = ActiveWorkoutPresentation.Totals(
                loggedSets = totals.loggedSets, totalSets = totals.totalSets, volumeKg = totals.volumeKg,
                completedExercises = totals.completedExercises,
            ),
            finishCheck = ActiveWorkoutPresentation.FinishCheck(
                loggedSets = check.loggedSets, unloggedSets = check.unloggedSets, canFinish = check.canFinish, title = check.title,
                message = check.message, templateDiff = check.templateDiff, diffMessage = check.diffMessage,
                asksToUpdateTemplate = check.asksToUpdateTemplate,
            ),
        )
    }

    private fun rebuilt(snapshot: WorkoutSnapshot): WorkoutSnapshot =
        WorkoutSnapshot(
            workoutID = snapshot.workoutID, revision = snapshot.revision, workoutName = snapshot.workoutName,
            activeStart = snapshot.activeStart, isPaused = snapshot.isPaused, elapsedWhenPaused = snapshot.elapsedWhenPaused,
            phase = snapshot.phase, exerciseName = snapshot.exerciseName, exerciseIndex = snapshot.exerciseIndex,
            exerciseCount = snapshot.exerciseCount, targetExerciseID = snapshot.targetExerciseID, targetSetID = snapshot.targetSetID,
            setLabel = snapshot.setLabel, tracking = snapshot.tracking, weightText = snapshot.weightText, repsText = snapshot.repsText,
            repsUnit = snapshot.repsUnit, showsWeight = snapshot.showsWeight, restStartedAt = snapshot.restStartedAt,
            restEndsAt = snapshot.restEndsAt, restTotalSeconds = snapshot.restTotalSeconds,
            restFrozenRemaining = snapshot.restFrozenRemaining, heartRate = snapshot.heartRate, volumeText = snapshot.volumeText,
            loggedSets = snapshot.loggedSets, totalSets = snapshot.totalSets, nextSetText = snapshot.nextSetText,
            nextExerciseName = snapshot.nextExerciseName, exerciseDoneSets = snapshot.exerciseDoneSets,
            exerciseSetCount = snapshot.exerciseSetCount, moment = snapshot.moment, superset = snapshot.superset, plates = snapshot.plates,
            coachTip = snapshot.coachTip, finish = snapshot.finish,
        )

    private fun rebuilt(history: ExerciseHistory): ExerciseHistory =
        ExerciseHistory(
            exerciseID = history.exerciseID,
            sessions = history.sessions.map {
                ExerciseSession(id = it.id, date = it.date, workoutName = it.workoutName, sets = it.sets, isPersonalRecord = it.isPersonalRecord)
            },
            e1RMSeries = history.e1RMSeries.map { E1RMPoint(date = it.date, value = it.value) },
            bestE1RM = history.bestE1RM,
            bestSetText = history.bestSetText,
            bestSetDate = history.bestSetDate,
            volumeLast30Days = history.volumeLast30Days,
            sessionsLast30Days = history.sessionsLast30Days,
            records = history.records.map { ExerciseRecordRow(id = it.id, label = it.label, value = it.value, date = it.date) },
        )

    // endregion

    // region States

    /** Workouts that exercise every optional: nothing logged, a rest running, paused, a personal record, an undo entry, empty. */
    private fun states(): List<WorkoutState> {
        val template = SampleData.templates()[0]
        val fresh = WorkoutFactory.makeWorkout(template, Fix.epoch, Fix.uuid(1))

        var resting = fresh
        resting = WorkoutReducer.reduce(resting, WorkoutAction.LogNextSet, Fix.at(30.0))
        resting = WorkoutReducer.reduce(resting, WorkoutAction.LogNextSet, Fix.at(100.0))
        resting = WorkoutReducer.reduce(resting, WorkoutAction.UpdateHeartRate(131), Fix.at(101.0))

        var pending = fresh
        for (second in listOf(40.0, 100.0, 200.0, 300.0, 400.0)) pending = WorkoutReducer.reduce(pending, WorkoutAction.LogNextSet, Fix.at(second))
        pending = WorkoutReducer.reduce(pending, WorkoutAction.ToggleLastSetRIR(2), Fix.at(401.0))
        pending = WorkoutReducer.reduce(pending, WorkoutAction.SkipRest, Fix.at(402.0))
        pending = WorkoutReducer.reduce(
            pending, WorkoutAction.SetWeight(pending.exercises[1].id, pending.exercises[1].sets[0].id, 100.0), Fix.at(403.0),
        )
        pending = WorkoutReducer.reduce(
            pending, WorkoutAction.SetRIR(pending.exercises[0].id, pending.exercises[0].sets[4].id, 9), Fix.at(404.0),
        )

        var paused = resting
        paused = WorkoutReducer.reduce(paused, WorkoutAction.Pause, Fix.at(120.0))
        paused = WorkoutReducer.reduce(paused, WorkoutAction.RemoveExercise(paused.exercises[5].id), Fix.at(121.0))

        var allLogged = fresh
        for (second in 0 until 30) allLogged = WorkoutReducer.reduce(allLogged, WorkoutAction.LogNextSet, Fix.at(second.toDouble() * 60))
        val empty = WorkoutFactory.makeEmpty("Free workout", Fix.epoch, Fix.uuid(2))
        return listOf(fresh, resting, pending, paused, allLogged, empty)
    }

    // endregion

    // region Tests

    @Test
    fun testEveryPresentationRebuildsFromItsPartsThroughThePublicInitializers() {
        var sawRows = false
        var sawDock = false
        var sawTip = false
        var sawRIR = false
        var sawEmpty = false
        var sawRecord = false
        for (state in states()) {
            for (offset in listOf(0.0, 150.0, 1_000.0)) {
                val presentation = WorkoutPresenter.present(state, Fix.at(offset), DemoRecovery.provider)
                assertWithMessage("${state.name} at +$offset s").that(rebuilt(presentation)).isEqualTo(presentation)
                sawRows = sawRows || !(presentation.card?.rows?.isEmpty() ?: true)
                sawDock = sawDock || presentation.dock != null
                sawTip = sawTip || presentation.card?.coachTip != null
                sawRIR = sawRIR || (presentation.card?.rows?.any { it.rirText != null } ?: false)
                sawRecord = sawRecord || (presentation.card?.rows?.any { it.estimated1RM != null } ?: false)
                sawEmpty = sawEmpty || presentation.isEmpty
            }
        }
        assertWithMessage("the states cover rows, dock, coach tip, RIR, records and the empty case")
            .that(sawRows && sawDock && sawTip && sawRIR && sawRecord && sawEmpty).isTrue()
    }

    @Test
    fun testOptionalsDefaultToNil() {
        val header = ActiveWorkoutPresentation.Header(
            title = "T", clockText = "0:00", isPaused = false, volumeText = "0", setsText = "0 of 0", heartRateText = "–",
            hasHeartRate = false, segments = emptyList(),
        )
        val totals = ActiveWorkoutPresentation.Totals(loggedSets = 0, totalSets = 0, volumeKg = 0.0, completedExercises = 0)
        val check = ActiveWorkoutPresentation.FinishCheck(
            loggedSets = 0, unloggedSets = 0, canFinish = false, title = "t", message = "m", templateDiff = TemplateDiff(),
            diffMessage = "d", asksToUpdateTemplate = false,
        )
        val bare = ActiveWorkoutPresentation(header = header, isEmpty = true, totals = totals, finishCheck = check)
        assertThat(bare.navigator).isNull()
        assertThat(bare.card).isNull()
        assertThat(bare.dock).isNull()
        assertThat(bare.undoText).isNull()

        val row = ActiveWorkoutPresentation.SetRow(
            id = Fix.uuid(1), number = "1", type = SetType.NORMAL, previousText = "–", weightText = "20", repsText = "5", weightEditable = true,
            isDone = false, isNext = true, isPersonalRecord = false, accessibilityLabel = "Set 1",
        )
        assertThat(row.estimated1RM).isNull()
        assertThat(row.rir).isNull()
        assertThat(row.rirText).isNull()

        val card = ActiveWorkoutPresentation.Card(
            exerciseID = Fix.uuid(2), exercise = ExerciseLibrary.exercise("bench")!!, recoveryPercent = 80,
            recoveryLevel = ActiveWorkoutPresentation.RecoveryLevel.GOOD, restSeconds = 90, restText = "1:30", note = "",
            weightColumnTitle = "kg", repsColumnTitle = "Reps", rows = listOf(row),
        )
        assertThat(card.supersetLabel).isNull()
        assertThat(card.coachTip).isNull()

        val dock = ActiveWorkoutPresentation.Dock(
            phase = ActiveWorkoutPresentation.DockPhase.RUNNING, remainingSeconds = 10, totalSeconds = 90, fraction = 0.1,
            remainingText = "0:10", nextSetText = "Next", showsRIR = false, isPaused = false,
        )
        assertThat(dock.rirSelection).isNull()
    }

    @Test
    fun testEverySnapshotRebuildsThroughThePublicInitializer() {
        val phases = mutableSetOf<SnapshotPhase>()
        for (state in states()) {
            for (offset in listOf(0.0, 150.0, 1_000.0)) {
                val snapshot = SnapshotBuilder.make(state, Fix.at(offset))
                assertWithMessage("${state.name} at +$offset s").that(rebuilt(snapshot)).isEqualTo(snapshot)
                phases.add(snapshot.phase)
            }
        }
        assertThat(phases).containsExactly(SnapshotPhase.LOGGING, SnapshotPhase.RESTING, SnapshotPhase.REST_OVER, SnapshotPhase.COMPLETE)
    }

    @Test
    fun testOptionalSnapshotFieldsDefaultToNil() {
        val snapshot = WorkoutSnapshot(
            workoutID = Fix.uuid(1), revision = 0, workoutName = "W", activeStart = Fix.epoch, isPaused = false,
            elapsedWhenPaused = 0, phase = SnapshotPhase.COMPLETE, exerciseName = "", exerciseIndex = 0, exerciseCount = 0, setLabel = "",
            tracking = TrackingKind.WEIGHT_REPS, weightText = "", repsText = "", repsUnit = "reps", showsWeight = true, restTotalSeconds = 0,
            volumeText = "0", loggedSets = 0, totalSets = 0, nextSetText = "",
        )
        assertThat(snapshot.targetExerciseID).isNull()
        assertThat(snapshot.targetSetID).isNull()
        assertThat(snapshot.restStartedAt).isNull()
        assertThat(snapshot.restEndsAt).isNull()
        assertThat(snapshot.restFrozenRemaining).isNull()
        assertThat(snapshot.heartRate).isNull()
        assertThat(snapshot.nextExerciseName).isNull()
    }

    @Test
    fun testExerciseHistoriesRebuildThroughThePublicInitializers() {
        val model = StrengthDataModel(persistence = null, seedDemoData = true, now = Fix.epoch)
        var sawSessions = false
        var sawBestSet = false
        for (id in listOf("bench", "squat", "plank", "custom-none")) {
            val history = model.history(id, Fix.epoch)
            assertWithMessage(id).that(rebuilt(history)).isEqualTo(history)
            sawSessions = sawSessions || history.sessions.isNotEmpty()
            sawBestSet = sawBestSet || history.bestSetText != null
        }
        assertThat(sawSessions && sawBestSet).isTrue()
    }

    @Test
    fun testHistoryPartsKeepEveryField() {
        val session = ExerciseSession(
            id = Fix.uuid(1), date = Fix.epoch, workoutName = "Upper A",
            sets = listOf(CompletedSet(type = SetType.NORMAL, weightKg = 80.0, reps = 5, rir = 1)), isPersonalRecord = true,
        )
        assertThat(session.id).isEqualTo(Fix.uuid(1))
        assertThat(session.date).isEqualTo(Fix.epoch)
        assertThat(session.workoutName).isEqualTo("Upper A")
        assertThat(session.sets.size).isEqualTo(1)
        assertThat(session.isPersonalRecord).isTrue()

        val dated = ExerciseRecordRow(id = "best", label = "Best set", value = "80 kg × 5", date = Fix.epoch)
        assertThat(listOf(dated.id, dated.label, dated.value)).isEqualTo(listOf("best", "Best set", "80 kg × 5"))
        assertThat(dated.date).isEqualTo(Fix.epoch)
        assertThat(ExerciseRecordRow(id = "x", label = "l", value = "v").date).isNull()

        val bare = ExerciseHistory(
            exerciseID = "bench", sessions = listOf(session), e1RMSeries = listOf(E1RMPoint(date = Fix.epoch, value = 93.0)), bestE1RM = 93.0,
            volumeLast30Days = 400.0, sessionsLast30Days = 1, records = listOf(dated),
        )
        assertThat(bare.bestSetText).isNull()
        assertThat(bare.bestSetDate).isNull()
        assertThat(bare.sessions).isEqualTo(listOf(session))
        assertThat(bare.records).isEqualTo(listOf(dated))
        assertThat(bare.volumeLast30Days).isEqualTo(400.0)
        assertThat(bare.sessionsLast30Days).isEqualTo(1)
    }

    // endregion
}
