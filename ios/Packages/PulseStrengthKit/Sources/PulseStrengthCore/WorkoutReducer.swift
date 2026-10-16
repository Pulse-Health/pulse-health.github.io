import Foundation

/// The only code that applies a `WorkoutAction` to a `WorkoutState` (port of the design's Active.dc.html logic).
public enum WorkoutReducer {
    /// How long a removed exercise or deleted set can be restored with `.undo` (6 seconds).
    public static var undoWindow: TimeInterval { 6 }

    /// Heaviest weight a set can hold (1,000,000 kg). Larger values are clamped to it; the keypad's six characters stay below it.
    public static let maximumWeightKg: Double = 1_000_000

    /// Lightest weight a set can hold: an assisted load of a reps-only exercise that allows added weight (`Exercise.carriesLoad`) goes
    /// down to -300 kg. Every other set keeps weights of 0 or more.
    public static let minimumWeightKg: Double = -300

    /// Longest rest an exercise can be given (one hour). Larger values are clamped to it; the rest presets stop at 5:00.
    public static let maximumRestSeconds: Int = 3_600

    /// Most reps a set can hold (999). Larger values are clamped to it.
    public static let maximumReps: Int = 999

    /// Most seconds a timed set can hold (10,800: three hours). A set of an exercise that tracks duration stores seconds in `reps`.
    public static let maximumDurationSeconds: Int = 10_800

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

// MARK: - Weight storage

extension WorkoutReducer {
    /// Weight clamped to 0...`maximumWeightKg` (`minimumWeightKg`...`maximumWeightKg` with `allowsNegative`) and rounded to 0.01 kg, the way
    /// a set stores it; nil (ignored) for NaN and +infinity. A result of zero is never negative zero.
    static func roundedWeight(_ kg: Double, allowsNegative: Bool = false) -> Double? {
        guard !kg.isNaN else { return nil }
        let lowerBounded = max(allowsNegative ? minimumWeightKg : 0, kg)
        guard lowerBounded.isFinite else { return nil }
        let rounded = (min(lowerBounded, maximumWeightKg) * 100).rounded(.toNearestOrAwayFromZero) / 100
        return rounded == 0 ? 0 : rounded
    }

    /// The name of the superset group at `index`: A...Z, then AA, AB, ... AZ, BA, ... (the way spreadsheet columns are named).
    static func groupName(at index: Int) -> String {
        let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        var remaining = index + 1
        var name: [Character] = []
        while remaining > 0 {
            name.append(letters[(remaining - 1) % letters.count])
            remaining = (remaining - 1) / letters.count
        }
        return String(name.reversed())
    }

    /// Whole seconds of `elapsed` (rounded down), within 0...`maximumDurationSeconds`; a time that is not finite counts as 0 (NaN) or the
    /// maximum (+infinity).
    static func wholeSeconds(_ elapsed: TimeInterval) -> Int {
        guard !elapsed.isNaN else { return 0 }
        return Int(max(0, min(elapsed.rounded(.down), Double(maximumDurationSeconds))))
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
            guard let (k, i) = locate(s, exerciseID, setID),
                  let value = roundedWeight(kg, allowsNegative: s.exercises[k].exercise.carriesLoad) else { return }
            s.exercises[k].sets[i].weightKg = value
        case let .setReps(exerciseID, setID, reps):
            guard let (k, i) = locate(s, exerciseID, setID) else { return }
            s.exercises[k].sets[i].reps = clampReps(reps, for: s.exercises[k].exercise)
            followTarget(&s, exerciseIndex: k, setIndex: i)
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

        case let .startTimedSet(ref):
            startTimedSet(&s, ref, now: now)
        case .stopTimedSet:
            stopTimedSet(&s, now: now)
        case .cancelTimedSet:
            s.timedSet = nil

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
            replaceExercise(&s, exerciseID: exerciseID, with: replacement)
        case let .toggleSuperset(exerciseID):
            toggleSuperset(&s, exerciseID: exerciseID, now: now)
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
        case let .setWeightUnit(unit):
            s.settings.weightUnit = unit

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

    /// Reps clamped to 0...`maximumReps`, or to 0...`maximumDurationSeconds` for an exercise that tracks duration (seconds).
    static func clampReps(_ reps: Int, for exercise: Exercise) -> Int {
        max(0, min(reps, exercise.tracking == .duration ? maximumDurationSeconds : maximumReps))
    }

    static func clampRIR(_ value: Int) -> Int { max(0, min(value, 4)) }

    static func clampRest(_ seconds: Int) -> Int { max(0, min(seconds, maximumRestSeconds)) }

    static func saturatingSum(_ a: Int, _ b: Int) -> Int {
        let (sum, overflow) = a.addingReportingOverflow(b)
        if !overflow { return sum }
        return b > 0 ? Int.max : Int.min
    }

    /// The weight and reps a new set of `exercise` starts with: those of the last working set of its previous session when there is
    /// one (a trailing drop set is skipped when an earlier working set exists: its lighter load is not where the next session
    /// starts), else the library defaults. Warm-ups are never copied. A weight is copied only when the exercise has an editable one
    /// (`Exercise.hasEditableWeight`): reps-only and timed exercises take the reps (seconds) only.
    static func startingValues(for exercise: Exercise) -> (weightKg: Double, reps: Int) {
        let allowsNegative = exercise.carriesLoad
        let defaults = exercise.defaults
        let defaultWeight = roundedWeight(defaults.weightKg, allowsNegative: allowsNegative) ?? 0
        let defaultReps = clampReps(defaults.reps, for: exercise)
        let working = exercise.previousSets.filter { !$0.isWarmup && $0.reps > 0 }
        guard let last = working.last(where: { $0.type != .drop }) ?? working.last else { return (defaultWeight, defaultReps) }
        let weight = exercise.hasEditableWeight ? (roundedWeight(last.weightKg, allowsNegative: allowsNegative) ?? defaultWeight) : defaultWeight
        return (weight, clampReps(last.reps, for: exercise))
    }

    /// Fresh pending sets for an exercise: `defaults.sets` of them, from the last working set of its previous session or the defaults.
    static func defaultSets(for exercise: Exercise) -> [LoggedSet] {
        let values = startingValues(for: exercise)
        return (0..<max(0, exercise.defaults.sets)).map { _ in
            LoggedSet(type: .normal, weightKg: values.weightKg, reps: values.reps)
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
    /// Marks a pending set done and applies the follow-up: last logged, superset advance, rest start.
    ///
    /// Superset: the next member of the group by exercise order becomes the current exercise and no rest starts; after the last
    /// member the first one is current again and the rest starts. The members need not be next to each other. While a timed set
    /// runs (another one than this) no rest starts.
    static func markDone(_ s: inout WorkoutState, exerciseIndex k: Int, setIndex i: Int, now: Date) {
        let entry = s.exercises[k]
        let set = entry.sets[i]
        s.exercises[k].sets[i].isDone = true
        s.lastLogged = SetRef(exerciseID: entry.id, setID: set.id)
        if s.timedSet?.setRef.setID == set.id { s.timedSet = nil }
        var seconds = RestRules.seconds(afterSetAt: i, types: entry.sets.map { $0.type }, exerciseRest: entry.restSeconds)
        if let group = entry.supersetGroup {
            let members = memberIndices(s, of: group)
            if let next = members.first(where: { $0 > k }) {
                s.currentIndex = next
                seconds = 0
            } else if let first = members.first {
                s.currentIndex = first
            }
        }
        if s.timedSet != nil { seconds = 0 }
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
        if weightSteps != 0, exercise.hasEditableWeight, set.weightKg.isFinite {
            // The step is added to the stored kilograms, so that a step up and a step down return to the very same stored weight. Where
            // the rounding to 0.01 kg would make the shown weight miss the step (about every tenth step in pounds), the step is taken
            // from the shown weight instead, so that repeated steps never drift away from it.
            let unit = s.settings.weightUnit
            let delta = Double(max(-1000, min(1000, weightSteps))) * exercise.weightStep(in: unit)
            let target = unit.displayValue(kg: set.weightKg) + delta
            let added = roundedWeight(set.weightKg + unit.toKg(delta), allowsNegative: exercise.carriesLoad)
            if let added, abs(unit.displayValue(kg: added) - target) < 1e-6 {
                set.weightKg = added
            } else {
                set.weightKg = roundedWeight(unit.toKg(target), allowsNegative: exercise.carriesLoad) ?? set.weightKg
            }
        }
        if repsSteps != 0 {
            let steps = max(-1000, min(1000, repsSteps))
            set.reps = clampReps(saturatingSum(set.reps, steps * exercise.repsStep), for: exercise)
        }
        s.exercises[k].sets[i] = set
        followTarget(&s, exerciseIndex: k, setIndex: i)
    }

    static func toggleLastSetRIR(_ s: inout WorkoutState, _ value: Int) {
        guard let ref = s.lastLogged, let (k, i) = locate(s, ref.exerciseID, ref.setID) else { return }
        let clamped = clampRIR(value)
        s.exercises[k].sets[i].rir = s.exercises[k].sets[i].rir == clamped ? nil : clamped
    }
}

// MARK: - Timed sets

private extension WorkoutReducer {
    /// Starts timing a pending set of a duration exercise; ignored for anything else and while another timed set runs.
    static func startTimedSet(_ s: inout WorkoutState, _ ref: SetRef, now: Date) {
        guard s.timedSet == nil, let (k, i) = locate(s, ref.exerciseID, ref.setID),
              s.exercises[k].exercise.tracking == .duration, !s.exercises[k].sets[i].isDone else { return }
        s.currentIndex = k
        s.rest = nil
        s.timedSet = TimedSetState(
            setRef: ref,
            startedAt: now,
            targetSeconds: s.exercises[k].sets[i].reps,
            frozenElapsed: s.isPaused ? 0 : nil
        )
    }

    /// Logs the timed set with the seconds timed so far, then behaves like `logSet`. A timer whose set is gone (deleted, replaced) or
    /// already logged just ends.
    static func stopTimedSet(_ s: inout WorkoutState, now: Date) {
        guard let timed = s.timedSet else { return }
        s.timedSet = nil
        guard let (k, i) = locate(s, timed.setRef.exerciseID, timed.setRef.setID), !s.exercises[k].sets[i].isDone else { return }
        s.exercises[k].sets[i].reps = clampReps(wholeSeconds(timed.elapsed(now: now)), for: s.exercises[k].exercise)
        markDone(&s, exerciseIndex: k, setIndex: i, now: now)
    }

    /// Keeps the target of the running timed set equal to the seconds of the set when the set is edited while it runs.
    static func followTarget(_ s: inout WorkoutState, exerciseIndex k: Int, setIndex i: Int) {
        guard var timed = s.timedSet, timed.setRef.setID == s.exercises[k].sets[i].id else { return }
        timed.targetSeconds = s.exercises[k].sets[i].reps
        s.timedSet = timed
    }

    /// Ends the timed set when its set (`setID`) or its exercise (`exerciseID`) is gone.
    static func dropTimedSet(_ s: inout WorkoutState, setID: UUID? = nil, exerciseID: UUID? = nil) {
        guard let ref = s.timedSet?.setRef else { return }
        if ref.setID == setID || ref.exerciseID == exerciseID { s.timedSet = nil }
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
            let values = startingValues(for: entry.exercise)
            weight = values.weightKg
            reps = values.reps
        }
        s.exercises[k].sets.append(LoggedSet(type: .normal, weightKg: weight, reps: reps, isDone: false, rir: nil))
    }

    static func deleteSet(_ s: inout WorkoutState, exerciseID: UUID, setID: UUID, now: Date) {
        guard let (k, i) = locate(s, exerciseID, setID) else { return }
        let removed = s.exercises[k].sets.remove(at: i)
        if s.lastLogged?.setID == setID { s.lastLogged = nil }
        dropTimedSet(&s, setID: setID)
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

    /// The positions of the exercises in `group`, ascending.
    static func memberIndices(_ s: WorkoutState, of group: String) -> [Int] {
        s.exercises.indices.filter { s.exercises[$0].supersetGroup == group }
    }

    /// True when `indices` (ascending, distinct) have no gap.
    static func isContiguous(_ indices: [Int]) -> Bool {
        guard let first = indices.first, let last = indices.last else { return true }
        return last - first == indices.count - 1
    }

    /// When a superset group is left with a single member, that member leaves the group too.
    static func releaseOrphan(_ s: inout WorkoutState, group: String?) {
        guard let group else { return }
        let members = memberIndices(s, of: group)
        if members.count == 1 { s.exercises[members[0]].supersetGroup = nil }
    }

    static func removeExercise(_ s: inout WorkoutState, exerciseID: UUID, now: Date) {
        guard let at = s.exerciseIndex(id: exerciseID) else { return }
        let removed = s.exercises.remove(at: at)
        releaseOrphan(&s, group: removed.supersetGroup)
        if at < s.currentIndex { s.currentIndex -= 1 }
        s.currentIndex = clampIndex(s.currentIndex, count: s.exercises.count)
        if s.lastLogged?.exerciseID == removed.id { s.lastLogged = nil }
        dropTimedSet(&s, exerciseID: removed.id)
        s.undo = UndoEntry(
            payload: .exercise(index: at, exercise: removed),
            title: "Removed " + removed.exercise.name,
            expiresAt: now.addingTimeInterval(undoWindow)
        )
    }

    /// Moves the exercise at `from` so it ends up at `to`; the current exercise stays selected. The members of a superset stay next
    /// to each other (see `keepGroupsTogether`).
    static func moveExercise(_ s: inout WorkoutState, from: Int, to: Int) {
        let count = s.exercises.count
        guard from >= 0, from < count, to >= 0, to < count, from != to else { return }
        let currentID = s.exercises[s.clampedIndex].id
        let movedID = s.exercises[from].id
        let item = s.exercises.remove(at: from)
        s.exercises.insert(item, at: to)
        keepGroupsTogether(&s, movedID: movedID, movedDown: to > from)
        if let index = s.exercises.firstIndex(where: { $0.id == currentID }) { s.currentIndex = index }
    }

    /// Restores the rule that the members of a superset group are next to each other after the exercise `movedID` was moved:
    /// * when the move split the moved exercise's own group, the exercise leaves it (a partner left alone leaves too, as in
    ///   `removeExercise`);
    /// * when the exercise landed between the members of another group it goes to the end of that group's block when it moved
    ///   down and to its start when it moved up (and leaves its own group first, which only happens in a state that already broke
    ///   the rule).
    static func keepGroupsTogether(_ s: inout WorkoutState, movedID: UUID, movedDown: Bool) {
        guard let at = s.exercises.firstIndex(where: { $0.id == movedID }) else { return }
        if let group = s.exercises[at].supersetGroup, !isContiguous(memberIndices(s, of: group)) {
            s.exercises[at].supersetGroup = nil
            releaseOrphan(&s, group: group)
        }
        // Each pass moves the exercise out of one block; a block that is next to another cannot hold it again, and the count bounds
        // the passes for a state that broke the rule before.
        for _ in 0..<s.exercises.count {
            guard let position = s.exercises.firstIndex(where: { $0.id == movedID }),
                  let block = enclosingBlock(s, around: position) else { return }
            if let own = s.exercises[position].supersetGroup {
                s.exercises[position].supersetGroup = nil
                releaseOrphan(&s, group: own)
            }
            let item = s.exercises.remove(at: position)
            s.exercises.insert(item, at: movedDown ? block.last : block.first)
        }
    }

    /// The first and last position of the first group (other than the exercise's own) whose members are on both sides of `position`.
    static func enclosingBlock(_ s: WorkoutState, around position: Int) -> (first: Int, last: Int)? {
        let own = s.exercises[position].supersetGroup
        var seen = Set<String>()
        for entry in s.exercises {
            guard let group = entry.supersetGroup, group != own, seen.insert(group).inserted else { continue }
            let members = memberIndices(s, of: group)
            if let first = members.first, let last = members.last, first < position, position < last { return (first, last) }
        }
        return nil
    }

    static func replaceExercise(_ s: inout WorkoutState, exerciseID: UUID, with replacement: Exercise) {
        guard let k = s.exerciseIndex(id: exerciseID) else { return }
        let old = s.exercises[k]
        s.exercises[k] = makeEntry(for: replacement, id: old.id, group: old.supersetGroup, templateEntryID: old.templateEntryID)
        if s.lastLogged?.exerciseID == old.id { s.lastLogged = nil }
        dropTimedSet(&s, exerciseID: old.id)
        // A deleted set of the old exercise no longer fits the new one.
        if let undo = s.undo, case let .set(undoExerciseID, _, _) = undo.payload, undoExerciseID == old.id {
            s.undo = nil
        }
    }

    /// In a group -> leaves it; otherwise joins the NEXT exercise (no next -> no-op). When the leaving exercise is in the middle of
    /// its group, the members after it become a group of their own, so that the members of every group stay next to each other.
    static func toggleSuperset(_ s: inout WorkoutState, exerciseID: UUID, now: Date) {
        guard let k = s.exerciseIndex(id: exerciseID) else { return }
        if let group = s.exercises[k].supersetGroup {
            leaveSuperset(&s, at: k, group: group, now: now)
            return
        }
        guard k + 1 < s.exercises.count else { return }
        let group = s.exercises[k + 1].supersetGroup ?? freeGroup(s, now: now)
        s.exercises[k].supersetGroup = group
        s.exercises[k + 1].supersetGroup = group
    }

    static func leaveSuperset(_ s: inout WorkoutState, at k: Int, group: String, now: Date) {
        s.exercises[k].supersetGroup = nil
        let after = memberIndices(s, of: group).filter { $0 > k }
        let before = memberIndices(s, of: group).filter { $0 < k }
        if !before.isEmpty, !after.isEmpty {
            let tail = freeGroup(s, now: now)
            for index in after { s.exercises[index].supersetGroup = tail }
            releaseOrphan(&s, group: tail)
        }
        releaseOrphan(&s, group: group)
    }

    /// The first group name (see `groupName(at:)`) that no exercise uses and that the exercise of a removal that can still be undone
    /// does not carry: a name handed out again in the meantime would put the restored exercise into a superset it was never in.
    static func freeGroup(_ s: WorkoutState, now: Date) -> String {
        var used = Set(s.exercises.compactMap { $0.supersetGroup })
        if let undo = s.undo, now <= undo.expiresAt, case let .exercise(_, removed) = undo.payload, let group = removed.supersetGroup {
            used.insert(group)
        }
        var index = 0
        while used.contains(groupName(at: index)) { index += 1 }
        return groupName(at: index)
    }
}

// MARK: - Rest timer and pause

private extension WorkoutReducer {
    static func adjustRest(_ s: inout WorkoutState, seconds: Int, now: Date) {
        guard var rest = s.rest else {
            // A rest never starts while a timed set runs.
            guard seconds > 0, s.timedSet == nil else { return }
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
        if var timed = s.timedSet {
            timed.frozenElapsed = timed.elapsed(now: now)
            s.timedSet = timed
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
        if var timed = s.timedSet, let frozen = timed.frozenElapsed {
            timed.startedAt = now.addingTimeInterval(-max(0, frozen))
            timed.frozenElapsed = nil
            s.timedSet = timed
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
            // The exercises may have been moved in the meantime: it rejoins its group only when that keeps the group together, and
            // when it lands inside the block of another group it goes to the end of that block.
            keepGroupsTogether(&s, movedID: restored.id, movedDown: true)
            s.currentIndex = s.exerciseIndex(id: restored.id) ?? at
        case let .set(exerciseID, index, set):
            guard let k = s.exerciseIndex(id: exerciseID),
                  !s.exercises.contains(where: { $0.sets.contains(where: { $0.id == set.id }) }) else { return }
            let at = max(0, min(index, s.exercises[k].sets.count))
            s.exercises[k].sets.insert(set, at: at)
        }
    }
}
