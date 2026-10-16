import XCTest
@testable import PulseStrengthCore

/// The live context of the Live Activity (widgets/SPEC.md section 2, "Live moments"): what `SnapshotBuilder.make` derives from the
/// state (set dots, superset, plates, coach tip) and the two things the app asks for (`prMoment`, `finishBrief`).
final class LiveMomentsTests: XCTestCase {
    // MARK: Helpers

    private func snapshot(_ state: WorkoutState, at seconds: Double = 20) -> WorkoutSnapshot {
        SnapshotBuilder.make(from: state, now: PresFix.at(seconds))
    }

    /// `state` after logging the next pending set `count` times, one second apart from `start`.
    private func logging(_ state: WorkoutState, _ count: Int, from start: Double = 10) -> WorkoutState {
        var copy = state
        for step in 0..<count {
            WorkoutReducer.reduce(&copy, .logNextSet, now: PresFix.at(start + Double(step)))
        }
        return copy
    }

    /// A superset brief as one line: "A round 2/3: A1 9 × 14 done | A2 32.5 × 11 current".
    private func line(_ brief: SupersetBrief?) -> String {
        guard let brief else { return "none" }
        let rows = brief.members.map { member in
            [member.tag, member.detail, member.isDone ? "done" : "", member.isCurrent ? "current" : ""]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        }
        return "\(brief.label) round \(brief.round)/\(brief.rounds): " + rows.joined(separator: " | ")
    }

    /// Dumbbell raise + pushdown in superset "A", three sets each, no rest between the members.
    private func pair() -> WorkoutState {
        let lateral = PresFix.entry(
            1, PresFix.lib("lateral"), [(.normal, 8, 15), (.normal, 9, 14), (.normal, 10, 13)], rest: 60, group: "A"
        )
        let pushdown = PresFix.entry(
            2, PresFix.lib("pushdown"), [(.normal, 30, 12), (.normal, 32.5, 11), (.normal, 35, 10)], rest: 60, group: "A"
        )
        return PresFix.workout([lateral, pushdown])
    }

    /// The bench press with `sets`, a previous best of `best` (0 = no history).
    private func bench(best: Double, _ sets: [PresFix.SetSpec]) -> WorkoutState {
        PresFix.single(PresFix.lib("bench", best: best), sets)
    }

    // MARK: Set dots

    func testTheBuilderNeverSetsTheMomentOrTheFinishCard() {
        for state in [PresFix.freshUpperA(), PresFix.goldenState(), PresFix.loggedEverything(PresFix.freshUpperA()), PresFix.workout([])] {
            let snap = snapshot(state, at: 1458)
            XCTAssertNil(snap.moment)
            XCTAssertNil(snap.finish)
        }
    }

    func testSetDotsCountTheSetsOfTheShownExercise() {
        let fresh = snapshot(PresFix.freshUpperA())
        XCTAssertEqual(fresh.exerciseDoneSets, 0)
        XCTAssertEqual(fresh.exerciseSetCount, 5)

        // The design's opening state: two warm-ups and the first working set of the bench are logged.
        let golden = snapshot(PresFix.goldenState(), at: 1458)
        XCTAssertEqual(golden.exerciseDoneSets, 3)
        XCTAssertEqual(golden.exerciseSetCount, 5)
    }

    func testSetDotsFollowTheTargetToTheNextExercise() {
        // The bench has five sets; once they are logged the incline press (three sets) is next.
        let state = logging(PresFix.freshUpperA(), 5)
        let snap = snapshot(state)
        XCTAssertEqual(snap.exerciseName, state.exercises[1].exercise.name)
        XCTAssertEqual(snap.exerciseDoneSets, 0)
        XCTAssertEqual(snap.exerciseSetCount, 3)
    }

    func testSetDotsOfAFinishedWorkoutAreFull() {
        let state = PresFix.loggedEverything(PresFix.freshUpperA())
        let snap = snapshot(state)
        let shown = state.exercises[state.clampedIndex]
        XCTAssertEqual(snap.phase, .complete)
        XCTAssertEqual(snap.exerciseDoneSets, shown.sets.count)
        XCTAssertEqual(snap.exerciseSetCount, shown.sets.count)
    }

    func testAWorkoutWithoutExercisesHasNoLiveContext() {
        let snap = snapshot(PresFix.workout([]))
        XCTAssertNil(snap.exerciseDoneSets)
        XCTAssertNil(snap.exerciseSetCount)
        XCTAssertNil(snap.superset)
        XCTAssertNil(snap.plates)
        XCTAssertNil(snap.coachTip)
    }

    // MARK: Superset

    func testSupersetFollowsTheRoundsOfAPair() throws {
        let state = pair()
        let lateral = state.exercises[0].exercise.name
        let pushdown = state.exercises[1].exercise.name

        let start = try XCTUnwrap(snapshot(state).superset)
        XCTAssertEqual(start.members.map(\.name), [lateral, pushdown])
        XCTAssertEqual(start.members.map(\.tag), ["A1", "A2"])
        XCTAssertEqual(line(start), "A round 1/3: A1 8 × 15 current | A2 30 × 12")

        // The first member is logged: the second is next, in the same round; nothing rests between the members.
        let afterFirst = snapshot(logging(state, 1))
        XCTAssertEqual(afterFirst.phase, .logging)
        XCTAssertEqual(afterFirst.exerciseName, pushdown)
        XCTAssertEqual(line(afterFirst.superset), "A round 1/3: A1 9 × 14 done | A2 30 × 12 current")

        // The round is complete: rest, then the first member again in round 2.
        let afterRound = snapshot(logging(state, 2))
        XCTAssertEqual(afterRound.phase, .resting)
        XCTAssertEqual(afterRound.exerciseName, lateral)
        XCTAssertEqual(line(afterRound.superset), "A round 2/3: A1 9 × 14 current | A2 32.5 × 11")
    }

    func testTheRoundDoesNotMoveOnWhileTheSecondMemberIsStillDue() {
        // The first member has two sets logged and the second one: the pair is in round 2 (counting the first member's sets alone
        // would say round 3 here).
        let state = pair()
        XCTAssertEqual(line(snapshot(logging(state, 3)).superset), "A round 2/3: A1 10 × 13 done | A2 32.5 × 11 current")
        XCTAssertEqual(line(snapshot(logging(state, 4)).superset), "A round 3/3: A1 10 × 13 current | A2 35 × 10")
        XCTAssertEqual(line(snapshot(logging(state, 5)).superset), "A round 3/3: A1 10 × 13 done | A2 35 × 10 current")
    }

    func testAFinishedSupersetStaysOnTheLastRound() {
        let snap = snapshot(logging(pair(), 6))
        XCTAssertEqual(snap.phase, .complete)
        XCTAssertEqual(line(snap.superset), "A round 3/3: A1 10 × 13 done current | A2 35 × 10 done")
    }

    func testSupersetOfThreeExercisesIsTaggedByPosition() throws {
        let entries = [
            PresFix.entry(1, PresFix.lib("lateral"), PresFix.normal(2, 8, 15), group: "B"),
            PresFix.entry(2, PresFix.lib("pushdown"), PresFix.normal(2, 30, 12), group: "B"),
            PresFix.entry(3, PresFix.lib("crossover"), PresFix.normal(2, 15, 12), group: "B"),
        ]
        let state = PresFix.workout(entries)
        XCTAssertEqual(line(snapshot(state).superset), "B round 1/2: B1 8 × 15 current | B2 30 × 12 | B3 15 × 12")
        XCTAssertEqual(
            line(snapshot(logging(state, 2)).superset),
            "B round 1/2: B1 8 × 15 done | B2 30 × 12 done | B3 15 × 12 current"
        )
        XCTAssertEqual(
            line(snapshot(logging(state, 3)).superset),
            "B round 2/2: B1 8 × 15 current | B2 30 × 12 | B3 15 × 12"
        )
    }

    func testSupersetDetailOfRepsAndDurationExercises() {
        let entries = [
            PresFix.entry(1, PresFix.lib("pushup"), [(.normal, 0, 12)], group: "C"),
            PresFix.entry(2, PresFix.lib("plank"), [(.normal, 0, 45)], group: "C"),
        ]
        // No weight to put in front of the body weight ("BW × 12") and none for the plank, which shows its seconds.
        XCTAssertEqual(line(snapshot(PresFix.workout(entries)).superset), "C round 1/1: C1 BW × 12 current | C2 45 s")
    }

    func testSupersetUsesTheSetCountOfTheFirstMemberAsRounds() {
        let entries = [
            PresFix.entry(1, PresFix.lib("lateral"), PresFix.normal(2, 8, 15), group: "A"),
            PresFix.entry(2, PresFix.lib("pushdown"), PresFix.normal(4, 30, 12), group: "A"),
        ]
        let state = PresFix.workout(entries)
        // Both members have logged two sets: the round stays at the cap while the second member still has sets left.
        XCTAssertEqual(
            line(snapshot(logging(state, 4)).superset),
            "A round 2/2: A1 8 × 15 done | A2 30 × 12 done current"
        )
    }

    func testSupersetMemberWithoutSetsHasNothingToDo() {
        let entries = [
            PresFix.entry(1, PresFix.lib("lateral"), PresFix.normal(3, 8, 15), group: "A"),
            PresFix.entry(2, PresFix.lib("pushdown"), [], group: "A"),
        ]
        XCTAssertEqual(line(snapshot(PresFix.workout(entries)).superset), "A round 1/3: A1 8 × 15 current | A2 done")
    }

    func testSupersetShowsAMemberLoggedOutOfOrder() {
        let state = pair()
        let second = state.exercises[1]
        let reduced = PresFix.reduced(state, .logSet(exerciseID: second.id, setID: second.sets[0].id), at: 10)
        XCTAssertEqual(line(snapshot(reduced).superset), "A round 1/3: A1 8 × 15 current | A2 32.5 × 11 done")
    }

    func testNoSupersetForOtherExercisesOrALoneGroup() {
        // The shown exercise (the bench) is not in a group, although the workout holds a superset.
        XCTAssertNil(snapshot(PresFix.freshUpperA()).superset)

        // Once the lateral raise is the shown exercise the superset of the template appears.
        var upper = PresFix.freshUpperA()
        upper.currentIndex = 3
        XCTAssertEqual(line(snapshot(upper).superset), "A round 1/3: A1 8 × 15 current | A2 30 × 12")

        // A group of one is no superset, and neither is an empty group name.
        let lone = PresFix.workout([PresFix.entry(1, PresFix.lib("lateral"), PresFix.normal(3, 8, 15), group: "A")])
        XCTAssertNil(snapshot(lone).superset)
        let unnamed = PresFix.workout([
            PresFix.entry(1, PresFix.lib("lateral"), PresFix.normal(3, 8, 15), group: ""),
            PresFix.entry(2, PresFix.lib("pushdown"), PresFix.normal(3, 30, 12), group: ""),
        ])
        XCTAssertNil(snapshot(unnamed).superset)
    }

    // MARK: Plates

    func testPlatesOfABarbellSet() {
        let snap = snapshot(bench(best: 0, [(.normal, 82.5, 6)]))
        XCTAssertEqual(snap.plates, PlateBrief(totalKg: 82.5, barKg: 20, perSide: [25, 5, 1.25], leftoverKg: 0, summary: "25 + 5 + 1.25"))
    }

    func testPlatesAlsoCoverWarmUpsAndTheRestingPhase() {
        // The first set of the upper workout is a 50 kg warm-up: one 15 kg plate per side.
        XCTAssertEqual(
            snapshot(PresFix.freshUpperA()).plates,
            PlateBrief(totalKg: 50, barKg: 20, perSide: [15], leftoverKg: 0, summary: "15")
        )
        // While resting the target is the next working set of the bench, 82.5 kg.
        let resting = snapshot(PresFix.goldenState(), at: 1458)
        XCTAssertEqual(resting.phase, .resting)
        XCTAssertEqual(resting.plates?.summary, "25 + 5 + 1.25")
        XCTAssertEqual(resting.plates?.totalKg, 82.5)
    }

    func testPlatesUseTheBarOfTheExercise() {
        var squat = PresFix.lib("squat")
        squat.barKg = 15
        let snap = snapshot(PresFix.single(squat, [(.normal, 100, 5)]))
        XCTAssertEqual(snap.plates, PlateBrief(totalKg: 100, barKg: 15, perSide: [25, 15, 2.5], leftoverKg: 0, summary: "25 + 15 + 2.5"))
    }

    func testPlatesReportWhatCannotBeLoaded() {
        let snap = snapshot(bench(best: 0, [(.normal, 23.7, 5)]))
        XCTAssertEqual(snap.plates, PlateBrief(totalKg: 23.7, barKg: 20, perSide: [1.25], leftoverKg: 0.6, summary: "1.25"))
    }

    func testNoPlatesWhenNothingIsLoadedOnTheBar() {
        // The empty bar, below the bar, a weight smaller than the smallest plate on each side, and no weight at all.
        for kilograms in [20.0, 15.0, 21.0, 0.0] {
            XCTAssertNil(snapshot(bench(best: 0, [(.normal, kilograms, 5)])).plates, "\(kilograms) kg")
        }
    }

    func testNoPlatesForOtherEquipmentOrTracking() {
        let cases: [(String, PresFix.SetSpec)] = [
            ("incline", (.normal, 28, 10)),
            ("crossover", (.normal, 15, 12)),
            ("legpress", (.normal, 100, 10)),
            ("pushup", (.normal, 0, 12)),
            ("plank", (.normal, 0, 45)),
        ]
        for (id, spec) in cases {
            XCTAssertNil(snapshot(PresFix.single(PresFix.lib(id), [spec])).plates, id)
        }
    }

    func testNoPlatesWhenEverySetIsLogged() {
        let snap = snapshot(logging(bench(best: 0, [(.normal, 82.5, 6)]), 1))
        XCTAssertEqual(snap.phase, .complete)
        XCTAssertNil(snap.plates)
    }

    func testDamagedWeightsGivePlatesNothingToShow() {
        for kilograms in [Double.nan, .infinity, -5, 1e15] {
            XCTAssertNil(snapshot(bench(best: 0, [(.normal, kilograms, 5)])).plates, "\(kilograms) kg")
        }
    }

    // MARK: Coach tip

    private func openingState(rir: Int?) -> WorkoutState {
        var state = PresFix.goldenState()
        let ref = state.lastLogged
        if let ref, let k = state.exercises.firstIndex(where: { $0.id == ref.exerciseID }),
           let i = state.exercises[k].sets.firstIndex(where: { $0.id == ref.setID }) {
            state.exercises[k].sets[i].rir = rir
        }
        return state
    }

    func testCoachTipAfterAnEasySet() {
        // Warm-ups and the first 82.5 kg set (RIR 3) are logged and the rest runs: the next working set is 82.5 kg.
        let state = PresFix.goldenState()
        let snap = snapshot(state, at: 1458)
        XCTAssertEqual(snap.phase, .resting)
        XCTAssertEqual(
            snap.coachTip,
            CoachTipBrief(
                title: "Felt easy?",
                subtitle: "3 reps in reserve on set 3",
                text: "Try 85 kg on set 4.",
                suggestedWeightKg: 85,
                suggestedWeightText: "85 kg",
                keepWeightText: "Keep 82.5",
                targetSetID: state.exercises[0].sets[3].id,
                targetExerciseID: state.exercises[0].id
            )
        )
    }

    func testCoachTipNeedsThreeRepsInReserve() {
        XCTAssertNil(snapshot(openingState(rir: nil), at: 1458).coachTip)
        XCTAssertNil(snapshot(openingState(rir: 0), at: 1458).coachTip)
        XCTAssertNil(snapshot(openingState(rir: 2), at: 1458).coachTip)
        XCTAssertEqual(snapshot(openingState(rir: 3), at: 1458).coachTip?.subtitle, "3 reps in reserve on set 3")
        // 4 stands for "4 or more".
        XCTAssertEqual(snapshot(openingState(rir: 4), at: 1458).coachTip?.subtitle, "4+ reps in reserve on set 3")
    }

    func testCoachTipOnlyWhileResting() {
        let state = PresFix.goldenState()
        XCTAssertNotNil(snapshot(state, at: 1458).coachTip)
        // The rest is over (it ended at 1553), skipped, or switched off.
        XCTAssertEqual(snapshot(state, at: 1600).phase, .restOver)
        XCTAssertNil(snapshot(state, at: 1600).coachTip)
        XCTAssertNil(snapshot(PresFix.reduced(state, .skipRest, at: 1410), at: 1458).coachTip)
        // A paused workout keeps its frozen rest, and with it the tip.
        let paused = PresFix.reduced(state, .pause, at: 1423)
        XCTAssertEqual(snapshot(paused, at: 3000).phase, .resting)
        XCTAssertNotNil(snapshot(paused, at: 3000).coachTip)
    }

    func testCoachTipIgnoresWarmUpsAndPendingWarmUps() {
        // A warm-up with RIR 3 is no reason to add weight.
        var state = PresFix.reduced(PresFix.freshUpperA(), .logNextSet, at: 10)
        state = PresFix.reduced(state, .toggleLastSetRIR(3), at: 11)
        XCTAssertEqual(snapshot(state, at: 12).phase, .resting)
        XCTAssertNil(snapshot(state, at: 12).coachTip)

        // The suggestion is for the next working set, whatever warm-up lies in between.
        let mixed = PresFix.single(PresFix.lib("bench"), [(.normal, 80, 5), (.warmup, 40, 5), (.normal, 82.5, 5)])
        var played = PresFix.reduced(mixed, .logNextSet, at: 10)
        played = PresFix.reduced(played, .toggleLastSetRIR(3), at: 11)
        XCTAssertEqual(snapshot(played, at: 12).coachTip?.text, "Try 85 kg on set 3.")
        XCTAssertEqual(snapshot(played, at: 12).coachTip?.keepWeightText, "Keep 82.5")

        // Only a warm-up is left: nothing to suggest.
        let onlyWarmUp = PresFix.single(PresFix.lib("bench"), [(.normal, 80, 5), (.warmup, 40, 5)])
        var last = PresFix.reduced(onlyWarmUp, .logNextSet, at: 10)
        last = PresFix.reduced(last, .toggleLastSetRIR(3), at: 11)
        XCTAssertNil(snapshot(last, at: 12).coachTip)
    }

    func testCoachTipNeedsAPendingSetOfTheSameExercise() {
        let single = PresFix.single(PresFix.lib("bench"), [(.normal, 80, 5), (.normal, 80, 5)])
        var played = logging(single, 2)
        played = PresFix.reduced(played, .toggleLastSetRIR(3), at: 12)
        XCTAssertEqual(snapshot(played, at: 13).phase, .complete)
        XCTAssertNil(snapshot(played, at: 13).coachTip)

        // The next set has no weight yet: no sensible suggestion.
        let unweighted = PresFix.single(PresFix.lib("bench"), [(.normal, 80, 5), (.normal, 0, 5)])
        var afterOne = PresFix.reduced(unweighted, .logNextSet, at: 10)
        afterOne = PresFix.reduced(afterOne, .toggleLastSetRIR(3), at: 11)
        XCTAssertNil(snapshot(afterOne, at: 12).coachTip)
    }

    func testCoachTipOnlyForWeightExercises() {
        for id in ["pushup", "plank"] {
            let exercise = PresFix.lib(id)
            let spec: PresFix.SetSpec = (.normal, 0, exercise.tracking == .duration ? 45 : 12)
            var state = PresFix.reduced(PresFix.single(exercise, [spec, spec]), .logNextSet, at: 10)
            state = PresFix.reduced(state, .toggleLastSetRIR(4), at: 11)
            XCTAssertEqual(snapshot(state, at: 12).phase, .resting, id)
            XCTAssertNil(snapshot(state, at: 12).coachTip, id)
        }
    }

    func testCoachTipStepFollowsTheEquipment() {
        // Dumbbells go up by 2 kg, cables by 2.5 kg.
        for (id, kilograms, expected) in [("incline", 28.0, "30 kg"), ("crossover", 15.0, "17.5 kg")] {
            var state = PresFix.reduced(PresFix.single(PresFix.lib(id), [(.normal, kilograms, 10), (.normal, kilograms, 10)]), .logNextSet, at: 10)
            state = PresFix.reduced(state, .toggleLastSetRIR(3), at: 11)
            XCTAssertEqual(snapshot(state, at: 12).coachTip?.suggestedWeightText, expected, id)
        }
        // The sum is rounded to 0.01 kg.
        var state = PresFix.reduced(bench(best: 0, [(.normal, 20.1, 5), (.normal, 20.1, 5)]), .logNextSet, at: 10)
        state = PresFix.reduced(state, .toggleLastSetRIR(3), at: 11)
        XCTAssertEqual(snapshot(state, at: 12).coachTip?.suggestedWeightKg, 22.6)
    }

    func testCoachTipIsDroppedWhenTheLoggedSetIsUndoneOrGone() {
        let state = PresFix.goldenState()
        let ref = state.lastLogged
        let undone = PresFix.reduced(state, .toggleSet(exerciseID: ref?.exerciseID ?? UUID(), setID: ref?.setID ?? UUID()), at: 1405)
        XCTAssertNil(snapshot(undone, at: 1458).coachTip)

        var stale = state
        stale.lastLogged = SetRef(exerciseID: UUID(), setID: UUID())
        XCTAssertNil(snapshot(stale, at: 1458).coachTip)
        stale.lastLogged = nil
        XCTAssertNil(snapshot(stale, at: 1458).coachTip)
    }

    func testCoachTipOfASupersetNamesTheMemberJustLogged() throws {
        // Logging the second member starts the rest; the Log button then targets the first member again, but the suggestion is for
        // the second member's own next set.
        var state = logging(pair(), 2)
        state = PresFix.reduced(state, .toggleLastSetRIR(3), at: 12)
        let snap = snapshot(state, at: 13)
        let pushdown = state.exercises[1]
        let tip = try XCTUnwrap(snap.coachTip)
        XCTAssertEqual(snap.targetExerciseID, state.exercises[0].id)
        XCTAssertEqual(tip.targetExerciseID, pushdown.id)
        XCTAssertEqual(tip.targetSetID, pushdown.sets[1].id)
        XCTAssertEqual(tip.text, "Try 35 kg on set 2.")
        XCTAssertEqual(tip.keepWeightText, "Keep 32.5")
        XCTAssertEqual(tip.subtitle, "3 reps in reserve on set 1")
    }

    // MARK: Record moment

    private let now = PresFix.at(100)

    /// 85 kg x 5 beats a previous best of 90 (estimate 99.17), 90 kg x 5 makes 105, 87.5 kg x 5 makes 102.08.
    private var records: WorkoutState { bench(best: 90, [(.normal, 85, 5), (.normal, 90, 5), (.normal, 87.5, 5)]) }

    func testRecordMomentForTheSetThatBeatsTheBest() throws {
        let before = records
        let after = logging(before, 1)
        let moment = try XCTUnwrap(SnapshotBuilder.prMoment(from: before, to: after, now: now))
        XCTAssertEqual(
            moment,
            PRMoment(
                exerciseName: "Barbell bench press",
                weightText: "85",
                repsText: "5",
                estimated1RM: 99,
                deltaKg: 9,
                expiresAt: now.addingTimeInterval(4)
            )
        )
    }

    func testASecondRecordReportsItsGainOverTheFirst() throws {
        let first = logging(records, 1)
        let second = logging(records, 2)
        let moment = try XCTUnwrap(SnapshotBuilder.prMoment(from: first, to: second, now: now))
        XCTAssertEqual(moment.weightText, "90")
        XCTAssertEqual(moment.estimated1RM, 105)
        XCTAssertEqual(moment.deltaKg, 6)
        // The third set (102.08) is no record.
        XCTAssertNil(SnapshotBuilder.prMoment(from: second, to: logging(records, 3), now: now))
    }

    func testNoRecordMomentWithoutAPreviousBest() {
        let before = bench(best: 0, [(.normal, 85, 5)])
        XCTAssertNil(SnapshotBuilder.prMoment(from: before, to: logging(before, 1), now: now))
    }

    func testRecordMomentNeedsMoreThanTheMargin() throws {
        // 85 kg x 5 is worth 99.1667: a best of 99.12 is not beaten by more than 0.05, a best of 99.11 is.
        let close = bench(best: 99.12, [(.normal, 85, 5)])
        XCTAssertNil(SnapshotBuilder.prMoment(from: close, to: logging(close, 1), now: now))
        let beaten = bench(best: 99.11, [(.normal, 85, 5)])
        let moment = try XCTUnwrap(SnapshotBuilder.prMoment(from: beaten, to: logging(beaten, 1), now: now))
        // Both estimates read 99 kg; a record never reads "+0 kg".
        XCTAssertEqual(moment.estimated1RM, 99)
        XCTAssertEqual(moment.deltaKg, 1)
    }

    func testWarmUpsAndNonWeightExercisesAreNeverRecords() {
        let warmUp = bench(best: 90, [(.warmup, 200, 5)])
        XCTAssertNil(SnapshotBuilder.prMoment(from: warmUp, to: logging(warmUp, 1), now: now))

        let pushUps = PresFix.single(PresFix.lib("pushup", best: 50), [(.normal, 0, 30)])
        XCTAssertNil(SnapshotBuilder.prMoment(from: pushUps, to: logging(pushUps, 1), now: now))
    }

    func testRecordMomentOnlyForTheChangeThatLoggedIt() throws {
        let before = records
        let after = logging(before, 1)
        // Nothing changed, or something else did: the record was already there.
        XCTAssertNil(SnapshotBuilder.prMoment(from: after, to: after, now: now))
        XCTAssertNil(SnapshotBuilder.prMoment(from: before, to: before, now: now))
        XCTAssertNil(SnapshotBuilder.prMoment(from: after, to: PresFix.reduced(after, .updateHeartRate(150), at: 20), now: now))
        XCTAssertNil(SnapshotBuilder.prMoment(from: after, to: PresFix.reduced(after, .pause, at: 20), now: now))
        // Going back (the record is undone) is no record either, but logging it again is.
        let set = after.exercises[0].sets[0]
        let undone = PresFix.reduced(after, .toggleSet(exerciseID: after.exercises[0].id, setID: set.id), at: 20)
        XCTAssertNil(SnapshotBuilder.prMoment(from: after, to: undone, now: now))
        XCTAssertNotNil(SnapshotBuilder.prMoment(from: undone, to: after, now: now))
    }

    func testEditingALoggedSetIntoARecordIsAMoment() throws {
        // 80 kg x 5 (93.3) is below a best of 95; raising the logged set to 85 kg makes it a record.
        let before = logging(bench(best: 95, [(.normal, 80, 5)]), 1)
        XCTAssertNil(SnapshotBuilder.prMoment(from: before, to: before, now: now))
        let entry = before.exercises[0]
        let edited = PresFix.reduced(before, .setWeight(exerciseID: entry.id, setID: entry.sets[0].id, kg: 85), at: 20)
        let moment = try XCTUnwrap(SnapshotBuilder.prMoment(from: before, to: edited, now: now))
        XCTAssertEqual(moment.weightText, "85")
    }

    func testTheBestOfSeveralNewRecordsIsReported() throws {
        // All three sets become logged at once: the 90 kg x 5 set has the highest estimate, measured against the running best.
        let before = records
        let after = PresFix.marking(before, exercise: 0, done: [0, 1, 2])
        let moment = try XCTUnwrap(SnapshotBuilder.prMoment(from: before, to: after, now: now))
        XCTAssertEqual(moment.weightText, "90")
        XCTAssertEqual(moment.estimated1RM, 105)
        XCTAssertEqual(moment.deltaKg, 6)
    }

    func testRecordMomentNamesTheExerciseThatGotTheRecord() throws {
        let entries = [
            PresFix.entry(1, PresFix.lib("bench", best: 90), [(.normal, 85, 5)]),
            PresFix.entry(2, PresFix.lib("squat", best: 150), [(.normal, 140, 5)]),
        ]
        let start = PresFix.workout(entries)
        let afterBench = logging(start, 1)
        let afterSquat = logging(start, 2)
        XCTAssertEqual(try XCTUnwrap(SnapshotBuilder.prMoment(from: start, to: afterBench, now: now)).exerciseName, "Barbell bench press")
        let squat = try XCTUnwrap(SnapshotBuilder.prMoment(from: afterBench, to: afterSquat, now: now))
        XCTAssertEqual(squat.exerciseName, "Back squat")
        XCTAssertEqual(squat.weightText, "140")
        XCTAssertEqual(squat.estimated1RM, 163)
        XCTAssertEqual(squat.deltaKg, 13)
    }

    func testRecordMomentOfAnotherWorkoutIsNotShown() {
        let before = records
        var other = logging(before, 1)
        other.id = UUID()
        XCTAssertNil(SnapshotBuilder.prMoment(from: before, to: other, now: now))
    }

    func testRecordMomentLifetime() throws {
        let before = records
        let after = logging(before, 1)
        func expiry(_ lifetime: TimeInterval) throws -> Date {
            try XCTUnwrap(SnapshotBuilder.prMoment(from: before, to: after, now: now, lifetime: lifetime)).expiresAt
        }
        XCTAssertEqual(try XCTUnwrap(SnapshotBuilder.prMoment(from: before, to: after, now: now)).expiresAt, now.addingTimeInterval(4))
        XCTAssertEqual(try expiry(10), now.addingTimeInterval(10))
        XCTAssertEqual(try expiry(0), now)
        XCTAssertEqual(try expiry(-3), now)
        XCTAssertEqual(try expiry(.nan), now.addingTimeInterval(SnapshotBuilder.defaultMomentLifetime))
        XCTAssertEqual(try expiry(.infinity), now.addingTimeInterval(SnapshotBuilder.defaultMomentLifetime))
    }

    // MARK: Finish card

    private func finished(
        seconds: Int = 2_730, volume: Double = 9_120, sets: Int = 21, records: Int = 2, name: String = "Upper A · Push"
    ) -> CompletedWorkout {
        let marks = (0..<records).map {
            PersonalRecord(exerciseID: "bench\($0)", exerciseName: "Bench", weightKg: 85, reps: 5, estimated1RM: 99, previousBest: 95)
        }
        var workout = WidFix.workout(1, name, at: WidFix.now, durationSeconds: seconds, volumeKg: volume, records: marks)
        workout.loggedSets = sets
        return workout
    }

    func testFinishBriefCarriesTheNumbersOfTheWorkout() {
        XCTAssertEqual(
            SnapshotBuilder.finishBrief(from: finished(), savedToHealth: true),
            FinishBrief(workoutName: "Upper A · Push", durationMinutes: 46, sets: 21, volumeText: "9.1", personalRecordCount: 2, savedToHealth: true)
        )
        XCTAssertFalse(SnapshotBuilder.finishBrief(from: finished(), savedToHealth: false).savedToHealth)
    }

    func testFinishBriefRoundsTheDurationToMinutes() {
        let table: [(Int, Int)] = [(0, 0), (29, 0), (30, 1), (89, 1), (90, 2), (2_729, 45), (2_730, 46), (-5, 0)]
        for (seconds, minutes) in table {
            XCTAssertEqual(SnapshotBuilder.finishBrief(from: finished(seconds: seconds), savedToHealth: false).durationMinutes, minutes, "\(seconds) s")
        }
        XCTAssertGreaterThan(SnapshotBuilder.finishBrief(from: finished(seconds: Int.max), savedToHealth: false).durationMinutes, 0)
    }

    func testFinishBriefShowsTheVolumeInTonnes() {
        let table: [(Double, String)] = [
            (9_120, "9.1"), (9_000, "9"), (9_049, "9"), (9_050, "9.1"), (49, "0"), (50, "0.1"), (0, "0"), (123_456, "123.5"),
            (-100, "0"), (.nan, "0"), (.infinity, "0"),
        ]
        for (kilograms, text) in table {
            XCTAssertEqual(SnapshotBuilder.finishBrief(from: finished(volume: kilograms), savedToHealth: false).volumeText, text, "\(kilograms) kg")
        }
    }

    func testFinishBriefCountsSetsAndRecords() {
        let brief = SnapshotBuilder.finishBrief(from: finished(sets: 0, records: 0), savedToHealth: false)
        XCTAssertEqual(brief.sets, 0)
        XCTAssertEqual(brief.personalRecordCount, 0)
        XCTAssertEqual(SnapshotBuilder.finishBrief(from: finished(sets: -4, records: 3), savedToHealth: false).sets, 0)
        XCTAssertEqual(SnapshotBuilder.finishBrief(from: finished(records: 3), savedToHealth: false).personalRecordCount, 3)
    }

    func testFinishBriefOfARealSummary() throws {
        // The summary of a workout played through the reducer: the numbers of the brief are those of the saved workout.
        let state = PresFix.loggedEverything(PresFix.freshUpperA(), start: 10)
        let completed = SummaryBuilder.build(from: state, finishedAt: PresFix.at(3_000))
        let brief = SnapshotBuilder.finishBrief(from: completed, savedToHealth: true)
        XCTAssertEqual(brief.workoutName, state.name)
        XCTAssertEqual(brief.sets, completed.loggedSets)
        XCTAssertEqual(brief.durationMinutes, (completed.durationSeconds + 30) / 60)
        XCTAssertEqual(brief.personalRecordCount, completed.personalRecords.count)
    }

    // MARK: Size

    /// A giant set of four exercises with names of 60 scalars everywhere, resting, with plates, a coach tip, a record, a heart
    /// rate and the finish card all present: the Live Activity limit is 4 KB, the budget 3,500 bytes.
    func testTheLargestRealisticSnapshotStaysUnderTheSizeBudget() throws {
        for (label, letter) in [("one-byte letters", "N"), ("two-byte letters", "ö")] {
            let name = String(repeating: letter, count: 60)
            XCTAssertEqual(name.unicodeScalars.count, 60)
            func named(_ id: String) -> Exercise {
                var exercise = PresFix.lib(id, best: 90)
                exercise.name = name
                return exercise
            }
            let entries = [
                PresFix.entry(1, named("bench"), PresFix.normal(4, 197.5, 8), rest: 90, group: "A"),
                PresFix.entry(2, named("lateral"), PresFix.normal(4, 20, 12), rest: 90, group: "A"),
                PresFix.entry(3, named("pushdown"), PresFix.normal(4, 40, 12), rest: 90, group: "A"),
                PresFix.entry(4, named("crossover"), PresFix.normal(4, 25, 12), rest: 90, group: "A"),
            ]
            let start = PresFix.workout(entries, name: name)
            let afterFirst = logging(start, 1)
            var state = logging(start, 4)
            state = PresFix.reduced(state, .toggleLastSetRIR(3), at: 20)
            state.heartRate = 187

            var snap = snapshot(state, at: 21)
            snap.moment = SnapshotBuilder.prMoment(from: start, to: afterFirst, now: PresFix.at(21))
            snap.finish = SnapshotBuilder.finishBrief(
                from: finished(seconds: 5_999, volume: 123_456, sets: 99, records: 9, name: name), savedToHealth: true
            )

            XCTAssertEqual(snap.phase, .resting, label)
            XCTAssertEqual(snap.superset?.members.count, 4, label)
            XCTAssertNotNil(snap.plates, label)
            XCTAssertNotNil(snap.coachTip, label)
            XCTAssertNotNil(snap.moment, label)
            XCTAssertNotNil(snap.finish, label)
            XCTAssertNotNil(snap.exerciseDoneSets, label)

            let bytes = try StrengthJSON.makeEncoder().encode(snap).count
            XCTAssertLessThan(bytes, 3_500, "\(label): \(bytes) bytes")
            let decoded = try StrengthJSON.makeDecoder().decode(WorkoutSnapshot.self, from: StrengthJSON.makeEncoder().encode(snap))
            XCTAssertEqual(decoded, snap, label)
        }
    }

    // MARK: Fuzz

    /// The relations between the live context and the state, whatever happened to the workout.
    private func checkLiveContext(_ snap: WorkoutSnapshot, _ state: WorkoutState, _ context: String) throws {
        XCTAssertNil(snap.moment, context)
        XCTAssertNil(snap.finish, context)
        XCTAssertLessThan(try StrengthJSON.makeEncoder().encode(snap).count, 3_500, context)
        guard !state.exercises.isEmpty else {
            XCTAssertNil(snap.exerciseDoneSets, context)
            XCTAssertNil(snap.exerciseSetCount, context)
            XCTAssertNil(snap.superset, context)
            XCTAssertNil(snap.plates, context)
            XCTAssertNil(snap.coachTip, context)
            return
        }
        let target = WorkoutTargets.nextPending(in: state)
        let shown = state.exercises[target?.exerciseIndex ?? state.clampedIndex]
        XCTAssertEqual(snap.exerciseSetCount, shown.sets.count, context)
        XCTAssertEqual(snap.exerciseDoneSets, shown.doneCount, context)

        let members = shown.supersetGroup.flatMap { group in
            group.isEmpty ? nil : state.exercises.filter { $0.supersetGroup == group }
        } ?? []
        if let group = shown.supersetGroup, members.count >= 2 {
            if let brief = snap.superset {
                XCTAssertEqual(brief.label, group, context)
                XCTAssertEqual(brief.members.map(\.name), members.map { $0.exercise.name }, context)
                XCTAssertEqual(brief.members.map(\.tag), (1...members.count).map { group + String($0) }, context)
                XCTAssertGreaterThanOrEqual(brief.rounds, 1, context)
                XCTAssertTrue((1...max(1, brief.rounds)).contains(brief.round), context)
                XCTAssertEqual(brief.members.filter(\.isCurrent).count, 1, context)
                XCTAssertEqual(brief.members.first(where: \.isCurrent)?.name, shown.exercise.name, context)
            } else {
                XCTFail("missing superset: " + context)
            }
        } else {
            XCTAssertNil(snap.superset, context)
        }

        if let plates = snap.plates {
            guard let target else { return XCTFail("plates without a target: " + context) }
            let entry = state.exercises[target.exerciseIndex]
            XCTAssertTrue(entry.exercise.supportsPlates, context)
            XCTAssertEqual(plates.totalKg, entry.sets[target.setIndex].weightKg, context)
            XCTAssertFalse(plates.perSide.isEmpty, context)
            XCTAssertEqual(plates.perSide, plates.perSide.sorted(by: >), context)
            XCTAssertEqual(plates.barKg + 2 * (plates.perSide.reduce(0, +) + plates.leftoverKg), plates.totalKg, accuracy: 0.05, context)
        }

        if let tip = snap.coachTip {
            XCTAssertEqual(snap.phase, .resting, context)
            XCTAssertEqual(state.lastLogged?.exerciseID, tip.targetExerciseID, context)
            let set = state.exercises.first { $0.id == tip.targetExerciseID }?.sets.first { $0.id == tip.targetSetID }
            XCTAssertNotNil(set, context)
            XCTAssertEqual(set?.isDone, false, context)
            XCTAssertNotEqual(set?.type, SetType.warmup, context)
            XCTAssertGreaterThan(tip.suggestedWeightKg, set?.weightKg ?? 0, context)
        }
    }

    func testTheLiveContextHoldsUnderRandomPlay() throws {
        var template = PresFix.upperA()
        // A previous best on every exercise so that random sets often are records.
        template.entries = template.entries.map { entry in
            var copy = entry
            copy.exercise.previousBestE1RM = 40
            return copy
        }
        for seed in 1...12 {
            var rng = PresLCG(seed: UInt64(seed) &+ 4_200)
            var state = seed % 4 == 0
                ? WorkoutFactory.makeEmpty(name: "Fuzz", now: PresFix.t0)
                : WorkoutFactory.makeWorkout(from: template, now: PresFix.t0)
            var previous = state
            var clock = 0.0
            for step in 0..<150 {
                clock += Double(rng.below(30)) / 2
                let exercise = state.exercises.isEmpty ? nil : state.exercises[rng.below(state.exercises.count)]
                let set = exercise.flatMap { $0.sets.isEmpty ? nil : $0.sets[rng.below($0.sets.count)] }
                let action: WorkoutAction
                switch rng.below(14) {
                case 0, 1, 2: action = .logNextSet
                case 3: action = exercise.flatMap { e in set.map { .toggleSet(exerciseID: e.id, setID: $0.id) } } ?? .skipRest
                case 4: action = .pause
                case 5: action = .resume
                case 6: action = .adjustRest(seconds: rng.below(2) == 0 ? 15 : -15)
                case 7: action = .goTo(index: rng.below(6))
                case 8: action = .nudgeNextSet(weightSteps: rng.below(5) - 2, repsSteps: rng.below(5) - 2)
                case 9: action = .skipRest
                case 10: action = .addExercises([PresFix.lib(["bench", "plank", "squat", "lateral"][rng.below(4)])])
                case 11: action = .toggleLastSetRIR(rng.below(5))
                case 12: action = exercise.map { .toggleSuperset(exerciseID: $0.id) } ?? .skipRest
                default:
                    action = exercise.flatMap { e in
                        set.map { .setWeight(exerciseID: e.id, setID: $0.id, kg: Double(rng.below(300)) / 2) }
                    } ?? .skipRest
                }
                WorkoutReducer.reduce(&state, action, now: PresFix.at(clock))

                let now = PresFix.at(clock + Double(rng.below(300)) / 2)
                let context = "seed \(seed) step \(step) \(action)"
                try checkLiveContext(SnapshotBuilder.make(from: state, now: now), state, context)

                if let moment = SnapshotBuilder.prMoment(from: previous, to: state, now: now) {
                    XCTAssertTrue(state.exercises.contains { $0.exercise.name == moment.exerciseName }, context)
                    XCTAssertGreaterThan(moment.estimated1RM, 0, context)
                    XCTAssertGreaterThanOrEqual(moment.deltaKg, 1, context)
                    XCTAssertEqual(moment.expiresAt, now.addingTimeInterval(4), context)
                }
                previous = state
            }
        }
    }
}
