import Foundation

/// Creates workouts from nothing or from a template, and turns a workout back into a template.
public enum WorkoutFactory {
    /// A workout without exercises, started `now`.
    public static func makeEmpty(name: String, now: Date, id: UUID = UUID()) -> WorkoutState {
        WorkoutState(id: id, name: name, startedAt: now)
    }

    /// A workout whose exercises, sets (all pending), rest times and supersets come from `template`.
    public static func makeWorkout(from template: WorkoutTemplate, now: Date, id: UUID = UUID()) -> WorkoutState {
        var groupSizes: [String: Int] = [:]
        for entry in template.entries {
            if let group = entry.supersetGroup { groupSizes[group, default: 0] += 1 }
        }
        let exercises = template.entries.map { entry -> WorkoutExercise in
            // A superset group needs at least two members; a lone letter in a template is dropped.
            let group = entry.supersetGroup.flatMap { (groupSizes[$0] ?? 0) >= 2 ? $0 : nil }
            return WorkoutExercise(
                id: UUID(),
                exercise: entry.exercise,
                sets: entry.plannedSets.map { LoggedSet(type: $0.type, weightKg: $0.weightKg, reps: $0.reps) },
                restSeconds: max(0, entry.restSeconds),
                supersetGroup: group,
                note: "",
                templateEntryID: entry.id
            )
        }
        return WorkoutState(
            id: id,
            name: template.name,
            templateID: template.id,
            templateBaseline: template.entries.map { $0.id },
            exercises: exercises,
            currentIndex: 0,
            startedAt: now
        )
    }

    /// `template` rebuilt from the workout's current exercises; kept entries keep their id, new exercises get new ones.
    public static func updatedTemplate(_ template: WorkoutTemplate, from state: WorkoutState) -> WorkoutTemplate {
        var usedIDs = Set<UUID>()
        var entries: [TemplateEntry] = []
        for workoutExercise in state.exercises {
            var entryID = workoutExercise.templateEntryID ?? UUID()
            if usedIDs.contains(entryID) { entryID = UUID() }
            usedIDs.insert(entryID)
            entries.append(entry(id: entryID, from: workoutExercise))
        }
        var result = template
        result.entries = entries
        return result
    }

    /// A new template (new ids, never performed) holding the workout's current exercises ("save as template").
    public static func template(from state: WorkoutState, name: String) -> WorkoutTemplate {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = state.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = !trimmed.isEmpty ? trimmed : (!fallback.isEmpty ? fallback : "Workout")
        return WorkoutTemplate(
            id: UUID(),
            name: title,
            entries: state.exercises.map { entry(id: UUID(), from: $0) },
            lastPerformed: nil
        )
    }

    private static func entry(id: UUID, from workoutExercise: WorkoutExercise) -> TemplateEntry {
        TemplateEntry(
            id: id,
            exercise: workoutExercise.exercise,
            plannedSets: workoutExercise.sets.map { PlannedSet(type: $0.type, weightKg: $0.weightKg, reps: $0.reps) },
            restSeconds: workoutExercise.restSeconds,
            supersetGroup: workoutExercise.supersetGroup
        )
    }
}
