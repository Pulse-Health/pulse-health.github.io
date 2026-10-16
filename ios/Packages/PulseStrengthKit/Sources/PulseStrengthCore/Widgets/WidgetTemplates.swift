import Foundation

/// What the snapshot says about the saved templates: the next workout, the launcher list and the cards derived from the next
/// workout's exercises (widgets/SPEC.md section 2: nextUp, templates, overload, formCue, loadedBar).
enum WidgetTemplates {
    // MARK: Next up and the launcher

    /// The template to train next and what to show of it. `template` is `StrengthData.nextTemplate()`: the next workout of the active
    /// plan, else the template after the most recently performed one. The plan fields are filled when an active plan names it.
    static func nextUp(_ template: WorkoutTemplate, in data: StrengthData, history: WidgetHistory) -> NextUpSummary {
        var summary = NextUpSummary(
            templateID: template.id,
            name: template.name,
            splitLabel: WidgetText.splitLabel(of: template.name),
            exerciseCount: template.entries.count,
            setCount: template.entries.reduce(0) { $0 + $1.plannedSets.count },
            estimatedMinutes: template.estimatedMinutes,
            lastPerformedAt: template.lastPerformed,
            daysSince: template.lastPerformed.map { history.daysAgo($0) },
            exercises: template.entries.map(brief)
        )
        if let plan = data.activePlan, plan.nextWorkout(in: data.templates)?.id == template.id,
           let position = plan.nextPosition(in: data.templates) {
            summary.planName = plan.name
            summary.planPosition = position
            summary.planCount = plan.templateIDs.count
        }
        return summary
    }

    /// Every saved template in store order, with `isSuggested` on `suggested`.
    static func launcher(_ templates: [WorkoutTemplate], suggested: UUID?, history: WidgetHistory) -> [TemplateSummary] {
        templates.map { template in
            TemplateSummary(
                templateID: template.id,
                name: template.name,
                exerciseCount: template.entries.count,
                estimatedMinutes: template.estimatedMinutes,
                lastPerformedAt: template.lastPerformed,
                daysSince: template.lastPerformed.map { history.daysAgo($0) },
                isSuggested: template.id == suggested
            )
        }
    }

    private static func brief(_ entry: TemplateEntry) -> PlannedExerciseBrief {
        PlannedExerciseBrief(
            exerciseID: entry.exercise.id,
            name: entry.exercise.name,
            muscle: entry.exercise.muscle,
            setCount: entry.plannedSets.count,
            summary: summary(of: entry)
        )
    }

    /// The planned sets in a few characters. Working sets are the ones that are not warm-ups (all sets when there is no other).
    /// Weight exercises: "3 × 85" (working sets × the heaviest working weight); reps only: "3 × 12" (the most reps); duration:
    /// "3 × 45 s" (the longest time). A set with a rep range counts with the top of its range.
    static func summary(of entry: TemplateEntry) -> String {
        let working = entry.plannedSets.filter { $0.type != .warmup }
        let used = working.isEmpty ? entry.plannedSets : working
        switch entry.exercise.tracking {
        case .weightReps:
            return "\(used.count) × " + NumberText.kg(used.map { $0.weightKg }.max() ?? 0)
        case .repsOnly:
            return "\(used.count) × \(used.map(topReps).max() ?? 0)"
        case .duration:
            return "\(used.count) × \(used.map(topReps).max() ?? 0) s"
        }
    }

    /// The most reps a planned set asks for: the top of its range, or its reps without one.
    private static func topReps(_ set: PlannedSet) -> Int {
        max(set.reps, set.repsMax ?? set.reps)
    }

    // MARK: Overload

    /// What to lift today to beat last time, for the first exercise of `template` that tracks weight, has a working set and has been done
    /// before; nil when there is none.
    ///
    /// The last time is the exercise's best working set (highest Epley estimate, the first on a tie) in the newest workout that
    /// contains it. The plan is the entry's first working set: its reps and the number of working sets. When last time's reps reached the
    /// planned reps the target adds the exercise's weight step and asks for the planned reps; otherwise it keeps the weight and asks for one more
    /// rep than last time, at most the planned reps. (The SPEC writes these as products: `weight × reps`.)
    ///
    /// A planned set with a rep range (`repsMax`) is double progression: the planned reps that have to be reached are the top of the
    /// range, and after adding weight the target starts again at the bottom of the range. Without a range this is the rule above.
    static func overload(for template: WorkoutTemplate, history: WidgetHistory) -> OverloadTarget? {
        for entry in template.entries where entry.exercise.tracksWeight {
            let working = entry.plannedSets.filter { $0.type != .warmup }
            guard let first = working.first, let last = lastBestSet(of: entry.exercise.id, history: history) else { continue }
            let bottom = first.reps
            let top = max(first.reps, first.repsMax ?? first.reps)
            let targetWeight: Double
            let targetReps: Int
            if last.set.reps >= top {
                targetWeight = last.set.weightKg + entry.exercise.weightStepKg
                targetReps = bottom
            } else {
                targetWeight = last.set.weightKg
                targetReps = min(last.set.reps + 1, top)
            }
            return OverloadTarget(
                exerciseID: entry.exercise.id,
                exerciseName: entry.exercise.name,
                lastWeightKg: last.set.weightKg,
                lastReps: last.set.reps,
                lastDaysAgo: history.daysAgo(last.finishedAt),
                targetWeightKg: targetWeight,
                targetReps: targetReps,
                targetSets: working.count,
                deltaKg: targetWeight - last.set.weightKg
            )
        }
        return nil
    }

    /// The best working set (highest Epley estimate, the first on a tie) of `exerciseID` in the newest workout that contains the
    /// exercise, with that workout's finish time; nil when the exercise was never done or that workout has no working set with a weight.
    private static func lastBestSet(of exerciseID: String, history: WidgetHistory) -> (set: CompletedSet, finishedAt: Date)? {
        var newest: CompletedWorkout?
        for entry in history.entries where entry.workout.exercises.contains(where: { $0.exerciseID == exerciseID }) {
            if let current = newest, current.finishedAt >= entry.workout.finishedAt { continue }
            newest = entry.workout
        }
        guard let workout = newest else { return nil }
        var best: (set: CompletedSet, estimate: Double)?
        for exercise in workout.exercises where exercise.exerciseID == exerciseID {
            for set in exercise.sets where set.type != .warmup {
                let estimate = Estimated1RM.epley(weightKg: set.weightKg, reps: set.reps)
                if estimate > (best?.estimate ?? 0) { best = (set, estimate) }
            }
        }
        return best.map { ($0.set, workout.finishedAt) }
    }

    // MARK: Form cue and loaded bar

    /// One coaching cue of the first exercise of `template` that has cues. Which cue changes with the day: `(dayOfYear - 1) mod count`.
    static func formCue(for template: WorkoutTemplate, history: WidgetHistory) -> FormCue? {
        guard let exercise = template.entries.map({ $0.exercise }).first(where: { !$0.cues.isEmpty }) else { return nil }
        let index = (WidgetCalendar.dayOfYear(ofDay: history.today) - 1) % exercise.cues.count
        return FormCue(
            exerciseID: exercise.id,
            exerciseName: exercise.name,
            cue: exercise.cues[index],
            index: index + 1,
            count: exercise.cues.count
        )
    }

    /// The plates for the heaviest working set of `template` among its exercises that use plates (barbell, weight): the first entry on
    /// a tie. nil without such a set, and when the weight is below the empty bar.
    static func loadedBar(for template: WorkoutTemplate) -> LoadedBar? {
        var best: (exercise: Exercise, weightKg: Double)?
        for entry in template.entries where entry.exercise.supportsPlates {
            guard let heaviest = entry.plannedSets.filter({ $0.type != .warmup }).map({ $0.weightKg }).max() else { continue }
            if heaviest > (best?.weightKg ?? -Double.infinity) { best = (entry.exercise, heaviest) }
        }
        guard let best, let plan = PlateCalculator.plan(totalKg: best.weightKg, barKg: best.exercise.barKg) else { return nil }
        return LoadedBar(
            exerciseID: best.exercise.id,
            exerciseName: best.exercise.name,
            totalKg: best.weightKg,
            barKg: best.exercise.barKg,
            platesPerSide: plan.perSide,
            leftoverKg: plan.leftoverKg,
            summary: WidgetText.platesText(plan.perSide)
        )
    }
}
