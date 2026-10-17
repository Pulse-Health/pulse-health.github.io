package health.pulse.strength.ui.hub

import androidx.compose.runtime.saveable.SaverScope
import com.google.common.truth.Truth.assertThat
import health.pulse.strength.core.ActiveWorkoutPresentation
import health.pulse.strength.core.CompletedSet
import health.pulse.strength.core.CompletedWorkout
import health.pulse.strength.core.Exercise
import health.pulse.strength.core.ExerciseLibrary
import health.pulse.strength.core.MuscleGroup
import health.pulse.strength.core.PlannedSet
import health.pulse.strength.core.SampleData
import health.pulse.strength.core.SetType
import health.pulse.strength.core.StrengthStore
import health.pulse.strength.core.TemplateEntry
import health.pulse.strength.core.TrackingKind
import health.pulse.strength.core.WorkoutTemplate
import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZoneOffset
import java.util.UUID
import org.junit.Test

/** The text, rotation, muscle and coach rules of the hub: plain Kotlin, no UI. */
class HubLogicTest {
    private val utc: ZoneId = ZoneOffset.UTC
    private val now: Instant = HubTestSupport.demoNow
    private val today: LocalDate = LocalDate.of(2026, 1, 17)

    private fun template(name: String, lastPerformed: Instant? = null, vararg exerciseIDs: String): WorkoutTemplate = WorkoutTemplate(
        name = name,
        entries = exerciseIDs.map { HubEditorDraft.makeEntry(ExerciseLibrary.exercise(it)!!) },
        lastPerformed = lastPerformed,
    )

    private fun workout(finishedAt: String, sets: Int, volume: Double) = CompletedWorkout(
        id = UUID.randomUUID(),
        name = "Workout",
        templateID = null,
        startedAt = Instant.parse(finishedAt).minusSeconds(3600),
        finishedAt = Instant.parse(finishedAt),
        durationSeconds = 3600,
        volumeKg = volume,
        loggedSets = sets,
        averageHeartRate = null,
        averageRIR = null,
        exercises = emptyList(),
        personalRecords = emptyList(),
        muscleSets = emptyList(),
    )

    // region HubFormat

    @Test
    fun countsAndSubtitles() {
        assertThat(HubFormat.exercises(0)).isEqualTo("0 exercises")
        assertThat(HubFormat.exercises(1)).isEqualTo("1 exercise")
        assertThat(HubFormat.exercises(6)).isEqualTo("6 exercises")
        assertThat(HubFormat.sets(1)).isEqualTo("1 set")
        assertThat(HubFormat.sets(5)).isEqualTo("5 sets")
        val upperA = SampleData.templates().first()
        assertThat(HubFormat.templateSubtitle(upperA, null)).isEqualTo("6 exercises · about 45 min")
        assertThat(HubFormat.templateSubtitle(upperA, "next up")).isEqualTo("6 exercises · about 45 min · next up")
    }

    @Test
    fun daysAgoCountsCalendarDays() {
        fun ago(date: String, zone: ZoneId = utc) = HubFormat.daysAgo(Instant.parse(date), today, zone)
        assertThat(ago("2026-01-17T00:00:00Z")).isEqualTo("today")
        assertThat(ago("2026-01-18T10:00:00Z")).isEqualTo("today") // a date in the future never reads "-1 days ago"
        assertThat(ago("2026-01-16T23:59:00Z")).isEqualTo("yesterday")
        assertThat(ago("2026-01-12T09:00:00Z")).isEqualTo("5 days ago")
        assertThat(ago("2026-01-04T09:00:00Z")).isEqualTo("13 days ago")
        assertThat(ago("2026-01-03T09:00:00Z")).isEqualTo("2 weeks ago")
        assertThat(ago("2025-11-19T09:00:00Z")).isEqualTo("8 weeks ago") // 59 days
        assertThat(ago("2025-11-18T09:00:00Z")).isEqualTo("2 months ago") // 60 days
        // The same instant is "yesterday" in UTC but "today" two hours east of it.
        assertThat(ago("2026-01-16T23:30:00Z", utc)).isEqualTo("yesterday")
        assertThat(ago("2026-01-16T23:30:00Z", ZoneOffset.ofHours(2))).isEqualTo("today")
    }

    @Test
    fun lastDoneSuffixOnlyForPerformedTemplates() {
        val never = template("A", null, "bench")
        val done = template("B", Instant.parse("2026-01-14T09:00:00Z"), "bench")
        assertThat(HubFormat.lastDoneSuffix(never, today, utc)).isNull()
        assertThat(HubFormat.lastDoneSuffix(done, today, utc)).isEqualTo("last done 3 days ago")
    }

    @Test
    fun dateTimeUsesEnglishMonthsAnd24HourClock() {
        assertThat(HubFormat.dateTime(Instant.parse("2026-10-08T18:10:00Z"), utc)).isEqualTo("Oct 8, 18:10")
        assertThat(HubFormat.dateTime(Instant.parse("2026-01-02T05:07:00Z"), utc)).isEqualTo("Jan 2, 05:07")
        assertThat(HubFormat.dateTime(Instant.parse("2026-12-31T23:59:00Z"), ZoneOffset.ofHours(1))).isEqualTo("Jan 1, 00:59")
    }

    @Test
    fun durationAndVolume() {
        assertThat(HubFormat.duration(3120)).isEqualTo("52m")
        assertThat(HubFormat.duration(3660)).isEqualTo("61m")
        assertThat(HubFormat.duration(89)).isEqualTo("1m")
        assertThat(HubFormat.duration(90)).isEqualTo("2m")
        assertThat(HubFormat.duration(-30)).isEqualTo("0m")
        assertThat(HubFormat.volume(8420.0)).isEqualTo("8,420 kg")
        assertThat(HubFormat.volume(1234567.4)).isEqualTo("1,234,567 kg")
        assertThat(HubFormat.volumeOrDash(8420.0)).isEqualTo("8,420 kg")
        assertThat(HubFormat.volumeOrDash(0.0)).isEqualTo("–")
    }

    @Test
    fun weekStatsCoverTheCalendarWeekOnly() {
        val history = listOf(
            workout("2026-01-17T09:00:00Z", sets = 10, volume = 1000.0), // Saturday
            workout("2026-01-12T09:00:00Z", sets = 12, volume = 2000.5), // Monday
            workout("2026-01-11T00:00:00Z", sets = 4, volume = 300.0), // Sunday 00:00 starts the week for en-US
            workout("2026-01-10T23:59:59Z", sets = 99, volume = 99999.0), // the Saturday before
        )
        val sunday = HubFormat.weekStats(history, today, utc, DayOfWeek.SUNDAY)
        assertThat(sunday).isEqualTo(HubWeekStats(sessions = 3, sets = 26, volumeKg = 3300.5))
        val monday = HubFormat.weekStats(history, today, utc, DayOfWeek.MONDAY) // week of Jan 12..18: Sunday the 11th is last week
        assertThat(monday).isEqualTo(HubWeekStats(sessions = 2, sets = 22, volumeKg = 3000.5))
        assertThat(HubFormat.weekStats(emptyList(), today, utc, DayOfWeek.MONDAY)).isEqualTo(HubWeekStats(0, 0, 0.0))
    }

    @Test
    fun planSummaryDescribesTheLastWorkingSet() {
        val bench = ExerciseLibrary.exercise("bench")!!
        val entry = TemplateEntry(
            exercise = bench,
            plannedSets = listOf(
                PlannedSet(SetType.WARMUP, 40.0, 10),
                PlannedSet(SetType.NORMAL, 82.5, 6),
                PlannedSet(SetType.NORMAL, 85.0, 6),
                PlannedSet(SetType.WARMUP, 20.0, 15),
            ),
            restSeconds = 150,
            supersetGroup = "A",
        )
        assertThat(HubFormat.planSummary(entry)).isEqualTo("4 sets · 85 kg × 6 · Rest 2:30 · Superset A")
        assertThat(HubFormat.planSummary(entry.copy(restSeconds = 0, supersetGroup = null))).isEqualTo("4 sets · 85 kg × 6")
        val onlyWarmups = entry.copy(plannedSets = listOf(PlannedSet(SetType.WARMUP, 40.0, 10)), restSeconds = 60, supersetGroup = null)
        assertThat(HubFormat.planSummary(onlyWarmups)).isEqualTo("1 set · 40 kg × 10 · Rest 1:00")
        val pushup = TemplateEntry(exercise = ExerciseLibrary.exercise("pushup")!!, plannedSets = List(3) { PlannedSet(SetType.NORMAL, 0.0, 12) }, restSeconds = 60)
        assertThat(HubFormat.planSummary(pushup)).isEqualTo("3 sets · 12 reps · Rest 1:00")
        val plank = ExerciseLibrary.builtIn.first { it.tracking == TrackingKind.DURATION }
        val plankEntry = TemplateEntry(exercise = plank, plannedSets = listOf(PlannedSet(SetType.NORMAL, 0.0, 45)), restSeconds = 0)
        assertThat(HubFormat.planSummary(plankEntry)).isEqualTo("1 set · 45 s")
        assertThat(HubFormat.planSummary(entry.copy(plannedSets = emptyList(), restSeconds = 0, supersetGroup = null))).isEqualTo("0 sets")
    }

    @Test
    fun setsTextMarksWarmupsAndKinds() {
        val sets = listOf(
            CompletedSet(SetType.WARMUP, 50.0, 8),
            CompletedSet(SetType.NORMAL, 82.5, 6),
            CompletedSet(SetType.DROP, 60.0, 10),
            CompletedSet(SetType.FAILURE, 82.5, 4),
        )
        assertThat(HubFormat.setsText(sets, TrackingKind.WEIGHT_REPS)).isEqualTo("W 50×8 · 82.5×6 · D 60×10 · F 82.5×4")
        assertThat(HubFormat.setsText(sets.take(2), TrackingKind.REPS_ONLY)).isEqualTo("W 8 reps · 6 reps")
        assertThat(HubFormat.setsText(sets.drop(1).take(1), TrackingKind.DURATION)).isEqualTo("6 s")
        assertThat(HubFormat.setsText(emptyList(), TrackingKind.WEIGHT_REPS)).isEmpty()
    }

    @Test
    fun smallTexts() {
        assertThat(HubFormat.busyMessage("Upper A · Push")).isEqualTo("Finish or discard Upper A · Push before starting another workout.")
        assertThat(HubFormat.busyMessage(null)).isEqualTo("Finish or discard your current workout before starting another workout.")
        assertThat(HubFormat.averageRIR(1.84)).isEqualTo("1.8")
        assertThat(HubFormat.averageRIR(2.0)).isEqualTo("2")
        assertThat(HubFormat.personalRecordTag(2)).isEqualTo("2 PR")
        assertThat(HubFormat.recordText(85.0, 5, 99.17)).isEqualTo("85 kg × 5 · est. 1RM 99 kg")
        assertThat(HubFormat.shortName(ExerciseLibrary.exercise("bench")!!)).isEqualTo("bench press")
        assertThat(HubFormat.shortName(ExerciseLibrary.exercise("pushup")!!)).isEqualTo("push-up")
    }

    // endregion

    // region Rotation

    @Test
    fun rotationFollowsTheMostRecentlyPerformedTemplate() {
        assertThat(HubRotation.next(emptyList())).isNull()
        val a = template("A", null, "bench")
        val b = template("B", null, "squat")
        val c = template("C", null, "deadlift")
        assertThat(HubRotation.next(listOf(a, b, c))).isEqualTo(a) // nothing performed yet: the first
        assertThat(HubRotation.next(listOf(a))).isEqualTo(a) // a single template recommends itself
        val bDone = b.copy(lastPerformed = Instant.parse("2026-01-10T10:00:00Z"))
        assertThat(HubRotation.next(listOf(a, bDone, c))).isEqualTo(c)
        val cNewest = c.copy(lastPerformed = Instant.parse("2026-01-12T10:00:00Z"))
        assertThat(HubRotation.next(listOf(a, bDone, cNewest))).isEqualTo(a) // wraps around
        assertThat(HubRotation.next(listOf(a.copy(lastPerformed = Instant.parse("2026-01-20T10:00:00Z")), bDone, cNewest))).isEqualTo(bDone)
    }

    // endregion

    // region Muscles

    @Test
    fun recoveryLevelsAndTitles() {
        assertThat(HubMuscles.level(100)).isEqualTo(ActiveWorkoutPresentation.RecoveryLevel.GOOD)
        assertThat(HubMuscles.level(80)).isEqualTo(ActiveWorkoutPresentation.RecoveryLevel.GOOD)
        assertThat(HubMuscles.level(79)).isEqualTo(ActiveWorkoutPresentation.RecoveryLevel.FAIR)
        assertThat(HubMuscles.level(60)).isEqualTo(ActiveWorkoutPresentation.RecoveryLevel.FAIR)
        assertThat(HubMuscles.level(59)).isEqualTo(ActiveWorkoutPresentation.RecoveryLevel.LOW)
        assertThat(HubMuscles.level(0)).isEqualTo(ActiveWorkoutPresentation.RecoveryLevel.LOW)
        assertThat(HubMuscles.levelTitle(85)).isEqualTo("Good")
        assertThat(HubMuscles.levelTitle(70)).isEqualTo("Fair")
        assertThat(HubMuscles.levelTitle(10)).isEqualTo("Low")
        assertThat(HubMuscles.readinessTitle(85)).isEqualTo("Ready")
        assertThat(HubMuscles.readinessTitle(70)).isEqualTo("Fair")
        assertThat(HubMuscles.readinessTitle(10)).isEqualTo("Low")
    }

    @Test
    fun percentsAreClampedAndReadinessIsTheMean() {
        assertThat(HubMuscles.percent(MuscleGroup.CHEST) { -5 }).isEqualTo(0)
        assertThat(HubMuscles.percent(MuscleGroup.CHEST) { 140 }).isEqualTo(100)
        // The demo recovery: 88, 100, 82, 79, 64, 100 -> 86.
        assertThat(HubMuscles.readiness(health.pulse.strength.core.DemoRecovery.provider)).isEqualTo(86)
        assertThat(HubMuscles.readiness { 0 }).isEqualTo(0)
        assertThat(HubMuscles.readiness { 100 }).isEqualTo(100)
        assertThat(HubMuscles.readiness { 250 }).isEqualTo(100)
    }

    @Test
    fun displayOrderHasEveryMuscleOnce() {
        assertThat(HubMuscles.displayOrder).containsExactlyElementsIn(MuscleGroup.entries)
        assertThat(HubMuscles.displayOrder.first()).isEqualTo(MuscleGroup.CHEST)
    }

    @Test
    fun musclesUsedAreSortedByCountThenFirstUse() {
        // shoulders (ohp), chest (bench, incline), shoulders (lateral), arms (pushdown)
        val mixed = template("Mixed", null, "ohp", "bench", "incline", "lateral", "pushdown")
        assertThat(HubMuscles.musclesUsed(mixed)).containsExactly(MuscleGroup.SHOULDERS, MuscleGroup.CHEST, MuscleGroup.ARMS).inOrder()
        assertThat(HubMuscles.musclesUsed(template("Empty"))).isEmpty()
        val chips = HubMuscles.chips(template("Four", null, "bench", "squat", "deadlift", "plank"), { 70 })
        assertThat(chips).hasSize(3)
        assertThat(chips.first()).isEqualTo(HubMuscleChip("Chest", "Chest 70%", 70))
    }

    @Test
    fun sentenceSubjectAndAgreement() {
        assertThat(HubMuscles.sentenceSubject(emptyList())).isEmpty()
        assertThat(HubMuscles.sentenceSubject(listOf(MuscleGroup.CHEST))).isEqualTo("Chest")
        assertThat(HubMuscles.sentenceSubject(listOf(MuscleGroup.CHEST, MuscleGroup.SHOULDERS))).isEqualTo("Chest and shoulders")
        assertThat(HubMuscles.isPlural(listOf(MuscleGroup.LEGS))).isTrue()
        assertThat(HubMuscles.isPlural(listOf(MuscleGroup.ARMS))).isTrue()
        assertThat(HubMuscles.isPlural(listOf(MuscleGroup.CHEST))).isFalse()
        assertThat(HubMuscles.isPlural(listOf(MuscleGroup.CHEST, MuscleGroup.BACK))).isTrue()
        assertThat(HubMuscles.isPlural(emptyList())).isFalse()
    }

    // endregion

    // region Coach

    private val demoStore = StrengthStore(null, seedDemoData = true, now = now)

    private fun coach(template: WorkoutTemplate, store: StrengthStore = demoStore, recovery: (MuscleGroup) -> Int = health.pulse.strength.core.DemoRecovery.provider): String? =
        HubCoach.message(
            template = template,
            recovery = recovery,
            exercise = { store.exercise(it) },
            hasResults = { it in loggedExerciseIDs(store.data.value) },
        )

    @Test
    fun coachNoteOfTheDemoTemplate() {
        val upperA = demoStore.templates.first()
        assertThat(coach(upperA)).isEqualTo("Chest and shoulders are recovered. Aim for 85 kg × 6 on your last bench press set.")
    }

    @Test
    fun coachNoteNamesTheTiredMuscles() {
        val upperA = demoStore.templates.first()
        val chestTired = { muscle: MuscleGroup -> if (muscle == MuscleGroup.CHEST) 40 else 90 }
        assertThat(coach(upperA, recovery = chestTired)).startsWith("Chest is still recovering. Aim for")
        assertThat(coach(upperA, recovery = { 10 })).startsWith("Chest and shoulders are still recovering. Aim for")
        val legs = demoStore.templates[1]
        assertThat(coach(legs, recovery = { if (it == MuscleGroup.LEGS) 30 else 100 })).startsWith("Legs are still recovering.")
        assertThat(coach(legs)).startsWith("Legs are recovered.")
    }

    @Test
    fun coachNoteHasNoTargetWithoutLoggedResults() {
        // A first-run store: the built-in library carries placeholder previous results that are not the user's.
        val emptyStore = StrengthStore(null, seedDemoData = false)
        val bench = ExerciseLibrary.exercise("bench")!!
        assertThat(bench.previousBestE1RM).isGreaterThan(0.0)
        val fresh = template("Fresh", null, "bench", "incline")
        assertThat(coach(fresh, emptyStore)).isEqualTo("Chest is recovered.")
        assertThat(coach(fresh, emptyStore, recovery = { 20 })).isEqualTo("Chest is still recovering.")
        assertThat(coach(template("Empty"), emptyStore)).isNull()
    }

    @Test
    fun coachTargetBeatsTheBestEstimatedOneRepMax() {
        val bench = demoStore.exercise("bench")!!
        // Best e1RM of the demo is 99 kg: 85 kg × 6 -> 102 kg is the first step above it for 6 reps.
        val weight = HubCoach.beatingWeight(bench, 6)
        assertThat(weight).isEqualTo(85.0)
        assertThat(health.pulse.strength.core.Estimated1RM.epley(weight, 6)).isGreaterThan(bench.previousBestE1RM)
        assertThat(health.pulse.strength.core.Estimated1RM.epley(weight - bench.weightStepKg, 6)).isAtMost(bench.previousBestE1RM + 0.05)
    }

    @Test
    fun coachSkipsBodyweightAndEmptyPlans() {
        val store = StrengthStore(null, seedDemoData = false)
        val pushUps = WorkoutTemplate(name = "Push-ups", entries = listOf(HubEditorDraft.makeEntry(ExerciseLibrary.exercise("pushup")!!)))
        assertThat(coach(pushUps, store)).isEqualTo("Chest is recovered.")
        val noReps = TemplateEntry(exercise = ExerciseLibrary.exercise("bench")!!, plannedSets = listOf(PlannedSet(SetType.NORMAL, 60.0, 0)), restSeconds = 60)
        assertThat(coach(WorkoutTemplate(name = "Zero", entries = listOf(noReps)), demoStore)).isEqualTo("Chest is recovered.")
    }

    @Test
    fun recoverySnapshotFreezesTheFiguresAndComparesByValue() {
        var chest = 40
        val provider: (MuscleGroup) -> Int = { if (it == MuscleGroup.CHEST) chest else if (it == MuscleGroup.CORE) 140 else 90 }
        val snapshot = HubRecoverySnapshot.of(provider)
        chest = 100
        assertThat(snapshot(MuscleGroup.CHEST)).isEqualTo(40) // the model moved on, the snapshot did not
        assertThat(snapshot(MuscleGroup.CORE)).isEqualTo(100) // clamped like HubMuscles.percent
        // Equal figures are equal snapshots (Compose then skips the sections), different figures are not.
        assertThat(HubRecoverySnapshot.of(provider)).isNotEqualTo(snapshot)
        chest = 40
        assertThat(HubRecoverySnapshot.of(provider)).isEqualTo(snapshot)
        assertThat(HubRecoverySnapshot.of(provider).hashCode()).isEqualTo(snapshot.hashCode())
        // The ring and the chips read the same numbers as the grid.
        assertThat(HubMuscles.readiness(snapshot)).isEqualTo(HubMuscles.readiness(provider))
    }

    // endregion

    // region Routes and navigation state

    @Test
    fun routesRoundTripThroughTheirTextForm() {
        val id = UUID.randomUUID()
        val routes = listOf(
            HubRoute.Library, HubRoute.Templates, HubRoute.Template(id), HubRoute.History, HubRoute.Workout(id), HubRoute.Recovery,
            HubRoute.Exercise("bench"), HubRoute.Exercise("custom-" + UUID.randomUUID()), HubRoute.Settings,
        )
        for (route in routes) assertThat(HubRoute.decode(route.encode())).isEqualTo(route)
        assertThat(routes.map { it.encode() }.toSet()).hasSize(routes.size)
    }

    @Test
    fun brokenRouteTextDecodesToNull() {
        assertThat(HubRoute.decode("")).isNull()
        assertThat(HubRoute.decode("nowhere")).isNull()
        assertThat(HubRoute.decode("template:not-a-uuid")).isNull()
        assertThat(HubRoute.decode("workout:")).isNull()
        assertThat(HubRoute.decode("exercise:")).isNull()
        assertThat(HubEntry.decode("x|library")).isNull()
        assertThat(HubEntry.decode("3|nowhere")).isNull()
        assertThat(HubEditorTarget.decode("template:oops")).isNull()
        assertThat(HubEditorTarget.decode("")).isNull()
    }

    @Test
    fun editorTargetsRoundTrip() {
        val id = UUID.randomUUID()
        assertThat(HubEditorTarget.decode(HubEditorTarget.New.encode())).isEqualTo(HubEditorTarget.New)
        assertThat(HubEditorTarget.decode(HubEditorTarget.Existing(id).encode())).isEqualTo(HubEditorTarget.Existing(id))
    }

    @Test
    fun navigatorPushesPopsAndIgnoresDoubleTaps() {
        val navigator = HubNavigator()
        assertThat(navigator.isAtRoot).isTrue()
        assertThat(navigator.pop()).isFalse()
        navigator.push(HubRoute.Templates)
        navigator.push(HubRoute.Templates) // a second tap on the same row while it opens
        assertThat(navigator.entries).hasSize(1)
        val id = UUID.randomUUID()
        navigator.push(HubRoute.Template(id))
        assertThat(navigator.entries.map { it.route }).containsExactly(HubRoute.Templates, HubRoute.Template(id)).inOrder()
        assertThat(navigator.entries.map { it.id }.toSet()).hasSize(2)
        assertThat(navigator.pop()).isTrue()
        navigator.push(HubRoute.Template(id)) // opened again: a new entry, so it never inherits the old scroll position
        assertThat(navigator.entries.map { it.id }.toSet()).hasSize(2)
        navigator.popToRoot()
        assertThat(navigator.isAtRoot).isTrue()
    }

    @Test
    fun navigatorSurvivesSaveAndRestore() {
        val navigator = HubNavigator()
        navigator.push(HubRoute.Library)
        navigator.push(HubRoute.Exercise("bench"))
        val saved = with(HubNavigator.Saver) { SaverScope { true }.save(navigator) }!!
        val restored = HubNavigator.Saver.restore(saved)!!
        assertThat(restored.entries).isEqualTo(navigator.entries)
        restored.push(HubRoute.Settings)
        assertThat(restored.entries.map { it.id }.toSet()).hasSize(3) // ids continue after the restored ones
    }

    @Test
    fun navigatorKeepsItsIdCounterAcrossSaveAndRestore() {
        val navigator = HubNavigator()
        navigator.push(HubRoute.Library) // id 1
        navigator.push(HubRoute.Exercise("bench")) // id 2
        navigator.pop()
        navigator.pop()
        assertThat(navigator.entries).isEmpty()
        val saved = with(HubNavigator.Saver) { SaverScope { true }.save(navigator) }!!
        val restored = HubNavigator.Saver.restore(saved)!!
        // The restored stack is empty, but the ids 1 and 2 belonged to screens that were popped: a page saved under one of them
        // must not come back for a screen opened now.
        restored.push(HubRoute.Library)
        assertThat(restored.entries.single().id).isEqualTo(3)
    }

    @Test
    fun navigatorRestoresItsCounterAndSkipsDamagedEntries() {
        val restored = HubNavigator.Saver.restore(listOf("7", "4|library", "5|templates", "6|nowhere"))!!
        assertThat(restored.entries.map { it.id }).containsExactly(4, 5).inOrder()
        restored.push(HubRoute.History)
        assertThat(restored.entries.last().id).isEqualTo(7)
        // An empty or damaged list still gives a working navigator.
        val broken = HubNavigator.Saver.restore(emptyList<String>())!!
        broken.push(HubRoute.Library)
        assertThat(broken.entries.single().id).isEqualTo(1)
    }

    @Test
    fun navigatorReportsEveryEntryThatLeavesTheStack() {
        val navigator = HubNavigator()
        val removed = mutableListOf<Int>()
        navigator.onRemoved = { removed.add(it.id) }
        navigator.push(HubRoute.Templates) // 1
        navigator.push(HubRoute.Library) // 2
        navigator.push(HubRoute.History) // 3
        navigator.pop()
        assertThat(removed).containsExactly(3)
        navigator.popToRoot()
        assertThat(removed).containsExactly(3, 2, 1).inOrder()
        assertThat(navigator.pop()).isFalse() // nothing to remove at the home screen
        navigator.popToRoot()
        assertThat(removed).hasSize(3)
    }

    @Test
    fun popIfOnlyPopsTheScreenOnTop() {
        val navigator = HubNavigator()
        navigator.push(HubRoute.Library) // 1
        navigator.push(HubRoute.Exercise("bench")) // 2
        val removed = mutableListOf<Int>()
        navigator.onRemoved = { removed.add(it.id) }
        assertThat(navigator.popIf(1)).isFalse() // the page below, reached by a second tap
        assertThat(navigator.popIf(9)).isFalse()
        assertThat(navigator.entries.map { it.id }).containsExactly(1, 2).inOrder()
        assertThat(navigator.popIf(2)).isTrue()
        assertThat(navigator.popIf(2)).isFalse() // the same arrow again: its page is gone
        assertThat(navigator.entries.map { it.id }).containsExactly(1)
        assertThat(removed).containsExactly(2)
        assertThat(navigator.popIf(0)).isFalse() // the home screen is id 0 and never on the stack
    }

    // endregion

    // region Editor draft

    @Test
    fun draftEntriesUseTheExerciseDefaults() {
        val bench = ExerciseLibrary.exercise("bench")!!
        val entry = HubEditorDraft.makeEntry(bench)
        assertThat(entry.plannedSets).hasSize(bench.defaults.sets)
        assertThat(entry.plannedSets.all { it.type == SetType.NORMAL && it.weightKg == bench.defaults.weightKg && it.reps == bench.defaults.reps }).isTrue()
        assertThat(entry.restSeconds).isEqualTo(bench.defaults.restSeconds)
        // A library exercise with zero default sets still gets one planned set.
        val zero: Exercise = bench.copy(defaults = bench.defaults.copy(sets = 0))
        assertThat(HubEditorDraft.makeEntry(zero).plannedSets).hasSize(1)
    }

    @Test
    fun draftMovesAndRemovesEntries() {
        val draft = HubEditorDraft("X", emptyList())
        draft.add(listOf("bench", "squat", "deadlift").map { ExerciseLibrary.exercise(it)!! })
        fun ids() = draft.entries.map { it.exercise.id }
        assertThat(ids()).containsExactly("bench", "squat", "deadlift").inOrder()
        draft.move(0, -1) // already first: nothing happens
        draft.move(2, 1) // already last
        draft.move(5, 1) // not an index
        assertThat(ids()).containsExactly("bench", "squat", "deadlift").inOrder()
        draft.move(2, -1)
        assertThat(ids()).containsExactly("bench", "deadlift", "squat").inOrder()
        draft.move(0, 1)
        assertThat(ids()).containsExactly("deadlift", "bench", "squat").inOrder()
        draft.remove(1)
        draft.remove(9)
        assertThat(ids()).containsExactly("deadlift", "squat").inOrder()
    }

    @Test
    fun draftOnlySavesWithANameAndAnExercise() {
        val draft = HubEditorDraft("   ", emptyList())
        assertThat(draft.canSave).isFalse()
        assertThat(draft.toTemplate(null)).isNull()
        draft.name = "Push"
        assertThat(draft.canSave).isFalse() // no exercise yet
        draft.add(listOf(ExerciseLibrary.exercise("bench")!!))
        assertThat(draft.canSave).isTrue()
        draft.name = "  \n "
        assertThat(draft.canSave).isFalse()
        draft.name = "  Push day \n"
        val created = draft.toTemplate(null)!!
        assertThat(created.name).isEqualTo("Push day")
        assertThat(created.lastPerformed).isNull()
        val existing = WorkoutTemplate(name = "Old", entries = emptyList(), lastPerformed = Instant.parse("2026-01-10T10:00:00Z"))
        val edited = draft.toTemplate(existing)!!
        assertThat(edited.id).isEqualTo(existing.id)
        assertThat(edited.lastPerformed).isEqualTo(existing.lastPerformed)
        assertThat(edited.name).isEqualTo("Push day")
    }

    @Test
    fun draftKnowsWhetherItDiffersFromWhatTheEditorOpenedWith() {
        assertThat(HubEditorDraft("", emptyList()).differsFrom(null)).isFalse() // a new template, untouched
        val draft = HubEditorDraft("", emptyList())
        draft.name = "P"
        assertThat(draft.differsFrom(null)).isTrue()
        draft.name = ""
        assertThat(draft.differsFrom(null)).isFalse() // typed and deleted again
        draft.add(listOf(ExerciseLibrary.exercise("bench")!!))
        assertThat(draft.differsFrom(null)).isTrue()
        draft.remove(0)
        assertThat(draft.differsFrom(null)).isFalse()

        val existing = template("Push", null, "bench", "squat")
        val editing = HubEditorDraft(existing.name, existing.entries)
        assertThat(editing.differsFrom(existing)).isFalse()
        editing.move(1, -1)
        assertThat(editing.differsFrom(existing)).isTrue()
        editing.move(0, 1)
        assertThat(editing.differsFrom(existing)).isFalse() // moved back
        editing.remove(1)
        assertThat(editing.differsFrom(existing)).isTrue()
        editing.entries = existing.entries
        editing.name = "Push "
        assertThat(editing.differsFrom(existing)).isTrue()
        // A draft that went through the saver (a rotation) still equals the template it was opened from.
        val saved = with(HubEditorDraft.Saver) { SaverScope { true }.save(HubEditorDraft(existing.name, existing.entries)) }!!
        assertThat(HubEditorDraft.Saver.restore(saved)!!.differsFrom(existing)).isFalse()
    }

    @Test
    fun draftSurvivesSaveAndRestore() {
        val draft = HubEditorDraft("Push", emptyList())
        draft.add(listOf("bench", "pushup").map { ExerciseLibrary.exercise(it)!! })
        val saved = with(HubEditorDraft.Saver) { SaverScope { true }.save(draft) }!!
        val restored = HubEditorDraft.Saver.restore(saved)!!
        assertThat(restored.name).isEqualTo("Push")
        assertThat(restored.entries).isEqualTo(draft.entries)
    }

    // endregion

    @Test
    fun loggedExerciseIdsComeFromBestsAndHistory() {
        assertThat(loggedExerciseIDs(StrengthStore(null, seedDemoData = false).data.value)).isEmpty()
        val ids = loggedExerciseIDs(demoStore.data.value)
        assertThat(ids).contains("bench")
        assertThat(ids).doesNotContain("deadlift")
    }
}
