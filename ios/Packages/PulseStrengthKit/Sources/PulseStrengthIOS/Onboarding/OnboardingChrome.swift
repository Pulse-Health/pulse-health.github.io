#if os(iOS)
import SwiftUI
import UIKit
import PulseStrengthCore

// What stays on screen while the steps change: the top bar (brand or Back button, setup progress, pause button) and the toast.

/// The bar at the top: the brand on the hero screens, a Back button and the four setup bars on the setup screens, and the pause
/// button for the motion everywhere.
@MainActor
struct OnboardingTopBar: View {
    @ObservedObject var model: OnboardingModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var markDrawn: CGFloat = 0

    var body: some View {
        HStack(spacing: 0) {
            leading
            Spacer(minLength: 0)
            pauseButton
        }
        .padding(.leading, OnboardingTheme.heroInset)
        .padding(.trailing, OnboardingTheme.heroInset - 5)
        .frame(height: OnboardingTheme.topBarHeight)
        .overlay(progress)
        .onAppear {
            if reduceMotion {
                markDrawn = 1
            } else {
                withAnimation(Animation.easeOut(duration: 1.1).delay(0.35)) {
                    markDrawn = 1
                }
            }
        }
    }

    // MARK: Brand and Back

    private var showsBack: Bool {
        model.step.previous != nil
    }

    private var showsBrand: Bool {
        !model.step.isSetup
    }

    private var leading: some View {
        ZStack(alignment: .leading) {
            brand
                .opacity(showsBrand ? 1 : 0)
                .offset(x: showsBrand ? 0 : -10)
            backButton
                .opacity(showsBack ? 1 : 0)
                .offset(x: showsBack ? 0 : 10)
                .allowsHitTesting(showsBack)
                .accessibilityHidden(!showsBack)
        }
        .animation(reduceMotion ? nil : Animation.easeOut(duration: 0.4), value: model.step)
    }

    private var brand: some View {
        HStack(spacing: 9) {
            OnboardingMarkTile(size: 30, drawn: markDrawn)
            Text(OnboardingBrand.name)
                .pulseFont(22, .bold, relativeTo: .title2)
                .foregroundStyle(Color.white)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(OnboardingBrand.name)
        .accessibilityHidden(!showsBrand)
    }

    private var backButton: some View {
        Button {
            model.goBack()
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 15, weight: .bold))
        }
        .buttonStyle(OnboardingRoundButtonStyle())
        .padding(.leading, -5)
        .disabled(model.isBusy)
        .accessibilityLabel(model.copy.text(.setupBack))
        .accessibilityIdentifier("onboarding.back")
    }

    // MARK: Progress

    /// How many of the four setup bars are filled: the step's number; all four on the last screen.
    private var filledBars: Int {
        if model.step == .done { return OnboardingStep.setupSteps.count }
        return model.step.setupNumber ?? 0
    }

    private var progress: some View {
        HStack(spacing: 6) {
            ForEach(0..<OnboardingStep.setupSteps.count, id: \.self) { (index: Int) in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.2))
                    Capsule()
                        .fill(OnboardingTheme.green)
                        .scaleEffect(x: index < filledBars ? 1 : 0.0001, y: 1, anchor: .leading)
                }
                .frame(width: 30, height: 4)
            }
        }
        .animation(reduceMotion ? nil : Animation.easeOut(duration: 0.6), value: filledBars)
        .opacity(model.step.isSetup ? 1 : 0)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.copy.setupProgress(max(filledBars, 1), of: OnboardingStep.setupSteps.count))
        .accessibilityHidden(!model.step.isSetup)
    }

    // MARK: Pause

    private var pauseButton: some View {
        Button {
            model.toggleMotion()
        } label: {
            Image(systemName: model.isMotionPaused ? "play.fill" : "pause.fill")
                .font(.system(size: 13, weight: .bold))
        }
        .buttonStyle(OnboardingRoundButtonStyle())
        .accessibilityLabel(model.copy.text(model.isMotionPaused ? .videoPlay : .videoPause))
        .accessibilityIdentifier("onboarding.motion")
    }
}

/// The message that drops in from the top for a moment (a toast).
@MainActor
struct OnboardingToast: View {
    @ObservedObject var model: OnboardingModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack {
            if let notice = model.notice {
                Text(notice.text)
                    .pulseFont(14, .medium, relativeTo: .subheadline)
                    .foregroundStyle(Color.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(OnboardingTheme.toastFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: Color.black.opacity(0.45), radius: 15, x: 0, y: 10)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .transition(reduceMotion ? AnyTransition.opacity : AnyTransition.move(edge: .top).combined(with: .opacity))
                    .accessibilityAddTraits(.isStaticText)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(reduceMotion ? nil : Animation.spring(response: 0.5, dampingFraction: 0.85), value: model.notice)
        .allowsHitTesting(false)
        .task(id: model.notice?.id) {
            guard let notice = model.notice else { return }
            AccessibilityNotification.Announcement(notice.text).post()
            do {
                try await Task.sleep(nanoseconds: 2_400_000_000)
            } catch {
                return
            }
            model.dismissNotice(id: notice.id)
        }
    }
}
#endif
