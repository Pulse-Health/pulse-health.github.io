#if os(iOS)
import SwiftUI
import PulseStrengthCore

// MARK: - Sheet

/// Form demo and cues of one exercise (Active.dc.html, `sh.info`).
///
/// Title bar ("Form" + Done), then a scrolling page: the large looping demo (3 : 2, 16 pt radius, "Start · End"
/// badge), the exercise name with chips for the primary muscle, the equipment and the secondary muscles, the
/// numbered "How to" cues, the "History & records" row and the photo attribution. The demo is `ExerciseMediaView`,
/// which pauses on the first frame when Reduce Motion is on.
///
/// The "History & records" row is shown only when the presenter passes `onShowHistory`; it is the way on to the
/// exercise detail screen, which the presenter owns (a sheet has no navigation of its own).
@MainActor
public struct FormInfoSheet: View {
    private let exercise: Exercise
    private let onShowHistory: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    public init(exercise: Exercise, onShowHistory: (() -> Void)? = nil) {
        self.exercise = exercise
        self.onShowHistory = onShowHistory
    }

    // MARK: Body

    public var body: some View {
        VStack(spacing: 0) {
            FormInfoHeader(onDone: { dismiss() })
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    demoTile
                    titleBlock
                    if !exercise.cues.isEmpty {
                        cuesCard
                    }
                    if let onShowHistory = onShowHistory {
                        FormInfoHistoryRow(action: onShowHistory)
                    }
                    attribution
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 34)
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(PulseTheme.ground.ignoresSafeArea())
    }

    // MARK: Demo

    private var hasMedia: Bool {
        guard let key = exercise.mediaKey else { return false }
        return !key.isEmpty
    }

    /// 358 x 239 in the design: full width, 3 : 2.
    private var demoTile: some View {
        Color.clear
            .aspectRatio(358.0 / 239.0, contentMode: .fit)
            .overlay { demoContent }
            .overlay(alignment: .bottomLeading) { startEndBadge }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(demoAccessibilityLabel)
    }

    @ViewBuilder
    private var demoContent: some View {
        if hasMedia {
            ExerciseMediaView(mediaKey: exercise.mediaKey, cornerRadius: 16)
        } else {
            noDemoPlaceholder
        }
    }

    private var noDemoPlaceholder: some View {
        ZStack {
            PulseTheme.progressTrack
            VStack(spacing: 10) {
                StrengthDumbbellGlyph(size: 44, color: PulseTheme.inkTertiary, strokeWidth: 1.4)
                Text("No form demo for this exercise yet")
                    .font(PulseFont.subhead)
                    .foregroundStyle(PulseTheme.inkSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
        }
    }

    @ViewBuilder
    private var startEndBadge: some View {
        if hasMedia {
            Text("Start · End")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.55), in: Capsule())
                .padding(10)
        }
    }

    private var demoAccessibilityLabel: String {
        if hasMedia {
            return "Form demo for " + exercise.name + ", alternating between the start and the end position"
        }
        return "No form demo for this exercise yet"
    }

    // MARK: Name and chips

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: exercise.name)
                .font(PulseFont.title)
                .foregroundStyle(PulseTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            FormInfoChipFlowLayout(spacing: 6, lineSpacing: 6) {
                FormInfoChip(text: exercise.muscle.title, isPrimary: true)
                FormInfoChip(text: exercise.equipment.title, isPrimary: false)
                if showsSecondary {
                    FormInfoChip(text: exercise.secondary, isPrimary: false)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Custom exercises carry the placeholder "Custom" instead of secondary muscles; nothing to show then.
    private var showsSecondary: Bool {
        !exercise.secondary.isEmpty && exercise.secondary != "Custom"
    }

    // MARK: Cues

    private var cuesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How to")
                .font(PulseFont.headline)
                .foregroundStyle(PulseTheme.ink)
                .accessibilityAddTraits(.isHeader)
            ForEach(Array(exercise.cues.enumerated()), id: \.offset) { pair in
                FormInfoCueRow(number: pair.offset + 1, text: pair.element)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PulseTheme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: Attribution

    private var attribution: some View {
        Text("Demo photos: Free Exercise DB (public domain).")
            .font(PulseFont.caption2)
            .foregroundStyle(PulseTheme.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Colours

private enum FormInfoColors {
    /// The 12 % green wash behind the primary-muscle chip and the cue numbers.
    static let greenWash = Color(light: 0x1B8448, dark: 0x30D158, lightAlpha: 0.12, darkAlpha: 0.18)
    /// The design's #007AFF icon and its 10 % wash behind it in the "History & records" row.
    static let historyIcon = Color(light: 0x007AFF, dark: 0x0A84FF)
    static let historyWash = Color(light: 0x007AFF, dark: 0x0A84FF, lightAlpha: 0.10, darkAlpha: 0.24)
}

// MARK: - History row

/// "History & records ›": a 56 pt white row with a 32 pt blue icon tile (Active.dc.html, `sh.info`).
private struct FormInfoHistoryRow: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                FormInfoTrendShape()
                    .stroke(
                        FormInfoColors.historyIcon,
                        style: StrokeStyle(lineWidth: 2 * 18 / 24, lineCap: .round, lineJoin: .round)
                    )
                    .frame(width: 18, height: 18)
                    .frame(width: 32, height: 32)
                    .background(FormInfoColors.historyWash, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityHidden(true)
                Text("History & records")
                    .font(PulseFont.body)
                    .foregroundStyle(PulseTheme.ink)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(PulseTheme.inkTertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(PulseTheme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(PulsePlainButtonStyle())
        .accessibilityHint("Shows the records, sessions and progress of this exercise")
    }
}

/// The trend glyph of the design (24 x 24 grid): the baseline, the rising line and its arrow head.
private struct FormInfoTrendShape: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 24
        let originX = rect.midX - 12 * scale
        let originY = rect.midY - 12 * scale
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: originX + x * scale, y: originY + y * scale)
        }
        var path = Path()
        path.move(to: point(3, 20))
        path.addLine(to: point(21, 20))
        path.move(to: point(4, 16))
        path.addLine(to: point(9, 11))
        path.addLine(to: point(13, 14))
        path.addLine(to: point(20, 7))
        path.move(to: point(16, 7))
        path.addLine(to: point(20, 7))
        path.addLine(to: point(20, 11))
        return path
    }
}

// MARK: - Title bar

private struct FormInfoHeader: View {
    let onDone: () -> Void

    var body: some View {
        ZStack {
            Text("Form")
                .font(PulseFont.headline)
                .foregroundStyle(PulseTheme.ink)
                .accessibilityAddTraits(.isHeader)
            HStack {
                Spacer(minLength: 0)
                Button(action: onDone) {
                    Text("Done")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(PulseTheme.green)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PulsePlainButtonStyle())
            }
        }
        .frame(height: 56)
        .padding(.horizontal, 16)
    }
}

// MARK: - Chip

/// Pill with the primary muscle (green) or the equipment / secondary muscles (grey).
private struct FormInfoChip: View {
    let text: String
    let isPrimary: Bool

    var body: some View {
        Text(verbatim: text)
            .font(.system(size: 13, weight: isPrimary ? .semibold : .regular))
            .foregroundStyle(isPrimary ? PulseTheme.greenText : PulseTheme.ink.opacity(0.8))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(fill, in: Capsule())
    }

    private var fill: Color {
        isPrimary ? FormInfoColors.greenWash : PulseTheme.chipFill
    }
}

// MARK: - Cue row

/// "1  Lie back with your eyes under the bar." A 24 pt green number badge and the cue text.
private struct FormInfoCueRow: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(verbatim: String(number))
                .pulseNumber(13, .bold)
                .foregroundStyle(PulseTheme.greenText)
                .frame(width: 24, height: 24)
                .background(FormInfoColors.greenWash, in: Circle())
            Text(verbatim: text)
                .font(PulseFont.subhead)
                .foregroundStyle(PulseTheme.ink)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step " + String(number) + ". " + text)
    }
}

// MARK: - Flow layout

/// Wraps its children onto several lines (a CSS flex-wrap row).
private struct FormInfoChipFlowLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    init(spacing: CGFloat = 6, lineSpacing: CGFloat = 6) {
        self.spacing = spacing
        self.lineSpacing = lineSpacing
    }

    struct Arrangement {
        var origins: [CGPoint]
        var size: CGSize
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let arrangement = arrange(width: bounds.width, subviews: subviews)
        for index in subviews.indices {
            let origin = arrangement.origins[index]
            subviews[index].place(
                at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                anchor: .topLeading,
                proposal: .unspecified
            )
        }
    }

    private func arrange(width: CGFloat?, subviews: Subviews) -> Arrangement {
        let limit: CGFloat = width ?? CGFloat.infinity
        var sizes: [CGSize] = []
        for subview in subviews {
            sizes.append(subview.sizeThatFits(.unspecified))
        }

        var origins = [CGPoint](repeating: .zero, count: sizes.count)
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0
        for index in sizes.indices {
            let itemSize = sizes[index]
            if x > 0 && x + itemSize.width > limit {
                x = 0
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            origins[index] = CGPoint(x: x, y: y)
            x += itemSize.width
            usedWidth = max(usedWidth, x)
            x += spacing
            rowHeight = max(rowHeight, itemSize.height)
        }
        return Arrangement(origins: origins, size: CGSize(width: usedWidth, height: y + rowHeight))
    }
}
#endif
