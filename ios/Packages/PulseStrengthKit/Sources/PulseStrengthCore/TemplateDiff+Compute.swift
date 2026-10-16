import Foundation

public extension TemplateDiff {
    /// What changed in `state` relative to the template it was started from (added, removed and reordered exercises).
    ///
    /// An exercise counts as added when it has no template entry, its entry is not in the baseline, or another exercise
    /// already claims that entry; a baseline entry counts as removed when no exercise refers to it; the exercises that
    /// remain are reordered when their relative order differs from the baseline.
    ///
    /// The sets and rest of the kept exercises are not compared (`changedExercises` stays empty): that needs the template, see
    /// `compute(for:against:)`.
    static func compute(for state: WorkoutState) -> TemplateDiff {
        let kept = keptExercises(in: state)
        let baseline = state.templateBaseline
        let claimed = Set(kept.map { $0.entryID })
        let removed = baseline.filter { !claimed.contains($0) }.count
        let baselineCommon = baseline.filter { claimed.contains($0) }
        return TemplateDiff(
            added: state.exercises.count - kept.count,
            removed: removed,
            reordered: kept.map { $0.entryID } != baselineCommon
        )
    }

    /// `compute(for:)` plus the kept exercises whose LOGGED and planned sets or rest differ from `template`'s entries
    /// (`changedExercises`, in workout order). Without a template (nil, or an entry the template no longer has) the result is the
    /// structure only.
    ///
    /// For each kept exercise:
    /// * `setCount`: the number of sets differs (warm-ups count);
    /// * `setType`: the sets have the same number but a set has another type;
    /// * `weight` / `reps`: a WORKING set (warm-ups are left out) has another weight (compared in kilograms rounded to 0.01) or reps
    ///   (seconds), compared set by set when both have the same number of working sets (a different number is a `setCount` change;
    ///   the weights count for exercises with an editable weight only). A planned set with a rep range (`PlannedSet.repsMax`) asks for
    ///   any number of reps inside the range: a set with such a number is no change, one outside the range is;
    /// * `restSeconds`: the exercise's rest differs.
    ///
    /// Notes and superset groups are not compared.
    static func compute(for state: WorkoutState, against template: WorkoutTemplate?) -> TemplateDiff {
        var diff = compute(for: state)
        guard let template else { return diff }
        for item in keptExercises(in: state) {
            guard let planned = template.entries.first(where: { $0.id == item.entryID }) else { continue }
            let entry = state.exercises[item.index]
            let kinds = changes(of: entry, from: planned)
            if !kinds.isEmpty {
                diff.changedExercises.append(ChangedExercise(entryID: item.entryID, name: entry.exercise.name, kinds: kinds))
            }
        }
        return diff
    }
}

private extension TemplateDiff {
    /// The exercises that still stand for a baseline entry, in workout order: the first exercise that claims an entry of the baseline
    /// keeps it, every other exercise counts as added.
    static func keptExercises(in state: WorkoutState) -> [(index: Int, entryID: UUID)] {
        let baselineSet = Set(state.templateBaseline)
        var claimed = Set<UUID>()
        var kept: [(index: Int, entryID: UUID)] = []
        for (index, entry) in state.exercises.enumerated() {
            if let entryID = entry.templateEntryID, baselineSet.contains(entryID), claimed.insert(entryID).inserted {
                kept.append((index, entryID))
            }
        }
        return kept
    }

    static func changes(of entry: WorkoutExercise, from planned: TemplateEntry) -> Set<Change> {
        var kinds = Set<Change>()
        let sets = entry.sets
        let plannedSets = planned.plannedSets
        if sets.count != plannedSets.count {
            kinds.insert(.setCount)
        } else if zip(sets, plannedSets).contains(where: { $0.type != $1.type }) {
            kinds.insert(.setType)
        }
        let working = sets.filter { $0.type != .warmup }
        let plannedWorking = plannedSets.filter { $0.type != .warmup }
        if working.count == plannedWorking.count {
            let pairs = Array(zip(working, plannedWorking))
            if entry.exercise.hasEditableWeight, pairs.contains(where: { hundredths($0.weightKg) != hundredths($1.weightKg) }) {
                kinds.insert(.weight)
            }
            if pairs.contains(where: { !isWithinPlan($0.reps, $1) }) { kinds.insert(.reps) }
        }
        if max(0, entry.restSeconds) != max(0, planned.restSeconds) { kinds.insert(.restSeconds) }
        return kinds
    }

    /// True when `reps` is what the planned set asks for: exactly its reps, or any number from its reps up to its `repsMax`.
    static func isWithinPlan(_ reps: Int, _ planned: PlannedSet) -> Bool {
        if let upper = planned.repsMax, upper > planned.reps { return reps >= planned.reps && reps <= upper }
        return reps == planned.reps
    }

    /// A weight in kilograms as a whole number of hundredths (a weight that is not finite counts as its own value).
    static func hundredths(_ kg: Double) -> Double {
        kg.isFinite ? (kg * 100).rounded(.toNearestOrAwayFromZero) : kg
    }
}
