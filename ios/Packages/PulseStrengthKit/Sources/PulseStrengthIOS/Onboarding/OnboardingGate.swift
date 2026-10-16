#if os(iOS)
import SwiftUI
import PulseStrengthCore

/// The services of the onboarding inside the app: the two permission prompts go to the strength feature's services (the Health sheet
/// and the notification prompt appear at their own step, not at launch), the account calls go to a stand-in that accepts every
/// email and password after a short pause until an identity provider (Clerk, see the privacy policy) is connected.
///
/// Connecting the real provider means conforming to `OnboardingServices` for the four account calls and keeping the two permission
/// calls from here; nothing in the screens changes.
@MainActor
public final class PulseOnboardingServices: OnboardingServices {
    private let system: PulseServices?
    private let account: SimulatedOnboardingServices

    /// `system` is nil in previews and UI tests: nothing is asked of the system, both permissions are answered "yes" after the pause.
    public init(system: PulseServices?, simulatedLatency: TimeInterval = 0.8) {
        self.system = system
        self.account = SimulatedOnboardingServices(latency: simulatedLatency)
    }

    public func authenticate(mode: AuthMode, email: String, password: String) async throws {
        try await account.authenticate(mode: mode, email: email, password: password)
    }

    public func authenticateWithApple(mode: AuthMode) async throws {
        try await account.authenticateWithApple(mode: mode)
    }

    public func sendPasswordReset(to email: String) async throws {
        try await account.sendPasswordReset(to: email)
    }

    public func requestHealthAccess() async -> Bool {
        guard let system = system else {
            return await account.requestHealthAccess()
        }
        return await system.requestHealthPermission()
    }

    public func requestNotificationAccess() async -> Bool {
        guard let system = system else {
            return await account.requestNotificationAccess()
        }
        return await system.requestNotificationPermission()
    }
}

/// Shows the onboarding on the first launch and the app afterwards.
///
/// The record that the flow leaves behind (when it ended, what the user answered) is kept in `store`; as long as there is none, the
/// flow runs. `content` receives the record (nil when the onboarding was bypassed), so the app can tell whether the setup steps
/// already asked for the Health and notification permissions.
@MainActor
public struct OnboardingGate<Content: View>: View {
    private let services: OnboardingServices
    private let store: OnboardingRecordStore
    private let content: (OnboardingRecord?) -> Content

    @State private var record: OnboardingRecord?
    @State private var isOnboarding: Bool

    /// `showsAlways` runs the flow even when a record exists (UI tests, a "show the welcome again" switch).
    public init(
        services: OnboardingServices,
        store: OnboardingRecordStore = OnboardingRecordStore(),
        showsAlways: Bool = false,
        @ViewBuilder content: @escaping (OnboardingRecord?) -> Content
    ) {
        let saved = store.load()
        self.services = services
        self.store = store
        self.content = content
        self._record = State(initialValue: saved)
        self._isOnboarding = State(initialValue: showsAlways || saved == nil)
    }

    public var body: some View {
        ZStack {
            if isOnboarding {
                OnboardingFlowView(services: services) { (outcome: OnboardingOutcome) in
                    finish(with: outcome)
                }
                .transition(.opacity)
            } else {
                content(record)
                    .transition(.opacity)
            }
        }
        .animation(Animation.easeInOut(duration: 0.45), value: isOnboarding)
    }

    private func finish(with outcome: OnboardingOutcome) {
        let completed = OnboardingRecord(completedAt: Date(), outcome: outcome)
        store.save(completed)
        record = completed
        isOnboarding = false
    }
}
#endif
