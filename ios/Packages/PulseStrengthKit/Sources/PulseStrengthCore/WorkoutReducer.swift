import Foundation

/// The only code that applies a `WorkoutAction` to a `WorkoutState` (port of the design's Active.dc.html logic).
public enum WorkoutReducer {
    /// How long a removed or replaced exercise or a deleted set can be restored with `.undo` (6 seconds).
    public static var undoWindow: TimeInterval { 6 }

    /// Heaviest weight a set can hold (1,000,000 kg). Larger values are clamped to it; the keypad's six characters stay below it.
    public static let maximumWeightKg: Double = 1_000_000

    /// Longest rest an exercise can be given (one hour). Larger values are clamped to it; the rest presets stop at 5:00.
    public static let maximumRestSeconds: Int = 3_600

    /// Shortest time between two samples of `WorkoutState.heartRateSeries` (30 seconds). Samples that arrive sooner still update the
    /// current heart rate and the average, but are not kept in the series.
    public static let heartRateSampleInterval: TimeInterval = 30

    /// Most samples `WorkoutState.heartRateSeries` keeps (360, three hours at one per 30 seconds). Once it is full, later samples are
    /// not added: the series keeps the start of the workout, and the average still counts every sample.
    public static let maximumHeartRateSamples: Int = 360

    /// Applies `action` to `state`; `revision` grows by one when the state changed (never for heart-rate samples).
    public static func reduce(_ state: inout WorkoutState, _ action: WorkoutAction, now: Date) {
        let before = state
        var next = state
        apply(action, to: &next, now: now)
        next.currentIndex = next.clampedIndex
        if !isHeartRateSample(action), next != before {
            next.revision = next.revision == Int.max ? Int.max : next.revision + 1
        }
        state = next
    }
}

// MARK: - Dispatch

private extension WorkoutReducer {
    static func isHeartRateSample(_ action: WorkoutAction) -> Bool {
        if case .updateHeartRate = action { return true }
        return false
    }

    static func apply(_ action: WorkoutAction, to s: inout WorkoutState, now: Date) {
        switch action {
        case let .toggleSet(exerciseID, setID):
            guard let (k, i) = locate(s, exerciseID, setID) else { return }
            if s.exercises[k].sets[i].isDone {
                s.exercises[k].sets[i].isDone = false
                s.exercises[k].sets[i].doneAt = nil
            } else {
                markDone(&s, exerciseIndex: k, setIndex: i, now: now)
            }
        case let .logSet(exerciseID, setID):
            guard let (k, i) = locate(s, exerciseID, setID), !s.exercises[k].sets[i].isDone else { return }
            markDone(&s, exerciseIndex: k, setIndex: i, now: now)
        case .logNextSet:
            guard let target = WorkoutTargets.nextPending(in: s) else { return }
            s.currentIndex = target.exerciseIndex
            markDone(&s, exerciseIndex: target.exerciseIndex, setIndex: target.setIndex, now: now)
        case let .setWeight(exerciseID, setID, kg):
            guard let (k, i) = locate(s, exerciseID, setID), let value = roundedWeight(kg) else { return }
            s.exercises[k].sets[i].weightKg = value
        case let .setReps(exerciseID, setID, reps):
            guard let (k, i) = locate(s, exerciseID, setID) else { return }
            s.exercises[k].sets[i].reps = clampReps(reps)
        case let .nudgeNextSet(weightSteps, repsSteps):
            nudgeNextSet(&s, weightSteps: weightSteps, repsSteps: repsSteps)
        case let .setSetType(exerciseID, setID, type):
            guard let (k, i) = locate(s, exerciseID, setID) else { return }
            s.exercises[k].sets[i].type = type
        case let .setRIR(exerciseID, setID, rir):
            guard let (k, i) = locate(s, exerciseID, setID) else { return }
            s.exercises[k].sets[i].rir = rir.map(clampRIR)
        case let .toggleLastSetRIR(value):
            toggleLastSetRIR(&s, value)
        case let .addSet(exerciseID):
            addSet(&s, exerciseID: exerciseID)
        case let .deleteSet(exerciseID, setID):
            deleteSet(&s, exerciseID: exerciseID, setID: setID, now: now)
        case let .setNote(exerciseID, note):
            guard let k = s.exerciseIndex(id: exerciseID) else { return }
            s.exercises[k].note = note

        case let .goTo(index):
            s.currentIndex = clampIndex(index, count: s.exercises.count)
        case .nextExercise:
            s.currentIndex = clampIndex(s.clampedIndex + 1, count: s.exercises.count)
        case .previousExercise:
            s.currentIndex = clampIndex(s.clampedIndex - 1, count: s.exercises.count)

        case let .addExercises(exercises):
            addExercises(&s, exercises)
        case let .removeExercise(exerciseID):
            removeExercise(&s, exerciseID: exerciseID, now: now)
        case let .moveExercise(from, to):
            moveExercise(&s, from: from, to: to)
        case let .moveExerciseBy(exerciseID, delta):
            guard let k = s.exerciseIndex(id: exerciseID) else { return }
            let (target, overflow) = k.addingReportingOverflow(delta)
            guard !overflow else { return }
            moveExercise(&s, from: k, to: target)
        case let .replaceExercise(exerciseID, replacement):
            replaceExercise(&s, exerciseID: exerciseID, with: replacement, now: now)
        case let .toggleSuperset(exerciseID):
            toggleSuperset(&s, exerciseID: exerciseID)
        case let .setRest(exerciseID, seconds):
            guard let k = s.exerciseIndex(id: exerciseID) else { return }
            s.exercises[k].restSeconds = clampRest(seconds)

        case let .adjustRest(seconds):
            adjustRest(&s, seconds: seconds, now: now)
        case .skipRest:
            s.rest = nil
        case let .setAutoStartRest(isOn):
            s.settings.autoStartRest = isOn
        case let .setAlertWhenRestEnds(isOn):
            s.settings.alertWhenRestEnds = isOn

        case .pause:
            pause(&s, now: now)
        case .resume:
            resume(&s, now: now)
        case .undo:
            undo(&s, now: now)
        case let .updateHeartRate(bpm):
            s.heartRate = bpm
            if let bpm, (30...240).contains(bpm) {
                s.heartRateSum += bpm
                s.heartRateCount += 1
                keepHeartRateSample(&s, bpm: bpm, now: now)
            }
        case let .setUsedWatch(isOn):
            s.usedWatch = isOn
        case let .rename(name):
            s.name = name
        }
    }
}

// MARK: - Lookup and clamping helpers

private extension WorkoutReducer {
    /// Exercise index and set index of a set, nil when either id is unknown.
    static func locate(_ s: WorkoutState, _ exerciseID: UUID, _ setID: UUID) -> (Int, Int)? {
        guard let k = s.exerciseIndex(id: exerciseID),
              let i = s.exercises[k].sets.firstIndex(where: { $0.id == setID }) else { return nil }
        return (k, i)
    }

    static func clampIndex(_ index: Int, count: Int) -> Int {
        count > 0 ? max(0, min(index, count - 1)) : 0
    }

    static func clampReps(_ reps: Int) -> Int { max(0, min(reps, 999)) }

    static func clampRIR(_ value: Int) -> Int { max(0, min(value, 4)) }

    static func clampRest(_ seconds: Int) -> Int { max(0, min(seconds, maximumRestSeconds)) }

    /// Weight clamped to 0...`maximumWeightKg` and rounded to 0.01 kg; nil (ignored) for NaN and +infinity.
    static func roundedWeight(_ kg: Double) -> Double? {
        guard !kg.isNaN else { return nil }
        let lowerBounded = max(0, kg)
        guard lowerBounded.isFinite else { return nil }
        return (min(lowerBounded, maximumWeightKg) * 100).rounded(.toNearestOrAwayFromZero) / 100
    }

    static func saturatingSum(_ a: Int, _ b: Int) -> Int {
        let (sum, overflow) = a.addingReportingOverflow(b)
        if !overflow { return sum }
        return b > 0 ? Int.max : Int.min
    }

    /// Fresh pending sets for an exercise, from its library defaults.
    static func defaultSets(for exercise: Exercise) -> [LoggedSet] {
        let defaults = exercise.defaults
        let weight = roundedWeight(defaults.weightKg) ?? 0
        return (0..<max(0, defaults.sets)).map { _ in
            LoggedSet(type: .normal, weightKg: weight, reps: clampReps(defaults.reps))
        }
    }

    /// A workout entry for `exercise` with default sets and default rest.
    static func makeEntry(for exercise: Exercise, id: UUID = UUID(), group: String? = nil, templateEntryID: UUID? = nil) -> WorkoutExercise {
        WorkoutExercise(
            id: id,
            exercise: exercise,
            sets: defaultSets(for: exercise),
            restSeconds: clampRest(exercise.defaults.restSeconds),
            supersetGroup: group,
            note: "",
            templateEntryID: templateEntryID
        )
    }
}

// MARK: - Logging and rest start

private extension WorkoutReducer {
    /// Rest after a set: warm-ups rest 40 % of the exercise rest (rounded to 5 s, at least 30 s), other sets the full rest.
    /// An exercise rest of 0 means the timer is off: no rest after a set of any type.
    static func restSeconds(for exercise: WorkoutExercise, set: LoggedSet) -> Int {
        let base = max(0, exercise.restSeconds)
        guard base > 0 else { return 0 }
        guard set.type == .warmup else { return base }
        let scaled = (Double(base) * 0.4 / 5).rounded(.toNearestOrAwayFromZero) * 5
        return max(30, Int(scaled))
    }

    /// Marks a pending set done and applies the follow-up: last logged, superset advance, rest start.
    static func markDone(_ s: inout WorkoutState, exerciseIndex k: Int, setIndex i: Int, now: Date) {
        let entry = s.exercises[k]
        let set = entry.sets[i]
        s.exercises[k].sets[i].isDone = true
        s.exercises[k].sets[i].doneAt = now
        s.lastLogged = SetRef(exerciseID: entry.id, setID: set.id)
        var seconds = restSeconds(for: entry, set: set)
        if let group = entry.supersetGroup {
            let members = s.exercises.indices.filter { s.exercises[$0].supersetGroup == group }
            if let last = members.last, k < last {
                s.currentIndex = k + 1
                seconds = 0
            } else if let first = members.first {
                s.currentIndex = first
            }
        }
        if s.settings.autoStartRest && seconds > 0 {
            s.rest = RestState(
                endsAt: now.addingTimeInterval(Double(seconds)),
                totalSeconds: seconds,
                frozenRemaining: s.isPaused ? Double(seconds) : nil
            )
        } else {
            s.rest = nil
        }
    }

    static func nudgeNextSet(_ s: inout WorkoutState, weightSteps: Int, repsSteps: Int) {
        guard let target = WorkoutTargets.nextPending(in: s) else { return }
        let k = target.exerciseIndex
        let i = target.setIndex
        let exercise = s.exercises[k].exercise
        var set = s.exercises[k].sets[i]
        if weightSteps != 0, exercise.tracksWeight {
            let steps = Double(max(-1000, min(1000, weightSteps)))
            set.weightKg = roundedWeight(set.weightKg + steps * exercise.weightStepKg) ?? set.weightKg
        }
        if repsSteps != 0 {
            let steps = max(-1000, min(1000, repsSteps))
            set.reps = clampReps(saturatingSum(set.reps, steps * exercise.repsStep))
        }
        s.exercises[k].sets[i] = set
    }

    static func toggleLastSetRIR(_ s: inout WorkoutState, _ value: Int) {
        guard let ref = s.lastLogged, let (k, i) = locate(s, ref.exerciseID, ref.setID) else { return }
        let clamped = clampRIR(value)
        s.exercises[k].sets[i].rir = s.exercises[k].sets[i].rir == clamped ? nil : clamped
    }
}

// MARK: - Heart rate series

private extension WorkoutReducer {
    /// Adds the sample at `now` to the series when at least `heartRateSampleInterval` seconds passed since the last kept one and the
    /// series is not full. A clock that moved back keeps nothing until it passes the last sample again.
    static func keepHeartRateSample(_ s: inout WorkoutState, bpm: Int, now: Date) {
        guard s.heartRateSeries.count < maximumHeartRateSamples else { return }
        if let last = s.heartRateSeries.last, now.timeIntervalSince(last.at) < heartRateSampleInterval { return }
        s.heartRateSeries.append(HeartRateSample(bpm: bpm, at: now))
    }
}

// MARK: - Sets

private extension WorkoutReducer {
    static func addSet(_ s: inout WorkoutState, exerciseID: UUID) {
        guard let k = s.exerciseIndex(id: exerciseID) else { return }
        let entry = s.exercises[k]
        let weight: Double
        let reps: Int
        if let last = entry.sets.last {
            weight = last.weightKg
            reps = last.reps
        } else {
            weight = roundedWeight(entry.exercise.defaults.weightKg) ?? 0
            reps = clampReps(entry.exercise.defaults.reps)
        }
        s.exercises[k].sets.append(LoggedSet(type: .normal, weightKg: weight, reps: reps, isDone: false, rir: nil))
    }

    static func deleteSet(_ s: inout WorkoutState, exerciseID: UUID, setID: UUID, now: Date) {
        guard let (k, i) = locate(s, exerciseID, setID) else { return }
        let removed = s.exercises[k].sets.remove(at: i)
        if s.lastLogged?.setID == setID { s.lastLogged = nil }
        s.undo = UndoEntry(
            payload: .set(exerciseID: exerciseID, index: i, set: removed),
            title: "Set deleted",
            expiresAt: now.addingTimeInterval(undoWindow)
        )
    }
}

// MARK: - Exercise list

private extension WorkoutReducer {
    static func addExercises(_ s: inout WorkoutState, _ exercises: [Exercise]) {
        guard !exercises.isEmpty else { return }
        let wasEmpty = s.exercises.isEmpty
        s.exercises.append(contentsOf: exercises.map { makeEntry(for: $0) })
        if wasEmpty { s.currentIndex = 0 }
    }

    /// When a superset group is left with a single member, that member leaves the group too.
    static func releaseOrphan(_ s: inout WorkoutState, group: String?) {
        guard let group else { return }
        let members = s.exercises.indices.filter { s.exercises[$0].supersetGroup == group }
        if members.count == 1 { s.exercises[members[0]].supersetGroup = nil }
    }

    static func removeExercise(_ s: inout WorkoutState, exerciseID: UUID, now: Date) {
        guard let at = s.exerciseIndex(id: exerciseID) else { return }
        let removed = s.exercises.remove(at: at)
        releaseOrphan(&s, group: removed.supersetGroup)
        if at < s.currentIndex { s.currentIndex -= 1 }
        s.currentIndex = clampIndex(s.currentIndex, count: s.exercises.count)
        if s.lastLogged?.exerciseID == removed.id { s.lastLogged = nil }
        s.undo = UndoEntry(
            payload: .exercise(index: at, exercise: removed),
            title: "Removed " + removed.exercise.name,
            expiresAt: now.addingTimeInterval(undoWindow)
        )
    }

    /// Moves the exercise at `from` so it ends up at `to`; the current exercise stays selected.
    static func moveExercise(_ s: inout WorkoutState, from: Int, to: Int) {
        let count = s.exercises.count
        guard from >= 0, from < count, to >= 0, to < count, from != to else { return }
        let currentID = s.exercises[s.clampedIndex].id
        let item = s.exercises.remove(at: from)
        s.exercises.insert(item, at: to)
        if let index = s.exercises.firstIndex(where: { $0.id == currentID }) { s.currentIndex = index }
    }

    static func replaceExercise(_ s: inout WorkoutState, exerciseID: UUID, with replacement: Exercise, now: Date) {
        guard let k = s.exerciseIndex(id: exerciseID) else { return }
        let old = s.exercises[k]
        s.exercises[k] = makeEntry(for: replacement, id: old.id, group: old.supersetGroup, templateEntryID: old.templateEntryID)
        if s.lastLogged?.exerciseID == old.id { s.lastLogged = nil }
        // A deleted set of the old exercise no longer fits the new one.
        if let undo = s.undo, case let .set(undoExerciseID, _, _) = undo.payload, undoExerciseID == old.id {
            s.undo = nil
        }
        // Replacing throws away what was logged on the old exercise (and its note): keep it restorable for a few seconds. An exercise
        // with no logged set and no note has only planned values to lose, which are cheap to enter again, so it leaves a pending undo
        // of something else alone.
        if old.sets.contains(where: { $0.isDone }) || !old.note.isEmpty {
            s.undo = UndoEntry(
                payload: .replaced(exercise: old),
                title: "Replaced " + old.exercise.name,
                expiresAt: now.addingTimeInterval(undoWindow)
            )
        }
    }

    static func toggleSuperset(_ s: inout WorkoutState, exerciseID: UUID) {
        guard let k = s.exerciseIndex(id: exerciseID) else { return }
        if let group = s.exercises[k].supersetGroup {
            s.exercises[k].supersetGroup = nil
            releaseOrphan(&s, group: group)
            return
        }
        guard k + 1 < s.exercises.count else { return }
        let group = s.exercises[k + 1].supersetGroup ?? freeGroup(s)
        s.exercises[k].supersetGroup = group
        s.exercises[k + 1].supersetGroup = group
    }

    /// First of A...E not used by any exercise, else "Z".
    static func freeGroup(_ s: WorkoutState) -> String {
        let used = Set(s.exercises.compactMap { $0.supersetGroup })
        for letter in ["A", "B", "C", "D", "E"] where !used.contains(letter) { return letter }
        return "Z"
    }
}

// MARK: - Rest timer and pause

private extension WorkoutReducer {
    static func adjustRest(_ s: inout WorkoutState, seconds: Int, now: Date) {
        guard var rest = s.rest else {
            guard seconds > 0 else { return }
            s.rest = RestState(
                endsAt: now.addingTimeInterval(Double(seconds)),
                totalSeconds: seconds,
                frozenRemaining: s.isPaused ? Double(seconds) : nil
            )
            return
        }
        let delta = Double(seconds)
        rest.totalSeconds = max(5, saturatingSum(rest.totalSeconds, seconds))
        if s.isPaused || rest.frozenRemaining != nil {
            let frozen = rest.frozenRemaining ?? max(0, rest.endsAt.timeIntervalSince(now))
            rest.frozenRemaining = max(0, frozen + delta)
        } else {
            rest.endsAt = max(now, max(now, rest.endsAt).addingTimeInterval(delta))
        }
        s.rest = rest
    }

    static func pause(_ s: inout WorkoutState, now: Date) {
        guard s.pausedAt == nil else { return }
        s.pausedAt = now
        if var rest = s.rest {
            rest.frozenRemaining = max(0, rest.endsAt.timeIntervalSince(now))
            s.rest = rest
        }
    }

    static func resume(_ s: inout WorkoutState, now: Date) {
        if let pausedAt = s.pausedAt {
            s.pausedTotal += max(0, now.timeIntervalSince(pausedAt))
            s.pausedAt = nil
        }
        if var rest = s.rest, let frozen = rest.frozenRemaining {
            rest.endsAt = now.addingTimeInterval(max(0, frozen))
            rest.frozenRemaining = nil
            s.rest = rest
        }
    }
}

// MARK: - Undo

private extension WorkoutReducer {
    static func undo(_ s: inout WorkoutState, now: Date) {
        guard let entry = s.undo else { return }
        s.undo = nil
        guard now <= entry.expiresAt else { return }
        switch entry.payload {
        case let .exercise(index, exercise):
            guard !s.exercises.contains(where: { $0.id == exercise.id }) else { return }
            var restored = exercise
            // Its partner may have left the group when it was removed; a group never has a single member.
            if let group = restored.supersetGroup, !s.exercises.contains(where: { $0.supersetGroup == group }) {
                restored.supersetGroup = nil
            }
            let at = max(0, min(index, s.exercises.count))
            s.exercises.insert(restored, at: at)
            s.currentIndex = at
        case let .set(exerciseID, index, set):
            guard let k = s.exerciseIndex(id: exerciseID),
                  !s.exercises.contains(where: { $0.sets.contains(where: { $0.id == set.id }) }) else { return }
            let at = max(0, min(index, s.exercises[k].sets.count))
            s.exercises[k].sets.insert(set, at: at)
        case let .replaced(original):
            // The replacement carries the entry id of the original; if that entry is gone the undo has nothing to swap back.
            guard let k = s.exerciseIndex(id: original.id) else { return }
            let current = s.exercises[k]
            // Swapping back would throw away what was logged on the replacement in the meantime: then the undo is simply spent.
            guard !current.sets.contains(where: { $0.isDone }), current.note.isEmpty else { return }
            var restored = original
            // The superset group is whatever the entry belongs to now (its partner may have been toggled since); a group never has
            // a single member.
            restored.supersetGroup = current.supersetGroup
            s.exercises[k] = restored
            s.currentIndex = k
        }
    }
}
