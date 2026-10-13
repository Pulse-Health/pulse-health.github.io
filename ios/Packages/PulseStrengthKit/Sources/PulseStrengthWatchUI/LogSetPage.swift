#if os(watchOS)
import SwiftUI
import PulseStrengthCore

// MARK: - Crown constants

/// The Digital Crown edits the weight in "steps" of `Exercise.weightStepKg`. The crown value itself is only a counter in the
/// middle of a wide range; every whole unit is one step, and the counter is re-centred once the rotation has been sent.
private enum CrownScale {
    static let lower: Double = 0
    static let upper: Double = 2000
    static let center: Double = 1000
    static let recenterDistance: Double = 300
    /// The absolute weight is sent to the phone 0.4 s after the last crown click.
    static let debounceNanoseconds: UInt64 = 400_000_000
}

// MARK: - Round stepper button

@MainActor
private struct WatchStepperButton: View {
    let symbol: String
    let label: String
    let fill: Color
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: { action() }) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(tint)
        }
        .buttonStyle(WatchCircleButtonStyle(fill: fill, diameter: 36))
        .accessibilityLabel(label)
    }
}

// MARK: - Page

/// "Log set": exercise name and elapsed time, "Set 4 of 5", weight and reps with - / + buttons (the weight also with the Digital
/// Crown), and the green "Log set" button. Shows "All sets logged" when nothing is left to do.
@MainActor
struct LogSetPage: View {
    @ObservedObject var controller: WorkoutController
    let snapshot: WorkoutSnapshot
    let date: Date
    /// True while this is the visible page; the Digital Crown only edits the weight then.
    let isSelected: Bool

    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    @State private var crownValue: Double = CrownScale.center
    @State private var crownAnchor: Double = CrownScale.center
    /// Weight chosen with the crown and not yet sent to the phone (shown instead of the snapshot's weight).
    @State private var pendingKg: Double?
    @State private var pendingSet: SetRef?
    @State private var commitTask: Task<Void, Never>?
    @FocusState private var crownFocused: Bool

    private var palette: WatchPalette { WatchPalette(reduced: isLuminanceReduced) }

    private var isComplete: Bool { snapshot.phase == .complete }

    private var crownControlEnabled: Bool {
        isSelected && snapshot.showsWeight && !isComplete
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Spacer(minLength: 2)
            mainBlock
            Spacer(minLength: 4)
            logButtonBlock
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .focusable(crownControlEnabled)
        .focused($crownFocused)
        .digitalCrownRotation(
            $crownValue,
            from: CrownScale.lower,
            through: CrownScale.upper,
            by: 1.0,
            sensitivity: .medium,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
        .onChange(of: crownValue) { _, newValue in
            crownDidChange(to: newValue)
        }
        .onChange(of: crownControlEnabled) { _, enabled in
            crownFocused = enabled
            if !enabled { flushPendingWeight() }
        }
        .onAppear {
            crownFocused = crownControlEnabled
        }
        .onDisappear {
            flushPendingWeight()
        }
    }

    // MARK: Header

    private var headerTitle: String {
        isComplete ? snapshot.workoutName : snapshot.exerciseName
    }

    private var elapsedSeconds: Int {
        WatchFormat.elapsedSeconds(snapshot, at: date)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(headerTitle)
                .font(WatchFont.text(14, .semibold))
                .foregroundStyle(palette.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 4)
            Text(WatchFormat.clockText(elapsedSeconds, coarse: isLuminanceReduced))
                .font(WatchFont.number(14, .semibold))
                .foregroundStyle(snapshot.isPaused ? palette.secondary : palette.primary)
                .lineLimit(1)
                .accessibilityLabel(snapshot.isPaused ? "Elapsed time, paused" : "Elapsed time")
                .accessibilityValue(WatchFormat.spoken(seconds: elapsedSeconds))
        }
        .padding(.horizontal, 4)
    }

    // MARK: Main block

    @ViewBuilder
    private var mainBlock: some View {
        if isComplete {
            completeBlock
        } else {
            VStack(spacing: 4) {
                Text(snapshot.setLabel)
                    .font(WatchFont.text(12.5, .regular))
                    .foregroundStyle(palette.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if snapshot.showsWeight {
                    weightRow
                }
                repsRow
            }
        }
    }

    private var completeBlock: some View {
        VStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 36, weight: .regular))
                .foregroundStyle(palette.accent)
                .accessibilityHidden(true)
            Text("All sets logged")
                .font(WatchFont.text(16, .semibold))
                .foregroundStyle(palette.primary)
                .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Weight

    private var weightString: String {
        if let pendingKg { return NumberText.kg(pendingKg) }
        return snapshot.weightText
    }

    private var weightRow: some View {
        HStack(spacing: 0) {
            WatchStepperButton(
                symbol: "minus",
                label: "Decrease weight",
                fill: palette.controlFill,
                tint: palette.primary
            ) {
                nudge(weightSteps: -1, repsSteps: 0)
            }
            Spacer(minLength: 2)
            weightValue
            Spacer(minLength: 2)
            WatchStepperButton(
                symbol: "plus",
                label: "Increase weight",
                fill: palette.controlFill,
                tint: palette.primary
            ) {
                nudge(weightSteps: 1, repsSteps: 0)
            }
        }
    }

    private var weightValue: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(weightString)
                .font(WatchFont.number(32, .bold))
                .tracking(-0.8)
                .foregroundStyle(palette.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
            Text("kg")
                .font(WatchFont.text(14, .semibold))
                .foregroundStyle(palette.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Weight")
        .accessibilityValue("\(weightString) kilograms")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                nudge(weightSteps: 1, repsSteps: 0)
            case .decrement:
                nudge(weightSteps: -1, repsSteps: 0)
            @unknown default:
                break
            }
        }
    }

    // MARK: Reps

    private var repsUnitSpoken: String {
        snapshot.repsUnit == "sec" ? "seconds" : "reps"
    }

    private var repsNumberText: String {
        if snapshot.showsWeight { return "× " + snapshot.repsText }
        return snapshot.repsText
    }

    /// With a weight above, reps are the smaller "× 6" line of the design; without one they are the main number.
    private var repsNumberSize: CGFloat { snapshot.showsWeight ? 20 : 32 }

    private var repsNumberWeight: Font.Weight { snapshot.showsWeight ? Font.Weight.semibold : Font.Weight.bold }

    private var repsUnitSize: CGFloat { snapshot.showsWeight ? 12.5 : 14 }

    private var repsRow: some View {
        HStack(spacing: 0) {
            WatchStepperButton(
                symbol: "minus",
                label: "Decrease reps",
                fill: palette.controlFill,
                tint: palette.primary
            ) {
                nudge(weightSteps: 0, repsSteps: -1)
            }
            Spacer(minLength: 2)
            repsValue
            Spacer(minLength: 2)
            WatchStepperButton(
                symbol: "plus",
                label: "Increase reps",
                fill: palette.controlFill,
                tint: palette.primary
            ) {
                nudge(weightSteps: 0, repsSteps: 1)
            }
        }
    }

    private var repsValue: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(repsNumberText)
                .font(WatchFont.number(repsNumberSize, repsNumberWeight))
                .foregroundStyle(palette.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(snapshot.repsUnit)
                .font(WatchFont.text(repsUnitSize, .semibold))
                .foregroundStyle(palette.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(snapshot.repsUnit == "sec" ? "Duration" : "Reps")
        .accessibilityValue("\(snapshot.repsText) \(repsUnitSpoken)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                nudge(weightSteps: 0, repsSteps: 1)
            case .decrement:
                nudge(weightSteps: 0, repsSteps: -1)
            @unknown default:
                break
            }
        }
    }

    // MARK: Log set

    private var logButtonForeground: Color {
        isLuminanceReduced ? palette.accent : palette.onAccent
    }

    private var logButtonStyle: WatchCapsuleButtonStyle {
        WatchCapsuleButtonStyle(
            fill: isLuminanceReduced ? Color.clear : WatchTheme.green,
            outline: isLuminanceReduced ? palette.accent : Color.clear,
            outlineWidth: isLuminanceReduced ? 1.5 : 0,
            height: 43
        )
    }

    @ViewBuilder
    private var logButtonBlock: some View {
        if !isComplete {
            Button(action: { logSet() }) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .heavy))
                    Text("Log set")
                        .font(WatchFont.text(15.5, .semibold))
                }
                .foregroundStyle(logButtonForeground)
            }
            .buttonStyle(logButtonStyle)
            .accessibilityLabel("Log set")
            .accessibilityHint(snapshot.setLabel)
        }
    }

    // MARK: Actions

    /// The set a "Log set" tap would log, read from the live snapshot, with its current weight and step.
    private struct LiveTarget {
        let ref: SetRef
        let weightKg: Double
        let stepKg: Double
    }

    private func liveTarget() -> LiveTarget? {
        guard let live = controller.snapshot(now: Date()),
              let exerciseID = live.targetExerciseID,
              let setID = live.targetSetID,
              let state = controller.state,
              let entry = state.exercises.first(where: { $0.id == exerciseID }),
              let set = entry.sets.first(where: { $0.id == setID })
        else { return nil }
        return LiveTarget(
            ref: SetRef(exerciseID: exerciseID, setID: setID),
            weightKg: set.weightKg,
            stepKg: entry.exercise.weightStepKg
        )
    }

    /// - / + buttons: the phone moves the next pending set by one step.
    private func nudge(weightSteps: Int, repsSteps: Int) {
        flushPendingWeight()
        controller.send(.nudgeNextSet(weightSteps: weightSteps, repsSteps: repsSteps), origin: .watch)
        WatchHaptics.click()
    }

    private func logSet() {
        flushPendingWeight()
        guard let target = liveTarget() else { return }
        controller.send(.logSet(exerciseID: target.ref.exerciseID, setID: target.ref.setID), origin: .watch)
        WatchHaptics.success()
    }

    // MARK: Digital Crown

    /// Every whole crown unit is one weight step. The new weight is shown at once and sent after 0.4 s without rotation.
    private func crownDidChange(to value: Double) {
        let steps = Int((value - crownAnchor).rounded())
        guard steps != 0 else { return }
        crownAnchor += Double(steps)
        guard crownControlEnabled, let target = liveTarget() else { return }
        if let pendingSet, pendingSet != target.ref {
            // The target moved on (for example the phone logged the set): the old pending weight no longer applies.
            pendingKg = nil
        }
        let base = pendingKg ?? target.weightKg
        let raw = base + Double(steps) * target.stepKg
        let next = max(0, (raw * 100).rounded() / 100)
        pendingKg = next
        pendingSet = target.ref
        scheduleCommit()
    }

    private func scheduleCommit() {
        commitTask?.cancel()
        commitTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: CrownScale.debounceNanoseconds)
            if Task.isCancelled { return }
            commitPendingWeight()
        }
    }

    /// Sends the pending crown weight now (before a button press, when the page is left, or when the debounce expires).
    private func flushPendingWeight() {
        commitTask?.cancel()
        commitPendingWeight()
    }

    private func commitPendingWeight() {
        commitTask = nil
        guard let kg = pendingKg, let ref = pendingSet else {
            pendingKg = nil
            pendingSet = nil
            return
        }
        pendingKg = nil
        pendingSet = nil
        if let target = liveTarget(), target.ref == ref, target.weightKg != kg {
            controller.send(.setWeight(exerciseID: ref.exerciseID, setID: ref.setID, kg: kg), origin: .watch)
        }
        recenterCrownIfNeeded()
    }

    private func recenterCrownIfNeeded() {
        guard abs(crownValue - CrownScale.center) > CrownScale.recenterDistance else { return }
        crownAnchor = CrownScale.center
        crownValue = CrownScale.center
    }
}
#endif
