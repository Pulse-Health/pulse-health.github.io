import Foundation

// MARK: - Errors

/// Why a change to the stored data was not made. Failed writes are not part of this: they surface as the error of the write.
public enum StrengthStoreError: Error, Equatable, Sendable, LocalizedError {
    /// There is no template, workout or custom exercise with that id.
    case notFound
    /// The name is empty once white space is trimmed.
    case invalidName
    /// The exercise id belongs to a built-in exercise, which cannot be replaced.
    case reservedExerciseID

    public var errorDescription: String? {
        switch self {
        case .notFound: return "That item no longer exists."
        case .invalidName: return "The name cannot be empty."
        case .reservedExerciseID: return "That exercise id belongs to a built-in exercise."
        }
    }
}

// MARK: - Templates

public extension StrengthData {
    /// Renames a template (the name is trimmed).
    mutating func renameTemplate(id: UUID, to name: String) -> Result<Void, StrengthStoreError> {
        guard let index = templates.firstIndex(where: { $0.id == id }) else { return .failure(.notFound) }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.invalidName) }
        templates[index].name = trimmed
        return .success(())
    }

    /// Removes a template. Finished workouts keep their `templateID` and name.
    mutating func deleteTemplate(id: UUID) -> Result<Void, StrengthStoreError> {
        guard let index = templates.firstIndex(where: { $0.id == id }) else { return .failure(.notFound) }
        templates.remove(at: index)
        return .success(())
    }

    /// Adds a copy of a template right after the original: new template id, new entry ids, never performed. The copy is returned.
    mutating func duplicateTemplate(id: UUID, name: String) -> Result<WorkoutTemplate, StrengthStoreError> {
        guard let index = templates.firstIndex(where: { $0.id == id }) else { return .failure(.notFound) }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.invalidName) }
        var copy = templates[index]
        copy.id = UUID()
        copy.name = trimmed
        copy.entries = copy.entries.map { entry in
            var renewed = entry
            renewed.id = UUID()
            return renewed
        }
        copy.lastPerformed = nil
        templates.insert(copy, at: index + 1)
        return .success(copy)
    }

    /// Moves the templates at `source` so that they end up before the template that is at `destination` now (`templates.count` moves
    /// them to the end): the meaning of SwiftUI's `onMove`. Offsets outside the list are ignored.
    mutating func moveTemplates(fromOffsets source: IndexSet, toOffset destination: Int) {
        let offsets = source.filter { templates.indices.contains($0) }
        guard !offsets.isEmpty else { return }
        let target = max(0, min(destination, templates.count))
        let moving = offsets.map { templates[$0] }
        var remaining = templates
        for offset in offsets.reversed() { remaining.remove(at: offset) }
        remaining.insert(contentsOf: moving, at: target - offsets.filter { $0 < target }.count)
        templates = remaining
    }

    /// Orders the templates as `ids` lists them. Ids that are not templates are ignored; templates that are not listed keep their
    /// relative order after the listed ones.
    mutating func setTemplateOrder(_ ids: [UUID]) {
        var used = Set<Int>()
        var ordered: [WorkoutTemplate] = []
        for id in ids {
            guard let index = templates.indices.first(where: { templates[$0].id == id && !used.contains($0) }) else { continue }
            used.insert(index)
            ordered.append(templates[index])
        }
        for index in templates.indices where !used.contains(index) { ordered.append(templates[index]) }
        templates = ordered
    }

    /// Makes the template copies of built-in exercises follow the current library (name, muscle, cues, media, ...). The remembered
    /// previous results of a copy are not part of the library and stay as they are. Returns true when a copy changed.
    @discardableResult
    mutating func refreshTemplateExercises() -> Bool {
        var changed = false
        for templateIndex in templates.indices {
            for entryIndex in templates[templateIndex].entries.indices {
                let copy = templates[templateIndex].entries[entryIndex].exercise
                guard var current = ExerciseLibrary.exercise(id: copy.id) else { continue }
                current.previousBestE1RM = copy.previousBestE1RM
                current.previousSets = copy.previousSets
                current.previousRecords = copy.previousRecords
                if current != copy {
                    templates[templateIndex].entries[entryIndex].exercise = current
                    changed = true
                }
            }
        }
        return changed
    }
}

// MARK: - Finished workouts

public extension StrengthData {
    /// Removes a finished workout, gives its template back the `lastPerformed` of the workout before it (when this one was the
    /// last), and recomputes the personal bests.
    mutating func deleteWorkout(id: UUID) -> Result<Void, StrengthStoreError> {
        guard let index = history.firstIndex(where: { $0.id == id }) else { return .failure(.notFound) }
        let removed = history.remove(at: index)
        if let templateID = removed.templateID,
           let position = templates.firstIndex(where: { $0.id == templateID }),
           templates[position].lastPerformed == removed.finishedAt {
            templates[position].lastPerformed = history.filter { $0.templateID == templateID }.map { $0.finishedAt }.max()
        }
        recomputePersonalBests()
        return .success(())
    }

    /// Replaces a finished workout (the one with the same id) by an edited version and recomputes everything derived from it.
    ///
    /// What the user may change is taken from `workout`: its name (trimmed; a blank name keeps the old one) and its exercises with
    /// their sets (weight, reps, RIR, type), notes and order. A set can be removed by leaving it out, an exercise without sets
    /// disappears. The weight is clamped to 0...`WorkoutReducer.maximumWeightKg` (as the live workout does; a reps-only exercise keeps an
    /// assisted load down to `WorkoutReducer.minimumWeightKg`) and rounded to 0.01 kg, reps to 0...10 800, RIR to 0...4. The start,
    /// finish, duration, heart rate and template are kept from the stored workout.
    ///
    /// Derived fields are rebuilt the way `SummaryBuilder` builds them (volume, logged sets, mean RIR, sets per muscle, the best
    /// e1RM of each exercise), and the personal records of this workout are judged against the workouts before it (the older ones in
    /// the history). Later workouts keep the records they were given. The personal bests are recomputed from the whole history.
    mutating func updateWorkout(_ workout: CompletedWorkout) -> Result<Void, StrengthStoreError> {
        guard let index = history.firstIndex(where: { $0.id == workout.id }) else { return .failure(.notFound) }
        let stored = history[index]
        let baselines = baselines(inWorkoutsOlderThanIndex: index)

        let exercises = workout.exercises.map { entry -> WorkoutExercise in
            let exercise = Exercise(
                id: entry.exerciseID,
                name: entry.name,
                muscle: entry.muscle,
                equipment: .other,
                tracking: entry.tracking,
                mediaKey: entry.mediaKey,
                previousBestE1RM: baselines[entry.exerciseID]?.e1RM ?? 0,
                defaults: ExerciseDefaults(sets: 0, weightKg: 0, reps: 0, restSeconds: 0),
                allowsAddedWeight: entry.carriesLoad,
                previousRecords: baselines[entry.exerciseID]?.marks ?? RecordMarks()
            )
            let sets = entry.sets.map { set in
                LoggedSet(
                    type: set.type,
                    weightKg: Self.sanitizedWeight(set.weightKg, allowsNegative: entry.tracking == .repsOnly),
                    reps: max(0, min(set.reps, 10_800)),
                    isDone: true,
                    rir: set.rir.map { max(0, min($0, 4)) }
                )
            }
            return WorkoutExercise(id: entry.id, exercise: exercise, sets: sets, restSeconds: 0, note: entry.note)
        }
        let trimmed = workout.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let state = WorkoutState(
            id: stored.id,
            name: trimmed.isEmpty ? stored.name : trimmed,
            templateID: stored.templateID,
            exercises: exercises,
            startedAt: stored.startedAt
        )
        var rebuilt = SummaryBuilder.build(from: state, finishedAt: stored.finishedAt)
        rebuilt.durationSeconds = stored.durationSeconds
        rebuilt.averageHeartRate = stored.averageHeartRate
        history[index] = rebuilt
        recomputePersonalBests()
        return .success(())
    }

    private static func sanitizedWeight(_ kg: Double, allowsNegative: Bool) -> Double {
        guard !kg.isNaN else { return 0 }
        let clamped = max(allowsNegative ? WorkoutReducer.minimumWeightKg : 0, min(kg, WorkoutReducer.maximumWeightKg))
        let rounded = (clamped * 100).rounded(.toNearestOrAwayFromZero) / 100
        return rounded == 0 ? 0 : rounded
    }
}

// MARK: - Custom exercises

public extension StrengthData {
    /// Removes a custom exercise from the library and every template entry that holds it; returns how many templates lost an entry.
    /// Finished workouts keep the exercise's name and results.
    mutating func deleteCustomExercise(id: String) -> Result<Int, StrengthStoreError> {
        guard let index = customExercises.firstIndex(where: { $0.id == id }) else { return .failure(.notFound) }
        customExercises.remove(at: index)
        var changed = 0
        for position in templates.indices {
            let kept = templates[position].entries.filter { $0.exercise.id != id }
            if kept.count != templates[position].entries.count {
                templates[position].entries = kept
                changed += 1
            }
        }
        return .success(changed)
    }

    /// Replaces a custom exercise (the one with the same id) and refreshes its copies in the templates. The remembered previous
    /// results of each copy stay as they are. Finished workouts keep the old name and muscle.
    mutating func updateCustomExercise(_ exercise: Exercise) -> Result<Void, StrengthStoreError> {
        guard let index = customExercises.firstIndex(where: { $0.id == exercise.id }) else { return .failure(.notFound) }
        let name = exercise.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return .failure(.invalidName) }
        var stored = exercise
        stored.name = name
        stored.isCustom = true
        stored.previousBestE1RM = customExercises[index].previousBestE1RM
        stored.previousSets = customExercises[index].previousSets
        stored.previousRecords = customExercises[index].previousRecords
        customExercises[index] = stored
        for templateIndex in templates.indices {
            for entryIndex in templates[templateIndex].entries.indices where templates[templateIndex].entries[entryIndex].exercise.id == stored.id {
                var copy = stored
                copy.previousBestE1RM = templates[templateIndex].entries[entryIndex].exercise.previousBestE1RM
                copy.previousSets = templates[templateIndex].entries[entryIndex].exercise.previousSets
                copy.previousRecords = templates[templateIndex].entries[entryIndex].exercise.previousRecords
                templates[templateIndex].entries[entryIndex].exercise = copy
            }
        }
        return .success(())
    }
}

// MARK: - Model

public extension StrengthDataModel {
    /// Renames a template and saves the templates.
    @discardableResult
    func renameTemplate(id: UUID, to name: String) -> Result<Void, Error> {
        if case let .failure(error) = data.renameTemplate(id: id, to: name) { return .failure(error) }
        return commit(templates: true)
    }

    /// Deletes a template and saves the templates.
    @discardableResult
    func deleteTemplate(id: UUID) -> Result<Void, Error> {
        if case let .failure(error) = data.deleteTemplate(id: id) { return .failure(error) }
        return commit(templates: true)
    }

    /// Adds a copy of a template after the original (see `StrengthData.duplicateTemplate`), saves the templates and returns the copy.
    @discardableResult
    func duplicateTemplate(id: UUID, name: String) -> Result<WorkoutTemplate, Error> {
        switch data.duplicateTemplate(id: id, name: name) {
        case let .failure(error):
            return .failure(error)
        case let .success(copy):
            return commit(templates: true).map { copy }
        }
    }

    /// Moves templates in the list (see `StrengthData.moveTemplates`) and saves the templates when the order changed.
    @discardableResult
    func moveTemplates(fromOffsets source: IndexSet, toOffset destination: Int) -> Result<Void, Error> {
        let before = data.templates
        data.moveTemplates(fromOffsets: source, toOffset: destination)
        return commit(templates: data.templates != before)
    }

    /// Orders the templates by `ids` (see `StrengthData.setTemplateOrder`) and saves the templates when the order changed.
    @discardableResult
    func setTemplateOrder(_ ids: [UUID]) -> Result<Void, Error> {
        let before = data.templates
        data.setTemplateOrder(ids)
        return commit(templates: data.templates != before)
    }

    /// Deletes a finished workout, recomputes the personal bests and saves what changed.
    @discardableResult
    func deleteWorkout(id: UUID) -> Result<Void, Error> {
        let templatesBefore = data.templates
        let bestsBefore = data.personalBests
        if case let .failure(error) = data.deleteWorkout(id: id) { return .failure(error) }
        return commit(templates: data.templates != templatesBefore, history: true, personalBests: data.personalBests != bestsBefore)
    }

    /// Replaces an edited finished workout, rebuilds its derived fields, recomputes the personal bests and saves what changed
    /// (see `StrengthData.updateWorkout`).
    @discardableResult
    func updateWorkout(_ workout: CompletedWorkout) -> Result<Void, Error> {
        let bestsBefore = data.personalBests
        if case let .failure(error) = data.updateWorkout(workout) { return .failure(error) }
        return commit(history: true, personalBests: data.personalBests != bestsBefore)
    }

    /// Recomputes the personal bests from the whole history and saves them when they changed.
    @discardableResult
    func recomputePersonalBests() -> Result<Void, Error> {
        let before = data.personalBests
        data.recomputePersonalBests()
        return commit(personalBests: data.personalBests != before)
    }

    /// Deletes a custom exercise and its entries in the templates and saves both; the success value is the number of templates that
    /// lost an entry, so the screen can warn about it.
    @discardableResult
    func deleteCustomExercise(id: String) -> Result<Int, Error> {
        switch data.deleteCustomExercise(id: id) {
        case let .failure(error):
            return .failure(error)
        case let .success(changed):
            return commit(templates: changed > 0, customExercises: true, exercises: true).map { changed }
        }
    }

    /// Replaces a custom exercise, refreshes its copies in the templates and saves both (see `StrengthData.updateCustomExercise`).
    @discardableResult
    func updateCustomExercise(_ exercise: Exercise) -> Result<Void, Error> {
        let templatesBefore = data.templates
        if case let .failure(error) = data.updateCustomExercise(exercise) { return .failure(error) }
        return commit(templates: data.templates != templatesBefore, customExercises: true, exercises: true)
    }

    /// Makes the template copies of built-in exercises follow the current library. In memory only: the templates file gets the
    /// refreshed copies the next time the templates are saved.
    internal func refreshTemplateExercises() {
        data.refreshTemplateExercises()
    }
}
