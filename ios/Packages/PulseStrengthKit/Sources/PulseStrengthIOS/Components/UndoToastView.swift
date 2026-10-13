#if os(iOS)
import SwiftUI
import UIKit
import PulseStrengthCore

/// The dark snackbar that offers "Undo" after an exercise was removed or a set was deleted
/// ("Removed Cable crossover", "Set deleted"). The caller shows it while
/// `ActiveWorkoutPresentation.undoText` is non-nil and dispatches `.undo` from `onUndo`.
public struct UndoToastView: View {
    public var text: String
    public var onUndo: () -> Void

    public init(text: String, onUndo: @escaping () -> Void) {
        self.text = text
        self.onUndo = onUndo
    }

    public var body: some View {
        HStack(spacing: 12) {
            Text(text)
                .font(.system(size: 15))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onUndo) {
                Text("Undo")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(PulseTheme.toastAction)
                    .padding(.horizontal, 12)
                    .frame(height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PulsePlainButtonStyle())
            .accessibilityHint("Restores what was just removed")
        }
        .padding(.leading, 16)
        .padding(.trailing, 6)
        .frame(height: 48)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(PulseTheme.toastFill.opacity(0.96))
                .shadow(color: Color.black.opacity(0.25), radius: 12, x: 0, y: 8)
        )
        .accessibilityElement(children: .contain)
        .onAppear {
            UIAccessibility.post(notification: .announcement, argument: text)
        }
    }
}
#endif
