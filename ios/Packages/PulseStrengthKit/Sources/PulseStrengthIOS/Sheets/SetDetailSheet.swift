#if os(iOS)
import SwiftUI
import UIKit
import PulseStrengthCore

// MARK: - Sheet

/// Set type, reps in reserve and delete for one set (Active.dc.html, `sh.set`).
///
/// Title bar ("Set 3 · Barbell Bench Press" + Done), the "Set type" list (Normal, Warm-up, Drop set, To failure,
/// each with its badge colours and a check on the current one), the "Reps in reserve" segmented control
/// (– 0 1 2 3 4+) and the red "Delete Set" button. Every choice is dispatched at once and the sheet stays open;
/// "Delete Set" removes the set (the workout screen offers Undo) and closes the sheet.
@MainActor
public struct SetDetailSheet: View {
    @ObservedObject private var controller: WorkoutController
    private let ref: SetRef

    @Environment(\.dismiss) private var dismiss

    /// What the sheet showed when "Delete Set" was tapped, so it does not go blank while it slides away.
    @State private var frozen: SetDetailSnapshot?

    public init(controller: WorkoutController, ref: SetRef) {
        self._controller = ObservedObject(wrappedValue: controller)
        self.ref = ref
    }

    // MARK: Body

    public var body: some View {
        VStack(spacing: 0) {
            SetDetailHeader(title: shown?.title ?? "Set details", onDone: { dismiss() })
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
        .dynamicTypeSize(PulseDynamicType.screenRange)
        .sheetDetentsHuggingContent(titleBarHeight: 56, estimate: 484)
        .onAppear {
            if live == nil {
                dismiss()
            }
        }
        .onChange(of: live == nil) { _, isMissing in
            if isMissing {
                dismiss()
            }
        }
    }

    @ViewBuilder
    private var panel: some View {
        if let data = shown {
            VStack(alignment: .leading, spacing: 12) {
                sectionLabel("Set type")
                typeList(data)
                sectionLabel("Reps in reserve")
                SetDetailRIRControl(selection: data.rir, onPick: { (value: Int?) in pickRIR(value) })
                deleteButton
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 16)
            .reportsSheetPanelHeight()
        } else {
            Color.clear.frame(height: 1)
        }
    }

    // MARK: Live data

    /// The set as it is right now; nil once it no longer exists.
    private var live: SetDetailSnapshot? {
        guard let state = controller.state,
              let exercise = state.exercises.first(where: { $0.id == ref.exerciseID }),
              let index = exercise.sets.firstIndex(where: { $0.id == ref.setID }) else {
            return nil
        }
        let set = exercise.sets[index]
        return SetDetailSnapshot(
            title: "Set " + String(index + 1) + " · " + exercise.exercise.name,
            type: set.type,
            rir: set.rir
        )
    }

    private var shown: SetDetailSnapshot? {
        live ?? frozen
    }

    // MARK: Pieces

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .pulseFont(13, relativeTo: .footnote)
            .foregroundStyle(PulseTheme.inkSecondary)
            .padding(.leading, 4)
            .accessibilityAddTraits(.isHeader)
    }

    private func typeList(_ data: SetDetailSnapshot) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return VStack(spacing: 0) {
            ForEach(SetType.allCases, id: \.self) { (type: SetType) in
                SetDetailTypeRow(
                    type: type,
                    isSelected: type == data.type,
                    showsDivider: type != .normal,
                    action: { pickType(type) }
                )
            }
        }
        .background(PulseTheme.card, in: shape)
        .clipShape(shape)
    }

    private var deleteButton: some View {
        Button(action: deleteSet) {
            HStack(spacing: 8) {
                Image(systemName: "trash")
                    .pulseFont(17, .regular, relativeTo: .body)
                Text("Delete Set")
                    .pulseFont(17, relativeTo: .body)
            }
            .foregroundStyle(PulseTheme.destructive)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(PulseTheme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(PulsePlainButtonStyle())
    }

    // MARK: Actions

    private func pickType(_ type: SetType) {
        SetDetailHaptics.select()
        controller.send(.setSetType(exerciseID: ref.exerciseID, setID: ref.setID, type: type))
    }

    private func pickRIR(_ value: Int?) {
        SetDetailHaptics.select()
        controller.send(.setRIR(exerciseID: ref.exerciseID, setID: ref.setID, rir: value))
    }

    private func deleteSet() {
        // Once-only: a second tap while the sheet slides away finds no set (`live` is nil) and must neither blank the
        // frozen copy nor repeat the haptic.
        guard let current = live else { return }
        frozen = current
        SetDetailHaptics.deleted()
        controller.send(.deleteSet(exerciseID: ref.exerciseID, setID: ref.setID))
        dismiss()
    }
}

// MARK: - Model types

/// The few values of the set the sheet displays.
private struct SetDetailSnapshot: Equatable {
    var title: String
    var type: SetType
    var rir: Int?
}

// MARK: - Haptics

@MainActor
private enum SetDetailHaptics {
    static func select() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func deleted() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}

// MARK: - Title bar

private struct SetDetailHeader: View {
    let title: String
    let onDone: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            stackedBar
        } else {
            centredBar
        }
    }

    /// The design's bar: the title centred (one line, two above the default text size), "Done" at the right.
    private var centredBar: some View {
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
                doneButton
            }
        }
        .frame(minHeight: 56)
        .padding(.horizontal, 16)
        .reportsSheetTitleBarHeight()
    }

    /// Accessibility text sizes: "Done" on its own line, the title under it, so they cannot overlap.
    private var stackedBar: some View {
        VStack(spacing: 2) {
            HStack {
                Spacer(minLength: 0)
                doneButton
            }
            Text(verbatim: title)
                .pulseFont(17, .semibold, relativeTo: .headline)
                .foregroundStyle(PulseTheme.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .frame(minHeight: 56)
        .reportsSheetTitleBarHeight()
    }

    private var doneButton: some View {
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

// MARK: - Set type row

/// One row of the set type list: 32 pt badge, name, explanation and a check on the chosen type.
private struct SetDetailTypeRow: View {
    let type: SetType
    let isSelected: Bool
    let showsDivider: Bool
    let action: () -> Void

    /// The badge (32 pt at the default text size) grows with the letter in it.
    @PulseScaled(32, relativeTo: .subheadline) private var badgeSide: CGFloat

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                badge
                texts
                Spacer(minLength: 0)
                Image(systemName: "checkmark")
                    .pulseFont(15, .bold, relativeTo: .subheadline)
                    .foregroundStyle(PulseTheme.green)
                    .opacity(isSelected ? 1 : 0)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(PulsePlainButtonStyle())
        .overlay(alignment: .top) {
            if showsDivider {
                Rectangle()
                    .fill(PulseTheme.separator)
                    .frame(height: 0.5)
            }
        }
        .accessibilityLabel(type.title + ", " + explanation)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var badge: some View {
        Text(verbatim: type.badge)
            .pulseFont(15, .bold, relativeTo: .subheadline)
            .foregroundStyle(type.badgeForeground)
            .frame(width: badgeSide, height: badgeSide)
            .background(type.badgeBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var texts: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: type.title)
                .pulseFont(17, relativeTo: .body)
                .foregroundStyle(PulseTheme.ink)
            Text(verbatim: explanation)
                .pulseFont(12, relativeTo: .footnote)
                .foregroundStyle(PulseTheme.inkSecondary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 8)
    }

    private var explanation: String {
        switch type {
        case .normal:
            return "Counts toward volume"
        case .warmup:
            return "Left out of volume and PRs"
        case .drop:
            return "Lower weight, little rest"
        case .failure:
            return "Until you cannot do another rep"
        }
    }
}

// MARK: - Reps in reserve

private struct SetDetailRIROption: Identifiable {
    /// nil clears the value.
    var value: Int?
    var title: String
    var spoken: String

    var id: String { title }
}

/// Segmented control "– 0 1 2 3 4+" (40 pt tall, as in the design). "–" clears the value, "4+" stores 4.
private struct SetDetailRIRControl: View {
    let selection: Int?
    let onPick: (Int?) -> Void

    private static let options: [SetDetailRIROption] = [
        SetDetailRIROption(value: nil, title: "–", spoken: "Not recorded"),
        SetDetailRIROption(value: 0, title: "0", spoken: "0 reps in reserve"),
        SetDetailRIROption(value: 1, title: "1", spoken: "1 rep in reserve"),
        SetDetailRIROption(value: 2, title: "2", spoken: "2 reps in reserve"),
        SetDetailRIROption(value: 3, title: "3", spoken: "3 reps in reserve"),
        SetDetailRIROption(value: 4, title: "4+", spoken: "4 or more reps in reserve")
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(SetDetailRIRControl.options) { option in
                segment(option)
            }
        }
        .padding(2)
        .background(PulseTheme.chipFill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Reps in reserve")
    }

    private func segment(_ option: SetDetailRIROption) -> some View {
        let isOn = option.value == selection
        return Button {
            onPick(option.value)
        } label: {
            Text(verbatim: option.title)
                .pulseFont(15, isOn ? .bold : .medium, design: .rounded, relativeTo: .subheadline)
                .foregroundStyle(PulseTheme.ink)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(segmentBackground(isOn))
                .contentShape(Rectangle())
        }
        .buttonStyle(PulsePlainButtonStyle())
        .accessibilityLabel(option.spoken)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func segmentBackground(_ isOn: Bool) -> some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(isOn ? PulseTheme.card : Color.clear)
            .shadow(color: Color.black.opacity(isOn ? 0.12 : 0), radius: 4, x: 0, y: 3)
    }
}
#endif
