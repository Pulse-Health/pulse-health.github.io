#if os(iOS)
import Foundation
import PulseStrengthCore

/// Process-wide hand-off between the Live Activity App Intents and the running app.
///
/// A `LiveActivityIntent` is executed in the app's process (see ARCHITECTURE.md 5.4). The intent only
/// knows how to build a `WorkoutAction`; the app installs a handler here that applies it to the
/// `WorkoutController`. When the app was launched in the background by the intent it may still be
/// starting up, so `perform` waits (polling every 50 ms, at most 3 s) for the handler to appear
/// and then gives up silently if it never does.
public final class WorkoutCommandBus: @unchecked Sendable {
    /// The handler type installed by the app.
    public typealias Handler = @Sendable (WorkoutAction, ActionOrigin) async -> Void

    public static let shared = WorkoutCommandBus()

    /// Longest time `perform` waits for a handler to be installed.
    private static let maximumWait: TimeInterval = 3
    /// Interval between two checks while waiting for a handler.
    private static let pollInterval: UInt64 = 50_000_000

    /// Guards `handler`.
    private let lock = NSLock()
    private var handler: Handler?

    public init() {}

    /// Installs the handler that executes commands. A later call replaces the earlier handler.
    public func install(_ handler: @escaping @Sendable (WorkoutAction, ActionOrigin) async -> Void) {
        lock.lock()
        self.handler = handler
        lock.unlock()
    }

    /// Runs `action` through the installed handler.
    ///
    /// If no handler is installed yet (the app is still starting after a background launch) this polls
    /// every 50 ms for up to 3 s. If none appears, or the calling task is cancelled meanwhile, the command
    /// is dropped without an error.
    public func perform(_ action: WorkoutAction, origin: ActionOrigin) async {
        guard let resolved = await waitForHandler() else { return }
        await resolved(action, origin)
    }

    // MARK: - Private

    private func currentHandler() -> Handler? {
        lock.lock()
        defer { lock.unlock() }
        return handler
    }

    private func waitForHandler() async -> Handler? {
        if let ready = currentHandler() {
            return ready
        }
        let deadline = Date().addingTimeInterval(Self.maximumWait)
        while Date() < deadline {
            do {
                try await Task.sleep(nanoseconds: Self.pollInterval)
            } catch {
                return currentHandler()
            }
            if let ready = currentHandler() {
                return ready
            }
        }
        return currentHandler()
    }
}
#endif
