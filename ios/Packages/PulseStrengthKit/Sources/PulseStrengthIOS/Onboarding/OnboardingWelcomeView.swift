#if os(iOS)
import SwiftUI
import UIKit
import PulseStrengthCore

/// The first screen: three highlights over the hero clip, story style. The bars at the top fill while a highlight is on screen
/// (6.5 s), a tap on a bar or a swipe moves on, holding the text pauses. Under them the preview of what the highlight is about, then
/// "Get started" and "Log in".
@MainActor
struct OnboardingWelcomeView: View {
    @ObservedObject var model: OnboardingModel
    /// The highlight on screen, for the backdrop (each one zooms the picture in a little more).
    @Binding var highlight: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.onboardingIsCompact) private var isCompact

    @State private var playback = HighlightPlayback()
    @State private var isHeld = false
    /// False until the screen has appeared once: the block rises in piece by piece.
    @State private var hasAppeared = false

    private var copy: OnboardingCopy { model.copy }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 0) {
                heading
                pager
                    .padding(.bottom, 14)
                    .modifier(OnboardingRise(delay: 0.35, visible: hasAppeared))
                highlights
                    .modifier(OnboardingRise(delay: 0.45, visible: hasAppeared))
                actions
                    .padding(.top, isCompact ? 18 : 22)
                    .modifier(OnboardingRise(delay: 0.6, visible: hasAppeared))
            }
            .padding(.horizontal, OnboardingTheme.heroInset)
            .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: isRunning) {
            await runClock()
        }
        .onChange(of: playback.index) { (_: Int, newIndex: Int) in
            highlight = newIndex
        }
        .onAppear {
            highlight = playback.index
            hasAppeared = true
        }
    }

    // MARK: Clock

    /// Things move while the welcome screen is in front, motion is wanted and the app is in the foreground.
    private var isAnimating: Bool {
        model.step == .welcome && !model.isMotionPaused && !reduceMotion && scenePhase == .active
    }

    /// The bars additionally stop while somebody holds the text.
    private var isRunning: Bool {
        isAnimating && !isHeld
    }

    private func runClock() async {
        guard isRunning else { return }
        var last = Date()
        while !Task.isCancelled {
            do {
                try await Task.sleep(nanoseconds: 50_000_000)
            } catch {
                return
            }
            let now = Date()
            playback.advance(by: now.timeIntervalSince(last))
            last = now
        }
    }

    private func select(_ index: Int) {
        playback.select(index)
    }

    // MARK: Pieces

    /// The page title for VoiceOver ("Welcome to Rebase"); nothing to see.
    private var heading: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .accessibilityElement()
            .accessibilityLabel(copy.text(.welcomeHeading))
            .accessibilityAddTraits(.isHeader)
    }

    private var pager: some View {
        HStack(spacing: 6) {
            ForEach(0..<playback.count, id: \.self) { (index: Int) in
                Button {
                    select(index)
                } label: {
                    bar(index)
                }
                .buttonStyle(PulsePlainButtonStyle())
                .accessibilityLabel(copy.showHighlight(index + 1, of: playback.count))
                .accessibilityValue(index == playback.index ? copy.highlightPosition(index + 1, of: playback.count) : "")
                .accessibilityAddTraits(index == playback.index ? .isSelected : [])
                .accessibilityIdentifier("onboarding.highlight.\(index + 1)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(copy.text(.pagerLabel))
    }

    private func bar(_ index: Int) -> some View {
        ZStack(alignment: .leading) {
            Capsule().fill(Color.white.opacity(0.26))
            Capsule()
                .fill(Color.white)
                .scaleEffect(x: fill(of: index), y: 1, anchor: .leading)
        }
        .frame(height: 3)
        .frame(maxWidth: .infinity, minHeight: 20)
        .contentShape(Rectangle())
    }

    /// With Reduce Motion the bars do not run; the one of the current highlight is full.
    private func fill(of index: Int) -> CGFloat {
        if reduceMotion {
            return index <= playback.index ? 1 : 0.0001
        }
        return CGFloat(max(playback.fill(of: index), 0.0001))
    }

    // MARK: Highlights

    private var highlights: some View {
        VStack(alignment: .leading, spacing: 0) {
            slides
            if !isCompact {
                proofs
                    .padding(.top, 20)
            }
        }
        .contentShape(Rectangle())
        .simultaneousGesture(holdAndSwipe)
    }

    /// Hold to pause, swipe sideways to move (like stories).
    private var holdAndSwipe: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                if !isHeld {
                    isHeld = true
                }
            }
            .onEnded { value in
                isHeld = false
                let across = value.translation.width
                let down = value.translation.height
                if abs(across) > 40 && abs(across) > abs(down) {
                    if across < 0 {
                        playback.selectNext()
                    } else {
                        playback.selectPrevious()
                    }
                }
            }
    }

    private var slideAnimation: Animation? {
        reduceMotion ? nil : Animation.easeOut(duration: 0.55)
    }

    private var slides: some View {
        ZStack(alignment: .topLeading) {
            ForEach(0..<playback.count, id: \.self) { (index: Int) in
                slide(index)
            }
        }
        .animation(slideAnimation, value: playback.index)
    }

    private func slide(_ index: Int) -> some View {
        let isActive = index == playback.index
        return VStack(alignment: .leading, spacing: 10) {
            Text(copy.text(OnboardingWelcomeView.titleKey(index)))
                .pulseFont(isCompact ? 30 : 34, .bold, relativeTo: .largeTitle)
                .foregroundStyle(Color.white)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(copy.text(OnboardingWelcomeView.subtitleKey(index)))
                .pulseFont(17, .regular, relativeTo: .body)
                .foregroundStyle(OnboardingTheme.onMediaSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(isActive ? 1 : 0)
        .offset(y: isActive ? 0 : (index < playback.index ? -10 : 12))
        .accessibilityHidden(!isActive)
    }

    private static func titleKey(_ index: Int) -> OnboardingText {
        switch index {
        case 0: return .highlight1Title
        case 1: return .highlight2Title
        default: return .highlight3Title
        }
    }

    private static func subtitleKey(_ index: Int) -> OnboardingText {
        switch index {
        case 0: return .highlight1Sub
        case 1: return .highlight2Sub
        default: return .highlight3Sub
        }
    }

    /// The previews, one per highlight. They are pictures: VoiceOver skips them.
    private var proofs: some View {
        ZStack {
            OnboardingPlanCard(copy: copy, isActive: playback.index == 0)
                .modifier(OnboardingHighlightSwap(index: 0, current: playback.index))
            OnboardingRestCard(copy: copy, isActive: playback.index == 1, isAnimating: isAnimating)
                .modifier(OnboardingHighlightSwap(index: 1, current: playback.index))
            OnboardingRecordCard(copy: copy, isActive: playback.index == 2)
                .modifier(OnboardingHighlightSwap(index: 2, current: playback.index))
        }
        .animation(slideAnimation, value: playback.index)
        .dynamicTypeSize(DynamicTypeSize.large)
        .accessibilityHidden(true)
    }

    // MARK: Actions

    private var actions: some View {
        VStack(spacing: 0) {
            Button {
                model.openAuth(.signUp)
            } label: {
                Text(copy.text(.welcomeStart))
            }
            .buttonStyle(OnboardingPrimaryButtonStyle(glow: true))
            .accessibilityIdentifier("onboarding.start")

            ViewThatFits(in: .horizontal) {
                loginLine
                loginStack
            }
            .frame(maxWidth: .infinity)

            legal
        }
    }

    private var loginPrompt: some View {
        Text(copy.text(.welcomeHaveAccount))
            .pulseFont(15, .regular, relativeTo: .subheadline)
            .foregroundStyle(OnboardingTheme.onMediaSecondary)
    }

    private var loginButton: some View {
        Button {
            model.openAuth(.logIn)
        } label: {
            Text(copy.text(.welcomeLogin))
        }
        .buttonStyle(OnboardingLinkButtonStyle())
        .accessibilityIdentifier("onboarding.login")
    }

    private var loginLine: some View {
        HStack(spacing: 2) {
            loginPrompt
            loginButton
        }
        .frame(minHeight: 48)
    }

    private var loginStack: some View {
        VStack(spacing: 0) {
            loginPrompt
            loginButton
        }
    }

    private var legal: some View {
        Text(OnboardingRichText.attributed(copy.legalWelcome, copy: copy))
            .pulseFont(12, .regular, relativeTo: .caption)
            .foregroundStyle(OnboardingTheme.onMediaTertiary)
            .tint(OnboardingTheme.onMediaSecondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
    }
}

// MARK: - Helpers

/// One of the previews: faded in and out, and nudged up or down by where it is in the order.
private struct OnboardingHighlightSwap: ViewModifier {
    let index: Int
    let current: Int

    func body(content: Content) -> some View {
        let isActive = index == current
        return content
            .opacity(isActive ? 1 : 0)
            .offset(y: isActive ? 0 : (index < current ? -10 : 12))
    }
}

/// The first appearance: a piece of the block rises in (opacity and 16 pt), one after the other.
struct OnboardingRise: ViewModifier {
    let delay: Double
    let visible: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let shown = visible || reduceMotion
        return content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 16)
            .animation(reduceMotion ? nil : Animation.easeOut(duration: 0.9).delay(delay), value: visible)
    }
}
#endif
