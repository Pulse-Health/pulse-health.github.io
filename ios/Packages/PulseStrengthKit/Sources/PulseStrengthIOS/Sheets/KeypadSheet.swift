#if os(iOS)
import SwiftUI
import UIKit
import PulseStrengthCore

// MARK: - Sheet

/// The weight / reps keypad of one set (Active.dc.html, `sh.keypad`).
///
/// Layout, top to bottom: title bar ("Set 4 · Barbell Bench Press" + Done), the two value cards (the edited one
/// highlighted), the -/+ steppers around the "Use last" button, the plate chips (barbell exercises only), the
/// 3 x 4 keypad and the primary button ("Next: Reps" / "Log Set" / "Done").
///
/// The text buffer lives here. After every key press, stepper tap or "Use last" the parsed value is dispatched
/// (`.setWeight` / `.setReps`), so the workout, the Live Activity and the Watch always show what is typed.
/// The set itself is always read live from the controller. A fresh buffer (just opened, just stepped, just
/// switched field) is replaced by the first digit, exactly like the design.
@MainActor
public struct KeypadSheet: View {
    @ObservedObject private var controller: WorkoutController
    private let ref: SetRef

    @Environment(\.dismiss) private var dismiss

    /// The value being edited.
    @State private var field: KeypadField
    /// The text of the edited value ("82.", "0", "12"). At most 6 characters; a weight has at most 2 decimals and
    /// reps stay within 0...`repsLimit` (999 reps, 10,800 seconds), so the card always shows what the reducer stores.
    @State private var buffer: String
    /// True until the next key press: the first digit replaces the whole buffer.
    @State private var isFresh: Bool

    public init(controller: WorkoutController, ref: SetRef, initialField: KeypadField) {
        self._controller = ObservedObject(wrappedValue: controller)
        self.ref = ref
        let found = KeypadSheet.lookup(ref, in: controller.state)
        var startField = initialField
        if let found = found, !found.exercise.exercise.tracksWeight {
            startField = .reps
        }
        self._field = State(initialValue: startField)
        self._buffer = State(initialValue: KeypadSheet.text(for: startField, in: found))
        self._isFresh = State(initialValue: true)
    }

    // MARK: Body

    public var body: some View {
        VStack(spacing: 0) {
            KeypadSheetHeader(title: titleText, onDone: { dismiss() })
            ViewThatFits(in: .vertical) {
                panel
                ScrollView {
                    panel
                }
                .scrollIndicators(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(PulseTheme.ground.ignoresSafeArea())
        .dynamicTypeSize(PulseDynamicType.activeWorkoutRange)
        .sheetDetentsHuggingContent(titleBarHeight: 56, estimate: estimatedSheetHeight)
        .onAppear {
            if target == nil {
                dismiss()
            }
        }
        .onChange(of: target == nil) { _, isMissing in
            if isMissing {
                dismiss()
            }
        }
    }

    @ViewBuilder
    private var panel: some View {
        if let current = target {
            VStack(spacing: 12) {
                valueCards(current)
                stepperRow(current)
                if current.exercise.exercise.supportsPlates {
                    plateRow(current)
                }
                keypadGrid
                primaryButton(current)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 16)
            .reportsSheetPanelHeight()
        } else {
            Color.clear.frame(height: 1)
        }
    }

    /// The detent height used until the panel has been measured: title bar plus panel, 584 pt with the plate row
    /// and 526 pt without it (the system adds the bottom safe area to a `.height` detent).
    private var estimatedSheetHeight: CGFloat {
        if let current = target, !current.exercise.exercise.supportsPlates {
            return 526
        }
        return 584
    }

    // MARK: Live data

    /// The set being edited, read from the controller on every render.
    private var target: KeypadTarget? {
        KeypadSheet.lookup(ref, in: controller.state)
    }

    private var titleText: String {
        guard let current = target else { return "Edit set" }
        return "Set " + String(current.index + 1) + " · " + current.exercise.exercise.name
    }

    private static func lookup(_ ref: SetRef, in state: WorkoutState?) -> KeypadTarget? {
        guard let state = state,
              let exercise = state.exercises.first(where: { $0.id == ref.exerciseID }),
              let index = exercise.sets.firstIndex(where: { $0.id == ref.setID }) else {
            return nil
        }
        return KeypadTarget(exercise: exercise, set: exercise.sets[index], index: index)
    }

    /// The text a field starts with: the set's current value.
    private static func text(for field: KeypadField, in target: KeypadTarget?) -> String {
        guard let target = target else { return "0" }
        switch field {
        case .weight:
            return NumberText.kg(target.set.weightKg)
        case .reps:
            return String(target.set.reps)
        }
    }

    // MARK: Value cards

    private func valueCards(_ current: KeypadTarget) -> some View {
        HStack(spacing: 10) {
            KeypadValueCard(
                label: "KG",
                text: cardText(.weight, current),
                isSelected: field == .weight,
                isEnabled: current.exercise.exercise.tracksWeight,
                accessibilityName: "Weight",
                accessibilityValueText: spokenValue(.weight, current),
                action: { selectField(.weight, current) }
            )
            KeypadValueCard(
                label: repsLabel(current),
                text: cardText(.reps, current),
                isSelected: field == .reps,
                isEnabled: true,
                accessibilityName: repsNoun(current).capitalized,
                accessibilityValueText: spokenValue(.reps, current),
                action: { selectField(.reps, current) }
            )
        }
    }

    private func repsLabel(_ current: KeypadTarget) -> String {
        current.exercise.exercise.tracking == .duration ? "SECONDS" : "REPS"
    }

    private func repsNoun(_ current: KeypadTarget) -> String {
        current.exercise.exercise.tracking == .duration ? "seconds" : "reps"
    }

    /// What a card shows: the live buffer for the edited field, the set's value for the other one.
    private func cardText(_ which: KeypadField, _ current: KeypadTarget) -> String {
        if which == field {
            return buffer
        }
        switch which {
        case .weight:
            switch current.exercise.exercise.tracking {
            case .weightReps:
                return NumberText.kg(current.set.weightKg)
            case .repsOnly:
                return "BW"
            case .duration:
                return "–"
            }
        case .reps:
            return String(current.set.reps)
        }
    }

    private func spokenValue(_ which: KeypadField, _ current: KeypadTarget) -> String {
        let text = cardText(which, current)
        switch which {
        case .weight:
            switch current.exercise.exercise.tracking {
            case .weightReps:
                return text + " kilograms"
            case .repsOnly:
                return "Bodyweight"
            case .duration:
                return "Not used"
            }
        case .reps:
            return text + " " + repsNoun(current)
        }
    }

    private func selectField(_ which: KeypadField, _ current: KeypadTarget) {
        if which == .weight && !current.exercise.exercise.tracksWeight {
            return
        }
        KeypadHaptics.select()
        field = which
        buffer = KeypadSheet.text(for: which, in: current)
        isFresh = true
    }

    // MARK: Steppers and "Use last"

    private func stepperRow(_ current: KeypadTarget) -> some View {
        HStack(spacing: 8) {
            KeypadStepButton(
                systemName: "minus",
                accessibilityName: "Decrease " + fieldNoun(current),
                action: { step(-1, current) }
            )
            useLastButton(current)
            KeypadStepButton(
                systemName: "plus",
                accessibilityName: "Increase " + fieldNoun(current),
                action: { step(1, current) }
            )
        }
    }

    private func fieldNoun(_ current: KeypadTarget) -> String {
        field == .weight ? "weight" : repsNoun(current)
    }

    private func useLastButton(_ current: KeypadTarget) -> some View {
        let previous = previousSet(for: current)
        return Button {
            useLast(current)
        } label: {
            KeypadUseLastLabel(text: useLastText(current, previous))
        }
        .buttonStyle(PulsePlainButtonStyle())
        .disabled(previous == nil)
    }

    /// The set of the last session that the PREVIOUS column shows for this set (warm-ups with warm-ups, working sets with working
    /// sets); nil when the last session had no such set.
    private func previousSet(for current: KeypadTarget) -> PreviousSet? {
        current.exercise.matchedPreviousSet(at: current.index)
    }

    private func useLastText(_ current: KeypadTarget, _ previous: PreviousSet?) -> String {
        guard let previous = previous else {
            return "No previous session · ±" + stepText(current)
        }
        switch field {
        case .weight:
            return "Use last: " + NumberText.kg(previous.weightKg) + " kg"
        case .reps:
            let unit = current.exercise.exercise.tracking == .duration ? " s" : " reps"
            return "Use last: " + String(previous.reps) + unit
        }
    }

    /// The size of one stepper tap for the edited field.
    private func stepText(_ current: KeypadTarget) -> String {
        switch field {
        case .weight:
            return NumberText.kg(current.exercise.exercise.weightStepKg)
        case .reps:
            return String(current.exercise.exercise.repsStep)
        }
    }

    private func step(_ direction: Int, _ current: KeypadTarget) {
        KeypadHaptics.key()
        let exercise = current.exercise.exercise
        var next: Double
        switch field {
        case .weight:
            next = KeypadSheet.parseNumber(buffer) + Double(direction) * exercise.weightStepKg
            next = min(WorkoutReducer.maximumWeightKg, max(0, next))
        case .reps:
            next = KeypadSheet.parseNumber(buffer) + Double(direction * exercise.repsStep)
            next = min(Double(KeypadSheet.repsLimit(exercise)), max(0, next.rounded()))
        }
        buffer = NumberText.kg(next)
        isFresh = true
        commit()
    }

    private func useLast(_ current: KeypadTarget) {
        guard let previous = previousSet(for: current) else { return }
        KeypadHaptics.key()
        switch field {
        case .weight:
            buffer = NumberText.kg(previous.weightKg)
        case .reps:
            buffer = String(min(KeypadSheet.repsLimit(current.exercise.exercise), max(0, previous.reps)))
        }
        isFresh = true
        commit()
    }

    // MARK: Plates

    private func plateRow(_ current: KeypadTarget) -> some View {
        let barKg = current.exercise.exercise.barKg
        let info = KeypadSheet.plateInfo(weightKg: current.set.weightKg, barKg: barKg)
        return KeypadPlateRow(
            barKg: barKg,
            info: info,
            speech: KeypadSheet.plateSpeech(info, barKg: barKg)
        )
    }

    /// Plates for one side of the bar, and the note the design shows next to them.
    private static func plateInfo(weightKg: Double, barKg: Double) -> KeypadPlateInfo {
        guard let plan = PlateCalculator.plan(totalKg: weightKg, barKg: barKg) else {
            // `plan` gives nothing for a total below the bar, and also for one above the heaviest it plans for
            // (100,000 kg), which the keypad can still produce.
            let note = weightKg < barKg ? "Below the bar weight" : "Too many plates to show"
            return KeypadPlateInfo(plates: [], note: note)
        }
        if plan.perSide.count > 24 {
            return KeypadPlateInfo(plates: [], note: "Too many plates to show")
        }
        var note = ""
        if plan.perSide.isEmpty {
            note = "Bar only"
        }
        if plan.leftoverKg > 0.01 {
            note = "+ " + NumberText.kg(plan.leftoverKg) + " kg left over"
        }
        return KeypadPlateInfo(plates: plan.perSide, note: note)
    }

    /// "20 + 10 + 2.5 per side" for VoiceOver.
    private static func plateSpeech(_ info: KeypadPlateInfo, barKg: Double) -> String {
        let bar = NumberText.kg(barKg) + " kilogram bar. "
        if info.plates.isEmpty {
            return bar + info.note
        }
        let list = info.plates.map { NumberText.kg($0) }.joined(separator: " + ")
        let tail = info.note.isEmpty ? "" : ", " + info.note
        return bar + list + " per side" + tail
    }

    // MARK: Keypad

    private var keypadGrid: some View {
        VStack(spacing: 8) {
            ForEach(0..<KeypadKey.rows.count, id: \.self) { rowIndex in
                HStack(spacing: 8) {
                    ForEach(KeypadKey.rows[rowIndex]) { key in
                        keyButton(key)
                    }
                }
            }
        }
    }

    private func keyButton(_ key: KeypadKey) -> some View {
        let isOff = key == .decimal && field == .reps
        return Button {
            press(key)
        } label: {
            keyLabel(key)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 52)
                .background(PulseTheme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(PulsePlainButtonStyle())
        .disabled(isOff)
        .opacity(isOff ? 0.35 : 1)
        .accessibilityLabel(key.accessibilityName)
    }

    @ViewBuilder
    private func keyLabel(_ key: KeypadKey) -> some View {
        switch key {
        case .digit(let digit):
            Text(verbatim: digit)
                .pulseNumber(26, .medium, relativeTo: .title)
                .foregroundStyle(PulseTheme.ink)
        case .decimal:
            Text(verbatim: ".")
                .pulseNumber(26, .medium, relativeTo: .title)
                .foregroundStyle(PulseTheme.ink)
        case .delete:
            Image(systemName: "delete.left")
                .pulseFont(22, .regular, relativeTo: .title2)
                .foregroundStyle(PulseTheme.ink)
        }
    }

    private func press(_ key: KeypadKey) {
        KeypadHaptics.key()
        let repsLimit = target.map { KeypadSheet.repsLimit($0.exercise.exercise) } ?? WorkoutReducer.maximumReps
        guard let next = KeypadSheet.applying(key, to: buffer, isFresh: isFresh, field: field, repsLimit: repsLimit) else {
            return
        }
        buffer = next
        isFresh = false
        commit()
    }

    /// The buffer after a key press, or nil when the key is ignored (second decimal point, decimal point on reps,
    /// more than 6 characters, a third decimal of a weight, reps above `repsLimit`). The last two keep the card equal to the
    /// stored value: the reducer rounds a weight to 0.01 and clamps reps to 0...`repsLimit`.
    private static func applying(_ key: KeypadKey, to buffer: String, isFresh: Bool, field: KeypadField, repsLimit: Int) -> String? {
        switch key {
        case .delete:
            return buffer.count > 1 ? String(buffer.dropLast()) : "0"
        case .decimal:
            if field == .reps {
                return nil
            }
            if isFresh {
                return "0."
            }
            return buffer.contains(".") ? nil : buffer + "."
        case .digit(let digit):
            let next = (isFresh || buffer == "0") ? digit : buffer + digit
            if next.count > 6 {
                return nil
            }
            switch field {
            case .reps:
                if (Int(next) ?? 0) > repsLimit {
                    return nil
                }
            case .weight:
                if let dot = next.firstIndex(of: ".") {
                    let decimals = next.distance(from: dot, to: next.endIndex) - 1
                    if decimals > 2 {
                        return nil
                    }
                }
            }
            return next
        }
    }

    // MARK: Primary button

    private func primaryButton(_ current: KeypadTarget) -> some View {
        let title = primaryTitle(current)
        return Button {
            primaryAction(current)
        } label: {
            Text(verbatim: title)
        }
        .buttonStyle(PulsePrimaryButtonStyle())
    }

    /// "Next: Reps" while typing a weight, then "Log Set" for a pending set or "Done" for a logged one.
    private func primaryTitle(_ current: KeypadTarget) -> String {
        if field == .weight && current.exercise.exercise.tracksWeight {
            return "Next: Reps"
        }
        return current.set.isDone ? "Done" : "Log Set"
    }

    private func primaryAction(_ current: KeypadTarget) {
        if field == .weight && current.exercise.exercise.tracksWeight {
            KeypadHaptics.select()
            field = .reps
            buffer = String(current.set.reps)
            isFresh = true
            return
        }
        if current.set.isDone {
            KeypadHaptics.select()
        } else {
            controller.send(.logSet(exerciseID: ref.exerciseID, setID: ref.setID))
            KeypadHaptics.logged()
        }
        dismiss()
    }

    // MARK: Dispatch

    /// Applies the buffer to the set: empty or unparsable text is 0.
    private func commit() {
        switch field {
        case .weight:
            let kilograms = KeypadSheet.parseNumber(buffer)
            controller.send(.setWeight(exerciseID: ref.exerciseID, setID: ref.setID, kg: kilograms))
        case .reps:
            let limit = target.map { KeypadSheet.repsLimit($0.exercise.exercise) } ?? WorkoutReducer.maximumReps
            let reps = Int(min(Double(limit), KeypadSheet.parseNumber(buffer).rounded()))
            controller.send(.setReps(exerciseID: ref.exerciseID, setID: ref.setID, reps: reps))
        }
    }

    /// The most the reps card can hold: 999 reps, or the seconds of a timed set (`WorkoutReducer.maximumDurationSeconds`).
    private static func repsLimit(_ exercise: Exercise) -> Int {
        exercise.tracking == .duration ? WorkoutReducer.maximumDurationSeconds : WorkoutReducer.maximumReps
    }

    /// "82.5" -> 82.5, "82." -> 82, "" -> 0, anything else -> 0. Never negative, never NaN.
    private static func parseNumber(_ text: String) -> Double {
        var cleaned = text.trimmingCharacters(in: .whitespaces)
        if cleaned.hasSuffix(".") {
            cleaned.removeLast()
        }
        guard !cleaned.isEmpty, let value = Double(cleaned), value.isFinite, value >= 0 else {
            return 0
        }
        return value
    }
}

// MARK: - Model types

/// The set being edited, with its exercise and position.
private struct KeypadTarget {
    var exercise: WorkoutExercise
    var set: LoggedSet
    /// 0-based position of the set in its exercise.
    var index: Int
}

private struct KeypadPlateInfo {
    var plates: [Double]
    var note: String
}

private enum KeypadKey: Hashable, Identifiable {
    case digit(String)
    case decimal
    case delete

    var id: String {
        switch self {
        case .digit(let digit):
            return "digit-" + digit
        case .decimal:
            return "decimal"
        case .delete:
            return "delete"
        }
    }

    var accessibilityName: String {
        switch self {
        case .digit(let digit):
            return digit
        case .decimal:
            return "Decimal point"
        case .delete:
            return "Delete"
        }
    }

    static let rows: [[KeypadKey]] = [
        [.digit("1"), .digit("2"), .digit("3")],
        [.digit("4"), .digit("5"), .digit("6")],
        [.digit("7"), .digit("8"), .digit("9")],
        [.decimal, .digit("0"), .delete]
    ]
}

// MARK: - Haptics

@MainActor
private enum KeypadHaptics {
    /// A light tap for every key, stepper and "Use last".
    static func key() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func select() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    /// A set was logged.
    static func logged() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

// MARK: - Title bar

private struct KeypadSheetHeader: View {
    let title: String
    let onDone: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ZStack {
            Text(verbatim: title)
                .pulseFont(17, .semibold, relativeTo: .headline)
                .foregroundStyle(PulseTheme.ink)
                .lineLimit(dynamicTypeSize > .large ? 2 : 1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 70)
                .accessibilityAddTraits(.isHeader)
            HStack {
                Spacer(minLength: 0)
                Button(action: onDone) {
                    Text("Done")
                        .pulseFont(17, .semibold, relativeTo: .headline)
                        .foregroundStyle(PulseTheme.green)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PulsePlainButtonStyle())
            }
        }
        .frame(minHeight: 56)
        .padding(.horizontal, 16)
        .reportsSheetTitleBarHeight()
    }
}

// MARK: - Value card

/// "KG 82.5" / "REPS 6": 14 pt radius, green 2 pt ring and a green tint while it is the edited value.
private struct KeypadValueCard: View {
    let label: String
    let text: String
    let isSelected: Bool
    let isEnabled: Bool
    let accessibilityName: String
    let accessibilityValueText: String
    let action: () -> Void

    /// The two text lines of the card (16 pt and 38 pt at the default text size) grow with their text.
    @PulseScaled(16, relativeTo: .footnote) private var labelHeight: CGFloat
    @PulseScaled(38, relativeTo: .largeTitle) private var numberHeight: CGFloat

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: label)
                    .pulseFont(12, relativeTo: .footnote)
                    .foregroundStyle(PulseTheme.inkSecondary)
                    .frame(height: labelHeight, alignment: .leading)
                Text(verbatim: text)
                    .pulseNumber(32, .bold, relativeTo: .largeTitle)
                    .foregroundStyle(PulseTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(height: numberHeight, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background { cardBackground }
            .overlay { cardRing }
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(Rectangle())
        }
        .buttonStyle(PulsePlainButtonStyle())
        .disabled(!isEnabled)
        .accessibilityLabel(accessibilityName)
        .accessibilityValue(accessibilityValueText)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
    }

    /// Selected: 8 % green over the sheet ground (as the design); otherwise a plain card.
    @ViewBuilder
    private var cardBackground: some View {
        if isSelected {
            ZStack {
                shape.fill(PulseTheme.ground)
                shape.fill(Color(light: 0x1B8448, dark: 0x30D158, lightAlpha: 0.08, darkAlpha: 0.16))
            }
        } else {
            shape.fill(PulseTheme.card)
        }
    }

    private var cardRing: some View {
        shape.strokeBorder(isSelected ? PulseTheme.green : Color.clear, lineWidth: 2)
    }
}

// MARK: - Stepper button

private struct KeypadStepButton: View {
    let systemName: String
    let accessibilityName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .pulseFont(18, .bold, relativeTo: .body)
                .foregroundStyle(PulseTheme.greenText)
                .frame(width: 64, height: 48)
                .background(PulseTheme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(PulsePlainButtonStyle())
        .accessibilityLabel(accessibilityName)
    }
}

// MARK: - Plates

/// One plate as a coloured disc with its weight (sizes and colours of the design).
private struct KeypadPlateChip: View {
    let plate: Double
    /// The disc grows with the figure inside it (24 to 44 pt at the default text size).
    @PulseScaled private var diameter: CGFloat

    init(plate: Double) {
        self.plate = plate
        self._diameter = PulseScaled(KeypadPlateLook.diameter(plate), relativeTo: .caption2)
    }

    var body: some View {
        let side = diameter
        return Text(verbatim: NumberText.kg(plate))
            .pulseNumber(11, .bold, relativeTo: .caption2)
            .foregroundStyle(KeypadPlateLook.foreground(plate))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(width: side, height: side)
            .background(KeypadPlateLook.fill(plate), in: Circle())
    }
}

/// "20 kg bar · each side" and the plates for one side. The label column (84 pt at the default text size) grows with
/// the text, so the label keeps its two lines.
private struct KeypadPlateRow: View {
    let barKg: Double
    let info: KeypadPlateInfo
    let speech: String

    @PulseScaled(84, relativeTo: .footnote) private var labelWidth: CGFloat

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(verbatim: NumberText.kg(barKg) + " kg bar · each side")
                .pulseFont(13, relativeTo: .footnote)
                .foregroundStyle(PulseTheme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: labelWidth, alignment: .leading)
            KeypadPlateFlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(Array(info.plates.enumerated()), id: \.offset) { pair in
                    KeypadPlateChip(plate: pair.element)
                }
                if !info.note.isEmpty {
                    Text(verbatim: info.note)
                        .pulseFont(13, relativeTo: .footnote)
                        .foregroundStyle(PulseTheme.inkSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 46)
        .padding(.horizontal, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(speech)
    }
}

/// The text of the "Use last" button: one line at the default size (shrinking a little if it must), two above it.
private struct KeypadUseLastLabel: View {
    let text: String

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Text(verbatim: text)
            .pulseFont(15, .semibold, relativeTo: .subheadline)
            .foregroundStyle(PulseTheme.greenText)
            .lineLimit(dynamicTypeSize > .large ? 2 : 1)
            .minimumScaleFactor(0.8)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(PulseTheme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private enum KeypadPlateLook {
    static func diameter(_ plate: Double) -> CGFloat {
        switch plate {
        case 25: return 44
        case 20: return 42
        case 15: return 38
        case 10: return 34
        case 5: return 30
        case 2.5: return 26
        default: return 24
        }
    }

    static func fill(_ plate: Double) -> Color {
        switch plate {
        case 25: return Color(light: 0x3A3A3C, dark: 0x3A3A3C)
        case 20: return Color(light: 0x48484A, dark: 0x48484A)
        case 15: return Color(light: 0x636366, dark: 0x636366)
        case 10: return Color(light: 0x8E8E93, dark: 0x8E8E93)
        case 5: return Color(light: 0xAEAEB2, dark: 0xAEAEB2)
        case 2.5: return Color(light: 0xC7C7CC, dark: 0xC7C7CC)
        default: return Color(light: 0xD1D1D6, dark: 0xD1D1D6)
        }
    }

    static func foreground(_ plate: Double) -> Color {
        switch plate {
        case 25, 20, 15: return Color.white
        default: return Color.black
        }
    }
}

/// Wraps its children onto several lines (a CSS flex-wrap row), each line vertically centred.
private struct KeypadPlateFlowLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    init(spacing: CGFloat = 6, lineSpacing: CGFloat = 6) {
        self.spacing = spacing
        self.lineSpacing = lineSpacing
    }

    struct Arrangement {
        var origins: [CGPoint]
        var sizes: [CGSize]
        var size: CGSize
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let arrangement = arrange(width: bounds.width, subviews: subviews)
        for index in subviews.indices {
            let origin = arrangement.origins[index]
            let itemSize = arrangement.sizes[index]
            subviews[index].place(
                at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: itemSize.width, height: itemSize.height)
            )
        }
    }

    private func arrange(width: CGFloat?, subviews: Subviews) -> Arrangement {
        let limit: CGFloat = width ?? CGFloat.infinity
        // A text wider than the row (large text sizes) is measured at the row width and wraps there.
        let measuring = ProposedViewSize(width: width, height: nil)
        var sizes: [CGSize] = []
        for subview in subviews {
            sizes.append(subview.sizeThatFits(measuring))
        }

        var rows: [[Int]] = []
        var current: [Int] = []
        var x: CGFloat = 0
        for index in sizes.indices {
            let itemWidth = sizes[index].width
            if !current.isEmpty && x + itemWidth > limit {
                rows.append(current)
                current = []
                x = 0
            }
            current.append(index)
            x += itemWidth + spacing
        }
        if !current.isEmpty {
            rows.append(current)
        }

        var origins = [CGPoint](repeating: .zero, count: sizes.count)
        var y: CGFloat = 0
        var usedWidth: CGFloat = 0
        for (rowNumber, row) in rows.enumerated() {
            var rowHeight: CGFloat = 0
            for index in row {
                rowHeight = max(rowHeight, sizes[index].height)
            }
            var rowX: CGFloat = 0
            for index in row {
                let offsetY = (rowHeight - sizes[index].height) / 2
                origins[index] = CGPoint(x: rowX, y: y + offsetY)
                rowX += sizes[index].width + spacing
            }
            usedWidth = max(usedWidth, rowX - spacing)
            y += rowHeight
            if rowNumber < rows.count - 1 {
                y += lineSpacing
            }
        }
        return Arrangement(origins: origins, sizes: sizes, size: CGSize(width: usedWidth, height: y))
    }
}
#endif
