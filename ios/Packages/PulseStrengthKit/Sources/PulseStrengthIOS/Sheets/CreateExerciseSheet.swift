#if os(iOS)
import SwiftUI
import UIKit
import PulseStrengthCore

/// "New Exercise" form (Cancel / Save): name, primary muscle, equipment and what to track.
///
/// Save builds the exercise with `Exercise.custom(name:muscle:equipment:tracking:)` (an empty name
/// becomes "Custom exercise"), hands it to `onCreate` and closes the sheet. Persisting the exercise is the
/// caller's job (the picker saves it with `StrengthStore.addCustomExercise`).
@MainActor
public struct CreateExerciseSheet: View {
    private let onCreate: (Exercise) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var muscle: MuscleGroup = .chest
    @State private var equipment: Equipment = .barbell
    @State private var tracking: TrackingKind = .weightReps
    /// Set by the first tap on Save, so a second tap while the sheet slides away creates no second exercise.
    @State private var didSubmit = false
    @FocusState private var nameIsFocused: Bool

    public init(initialName: String, onCreate: @escaping (Exercise) -> Void) {
        self._name = State(initialValue: initialName)
        self.onCreate = onCreate
    }

    // MARK: Body

    public var body: some View {
        VStack(spacing: 0) {
            ExerciseEditorTitleBar(
                title: "New Exercise",
                leadingTitle: "Cancel",
                leadingAction: { dismiss() },
                trailingTitle: "Save",
                trailingAction: { save() }
            )
            ScrollView {
                formContent
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(PulseTheme.ground.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(PulseTheme.sheetRadius)
        .presentationBackground(PulseTheme.ground)
    }

    private var formContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            nameSection
            muscleSection
            equipmentSection
            trackingSection
            footnote
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 16)
    }

    // MARK: Sections

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Name")
            TextField("e.g. Landmine press", text: $name)
                .font(PulseFont.body)
                .foregroundStyle(PulseTheme.ink)
                .focused($nameIsFocused)
                .submitLabel(.done)
                .textInputAutocapitalization(.words)
                .onSubmit {
                    nameIsFocused = false
                }
                .padding(.horizontal, 16)
                .frame(height: 48)
                .background(PulseTheme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityLabel("Name")
        }
    }

    private var muscleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Primary muscle")
            ExerciseChipFlowLayout(spacing: 8) {
                ForEach(MuscleGroup.allCases) { (group: MuscleGroup) in
                    CreateExerciseChip(title: group.title, isSelected: muscle == group) {
                        muscle = group
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var equipmentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Equipment")
            ExerciseChipFlowLayout(spacing: 8) {
                ForEach(Equipment.allCases) { (item: Equipment) in
                    CreateExerciseChip(title: item.title, isSelected: equipment == item) {
                        equipment = item
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var trackingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Track")
            CreateExerciseTrackControl(options: trackingOptions, selection: $tracking)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Track")
        }
    }

    private var footnote: some View {
        Text("Custom exercises are saved to your library and can be added to any workout.")
            .font(PulseFont.footnote)
            .foregroundStyle(PulseTheme.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(PulseFont.footnote)
            .foregroundStyle(PulseTheme.inkSecondary)
            .padding(.leading, 4)
            .accessibilityAddTraits(.isHeader)
    }

    private var trackingOptions: [(value: TrackingKind, title: String)] {
        TrackingKind.allCases.map { (kind: TrackingKind) -> (value: TrackingKind, title: String) in
            (value: kind, title: kind.title)
        }
    }

    // MARK: Actions

    private func save() {
        guard !didSubmit else { return }
        didSubmit = true
        nameIsFocused = false
        let exercise = Exercise.custom(name: name, muscle: muscle, equipment: equipment, tracking: tracking)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onCreate(exercise)
        dismiss()
    }
}

// MARK: - Form controls

/// A muscle / equipment chip of the form: 40 pt tall with 16 pt side padding (the picker's `PulseChip` is 36 pt
/// with 14 pt), 15 pt text, blue tint when selected (Active.dc.html, the "New exercise" sheet).
private struct CreateExerciseChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? PulseTheme.blueText : PulseTheme.ink.opacity(0.75))
                .padding(.horizontal, 16)
                .frame(height: 40)
                .background(isSelected ? PulseTheme.blueTint : PulseTheme.chipFill, in: Capsule())
        }
        .buttonStyle(PulsePlainButtonStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The "Track" segmented control of the form: 40 pt segments with 14 pt text in the system face, bold when
/// selected (`PulseSegmented` is 36 pt with 15 pt rounded text).
private struct CreateExerciseTrackControl: View {
    let options: [(value: TrackingKind, title: String)]
    @Binding var selection: TrackingKind

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { index in
                segment(options[index])
            }
        }
        .padding(2)
        .background(PulseTheme.chipFill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func segment(_ option: (value: TrackingKind, title: String)) -> some View {
        let isSelected = option.value == selection
        return Button {
            selection = option.value
        } label: {
            Text(option.title)
                .font(.system(size: 14, weight: isSelected ? .bold : .medium))
                .foregroundStyle(PulseTheme.ink)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isSelected ? PulseTheme.card : Color.clear)
                        .shadow(color: Color.black.opacity(isSelected ? 0.12 : 0), radius: 4, x: 0, y: 3)
                )
        }
        .buttonStyle(PulsePlainButtonStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Wrapping layout

/// Left-aligned chips that wrap onto further lines (the muscle and equipment pickers).
private struct ExerciseChipFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? CGFloat.infinity
        return arrange(subviews: subviews, maxWidth: maxWidth).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(subviews: subviews, maxWidth: bounds.width)
        for index in subviews.indices {
            let point = result.positions[index]
            subviews[index].place(
                at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y),
                anchor: .topLeading,
                proposal: ProposedViewSize.unspecified
            )
        }
    }

    private func arrange(subviews: Subviews, maxWidth: CGFloat) -> (positions: [CGPoint], size: CGSize) {
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize.unspecified)
            if x > 0 && x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            x += size.width
            widest = max(widest, x)
            x += spacing
            rowHeight = max(rowHeight, size.height)
        }
        return (positions, CGSize(width: widest, height: y + rowHeight))
    }
}
#endif
