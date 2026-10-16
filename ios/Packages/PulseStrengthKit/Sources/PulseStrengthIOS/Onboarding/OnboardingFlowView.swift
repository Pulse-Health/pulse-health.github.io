#if os(iOS)
import SwiftUI
import PulseStrengthCore

/// The whole first-run flow as one view: the hero clip behind, the welcome screen, the account sheet, the four setup steps and the
/// last screen, with the top bar and the toast above them.
///
/// The view only renders `OnboardingModel`; it reports the end of the flow through `onComplete` (once). It is dark only: the clip is
/// the surface.
@MainActor
public struct OnboardingFlowView: View {
    @StateObject private var model: OnboardingModel
    private let onComplete: (OnboardingOutcome) -> Void

    @State private var highlight = 0
    @State private var screenHeight: CGFloat = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// `state` starts the flow at another screen (previews and tests); a new user starts at the welcome screen.
    public init(
        services: OnboardingServices,
        copy: OnboardingCopy = OnboardingCopy(),
        state: OnboardingState = OnboardingState(),
        onComplete: @escaping (OnboardingOutcome) -> Void
    ) {
        self._model = StateObject(wrappedValue: OnboardingModel(services: services, copy: copy, state: state))
        self.onComplete = onComplete
    }

    public var body: some View {
        ZStack {
            OnboardingBackdrop(step: model.step, highlight: highlight, isMotionPaused: model.isMotionPaused)
            screens
            VStack(spacing: 0) {
                OnboardingTopBar(model: model)
                Spacer(minLength: 0)
            }
            OnboardingToast(model: model)
        }
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: OnboardingScreenHeightKey.self, value: proxy.size.height)
            }
            .ignoresSafeArea()
        )
        .onPreferenceChange(OnboardingScreenHeightKey.self) { (height: CGFloat) in
            screenHeight = height
        }
        .environment(\.onboardingIsCompact, screenHeight > 0 && screenHeight < OnboardingTheme.compactHeight)
        .preferredColorScheme(.dark)
        .tint(OnboardingTheme.green)
        .dynamicTypeSize(PulseDynamicType.screenRange)
        .sheet(isPresented: authSheetIsPresented) {
            authSheet
        }
        .onChange(of: model.state.outcome) { (_: OnboardingOutcome?, outcome: OnboardingOutcome?) in
            if let outcome = outcome {
                onComplete(outcome)
            }
        }
    }

    // MARK: Screens

    private var stepAnimation: Animation? {
        reduceMotion ? nil : Animation.easeOut(duration: 0.55)
    }

    /// Where the active setup screen is among the five (profile ... done); -1 on the welcome screen and under the account sheet.
    private var activeIndex: Int {
        switch model.step {
        case .welcome, .auth: return -1
        case .profile: return 0
        case .health: return 1
        case .coach: return 2
        case .notify: return 3
        case .done: return 4
        }
    }

    private var screens: some View {
        ZStack {
            OnboardingWelcomeView(model: model, highlight: $highlight)
                .opacity(model.step == .welcome ? 1 : 0)
                .offset(y: model.step == .welcome ? 0 : 18)
                .allowsHitTesting(model.step == .welcome)
                .accessibilityHidden(model.step != .welcome)

            setupScreens
                .padding(.top, OnboardingTheme.topBarHeight + 12)
        }
        .animation(stepAnimation, value: model.step)
    }

    private var setupScreens: some View {
        ZStack {
            OnboardingProfileScreen(model: model, isActive: activeIndex == 0)
                .modifier(OnboardingScreenPlacement(index: 0, activeIndex: activeIndex))
            OnboardingHealthScreen(model: model, isActive: activeIndex == 1)
                .modifier(OnboardingScreenPlacement(index: 1, activeIndex: activeIndex))
            OnboardingCoachScreen(model: model, isActive: activeIndex == 2)
                .modifier(OnboardingScreenPlacement(index: 2, activeIndex: activeIndex))
            OnboardingNotifyScreen(model: model, isActive: activeIndex == 3)
                .modifier(OnboardingScreenPlacement(index: 3, activeIndex: activeIndex))
            OnboardingDoneScreen(model: model, isActive: activeIndex == 4)
                .modifier(OnboardingScreenPlacement(index: 4, activeIndex: activeIndex))
        }
    }

    // MARK: Account sheet

    private var authSheetIsPresented: Binding<Bool> {
        Binding<Bool>(
            get: { model.step == .auth },
            set: { (presented: Bool) in
                if !presented {
                    model.closeAuth()
                }
            }
        )
    }

    /// The sheet sets its own detents (it is as tall as its form); what is the same for every presentation is set here.
    private var authSheet: some View {
        OnboardingAuthSheet(model: model)
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(PulseTheme.sheetRadius)
            .presentationBackground(.regularMaterial)
            .interactiveDismissDisabled(model.isBusy)
            .preferredColorScheme(.dark)
            .tint(OnboardingTheme.green)
            .dynamicTypeSize(PulseDynamicType.screenRange)
    }
}

/// The height of the screen, reported from behind the content (which respects the safe areas).
private struct OnboardingScreenHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// A setup screen waits to the right until its turn, slides to the middle, and leaves to the left (the order of the steps is
/// the same as the order of the screens, so going back reverses it).
private struct OnboardingScreenPlacement: ViewModifier {
    let index: Int
    let activeIndex: Int

    func body(content: Content) -> some View {
        let isActive = index == activeIndex
        return content
            .opacity(isActive ? 1 : 0)
            .offset(x: isActive ? 0 : (index < activeIndex ? -32 : 32))
            .allowsHitTesting(isActive)
            .accessibilityHidden(!isActive)
    }
}
#endif
