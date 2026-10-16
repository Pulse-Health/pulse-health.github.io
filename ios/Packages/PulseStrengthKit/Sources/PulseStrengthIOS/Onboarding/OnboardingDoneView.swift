#if os(iOS)
import SwiftUI
import UIKit
import PulseStrengthCore

/// The last screen: a check that draws itself, "You're all set." and what was chosen, as chips.
@MainActor
struct OnboardingDoneScreen: View {
    @ObservedObject var model: OnboardingModel
    let isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AccessibilityFocusState private var titleHasFocus: Bool

    private var copy: OnboardingCopy { model.copy }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                ScrollView {
                    VStack(spacing: 20) {
                        summaryBlock
                        finishButton
                    }
                    .padding(.horizontal, OnboardingTheme.heroInset)
                    .padding(.bottom, 20)
                }
            } else {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    summaryBlock
                        .padding(.bottom, 28)
                    Spacer(minLength: 0)
                    finishButton
                        .padding(.horizontal, OnboardingTheme.heroInset)
                        .padding(.top, 12)
                        .padding(.bottom, 12)
                }
            }
        }
        .onChange(of: isActive) { (_: Bool, active: Bool) in
            if active {
                titleHasFocus = true
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
    }

    private var summaryBlock: some View {
        VStack(spacing: 0) {
            OnboardingDoneBadge(isActive: isActive)
                .padding(.bottom, 28)
            Text(copy.text(.doneTitle))
                .pulseFont(34, .bold, relativeTo: .largeTitle)
                .foregroundStyle(Color.white)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($titleHasFocus)
            Text(copy.text(.doneSub))
                .pulseFont(17, .regular, relativeTo: .body)
                .foregroundStyle(OnboardingTheme.onMediaSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
            OnboardingWrapLayout(spacing: 8) {
                ForEach(summaryItems.indices, id: \.self) { (index: Int) in
                    chip(summaryItems[index])
                }
            }
            .padding(.top, 26)
            .padding(.horizontal, OnboardingTheme.heroInset)
        }
        .frame(maxWidth: .infinity)
    }

    private var summaryItems: [OnboardingSummaryItem] {
        model.summary
    }

    private func chip(_ item: OnboardingSummaryItem) -> some View {
        HStack(spacing: 6) {
            if item.isOn {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(OnboardingTheme.green)
                    .accessibilityHidden(true)
            }
            Text(item.text)
                .pulseFont(13, .semibold, relativeTo: .footnote)
                .foregroundStyle(item.isOn ? Color.white : OnboardingTheme.inkSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(OnboardingTheme.chipFill, in: Capsule())
        .accessibilityElement(children: .combine)
    }

    private var finishButton: some View {
        Button {
            model.finish()
        } label: {
            Text(copy.text(.doneStart))
        }
        .buttonStyle(OnboardingPrimaryButtonStyle())
        .accessibilityIdentifier("onboarding.finish")
    }
}

// MARK: - The check

/// A green ring and check that draw themselves, with two ripples going out from the ring.
@MainActor
private struct OnboardingDoneBadge: View {
    let isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var ringDrawn = true
    @State private var checkDrawn = true

    private static let size: CGFloat = 96

    var body: some View {
        ZStack {
            ripples
            Circle()
                .stroke(OnboardingTheme.greenTint, lineWidth: 5)
                .padding(2.5)
            Circle()
                .trim(from: 0, to: ringDrawn ? 1 : 0.0001)
                .stroke(OnboardingTheme.green, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(2.5)
            OnboardingCheckShape()
                .trim(from: 0, to: checkDrawn ? 1 : 0.0001)
                .stroke(OnboardingTheme.green, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
        }
        .frame(width: OnboardingDoneBadge.size, height: OnboardingDoneBadge.size)
        .accessibilityHidden(true)
        .task(id: isActive) {
            guard isActive, !reduceMotion else {
                ringDrawn = true
                checkDrawn = true
                return
            }
            ringDrawn = false
            checkDrawn = false
            try? await Task.sleep(nanoseconds: 60_000_000)
            withAnimation(Animation.easeOut(duration: 0.9).delay(0.15)) {
                ringDrawn = true
            }
            withAnimation(Animation.easeOut(duration: 0.5).delay(0.85)) {
                checkDrawn = true
            }
        }
    }

    /// Two rings that grow and fade, offset by half a period, starting after the check is drawn.
    private var ripples: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isActive || reduceMotion)) { context in
            ZStack {
                ripple(at: context.date, offset: 0)
                ripple(at: context.date, offset: 1.4)
            }
        }
    }

    private func ripple(at date: Date, offset: Double) -> some View {
        let period = 2.8
        let phase = (date.timeIntervalSinceReferenceDate + offset).truncatingRemainder(dividingBy: period) / period
        return Circle()
            .stroke(OnboardingTheme.green, lineWidth: 2)
            .scaleEffect(1 + 0.9 * phase)
            .opacity(isActive && !reduceMotion && checkDrawn ? 0.5 * (1 - phase) : 0)
    }
}

/// The check mark on a 96 x 96 grid.
private struct OnboardingCheckShape: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 96
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * scale, y: rect.minY + y * scale)
        }
        var path = Path()
        path.move(to: point(30, 49.5))
        path.addLine(to: point(42.5, 62))
        path.addLine(to: point(67, 36))
        return path
    }
}

// MARK: - Wrapping chips

/// Lays its children out in rows that wrap, each row centred (the summary chips).
struct OnboardingWrapLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = arrange(width: width, subviews: subviews)
        let height = rows.reduce(CGFloat(0)) { (total: CGFloat, row: Row) in total + row.height }
            + spacing * CGFloat(max(rows.count - 1, 0))
        let widest = rows.map { (row: Row) in row.width }.max() ?? 0
        return CGSize(width: proposal.width == nil ? widest : min(widest, width), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(width: bounds.width, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX + (bounds.width - row.width) / 2
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width && !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty {
            rows.append(current)
        }
        return rows
    }
}
#endif
