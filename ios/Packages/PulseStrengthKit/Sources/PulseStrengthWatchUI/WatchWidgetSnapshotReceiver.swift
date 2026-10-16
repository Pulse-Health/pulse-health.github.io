#if os(watchOS)
import Foundation
import WidgetKit
import PulseStrengthCore

// MARK: - Codec

/// Reads the widget snapshot the iPhone sent: the JSON of `WidgetSnapshot` with ISO-8601 dates, with or without fractional seconds and with
/// any UTC offset (`WidgetSnapshotCodec` in `PulseStrengthIOS` writes it; `PulseStrengthCore` keeps its own coder internal).
enum WidgetSnapshotCodec {
    static func decode(_ data: Data) throws -> WidgetSnapshot {
        let formatters = ISO8601Formatters()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { (decoder: Decoder) throws -> Date in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let date = formatters.withFraction.date(from: text) ?? formatters.withoutFraction.date(from: text) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not an ISO-8601 date: \(text)")
            }
            return date
        }
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        return try decoder.decode(WidgetSnapshot.self, from: data)
    }
}

/// The two ISO-8601 formatters of one decoding pass. Each pass makes its own and uses them on its own thread only, which is why they may
/// be captured by the decoder's `@Sendable` date closure.
private struct ISO8601Formatters: @unchecked Sendable {
    let withFraction: ISO8601DateFormatter
    let withoutFraction: ISO8601DateFormatter

    init() {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        withFraction = fractional
        withoutFraction = plain
    }
}

// MARK: - Receiver

/// The Watch app's end of two hand-offs that concern the Watch widgets.
///
/// * iPhone -> widgets. `handle(payload:)` takes the WatchConnectivity dictionaries (application context, message, user info) from
///   `WatchConnectivityClient`, finds the widget snapshot under the key `"w"` (see `WatchWidgetSnapshotSender` in `PulseStrengthIOS`), saves it
///   into the Watch's own App Group container with `WidgetSnapshotStore.save` and reloads the Watch widgets. The widget extension reads that
///   file; it never talks to the iPhone itself.
/// * Widgets -> workout. The buttons of the Watch widgets (`WatchIntents.swift`) leave their action in the Watch's command inbox
///   (`WidgetCommandInbox`) and post the Darwin notification `StrengthConfig.commandInboxNotification`. `drainCommands()` empties the inbox
///   when that notification arrives, when the app launches (`start`) and whenever the client asks the iPhone for its state (the app
///   delegate does so each time the app becomes active), and applies each action with the Watch controller, `controller.send(_, origin: .watch)`.
///   That is the way every edit made on the Watch reaches the iPhone (one `RemoteCommand` per edit, acknowledged by the iPhone's next
///   envelope); there is no second path for workout state. A link left by the Start button only makes the Watch ask the iPhone for the workout:
///   starting one is the iPhone's job.
///
/// Use `WatchWidgetSnapshotReceiver.shared`. `handle(payload:)` may run on any thread; everything else runs on the main actor.
public final class WatchWidgetSnapshotReceiver: @unchecked Sendable {
    public static let shared = WatchWidgetSnapshotReceiver()

    /// The key of the encoded snapshot in the WatchConnectivity dictionaries (`WatchWidgetSnapshotSender.payloadKey` on the iPhone).
    public static let payloadKey = "w"

    private let lock = NSLock()
    private var lastData: Data?

    // Main actor only.
    private weak var controller: WorkoutController?
    private var requestState: (@MainActor () -> Void)?
    private var isObserving = false

    private init() {}

    // MARK: iPhone -> widgets

    /// Saves the widget snapshot in `payload`, if there is one that differs from the last one handled, and reloads the Watch widgets.
    /// Anything that is not a valid snapshot of this or an older schema is ignored, and the saved file stays as it was.
    public func handle(payload: [String: Any]) {
        guard let data = payload[Self.payloadKey] as? Data else { return }
        guard save(data) else { return }
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// True when `data` replaced the snapshot on disk.
    private func save(_ data: Data) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard data != lastData else { return false }
        guard let snapshot = try? WidgetSnapshotCodec.decode(data),
              snapshot.schemaVersion <= WidgetSnapshot.currentSchemaVersion
        else { return false }
        lastData = data
        // The snapshot built at the same instant is the one already saved (the context the app re-reads at every launch): it needs
        // neither a write nor a reload.
        if let stored = WidgetSnapshotStore.load(), abs(stored.generatedAt.timeIntervalSince(snapshot.generatedAt)) < 0.001 {
            return false
        }
        do {
            try WidgetSnapshotStore.save(snapshot)
        } catch {
            lastData = nil
            return false
        }
        return true
    }

    // MARK: Widgets -> workout

    /// Connects the receiver to the Watch's workout: applies what the widgets left in the inbox now and whenever the Darwin notification
    /// arrives. `requestState` asks the iPhone for the current workout (`WatchConnectivityClient.requestState`). Call it once at launch.
    @MainActor
    public func start(controller: WorkoutController, requestState: @escaping @MainActor () -> Void) {
        self.controller = controller
        self.requestState = requestState
        observeInbox()
        drainCommands()
    }

    /// Applies every request the Watch widgets left in the inbox (older than ten minutes: dropped by the inbox) and empties it.
    @MainActor
    public func drainCommands() {
        guard let controller, let inbox = WidgetCommandInbox.shared() else { return }
        guard let commands = try? inbox.drain(), !commands.isEmpty else { return }
        var applied = false
        var logged = false
        for command in commands {
            if let action = command.action {
                // A mirror numbers and forwards the edit itself; an action that changes nothing (the workout is gone, the set is
                // logged already) leaves the revision alone and sends nothing.
                let before = controller.state?.revision
                controller.send(action, origin: .watch)
                if controller.state?.revision != before {
                    applied = true
                    if case .logSet = action { logged = true }
                }
            } else if command.link != nil {
                requestState?()
            }
        }
        if logged {
            WatchHaptics.success()
        } else if applied {
            WatchHaptics.click()
        }
    }

    @MainActor
    private func observeInbox() {
        guard !isObserving else { return }
        isObserving = true
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            { _, observer, _, _, _ in
                guard let observer else { return }
                let receiver = Unmanaged<WatchWidgetSnapshotReceiver>.fromOpaque(observer).takeUnretainedValue()
                Task { @MainActor in
                    receiver.drainCommands()
                }
            },
            StrengthConfig.commandInboxNotification as CFString,
            nil,
            .deliverImmediately
        )
    }
}
#endif
