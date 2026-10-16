#if os(iOS)
import Foundation
import PulseStrengthCore

// MARK: - Codec

/// The wire format of the widget snapshot that travels to the Watch: the JSON of `WidgetSnapshot` with sorted keys and ISO-8601 dates with
/// milliseconds, the same text format `WidgetSnapshotStore` writes to its file, so two equal snapshots give equal bytes and the Watch can
/// save what it decoded with `WidgetSnapshotStore.save`. It decodes dates with or without fractional seconds and with any UTC offset.
///
/// `PulseStrengthCore` keeps its own coder internal, so the two ends of the link (this file and `WatchWidgetSnapshotReceiver` in
/// `PulseStrengthWatchUI`) each carry a small copy of the plain `JSONEncoder` / `JSONDecoder` setup.
public enum WidgetSnapshotCodec {
    public static func encode(_ snapshot: WidgetSnapshot) throws -> Data {
        let formatters = ISO8601Formatters()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .custom { (date: Date, encoder: Encoder) throws -> Void in
            var container = encoder.singleValueContainer()
            try container.encode(formatters.withFraction.string(from: date))
        }
        encoder.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        return try encoder.encode(snapshot)
    }

    public static func decode(_ data: Data) throws -> WidgetSnapshot {
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

/// The two ISO-8601 formatters of one coding pass (milliseconds, and none for reading older text). Each pass makes its own and uses them
/// on its own thread only, which is why they may be captured by the coders' `@Sendable` date closures.
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

// MARK: - Sender

/// Phone -> Watch: the latest `WidgetSnapshot` for the Watch widgets and complications.
///
/// The app's widget publisher calls `update(_:)` whenever it writes a new snapshot. The snapshot travels inside the SAME application-context
/// dictionary as the state envelope, under the extra key `"w"` (`payloadKey`; the envelope stays under `"m"`), as the `Data` of
/// `WidgetSnapshotCodec`. `WCSession.updateApplicationContext` replaces the whole dictionary, so the sender remembers the latest blob and
/// `PhoneWatchBridge` adds it to every context it sends, and sends the context again when only the snapshot changed. The Watch app saves it
/// into its own App Group container (`WatchWidgetSnapshotReceiver`) and reloads its widgets.
///
/// Live `sendMessage` payloads do not carry the snapshot: they stay as small as they were, and the context reaches a running Watch app as
/// soon as the message does. The snapshot is about 10 to 15 KB of JSON (the preview snapshot is 10 KB).
public final class WatchWidgetSnapshotSender: @unchecked Sendable {
    public static let shared = WatchWidgetSnapshotSender()

    /// The key of the encoded snapshot in the WatchConnectivity dictionaries (the state envelope is under `SyncCodec.payloadKey`, `"m"`).
    public static let payloadKey = "w"

    private let lock = NSLock()
    private var latest: Data?
    private var changeHandler: (@Sendable () -> Void)?

    private init() {}

    /// Remembers `snapshot` as the one the Watch should show and tells the bridge to send it. Safe to call from any thread, as often as the
    /// publisher likes: a snapshot that encodes to the same bytes as the previous one sends nothing.
    public func update(_ snapshot: WidgetSnapshot) {
        guard let data = try? WidgetSnapshotCodec.encode(snapshot) else { return }
        lock.lock()
        let changed = data != latest
        latest = data
        let handler = changeHandler
        lock.unlock()
        if changed {
            handler?()
        }
    }

    /// The encoded latest snapshot; nil until `update(_:)` has run.
    var latestData: Data? {
        lock.lock()
        defer { lock.unlock() }
        return latest
    }

    /// `PhoneWatchBridge` registers here to be told (on any thread) when a different snapshot arrived.
    func observeChanges(_ handler: @escaping @Sendable () -> Void) {
        lock.lock()
        changeHandler = handler
        lock.unlock()
    }

    /// `payload` with the latest snapshot added under `payloadKey`; `payload` itself when no snapshot is known yet.
    func attaching(to payload: [String: Any]) -> [String: Any] {
        guard let data = latestData else { return payload }
        var merged = payload
        merged[Self.payloadKey] = data
        return merged
    }
}
#endif
