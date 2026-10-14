import XCTest
@testable import PulseStrengthCore
final class SmokeTests: XCTestCase { func testModelsCompile() { XCTAssertEqual(SetType.warmup.badge, "W") } }
