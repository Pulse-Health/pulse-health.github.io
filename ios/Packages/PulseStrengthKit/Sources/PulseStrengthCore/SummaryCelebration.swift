import Foundation

/// The choreography of the finish celebration at the top of the workout summary: when each beat happens, how the figures count
/// up and where every piece of confetti flies. Everything here is a pure function of the seconds since the celebration began, so
/// the timing and the paths can be tested without a screen; the SwiftUI view only draws what these return.
///
/// The beats, in order: the medal springs in (0.15 s) while its ring draws (0.55 s) and its check follows (1.0 s); at the impact
/// (1.4 s) the medal thumps, ripples and sparks go out and the first confetti bursts from it; the title rises, then the three
/// figures, which count up while a second spray of confetti shoots in from both lower corners; last, the cue to scroll down
/// fades in.
public enum SummaryCelebration {
    // MARK: Timeline (seconds)

    /// The summary slides up as a full-screen cover; the beats start once it has mostly arrived.
    public static let appearDelay: TimeInterval = 0.3

    public static let medalStart: TimeInterval = 0.15
    public static let medalDuration: TimeInterval = 0.85
    public static let ringStart: TimeInterval = 0.55
    public static let ringDuration: TimeInterval = 0.85
    public static let checkStart: TimeInterval = 1.0
    public static let checkDuration: TimeInterval = 0.42
    /// The check has landed: thump, ripples, sparks, glow and the first confetti.
    public static let impact: TimeInterval = 1.4
    public static let titleStart: TimeInterval = 1.55
    public static let titleStagger: TimeInterval = 0.13
    public static let subtitleStart: TimeInterval = 1.9
    public static let panelStart: TimeInterval = 2.05
    public static let figureStart: TimeInterval = 2.1
    public static let figureStagger: TimeInterval = 0.1
    public static let countStart: TimeInterval = 2.15
    public static let countDuration: TimeInterval = 1.4
    /// The second spray of confetti, from the lower corners.
    public static let cannonStart: TimeInterval = 2.1
    public static let cueStart: TimeInterval = 2.9
    public static let cueDuration: TimeInterval = 0.7

    /// When the last confetti piece is gone and the cue is in: from here on nothing moves any more.
    public static var settleTime: TimeInterval {
        max(ConfettiPiece.latestEnd, cueStart + cueDuration)
    }

    // MARK: Easing

    public static func clamp01(_ value: Double) -> Double {
        guard value.isFinite else { return value > 0 ? 1 : 0 }
        return min(1, max(0, value))
    }

    /// How far `elapsed` is through the window that starts at `start` and lasts `duration` (0 before it, 1 after it).
    public static func progress(_ elapsed: TimeInterval, start: TimeInterval, duration: TimeInterval) -> Double {
        guard duration > 0 else { return elapsed >= start ? 1 : 0 }
        return clamp01((elapsed - start) / duration)
    }

    public static func easeOut(_ x: Double) -> Double {
        let u = 1 - clamp01(x)
        return 1 - u * u * u
    }

    public static func easeIn(_ x: Double) -> Double {
        let u = clamp01(x)
        return u * u
    }

    public static func easeInOut(_ x: Double) -> Double {
        let u = clamp01(x)
        return u < 0.5 ? 4 * u * u * u : 1 - pow(-2 * u + 2, 3) / 2
    }

    /// Ease-out that overshoots 1 on the way (about 1.1) and settles at exactly 1: the spring of a rising title or figure.
    public static func easeOutBack(_ x: Double) -> Double {
        let u = clamp01(x)
        let c1 = 1.70158
        let c3 = c1 + 1
        let shifted = u - 1
        return 1 + c3 * shifted * shifted * shifted + c1 * shifted * shifted
    }

    /// Eased interpolation through `stops` (sorted by `at`, from 0 to 1): each segment eases out from one value to the next.
    static func keyframes(_ x: Double, _ stops: [(at: Double, value: Double)]) -> Double {
        guard let first = stops.first, let last = stops.last else { return 0 }
        let u = clamp01(x)
        if u <= first.at { return first.value }
        if u >= last.at { return last.value }
        for index in 1..<stops.count {
            let from = stops[index - 1]
            let to = stops[index]
            if u <= to.at {
                let local = (u - from.at) / (to.at - from.at)
                return from.value + (to.value - from.value) * easeOut(local)
            }
        }
        return last.value
    }

    // MARK: The medal

    public struct MedalPose: Equatable, Sendable {
        public var scale: Double
        public var rotation: Double
        public var opacity: Double
    }

    /// The spring-in of the medal: from nothing, past full size (1.14), a little under (0.96), to rest; it also untwists from -24°.
    public static func medalPose(at elapsed: TimeInterval) -> MedalPose {
        let u = progress(elapsed, start: medalStart, duration: medalDuration)
        return MedalPose(
            scale: keyframes(u, [(0, 0), (0.55, 1.14), (0.78, 0.96), (1, 1)]),
            rotation: keyframes(u, [(0, -24), (0.55, 4), (0.78, 0), (1, 0)]),
            opacity: easeOut(u / 0.55)
        )
    }

    /// The small pulse of the medal at the impact (1 → 1.1 → 1).
    public static func thumbScale(at elapsed: TimeInterval) -> Double {
        let u = progress(elapsed, start: impact, duration: 0.6)
        return keyframes(u, [(0, 1), (0.35, 1.1), (1, 1)])
    }

    /// How much of the ring around the medal is drawn (0 to 1).
    public static func ringProgress(at elapsed: TimeInterval) -> Double {
        easeInOut(progress(elapsed, start: ringStart, duration: ringDuration))
    }

    /// How much of the check mark is drawn (0 to 1).
    public static func checkProgress(at elapsed: TimeInterval) -> Double {
        easeOut(progress(elapsed, start: checkStart, duration: checkDuration))
    }

    public struct Burst: Equatable, Sendable {
        public var scale: Double
        public var opacity: Double
    }

    /// One of the two rings that grow and fade from the medal at the impact; `index` 1 follows 0.18 s after 0.
    public static func ripple(at elapsed: TimeInterval, index: Int) -> Burst {
        let u = progress(elapsed, start: impact + 0.18 * Double(index), duration: 1.2)
        guard u > 0, u < 1 else { return Burst(scale: 0.85, opacity: 0) }
        let e = easeOut(u)
        return Burst(scale: 0.85 + 1.55 * e, opacity: 0.75 * (1 - e))
    }

    /// The ring of short rays that flashes out of the medal at the impact.
    public static func sparks(at elapsed: TimeInterval) -> Burst {
        let u = progress(elapsed, start: impact, duration: 0.9)
        guard u > 0, u < 1 else { return Burst(scale: 0.55, opacity: 0) }
        let opacity = u <= 0.25 ? u / 0.25 : (1 - u) / 0.75
        return Burst(scale: 0.55 + 0.8 * easeOut(u), opacity: opacity)
    }

    /// The soft light behind the medal: it flares at the impact and stays as a glow.
    public static func glow(at elapsed: TimeInterval) -> Burst {
        let u = progress(elapsed, start: impact, duration: 1.8)
        guard u > 0 else { return Burst(scale: 0.8, opacity: 0) }
        return Burst(
            scale: keyframes(u, [(0, 0.8), (0.35, 1.25), (1, 1.1)]),
            opacity: keyframes(u, [(0, 0), (0.35, 0.6), (1, 0.3)])
        )
    }

    /// The sunburst behind the medal: it fades and grows in at the impact and turns slowly until things settle.
    public static func rays(at elapsed: TimeInterval) -> (scale: Double, opacity: Double, rotation: Double) {
        let start = impact - 0.05
        let u = progress(elapsed, start: start, duration: 1.6)
        let turning = min(max(0, elapsed - start), settleTime - start)
        return (scale: 0.6 + 0.4 * easeOut(u), opacity: easeOut(u), rotation: turning * 7.2)
    }

    public struct Twinkle: Equatable, Sendable {
        public var scale: Double
        public var rotation: Double
        public var opacity: Double
    }

    /// A star that blinks once: it opens, turns a quarter and closes again over 1.3 s, beginning at `delay`.
    public static func twinkle(at elapsed: TimeInterval, delay: TimeInterval) -> Twinkle {
        let u = progress(elapsed, start: delay, duration: 1.3)
        guard u > 0, u < 1 else { return Twinkle(scale: 0, rotation: 0, opacity: 0) }
        let open = u < 0.4 ? easeInOut(u / 0.4) : 1 - easeInOut((u - 0.4) / 0.6)
        return Twinkle(scale: open, rotation: 120 * u, opacity: open)
    }

    // MARK: Text and figures

    /// 0 before `start`, then a spring (it overshoots 1 on the way) to 1: drives the rise of a line or a figure.
    public static func rise(at elapsed: TimeInterval, start: TimeInterval, duration: TimeInterval = 0.75) -> Double {
        easeOutBack(progress(elapsed, start: start, duration: duration))
    }

    /// 0 before `start`, then straight to 1 without overshoot.
    public static func fade(at elapsed: TimeInterval, start: TimeInterval, duration: TimeInterval = 0.7) -> Double {
        easeOut(progress(elapsed, start: start, duration: duration))
    }

    /// How far the figures have counted (0 to 1): fast at first, slowing into the final value.
    public static func countProgress(at elapsed: TimeInterval) -> Double {
        easeOut(progress(elapsed, start: countStart, duration: countDuration))
    }

    // MARK: Scrolling down to the stats

    /// How far the stats sheet has come up over the celebration: 0 at rest, 1 once its top is at the top of the screen.
    /// `sheetTop` is the distance from the top of the visible area to the top of the sheet; `heroHeight` is what it is at rest.
    public static func scrollProgress(sheetTop: Double, heroHeight: Double) -> Double {
        guard heroHeight > 0, sheetTop.isFinite else { return 0 }
        return 1 - clamp01(sheetTop / heroHeight)
    }

    /// The green behind the celebration is fully there until the sheet is well up and then gives way to the plain screen
    /// background, so the sheet's rounded top corners and the strip behind the status bar do not show green on the stats page.
    public static func backdropOpacity(scrollProgress: Double) -> Double {
        1 - progress(scrollProgress, start: 0.6, duration: 0.4)
    }

    /// The Done bar is see-through over the celebration and becomes the solid bar of the stats page as the sheet comes up
    /// (0 over the celebration, 1 once the sheet covers most of the screen).
    public static func barProgress(scrollProgress: Double) -> Double {
        progress(scrollProgress, start: 0.2, duration: 0.4)
    }

    /// The scroll cue and the celebration itself recede as the sheet covers them (1 at rest, 0 once it is well up).
    public static func heroVisibility(scrollProgress: Double) -> Double {
        1 - progress(scrollProgress, start: 0.0, duration: 0.8)
    }
}

// MARK: - Figures

/// The three big figures of the celebration and how they read while they count up.
public struct SummaryFigures: Equatable, Sendable {
    public struct Figure: Equatable, Sendable {
        public let value: String
        /// "h", "min", "s" or "kg"; empty for the number of sets.
        public let unit: String
    }

    public let durationSeconds: Int
    public let volumeKg: Double
    public let sets: Int

    public init(durationSeconds: Int, volumeKg: Double, sets: Int) {
        self.durationSeconds = max(0, durationSeconds)
        self.volumeKg = volumeKg.isFinite ? max(0, volumeKg) : 0
        self.sets = max(0, sets)
    }

    /// The figures once the count is done.
    public var counted: (duration: Figure, volume: Figure, sets: Figure) {
        (duration(at: 1), volume(at: 1), setCount(at: 1))
    }

    /// The duration at `progress` (0 to 1): "1:15 h" from an hour on, "52 min" under an hour, "45 s" under a minute. The unit
    /// is chosen from the final duration, so it does not change while counting.
    public func duration(at progress: Double) -> Figure {
        let p = SummaryCelebration.clamp01(progress)
        if durationSeconds >= 3600 {
            let finalMinutes = durationSeconds / 60
            let minutes = Int((Double(finalMinutes) * p).rounded())
            let value = String(minutes / 60) + ":" + (minutes % 60 < 10 ? "0" : "") + String(minutes % 60)
            return Figure(value: value, unit: "h")
        }
        if durationSeconds >= 60 {
            let finalMinutes = durationSeconds / 60
            return Figure(value: String(Int((Double(finalMinutes) * p).rounded())), unit: "min")
        }
        return Figure(value: String(Int((Double(durationSeconds) * p).rounded())), unit: "s")
    }

    public func volume(at progress: Double) -> Figure {
        let p = SummaryCelebration.clamp01(progress)
        return Figure(value: NumberText.thousands(volumeKg * p), unit: "kg")
    }

    public func setCount(at progress: Double) -> Figure {
        let p = SummaryCelebration.clamp01(progress)
        return Figure(value: String(Int((Double(sets) * p).rounded())), unit: "")
    }
}

// MARK: - Confetti

/// One piece of confetti: where it starts, where it flies and how it tumbles. A piece rises to its highest point (36 % of its
/// flight) with a decelerating move, then falls away accelerating, shrinking a little and fading out.
public struct ConfettiPiece: Equatable, Identifiable, Sendable {
    public enum Launcher: Equatable, Sendable {
        /// From the medal, in every direction.
        case burst
        /// From the lower leading (left) corner, up and inwards.
        case cannonLeading
        /// From the lower trailing (right) corner, up and inwards.
        case cannonTrailing
    }

    public enum Shape: Equatable, Sendable {
        case ribbon
        case dot
        case chip
    }

    public struct Pose: Equatable, Sendable {
        /// Offsets from the launch point, in points at the design size (390 x 844).
        public var x: Double
        public var y: Double
        /// Degrees in the plane of the screen.
        public var rotation: Double
        /// Degrees of tumbling around the horizontal axis (the piece seems to turn over: its height follows cos).
        public var flip: Double
        public var scale: Double
        public var opacity: Double
    }

    /// The colours the pieces use: indexes into the view's palette.
    public static let paletteCount = 6
    /// The share of a flight at which a piece is at its highest.
    public static let apex = 0.36

    public let id: Int
    public let launcher: Launcher
    public let shape: Shape
    public let colorIndex: Int
    public let width: Double
    public let height: Double
    /// Where the piece is at its highest, relative to the launch point.
    public let dx: Double
    public let dy: Double
    /// Where it ends up vertically (it also drifts on to 1.2 times `dx`).
    public let dyFall: Double
    public let rotation: Double
    public let flip: Double
    public let delay: TimeInterval
    public let duration: TimeInterval

    public var end: TimeInterval { delay + duration }

    /// Nil before the piece launches and after it has gone.
    public func pose(at elapsed: TimeInterval) -> Pose? {
        let t = (elapsed - delay) / duration
        guard t > 0, t < 1 else { return nil }
        if t < ConfettiPiece.apex {
            let e = SummaryCelebration.easeOut(t / ConfettiPiece.apex)
            return Pose(
                x: dx * e,
                y: dy * e,
                rotation: rotation * 0.45 * e,
                flip: flip * 0.45 * e,
                scale: 0.3 + 0.7 * e,
                opacity: 1
            )
        }
        let e = SummaryCelebration.easeIn((t - ConfettiPiece.apex) / (1 - ConfettiPiece.apex))
        return Pose(
            x: dx + (dx * 1.2 - dx) * e,
            y: dy + (dyFall - dy) * e,
            rotation: rotation * (0.45 + 0.55 * e),
            flip: flip * (0.45 + 0.55 * e),
            scale: 1 - 0.15 * e,
            opacity: 1 - e
        )
    }

    /// The last moment any piece of the standard set is still on screen.
    public static var latestEnd: TimeInterval {
        standardSet.map { $0.end }.max() ?? 0
    }

    /// The set the summary uses.
    public static let standardSet: [ConfettiPiece] = makeSet()

    public static let burstCount = 34
    public static let cannonCount = 15

    /// The pieces for one celebration: a burst from the medal at the impact, then a spray from each lower corner. The same seed
    /// always gives the same pieces.
    public static func makeSet(seed: UInt64 = 20_261_017) -> [ConfettiPiece] {
        var random = SplitMix64(state: seed)
        var pieces: [ConfettiPiece] = []

        func piece(
            launcher: Launcher,
            dx: Double,
            dy: Double,
            fall: Double,
            delay: Double,
            duration: Double
        ) -> ConfettiPiece {
            let kind = Int(random.unit() * 3)
            let shape: Shape = kind == 0 ? .ribbon : (kind == 1 ? .dot : .chip)
            let width = 6 + random.unit() * 3
            let height: Double
            switch shape {
            case .ribbon: height = 12 + random.unit() * 6
            case .dot: height = width
            case .chip: height = 7 + random.unit() * 3
            }
            let color = min(paletteCount - 1, Int(random.unit() * Double(paletteCount)))
            let spin = (random.unit() < 0.5 ? -1.0 : 1.0) * (360 + random.unit() * 720)
            let tumble = (random.unit() < 0.5 ? -1.0 : 1.0) * (360 + random.unit() * 900)
            return ConfettiPiece(
                id: pieces.count,
                launcher: launcher,
                shape: shape,
                colorIndex: color,
                width: width,
                height: height,
                dx: dx,
                dy: dy,
                dyFall: fall,
                rotation: spin,
                flip: tumble,
                delay: delay,
                duration: duration
            )
        }

        for index in 0..<burstCount {
            let angle = Double(index) / Double(burstCount) * 2 * Double.pi + (random.unit() - 0.5) * 0.3
            let distance = 120 + random.unit() * 200
            let dx = cos(angle) * distance
            let dy = sin(angle) * distance * 0.9 - 40
            let fall = dy + 240 + random.unit() * 260
            let delay = SummaryCelebration.impact + random.unit() * 0.1
            let duration = 2.3 + random.unit() * 1.0
            pieces.append(piece(launcher: .burst, dx: dx, dy: dy, fall: fall, delay: delay, duration: duration))
        }

        for launcher in [Launcher.cannonLeading, Launcher.cannonTrailing] {
            let direction = launcher == .cannonLeading ? 1.0 : -1.0
            for index in 0..<cannonCount {
                let dx = direction * (50 + random.unit() * 210)
                let dy = -(360 + random.unit() * 260)
                let fall = dy + 640 + random.unit() * 200
                let delay = SummaryCelebration.cannonStart + Double(index) * 0.012 + random.unit() * 0.05
                let duration = 2.2 + random.unit() * 1.0
                pieces.append(piece(launcher: launcher, dx: dx, dy: dy, fall: fall, delay: delay, duration: duration))
            }
        }
        return pieces
    }
}

/// A small deterministic generator (SplitMix64), so the confetti is the same on every device and in every test run.
private struct SplitMix64 {
    var state: UInt64

    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// A number in 0 ..< 1.
    mutating func unit() -> Double {
        Double(next() >> 11) / 9_007_199_254_740_992.0
    }
}
