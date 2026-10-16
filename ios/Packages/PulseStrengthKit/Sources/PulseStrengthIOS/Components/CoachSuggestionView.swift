#if os(iOS)
import SwiftUI
import Foundation
import PulseStrengthCore

/// The "Next time · 82.5 kg × 6" suggestion at the bottom of an exercise card, with an "Apply" button that sets the pending working
/// sets to it. Styled like `CoachTipView`; shown before the first set of the exercise is logged.
///
/// Without something to apply (the "Log RIR" hint) there is no button.
///
/// `isCompact` drops the reason line of a note that has no button (it stays available to VoiceOver as the hint) for the moments the
/// card is short of room: a rest is running, the text is large, or the exercise has many sets. With an "Apply" button the row is as
/// tall as the button anyway, so the reason stays: it is what says why the weight goes down or the reps go up. The hub card always
/// shows the reason.
struct CoachSuggestionView: View {
    let line: CoachLine
    let canApply: Bool
    let isCompact: Bool
    let onApply: () -> Void

    /// The 13 pt text and the 13 pt button label grow with Dynamic Type like the coach tip.
    @PulseScaled(13, relativeTo: .footnote) private var textSize: CGFloat

    init(line: CoachLine, canApply: Bool, isCompact: Bool = false, onApply: @escaping () -> Void) {
        self.line = line
        self.canApply = canApply
        self.isCompact = isCompact
        self.onApply = onApply
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            texts
                // The button brings the row's height; the words keep their own room from the edge of the wash.
                .padding(.vertical, canApply ? 6 : 0)
                .frame(maxWidth: .infinity, alignment: .leading)
            if canApply {
                applyButton
            }
        }
        .padding(.horizontal, 10)
        // The button brings its own vertical room (see `applyButton`), so the row does not grow by the full padding twice.
        .padding(.vertical, canApply ? 2 : 8)
        .background(
            PulseTheme.coachTipFill,
            in: RoundedRectangle(cornerRadius: PulseTheme.rowRadius, style: .continuous)
        )
    }

    private var showsDetail: Bool { !(isCompact && !canApply) }

    private var texts: some View {
        VStack(alignment: .leading, spacing: 2) {
            let title: Text = Text("Next time · ").fontWeight(.semibold) + Text(verbatim: line.headline).fontWeight(.semibold)
            title
                .font(.system(size: textSize))
                .foregroundStyle(PulseTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let detail = line.detail, showsDetail {
                // Ink at 75 % rather than the secondary grey: the grey is 4.2:1 on this tinted fill in dark mode.
                Text(verbatim: detail)
                    .font(.system(size: textSize - 1))
                    .foregroundStyle(PulseTheme.ink.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(showsDetail ? "" : (line.detail ?? ""))
    }

    private var applyButton: some View {
        Button(action: onApply) {
            Text("Apply")
                .font(.system(size: textSize, weight: .semibold))
                .foregroundStyle(PulseTheme.onGreen)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(PulseTheme.green, in: Capsule())
                // Transparent room above and below the capsule: the tap target is about 44 pt tall, the capsule stays as it was.
                .padding(.vertical, 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(PulsePlainButtonStyle())
        .accessibilityLabel("Apply to sets")
        .accessibilityValue(line.headline)
        .accessibilityIdentifier("coach-apply")
    }
}
#endif
