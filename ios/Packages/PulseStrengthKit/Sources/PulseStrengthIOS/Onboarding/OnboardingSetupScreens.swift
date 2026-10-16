#if os(iOS)
import SwiftUI
import UIKit
import PulseStrengthCore

// The four numbered setup steps: profile (main goal and experience, the coaching profile of the privacy policy), Apple Health,
// AI Coaching (explicit consent, off unless turned on), notifications.

/// The inside of a primary button that waits for the system: a spinner instead of the icon while it is up.
private struct OnboardingActionLabel: View {
    let title: String
    let symbol: String?
    let isBusy: Bool

    var body: some View {
        HStack(spacing: 8) {
            if isBusy {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(Color.black)
            } else if let symbol = symbol {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
            }
            Text(title)
        }
    }
}

/// A card-sized button (the goal options): shrinks a little while pressed.
private struct OnboardingCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}

// MARK: - 1 · Profile

/// "What are you training for?": one main goal and one experience level, both needed to go on.
@MainActor
struct OnboardingProfileScreen: View {
    @ObservedObject var model: OnboardingModel
    let isActive: Bool

    @Environment(\.onboardingIsCompact) private var isCompact
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var copy: OnboardingCopy { model.copy }

    var body: some View {
        OnboardingSetupLayout(
            title: copy.text(.profileTitle),
            subtitle: copy.text(.profileSub),
            isActive: isActive,
            content: {
                VStack(alignment: .leading, spacing: 0) {
                    goals
                    levels
                        .padding(.top, isCompact ? 16 : 22)
                }
            },
            foot: {
                Button {
                    model.continueFromProfile()
                } label: {
                    Text(copy.text(.profileContinue))
                }
                .buttonStyle(OnboardingPrimaryButtonStyle())
                .disabled(!model.state.canContinueFromProfile)
                .accessibilityIdentifier("onboarding.profile.continue")
            }
        )
    }

    // MARK: Main goal

    private var goals: some View {
        VStack(spacing: isCompact ? 8 : 10) {
            ForEach(TrainingGoal.allCases, id: \.self) { (goal: TrainingGoal) in
                goalCard(goal)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(copy.text(.profileGoal))
    }

    private func goalCard(_ goal: TrainingGoal) -> some View {
        let isSelected = model.answers.goal == goal
        let shape = RoundedRectangle(cornerRadius: PulseTheme.cardRadius, style: .continuous)
        return Button {
            if !isSelected {
                UISelectionFeedbackGenerator().selectionChanged()
            }
            model.selectGoal(goal)
        } label: {
            HStack(spacing: isCompact ? 12 : 14) {
                OnboardingIconTile(
                    tint: OnboardingProfileScreen.tint(of: goal),
                    size: isCompact ? 36 : 44,
                    radius: isCompact ? 10 : 12
                ) {
                    goalIcon(goal)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(copy.text(OnboardingSummary.goalText(goal)))
                        .pulseFont(isCompact ? 16 : 17, .semibold, relativeTo: .body)
                        .foregroundStyle(Color.white)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if !isCompact {
                        Text(copy.text(OnboardingSummary.goalSubtitleText(goal)))
                            .pulseFont(13, .regular, relativeTo: .footnote)
                            .foregroundStyle(OnboardingTheme.inkSecondary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                checkmark(isSelected)
            }
            .padding(.leading, isCompact ? 12 : 14)
            .padding(.trailing, 16)
            .padding(.vertical, isCompact ? 8 : 12)
            .frame(maxWidth: .infinity, minHeight: isCompact ? 52 : 76, alignment: .leading)
            .background(isSelected ? OnboardingTheme.selectedFill : OnboardingTheme.card.opacity(0.72), in: shape)
            .overlay(
                shape.strokeBorder(
                    isSelected ? OnboardingTheme.nextRowRing : Color.white.opacity(0.12),
                    lineWidth: isSelected ? 1.5 : 0.5
                )
            )
            .contentShape(shape)
        }
        .buttonStyle(OnboardingCardButtonStyle())
        .animation(Animation.easeOut(duration: 0.25), value: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("onboarding.goal." + goal.rawValue)
    }

    private func checkmark(_ isSelected: Bool) -> some View {
        ZStack {
            Circle()
                .fill(isSelected ? OnboardingTheme.green : Color.clear)
            Circle()
                .strokeBorder(Color.white.opacity(isSelected ? 0 : 0.28), lineWidth: 2)
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(OnboardingTheme.onGreen)
                .scaleEffect(isSelected ? 1 : 0.4)
                .opacity(isSelected ? 1 : 0)
        }
        .frame(width: 24, height: 24)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func goalIcon(_ goal: TrainingGoal) -> some View {
        switch goal {
        case .strength:
            StrengthDumbbellGlyph(size: 22, color: OnboardingProfileScreen.tint(of: goal), strokeWidth: 2)
        case .active:
            OnboardingSymbol(name: "heart", size: 20)
        case .recover:
            OnboardingSymbol(name: "moon", size: 20)
        case .performance:
            OnboardingSymbol(name: "flame", size: 20)
        }
    }

    private static func tint(of goal: TrainingGoal) -> Color {
        switch goal {
        case .strength: return OnboardingTheme.green
        case .active: return OnboardingTheme.heart
        case .recover: return OnboardingTheme.blueText
        case .performance: return OnboardingTheme.recoveryFair
        }
    }

    // MARK: Experience

    private var levels: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(copy.text(.profileLevel))
                .pulseFont(13, .semibold, relativeTo: .footnote)
                .foregroundStyle(OnboardingTheme.inkSecondary)
                .padding(.horizontal, 4)
                .accessibilityHidden(true)
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: 2) {
                        levelButtons
                    }
                } else {
                    HStack(spacing: 2) {
                        levelButtons
                    }
                }
            }
            .padding(2)
            .background(OnboardingTheme.chipFill, in: RoundedRectangle(cornerRadius: PulseTheme.listRadius, style: .continuous))
            .accessibilityElement(children: .contain)
            .accessibilityLabel(copy.text(.profileLevel))
        }
    }

    private var levelButtons: some View {
        ForEach(ExperienceLevel.allCases, id: \.self) { (level: ExperienceLevel) in
            levelButton(level)
        }
    }

    private func levelButton(_ level: ExperienceLevel) -> some View {
        let isSelected = model.answers.level == level
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return Button {
            if !isSelected {
                UISelectionFeedbackGenerator().selectionChanged()
            }
            model.selectLevel(level)
        } label: {
            Text(copy.text(OnboardingSummary.levelText(level)))
                .pulseFont(14, .semibold, relativeTo: .subheadline)
                .foregroundStyle(isSelected ? Color.white : OnboardingTheme.onMediaSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity, minHeight: 42)
                .background(isSelected ? OnboardingTheme.selectedSegment : Color.clear, in: shape)
                .overlay(
                    shape.strokeBorder(isSelected ? OnboardingTheme.nextRowRing : Color.clear, lineWidth: 1.5)
                )
                .contentShape(shape)
        }
        .buttonStyle(PulsePlainButtonStyle())
        .animation(Animation.easeOut(duration: 0.25), value: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("onboarding.level." + level.rawValue)
    }
}

// MARK: - 2 · Apple Health

/// "Connect Apple Health": what the app reads and writes, and that the readings stay on the iPhone.
@MainActor
struct OnboardingHealthScreen: View {
    @ObservedObject var model: OnboardingModel
    let isActive: Bool

    private var copy: OnboardingCopy { model.copy }

    var body: some View {
        OnboardingSetupLayout(
            title: copy.text(.healthTitle),
            subtitle: copy.text(.healthSub),
            isActive: isActive,
            content: {
                OnboardingRowGroup {
                    OnboardingRow(
                        tint: OnboardingTheme.heart,
                        title: copy.text(.healthHeartRate),
                        subtitle: copy.text(.healthHeartRateSub),
                        tag: copy.text(.healthRead)
                    ) {
                        OnboardingSymbol(name: "heart.fill")
                    }
                    OnboardingRowDivider()
                    OnboardingRow(
                        tint: OnboardingTheme.green,
                        title: copy.text(.healthWorkouts),
                        subtitle: copy.text(.healthWorkoutsSub),
                        tag: copy.text(.healthWrite),
                        tagIsWrite: true
                    ) {
                        StrengthDumbbellGlyph(size: 20, color: OnboardingTheme.green, strokeWidth: 2)
                    }
                    OnboardingRowDivider()
                    OnboardingRow(
                        tint: OnboardingTheme.blueText,
                        title: copy.text(.healthBody),
                        subtitle: copy.text(.healthBodySub),
                        tag: copy.text(.healthRead)
                    ) {
                        OnboardingSymbol(name: "moon")
                    }
                }
            },
            foot: {
                VStack(spacing: 4) {
                    OnboardingNote {
                        Text(OnboardingRichText.attributed(copy.healthNote, copy: copy))
                            .tint(Color.white)
                    }
                    .padding(.bottom, 10)

                    Button {
                        Task {
                            await model.connectHealth()
                        }
                    } label: {
                        OnboardingActionLabel(title: copy.text(.healthConnect), symbol: "heart.fill", isBusy: model.busy == .health)
                    }
                    .buttonStyle(OnboardingPrimaryButtonStyle())
                    .disabled(model.isBusy)
                    .accessibilityIdentifier("onboarding.health.connect")

                    Button {
                        model.skipHealth()
                    } label: {
                        Text(copy.text(.healthLater))
                    }
                    .buttonStyle(OnboardingTextButtonStyle())
                    .disabled(model.isBusy)
                    .accessibilityIdentifier("onboarding.health.later")
                }
            }
        )
    }
}

// MARK: - 3 · AI Coaching

/// "Add AI Coaching?": what the coach would receive, what never leaves the phone, and the explicit consent. The two answers are
/// equally big on purpose: declining must be as easy as accepting.
@MainActor
struct OnboardingCoachScreen: View {
    @ObservedObject var model: OnboardingModel
    let isActive: Bool

    private var copy: OnboardingCopy { model.copy }

    var body: some View {
        OnboardingSetupLayout(
            title: copy.text(.coachTitle),
            subtitle: copy.text(.coachSub),
            isActive: isActive,
            content: {
                VStack(alignment: .leading, spacing: 0) {
                    Text(copy.text(.coachShared))
                        .pulseFont(13, .semibold, relativeTo: .footnote)
                        .foregroundStyle(OnboardingTheme.inkSecondary)
                        .padding(.horizontal, 4)
                        .padding(.bottom, 8)
                        .accessibilityAddTraits(.isHeader)
                    OnboardingRowGroup {
                        OnboardingRow(
                            tint: OnboardingTheme.green,
                            title: copy.text(.coachRow1),
                            subtitle: copy.text(.coachRow1Sub)
                        ) {
                            OnboardingSymbol(name: "person")
                        }
                        OnboardingRowDivider()
                        OnboardingRow(
                            tint: OnboardingTheme.heart,
                            title: copy.text(.coachRow2),
                            subtitle: copy.text(.coachRow2Sub)
                        ) {
                            OnboardingSymbol(name: "heart")
                        }
                        OnboardingRowDivider()
                        OnboardingRow(
                            tint: OnboardingTheme.blueText,
                            title: copy.text(.coachRow3),
                            subtitle: copy.text(.coachRow3Sub)
                        ) {
                            OnboardingSymbol(name: "bubble.left")
                        }
                    }
                    OnboardingNote {
                        Text(copy.text(.coachNever))
                    }
                    .padding(.top, 16)
                }
            },
            foot: {
                VStack(spacing: 8) {
                    Text(OnboardingRichText.attributed(copy.coachConsent, copy: copy))
                        .pulseFont(12, .regular, relativeTo: .caption)
                        .foregroundStyle(OnboardingTheme.onMediaTertiary)
                        .tint(Color.white)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 2)
                        .padding(.bottom, 2)

                    Button {
                        model.answerCoach(true)
                    } label: {
                        Text(copy.text(.coachOn))
                    }
                    .buttonStyle(OnboardingPrimaryButtonStyle())
                    .disabled(model.isBusy)
                    .accessibilityIdentifier("onboarding.coach.on")

                    Button {
                        model.answerCoach(false)
                    } label: {
                        Text(copy.text(.coachOff))
                    }
                    .buttonStyle(OnboardingGlassButtonStyle())
                    .disabled(model.isBusy)
                    .accessibilityIdentifier("onboarding.coach.off")
                }
            }
        )
    }
}

// MARK: - 4 · Notifications

/// "Never miss your next set": an example of the rest-over alert and what it does.
@MainActor
struct OnboardingNotifyScreen: View {
    @ObservedObject var model: OnboardingModel
    let isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var cardIn = true

    private var copy: OnboardingCopy { model.copy }

    var body: some View {
        OnboardingSetupLayout(
            title: copy.text(.notifyTitle),
            subtitle: copy.text(.notifySub),
            isActive: isActive,
            content: {
                VStack(alignment: .leading, spacing: 0) {
                    exampleNotification
                    VStack(alignment: .leading, spacing: 14) {
                        point(copy.text(.notifyPoint1))
                        point(copy.text(.notifyPoint2))
                    }
                    .padding(.horizontal, 4)
                    .padding(.top, 24)
                }
            },
            foot: {
                VStack(spacing: 4) {
                    Button {
                        Task {
                            await model.enableNotifications()
                        }
                    } label: {
                        OnboardingActionLabel(title: copy.text(.notifyOn), symbol: "bell", isBusy: model.busy == .notifications)
                    }
                    .buttonStyle(OnboardingPrimaryButtonStyle())
                    .disabled(model.isBusy)
                    .accessibilityIdentifier("onboarding.notify.on")

                    Button {
                        model.skipNotifications()
                    } label: {
                        Text(copy.text(.notifyLater))
                    }
                    .buttonStyle(OnboardingTextButtonStyle())
                    .disabled(model.isBusy)
                    .accessibilityIdentifier("onboarding.notify.later")
                }
            }
        )
        .task(id: isActive) {
            guard isActive, !reduceMotion else {
                cardIn = true
                return
            }
            cardIn = false
            try? await Task.sleep(nanoseconds: 60_000_000)
            withAnimation(Animation.spring(response: 0.6, dampingFraction: 0.72).delay(0.3)) {
                cardIn = true
            }
        }
    }

    /// The alert as it would look on the lock screen. It is a picture; the points below say the same in words.
    private var exampleNotification: some View {
        HStack(alignment: .top, spacing: 12) {
            OnboardingMarkTile(size: 40)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(copy.text(.notifyApp))
                        .pulseFont(15, .semibold, relativeTo: .subheadline)
                        .foregroundStyle(Color.white)
                    Spacer(minLength: 8)
                    Text(copy.text(.notifyTime))
                        .pulseFont(13, .regular, relativeTo: .footnote)
                        .foregroundStyle(OnboardingTheme.inkSecondary)
                }
                Text(OnboardingRichText.attributed(copy.notifyBody, copy: copy))
                    .pulseFont(15, .regular, relativeTo: .subheadline)
                    .foregroundStyle(Color.white.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onboardingGlass(radius: 22)
        .scaleEffect(cardIn ? 1 : 0.96)
        .offset(y: cardIn ? 0 : -26)
        .opacity(cardIn ? 1 : 0)
        .accessibilityHidden(true)
    }

    private func point(_ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(OnboardingTheme.green)
                .frame(width: 22, height: 22)
                .background(OnboardingTheme.greenTint, in: Circle())
                .accessibilityHidden(true)
            Text(text)
                .pulseFont(15, .regular, relativeTo: .subheadline)
                .foregroundStyle(OnboardingTheme.onMediaSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
#endif
