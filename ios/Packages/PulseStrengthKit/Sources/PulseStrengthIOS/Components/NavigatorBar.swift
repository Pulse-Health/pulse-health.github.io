#if os(iOS)
import SwiftUI
import PulseStrengthCore

/// The exercise navigator capsule ("<  1 / 6  >") and the Edit pill next to it.
public struct NavigatorBar: View {
    public var navigator: ActiveWorkoutPresentation.Navigator
    public var onPrevious: () -> Void
    public var onNext: () -> Void
    public var onEdit: () -> Void

    public init(
        navigator: ActiveWorkoutPresentation.Navigator,
        onPrevious: @escaping () -> Void,
        onNext: @escaping () -> Void,
        onEdit: @escaping () -> Void
    ) {
        self.navigator = navigator
        self.onPrevious = onPrevious
        self.onNext = onNext
        self.onEdit = onEdit
    }

    public var body: some View {
        HStack(spacing: 8) {
            capsule
            Spacer(minLength: 8)
            editPill
        }
    }

    // MARK: Capsule

    private var capsule: some View {
        HStack(spacing: 0) {
            arrowButton(
                systemName: "chevron.left",
                label: "Previous exercise",
                isEnabled: navigator.canGoPrevious,
                action: onPrevious
            )
            positionLabel
            arrowButton(
                systemName: "chevron.right",
                label: "Next exercise",
                isEnabled: navigator.canGoNext,
                action: onNext
            )
        }
        .frame(height: 44)
        .background(PulseTheme.chipFill, in: Capsule())
    }

    private func arrowButton(systemName: String, label: String, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(PulseTheme.green)
                .frame(width: 48, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PulsePlainButtonStyle())
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.3)
        .accessibilityLabel(label)
    }

    private var positionLabel: some View {
        HStack(spacing: 0) {
            Text("\(navigator.position)")
                .foregroundStyle(PulseTheme.ink)
            Text(" / \(navigator.total)")
                .font(PulseFont.number(17, .medium))
                .foregroundStyle(PulseTheme.inkSecondary)
        }
        .font(PulseFont.number(17, .semibold))
        .monospacedDigit()
        .frame(minWidth: 62)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Exercise \(navigator.position) of \(navigator.total)")
    }

    // MARK: Edit pill

    private var editPill: some View {
        Button(action: onEdit) {
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 15, weight: .bold))
                Text("Edit")
                    .font(.system(size: 17, weight: .semibold))
            }
            .foregroundStyle(PulseTheme.greenText)
            .padding(.horizontal, 16)
            .frame(height: 44)
            .background(PulseTheme.chipFill, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(PulsePlainButtonStyle())
        .accessibilityHint("Reorder, add or remove exercises")
    }
}
#endif
