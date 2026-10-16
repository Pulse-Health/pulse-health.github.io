import Foundation

// MARK: - Presenter

/// Turns a `WorkoutState` into the display-ready `ActiveWorkoutPresentation` (port of `renderVals` in the design's Active.dc.html).
public enum WorkoutPresenter {
    /// Builds the presentation of `state` at `now`; `recovery` supplies the muscle recovery percentages (0...100).
    public static func present(
        _ state: WorkoutState,
        now: Date,
        recovery: RecoveryProvider
    ) -> ActiveWorkoutPresentation {
        let totals = PresenterSupport.totals(of: state)
        let currentIndex = state.clampedIndex
        let diff = TemplateDiff.compute(for: state)

        return ActiveWorkoutPresentation(
            header: makeHeader(state, now: now, totals: totals, currentIndex: currentIndex),
            navigator: makeNavigator(state, currentIndex: currentIndex),
            card: state.currentExercise.map { makeCard($0, state: state, recovery: recovery) },
            dock: makeDock(state, now: now),
            undoText: makeUndoText(state, now: now),
            isEmpty: state.exercises.isEmpty,
            totals: totals,
            finishCheck: makeFinishCheck(totals: totals, diff: diff, templateID: state.templateID)
        )
    }
}

// MARK: - Header, navigator, undo

private extension WorkoutPresenter {
    static func makeHeader(
        _ state: WorkoutState,
        now: Date,
        totals: ActiveWorkoutPresentation.Totals,
        currentIndex: Int
    ) -> ActiveWorkoutPresentation.Header {
        var clock = NumberText.clock(seconds: state.elapsedSeconds(now: now))
        if state.isPaused { clock = "Paused · " + clock }

        let segments = state.exercises.enumerated().map { index, entry in
            ActiveWorkoutPresentation.Segment(
                fraction: entry.sets.isEmpty ? 0 : Double(entry.doneCount) / Double(entry.sets.count),
                isCurrent: index == currentIndex
            )
        }

        let bpm = state.heartRate.flatMap { $0 > 0 ? $0 : nil }
        return ActiveWorkoutPresentation.Header(
            title: state.name,
            clockText: clock,
            isPaused: state.isPaused,
            volumeText: NumberText.thousands(totals.volumeKg),
            setsText: "\(totals.loggedSets) of \(totals.totalSets)",
            heartRateText: bpm.map { String($0) } ?? "–",
            hasHeartRate: bpm != nil,
            segments: segments
        )
    }

    static func makeNavigator(_ state: WorkoutState, currentIndex: Int) -> ActiveWorkoutPresentation.Navigator? {
        guard !state.exercises.isEmpty else { return nil }
        return ActiveWorkoutPresentation.Navigator(
            position: currentIndex + 1,
            total: state.exercises.count,
            canGoPrevious: currentIndex > 0,
            canGoNext: currentIndex < state.exercises.count - 1
        )
    }

    static func makeUndoText(_ state: WorkoutState, now: Date) -> String? {
        guard let undo = state.undo, now <= undo.expiresAt else { return nil }
        return undo.title
    }
}

// MARK: - Card and rows

private extension WorkoutPresenter {
    static func makeCard(
        _ entry: WorkoutExercise,
        state: WorkoutState,
        recovery: RecoveryProvider
    ) -> ActiveWorkoutPresentation.Card {
        let exercise = entry.exercise
        let percent = max(0, min(100, recovery(exercise.muscle)))
        let analysis = PresenterSupport.analyse(entry)
        let level: ActiveWorkoutPresentation.RecoveryLevel = percent >= 80 ? .good : (percent >= 60 ? .fair : .low)

        let weightTitle: String
        switch exercise.tracking {
        case .weightReps: weightTitle = "kg"
        case .repsOnly: weightTitle = "Added"
        case .duration: weightTitle = ""
        }

        let group = entry.supersetGroup.flatMap { $0.isEmpty ? nil : $0 }
        return ActiveWorkoutPresentation.Card(
            exerciseID: entry.id,
            exercise: exercise,
            recoveryPercent: percent,
            recoveryLevel: level,
            supersetLabel: group.map { "Superset " + $0 },
            restSeconds: entry.restSeconds,
            restText: NumberText.rest(seconds: entry.restSeconds),
            note: entry.note,
            weightColumnTitle: weightTitle,
            repsColumnTitle: exercise.tracking == .duration ? "Sec" : "Reps",
            coachTip: state.rest == nil ? PresenterSupport.coachTip(for: entry, baseline: analysis.baseline) : nil,
            rows: makeRows(entry, analysis: analysis.sets)
        )
    }

    static func makeRows(
        _ entry: WorkoutExercise,
        analysis: [PresenterSupport.SetAnalysis]
    ) -> [ActiveWorkoutPresentation.SetRow] {
        let exercise = entry.exercise
        var workingNumber = 0
        var nextFound = false
        var rows: [ActiveWorkoutPresentation.SetRow] = []
        rows.reserveCapacity(entry.sets.count)

        for (index, set) in entry.sets.enumerated() {
            let number: String
            switch set.type {
            case .warmup: number = "W"
            case .drop: number = "D"
            case .failure: number = "F"
            case .normal:
                workingNumber += 1
                number = String(workingNumber)
            }
            let isNext = !set.isDone && !nextFound
            if isNext { nextFound = true }
            let info = analysis[index]

            rows.append(ActiveWorkoutPresentation.SetRow(
                id: set.id,
                number: number,
                type: set.type,
                previousText: PresenterSupport.previousText(exercise, setIndex: index),
                weightText: PresenterSupport.weightText(set, exercise: exercise),
                repsText: String(set.reps),
                weightEditable: exercise.tracksWeight,
                isDone: set.isDone,
                isNext: isNext,
                isPersonalRecord: info.isRecord,
                estimated1RM: info.isRecord ? PresenterSupport.wholeKilograms(info.e1RM) : nil,
                rir: set.rir,
                rirText: set.isDone ? set.rir.map(PresenterSupport.rirText) : nil,
                accessibilityLabel: PresenterSupport.accessibilityLabel(setIndex: index, set: set, exercise: exercise)
            ))
        }
        return rows
    }
}

// MARK: - Rest dock

private extension WorkoutPresenter {
    static func makeDock(_ state: WorkoutState, now: Date) -> ActiveWorkoutPresentation.Dock? {
        guard let rest = state.rest, let entry = state.currentExercise,
              let remaining = PresenterSupport.restRemainingSeconds(state, now: now) else { return nil }

        let finished = remaining == 0
        let total = rest.totalSeconds
        let fraction: Double
        if finished {
            fraction = 1
        } else if total > 0 {
            fraction = max(0, min(1, Double(remaining) / Double(total)))
        } else {
            fraction = 0
        }

        let lastSet = lastLoggedSet(in: state)
        let showsRIR = lastSet.map { $0.isDone && $0.type != .warmup } ?? false
        return ActiveWorkoutPresentation.Dock(
            phase: finished ? .finished : .running,
            remainingSeconds: remaining,
            totalSeconds: total,
            fraction: fraction,
            remainingText: finished ? "Go" : NumberText.rest(seconds: remaining),
            nextSetText: nextSetText(entry),
            showsRIR: showsRIR,
            rirSelection: showsRIR ? lastSet?.rir : nil,
            isPaused: state.isPaused
        )
    }

    /// The set `lastLogged` points at, when it still exists.
    static func lastLoggedSet(in state: WorkoutState) -> LoggedSet? {
        guard let ref = state.lastLogged,
              let entry = state.exercises.first(where: { $0.id == ref.exerciseID }) else { return nil }
        return entry.sets.first(where: { $0.id == ref.setID })
    }

    /// "Next · Set 2 · 82.5 kg × 6" for the first pending set of the card, or "All sets logged".
    static func nextSetText(_ entry: WorkoutExercise) -> String {
        var workingNumber = 0
        for set in entry.sets {
            var number = ""
            switch set.type {
            case .warmup: break
            case .drop: number = "D"
            case .failure: number = "F"
            case .normal:
                workingNumber += 1
                number = String(workingNumber)
            }
            if set.isDone { continue }
            let label = set.type == .warmup ? "Warm-up" : "Set " + number
            return "Next · " + label + " · " + PresenterSupport.workText(set, exercise: entry.exercise)
        }
        return "All sets logged"
    }
}

// MARK: - Finish check

private extension WorkoutPresenter {
    static func makeFinishCheck(
        totals: ActiveWorkoutPresentation.Totals,
        diff: TemplateDiff,
        templateID: UUID?
    ) -> ActiveWorkoutPresentation.FinishCheck {
        let logged = totals.loggedSets
        let unlogged = max(0, totals.totalSets - logged)

        let title = logged == 0 ? "Nothing logged yet" : "Finish workout?"
        let message: String
        if logged == 0 {
            message = "Log at least one set to save this workout."
        } else if unlogged > 0 {
            message = "\(unlogged) " + (unlogged == 1 ? "set is" : "sets are") + " not logged yet and will be left out."
        } else {
            message = "All sets are logged. Nice work."
        }

        return ActiveWorkoutPresentation.FinishCheck(
            loggedSets: logged,
            unloggedSets: unlogged,
            canFinish: logged > 0,
            title: title,
            message: message,
            templateDiff: diff,
            diffMessage: "Changes: " + diff.summary + ".",
            asksToUpdateTemplate: !diff.isEmpty && templateID != nil
        )
    }
}

// MARK: - Shared helpers (presenter, summary and snapshot)

/// Calculations and texts shared by the presenter, the summary builder and the snapshot builder.
enum PresenterSupport {
    /// A personal record must beat the running best by more than this many kilograms of estimated 1RM.
    static let recordMargin = 0.05

    /// Estimated 1RM and personal-record flag of one set.
    struct SetAnalysis: Equatable {
        /// Epley estimate for logged-or-pending non-warm-up sets of weight-tracking exercises, else 0.
        var e1RM: Double
        /// A logged set that beat the running baseline by more than `recordMargin` (never without history).
        var isRecord: Bool
        /// The running baseline the set was measured against: the previous best raised by the logged sets before it. For a record
        /// this is the estimate it beat (the live record moment shows the difference).
        var baselineBefore: Double
    }

    // MARK: Totals

    static func totals(of state: WorkoutState) -> ActiveWorkoutPresentation.Totals {
        var logged = 0
        var all = 0
        var volume = 0.0
        var completed = 0
        for entry in state.exercises {
            all += entry.sets.count
            logged += entry.doneCount
            volume += volumeKg(of: entry)
            if entry.isComplete { completed += 1 }
        }
        return ActiveWorkoutPresentation.Totals(
            loggedSets: logged,
            totalSets: all,
            volumeKg: volume,
            completedExercises: completed
        )
    }

    /// Weight x reps of the logged, non-warm-up sets of a weight-tracking exercise.
    static func volumeKg(of entry: WorkoutExercise) -> Double {
        guard entry.exercise.tracksWeight else { return 0 }
        var volume = 0.0
        for set in entry.sets where set.isDone && set.type.countsTowardVolume {
            volume += set.weightKg * Double(set.reps)
        }
        return volume
    }

    /// Largest whole-kilogram value shown for an estimate; anything above (only possible for a state the reducer did not produce) clamps.
    private static let wholeKilogramLimit = 1_000_000_000.0

    /// A kilogram value rounded to a whole number for display, never trapping: non-finite gives 0, huge values clamp.
    static func wholeKilograms(_ value: Double) -> Int {
        guard value.isFinite else { return 0 }
        return Int(max(-wholeKilogramLimit, min(value.rounded(), wholeKilogramLimit)))
    }

    // MARK: Personal records

    /// Per-set analysis in set order plus the final running baseline (previous best raised by the logged sets).
    ///
    /// The baseline starts at `previousBestE1RM` and rises with every logged set that beats it; without history
    /// (`previousBestE1RM == 0`) no set is flagged.
    static func analyse(_ entry: WorkoutExercise) -> (sets: [SetAnalysis], baseline: Double) {
        let exercise = entry.exercise
        let hasHistory = exercise.previousBestE1RM > 0
        var baseline = max(0, exercise.previousBestE1RM)
        var result: [SetAnalysis] = []
        result.reserveCapacity(entry.sets.count)

        for set in entry.sets {
            var e1RM = exercise.tracksWeight && set.type.countsTowardVolume
                ? Estimated1RM.epley(weightKg: set.weightKg, reps: set.reps)
                : 0
            // A weight so large that the estimate overflows (a state not produced by the reducer) is not a usable estimate.
            if !e1RM.isFinite { e1RM = 0 }
            let isRecord = set.isDone && hasHistory && e1RM > baseline + recordMargin
            let before = baseline
            if set.isDone && e1RM > baseline { baseline = e1RM }
            result.append(SetAnalysis(e1RM: e1RM, isRecord: isRecord, baselineBefore: before))
        }
        return (result, baseline)
    }

    // MARK: Coach tip

    /// "85 kg × 6 on your last set would beat your best estimated 1RM of 99 kg." or nil.
    static func coachTip(for entry: WorkoutExercise, baseline: Double) -> String? {
        let exercise = entry.exercise
        guard exercise.tracksWeight, exercise.previousBestE1RM > 0 else { return nil }
        let pending = entry.sets.filter { !$0.isDone && $0.type != .warmup }
        guard let target = pending.last(where: { $0.type == .normal }) ?? pending.last else { return nil }
        guard target.reps > 0, let weight = lowestBeatingWeight(
            baseline: baseline, reps: target.reps, step: exercise.weightStepKg
        ) else { return nil }
        return NumberText.kg(weight) + " kg × \(target.reps) on your last set would beat your best estimated 1RM of "
            + NumberText.thousands(baseline) + " kg."
    }

    /// The lowest multiple of `step` whose Epley estimate with `reps` exceeds `baseline` by more than the record margin.
    static func lowestBeatingWeight(baseline: Double, reps: Int, step: Double) -> Double? {
        guard baseline.isFinite, baseline > 0, reps > 0, step > 0, step.isFinite else { return nil }
        let threshold = baseline + recordMargin
        func beats(_ weight: Double) -> Bool { Estimated1RM.epley(weightKg: weight, reps: reps) > threshold }

        let minimum = threshold / (1 + Double(reps) / 30)
        var multiples = (minimum / step).rounded(.up)
        guard multiples.isFinite, multiples < 1e9 else { return nil }
        multiples = max(1, multiples)
        // Correct a possible off-by-one from floating point rounding in either direction.
        var guardCount = 0
        while multiples > 1, beats((multiples - 1) * step), guardCount < 8 {
            multiples -= 1
            guardCount += 1
        }
        while !beats(multiples * step), guardCount < 16 {
            multiples += 1
            guardCount += 1
        }
        let weight = multiples * step
        return beats(weight) ? weight : nil
    }

    // MARK: Rest

    /// Whole seconds of rest left (rounded up, frozen while paused); nil without a rest.
    static func restRemainingSeconds(_ state: WorkoutState, now: Date) -> Int? {
        guard let rest = state.rest else { return nil }
        let seconds: TimeInterval
        if let frozen = rest.frozenRemaining {
            seconds = frozen
        } else {
            seconds = rest.endsAt.timeIntervalSince(state.pausedAt ?? now)
        }
        guard seconds.isFinite else { return 0 }
        // A tiny tolerance keeps floating-point noise (95.0000002 s) from showing one second too many.
        let rounded = (max(0, seconds) - 1e-6).rounded(.up)
        return Int(max(0, min(rounded, 1_000_000_000)))
    }

    // MARK: Texts

    /// "RIR 3" or "RIR 4+".
    static func rirText(_ rir: Int) -> String {
        rir >= 4 ? "RIR 4+" : "RIR " + String(max(0, rir))
    }

    /// "82.5" for weight-tracking exercises, "BW" for reps-only, "–" for durations.
    static func weightText(_ set: LoggedSet, exercise: Exercise) -> String {
        switch exercise.tracking {
        case .weightReps: return NumberText.kg(set.weightKg)
        case .repsOnly: return "BW"
        case .duration: return "–"
        }
    }

    /// "82.5 kg × 6", "8 reps" or "45 s": what a set asks for.
    static func workText(_ set: LoggedSet, exercise: Exercise) -> String {
        switch exercise.tracking {
        case .weightReps: return NumberText.kg(set.weightKg) + " kg × \(set.reps)"
        case .repsOnly: return "\(set.reps) reps"
        case .duration: return "\(set.reps) s"
        }
    }

    /// Text for the PREVIOUS column: "80 × 6", "8 reps", "45 s" or "–" without history.
    static func previousText(_ exercise: Exercise, setIndex: Int) -> String {
        guard !exercise.previousSets.isEmpty else { return "–" }
        let previous = exercise.previousSets[min(max(0, setIndex), exercise.previousSets.count - 1)]
        switch exercise.tracking {
        case .weightReps: return NumberText.kg(previous.weightKg) + " × \(previous.reps)"
        case .repsOnly: return "\(previous.reps) reps"
        case .duration: return "\(previous.reps) s"
        }
    }

    /// "Set 3, working set, 82.5 kilograms, 6 reps, logged".
    static func accessibilityLabel(setIndex: Int, set: LoggedSet, exercise: Exercise) -> String {
        let typeName: String
        switch set.type {
        case .normal: typeName = "working set"
        case .warmup: typeName = "warm-up"
        case .drop: typeName = "drop set"
        case .failure: typeName = "failure set"
        }
        var parts = ["Set \(setIndex + 1)", typeName]
        switch exercise.tracking {
        case .weightReps:
            let kg = NumberText.kg(set.weightKg)
            parts.append(kg + (kg == "1" ? " kilogram" : " kilograms"))
            parts.append("\(set.reps)" + (set.reps == 1 ? " rep" : " reps"))
        case .repsOnly:
            parts.append("bodyweight")
            parts.append("\(set.reps)" + (set.reps == 1 ? " rep" : " reps"))
        case .duration:
            parts.append("\(set.reps)" + (set.reps == 1 ? " second" : " seconds"))
        }
        parts.append(set.isDone ? "logged" : "not logged")
        return parts.joined(separator: ", ")
    }
}
