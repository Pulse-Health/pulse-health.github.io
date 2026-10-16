import Foundation

/// Whether the host app shows the onboarding at launch, decided from the launch arguments so that the UI tests of the other
/// screens can start at the hub while one test walks the onboarding.
public enum OnboardingLaunchMode: Equatable, Hashable, Sendable {
    /// The usual launch: the flow runs until it has been completed once.
    case firstLaunch
    /// The flow is not shown (UI tests of the other screens, `-PulseSkipOnboarding` in an Xcode scheme).
    case skip
    /// The flow is shown at every launch (the UI test of the onboarding, `-PulseShowOnboarding` in an Xcode scheme).
    case always

    /// Set by the UI tests: a fresh temporary store and no live services. Implies `skip` unless `showArgument` is also given.
    public static let uiTestArgument = "-PulseUITest"
    public static let skipArgument = "-PulseSkipOnboarding"
    public static let showArgument = "-PulseShowOnboarding"

    public static func resolve(arguments: [String]) -> OnboardingLaunchMode {
        if arguments.contains(showArgument) { return .always }
        if arguments.contains(skipArgument) || arguments.contains(uiTestArgument) { return .skip }
        return .firstLaunch
    }
}
