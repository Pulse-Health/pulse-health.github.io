import Foundation

// Live moments of the Live Activity (widgets/SPEC.md section 2, "Live moments"). `SnapshotBuilder.make` fills the parts that follow
// from the state alone (superset, plates, coach tip); the two public functions below make what the app decides on: the record
// banner and the final card.

/// Helpers for the transient parts of the Live Activity content that the app, not `SnapshotBuilder.make`, decides on.
public extension SnapshotBuilder {
    /// Seconds a record banner stays when the app does not say otherwise.
    static let defaultMomentLifetime: TimeInterval = 4

    /// A `PRMoment` when the change from `old` to `new` logged a set that is a personal record (the presenter's rule: a logged,
    /// non-warm-up weight set whose Epley estimate beats the running best by more than 0.05; nothing without a previous best), else nil.
    /// The moment expires `lifetime` seconds after `now` (a negative or non-finite lifetime counts as none and as the default); the
    /// app sends the clearing update at `expiresAt`.
    ///
    /// A set is *new* when it is a record in `new` and was not one in `old` (a set that was pending, absent or no record before, found
    /// by its id), so a change that does not touch the sets (a heart-rate sample, a pause) and a record that was already there give
    /// nil. Two states of different workouts give nil: nothing was logged in the workout being shown. When several sets became
    /// records at once (a bulk change, an undo and redo) the one with the highest estimate is reported, the later one on a tie.
    ///
    /// The text fields follow the snapshot's own: `weightText` "85" and `repsText` "5" carry no unit. `estimated1RM` is the estimate
    /// in whole kilograms. `deltaKg` is the difference of the whole-kilogram estimates between the set and the running best it beat
    /// (the previous best raised by the sets logged before it, so a second record in a session reports its gain over the first),
    /// at least 1 so a record never reads "+0 kg".
    static func prMoment(from old: WorkoutState, to new: WorkoutState, now: Date, lifetime: TimeInterval = 4) -> PRMoment? {
        guard old.id == new.id else { return nil }
        var best: (exerciseName: String, set: LoggedSet, e1RM: Double, baseline: Double)?
        for entry in new.exercises {
            let analysis = PresenterSupport.analyse(entry).sets
            let earlier = old.exercises.first { $0.id == entry.id }.map { (sets: $0.sets, analysis: PresenterSupport.analyse($0).sets) }
            for (index, set) in entry.sets.enumerated() where analysis[index].isRecord {
                if let earlier, let before = earlier.sets.firstIndex(where: { $0.id == set.id }), earlier.analysis[before].isRecord {
                    continue
                }
                if analysis[index].e1RM >= (best?.e1RM ?? 0) {
                    best = (entry.exercise.name, set, analysis[index].e1RM, analysis[index].baselineBefore)
                }
            }
        }
        guard let best else { return nil }

        let seconds = lifetime.isFinite ? max(0, lifetime) : defaultMomentLifetime
        let estimate = PresenterSupport.wholeKilograms(best.e1RM)
        return PRMoment(
            exerciseName: best.exerciseName,
            weightText: NumberText.kg(best.set.weightKg),
            repsText: String(best.set.reps),
            estimated1RM: estimate,
            deltaKg: max(1, estimate - PresenterSupport.wholeKilograms(best.baseline)),
            expiresAt: now.addingTimeInterval(seconds)
        )
    }

    /// The Live Activity's final card for a finished workout: the duration in whole minutes (a half rounds up), the logged sets, the
    /// volume in tonnes with one decimal and no trailing zero ("9.1", "9"), the number of records, and whether Health has it.
    static func finishBrief(from completed: CompletedWorkout, savedToHealth: Bool) -> FinishBrief {
        FinishBrief(
            workoutName: completed.name,
            durationMinutes: WidgetSessions.roundedMinutes(completed.durationSeconds),
            sets: max(0, completed.loggedSets),
            volumeText: NumberText.kg((max(0, completed.volumeKg) / 100).rounded() / 10),
            personalRecordCount: completed.personalRecords.count,
            savedToHealth: savedToHealth
        )
    }
}

// MARK: - Parts of the snapshot that follow from the state

extension SnapshotBuilder {
    /// The running superset when the exercise at `shownIndex` is in one: the exercises that share its group, in workout order.
    ///
    /// * `label` is the group ("A"); the members are tagged with it and their position ("A1", "A2", ...).
    /// * `rounds` is the set count of the first member. `round` is the round in progress, 1-based and capped at `rounds`: the rounds
    ///   every member has finished plus one. Counting from the least advanced member (members without sets are left out) keeps
    ///   the round right after the first member has logged and the second is next, which is when the Live Activity shows
    ///   "A2 2/3"; the first member's count alone would already move on to the next round there. Whenever the first member is the
    ///   next to log the two readings agree.
    /// * `detail` is "<weight text> × <reps>" ("10 × 12", "BW × 12") of the member's next pending set, or of its last set when it has
    ///   none left; a duration exercise reads "45 s", since it has no weight to put in front. Empty without sets.
    /// * `isDone` tells whether the member's set of this round is logged; a member that has no set in the round counts as done when
    ///   it has no pending set. `isCurrent` marks the shown exercise.
    ///
    /// nil for an exercise without a group and for a group of one (the reducer never leaves one behind).
    static func supersetBrief(in state: WorkoutState, shownIndex: Int) -> SupersetBrief? {
        guard state.exercises.indices.contains(shownIndex),
              let group = state.exercises[shownIndex].supersetGroup, !group.isEmpty
        else { return nil }
        let memberIndices = state.exercises.indices.filter { state.exercises[$0].supersetGroup == group }
        guard memberIndices.count >= 2 else { return nil }

        let rounds = max(1, state.exercises[memberIndices[0]].sets.count)
        let finishedRounds = memberIndices.compactMap { index -> Int? in
            let entry = state.exercises[index]
            return entry.sets.isEmpty ? nil : entry.doneCount
        }.min() ?? 0
        let round = min(rounds, finishedRounds + 1)

        let members = memberIndices.enumerated().map { position, index -> SupersetMember in
            let entry = state.exercises[index]
            let roundSet = entry.sets.indices.contains(round - 1) ? entry.sets[round - 1] : nil
            let nextSet = entry.sets.first(where: { !$0.isDone }) ?? entry.sets.last
            return SupersetMember(
                tag: group + String(position + 1),
                name: entry.exercise.name,
                detail: nextSet.map { supersetDetail($0, exercise: entry.exercise) } ?? "",
                isDone: roundSet?.isDone ?? !entry.sets.contains(where: { !$0.isDone }),
                isCurrent: index == shownIndex
            )
        }
        return SupersetBrief(label: group, round: round, rounds: rounds, members: members)
    }

    /// "10 × 12", "BW × 12" or, for a duration, "45 s".
    private static func supersetDetail(_ set: LoggedSet, exercise: Exercise) -> String {
        if exercise.tracking == .duration { return "\(set.reps) s" }
        return PresenterSupport.weightText(set, exercise: exercise) + " × \(set.reps)"
    }

    /// The plates to load for `set` when `exercise` is a barbell weight exercise (`Exercise.supportsPlates`), by
    /// `PlateCalculator.plan` with the exercise's own bar. `summary` joins the plates of one side with " + " ("20 + 10 + 2.5").
    ///
    /// nil without a set, for other equipment, below the weight of the empty bar, and when no plate is needed (the bare bar, or a
    /// weight smaller than the smallest plate on each side): there is nothing to show beside the Log button then.
    static func plateBrief(for set: LoggedSet?, exercise: Exercise?) -> PlateBrief? {
        guard let set, let exercise, exercise.supportsPlates,
              let plan = PlateCalculator.plan(totalKg: set.weightKg, barKg: exercise.barKg),
              !plan.perSide.isEmpty
        else { return nil }
        return PlateBrief(
            totalKg: set.weightKg,
            barKg: exercise.barKg,
            perSide: plan.perSide,
            leftoverKg: plan.leftoverKg,
            summary: WidgetText.platesText(plan.perSide)
        )
    }

    /// The one-tap suggestion for the next set, only while `phase` is `.resting`.
    ///
    /// It needs the last logged set (`WorkoutState.lastLogged`) to still be logged, to be a non-warm-up set of a weight exercise with
    /// 3 or more reps in reserve, and the same exercise to have a pending working set (the first one; warm-ups do not count, and a
    /// weight that is not above zero gives no tip). Then `suggestedWeightKg` is that set's weight plus the exercise's weight step
    /// (rounded to 0.01), `suggestedWeightText` "82.5 kg", `keepWeightText` "Keep 80", `subtitle` "3 reps in reserve on set 2"
    /// ("4+" for the top value, which stands for four or more) and `text` "Try 82.5 kg on set 3.". Set numbers count every set of
    /// the exercise, like the snapshot's `setLabel`. The suggestion names its own set and exercise: with a superset that is the
    /// exercise just logged, not necessarily the target of the Log button.
    static func coachTipBrief(in state: WorkoutState, phase: SnapshotPhase) -> CoachTipBrief? {
        guard phase == .resting, let reference = state.lastLogged,
              let exerciseIndex = state.exercises.firstIndex(where: { $0.id == reference.exerciseID })
        else { return nil }
        let entry = state.exercises[exerciseIndex]
        guard let loggedIndex = entry.sets.firstIndex(where: { $0.id == reference.setID }) else { return nil }
        let logged = entry.sets[loggedIndex]
        guard logged.isDone, logged.type != .warmup, entry.exercise.tracksWeight,
              let reserve = logged.rir, reserve >= 3,
              let pendingIndex = entry.sets.firstIndex(where: { !$0.isDone && $0.type != .warmup })
        else { return nil }
        let pending = entry.sets[pendingIndex]
        guard pending.weightKg.isFinite, pending.weightKg > 0 else { return nil }

        let suggested = WidgetText.hundredth(pending.weightKg + entry.exercise.weightStepKg)
        let suggestedText = NumberText.kg(suggested) + " kg"
        return CoachTipBrief(
            subtitle: (reserve >= 4 ? "4+" : String(reserve)) + " reps in reserve on set \(loggedIndex + 1)",
            text: "Try " + suggestedText + " on set \(pendingIndex + 1).",
            suggestedWeightKg: suggested,
            suggestedWeightText: suggestedText,
            keepWeightText: "Keep " + NumberText.kg(pending.weightKg),
            targetSetID: pending.id,
            targetExerciseID: entry.id
        )
    }
}
