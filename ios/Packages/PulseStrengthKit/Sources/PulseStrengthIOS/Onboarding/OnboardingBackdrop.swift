#if os(iOS)
import SwiftUI
import UIKit
import AVFoundation
import PulseStrengthCore

// The picture behind every step of the onboarding: the hero clip (a still poster first, the muted looping video fades in over it),
// two dark gradients that keep the status bar and the copy legible, and a veil that takes over once the setup steps start.

// MARK: - Resources

/// Finds the clip and its poster in the package resources.
enum OnboardingMedia {
    static let videoName = "onboarding-hero"
    static let posterName = "onboarding-hero-poster"

    static func videoURL() -> URL? {
        url(videoName, "mp4")
    }

    /// The poster, decoded once.
    static let poster: UIImage? = {
        guard let url = url(posterName, "jpg") else { return nil }
        return UIImage(contentsOfFile: url.path)
    }()

    private static func url(_ name: String, _ fileExtension: String) -> URL? {
        // Processed resources can keep or drop their folder depending on the build system.
        let folders: [String?] = [nil, "Onboarding", "Resources/Onboarding"]
        for folder in folders {
            if let url = Bundle.module.url(forResource: name, withExtension: fileExtension, subdirectory: folder) {
                return url
            }
        }
        return nil
    }
}

// MARK: - Looping video

/// A view whose layer shows an `AVPlayer`.
final class OnboardingPlayerView: UIView {
    let playerLayer = AVPlayerLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        playerLayer.videoGravity = .resizeAspectFill
        layer.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
    }
}

/// The hero clip: muted, looping, never takes the audio session (the clip has no audio track either).
/// `isPlaying` starts and pauses it; `onFirstFrame` fires once the first frame can be shown.
struct OnboardingLoopingVideo: UIViewRepresentable {
    let url: URL
    let isPlaying: Bool
    let onFirstFrame: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> OnboardingPlayerView {
        let view = OnboardingPlayerView()
        context.coordinator.attach(url: url, to: view, onFirstFrame: onFirstFrame)
        context.coordinator.setPlaying(isPlaying)
        return view
    }

    func updateUIView(_ view: OnboardingPlayerView, context: Context) {
        context.coordinator.setPlaying(isPlaying)
    }

    static func dismantleUIView(_ view: OnboardingPlayerView, coordinator: Coordinator) {
        coordinator.stop(view)
    }

    final class Coordinator {
        private var player: AVQueuePlayer?
        private var looper: AVPlayerLooper?
        private var readyObservation: NSKeyValueObservation?
        private var wantsPlayback = false

        func attach(url: URL, to view: OnboardingPlayerView, onFirstFrame: @escaping () -> Void) {
            let queue = AVQueuePlayer()
            queue.isMuted = true
            queue.allowsExternalPlayback = false
            queue.preventsDisplaySleepDuringVideoPlayback = false
            looper = AVPlayerLooper(player: queue, templateItem: AVPlayerItem(url: url))
            player = queue
            view.playerLayer.player = queue
            readyObservation = view.playerLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) { layer, _ in
                if layer.isReadyForDisplay {
                    DispatchQueue.main.async {
                        onFirstFrame()
                    }
                }
            }
        }

        func setPlaying(_ playing: Bool) {
            wantsPlayback = playing
            guard let player = player else { return }
            if playing {
                player.play()
            } else {
                player.pause()
            }
        }

        func stop(_ view: OnboardingPlayerView) {
            readyObservation?.invalidate()
            readyObservation = nil
            player?.pause()
            looper?.disableLooping()
            looper = nil
            view.playerLayer.player = nil
            player = nil
        }
    }
}

// MARK: - Backdrop

/// The picture behind the screens.
///
/// * welcome and auth: the clip, slowly zooming in as the highlights and the sheet come on;
/// * the setup steps: the same picture, darker and blurred under the veil, with a faint green light at the top; the clip rests there.
@MainActor
struct OnboardingBackdrop: View {
    let step: OnboardingStep
    /// The highlight on the welcome screen (0...2): each one zooms in a little more.
    let highlight: Int
    /// The user asked for the motion to stop (the pause button).
    let isMotionPaused: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var videoIsReady = false
    @State private var lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled

    var body: some View {
        ZStack {
            Color.black
            media
            grade
            veil
        }
        .scaleEffect(zoom)
        .animation(reduceMotion ? nil : Animation.easeOut(duration: 1.6), value: zoom)
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    }

    // MARK: Picture

    @ViewBuilder
    private var media: some View {
        GeometryReader { proxy in
            ZStack {
                if let poster = OnboardingMedia.poster {
                    Image(uiImage: poster)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                }
                if let url = OnboardingMedia.videoURL(), !reduceMotion {
                    OnboardingLoopingVideo(url: url, isPlaying: shouldPlay) {
                        videoIsReady = true
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .opacity(videoIsReady ? 1 : 0)
                    .animation(Animation.easeInOut(duration: 1), value: videoIsReady)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    /// The clip only matters where it can be seen: behind the welcome copy and above the sheet. Behind the veil it rests.
    private var shouldPlay: Bool {
        (step == .welcome || step == .auth) && !isMotionPaused && !lowPowerMode && scenePhase == .active
    }

    // MARK: Layers

    /// A dark scrim at the top (status bar) and a dark floor at the bottom (the copy).
    private var grade: some View {
        ZStack {
            LinearGradient(
                stops: [
                    Gradient.Stop(color: Color.black.opacity(0.62), location: 0),
                    Gradient.Stop(color: Color.black.opacity(0.26), location: 0.12),
                    Gradient.Stop(color: Color.black.opacity(0), location: 0.26),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            LinearGradient(
                stops: [
                    Gradient.Stop(color: Color.black, location: 0),
                    Gradient.Stop(color: Color.black.opacity(0.94), location: 0.20),
                    Gradient.Stop(color: Color.black.opacity(0.62), location: 0.36),
                    Gradient.Stop(color: Color.black.opacity(0.22), location: 0.50),
                    Gradient.Stop(color: Color.black.opacity(0), location: 0.64),
                ],
                startPoint: .bottom,
                endPoint: .top
            )
        }
    }

    /// Darker, blurred, with a faint green horizon light: the setup steps. Half a veil under the sheet.
    private var veil: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            Color.black.opacity(0.62)
            RadialGradient(
                colors: [OnboardingTheme.green.opacity(0.20), OnboardingTheme.green.opacity(0)],
                center: .top,
                startRadius: 0,
                endRadius: 480
            )
        }
        .opacity(veilOpacity)
        .animation(reduceMotion ? nil : Animation.easeOut(duration: 0.8), value: veilOpacity)
    }

    private var veilOpacity: Double {
        switch step {
        case .welcome: return 0
        case .auth: return 0.3
        case .profile, .health, .coach, .notify, .done: return 1
        }
    }

    private var zoom: CGFloat {
        if reduceMotion { return 1 }
        switch step {
        case .welcome:
            let zooms: [CGFloat] = [1, 1.035, 1.07]
            return zooms[min(max(highlight, 0), zooms.count - 1)]
        case .auth:
            return 1.1
        case .profile, .health, .coach, .notify, .done:
            return 1.16
        }
    }
}
#endif
