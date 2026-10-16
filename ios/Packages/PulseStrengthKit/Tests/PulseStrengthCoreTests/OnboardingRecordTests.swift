import XCTest
@testable import PulseStrengthCore

/// What the app remembers after the onboarding (OnboardingRecord.swift) and the simulated services (OnboardingServices.swift).
@MainActor
final class OnboardingRecordTests: XCTestCase {
    private func makeDefaults(_ name: String = #function) -> UserDefaults {
        let suite = "health.pulse.strength.tests." + name
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private let answers = OnboardingAnswers(
        goal: .performance, level: .advanced, healthConnected: true, aiCoachingEnabled: false, notificationsEnabled: true
    )

    // MARK: Record

    func testARecordFromAFinishedFlowIsANewAccountWithItsAnswers() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let record = OnboardingRecord(completedAt: date, outcome: .finished(answers))
        XCTAssertTrue(record.isNewAccount)
        XCTAssertEqual(record.answers, answers)
        XCTAssertEqual(record.completedAt, date)
        XCTAssertTrue(record.askedForPermissions)
    }

    func testARecordFromALogInHasNoAnswersAndAsksForNothing() {
        let record = OnboardingRecord(completedAt: Date(timeIntervalSince1970: 1_700_000_000), outcome: .signedIn)
        XCTAssertFalse(record.isNewAccount)
        XCTAssertEqual(record.answers, OnboardingAnswers())
        XCTAssertFalse(record.askedForPermissions, "the app still has to ask at launch")
    }

    // MARK: Store

    func testNothingIsSavedUntilTheFlowIsDone() {
        let store = OnboardingRecordStore(defaults: makeDefaults())
        XCTAssertNil(store.load())
    }

    func testTheRecordSurvivesASaveAndLoad() {
        let defaults = makeDefaults()
        let record = OnboardingRecord(completedAt: Date(timeIntervalSince1970: 1_700_000_000), outcome: .finished(answers))
        OnboardingRecordStore(defaults: defaults).save(record)
        XCTAssertEqual(OnboardingRecordStore(defaults: defaults).load(), record, "a new store on the same defaults, like the next launch")
    }

    func testClearingForgetsTheRecord() {
        let store = OnboardingRecordStore(defaults: makeDefaults())
        store.save(OnboardingRecord(completedAt: Date(timeIntervalSince1970: 1_700_000_000), outcome: .signedIn))
        XCTAssertNotNil(store.load())
        store.clear()
        XCTAssertNil(store.load())
    }

    func testUnreadableDataCountsAsNotCompleted() {
        let defaults = makeDefaults()
        defaults.set(Data("not json".utf8), forKey: OnboardingRecordStore.defaultKey)
        XCTAssertNil(OnboardingRecordStore(defaults: defaults).load())
    }

    func testTwoKeysDoNotMix() {
        let defaults = makeDefaults()
        let first = OnboardingRecordStore(defaults: defaults, key: "first")
        let second = OnboardingRecordStore(defaults: defaults, key: "second")
        first.save(OnboardingRecord(completedAt: Date(timeIntervalSince1970: 1_700_000_000), outcome: .signedIn))
        XCTAssertNotNil(first.load())
        XCTAssertNil(second.load())
    }

    // MARK: Launch mode

    func testTheOnboardingRunsAtTheFirstLaunchOfANormalStart() {
        XCTAssertEqual(OnboardingLaunchMode.resolve(arguments: ["/path/to/PulseStrength"]), .firstLaunch)
        XCTAssertEqual(OnboardingLaunchMode.resolve(arguments: []), .firstLaunch)
    }

    func testTheUITestsOfTheOtherScreensSkipIt() {
        XCTAssertEqual(OnboardingLaunchMode.resolve(arguments: ["app", "-PulseUITest", "-AppleLanguages", "(en)"]), .skip)
        XCTAssertEqual(OnboardingLaunchMode.resolve(arguments: ["app", "-PulseSkipOnboarding"]), .skip)
    }

    func testTheOnboardingTestAsksForItExplicitly() {
        XCTAssertEqual(OnboardingLaunchMode.resolve(arguments: ["app", "-PulseUITest", "-PulseShowOnboarding"]), .always)
        XCTAssertEqual(OnboardingLaunchMode.resolve(arguments: ["app", "-PulseShowOnboarding"]), .always)
        XCTAssertEqual(
            OnboardingLaunchMode.resolve(arguments: ["app", "-PulseSkipOnboarding", "-PulseShowOnboarding"]), .always,
            "asking to see it wins"
        )
    }

    // MARK: Simulated services

    func testSimulatedServicesAcceptEverythingByDefault() async throws {
        let services = SimulatedOnboardingServices(latency: 0)
        try await services.authenticate(mode: .signUp, email: "a@b.co", password: "12345678")
        try await services.authenticateWithApple(mode: .logIn)
        try await services.sendPasswordReset(to: "a@b.co")
        let health = await services.requestHealthAccess()
        let notifications = await services.requestNotificationAccess()
        XCTAssertTrue(health)
        XCTAssertTrue(notifications)
    }

    func testSimulatedServicesCanBeToldToFailOrToSayNo() async {
        let services = SimulatedOnboardingServices(latency: 0, failure: .invalidCredentials, healthAnswer: false, notificationAnswer: false)
        do {
            try await services.authenticate(mode: .logIn, email: "a@b.co", password: "x")
            XCTFail("expected a failure")
        } catch {
            XCTAssertEqual(error as? OnboardingAuthError, .invalidCredentials)
        }
        let health = await services.requestHealthAccess()
        let notifications = await services.requestNotificationAccess()
        XCTAssertFalse(health)
        XCTAssertFalse(notifications)
    }

    func testSimulatedServicesTakeTheirTime() async throws {
        let services = SimulatedOnboardingServices(latency: 0.05)
        let start = Date()
        try await services.authenticate(mode: .signUp, email: "a@b.co", password: "12345678")
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(start), 0.04)
    }
}
