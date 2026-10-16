#if os(iOS)
import SwiftUI
import PulseStrengthCore

// The frame every setup step shares: the title and one line under it, a body that scrolls when it does not fit, and the buttons pinned
// to the bottom. At accessibility text sizes everything scrolls together, so nothing is cut off and the buttons stay reachable.

/// Title, subtitle, scrolling content, pinned footer.
@MainActor
struct OnboardingSetupLayout<Content: View, Foot: View>: View {
    let title: String
    let subtitle: String
    /// True while this is the step on screen: VoiceOver moves to the title.
    let isActive: Bool
    private let content: Content
    private let foot: Foot

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AccessibilityFocusState private var titleHasFocus: Bool

    init(
        title: String,
        subtitle: String,
        isActive: Bool,
        @ViewBuilder content: () -> Content,
        @ViewBuilder foot: () -> Foot
    ) {
        self.title = title
        self.subtitle = subtitle
        self.isActive = isActive
        self.content = content()
        self.foot = foot()
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                scrollingEverything
            } else {
                pinnedFoot
            }
        }
        .onChange(of: isActive) { (_: Bool, active: Bool) in
            if active {
                titleHasFocus = true
            }
        }
    }

    /// The usual layout: head and body scroll above the buttons.
    private var pinnedFoot: some View {
        VStack(spacing: 0) {
            OnboardingFadingScroll {
                VStack(alignment: .leading, spacing: 0) {
                    head
                    content
                        .padding(.top, 22)
                }
                .padding(.horizontal, OnboardingTheme.heroInset)
                .padding(.bottom, 8)
            }
            foot
                .padding(.horizontal, OnboardingTheme.heroInset)
                .padding(.top, 12)
                .padding(.bottom, 12)
        }
    }

    /// Accessibility text sizes: one scroll view for head, body and buttons.
    private var scrollingEverything: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                head
                content
                    .padding(.top, 22)
                foot
                    .padding(.top, 20)
            }
            .padding(.horizontal, OnboardingTheme.heroInset)
            .padding(.bottom, 20)
        }
    }

    private var head: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .pulseFont(34, .bold, relativeTo: .largeTitle)
                .foregroundStyle(Color.white)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($titleHasFocus)
            Text(subtitle)
                .pulseFont(17, .regular, relativeTo: .body)
                .foregroundStyle(OnboardingTheme.onMediaSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Scroll view with a fade

private struct OnboardingContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct OnboardingViewportHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct OnboardingScrolledKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// A scroll view whose bottom edge fades out while there is more to scroll to (a soft hint that the content goes on).
@MainActor
private struct OnboardingFadingScroll<Content: View>: View {
    private let content: Content

    @State private var contentHeight: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0
    @State private var scrolled: CGFloat = 0

    private static var coordinateSpaceName: String { "onboardingFadingScroll" }

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView {
            content
                .background(
                    GeometryReader { proxy in
                        Color.clear
                            .preference(key: OnboardingContentHeightKey.self, value: proxy.size.height)
                            .preference(
                                key: OnboardingScrolledKey.self,
                                value: -proxy.frame(in: .named(OnboardingFadingScroll<Content>.coordinateSpaceName)).minY
                            )
                    }
                )
        }
        .coordinateSpace(name: OnboardingFadingScroll<Content>.coordinateSpaceName)
        .scrollBounceBehavior(.basedOnSize)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: OnboardingViewportHeightKey.self, value: proxy.size.height)
            }
        )
        .onPreferenceChange(OnboardingContentHeightKey.self) { (height: CGFloat) in
            contentHeight = height
        }
        .onPreferenceChange(OnboardingViewportHeightKey.self) { (height: CGFloat) in
            viewportHeight = height
        }
        .onPreferenceChange(OnboardingScrolledKey.self) { (distance: CGFloat) in
            scrolled = distance
        }
        .mask(fadeMask)
    }

    /// True while some of the content is still below the visible part.
    private var hasMoreBelow: Bool {
        contentHeight - viewportHeight - scrolled > 2
    }

    private var fadeMask: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color.black)
            LinearGradient(colors: [Color.black, Color.black.opacity(0)], startPoint: .top, endPoint: .bottom)
                .frame(height: hasMoreBelow ? 36 : 0)
        }
    }
}
#endif
