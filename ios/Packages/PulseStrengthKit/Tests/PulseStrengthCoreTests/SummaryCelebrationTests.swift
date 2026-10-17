import XCTest
@testable import PulseStrengthCore

/// The finish celebration of the workout summary (SummaryCelebration.swift): its timeline, the count-up of the figures and the
/// confetti paths.
final class SummaryCelebrationTests: XCTestCase {
    // MARK: Timeline

    func testTheBeatsFollowEachOther() {
        XCTAssertLessThan(SummaryCelebration.medalStart, SummaryCelebration.ringStart)
        XCTAssertLessThan(SummaryCelebration.ringStart, SummaryCelebration.checkStart)
        XCTAssertEqual(
            SummaryCelebration.checkStart + SummaryCelebration.checkDuration,
            SummaryCelebration.impact,
            accuracy: 0.05,
            "the check lands on the impact"
        )
        XCTAssertGreaterThan(SummaryCelebration.titleStart, SummaryCelebration.impact)
        XCTAssertGreaterThan(SummaryCelebration.figureStart, SummaryCelebration.titleStart)
        XCTAssertGreaterThan(SummaryCelebration.cueStart, SummaryCelebration.figureStart)
    }

    func testSettlesWithinSevenSeconds() {
        XCTAssertGreaterThanOrEqual(SummaryCelebration.settleTime, SummaryCelebration.cueStart + SummaryCelebration.cueDuration)
        XCTAssertGreaterThanOrEqual(SummaryCelebration.settleTime, ConfettiPiece.latestEnd)
        XCTAssertLessThan(SummaryCelebration.settleTime, 7)
    }

    // MARK: Easing

    func testEasingsStartAtZeroAndEndAtOne() {
        let easings: [(Double) -> Double] = [
            SummaryCelebration.easeOut,
            SummaryCelebration.easeIn,
            SummaryCelebration.easeInOut,
            SummaryCelebration.easeOutBack,
        ]
        for easing in easings {
            XCTAssertEqual(easing(0), 0, accuracy: 1e-9)
            XCTAssertEqual(easing(1), 1, accuracy: 1e-9)
            XCTAssertEqual(easing(-3), 0, accuracy: 1e-9, "clamped below")
            XCTAssertEqual(easing(7), 1, accuracy: 1e-9, "clamped above")
        }
    }

    func testEaseOutBackOvershootsOnTheWay() {
        let samples = stride(from: 0.0, through: 1.0, by: 0.05).map { SummaryCelebration.easeOutBack($0) }
        XCTAssertGreaterThan(samples.max() ?? 0, 1.05)
        XCTAssertLessThan(samples.max() ?? 0, 1.2)
    }

    func testProgressIsClampedAndHandlesAZeroDuration() {
        XCTAssertEqual(SummaryCelebration.progress(0.5, start: 1, duration: 2), 0, accuracy: 1e-9)
        XCTAssertEqual(SummaryCelebration.progress(2, start: 1, duration: 2), 0.5, accuracy: 1e-9)
        XCTAssertEqual(SummaryCelebration.progress(9, start: 1, duration: 2), 1, accuracy: 1e-9)
        XCTAssertEqual(SummaryCelebration.progress(0.5, start: 1, duration: 0), 0)
        XCTAssertEqual(SummaryCelebration.progress(1.5, start: 1, duration: 0), 1)
        XCTAssertEqual(SummaryCelebration.clamp01(.nan), 0)
        XCTAssertEqual(SummaryCelebration.clamp01(.infinity), 1)
    }

    // MARK: The medal

    func testTheMedalSpringsInThroughAnOvershootAndComesToRest() {
        let before = SummaryCelebration.medalPose(at: 0)
        XCTAssertEqual(before.scale, 0, accuracy: 1e-9)
        XCTAssertEqual(before.opacity, 0, accuracy: 1e-9)

        let end = SummaryCelebration.medalStart + SummaryCelebration.medalDuration
        let after = SummaryCelebration.medalPose(at: end + 0.01)
        XCTAssertEqual(after.scale, 1, accuracy: 1e-9)
        XCTAssertEqual(after.rotation, 0, accuracy: 1e-9)
        XCTAssertEqual(after.opacity, 1, accuracy: 1e-9)

        let scales = stride(from: 0.0, through: end, by: 0.01).map { SummaryCelebration.medalPose(at: $0).scale }
        XCTAssertGreaterThan(scales.max() ?? 0, 1.1, "it goes past full size")
        XCTAssertLessThan(scales.max() ?? 0, 1.2)
    }

    func testTheRingAndTheCheckDrawInOrderAndNeverBackwards() {
        var ring = 0.0
        var check = 0.0
        var time = 0.0
        while time <= 3 {
            let nextRing = SummaryCelebration.ringProgress(at: time)
            let nextCheck = SummaryCelebration.checkProgress(at: time)
            XCTAssertGreaterThanOrEqual(nextRing, ring)
            XCTAssertGreaterThanOrEqual(nextCheck, check)
            XCTAssertTrue((0...1).contains(nextRing))
            XCTAssertTrue((0...1).contains(nextCheck))
            ring = nextRing
            check = nextCheck
            time += 0.02
        }
        XCTAssertEqual(SummaryCelebration.ringProgress(at: 0.4), 0, accuracy: 1e-9)
        XCTAssertEqual(SummaryCelebration.checkProgress(at: 0.9), 0, accuracy: 1e-9)
        XCTAssertGreaterThan(SummaryCelebration.ringProgress(at: SummaryCelebration.checkStart), 0.5, "the ring is mostly round when the check starts")
        XCTAssertEqual(SummaryCelebration.ringProgress(at: 3), 1, accuracy: 1e-9)
        XCTAssertEqual(SummaryCelebration.checkProgress(at: 3), 1, accuracy: 1e-9)
    }

    func testTheImpactEffectsAreInvisibleBeforeAndAfterTheirWindow() {
        XCTAssertEqual(SummaryCelebration.ripple(at: SummaryCelebration.impact - 0.1, index: 0).opacity, 0)
        XCTAssertEqual(SummaryCelebration.ripple(at: SummaryCelebration.impact + 3, index: 0).opacity, 0)
        XCTAssertGreaterThan(SummaryCelebration.ripple(at: SummaryCelebration.impact + 0.3, index: 0).opacity, 0.2)
        XCTAssertEqual(SummaryCelebration.ripple(at: SummaryCelebration.impact + 0.1, index: 1).opacity, 0, "the second ripple follows later")
        XCTAssertGreaterThan(SummaryCelebration.ripple(at: SummaryCelebration.impact + 1, index: 1).scale, 1)

        XCTAssertEqual(SummaryCelebration.sparks(at: SummaryCelebration.impact - 0.1).opacity, 0)
        XCTAssertEqual(SummaryCelebration.sparks(at: SummaryCelebration.impact + 2).opacity, 0)
        XCTAssertEqual(SummaryCelebration.sparks(at: SummaryCelebration.impact + 0.225).opacity, 1, accuracy: 1e-9, "peak at a quarter")

        XCTAssertEqual(SummaryCelebration.glow(at: SummaryCelebration.impact - 0.1).opacity, 0)
        XCTAssertEqual(SummaryCelebration.glow(at: SummaryCelebration.impact + 5).opacity, 0.3, accuracy: 1e-9, "it stays as a glow")

        XCTAssertEqual(SummaryCelebration.thumbScale(at: 0), 1, accuracy: 1e-9)
        XCTAssertEqual(SummaryCelebration.thumbScale(at: SummaryCelebration.impact + 5), 1, accuracy: 1e-9)
        XCTAssertGreaterThan(SummaryCelebration.thumbScale(at: SummaryCelebration.impact + 0.21), 1.05)
    }

    func testTheRaysTurnUntilThingsSettleAndThenStop() {
        XCTAssertEqual(SummaryCelebration.rays(at: 0).opacity, 0, accuracy: 1e-9)
        XCTAssertEqual(SummaryCelebration.rays(at: 0).rotation, 0, accuracy: 1e-9)
        let later = SummaryCelebration.rays(at: SummaryCelebration.settleTime + 10)
        let atSettle = SummaryCelebration.rays(at: SummaryCelebration.settleTime)
        XCTAssertEqual(later.opacity, 1, accuracy: 1e-9)
        XCTAssertEqual(later.rotation, atSettle.rotation, accuracy: 1e-9, "no jump when the timeline stops")
        XCTAssertGreaterThan(later.rotation, 0)
    }

    func testAStarBlinksOnceInsideItsWindow() {
        XCTAssertEqual(SummaryCelebration.twinkle(at: 1.0, delay: 1.5).opacity, 0)
        XCTAssertEqual(SummaryCelebration.twinkle(at: 3.0, delay: 1.5).opacity, 0)
        let open = SummaryCelebration.twinkle(at: 1.5 + 1.3 * 0.4, delay: 1.5)
        XCTAssertEqual(open.scale, 1, accuracy: 1e-9)
        XCTAssertEqual(open.opacity, 1, accuracy: 1e-9)
    }

    // MARK: Text, count and scrolling

    func testALineRisesFromNothingToRestWithASpring() {
        XCTAssertEqual(SummaryCelebration.rise(at: 0, start: 1), 0, accuracy: 1e-9)
        XCTAssertEqual(SummaryCelebration.rise(at: 5, start: 1), 1, accuracy: 1e-9)
        XCTAssertEqual(SummaryCelebration.fade(at: 0, start: 1), 0, accuracy: 1e-9)
        XCTAssertEqual(SummaryCelebration.fade(at: 5, start: 1), 1, accuracy: 1e-9)
        let fades = stride(from: 0.0, through: 3.0, by: 0.05).map { SummaryCelebration.fade(at: $0, start: 1) }
        XCTAssertLessThanOrEqual(fades.max() ?? 0, 1, "a fade never overshoots")
    }

    func testTheCountRunsFromZeroToOneInsideItsWindow() {
        XCTAssertEqual(SummaryCelebration.countProgress(at: 0), 0, accuracy: 1e-9)
        XCTAssertEqual(SummaryCelebration.countProgress(at: SummaryCelebration.countStart), 0, accuracy: 1e-9)
        XCTAssertEqual(
            SummaryCelebration.countProgress(at: SummaryCelebration.countStart + SummaryCelebration.countDuration),
            1,
            accuracy: 1e-9
        )
        XCTAssertGreaterThan(
            SummaryCelebration.countProgress(at: SummaryCelebration.countStart + SummaryCelebration.countDuration / 2),
            0.5,
            "it is fast at first and slows into the final value"
        )
        var previous = 0.0
        var time = 0.0
        while time < 5 {
            let value = SummaryCelebration.countProgress(at: time)
            XCTAssertGreaterThanOrEqual(value, previous)
            previous = value
            time += 0.05
        }
    }

    func testTheSheetProgressFollowsTheSheetTop() {
        XCTAssertEqual(SummaryCelebration.scrollProgress(sheetTop: 700, heroHeight: 700), 0, accuracy: 1e-9)
        XCTAssertEqual(SummaryCelebration.scrollProgress(sheetTop: 350, heroHeight: 700), 0.5, accuracy: 1e-9)
        XCTAssertEqual(SummaryCelebration.scrollProgress(sheetTop: 0, heroHeight: 700), 1, accuracy: 1e-9)
        XCTAssertEqual(SummaryCelebration.scrollProgress(sheetTop: -80, heroHeight: 700), 1, accuracy: 1e-9)
        XCTAssertEqual(SummaryCelebration.scrollProgress(sheetTop: 900, heroHeight: 700), 0, accuracy: 1e-9, "pulled down past the top")
        XCTAssertEqual(SummaryCelebration.scrollProgress(sheetTop: 100, heroHeight: 0), 0, "nothing measured yet")
        XCTAssertEqual(SummaryCelebration.scrollProgress(sheetTop: .nan, heroHeight: 700), 0)
    }

    func testTheGreenGivesWayAndTheBarSolidifiesAsTheSheetComesUp() {
        XCTAssertEqual(SummaryCelebration.backdropOpacity(scrollProgress: 0), 1, accuracy: 1e-9)
        XCTAssertEqual(SummaryCelebration.backdropOpacity(scrollProgress: 0.6), 1, accuracy: 1e-9)
        XCTAssertEqual(SummaryCelebration.backdropOpacity(scrollProgress: 1), 0, accuracy: 1e-9)
        XCTAssertEqual(SummaryCelebration.barProgress(scrollProgress: 0), 0, accuracy: 1e-9)
        XCTAssertEqual(SummaryCelebration.barProgress(scrollProgress: 0.6), 1, accuracy: 1e-9)
        XCTAssertEqual(SummaryCelebration.barProgress(scrollProgress: 1), 1, accuracy: 1e-9)
        XCTAssertEqual(SummaryCelebration.heroVisibility(scrollProgress: 0), 1, accuracy: 1e-9)
        XCTAssertEqual(SummaryCelebration.heroVisibility(scrollProgress: 1), 0, accuracy: 1e-9)
    }

    // MARK: Figures

    func testFiguresStartAtZeroAndEndOnTheRealValues() {
        let figures = SummaryFigures(durationSeconds: 4_500, volumeKg: 5_064, sets: 19)
        XCTAssertEqual(figures.duration(at: 0), SummaryFigures.Figure(value: "0:00", unit: "h"))
        XCTAssertEqual(figures.duration(at: 1), SummaryFigures.Figure(value: "1:15", unit: "h"))
        XCTAssertEqual(figures.volume(at: 0), SummaryFigures.Figure(value: "0", unit: "kg"))
        XCTAssertEqual(figures.volume(at: 1), SummaryFigures.Figure(value: "5,064", unit: "kg"))
        XCTAssertEqual(figures.setCount(at: 0), SummaryFigures.Figure(value: "0", unit: ""))
        XCTAssertEqual(figures.setCount(at: 1), SummaryFigures.Figure(value: "19", unit: ""))
        XCTAssertEqual(figures.counted.duration.value, "1:15")
        XCTAssertEqual(figures.counted.volume.value, "5,064")
        XCTAssertEqual(figures.counted.sets.value, "19")
    }

    func testTheDurationUnitDoesNotChangeWhileCounting() {
        let long = SummaryFigures(durationSeconds: 3_723, volumeKg: 0, sets: 0)
        let medium = SummaryFigures(durationSeconds: 3_120, volumeKg: 0, sets: 0)
        let short = SummaryFigures(durationSeconds: 45, volumeKg: 0, sets: 0)
        for step in 0...20 {
            let p = Double(step) / 20
            XCTAssertEqual(long.duration(at: p).unit, "h")
            XCTAssertEqual(medium.duration(at: p).unit, "min")
            XCTAssertEqual(short.duration(at: p).unit, "s")
        }
        XCTAssertEqual(long.duration(at: 1).value, "1:02", "the minutes are floored like the summary tile")
        XCTAssertEqual(medium.duration(at: 1).value, "52")
        XCTAssertEqual(medium.duration(at: 0.5).value, "26")
        XCTAssertEqual(short.duration(at: 1).value, "45")
    }

    func testTheHourClockPadsTheMinutes() {
        let figures = SummaryFigures(durationSeconds: 3_600 + 5 * 60, volumeKg: 0, sets: 0)
        XCTAssertEqual(figures.duration(at: 1).value, "1:05")
        XCTAssertEqual(figures.duration(at: 0).value, "0:00")
    }

    func testFiguresCountUpWithoutGoingBackwardsOrPastTheEnd() {
        let figures = SummaryFigures(durationSeconds: 4_500, volumeKg: 5_064, sets: 19)
        var volume = -1
        var sets = -1
        for step in 0...100 {
            let p = Double(step) / 100
            let nextVolume = Int(figures.volume(at: p).value.replacingOccurrences(of: ",", with: "")) ?? -2
            let nextSets = Int(figures.setCount(at: p).value) ?? -2
            XCTAssertGreaterThanOrEqual(nextVolume, volume)
            XCTAssertGreaterThanOrEqual(nextSets, sets)
            XCTAssertLessThanOrEqual(nextVolume, 5_064)
            XCTAssertLessThanOrEqual(nextSets, 19)
            volume = nextVolume
            sets = nextSets
        }
        XCTAssertEqual(figures.volume(at: 7).value, "5,064", "progress is clamped")
        XCTAssertEqual(figures.volume(at: -1).value, "0")
    }

    func testBadInputGivesZeroFigures() {
        let figures = SummaryFigures(durationSeconds: -5, volumeKg: .nan, sets: -2)
        XCTAssertEqual(figures.durationSeconds, 0)
        XCTAssertEqual(figures.volumeKg, 0)
        XCTAssertEqual(figures.sets, 0)
        XCTAssertEqual(figures.counted.duration, SummaryFigures.Figure(value: "0", unit: "s"))
        XCTAssertEqual(figures.counted.volume, SummaryFigures.Figure(value: "0", unit: "kg"))
    }

    // MARK: Confetti

    func testTheStandardSetHasABurstAndTwoCannons() {
        let pieces = ConfettiPiece.standardSet
        XCTAssertEqual(pieces.count, ConfettiPiece.burstCount + 2 * ConfettiPiece.cannonCount)
        XCTAssertEqual(pieces.filter { $0.launcher == .burst }.count, ConfettiPiece.burstCount)
        XCTAssertEqual(pieces.filter { $0.launcher == .cannonLeading }.count, ConfettiPiece.cannonCount)
        XCTAssertEqual(pieces.filter { $0.launcher == .cannonTrailing }.count, ConfettiPiece.cannonCount)
        XCTAssertEqual(Set(pieces.map { $0.id }).count, pieces.count, "ids are unique")
        XCTAssertEqual(pieces.map { $0.id }, Array(0..<pieces.count))
    }

    func testTheSetIsTheSameEveryTimeAndDiffersWithTheSeed() {
        XCTAssertEqual(ConfettiPiece.makeSet(), ConfettiPiece.makeSet())
        XCTAssertEqual(ConfettiPiece.makeSet(), ConfettiPiece.standardSet)
        XCTAssertNotEqual(ConfettiPiece.makeSet(seed: 1), ConfettiPiece.makeSet(seed: 2))
    }

    func testPiecesAreLaunchedInTheirOwnMoments() {
        for piece in ConfettiPiece.standardSet {
            XCTAssertGreaterThan(piece.duration, 2)
            XCTAssertLessThan(piece.duration, 3.5)
            switch piece.launcher {
            case .burst:
                XCTAssertGreaterThanOrEqual(piece.delay, SummaryCelebration.impact)
                XCTAssertLessThan(piece.delay, SummaryCelebration.impact + 0.11)
            case .cannonLeading, .cannonTrailing:
                XCTAssertGreaterThanOrEqual(piece.delay, SummaryCelebration.cannonStart)
                XCTAssertLessThan(piece.delay, SummaryCelebration.cannonStart + 0.3)
            }
        }
    }

    func testPiecesFlyTheRightWay() {
        for piece in ConfettiPiece.standardSet {
            switch piece.launcher {
            case .burst:
                XCTAssertGreaterThan(piece.dyFall, piece.dy, "it falls after its highest point")
            case .cannonLeading:
                XCTAssertGreaterThan(piece.dx, 0, "inwards from the left corner")
                XCTAssertLessThan(piece.dy, -300, "up")
            case .cannonTrailing:
                XCTAssertLessThan(piece.dx, 0, "inwards from the right corner")
                XCTAssertLessThan(piece.dy, -300, "up")
            }
            XCTAssertTrue(piece.colorIndex >= 0 && piece.colorIndex < ConfettiPiece.paletteCount)
            XCTAssertGreaterThan(piece.width, 0)
            XCTAssertGreaterThan(piece.height, 0)
        }
    }

    func testAPieceIsOnlyThereDuringItsFlight() {
        let piece = ConfettiPiece.standardSet[0]
        XCTAssertNil(piece.pose(at: piece.delay - 0.01))
        XCTAssertNil(piece.pose(at: piece.delay))
        XCTAssertNotNil(piece.pose(at: piece.delay + 0.01))
        XCTAssertNotNil(piece.pose(at: piece.end - 0.01))
        XCTAssertNil(piece.pose(at: piece.end + 0.001))
        XCTAssertNil(piece.pose(at: piece.end + 10))
    }

    func testAPieceIsAtItsHighestPointAtTheApex() {
        for piece in ConfettiPiece.standardSet {
            guard let pose = piece.pose(at: piece.delay + ConfettiPiece.apex * piece.duration) else {
                XCTFail("piece \(piece.id) has no pose at its apex")
                continue
            }
            XCTAssertEqual(pose.x, piece.dx, accuracy: 0.5)
            XCTAssertEqual(pose.y, piece.dy, accuracy: 0.5)
            XCTAssertEqual(pose.opacity, 1, accuracy: 1e-6)
            XCTAssertEqual(pose.scale, 1, accuracy: 1e-3)
        }
    }

    func testAPieceFallsFadesAndNeverMovesBackUpAfterTheApex() {
        let piece = ConfettiPiece.standardSet[0]
        var previousY = -Double.infinity
        var previousOpacity = 2.0
        var time = piece.delay + ConfettiPiece.apex * piece.duration
        while time < piece.end - 0.001 {
            guard let pose = piece.pose(at: time) else {
                XCTFail("no pose at \(time)")
                return
            }
            XCTAssertGreaterThanOrEqual(pose.y, previousY - 1e-9)
            XCTAssertLessThanOrEqual(pose.opacity, previousOpacity + 1e-9)
            previousY = pose.y
            previousOpacity = pose.opacity
            time += 0.02
        }
        let nearEnd = piece.pose(at: piece.end - 0.001)
        XCTAssertNotNil(nearEnd)
        XCTAssertLessThan(nearEnd?.opacity ?? 1, 0.01)
        XCTAssertEqual(nearEnd?.y ?? 0, piece.dyFall, accuracy: 1)
    }

    func testAPieceStartsSmallAtTheLaunchPoint() {
        let piece = ConfettiPiece.standardSet[3]
        guard let pose = piece.pose(at: piece.delay + 0.0001) else {
            XCTFail("no pose just after the launch")
            return
        }
        XCTAssertEqual(pose.x, 0, accuracy: 0.5)
        XCTAssertEqual(pose.y, 0, accuracy: 0.5)
        XCTAssertEqual(pose.scale, 0.3, accuracy: 0.01)
    }
}
