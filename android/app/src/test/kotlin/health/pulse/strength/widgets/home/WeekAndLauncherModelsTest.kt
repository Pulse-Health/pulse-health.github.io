package health.pulse.strength.widgets.home

import com.google.common.truth.Truth.assertThat
import health.pulse.strength.core.widgets.DayCell
import health.pulse.strength.core.widgets.DeepLinks
import health.pulse.strength.core.widgets.TemplateSummary
import java.time.Instant
import org.junit.Test

/** Training week (HS-10) and template launcher (HS-11): what is listed, what is left out, and where each button leads. */
class WeekAndLauncherModelsTest {
    private val preview = HomeFixtures.preview
    private val empty = HomeFixtures.empty

    // region Training week

    @Test
    fun theStripMarksFinishedDaysTodayAndTheRest() {
        val card = TrainingWeekModel.card(preview)
        assertThat(card.progress).isEqualTo("3 of 4")
        assertThat(card.days.map { it.letter }).containsExactly("M", "T", "W", "T", "F", "S", "S").inOrder()
        assertThat(card.days.map { it.kind }).containsExactly(
            DayKind.DONE, DayKind.DONE, DayKind.DONE, DayKind.EMPTY, DayKind.EMPTY, DayKind.TODAY, DayKind.EMPTY,
        ).inOrder()
        assertThat(card.days.map { it.label }).containsExactly("UA", "LA", "UB", null, null, null, null).inOrder()
    }

    @Test
    fun aFinishedDayWithoutInitialsStillShowsAsDone() {
        val days = preview.week.days.toMutableList()
        days[3] = DayCell(date = days[3].date, letter = "T", sessions = 2, label = null)
        val card = TrainingWeekModel.card(preview.copy(week = preview.week.copy(days = days)))
        assertThat(card.days[3]).isEqualTo(WeekDay("T", "WO", DayKind.DONE))
    }

    @Test
    fun theLastSessionHasThreeStatsAndANamedDay() {
        val session = TrainingWeekModel.card(preview).session!!
        assertThat(session.name).isEqualTo("Upper B · Pull")
        assertThat(session.day).isEqualTo("Wed")
        assertThat(session.stats).containsExactly(
            SessionStat("51", "min", "Duration"),
            SessionStat("18", null, "Sets"),
            SessionStat("8.4", "t", "Volume"),
        ).inOrder()
        assertThat(session.description).isEqualTo("Last session: Upper B · Pull, Wed, 51 minutes, 18 sets, 8.4 t")
    }

    @Test
    fun aSessionFromToday() {
        val last = preview.lastSession!!.copy(finishedAt = Instant.parse("2026-10-17T08:30:00Z"), volumeKg = 850.0)
        val session = TrainingWeekModel.card(preview.copy(lastSession = last)).session!!
        assertThat(session.day).isEqualTo("Today")
        assertThat(session.stats.last()).isEqualTo(SessionStat("850", "kg", "Volume"))
    }

    @Test
    fun theLatestRecordIsOneLine() {
        assertThat(TrainingWeekModel.card(preview).record).isEqualTo(RecordRow("Bench Press PR", "85 × 5"))
        assertThat(TrainingWeekModel.card(empty).record).isNull()
    }

    @Test
    fun theButtonStartsTheNextWorkoutResumesTheRunningOneOrOpensTheApp() {
        assertThat(TrainingWeekModel.card(preview).action)
            .isEqualTo(WeekAction("Start Upper A · Push", DeepLinks.startNext, "Start Upper A · Push", primary = true))
        val running = TrainingWeekModel.card(preview.copy(active = HomeFixtures.runningWorkout())).action
        assertThat(running).isEqualTo(WeekAction("Resume Upper A · Push", DeepLinks.workout, "Resume Upper A · Push", primary = true))
        val none = TrainingWeekModel.card(empty)
        assertThat(none.action).isEqualTo(WeekAction("Open Pulse Strength", DeepLinks.hub, "Open Pulse Strength", primary = false))
        assertThat(none.message).isEqualTo("Open Pulse Strength to create a workout")
        assertThat(TrainingWeekModel.card(preview).message).isNull()
    }

    @Test
    fun theWholeCardReadsAsOneSentenceForAScreenReader() {
        assertThat(TrainingWeekModel.card(preview).description).isEqualTo(
            "Training week: 3 of 4 workouts. Last session: Upper B · Pull, Wed, 51 minutes, 18 sets, 8.4 t. " +
                "Latest record: Bench Press, 85 kilograms for 5 reps.",
        )
        assertThat(TrainingWeekModel.card(empty).description).isEqualTo("Training week: 0 of 4 workouts.")
    }

    @Test
    fun theSectionsAreDroppedFromTheBottomWhenTheWidgetIsShort() {
        assertThat(TrainingWeekModel.sections(400f, hasRecord = true)).isEqualTo(WeekSections(session = true, record = true))
        assertThat(TrainingWeekModel.sections(300f, hasRecord = true)).isEqualTo(WeekSections(session = true, record = false))
        // Too short for the session card but not for the one-line record.
        assertThat(TrainingWeekModel.sections(250f, hasRecord = true)).isEqualTo(WeekSections(session = false, record = true))
        assertThat(TrainingWeekModel.sections(180f, hasRecord = true)).isEqualTo(WeekSections(session = false, record = false))
        assertThat(TrainingWeekModel.sections(400f, hasRecord = false)).isEqualTo(WeekSections(session = true, record = false))
    }

    @Test
    fun theVolumeIsSplitIntoANumberAndItsUnit() {
        assertThat(TrainingWeekModel.volumeParts(8400.0)).isEqualTo("8.4" to "t")
        assertThat(TrainingWeekModel.volumeParts(850.0)).isEqualTo("850" to "kg")
    }

    // endregion

    // region Template launcher

    private fun template(id: String, name: String, suggested: Boolean = false, daysSince: Int? = 2, minutes: Int = 50, exercises: Int = 5) =
        TemplateSummary(id, name, exerciseCount = exercises, estimatedMinutes = minutes, daysSince = daysSince, isSuggested = suggested)

    @Test
    fun theSuggestedTemplateComesFirstAndTheOthersKeepTheirOrder() {
        val templates = listOf(template("a", "A"), template("b", "B", suggested = true), template("c", "C"))
        assertThat(LauncherModel.ordered(templates).map { it.templateID }).containsExactly("b", "a", "c").inOrder()
        assertThat(LauncherModel.ordered(preview.templates).map { it.name }.first()).isEqualTo("Upper A · Push")
    }

    @Test
    fun aRowNamesExercisesMinutesAndAgeAndLinksToItsTemplate() {
        val row = LauncherModel.row(preview.templates.first())
        assertThat(row.subtitle).isEqualTo("6 exercises · ~55 min · 5d ago")
        assertThat(row.link).isEqualTo(DeepLinks.start("00000000-0000-4000-8000-0000000000a1"))
        assertThat(row.description).isEqualTo("Start Upper A · Push, next in your rotation")
        assertThat(row.suggested).isTrue()
    }

    @Test
    fun missingDetailsAreLeftOutOfTheSubtitle() {
        assertThat(LauncherModel.row(template("a", "A", daysSince = null, minutes = 0, exercises = 1)).subtitle).isEqualTo("1 exercise")
        assertThat(LauncherModel.row(template("a", "A", daysSince = 0)).subtitle).isEqualTo("5 exercises · ~50 min · today")
    }

    @Test
    fun everyTemplateIsListedWhenTheyFit() {
        val plan = LauncherModel.plan(preview, 320f)
        assertThat(plan.rows.map { it.name }).containsExactly("Upper A · Push", "Lower A · Quads", "Upper B · Pull").inOrder()
        assertThat(plan.hidden).isEqualTo(0)
        assertThat(plan.showCaption).isTrue()
        assertThat(plan.message).isNull()
    }

    @Test
    fun theTemplatesThatDoNotFitAreCountedNotCutOffSilently() {
        val plan = LauncherModel.plan(preview, 250f)
        assertThat(plan.rows.map { it.name }).containsExactly("Upper A · Push")
        assertThat(plan.hidden).isEqualTo(2)
        assertThat(plan.showCaption).isFalse()
        // Never fewer than the suggested template, however short the widget.
        assertThat(LauncherModel.plan(preview, 100f).rows).hasSize(1)
    }

    @Test
    fun aTallWidgetListsAtMostSixTemplates() {
        val many = preview.copy(templates = (1..8).map { template("t$it", "Template $it", suggested = it == 1) })
        val plan = LauncherModel.plan(many, 700f)
        assertThat(plan.rows).hasSize(6)
        assertThat(plan.hidden).isEqualTo(2)
        val six = preview.copy(templates = (1..6).map { template("t$it", "Template $it") })
        val all = LauncherModel.plan(six, 700f)
        assertThat(all.hidden).isEqualTo(0)
        // No template is suggested: there is nothing to explain.
        assertThat(all.showCaption).isFalse()
    }

    @Test
    fun withoutTemplatesTheLauncherSaysWhatToDo() {
        val plan = LauncherModel.plan(empty, 320f)
        assertThat(plan.rows).isEmpty()
        assertThat(plan.message).isEqualTo("Open Pulse Strength to create a workout")
        assertThat(plan.showCaption).isFalse()
        assertThat(LauncherModel.description(plan)).isEqualTo("Start a workout. Open Pulse Strength to create a workout")
    }

    @Test
    fun theWholeLauncherReadsAsOneSentence() {
        assertThat(LauncherModel.description(LauncherModel.plan(preview, 320f))).isEqualTo(
            "Start a workout. Start Upper A · Push, next in your rotation. Start Lower A · Quads. Start Upper B · Pull",
        )
    }

    @Test
    fun theEmptyWorkoutUsesTheNameTheEngineWouldGiveIt() {
        assertThat(DeepLinks.startEmpty(LauncherModel.DefaultWorkoutName)).isEqualTo("pulse-strength://start-empty?name=Workout")
    }

    // endregion
}
