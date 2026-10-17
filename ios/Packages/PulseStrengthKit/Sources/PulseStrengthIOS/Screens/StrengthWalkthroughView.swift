#if os(iOS)
import SwiftUI
import UIKit
import PulseStrengthCore

/// The walkthrough that follows onboarding: a short, swipeable tour of the Strength feature (the hub, logging sets, the
/// rest timer, shaping a workout, finishing, and where everything else lives). Each page has a small picture of the part
/// of the app it talks about, a title, a sentence and up to three tips.
///
/// It is presented as a sheet by `PulseStrengthRootView` when `StrengthAppEnvironment.showsWalkthrough` is true; the host app
/// sets that through `showWalkthroughAfterOnboarding()` once onboarding is done, and the hub's More menu replays it.
/// `onClose` is called by "Skip" and by "Get Started" on the last page (a swipe down on the sheet closes it as well).
///
/// The pages scroll, so the tour stays usable at the largest text sizes and on an iPhone SE. The pictures are drawn
/// with fixed sizes (they are decoration, hidden from VoiceOver); everything the user has to read is real, scalable text.
@MainActor
public struct StrengthWalkthroughView: View {
    private let steps: [WalkthroughStep]
    private let onClose: () -> Void

    @State private var progress: WalkthroughProgress

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(steps: [WalkthroughStep] = Walkthrough.steps, onClose: @escaping () -> Void) {
        self.steps = steps
        self.onClose = onClose
        self._progress = State(initialValue: WalkthroughProgress(count: steps.count))
    }

    // MARK: Body

    public var body: some View {
        VStack(spacing: 0) {
            topBar
            pages
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PulseTheme.ground.ignoresSafeArea())
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack {
            Button {
                goBack()
            } label: {
                Label("Back", systemImage: "chevron.left")
                    .pulseFont(17, relativeTo: .body)
                    .foregroundStyle(PulseTheme.greenText)
                    .frame(minWidth: 44, alignment: .leading)
                    .pulseScaledFrame(minHeight: 44, relativeTo: PulseDynamicType.controlHeightStyle)
                    .contentShape(Rectangle())
            }
            .opacity(progress.isFirst ? 0 : 1)
            .disabled(progress.isFirst)
            .accessibilityHidden(progress.isFirst)
            .accessibilityIdentifier("walkthrough-back")
            Spacer(minLength: 8)
            Button {
                onClose()
            } label: {
                Text("Skip")
                    .pulseFont(17, relativeTo: .body)
                    .foregroundStyle(PulseTheme.inkSecondary)
                    .frame(minWidth: 44, alignment: .trailing)
                    .pulseScaledFrame(minHeight: 44, relativeTo: PulseDynamicType.controlHeightStyle)
                    .contentShape(Rectangle())
            }
            .opacity(progress.isLast ? 0 : 1)
            .disabled(progress.isLast)
            .accessibilityHidden(progress.isLast)
            .accessibilityIdentifier("walkthrough-skip")
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        // The same 560 pt cap as the page and the footer below, so Back and Skip stay over them on a wide screen.
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
    }

    // MARK: Pages

    private var pages: some View {
        TabView(selection: pageBinding) {
            ForEach(0..<steps.count, id: \.self) { (index: Int) in
                WalkthroughPage(step: steps[index])
                    .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
    }

    /// The pager and the buttons share one `WalkthroughProgress`: a swipe moves it, so does "Next".
    private var pageBinding: Binding<Int> {
        Binding<Int>(
            get: {
                progress.index
            },
            set: { (newIndex: Int) in
                progress.go(to: newIndex)
            }
        )
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: 18) {
            pageDots
            Button {
                advance()
            } label: {
                Text(progress.isLast ? "Get Started" : "Next")
            }
            .buttonStyle(PulsePrimaryButtonStyle())
            .accessibilityIdentifier("walkthrough-next")
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 20)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
    }

    private var pageDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<progress.count, id: \.self) { (index: Int) in
                Circle()
                    .fill(index == progress.index ? PulseTheme.green : PulseTheme.progressTrackCurrent)
                    .frame(width: 8, height: 8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Walkthrough page")
        .accessibilityValue(progress.positionText)
    }

    // MARK: Actions

    private var pageAnimation: Animation? {
        reduceMotion ? nil : Animation.easeInOut(duration: 0.3)
    }

    private func advance() {
        if progress.isLast {
            onClose()
            return
        }
        withAnimation(pageAnimation) {
            _ = progress.advance()
        }
        announcePage()
    }

    private func goBack() {
        withAnimation(pageAnimation) {
            _ = progress.goBack()
        }
        announcePage()
    }

    /// Tells a VoiceOver user which page "Next" or "Back" has moved to (focus stays on the button, so nothing else would).
    private func announcePage() {
        guard UIAccessibility.isVoiceOverRunning, steps.indices.contains(progress.index) else { return }
        UIAccessibility.post(
            notification: .announcement,
            argument: steps[progress.index].title + ", " + progress.positionText
        )
    }
}

// MARK: - One page

private struct WalkthroughPage: View {
    let step: WalkthroughStep

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                WalkthroughIllustration(step: step)
                    .padding(.top, 8)
                    .accessibilityHidden(true)
                VStack(spacing: 10) {
                    Text(step.title)
                        .pulseFont(28, .bold, relativeTo: .title)
                        .foregroundStyle(PulseTheme.ink)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text(step.message)
                        .pulseFont(17, relativeTo: .body)
                        .foregroundStyle(PulseTheme.inkSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !step.points.isEmpty {
                    points
                }
            }
            .padding(.horizontal, 24)
            // Clears the fade below, so the last line of a scrolled-to-the-end page is not faded.
            .padding(.bottom, 36)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        // On a small phone or at large text the page is taller than the space above the dots and scrolls; without a cue the
        // cut-off edge looks like the end of the content. The bottom fades out instead (invisible when everything fits).
        .mask {
            VStack(spacing: 0) {
                Rectangle()
                LinearGradient(
                    colors: [Color.black, Color.black.opacity(0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 28)
            }
        }
    }

    private var points: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(step.points, id: \.self) { (point: String) in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .pulseFont(16, relativeTo: .body)
                        .foregroundStyle(PulseTheme.green)
                        .padding(.top, 1)
                        .accessibilityHidden(true)
                    Text(point)
                        .pulseFont(15, relativeTo: .subheadline)
                        .foregroundStyle(PulseTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .pulseCard()
    }
}

// MARK: - Pictures

/// A small, simplified picture of the part of the app a step is about, drawn with the real theme colours. Fixed sizes on
/// purpose: it is decoration and must look the same at every text size.
private struct WalkthroughIllustration: View {
    let step: WalkthroughStep

    var body: some View {
        switch step.id {
        case "welcome":
            welcome
        case "today":
            todayCard
        case "log":
            setRows
        case "rest":
            restDock
        case "shape":
            shapeList
        case "finish":
            summary
        case "more":
            moreMenu
        default:
            symbolBadge(step.symbol)
        }
    }

    // MARK: Pieces

    private func symbolBadge(_ name: String) -> some View {
        ZStack {
            Circle()
                .fill(PulseTheme.greenTint)
            Image(systemName: name)
                .font(.system(size: 52, weight: .semibold))
                .foregroundStyle(PulseTheme.green)
        }
        .frame(width: 120, height: 120)
    }

    private var welcome: some View {
        ZStack {
            Circle()
                .fill(PulseTheme.greenTint)
            StrengthDumbbellGlyph(size: 60, color: PulseTheme.green, strokeWidth: 2.2)
        }
        .frame(width: 120, height: 120)
    }

    /// The recommended-workout card of the hub.
    private var todayCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Today \u{00B7} Recommended")
                    .font(.system(size: 13))
                    .foregroundStyle(PulseTheme.inkSecondary)
                Text("Upper A \u{00B7} Push")
                    .font(PulseFont.number(24))
                    .foregroundStyle(PulseTheme.ink)
            }
            HStack(spacing: 5) {
                muscleChip("Chest 88%", color: PulseTheme.recoveryGood)
                muscleChip("Shoulders 74%", color: PulseTheme.recoveryFair)
                muscleChip("Arms 91%", color: PulseTheme.recoveryGood)
            }
            HStack(spacing: 8) {
                Text("Start Workout")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(PulseTheme.onGreen)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(PulseTheme.green, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(PulseTheme.greenText)
                    .frame(width: 44, height: 44)
                    .background(PulseTheme.cellFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(16)
        .frame(maxWidth: 320, alignment: .leading)
        .pulseCard()
    }

    private func muscleChip(_ title: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(PulseTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(PulseTheme.cellFill, in: Capsule())
    }

    /// Three set rows: a logged warm-up, a logged working set, and the next set with its ring.
    private var setRows: some View {
        VStack(spacing: 6) {
            setRow(type: .warmup, number: "W", weight: "40", reps: "8", done: true, isNext: false)
            setRow(type: .normal, number: "1", weight: "80", reps: "6", done: true, isNext: false)
            setRow(type: .normal, number: "2", weight: "80", reps: "6", done: false, isNext: true)
        }
        .padding(10)
        .frame(maxWidth: 320)
        .pulseCard()
    }

    private func setRow(type: SetType, number: String, weight: String, reps: String, done: Bool, isNext: Bool) -> some View {
        HStack(spacing: 8) {
            Text(number)
                .font(PulseFont.number(14))
                .foregroundStyle(type.badgeForeground)
                .frame(width: 32, height: 32)
                .background(type.badgeBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Spacer(minLength: 4)
            valueCell(weight, unit: "kg", filled: done)
            valueCell(reps, unit: "reps", filled: done)
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 26))
                .foregroundStyle(done ? PulseTheme.green : PulseTheme.inkTertiary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(done ? PulseTheme.doneRowFill : PulseTheme.rowFill, in: RoundedRectangle(cornerRadius: PulseTheme.rowRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PulseTheme.rowRadius, style: .continuous)
                .stroke(PulseTheme.nextRowRing, lineWidth: isNext ? 1.5 : 0)
        )
    }

    private func valueCell(_ value: String, unit: String, filled: Bool) -> some View {
        HStack(spacing: 3) {
            Text(value)
                .font(PulseFont.number(16, .semibold))
                .foregroundStyle(PulseTheme.ink)
            Text(unit)
                .font(.system(size: 11))
                .foregroundStyle(PulseTheme.inkSecondary)
        }
        .frame(width: 72, height: 32)
        .background(filled ? PulseTheme.cellOnTint : PulseTheme.cellFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    /// The rest dock: the countdown, a progress bar and the -15 / +15 / Skip buttons.
    private var restDock: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Rest")
                        .font(.system(size: 12))
                        .foregroundStyle(PulseTheme.inkSecondary)
                    Text("1:30")
                        .font(PulseFont.number(32))
                        .monospacedDigit()
                        .foregroundStyle(PulseTheme.ink)
                }
                Spacer(minLength: 4)
                dockButton("\u{2212}15")
                dockButton("+15")
                dockButton("Skip")
            }
            GeometryReader { (proxy: GeometryProxy) in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(PulseTheme.progressTrack)
                    Capsule()
                        .fill(PulseTheme.progress)
                        .frame(width: proxy.size.width * 0.6)
                }
            }
            .frame(height: 6)
        }
        .padding(16)
        .frame(maxWidth: 320)
        .pulseCard()
    }

    private func dockButton(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(PulseTheme.greenText)
            .frame(minWidth: 44, minHeight: 36)
            .padding(.horizontal, 4)
            .background(PulseTheme.cellFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    /// The exercise list with its drag handles and options buttons, and the Undo toast.
    private var shapeList: some View {
        VStack(spacing: 12) {
            VStack(spacing: 0) {
                exerciseRow("Bench press")
                Divider()
                exerciseRow("Incline press")
                Divider()
                exerciseRow("Cable fly")
            }
            .padding(.horizontal, 12)
            .pulseCard()
            HStack(spacing: 14) {
                Text("Set deleted")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.white)
                Text("Undo")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(PulseTheme.toastAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(PulseTheme.toastFill, in: Capsule())
        }
        .frame(maxWidth: 320)
    }

    private func exerciseRow(_ name: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(PulseTheme.inkTertiary)
            Text(name)
                .font(.system(size: 16))
                .foregroundStyle(PulseTheme.ink)
            Spacer(minLength: 4)
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 20))
                .foregroundStyle(PulseTheme.greenText)
        }
        .frame(minHeight: 46)
    }

    /// The summary header: the trophy, the title and the three totals.
    private var summary: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(PulseTheme.prFill)
                Image(systemName: "trophy.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(PulseTheme.prText)
            }
            .frame(width: 64, height: 64)
            Text("Workout Complete")
                .font(PulseFont.number(20))
                .foregroundStyle(PulseTheme.ink)
            HStack(spacing: 0) {
                total("12", caption: "sets")
                total("4,860", caption: "kg volume")
                total("1", caption: "new PR")
            }
        }
        .padding(16)
        .frame(maxWidth: 320)
        .pulseCard()
    }

    private func total(_ value: String, caption: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(PulseFont.number(20))
                .foregroundStyle(PulseTheme.ink)
            Text(caption)
                .font(.system(size: 12))
                .foregroundStyle(PulseTheme.inkSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    /// The hub's More menu, with the walkthrough entry highlighted.
    private var moreMenu: some View {
        VStack(spacing: 0) {
            menuRow("Exercise Library", systemImage: "magnifyingglass", highlighted: false)
            Divider()
            menuRow("Import Plan\u{2026}", systemImage: "square.and.arrow.down", highlighted: false)
            Divider()
            menuRow("Settings", systemImage: "gearshape", highlighted: false)
            Divider()
            menuRow("App Walkthrough", systemImage: "questionmark.circle", highlighted: true)
        }
        .frame(maxWidth: 280)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .pulseCard(radius: 14)
    }

    private func menuRow(_ title: String, systemImage: String, highlighted: Bool) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 16, weight: highlighted ? .semibold : .regular))
                .foregroundStyle(highlighted ? PulseTheme.greenText : PulseTheme.ink)
            Spacer(minLength: 4)
            Image(systemName: systemImage)
                .font(.system(size: 16))
                .foregroundStyle(highlighted ? PulseTheme.greenText : PulseTheme.inkSecondary)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 46)
        .background(highlighted ? PulseTheme.greenTint : Color.clear)
    }
}
#endif
