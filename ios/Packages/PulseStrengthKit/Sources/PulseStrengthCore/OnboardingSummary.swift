import Foundation

/// One chip on the last screen: what the user chose, and whether it is switched on.
public struct OnboardingSummaryItem: Equatable, Hashable, Sendable {
    public let text: String
    /// False for "later" and "off" answers, which are shown muted.
    public let isOn: Bool

    public init(text: String, isOn: Bool) {
        self.text = text
        self.isOn = isOn
    }
}

public enum OnboardingSummary {
    /// The chips of the last screen: goal, experience, Apple Health, AI Coaching, notifications (an unanswered question counts as "later" / "off").
    public static func items(for answers: OnboardingAnswers, copy: OnboardingCopy) -> [OnboardingSummaryItem] {
        var items: [OnboardingSummaryItem] = []
        if let goal = answers.goal {
            items.append(OnboardingSummaryItem(text: copy.text(goalText(goal)), isOn: true))
        }
        if let level = answers.level {
            items.append(OnboardingSummaryItem(text: copy.text(levelText(level)), isOn: true))
        }
        let health = answers.healthConnected ?? false
        items.append(OnboardingSummaryItem(text: copy.text(health ? .doneHealthOn : .doneHealthOff), isOn: health))
        let coach = answers.aiCoachingEnabled ?? false
        items.append(OnboardingSummaryItem(text: copy.text(coach ? .doneCoachOn : .doneCoachOff), isOn: coach))
        let notify = answers.notificationsEnabled ?? false
        items.append(OnboardingSummaryItem(text: copy.text(notify ? .doneNotifyOn : .doneNotifyOff), isOn: notify))
        return items
    }

    public static func goalText(_ goal: TrainingGoal) -> OnboardingText {
        switch goal {
        case .strength: return .goalStrength
        case .active: return .goalActive
        case .recover: return .goalRecover
        case .performance: return .goalPerformance
        }
    }

    public static func goalSubtitleText(_ goal: TrainingGoal) -> OnboardingText {
        switch goal {
        case .strength: return .goalStrengthSub
        case .active: return .goalActiveSub
        case .recover: return .goalRecoverSub
        case .performance: return .goalPerformanceSub
        }
    }

    public static func levelText(_ level: ExperienceLevel) -> OnboardingText {
        switch level {
        case .beginner: return .levelBeginner
        case .intermediate: return .levelIntermediate
        case .advanced: return .levelAdvanced
        }
    }
}
