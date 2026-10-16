import XCTest
@testable import PulseStrengthCore

final class StrengthDeepLinkTests: XCTestCase {
    func testEveryLinkRoundTrips() {
        let id = UUID()
        let links: [StrengthDeepLink] = [
            .workout, .startNext, .hub, .plates,
            .start(templateID: id), .startEmpty(name: "Mobility · Hips & T-spine"), .exercise(id: "bench"),
        ]
        for link in links {
            XCTAssertEqual(StrengthDeepLink(url: link.url), link, "\(link)")
        }
    }

    func testTheExistingWorkoutUrlStillParses() {
        XCTAssertEqual(StrengthDeepLink(url: StrengthConfig.workoutURL), .workout)
    }

    func testForeignSchemesAndGarbageAreRejected() {
        XCTAssertNil(StrengthDeepLink(url: URL(string: "https://example.com/workout")!))
        XCTAssertNil(StrengthDeepLink(url: URL(string: "pulse-strength://unknown")!))
        XCTAssertNil(StrengthDeepLink(url: URL(string: "pulse-strength://start?template=nope")!))
        XCTAssertNil(StrengthDeepLink(url: URL(string: "pulse-strength://exercise")!))
    }

    func testAnEmptyNameFallsBackToTheDefaultWorkoutName() {
        XCTAssertEqual(StrengthDeepLink(url: URL(string: "pulse-strength://start-empty?name=%20")!), .startEmpty(name: StrengthConfig.defaultWorkoutName))
    }
}
