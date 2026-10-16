import Foundation
import XCTest
@testable import PulseStrengthCore

// The presentation, snapshot and history value types have explicit public initializers (code outside the module, such as UI
// fixtures and snapshot tests, cannot use an internal memberwise initializer). These tests rebuild real values field by field
// through those initializers, so a field that an initializer forgets or swaps shows up as a difference. That the initializers
// are really visible from another module was checked with a separate package that imports PulseStrengthCore normally.

final class PublicInitializerTests: XCTestCase {
    // MARK: Rebuilding

    private func rebuilt(_ segment: ActiveWorkoutPresentation.Segment) -> ActiveWorkoutPresentation.Segment {
        ActiveWorkoutPresentation.Segment(fraction: segment.fraction, isCurrent: segment.isCurrent)
    }

    private func rebuilt(_ header: ActiveWorkoutPresentation.Header) -> ActiveWorkoutPresentation.Header {
        ActiveWorkoutPresentation.Header(
            title: header.title, clockText: header.clockText, isPaused: header.isPaused, volumeText: header.volumeText,
            setsText: header.setsText, heartRateText: header.heartRateText, hasHeartRate: header.hasHeartRate,
            segments: header.segments.map(rebuilt)
        )
    }

    private func rebuilt(_ navigator: ActiveWorkoutPresentation.Navigator) -> ActiveWorkoutPresentation.Navigator {
        ActiveWorkoutPresentation.Navigator(
            position: navigator.position, total: navigator.total, canGoPrevious: navigator.canGoPrevious, canGoNext: navigator.canGoNext
        )
    }

    private func rebuilt(_ row: ActiveWorkoutPresentation.SetRow) -> ActiveWorkoutPresentation.SetRow {
        ActiveWorkoutPresentation.SetRow(
            id: row.id, number: row.number, type: row.type, previousText: row.previousText, weightText: row.weightText,
            repsText: row.repsText, weightEditable: row.weightEditable, isDone: row.isDone, isNext: row.isNext,
            isPersonalRecord: row.isPersonalRecord, estimated1RM: row.estimated1RM, rir: row.rir, rirText: row.rirText,
            accessibilityLabel: row.accessibilityLabel, prKind: row.prKind, previousSet: row.previousSet
        )
    }

    private func rebuilt(_ timed: ActiveWorkoutPresentation.TimedSetPresentation) -> ActiveWorkoutPresentation.TimedSetPresentation {
        ActiveWorkoutPresentation.TimedSetPresentation(
            exerciseID: timed.exerciseID, setID: timed.setID, setNumber: timed.setNumber, elapsedSeconds: timed.elapsedSeconds,
            targetSeconds: timed.targetSeconds, remainingSeconds: timed.remainingSeconds, isOverTarget: timed.isOverTarget,
            isPaused: timed.isPaused, elapsedText: timed.elapsedText, targetText: timed.targetText, remainingText: timed.remainingText
        )
    }

    private func rebuilt(_ card: ActiveWorkoutPresentation.Card) -> ActiveWorkoutPresentation.Card {
        ActiveWorkoutPresentation.Card(
            exerciseID: card.exerciseID, exercise: card.exercise, recoveryPercent: card.recoveryPercent,
            recoveryLevel: card.recoveryLevel, supersetLabel: card.supersetLabel, restSeconds: card.restSeconds,
            restText: card.restText, note: card.note, weightColumnTitle: card.weightColumnTitle,
            repsColumnTitle: card.repsColumnTitle, coachTip: card.coachTip, rows: card.rows.map(rebuilt)
        )
    }

    private func rebuilt(_ dock: ActiveWorkoutPresentation.Dock) -> ActiveWorkoutPresentation.Dock {
        ActiveWorkoutPresentation.Dock(
            phase: dock.phase, remainingSeconds: dock.remainingSeconds, totalSeconds: dock.totalSeconds, fraction: dock.fraction,
            remainingText: dock.remainingText, nextSetText: dock.nextSetText, showsRIR: dock.showsRIR,
            rirSelection: dock.rirSelection, isPaused: dock.isPaused
        )
    }

    private func rebuilt(_ presentation: ActiveWorkoutPresentation) -> ActiveWorkoutPresentation {
        let totals = presentation.totals
        let check = presentation.finishCheck
        return ActiveWorkoutPresentation(
            header: rebuilt(presentation.header),
            navigator: presentation.navigator.map(rebuilt),
            card: presentation.card.map(rebuilt),
            dock: presentation.dock.map(rebuilt),
            undoText: presentation.undoText,
            isEmpty: presentation.isEmpty,
            totals: ActiveWorkoutPresentation.Totals(
                loggedSets: totals.loggedSets, totalSets: totals.totalSets, volumeKg: totals.volumeKg,
                completedExercises: totals.completedExercises
            ),
            finishCheck: ActiveWorkoutPresentation.FinishCheck(
                loggedSets: check.loggedSets, unloggedSets: check.unloggedSets, canFinish: check.canFinish, title: check.title,
                message: check.message, templateDiff: check.templateDiff, diffMessage: check.diffMessage,
                asksToUpdateTemplate: check.asksToUpdateTemplate
            ),
            timedSet: presentation.timedSet.map(rebuilt)
        )
    }

    private func rebuilt(_ snapshot: WorkoutSnapshot) -> WorkoutSnapshot {
        WorkoutSnapshot(
            workoutID: snapshot.workoutID, revision: snapshot.revision, workoutName: snapshot.workoutName,
            activeStart: snapshot.activeStart, isPaused: snapshot.isPaused, elapsedWhenPaused: snapshot.elapsedWhenPaused,
            phase: snapshot.phase, exerciseName: snapshot.exerciseName, exerciseIndex: snapshot.exerciseIndex,
            exerciseCount: snapshot.exerciseCount, targetExerciseID: snapshot.targetExerciseID, targetSetID: snapshot.targetSetID,
            setLabel: snapshot.setLabel, tracking: snapshot.tracking, weightText: snapshot.weightText, repsText: snapshot.repsText,
            repsUnit: snapshot.repsUnit, showsWeight: snapshot.showsWeight, restStartedAt: snapshot.restStartedAt,
            restEndsAt: snapshot.restEndsAt, restTotalSeconds: snapshot.restTotalSeconds,
            restFrozenRemaining: snapshot.restFrozenRemaining, heartRate: snapshot.heartRate, volumeText: snapshot.volumeText,
            loggedSets: snapshot.loggedSets, totalSets: snapshot.totalSets, nextSetText: snapshot.nextSetText,
            nextExerciseName: snapshot.nextExerciseName, weightUnit: snapshot.weightUnit
        )
    }

    private func rebuilt(_ history: ExerciseHistory) -> ExerciseHistory {
        ExerciseHistory(
            exerciseID: history.exerciseID,
            sessions: history.sessions.map {
                ExerciseSession(id: $0.id, date: $0.date, workoutName: $0.workoutName, sets: $0.sets, isPersonalRecord: $0.isPersonalRecord)
            },
            e1RMSeries: history.e1RMSeries.map { E1RMPoint(date: $0.date, value: $0.value) },
            bestE1RM: history.bestE1RM,
            bestSetText: history.bestSetText,
            bestSetDate: history.bestSetDate,
            volumeLast30Days: history.volumeLast30Days,
            sessionsLast30Days: history.sessionsLast30Days,
            records: history.records.map { ExerciseRecordRow(id: $0.id, label: $0.label, value: $0.value, date: $0.date) },
            previousSets: history.previousSets.map { PreviousSet(weightKg: $0.weightKg, reps: $0.reps, type: $0.type, rir: $0.rir) }
        )
    }

    // MARK: States

    /// Workouts that exercise every optional: nothing logged, a rest running, paused, a personal record, an undo entry, empty.
    private func states() -> [WorkoutState] {
        let template = SampleData.templates()[0]
        let fresh = WorkoutFactory.makeWorkout(from: template, now: SvcSyncFix.epoch, id: SvcSyncFix.uuid(1))

        var resting = fresh
        WorkoutReducer.reduce(&resting, .logNextSet, now: SvcSyncFix.at(30))
        WorkoutReducer.reduce(&resting, .logNextSet, now: SvcSyncFix.at(100))
        WorkoutReducer.reduce(&resting, .updateHeartRate(131), now: SvcSyncFix.at(101))

        var pending = fresh
        for second in [40.0, 100, 200, 300, 400] { WorkoutReducer.reduce(&pending, .logNextSet, now: SvcSyncFix.at(second)) }
        WorkoutReducer.reduce(&pending, .toggleLastSetRIR(2), now: SvcSyncFix.at(401))
        WorkoutReducer.reduce(&pending, .skipRest, now: SvcSyncFix.at(402))
        WorkoutReducer.reduce(&pending, .setWeight(exerciseID: pending.exercises[1].id, setID: pending.exercises[1].sets[0].id, kg: 100), now: SvcSyncFix.at(403))
        WorkoutReducer.reduce(&pending, .setRIR(exerciseID: pending.exercises[0].id, setID: pending.exercises[0].sets[4].id, rir: 9), now: SvcSyncFix.at(404))

        var paused = resting
        WorkoutReducer.reduce(&paused, .pause, now: SvcSyncFix.at(120))
        WorkoutReducer.reduce(&paused, .removeExercise(exerciseID: paused.exercises[5].id), now: SvcSyncFix.at(121))

        let allLogged = {
            var state = fresh
            for second in 0..<30 { WorkoutReducer.reduce(&state, .logNextSet, now: SvcSyncFix.at(Double(second) * 60)) }
            return state
        }()
        let empty = WorkoutFactory.makeEmpty(name: "Free workout", now: SvcSyncFix.epoch, id: SvcSyncFix.uuid(2))
        var inPounds = resting
        inPounds.settings.weightUnit = .lb
        var timing = WorkoutFactory.makeEmpty(name: "Core", now: SvcSyncFix.epoch, id: SvcSyncFix.uuid(3))
        WorkoutReducer.reduce(&timing, .addExercises([ExerciseLibrary.exercise(id: "plank")!]), now: SvcSyncFix.at(1))
        WorkoutReducer.reduce(
            &timing, .startTimedSet(SetRef(exerciseID: timing.exercises[0].id, setID: timing.exercises[0].sets[0].id)), now: SvcSyncFix.at(5)
        )
        return [fresh, resting, pending, paused, allLogged, empty, inPounds, timing]
    }

    // MARK: Tests

    func testEveryPresentationRebuildsFromItsPartsThroughThePublicInitializers() {
        var sawRows = false, sawDock = false, sawTip = false, sawRIR = false, sawEmpty = false, sawRecord = false, sawTimed = false
        for state in states() {
            for offset in [0.0, 150, 1_000] {
                let presentation = WorkoutPresenter.present(state, now: SvcSyncFix.at(offset), recovery: DemoRecovery.provider)
                XCTAssertEqual(rebuilt(presentation), presentation, "\(state.name) at +\(offset) s")
                sawRows = sawRows || !(presentation.card?.rows.isEmpty ?? true)
                sawDock = sawDock || presentation.dock != nil
                sawTip = sawTip || presentation.card?.coachTip != nil
                sawRIR = sawRIR || (presentation.card?.rows.contains { $0.rirText != nil } ?? false)
                sawRecord = sawRecord || (presentation.card?.rows.contains { $0.estimated1RM != nil } ?? false)
                sawEmpty = sawEmpty || presentation.isEmpty
                sawTimed = sawTimed || presentation.timedSet != nil
            }
        }
        XCTAssertTrue(
            sawRows && sawDock && sawTip && sawRIR && sawRecord && sawEmpty && sawTimed,
            "the states cover rows, dock, coach tip, RIR, records, the empty case and a timed set"
        )
    }

    func testOptionalsDefaultToNil() {
        let header = ActiveWorkoutPresentation.Header(
            title: "T", clockText: "0:00", isPaused: false, volumeText: "0", setsText: "0 of 0", heartRateText: "–",
            hasHeartRate: false, segments: []
        )
        let totals = ActiveWorkoutPresentation.Totals(loggedSets: 0, totalSets: 0, volumeKg: 0, completedExercises: 0)
        let check = ActiveWorkoutPresentation.FinishCheck(
            loggedSets: 0, unloggedSets: 0, canFinish: false, title: "t", message: "m", templateDiff: TemplateDiff(),
            diffMessage: "d", asksToUpdateTemplate: false
        )
        let bare = ActiveWorkoutPresentation(header: header, isEmpty: true, totals: totals, finishCheck: check)
        XCTAssertNil(bare.navigator)
        XCTAssertNil(bare.card)
        XCTAssertNil(bare.dock)
        XCTAssertNil(bare.undoText)

        let row = ActiveWorkoutPresentation.SetRow(
            id: SvcSyncFix.uuid(1), number: "1", type: .normal, previousText: "–", weightText: "20", repsText: "5", weightEditable: true,
            isDone: false, isNext: true, isPersonalRecord: false, accessibilityLabel: "Set 1"
        )
        XCTAssertNil(row.estimated1RM)
        XCTAssertNil(row.rir)
        XCTAssertNil(row.rirText)

        let card = ActiveWorkoutPresentation.Card(
            exerciseID: SvcSyncFix.uuid(2), exercise: ExerciseLibrary.exercise(id: "bench")!, recoveryPercent: 80, recoveryLevel: .good,
            restSeconds: 90, restText: "1:30", note: "", weightColumnTitle: "kg", repsColumnTitle: "Reps", rows: [row]
        )
        XCTAssertNil(card.supersetLabel)
        XCTAssertNil(card.coachTip)

        let dock = ActiveWorkoutPresentation.Dock(
            phase: .running, remainingSeconds: 10, totalSeconds: 90, fraction: 0.1, remainingText: "0:10", nextSetText: "Next",
            showsRIR: false, isPaused: false
        )
        XCTAssertNil(dock.rirSelection)
    }

    func testEverySnapshotRebuildsThroughThePublicInitializer() {
        var phases = Set<SnapshotPhase>()
        for state in states() {
            for offset in [0.0, 150, 1_000] {
                let snapshot = SnapshotBuilder.make(from: state, now: SvcSyncFix.at(offset))
                XCTAssertEqual(rebuilt(snapshot), snapshot, "\(state.name) at +\(offset) s")
                phases.insert(snapshot.phase)
            }
        }
        XCTAssertEqual(phases, [.logging, .resting, .restOver, .complete])
    }

    func testOptionalSnapshotFieldsDefaultToNil() {
        let snapshot = WorkoutSnapshot(
            workoutID: SvcSyncFix.uuid(1), revision: 0, workoutName: "W", activeStart: SvcSyncFix.epoch, isPaused: false,
            elapsedWhenPaused: 0, phase: .complete, exerciseName: "", exerciseIndex: 0, exerciseCount: 0, setLabel: "",
            tracking: .weightReps, weightText: "", repsText: "", repsUnit: "reps", showsWeight: true, restTotalSeconds: 0,
            volumeText: "0", loggedSets: 0, totalSets: 0, nextSetText: ""
        )
        XCTAssertNil(snapshot.targetExerciseID)
        XCTAssertNil(snapshot.targetSetID)
        XCTAssertNil(snapshot.restStartedAt)
        XCTAssertNil(snapshot.restEndsAt)
        XCTAssertNil(snapshot.restFrozenRemaining)
        XCTAssertNil(snapshot.heartRate)
        XCTAssertNil(snapshot.nextExerciseName)
        XCTAssertEqual(snapshot.weightUnit, .kg)
    }

    func testExerciseHistoriesRebuildThroughThePublicInitializers() {
        svcMain {
            let model = StrengthDataModel(persistence: nil, seedDemoData: true, now: SvcSyncFix.epoch)
            var sawSessions = false, sawBestSet = false
            for id in ["bench", "squat", "plank", "custom-none"] {
                let history = model.history(for: id, now: SvcSyncFix.epoch)
                XCTAssertEqual(rebuilt(history), history, id)
                sawSessions = sawSessions || !history.sessions.isEmpty
                sawBestSet = sawBestSet || history.bestSetText != nil
            }
            XCTAssertTrue(sawSessions && sawBestSet)
        }
    }

    func testHistoryPartsKeepEveryField() {
        let session = ExerciseSession(
            id: SvcSyncFix.uuid(1), date: SvcSyncFix.epoch, workoutName: "Upper A",
            sets: [CompletedSet(type: .normal, weightKg: 80, reps: 5, rir: 1)], isPersonalRecord: true
        )
        XCTAssertEqual(session.id, SvcSyncFix.uuid(1))
        XCTAssertEqual(session.date, SvcSyncFix.epoch)
        XCTAssertEqual(session.workoutName, "Upper A")
        XCTAssertEqual(session.sets.count, 1)
        XCTAssertTrue(session.isPersonalRecord)

        let dated = ExerciseRecordRow(id: "best", label: "Best set", value: "80 kg × 5", date: SvcSyncFix.epoch)
        XCTAssertEqual([dated.id, dated.label, dated.value], ["best", "Best set", "80 kg × 5"])
        XCTAssertEqual(dated.date, SvcSyncFix.epoch)
        XCTAssertNil(ExerciseRecordRow(id: "x", label: "l", value: "v").date)

        let bare = ExerciseHistory(
            exerciseID: "bench", sessions: [session], e1RMSeries: [E1RMPoint(date: SvcSyncFix.epoch, value: 93)], bestE1RM: 93,
            volumeLast30Days: 400, sessionsLast30Days: 1, records: [dated]
        )
        XCTAssertNil(bare.bestSetText)
        XCTAssertNil(bare.bestSetDate)
        XCTAssertEqual(bare.sessions, [session])
        XCTAssertEqual(bare.records, [dated])
        XCTAssertEqual(bare.volumeLast30Days, 400)
        XCTAssertEqual(bare.sessionsLast30Days, 1)
    }
}
