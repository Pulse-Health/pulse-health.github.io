#if os(iOS)
import SwiftUI
import UIKit
import PulseStrengthCore

// MARK: - Frame loading

/// The two form-demo frames of one exercise ("<mediaKey>-a" and "<mediaKey>-b").
struct ExerciseMediaFrames {
    var first: UIImage?
    var second: UIImage?

    var hasAny: Bool { first != nil || second != nil }
}

/// Loads and caches the loose `.jpg` frames shipped in the package resources.
/// Lookups that fail are remembered too, so a missing frame is not searched for again every second.
final class ExerciseMediaStore: @unchecked Sendable {
    static let shared = ExerciseMediaStore()

    private let lock = NSLock()
    private var images: [String: UIImage] = [:]
    private var missing: Set<String> = []

    private init() {}

    func frames(for mediaKey: String?) -> ExerciseMediaFrames {
        guard let key = mediaKey, !key.isEmpty else { return ExerciseMediaFrames(first: nil, second: nil) }
        let a = image(named: key + "-a")
        let b = image(named: key + "-b")
        // With a single frame, show it as the (static) first frame.
        if a == nil, let only = b { return ExerciseMediaFrames(first: only, second: nil) }
        return ExerciseMediaFrames(first: a, second: b)
    }

    private func image(named name: String) -> UIImage? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = images[name] { return cached }
        if missing.contains(name) { return nil }
        if let loaded = ExerciseMediaStore.load(name: name) {
            images[name] = loaded
            return loaded
        }
        missing.insert(name)
        return nil
    }

    private static func load(name: String) -> UIImage? {
        if let image = UIImage(named: name, in: Bundle.module, with: nil) {
            return image
        }
        // Processed resources can keep or drop their folder depending on the build system.
        let folders: [String?] = [nil, "ExerciseMedia", "Resources/ExerciseMedia"]
        for folder in folders {
            if let url = Bundle.module.url(forResource: name, withExtension: "jpg", subdirectory: folder),
               let image = UIImage(contentsOfFile: url.path) {
                return image
            }
        }
        return nil
    }
}

// MARK: - View

/// The form-demo tile: crossfades the two frames of an exercise every 0.9 s (0.35 s fade),
/// aspect-fill and clipped to a rounded rectangle. Fills whatever frame it is given.
/// Shows a placeholder figure when the exercise has no media or the image is missing,
/// and a static first frame when Reduce Motion is on.
public struct ExerciseMediaView: View {
    private let mediaKey: String?
    private let cornerRadius: CGFloat
    private let animated: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// `animated: false` shows the static first frame, like the design's list and picker thumbnails.
    public init(mediaKey: String?, cornerRadius: CGFloat = 12, animated: Bool = true) {
        self.mediaKey = mediaKey
        self.cornerRadius = cornerRadius
        self.animated = animated
    }

    public var body: some View {
        let frames = ExerciseMediaStore.shared.frames(for: mediaKey)
        return Color.clear
            .overlay { tileContent(frames) }
            .background(PulseTheme.mediaTile)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func tileContent(_ frames: ExerciseMediaFrames) -> some View {
        if let first = frames.first {
            if let second = frames.second, !reduceMotion, animated {
                ExerciseMediaCrossfade(first: first, second: second)
            } else {
                ExerciseMediaFill(image: first)
            }
        } else {
            ExerciseMediaPlaceholder()
        }
    }
}

// MARK: - Pieces

private struct ExerciseMediaFill: View {
    let image: UIImage

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
    }
}

private struct ExerciseMediaCrossfade: View {
    let first: UIImage
    let second: UIImage

    private static let period: Double = 0.9

    var body: some View {
        TimelineView(.periodic(from: Date(timeIntervalSinceReferenceDate: 0), by: ExerciseMediaCrossfade.period)) { context in
            let showSecond = ExerciseMediaCrossfade.isSecondFrame(at: context.date)
            ZStack {
                ExerciseMediaFill(image: first)
                ExerciseMediaFill(image: second)
                    .opacity(showSecond ? 1 : 0)
            }
            .animation(.easeInOut(duration: 0.35), value: showSecond)
        }
    }

    private static func isSecondFrame(at date: Date) -> Bool {
        let steps = date.timeIntervalSinceReferenceDate / period
        // The small offset keeps a tick that lands a hair before its boundary on the right side of it.
        let index = Int((steps + 0.001).rounded(.down))
        return index % 2 != 0
    }
}

/// The design's dumbbell in grey: 36 pt (stroke 1.4) in the 60 pt tile of the exercise card, 22 pt (stroke 1.6) in
/// the 44 pt list tiles, and no larger than the 44 pt of the form sheet's "no demo" panel in a big frame.
private struct ExerciseMediaPlaceholder: View {
    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let isLargeTile = side >= 56
            StrengthDumbbellGlyph(
                size: isLargeTile ? min(side * 0.6, 44) : max(10, side * 0.5),
                color: PulseTheme.inkTertiary,
                strokeWidth: isLargeTile ? 1.4 : 1.6
            )
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}
#endif
