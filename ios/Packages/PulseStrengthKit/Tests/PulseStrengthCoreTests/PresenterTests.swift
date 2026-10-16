import XCTest
@testable import PulseStrengthCore

// MARK: - Fixtures shared by the presenter, summary and snapshot tests

/// Deterministic fixtures (no clock, no randomness) for the presenter, summary and snapshot tests.
enum PresFix {
    /// The fake "start of the workout".
    static let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    /// `t0` plus `seconds`.
    static func at(_ seconds: Double) -> Date { t0.addingTimeInterval(seconds) }

    /// A stable UUID built from two numbers.
    static func uuid(_ high: Int, _ low: Int) -> UUID {
        func hex(_ value: Int, _ width: Int) -> String {
            let digits = String(value, radix: 16)
            return String(repeating: "0", count: max(0, width - digits.count)) + digits
        }
        return UUID(uuidString: "00000000-0000-0000-\(hex(high, 4))-\(hex(low, 12))")!
    }

    /// A built-in exercise of the library with the demo previous results (bench: best 99, last sets 50 × 8 ... 80 × 5).
    static func lib(_ id: String) -> Exercise {
        guard let exercise = ExerciseLibrary.exercise(id: id) else { preconditionFailure("unknown exercise \(id)") }
        return DemoPreviousResults.applying(to: exercise)
    }

    /// `exercise` with another previous best estimated 1RM.
    static func lib(_ id: String, best: Double) -> Exercise {
        var exercise = lib(id)
        exercise.previousBestE1RM = best
        return exercise
    }

    /// Demo recovery percentages (88 % chest).
    static let demoRecovery: RecoveryProvider = DemoRecovery.provider

    // MARK: Workouts

    typealias SetSpec = (SetType, Double, Int)

    static func normal(_ count: Int, _ kg: Double, _ reps: Int) -> [SetSpec] {
        Array(repeating: (SetType.normal, kg, reps), count: count)
    }

    /// Entry number `n` (1-based) with deterministic ids: entry `uuid(0x100 + n, 0)`, sets `uuid(0x100 + n, i + 1)`.
    static func entry(
        _ n: Int, _ exercise: Exercise, _ sets: [SetSpec], rest: Int? = nil,
        group: String? = nil, templateEntry: UUID? = nil
    ) -> WorkoutExercise {
        WorkoutExercise(
            id: uuid(0x100 + n, 0),
            exercise: exercise,
            sets: sets.enumerated().map { offset, spec in
                LoggedSet(id: uuid(0x100 + n, offset + 1), type: spec.0, weightKg: spec.1, reps: spec.2)
            },
            restSeconds: rest ?? exercise.defaults.restSeconds,
            supersetGroup: group,
            note: "",
            templateEntryID: templateEntry
        )
    }

    /// A workout of `entries` starting at `t0`.
    static func workout(_ entries: [WorkoutExercise], index: Int = 0, name: String = "Test") -> WorkoutState {
        WorkoutState(id: uuid(1, 2), name: name, exercises: entries, currentIndex: index, startedAt: t0)
    }

    /// A single-exercise workout with the given sets.
    static func single(_ exercise: Exercise, _ sets: [SetSpec], rest: Int? = nil) -> WorkoutState {
        workout([entry(1, exercise, sets, rest: rest)])
    }

    /// Marks the sets at `indexes` of exercise `k` as logged without touching the rest of the state.
    static func marking(_ state: WorkoutState, exercise k: Int, done indexes: [Int]) -> WorkoutState {
        var copy = state
        for i in indexes { copy.exercises[k].sets[i].isDone = true }
        return copy
    }

    // MARK: Upper A - Push (the design's workout)

    static func templateEntry(
        _ n: Int, _ exercise: Exercise, _ planned: [PlannedSet], rest: Int, group: String? = nil
    ) -> TemplateEntry {
        TemplateEntry(id: uuid(0x200 + n, 0), exercise: exercise, plannedSets: planned, restSeconds: rest, supersetGroup: group)
    }

    static func planned(_ count: Int, _ kg: Double, _ reps: Int) -> [PlannedSet] {
        Array(repeating: PlannedSet(type: .normal, weightKg: kg, reps: reps), count: count)
    }

    /// "Upper A · Push": bench with two warm-ups, incline, overhead press, lateral raise + pushdown (superset A), crossover.
    static func upperA() -> WorkoutTemplate {
        WorkoutTemplate(
            id: uuid(0x2FF, 1),
            name: "Upper A · Push",
            entries: [
                templateEntry(1, lib("bench"), [
                    PlannedSet(type: .warmup, weightKg: 50, reps: 8), PlannedSet(type: .warmup, weightKg: 70, reps: 5),
                    PlannedSet(weightKg: 82.5, reps: 6), PlannedSet(weightKg: 82.5, reps: 6), PlannedSet(weightKg: 85, reps: 6),
                ], rest: 150),
                templateEntry(2, lib("incline"), planned(3, 28, 10), rest: 90),
                templateEntry(3, lib("ohp"), planned(3, 45, 8), rest: 120),
                templateEntry(4, lib("lateral"), planned(3, 8, 15), rest: 60, group: "A"),
                templateEntry(5, lib("pushdown"), planned(3, 30, 12), rest: 60, group: "A"),
                templateEntry(6, lib("crossover"), planned(3, 15, 12), rest: 60),
            ]
        )
    }

    /// The design's workout just started at `t0`, nothing logged.
    static func freshUpperA() -> WorkoutState {
        WorkoutFactory.makeWorkout(from: upperA(), now: t0, id: uuid(1, 1))
    }

    /// The design's opening state: warm-ups 50x8 and 70x5 and the first 82.5x6 logged (RIR 3), rest running.
    /// The last set was logged at `t0 + 1403` (150 s rest, ends at `t0 + 1553`); the design clock reads 24:18 at `t0 + 1458`.
    static func goldenState() -> WorkoutState {
        var state = freshUpperA()
        WorkoutReducer.reduce(&state, .logNextSet, now: at(1200))
        WorkoutReducer.reduce(&state, .logNextSet, now: at(1300))
        WorkoutReducer.reduce(&state, .logNextSet, now: at(1403))
        WorkoutReducer.reduce(&state, .toggleLastSetRIR(3), now: at(1404))
        return state
    }

    /// The `now` at which the golden state shows the design's 24:18 clock and 1:35 of rest left.
    static var goldenNow: Date { at(1458) }

    // MARK: Reducer shortcuts

    static func reduced(_ state: WorkoutState, _ action: WorkoutAction, at seconds: Double = 0) -> WorkoutState {
        var copy = state
        WorkoutReducer.reduce(&copy, action, now: at(seconds))
        return copy
    }

    static func log(_ state: WorkoutState, _ k: Int, _ i: Int) -> WorkoutAction {
        .logSet(exerciseID: state.exercises[k].id, setID: state.exercises[k].sets[i].id)
    }

    /// Logs every pending set of the workout, one second apart, starting at `t0 + start`.
    static func loggedEverything(_ state: WorkoutState, start: Double = 0) -> WorkoutState {
        var copy = state
        var seconds = start
        while WorkoutTargets.nextPending(in: copy) != nil {
            WorkoutReducer.reduce(&copy, .logNextSet, now: at(seconds))
            seconds += 1
        }
        return copy
    }

    static func present(_ state: WorkoutState, at seconds: Double = 0) -> ActiveWorkoutPresentation {
        WorkoutPresenter.present(state, now: at(seconds), recovery: demoRecovery)
    }
}

// MARK: - Presenter: the design's opening state

final class PresenterGoldenTests: XCTestCase {
    private var state = PresFix.goldenState()
    private var view: ActiveWorkoutPresentation { WorkoutPresenter.present(state, now: PresFix.goldenNow, recovery: PresFix.demoRecovery) }

    override func setUp() {
        super.setUp()
        state = PresFix.goldenState()
    }

    func testFixtureMatchesTheDesignState() {
        XCTAssertEqual(state.exercises.count, 6)
        XCTAssertEqual(state.exercises[0].sets.map { $0.isDone }, [true, true, true, false, false])
        XCTAssertEqual(state.exercises[0].sets[2].rir, 3)
        XCTAssertEqual(state.rest?.totalSeconds, 150)
        XCTAssertEqual(state.rest?.endsAt, PresFix.at(1553))
        XCTAssertEqual(state.exercises[0].exercise.previousBestE1RM, 99)
    }

    func testHeaderTotals() {
        let header = view.header
        XCTAssertEqual(header.title, "Upper A · Push")
        XCTAssertEqual(header.clockText, "24:18")
        XCTAssertFalse(header.isPaused)
        XCTAssertEqual(header.volumeText, "495")
        XCTAssertEqual(header.setsText, "3 of 20")
        XCTAssertEqual(header.heartRateText, "–")
        XCTAssertFalse(header.hasHeartRate)
        XCTAssertEqual(view.totals.loggedSets, 3)
        XCTAssertEqual(view.totals.totalSets, 20)
        XCTAssertEqual(view.totals.volumeKg, 495, accuracy: 0.0001)
        XCTAssertEqual(view.totals.completedExercises, 0)
        XCTAssertFalse(view.isEmpty)
    }

    func testSegmentsFollowTheLoggedShareOfEachExercise() {
        let segments = view.header.segments
        XCTAssertEqual(segments.count, 6)
        XCTAssertEqual(segments[0].fraction, 0.6, accuracy: 0.0001)
        XCTAssertTrue(segments.dropFirst().allSatisfy { $0.fraction == 0 })
        XCTAssertEqual(segments.map { $0.isCurrent }, [true, false, false, false, false, false])
    }

    func testTheCardCarriesWhetherTheRecoveryIsMeasured() throws {
        let state = PresFix.freshUpperA()
        XCTAssertTrue(try XCTUnwrap(WorkoutPresenter.present(state, now: PresFix.t0, recovery: DemoRecovery.provider).card).recoveryHasData)
        let card = try XCTUnwrap(WorkoutPresenter.present(state, now: PresFix.t0, recovery: { _ in 100 }, recoveryHasData: false).card)
        XCTAssertFalse(card.recoveryHasData)
        XCTAssertEqual(card.recoveryPercent, 100)
    }

    func testNavigator() {
        let nav = try! XCTUnwrap(view.navigator)
        XCTAssertEqual(nav.position, 1)
        XCTAssertEqual(nav.total, 6)
        XCTAssertFalse(nav.canGoPrevious)
        XCTAssertTrue(nav.canGoNext)
    }

    func testCardOfTheCurrentExercise() throws {
        let card = try XCTUnwrap(view.card)
        XCTAssertEqual(card.exerciseID, state.exercises[0].id)
        XCTAssertEqual(card.exercise.id, "bench")
        XCTAssertEqual(card.recoveryPercent, 88)
        XCTAssertEqual(card.recoveryLevel, .good)
        XCTAssertNil(card.supersetLabel)
        XCTAssertEqual(card.restSeconds, 150)
        XCTAssertEqual(card.restText, "2:30")
        XCTAssertEqual(card.weightColumnTitle, "kg")
        XCTAssertEqual(card.repsColumnTitle, "Reps")
        XCTAssertEqual(card.note, "")
        XCTAssertEqual(card.rows.count, 5)
    }

    func testRows() throws {
        let rows = try XCTUnwrap(view.card).rows
        XCTAssertEqual(rows.map { $0.id }, state.exercises[0].sets.map { $0.id })
        XCTAssertEqual(rows.map { $0.number }, ["W", "W", "1", "2", "3"])
        XCTAssertEqual(rows.map { $0.previousText }, ["50 × 8", "70 × 5", "80 × 6", "80 × 6", "80 × 5"])
        XCTAssertEqual(rows.map { $0.weightText }, ["50", "70", "82.5", "82.5", "85"])
        XCTAssertEqual(rows.map { $0.repsText }, ["8", "5", "6", "6", "6"])
        XCTAssertEqual(rows.map { $0.isDone }, [true, true, true, false, false])
        XCTAssertEqual(rows.map { $0.isNext }, [false, false, false, true, false])
        XCTAssertTrue(rows.allSatisfy { $0.weightEditable })
        XCTAssertEqual(rows.map { $0.type }, [.warmup, .warmup, .normal, .normal, .normal])
        XCTAssertEqual(rows.map { $0.rirText }, [nil, nil, "RIR 3", nil, nil])
        XCTAssertEqual(rows.map { $0.rir }, [nil, nil, 3, nil, nil])
        // 82.5 x 6 is exactly the previous best (99.0): not a record.
        XCTAssertEqual(rows.map { $0.isPersonalRecord }, [false, false, false, false, false])
        XCTAssertEqual(rows.map { $0.estimated1RM }, [nil, nil, nil, nil, nil])
    }

    func testAccessibilityLabels() throws {
        let rows = try XCTUnwrap(view.card).rows
        XCTAssertEqual(rows[0].accessibilityLabel, "Set 1, warm-up, 50 kilograms, 8 reps, logged")
        XCTAssertEqual(rows[2].accessibilityLabel, "Set 3, working set, 82.5 kilograms, 6 reps, logged")
        XCTAssertEqual(rows[3].accessibilityLabel, "Set 4, working set, 82.5 kilograms, 6 reps, not logged")
    }

    func testRestDockWhileTheRestRuns() throws {
        let dock = try XCTUnwrap(view.dock)
        XCTAssertEqual(dock.phase, .running)
        XCTAssertEqual(dock.remainingSeconds, 95)
        XCTAssertEqual(dock.totalSeconds, 150)
        XCTAssertEqual(dock.fraction, 95.0 / 150.0, accuracy: 0.0001)
        XCTAssertEqual(dock.remainingText, "1:35")
        XCTAssertEqual(dock.nextSetText, "Next · Set 2 · 82.5 kg × 6")
        XCTAssertTrue(dock.showsRIR)
        XCTAssertEqual(dock.rirSelection, 3)
        XCTAssertFalse(dock.isPaused)
    }

    func testNoCoachTipWhileTheRestRuns() throws {
        XCTAssertNil(try XCTUnwrap(view.card).coachTip)
    }

    func testCoachTipAppearsOnceTheRestIsCleared() throws {
        state = PresFix.reduced(state, .skipRest, at: 1459)
        XCTAssertNil(view.dock)
        let tip = try XCTUnwrap(view.card).coachTip
        XCTAssertEqual(tip, "85 kg × 6 on your last set would beat your best estimated 1RM of 99 kg.")
    }

    func testFinishCheckOfTheOpeningState() {
        let check = view.finishCheck
        XCTAssertEqual(check.loggedSets, 3)
        XCTAssertEqual(check.unloggedSets, 17)
        XCTAssertTrue(check.canFinish)
        XCTAssertEqual(check.title, "Finish workout?")
        XCTAssertEqual(check.message, "17 sets are not logged yet and will be left out.")
        XCTAssertTrue(check.templateDiff.isEmpty)
        XCTAssertEqual(check.diffMessage, "Changes: none.")
        XCTAssertFalse(check.asksToUpdateTemplate)
    }

    func testNoUndoTextInitially() {
        XCTAssertNil(view.undoText)
    }
}

// MARK: - Presenter: header, empty workout, paused clock

final class PresenterHeaderTests: XCTestCase {
    func testEmptyWorkout() {
        let state = WorkoutFactory.makeEmpty(name: "Workout", now: PresFix.t0)
        let view = PresFix.present(state, at: 65)
        XCTAssertTrue(view.isEmpty)
        XCTAssertNil(view.navigator)
        XCTAssertNil(view.card)
        XCTAssertNil(view.dock)
        XCTAssertNil(view.undoText)
        XCTAssertEqual(view.header.title, "Workout")
        XCTAssertEqual(view.header.clockText, "1:05")
        XCTAssertEqual(view.header.setsText, "0 of 0")
        XCTAssertEqual(view.header.volumeText, "0")
        XCTAssertTrue(view.header.segments.isEmpty)
        XCTAssertEqual(view.totals, ActiveWorkoutPresentation.Totals(loggedSets: 0, totalSets: 0, volumeKg: 0, completedExercises: 0))
        XCTAssertEqual(view.finishCheck.title, "Nothing logged yet")
        XCTAssertEqual(view.finishCheck.message, "Log at least one set to save this workout.")
        XCTAssertFalse(view.finishCheck.canFinish)
        XCTAssertEqual(view.finishCheck.unloggedSets, 0)
    }

    func testEmptyWorkoutHasNoDockEvenWithAStrayRest() {
        var state = WorkoutFactory.makeEmpty(name: "Workout", now: PresFix.t0)
        state.rest = RestState(endsAt: PresFix.at(100), totalSeconds: 60)
        XCTAssertNil(PresFix.present(state, at: 10).dock)
    }

    func testClockFormats() {
        let state = PresFix.freshUpperA()
        XCTAssertEqual(PresFix.present(state, at: 0).header.clockText, "0:00")
        XCTAssertEqual(PresFix.present(state, at: 59.9).header.clockText, "0:59")
        XCTAssertEqual(PresFix.present(state, at: 1458).header.clockText, "24:18")
        XCTAssertEqual(PresFix.present(state, at: 3723).header.clockText, "1:02:03")
        XCTAssertEqual(PresFix.present(state, at: -30).header.clockText, "0:00")
    }

    func testPausedClockText() {
        var state = PresFix.freshUpperA()
        WorkoutReducer.reduce(&state, .pause, now: PresFix.at(600))
        let view = PresFix.present(state, at: 900)
        XCTAssertEqual(view.header.clockText, "Paused · 10:00")
        XCTAssertTrue(view.header.isPaused)
        // The clock stays frozen while time passes.
        XCTAssertEqual(PresFix.present(state, at: 5000).header.clockText, "Paused · 10:00")
    }

    func testClockExcludesPausedTimeAfterResume() {
        var state = PresFix.freshUpperA()
        WorkoutReducer.reduce(&state, .pause, now: PresFix.at(600))
        WorkoutReducer.reduce(&state, .resume, now: PresFix.at(1000))
        let view = PresFix.present(state, at: 1100)
        XCTAssertEqual(view.header.clockText, "11:40")
        XCTAssertFalse(view.header.isPaused)
    }

    func testHeartRateText() {
        var state = PresFix.freshUpperA()
        XCTAssertEqual(PresFix.present(state).header.heartRateText, "–")
        WorkoutReducer.reduce(&state, .updateHeartRate(128), now: PresFix.at(1))
        let view = PresFix.present(state, at: 2)
        XCTAssertEqual(view.header.heartRateText, "128")
        XCTAssertTrue(view.header.hasHeartRate)
        WorkoutReducer.reduce(&state, .updateHeartRate(nil), now: PresFix.at(3))
        XCTAssertEqual(PresFix.present(state).header.heartRateText, "–")
        XCTAssertFalse(PresFix.present(state).header.hasHeartRate)
        WorkoutReducer.reduce(&state, .updateHeartRate(0), now: PresFix.at(4))
        XCTAssertEqual(PresFix.present(state).header.heartRateText, "–")
    }

    func testVolumeUsesThousandsSeparators() {
        let state = PresFix.marking(PresFix.single(PresFix.lib("squat"), PresFix.normal(3, 100, 6)), exercise: 0, done: [0, 1, 2])
        XCTAssertEqual(PresFix.present(state).header.volumeText, "1,800")
        let heavy = PresFix.marking(PresFix.single(PresFix.lib("squat"), PresFix.normal(2, 1250, 10)), exercise: 0, done: [0, 1])
        XCTAssertEqual(PresFix.present(heavy).header.volumeText, "25,000")
    }

    func testVolumeExcludesWarmUpsUnloggedAndNonWeightExercises() {
        let bench = PresFix.entry(1, PresFix.lib("bench"), [(.warmup, 50, 8), (.normal, 80, 5), (.drop, 60, 10), (.failure, 70, 4), (.normal, 80, 5)])
        let pushup = PresFix.entry(2, PresFix.lib("pushup"), PresFix.normal(2, 10, 12))
        let plank = PresFix.entry(3, PresFix.lib("plank"), PresFix.normal(1, 0, 45))
        var state = PresFix.workout([bench, pushup, plank])
        state = PresFix.marking(state, exercise: 0, done: [0, 1, 2, 3])
        state = PresFix.marking(state, exercise: 1, done: [0, 1])
        state = PresFix.marking(state, exercise: 2, done: [0])
        // 80x5 + 60x10 + 70x4 = 400 + 600 + 280; the warm-up, the pending set and the bodyweight work do not count.
        XCTAssertEqual(PresFix.present(state).totals.volumeKg, 1280, accuracy: 0.0001)
        XCTAssertEqual(PresFix.present(state).header.volumeText, "1,280")
        XCTAssertEqual(PresFix.present(state).totals.loggedSets, 7)
    }

    func testCompletedExercisesNeedASetAndAllDone() {
        let a = PresFix.entry(1, PresFix.lib("bench"), PresFix.normal(2, 80, 5))
        let b = PresFix.entry(2, PresFix.lib("incline"), PresFix.normal(2, 28, 10))
        var empty = PresFix.entry(3, PresFix.lib("ohp"), [])
        empty.sets = []
        var state = PresFix.workout([a, b, empty])
        state = PresFix.marking(state, exercise: 0, done: [0, 1])
        state = PresFix.marking(state, exercise: 1, done: [0])
        let view = PresFix.present(state)
        XCTAssertEqual(view.totals.completedExercises, 1)
        XCTAssertEqual(view.header.segments.map { $0.fraction }, [1, 0.5, 0])
    }

    func testNavigatorAtTheEnds() throws {
        var state = PresFix.freshUpperA()
        state = PresFix.reduced(state, .goTo(index: 5))
        let last = try XCTUnwrap(PresFix.present(state).navigator)
        XCTAssertEqual(last.position, 6)
        XCTAssertTrue(last.canGoPrevious)
        XCTAssertFalse(last.canGoNext)
        state = PresFix.reduced(state, .goTo(index: 2))
        let middle = try XCTUnwrap(PresFix.present(state).navigator)
        XCTAssertEqual(middle.position, 3)
        XCTAssertTrue(middle.canGoPrevious)
        XCTAssertTrue(middle.canGoNext)
        XCTAssertEqual(PresFix.present(state).header.segments.map { $0.isCurrent }, [false, false, true, false, false, false])
    }

    func testOutOfRangeCurrentIndexIsClamped() throws {
        var state = PresFix.freshUpperA()
        state.currentIndex = 99
        let view = PresFix.present(state)
        XCTAssertEqual(try XCTUnwrap(view.navigator).position, 6)
        XCTAssertEqual(try XCTUnwrap(view.card).exercise.id, "crossover")
        state.currentIndex = -4
        XCTAssertEqual(try XCTUnwrap(PresFix.present(state).navigator).position, 1)
    }

    func testUndoTextWindow() {
        var state = PresFix.freshUpperA()
        WorkoutReducer.reduce(&state, .removeExercise(exerciseID: state.exercises[5].id), now: PresFix.at(10))
        XCTAssertEqual(PresFix.present(state, at: 11).undoText, "Removed Cable crossover")
        XCTAssertEqual(PresFix.present(state, at: 16).undoText, "Removed Cable crossover")
        XCTAssertNil(PresFix.present(state, at: 16.001).undoText)
        XCTAssertNil(PresFix.present(state, at: 60).undoText)
    }

    func testUndoTextForADeletedSet() {
        var state = PresFix.freshUpperA()
        WorkoutReducer.reduce(&state, .deleteSet(exerciseID: state.exercises[1].id, setID: state.exercises[1].sets[0].id), now: PresFix.at(20))
        XCTAssertEqual(PresFix.present(state, at: 21).undoText, "Set deleted")
        XCTAssertEqual(PresFix.present(state, at: 21).totals.totalSets, 19)
    }
}

// MARK: - Presenter: card, recovery, tracking kinds

final class PresenterCardTests: XCTestCase {
    private func levelAndPercent(_ percent: Int) throws -> (Int, ActiveWorkoutPresentation.RecoveryLevel) {
        let provider: RecoveryProvider = { _ in percent }
        let view = WorkoutPresenter.present(PresFix.freshUpperA(), now: PresFix.t0, recovery: provider)
        let card = try XCTUnwrap(view.card)
        return (card.recoveryPercent, card.recoveryLevel)
    }

    func testRecoveryLevelsAtTheThresholds() throws {
        XCTAssertTrue(try levelAndPercent(100) == (100, .good))
        XCTAssertTrue(try levelAndPercent(80) == (80, .good))
        XCTAssertTrue(try levelAndPercent(79) == (79, .fair))
        XCTAssertTrue(try levelAndPercent(60) == (60, .fair))
        XCTAssertTrue(try levelAndPercent(59) == (59, .low))
        XCTAssertTrue(try levelAndPercent(0) == (0, .low))
    }

    func testRecoveryPercentIsClamped() throws {
        XCTAssertTrue(try levelAndPercent(250) == (100, .good))
        XCTAssertTrue(try levelAndPercent(-5) == (0, .low))
    }

    func testRecoveryIsLookedUpByTheMuscleOfTheCurrentExercise() throws {
        var state = PresFix.freshUpperA()
        let provider: RecoveryProvider = { muscle in
            switch muscle {
            case .chest: return 90
            case .shoulders: return 70
            case .arms: return 40
            default: return 100
            }
        }
        XCTAssertEqual(try XCTUnwrap(WorkoutPresenter.present(state, now: PresFix.t0, recovery: provider).card).recoveryPercent, 90)
        state = PresFix.reduced(state, .goTo(index: 2))
        XCTAssertEqual(try XCTUnwrap(WorkoutPresenter.present(state, now: PresFix.t0, recovery: provider).card).recoveryPercent, 70)
        state = PresFix.reduced(state, .goTo(index: 4))
        let card = try XCTUnwrap(WorkoutPresenter.present(state, now: PresFix.t0, recovery: provider).card)
        XCTAssertEqual(card.recoveryPercent, 40)
        XCTAssertEqual(card.recoveryLevel, .low)
    }

    func testDemoRecoveryProviderValues() throws {
        var state = PresFix.freshUpperA()
        state = PresFix.reduced(state, .goTo(index: 3))
        let card = try XCTUnwrap(PresFix.present(state).card)
        XCTAssertEqual(card.exercise.muscle, .shoulders)
        XCTAssertEqual(card.recoveryPercent, 82)
        XCTAssertEqual(card.recoveryLevel, .good)
    }

    func testSupersetLabelAndRestText() throws {
        var state = PresFix.freshUpperA()
        state = PresFix.reduced(state, .goTo(index: 3))
        var card = try XCTUnwrap(PresFix.present(state).card)
        XCTAssertEqual(card.supersetLabel, "Superset A")
        XCTAssertEqual(card.restText, "1:00")
        state = PresFix.reduced(state, .setRest(exerciseID: state.exercises[3].id, seconds: 0))
        card = try XCTUnwrap(PresFix.present(state).card)
        XCTAssertEqual(card.restText, "Off")
        XCTAssertEqual(card.restSeconds, 0)
        state = PresFix.reduced(state, .goTo(index: 5))
        XCTAssertNil(try XCTUnwrap(PresFix.present(state).card).supersetLabel)
    }

    func testNoteIsPassedThrough() throws {
        var state = PresFix.freshUpperA()
        state = PresFix.reduced(state, .setNote(exerciseID: state.exercises[0].id, note: "Pause on the chest"))
        XCTAssertEqual(try XCTUnwrap(PresFix.present(state).card).note, "Pause on the chest")
    }

    func testRepsOnlyExercise() throws {
        let state = PresFix.single(PresFix.lib("pushup"), [(.normal, 0, 12), (.normal, 0, 10)])
        let card = try XCTUnwrap(PresFix.present(state).card)
        XCTAssertEqual(card.weightColumnTitle, "Added")
        XCTAssertEqual(card.repsColumnTitle, "Reps")
        XCTAssertEqual(card.rows.map { $0.weightText }, ["BW", "BW"])
        XCTAssertEqual(card.rows.map { $0.weightEditable }, [false, false])
        XCTAssertEqual(card.rows.map { $0.repsText }, ["12", "10"])
        // The library's last session was 15 reps; the last entry is reused for further sets.
        XCTAssertEqual(card.rows.map { $0.previousText }, ["15 reps", "15 reps"])
        XCTAssertEqual(card.rows[0].accessibilityLabel, "Set 1, working set, bodyweight, 12 reps, not logged")
    }

    func testDurationExercise() throws {
        let state = PresFix.single(PresFix.lib("plank"), [(.normal, 0, 45), (.normal, 0, 40)])
        let card = try XCTUnwrap(PresFix.present(state).card)
        XCTAssertEqual(card.weightColumnTitle, "")
        XCTAssertEqual(card.repsColumnTitle, "Sec")
        XCTAssertEqual(card.rows.map { $0.weightText }, ["–", "–"])
        XCTAssertEqual(card.rows.map { $0.weightEditable }, [false, false])
        XCTAssertEqual(card.rows.map { $0.repsText }, ["45", "40"])
        XCTAssertEqual(card.rows.map { $0.previousText }, ["45 s", "45 s"])
        XCTAssertEqual(card.rows[1].accessibilityLabel, "Set 2, working set, 40 seconds, not logged")
    }

    func testPreviousTextWithoutHistoryAndWithShorterHistory() throws {
        let noHistory = PresFix.single(PresFix.lib("dips"), PresFix.normal(2, 0, 8))
        XCTAssertEqual(try XCTUnwrap(PresFix.present(noHistory).card).rows.map { $0.previousText }, ["–", "–"])

        // Incline has three previous sets; the fourth row reuses the last one.
        let incline = PresFix.single(PresFix.lib("incline"), PresFix.normal(4, 28, 10))
        XCTAssertEqual(
            try XCTUnwrap(PresFix.present(incline).card).rows.map { $0.previousText },
            ["26 × 10", "26 × 10", "26 × 9", "26 × 9"]
        )
    }

    func testPreviousTextFormatsDecimalWeights() throws {
        var exercise = PresFix.lib("bench")
        exercise.previousSets = [PreviousSet(weightKg: 82.5, reps: 5), PreviousSet(weightKg: 80.25, reps: 6)]
        let state = PresFix.single(exercise, PresFix.normal(2, 80, 5))
        XCTAssertEqual(try XCTUnwrap(PresFix.present(state).card).rows.map { $0.previousText }, ["82.5 × 5", "80.25 × 6"])
    }

    func testSetTypeNumberingAndLabels() throws {
        let sets: [PresFix.SetSpec] = [(.warmup, 40, 10), (.normal, 80, 5), (.drop, 60, 8), (.normal, 80, 5), (.failure, 70, 4), (.normal, 80, 5)]
        let state = PresFix.single(PresFix.lib("bench"), sets)
        let rows = try XCTUnwrap(PresFix.present(state).card).rows
        XCTAssertEqual(rows.map { $0.number }, ["W", "1", "D", "2", "F", "3"])
        XCTAssertEqual(rows[2].accessibilityLabel, "Set 3, drop set, 60 kilograms, 8 reps, not logged")
        XCTAssertEqual(rows[4].accessibilityLabel, "Set 5, failure set, 70 kilograms, 4 reps, not logged")
    }

    func testAccessibilityLabelSingulars() throws {
        let state = PresFix.single(PresFix.lib("bench"), [(.normal, 1, 1)])
        XCTAssertEqual(try XCTUnwrap(PresFix.present(state).card).rows[0].accessibilityLabel, "Set 1, working set, 1 kilogram, 1 rep, not logged")
        let plank = PresFix.single(PresFix.lib("plank"), [(.normal, 0, 1)])
        XCTAssertEqual(try XCTUnwrap(PresFix.present(plank).card).rows[0].accessibilityLabel, "Set 1, working set, 1 second, not logged")
    }

    func testRIRText() throws {
        var state = PresFix.single(PresFix.lib("bench"), PresFix.normal(4, 80, 5))
        state = PresFix.marking(state, exercise: 0, done: [0, 1, 2])
        state.exercises[0].sets[0].rir = 0
        state.exercises[0].sets[1].rir = 4
        state.exercises[0].sets[2].rir = nil
        state.exercises[0].sets[3].rir = 2   // pending sets never show a RIR tag
        let rows = try XCTUnwrap(PresFix.present(state).card).rows
        XCTAssertEqual(rows.map { $0.rirText }, ["RIR 0", "RIR 4+", nil, nil])
        XCTAssertEqual(rows.map { $0.rir }, [0, 4, nil, 2])
    }

    func testOnlyTheFirstPendingSetIsNext() throws {
        var state = PresFix.single(PresFix.lib("bench"), PresFix.normal(4, 80, 5))
        XCTAssertEqual(try XCTUnwrap(PresFix.present(state).card).rows.map { $0.isNext }, [true, false, false, false])
        state = PresFix.marking(state, exercise: 0, done: [0, 2])
        XCTAssertEqual(try XCTUnwrap(PresFix.present(state).card).rows.map { $0.isNext }, [false, true, false, false])
        state = PresFix.marking(state, exercise: 0, done: [1, 3])
        XCTAssertEqual(try XCTUnwrap(PresFix.present(state).card).rows.map { $0.isNext }, [false, false, false, false])
    }

    func testCardFollowsTheCurrentExercise() throws {
        var state = PresFix.freshUpperA()
        state = PresFix.reduced(state, .nextExercise)
        let card = try XCTUnwrap(PresFix.present(state).card)
        XCTAssertEqual(card.exercise.id, "incline")
        XCTAssertEqual(card.exerciseID, state.exercises[1].id)
        XCTAssertEqual(card.rows.map { $0.weightText }, ["28", "28", "28"])
        XCTAssertEqual(card.restText, "1:30")
    }
}

// MARK: - Presenter: personal records and the coach tip

final class PresenterRecordTests: XCTestCase {
    private func rows(_ exercise: Exercise, _ sets: [PresFix.SetSpec], done: [Int]) throws -> [ActiveWorkoutPresentation.SetRow] {
        let state = PresFix.marking(PresFix.single(exercise, sets), exercise: 0, done: done)
        return try XCTUnwrap(PresFix.present(state).card).rows
    }

    func testBaselineRisesWithinOneWorkout() throws {
        let result = try rows(PresFix.lib("bench", best: 80), [(.normal, 85, 5), (.normal, 85, 6)], done: [0, 1])
        XCTAssertEqual(result.map { $0.isPersonalRecord }, [true, true])
        // 85 x 5 = 99.17 and 85 x 6 = 102.
        XCTAssertEqual(result.map { $0.estimated1RM }, [99, 102])
    }

    func testAnEqualOrLowerSetAfterARecordIsNoRecord() throws {
        let result = try rows(PresFix.lib("bench", best: 80), [(.normal, 85, 6), (.normal, 85, 5), (.normal, 85, 6)], done: [0, 1, 2])
        XCTAssertEqual(result.map { $0.isPersonalRecord }, [true, false, false])
        XCTAssertEqual(result.map { $0.estimated1RM }, [102, nil, nil])
    }

    func testASetMustBeatTheBaselineNotJustEqualIt() throws {
        // 82.5 x 6 = 99.0 = the previous best: not a record. 49.75 x 30 = 99.5: a record.
        let equal = try rows(PresFix.lib("bench"), [(.normal, 82.5, 6)], done: [0])
        XCTAssertEqual(equal.map { $0.isPersonalRecord }, [false])
        let above = try rows(PresFix.lib("bench"), [(.normal, 49.75, 30)], done: [0])
        XCTAssertEqual(above.map { $0.isPersonalRecord }, [true])
        XCTAssertEqual(above.map { $0.estimated1RM }, [100])   // 99.5 rounds half up
    }

    func testARecordMustBeatTheBaselineByMoreThanFiftyGrams() throws {
        // 49.51 x 30 = 99.02: above the previous best of 99 but within the 0.05 margin.
        let within = try rows(PresFix.lib("bench"), [(.normal, 49.51, 30)], done: [0])
        XCTAssertEqual(within.map { $0.isPersonalRecord }, [false])
        // 49.53 x 30 = 99.06 clears the margin.
        let beyond = try rows(PresFix.lib("bench"), [(.normal, 49.53, 30)], done: [0])
        XCTAssertEqual(beyond.map { $0.isPersonalRecord }, [true])
        // The same margin applies to the coach tip: with a best of 98.96, 82.5 x 6 (99.0) is not enough.
        let state = PresFix.single(PresFix.lib("bench", best: 98.96), [(.normal, 70, 6)])
        XCTAssertEqual(
            try XCTUnwrap(PresFix.present(state).card).coachTip,
            "85 kg × 6 on your last set would beat your best estimated 1RM of 99 kg."
        )
    }

    func testNoRecordWithoutHistory() throws {
        let exercise = PresFix.lib("bench", best: 0)
        let result = try rows(exercise, [(.normal, 100, 5), (.normal, 110, 5)], done: [0, 1])
        XCTAssertEqual(result.map { $0.isPersonalRecord }, [false, false])
        XCTAssertEqual(result.map { $0.estimated1RM }, [nil, nil])
        let state = PresFix.marking(PresFix.single(exercise, [(.normal, 100, 5)]), exercise: 0, done: [0])
        XCTAssertNil(try XCTUnwrap(PresFix.present(state).card).coachTip)
    }

    func testPendingSetsAreNeverRecordsAndDoNotRaiseTheBaseline() throws {
        let result = try rows(PresFix.lib("bench", best: 80), [(.normal, 120, 5), (.normal, 85, 5)], done: [1])
        XCTAssertEqual(result.map { $0.isPersonalRecord }, [false, true])
    }

    func testWarmUpsNeverCountAsRecordsOrRaiseTheBaseline() throws {
        let result = try rows(PresFix.lib("bench", best: 80), [(.warmup, 100, 5), (.normal, 85, 5)], done: [0, 1])
        XCTAssertEqual(result.map { $0.isPersonalRecord }, [false, true])
        XCTAssertEqual(result.map { $0.estimated1RM }, [nil, 99])
    }

    func testDropAndFailureSetsCanBeRecords() throws {
        let result = try rows(PresFix.lib("bench", best: 80), [(.failure, 85, 5), (.drop, 90, 5)], done: [0, 1])
        XCTAssertEqual(result.map { $0.isPersonalRecord }, [true, true])
    }

    func testBodyweightAndDurationExercisesNeverGetRecords() throws {
        var pushup = PresFix.lib("pushup")
        pushup.previousBestE1RM = 10
        XCTAssertEqual(try rows(pushup, [(.normal, 20, 30)], done: [0]).map { $0.isPersonalRecord }, [false])
        var plank = PresFix.lib("plank")
        plank.previousBestE1RM = 10
        XCTAssertEqual(try rows(plank, [(.normal, 20, 300)], done: [0]).map { $0.isPersonalRecord }, [false])
    }

    func testUnloggingARecordRemovesTheFlag() throws {
        var state = PresFix.marking(PresFix.single(PresFix.lib("bench", best: 80), [(.normal, 85, 5)]), exercise: 0, done: [0])
        XCTAssertEqual(try XCTUnwrap(PresFix.present(state).card).rows.map { $0.isPersonalRecord }, [true])
        state = PresFix.reduced(state, PresFix.log(state, 0, 0))   // logSet on a done set is a no-op
        XCTAssertEqual(try XCTUnwrap(PresFix.present(state).card).rows.map { $0.isPersonalRecord }, [true])
        state = PresFix.reduced(state, .toggleSet(exerciseID: state.exercises[0].id, setID: state.exercises[0].sets[0].id))
        XCTAssertEqual(try XCTUnwrap(PresFix.present(state).card).rows.map { $0.isPersonalRecord }, [false])
    }

    // MARK: Coach tip

    func testCoachTipUsesTheLastPendingNormalSet() throws {
        // Previous best 99: with 6 reps the lowest 2.5 kg multiple above 99.05 is 85 kg.
        let state = PresFix.single(PresFix.lib("bench"), [(.normal, 82.5, 6), (.normal, 60, 6), (.failure, 50, 4)])
        XCTAssertEqual(
            try XCTUnwrap(PresFix.present(state).card).coachTip,
            "85 kg × 6 on your last set would beat your best estimated 1RM of 99 kg."
        )
    }

    func testCoachTipIgnoresTheCurrentWeightOfTheSet() throws {
        // The set already equals the target weight (or is far above it): the tip is the same.
        for weight in [85.0, 100.0, 40.0] {
            let state = PresFix.single(PresFix.lib("bench"), [(.normal, weight, 6)])
            XCTAssertEqual(
                try XCTUnwrap(PresFix.present(state).card).coachTip,
                "85 kg × 6 on your last set would beat your best estimated 1RM of 99 kg."
            )
        }
    }

    func testCoachTipUsesTheRepsOfTheTargetSet() throws {
        // 5 reps: 99.05 / (1 + 5/30) = 84.9 -> 85 kg (99.17); 8 reps: 99.05 / 1.2667 = 78.2 -> 80 kg.
        let five = PresFix.single(PresFix.lib("bench"), [(.normal, 70, 5)])
        XCTAssertEqual(try XCTUnwrap(PresFix.present(five).card).coachTip, "85 kg × 5 on your last set would beat your best estimated 1RM of 99 kg.")
        let eight = PresFix.single(PresFix.lib("bench"), [(.normal, 70, 8)])
        XCTAssertEqual(try XCTUnwrap(PresFix.present(eight).card).coachTip, "80 kg × 8 on your last set would beat your best estimated 1RM of 99 kg.")
    }

    func testCoachTipUsesTheWeightStepOfTheEquipment() throws {
        // Incline dumbbell press: best 38, 10 reps -> 38.05 / 1.3333 = 28.54 -> next multiple of 2 kg is 30.
        let dumbbell = PresFix.single(PresFix.lib("incline"), [(.normal, 24, 10)])
        XCTAssertEqual(try XCTUnwrap(PresFix.present(dumbbell).card).coachTip, "30 kg × 10 on your last set would beat your best estimated 1RM of 38 kg.")
        // A 1 kg step (bodyweight-style equipment with a weight column): 99.05 / 1.2 = 82.54 -> 83.
        var odd = PresFix.lib("bench")
        odd.equipment = .other
        let state = PresFix.single(odd, [(.normal, 70, 6)])
        XCTAssertEqual(try XCTUnwrap(PresFix.present(state).card).coachTip, "83 kg × 6 on your last set would beat your best estimated 1RM of 99 kg.")
    }

    func testCoachTipFallsBackToTheLastPendingNonWarmUpSet() throws {
        let state = PresFix.single(PresFix.lib("bench"), [(.warmup, 50, 8), (.drop, 60, 6), (.failure, 50, 6)])
        // The last pending set is a failure set with 6 reps.
        XCTAssertEqual(
            try XCTUnwrap(PresFix.present(state).card).coachTip,
            "85 kg × 6 on your last set would beat your best estimated 1RM of 99 kg."
        )
    }

    func testCoachTipBaselineRisesWithLoggedSets() throws {
        // 85 x 6 logged: the best is now 102, so the last set needs 87.5 kg (87.5 x 6 = 105).
        let state = PresFix.marking(
            PresFix.single(PresFix.lib("bench"), [(.normal, 85, 6), (.normal, 85, 6)]), exercise: 0, done: [0]
        )
        XCTAssertEqual(
            try XCTUnwrap(PresFix.present(state).card).coachTip,
            "87.5 kg × 6 on your last set would beat your best estimated 1RM of 102 kg."
        )
    }

    func testNoCoachTipVariants() throws {
        // All sets logged / only warm-ups pending.
        let allDone = PresFix.marking(PresFix.single(PresFix.lib("bench"), PresFix.normal(2, 80, 5)), exercise: 0, done: [0, 1])
        XCTAssertNil(try XCTUnwrap(PresFix.present(allDone).card).coachTip)
        let onlyWarmUp = PresFix.marking(PresFix.single(PresFix.lib("bench"), [(.warmup, 50, 8), (.normal, 80, 5)]), exercise: 0, done: [1])
        XCTAssertNil(try XCTUnwrap(PresFix.present(onlyWarmUp).card).coachTip)
        // Not a weight exercise.
        var pushup = PresFix.lib("pushup")
        pushup.previousBestE1RM = 40
        XCTAssertNil(try XCTUnwrap(PresFix.present(PresFix.single(pushup, PresFix.normal(2, 0, 12))).card).coachTip)
        // Zero reps cannot beat anything.
        XCTAssertNil(try XCTUnwrap(PresFix.present(PresFix.single(PresFix.lib("bench"), [(.normal, 80, 0)])).card).coachTip)
    }

    func testNoCoachTipWhileARestIsRunningEvenWhenFinished() throws {
        var state = PresFix.single(PresFix.lib("bench"), PresFix.normal(3, 80, 5))
        state.rest = RestState(endsAt: PresFix.at(100), totalSeconds: 100)
        XCTAssertNil(try XCTUnwrap(PresFix.present(state, at: 50).card).coachTip)
        XCTAssertNil(try XCTUnwrap(PresFix.present(state, at: 500).card).coachTip)
        state.rest = nil
        XCTAssertNotNil(try XCTUnwrap(PresFix.present(state, at: 500).card).coachTip)
    }
}

// MARK: - Presenter: the rest dock

final class PresenterDockTests: XCTestCase {
    /// Bench-only workout with `sets` normal sets of 80 x 5; the first set was logged at `t0 + 100` (150 s rest).
    private func benchAfterFirstSet(sets: Int = 3) -> WorkoutState {
        var state = PresFix.single(PresFix.lib("bench"), PresFix.normal(sets, 80, 5), rest: 150)
        WorkoutReducer.reduce(&state, PresFix.log(state, 0, 0), now: PresFix.at(100))
        return state
    }

    func testNoDockWithoutARest() {
        XCTAssertNil(PresFix.present(PresFix.freshUpperA()).dock)
        var state = benchAfterFirstSet()
        state = PresFix.reduced(state, .skipRest, at: 110)
        XCTAssertNil(PresFix.present(state, at: 111).dock)
    }

    func testRunningDockAndCeilingOfTheRemainingTime() throws {
        let state = benchAfterFirstSet()   // rest ends at t0 + 250
        var dock = try XCTUnwrap(PresFix.present(state, at: 100).dock)
        XCTAssertEqual(dock.remainingSeconds, 150)
        XCTAssertEqual(dock.remainingText, "2:30")
        XCTAssertEqual(dock.fraction, 1, accuracy: 0.0001)
        dock = try XCTUnwrap(PresFix.present(state, at: 100.4).dock)
        XCTAssertEqual(dock.remainingSeconds, 150)   // 149.6 s rounds up
        dock = try XCTUnwrap(PresFix.present(state, at: 101).dock)
        XCTAssertEqual(dock.remainingSeconds, 149)
        XCTAssertEqual(dock.remainingText, "2:29")
        dock = try XCTUnwrap(PresFix.present(state, at: 249.5).dock)
        XCTAssertEqual(dock.remainingSeconds, 1)
        XCTAssertEqual(dock.remainingText, "0:01")
        XCTAssertEqual(dock.phase, .running)
    }

    func testFinishedDock() throws {
        let state = benchAfterFirstSet()
        for seconds in [250.0, 250.0001, 300, 10_000] {
            let dock = try XCTUnwrap(PresFix.present(state, at: seconds).dock)
            XCTAssertEqual(dock.phase, .finished, "at \(seconds)")
            XCTAssertEqual(dock.remainingSeconds, 0)
            XCTAssertEqual(dock.remainingText, "Go")
            XCTAssertEqual(dock.fraction, 1)
            XCTAssertEqual(dock.totalSeconds, 150)
        }
    }

    func testNextSetTextForWorkingSets() throws {
        let state = benchAfterFirstSet()
        XCTAssertEqual(try XCTUnwrap(PresFix.present(state, at: 101).dock).nextSetText, "Next · Set 2 · 80 kg × 5")
        let more = PresFix.reduced(state, PresFix.log(state, 0, 1), at: 120)
        XCTAssertEqual(try XCTUnwrap(PresFix.present(more, at: 121).dock).nextSetText, "Next · Set 3 · 80 kg × 5")
    }

    func testNextSetTextForWarmUpDropAndFailureSets() throws {
        let sets: [PresFix.SetSpec] = [(.warmup, 50, 8), (.normal, 80, 5), (.drop, 60, 8), (.failure, 70, 4), (.normal, 82.5, 6)]
        var state = PresFix.single(PresFix.lib("bench"), sets, rest: 150)
        // A stray rest keeps the dock visible while sets are marked as logged one by one.
        state.rest = RestState(endsAt: PresFix.at(500), totalSeconds: 150)
        XCTAssertEqual(try XCTUnwrap(PresFix.present(state, at: 400).dock).nextSetText, "Next · Warm-up · 50 kg × 8")
        state = PresFix.marking(state, exercise: 0, done: [0])
        XCTAssertEqual(try XCTUnwrap(PresFix.present(state, at: 400).dock).nextSetText, "Next · Set 1 · 80 kg × 5")
        state = PresFix.marking(state, exercise: 0, done: [1])
        XCTAssertEqual(try XCTUnwrap(PresFix.present(state, at: 400).dock).nextSetText, "Next · Set D · 60 kg × 8")
        state = PresFix.marking(state, exercise: 0, done: [2])
        XCTAssertEqual(try XCTUnwrap(PresFix.present(state, at: 400).dock).nextSetText, "Next · Set F · 70 kg × 4")
        state = PresFix.marking(state, exercise: 0, done: [3])
        XCTAssertEqual(try XCTUnwrap(PresFix.present(state, at: 400).dock).nextSetText, "Next · Set 2 · 82.5 kg × 6")
    }

    func testNextSetTextForRepsOnlyAndDuration() throws {
        var pushup = PresFix.single(PresFix.lib("pushup"), [(.normal, 0, 12), (.normal, 0, 10)])
        pushup.rest = RestState(endsAt: PresFix.at(100), totalSeconds: 60)
        XCTAssertEqual(try XCTUnwrap(PresFix.present(pushup, at: 50).dock).nextSetText, "Next · Set 1 · 12 reps")
        var plank = PresFix.single(PresFix.lib("plank"), [(.normal, 0, 45)])
        plank.rest = RestState(endsAt: PresFix.at(100), totalSeconds: 45)
        XCTAssertEqual(try XCTUnwrap(PresFix.present(plank, at: 50).dock).nextSetText, "Next · Set 1 · 45 s")
    }

    func testAllSetsLoggedText() throws {
        var state = PresFix.single(PresFix.lib("bench"), PresFix.normal(2, 80, 5), rest: 150)
        state = PresFix.reduced(state, PresFix.log(state, 0, 0), at: 10)
        state = PresFix.reduced(state, PresFix.log(state, 0, 1), at: 20)
        let dock = try XCTUnwrap(PresFix.present(state, at: 30).dock)
        XCTAssertEqual(dock.nextSetText, "All sets logged")
        XCTAssertTrue(dock.showsRIR)
    }

    func testRIRSelectorFollowsTheLastLoggedSet() throws {
        var state = benchAfterFirstSet()
        var dock = try XCTUnwrap(PresFix.present(state, at: 101).dock)
        XCTAssertTrue(dock.showsRIR)
        XCTAssertNil(dock.rirSelection)

        state = PresFix.reduced(state, .toggleLastSetRIR(2), at: 102)
        dock = try XCTUnwrap(PresFix.present(state, at: 103).dock)
        XCTAssertEqual(dock.rirSelection, 2)
        state = PresFix.reduced(state, .toggleLastSetRIR(4), at: 104)
        XCTAssertEqual(try XCTUnwrap(PresFix.present(state, at: 105).dock).rirSelection, 4)
        state = PresFix.reduced(state, .toggleLastSetRIR(4), at: 106)
        XCTAssertNil(try XCTUnwrap(PresFix.present(state, at: 107).dock).rirSelection)
    }

    func testRIRSelectorIsHiddenAfterAWarmUp() throws {
        var state = PresFix.single(PresFix.lib("bench"), [(.warmup, 50, 8), (.normal, 80, 5)], rest: 150)
        state = PresFix.reduced(state, PresFix.log(state, 0, 0), at: 10)
        let dock = try XCTUnwrap(PresFix.present(state, at: 11).dock)
        XCTAssertFalse(dock.showsRIR)
        XCTAssertNil(dock.rirSelection)
        XCTAssertEqual(dock.nextSetText, "Next · Set 1 · 80 kg × 5")
    }

    func testRIRSelectorIsHiddenWhenTheLastLoggedSetIsNoLongerDone() throws {
        var state = benchAfterFirstSet()
        state = PresFix.reduced(state, .toggleSet(exerciseID: state.exercises[0].id, setID: state.exercises[0].sets[0].id), at: 110)
        state.rest = RestState(endsAt: PresFix.at(300), totalSeconds: 150)   // a stray rest is still shown
        XCTAssertFalse(try XCTUnwrap(PresFix.present(state, at: 120).dock).showsRIR)
    }

    func testRIRSelectorIsHiddenWithoutAResolvableLastLoggedSet() throws {
        var state = benchAfterFirstSet()
        state.lastLogged = nil
        XCTAssertFalse(try XCTUnwrap(PresFix.present(state, at: 120).dock).showsRIR)
        state.lastLogged = SetRef(exerciseID: PresFix.uuid(0xAAAA, 1), setID: PresFix.uuid(0xAAAA, 2))
        XCTAssertFalse(try XCTUnwrap(PresFix.present(state, at: 120).dock).showsRIR)
        state.lastLogged = SetRef(exerciseID: state.exercises[0].id, setID: PresFix.uuid(0xAAAA, 3))
        XCTAssertFalse(try XCTUnwrap(PresFix.present(state, at: 120).dock).showsRIR)
    }

    func testRIRSelectorResolvesAcrossExercises() throws {
        // The last logged set belongs to another exercise than the one on the card.
        var state = PresFix.freshUpperA()
        state = PresFix.reduced(state, .goTo(index: 2))
        state = PresFix.reduced(state, PresFix.log(state, 2, 0), at: 10)
        state = PresFix.reduced(state, .toggleLastSetRIR(1), at: 11)
        state = PresFix.reduced(state, .goTo(index: 0), at: 12)
        let dock = try XCTUnwrap(PresFix.present(state, at: 20).dock)
        XCTAssertTrue(dock.showsRIR)
        XCTAssertEqual(dock.rirSelection, 1)
    }

    func testDockWhilePausedIsFrozen() throws {
        var state = benchAfterFirstSet()   // rest ends at t0 + 250
        state = PresFix.reduced(state, .pause, at: 130)
        for seconds in [131.0, 200, 5000] {
            let dock = try XCTUnwrap(PresFix.present(state, at: seconds).dock)
            XCTAssertEqual(dock.remainingSeconds, 120, "at \(seconds)")
            XCTAssertEqual(dock.remainingText, "2:00")
            XCTAssertEqual(dock.phase, .running)
            XCTAssertTrue(dock.isPaused)
        }
        state = PresFix.reduced(state, .resume, at: 520)   // 390 s paused
        let dock = try XCTUnwrap(PresFix.present(state, at: 560).dock)
        XCTAssertEqual(dock.remainingSeconds, 80)
        XCTAssertFalse(dock.isPaused)
    }

    func testDockFractionWithZeroTotalIsZero() throws {
        var state = PresFix.single(PresFix.lib("bench"), PresFix.normal(2, 80, 5))
        state.rest = RestState(endsAt: PresFix.at(100), totalSeconds: 0)
        let dock = try XCTUnwrap(PresFix.present(state, at: 50).dock)
        XCTAssertEqual(dock.fraction, 0)
        XCTAssertEqual(dock.remainingSeconds, 50)
    }

    func testRestAdjustmentIsReflected() throws {
        var state = benchAfterFirstSet()
        state = PresFix.reduced(state, .adjustRest(seconds: 15), at: 110)   // ends at t0 + 265, total 165
        let dock = try XCTUnwrap(PresFix.present(state, at: 115).dock)
        XCTAssertEqual(dock.remainingSeconds, 150)
        XCTAssertEqual(dock.totalSeconds, 165)
        XCTAssertEqual(dock.fraction, 150.0 / 165.0, accuracy: 0.0001)
    }
}

// MARK: - Presenter: finish check

final class PresenterFinishCheckTests: XCTestCase {
    func testNothingLogged() {
        let check = PresFix.present(PresFix.freshUpperA()).finishCheck
        XCTAssertEqual(check.loggedSets, 0)
        XCTAssertEqual(check.unloggedSets, 20)
        XCTAssertFalse(check.canFinish)
        XCTAssertEqual(check.title, "Nothing logged yet")
        XCTAssertEqual(check.message, "Log at least one set to save this workout.")
    }

    func testOneUnloggedSetUsesTheSingular() {
        var state = PresFix.loggedEverything(PresFix.freshUpperA())
        let last = state.exercises[5].sets[2]
        state = PresFix.reduced(state, .toggleSet(exerciseID: state.exercises[5].id, setID: last.id))
        let check = PresFix.present(state).finishCheck
        XCTAssertEqual(check.loggedSets, 19)
        XCTAssertEqual(check.unloggedSets, 1)
        XCTAssertTrue(check.canFinish)
        XCTAssertEqual(check.title, "Finish workout?")
        XCTAssertEqual(check.message, "1 set is not logged yet and will be left out.")
    }

    func testSeveralUnloggedSetsUseThePlural() {
        let state = PresFix.goldenState()
        XCTAssertEqual(PresFix.present(state, at: 1500).finishCheck.message, "17 sets are not logged yet and will be left out.")
        let two = PresFix.marking(PresFix.single(PresFix.lib("bench"), PresFix.normal(4, 80, 5)), exercise: 0, done: [0, 1])
        XCTAssertEqual(PresFix.present(two).finishCheck.message, "2 sets are not logged yet and will be left out.")
    }

    func testAllSetsLogged() {
        let state = PresFix.loggedEverything(PresFix.freshUpperA())
        let view = PresFix.present(state, at: 600)
        XCTAssertEqual(view.finishCheck.loggedSets, 20)
        XCTAssertEqual(view.finishCheck.unloggedSets, 0)
        XCTAssertTrue(view.finishCheck.canFinish)
        XCTAssertEqual(view.finishCheck.title, "Finish workout?")
        XCTAssertEqual(view.finishCheck.message, "All sets are logged. Nice work.")
        XCTAssertEqual(view.header.setsText, "20 of 20")
        XCTAssertEqual(view.totals.completedExercises, 6)
        XCTAssertTrue(view.header.segments.allSatisfy { $0.fraction == 1 })
    }

    func testTemplateChangesAskToUpdateTheTemplate() {
        var state = PresFix.goldenState()
        state = PresFix.reduced(state, .removeExercise(exerciseID: state.exercises[5].id), at: 1500)
        state = PresFix.reduced(state, .addExercises([PresFix.lib("pushup")]), at: 1501)
        let check = PresFix.present(state, at: 1502).finishCheck
        XCTAssertEqual(check.templateDiff, TemplateDiff(added: 1, removed: 1, reordered: false))
        XCTAssertEqual(check.diffMessage, "Changes: 1 added, 1 removed.")
        XCTAssertTrue(check.asksToUpdateTemplate)
    }

    func testNoTemplateMeansNoUpdateQuestion() {
        var state = WorkoutFactory.makeEmpty(name: "Workout", now: PresFix.t0)
        state = PresFix.reduced(state, .addExercises([PresFix.lib("bench"), PresFix.lib("incline")]), at: 1)
        let check = PresFix.present(state, at: 2).finishCheck
        XCTAssertFalse(check.templateDiff.isEmpty)
        XCTAssertNil(state.templateID)
        XCTAssertFalse(check.asksToUpdateTemplate)
        XCTAssertEqual(check.diffMessage, "Changes: 2 added.")
    }

    func testDiffMessageListsEveryKindOfChange() {
        var state = PresFix.freshUpperA()
        state = PresFix.reduced(state, .moveExercise(from: 0, to: 2), at: 1)
        state = PresFix.reduced(state, .removeExercise(exerciseID: state.exercises[4].id), at: 2)
        state = PresFix.reduced(state, .addExercises([PresFix.lib("dips")]), at: 3)
        let check = PresFix.present(state, at: 4).finishCheck
        XCTAssertEqual(check.diffMessage, "Changes: 1 added, 1 removed, new order.")
        XCTAssertTrue(check.asksToUpdateTemplate)
    }
}

// MARK: - Template diff

final class TemplateDiffComputeTests: XCTestCase {
    func testUntouchedWorkoutHasNoDiff() {
        let diff = TemplateDiff.compute(for: PresFix.freshUpperA())
        XCTAssertTrue(diff.isEmpty)
        XCTAssertEqual(diff, TemplateDiff(added: 0, removed: 0, reordered: false))
    }

    func testProgressDoesNotChangeTheDiff() {
        XCTAssertTrue(TemplateDiff.compute(for: PresFix.goldenState()).isEmpty)
        XCTAssertTrue(TemplateDiff.compute(for: PresFix.loggedEverything(PresFix.freshUpperA())).isEmpty)
    }

    func testAddedExercises() {
        var state = PresFix.freshUpperA()
        state = PresFix.reduced(state, .addExercises([PresFix.lib("dips")]))
        XCTAssertEqual(TemplateDiff.compute(for: state), TemplateDiff(added: 1, removed: 0, reordered: false))
        state = PresFix.reduced(state, .addExercises([PresFix.lib("pullup"), PresFix.lib("squat")]))
        XCTAssertEqual(TemplateDiff.compute(for: state), TemplateDiff(added: 3, removed: 0, reordered: false))
    }

    func testRemovedExercises() {
        var state = PresFix.freshUpperA()
        state = PresFix.reduced(state, .removeExercise(exerciseID: state.exercises[2].id))
        XCTAssertEqual(TemplateDiff.compute(for: state), TemplateDiff(added: 0, removed: 1, reordered: false))
        state = PresFix.reduced(state, .removeExercise(exerciseID: state.exercises[0].id))
        XCTAssertEqual(TemplateDiff.compute(for: state), TemplateDiff(added: 0, removed: 2, reordered: false))
    }

    func testRemovingAndUndoingRestoresTheOriginalDiff() {
        var state = PresFix.freshUpperA()
        state = PresFix.reduced(state, .removeExercise(exerciseID: state.exercises[2].id), at: 1)
        XCTAssertEqual(TemplateDiff.compute(for: state).removed, 1)
        state = PresFix.reduced(state, .undo, at: 2)
        XCTAssertTrue(TemplateDiff.compute(for: state).isEmpty)
    }

    func testReorderedExercises() {
        var state = PresFix.freshUpperA()
        state = PresFix.reduced(state, .moveExercise(from: 0, to: 3))
        XCTAssertEqual(TemplateDiff.compute(for: state), TemplateDiff(added: 0, removed: 0, reordered: true))
        // Moving it back restores the baseline order.
        state = PresFix.reduced(state, .moveExercise(from: 3, to: 0))
        XCTAssertTrue(TemplateDiff.compute(for: state).isEmpty)
    }

    func testSwappingNeighboursCountsAsReordered() {
        var state = PresFix.freshUpperA()
        state = PresFix.reduced(state, .moveExerciseBy(exerciseID: state.exercises[1].id, delta: 1))
        XCTAssertTrue(TemplateDiff.compute(for: state).reordered)
    }

    func testCombinedChanges() {
        var state = PresFix.freshUpperA()
        state = PresFix.reduced(state, .removeExercise(exerciseID: state.exercises[1].id), at: 1)
        state = PresFix.reduced(state, .addExercises([PresFix.lib("dips"), PresFix.lib("pullup")]), at: 2)
        state = PresFix.reduced(state, .moveExercise(from: 0, to: 2), at: 3)
        let diff = TemplateDiff.compute(for: state)
        XCTAssertEqual(diff, TemplateDiff(added: 2, removed: 1, reordered: true))
        XCTAssertEqual(diff.summary, "2 added, 1 removed, new order")
    }

    func testRemovingFromTheMiddleIsNotAReorder() {
        var state = PresFix.freshUpperA()
        state = PresFix.reduced(state, .removeExercise(exerciseID: state.exercises[2].id))
        XCTAssertFalse(TemplateDiff.compute(for: state).reordered)
    }

    func testMovingAnAddedExerciseIsNotAReorder() {
        var state = PresFix.freshUpperA()
        state = PresFix.reduced(state, .addExercises([PresFix.lib("dips")]), at: 1)
        state = PresFix.reduced(state, .moveExercise(from: 6, to: 0), at: 2)
        XCTAssertEqual(TemplateDiff.compute(for: state), TemplateDiff(added: 1, removed: 0, reordered: false))
    }

    func testReplacingKeepsTheTemplateEntry() {
        var state = PresFix.freshUpperA()
        state = PresFix.reduced(state, .replaceExercise(exerciseID: state.exercises[1].id, with: PresFix.lib("cpress")))
        XCTAssertTrue(TemplateDiff.compute(for: state).isEmpty)
    }

    func testWorkoutWithoutTemplateCountsEveryExerciseAsAdded() {
        var state = WorkoutFactory.makeEmpty(name: "Workout", now: PresFix.t0)
        XCTAssertTrue(TemplateDiff.compute(for: state).isEmpty)
        state = PresFix.reduced(state, .addExercises([PresFix.lib("bench"), PresFix.lib("incline")]))
        XCTAssertEqual(TemplateDiff.compute(for: state), TemplateDiff(added: 2, removed: 0, reordered: false))
    }

    func testExercisesWithEntriesOutsideTheBaselineAreAdded() {
        var state = PresFix.freshUpperA()
        state.exercises[0].templateEntryID = PresFix.uuid(0xBEEF, 1)
        XCTAssertEqual(TemplateDiff.compute(for: state), TemplateDiff(added: 1, removed: 1, reordered: false))
    }

    func testADuplicatedTemplateEntryCountsAsAdded() {
        var state = PresFix.freshUpperA()
        var copy = state.exercises[0]
        copy.id = PresFix.uuid(0xCAFE, 1)
        state.exercises.append(copy)
        XCTAssertEqual(TemplateDiff.compute(for: state), TemplateDiff(added: 1, removed: 0, reordered: false))
    }

    func testEverythingRemovedAndReplacedByNewExercises() {
        var state = PresFix.freshUpperA()
        state.exercises = [PresFix.entry(1, PresFix.lib("squat"), PresFix.normal(3, 60, 6))]
        XCTAssertEqual(TemplateDiff.compute(for: state), TemplateDiff(added: 1, removed: 6, reordered: false))
        state.exercises = []
        XCTAssertEqual(TemplateDiff.compute(for: state), TemplateDiff(added: 0, removed: 6, reordered: false))
    }
}

// MARK: - Fuzz: invariants under random action sequences

/// Tiny deterministic linear congruential generator (no real randomness).
struct PresLCG {
    private var state: UInt64

    init(seed: UInt64) { state = seed &* 6364136223846793005 &+ 1442695040888963407 }

    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state >> 33
    }

    mutating func below(_ bound: Int) -> Int { bound <= 0 ? 0 : Int(next() % UInt64(bound)) }
}

final class PresenterFuzzTests: XCTestCase {
    private func randomAction(_ state: WorkoutState, _ rng: inout PresLCG) -> WorkoutAction {
        let exercise = state.exercises.isEmpty ? nil : state.exercises[rng.below(state.exercises.count)]
        let set = exercise.flatMap { $0.sets.isEmpty ? nil : $0.sets[rng.below($0.sets.count)] }
        let exerciseID = exercise?.id ?? PresFix.uuid(0xDEAD, 1)
        let setID = set?.id ?? PresFix.uuid(0xDEAD, 2)
        switch rng.below(22) {
        case 0, 1, 2, 3: return .toggleSet(exerciseID: exerciseID, setID: setID)
        case 4, 5: return .logNextSet
        case 6: return .logSet(exerciseID: exerciseID, setID: setID)
        case 7: return .setRIR(exerciseID: exerciseID, setID: setID, rir: rng.below(6) == 5 ? nil : rng.below(5))
        case 8: return .toggleLastSetRIR(rng.below(5))
        case 9: return .setSetType(exerciseID: exerciseID, setID: setID, type: SetType.allCases[rng.below(4)])
        case 10: return .addSet(exerciseID: exerciseID)
        case 11: return .deleteSet(exerciseID: exerciseID, setID: setID)
        case 12: return .removeExercise(exerciseID: exerciseID)
        case 13: return .undo
        case 14: return .moveExercise(from: rng.below(8), to: rng.below(8))
        case 15: return .goTo(index: rng.below(8))
        case 16: return .addExercises([PresFix.lib(["dips", "pushup", "plank", "squat", "bench"][rng.below(5)])])
        case 17: return .adjustRest(seconds: rng.below(2) == 0 ? 15 : -15)
        case 18: return rng.below(2) == 0 ? .pause : .resume
        case 19: return .setWeight(exerciseID: exerciseID, setID: setID, kg: Double(rng.below(200)) / 2)
        case 20: return .toggleSuperset(exerciseID: exerciseID)
        default: return .skipRest
        }
    }

    private func check(_ state: WorkoutState, now: Date, context: String, file: StaticString = #filePath, line: UInt = #line) {
        let view = WorkoutPresenter.present(state, now: now, recovery: PresFix.demoRecovery)
        let totals = view.totals
        let allSets = state.exercises.flatMap { $0.sets }
        XCTAssertEqual(totals.totalSets, allSets.count, context, file: file, line: line)
        XCTAssertEqual(totals.loggedSets, allSets.filter { $0.isDone }.count, context, file: file, line: line)
        XCTAssertEqual(view.header.setsText, "\(totals.loggedSets) of \(totals.totalSets)", context, file: file, line: line)
        XCTAssertEqual(view.header.segments.count, state.exercises.count, context, file: file, line: line)
        XCTAssertEqual(view.header.segments.filter { $0.isCurrent }.count, state.exercises.isEmpty ? 0 : 1, context, file: file, line: line)
        XCTAssertEqual(view.isEmpty, state.exercises.isEmpty, context, file: file, line: line)
        XCTAssertEqual(view.card == nil, state.exercises.isEmpty, context, file: file, line: line)
        XCTAssertEqual(view.navigator == nil, state.exercises.isEmpty, context, file: file, line: line)
        XCTAssertEqual(view.dock != nil, state.rest != nil && !state.exercises.isEmpty, context, file: file, line: line)
        XCTAssertEqual(view.finishCheck.unloggedSets, totals.totalSets - totals.loggedSets, context, file: file, line: line)
        XCTAssertEqual(view.finishCheck.canFinish, totals.loggedSets > 0, context, file: file, line: line)
        XCTAssertGreaterThanOrEqual(totals.volumeKg, 0, context, file: file, line: line)
        for segment in view.header.segments {
            XCTAssertTrue((0...1).contains(segment.fraction), context, file: file, line: line)
        }
        if let dock = view.dock {
            XCTAssertTrue((0...1).contains(dock.fraction), context, file: file, line: line)
            XCTAssertGreaterThanOrEqual(dock.remainingSeconds, 0, context, file: file, line: line)
            XCTAssertEqual(dock.phase == .finished, dock.remainingSeconds == 0, context, file: file, line: line)
            if dock.phase == .finished { XCTAssertEqual(dock.remainingText, "Go", context, file: file, line: line) }
        }
        if let card = view.card {
            let entry = state.currentExercise!
            XCTAssertEqual(card.rows.count, entry.sets.count, context, file: file, line: line)
            let pending = entry.sets.contains { !$0.isDone }
            XCTAssertEqual(card.rows.filter { $0.isNext }.count, pending ? 1 : 0, context, file: file, line: line)
            XCTAssertEqual(card.coachTip != nil && state.rest != nil, false, context, file: file, line: line)
            for row in card.rows {
                if row.isPersonalRecord {
                    XCTAssertTrue(row.isDone, context, file: file, line: line)
                    XCTAssertNotNil(row.estimated1RM, context, file: file, line: line)
                    XCTAssertNotEqual(row.type, .warmup, context, file: file, line: line)
                } else {
                    XCTAssertNil(row.estimated1RM, context, file: file, line: line)
                }
                if row.rirText != nil { XCTAssertTrue(row.isDone, context, file: file, line: line) }
                XCTAssertFalse(row.accessibilityLabel.isEmpty, context, file: file, line: line)
            }
        }
        XCTAssertEqual(view.finishCheck.templateDiff, TemplateDiff.compute(for: state), context, file: file, line: line)
    }

    func testInvariantsHoldUnderRandomActions() {
        for seed in 1...12 {
            var rng = PresLCG(seed: UInt64(seed))
            var state = seed % 3 == 0
                ? WorkoutFactory.makeEmpty(name: "Fuzz", now: PresFix.t0)
                : WorkoutFactory.makeWorkout(from: PresFix.upperA(), now: PresFix.t0)
            var clock = 0.0
            for step in 0..<160 {
                clock += Double(rng.below(40)) / 4
                let action = randomAction(state, &rng)
                WorkoutReducer.reduce(&state, action, now: PresFix.at(clock))
                check(state, now: PresFix.at(clock + Double(rng.below(200)) / 2), context: "seed \(seed) step \(step) \(action)")
            }
        }
    }
}
