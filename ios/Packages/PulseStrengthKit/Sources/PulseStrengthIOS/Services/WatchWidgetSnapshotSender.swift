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
        let formatter = makeFormatter(fractionalSeconds: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .custom { (date: Date, encoder: Encoder) throws -> Void in
            var container = encoder.singleValueContainer()
            try container.encode(formatter.string(from: date))
        }
        encoder.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        return try encoder.encode(snapshot)
    }

    public static func decode(_ data: Data) throws -> WidgetSnapshot {
        let withFraction = makeFormatter(fractionalSeconds: true)
        let withoutFraction = makeFormatter(fractionalSeconds: false)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { (decoder: Decoder) throws -> Date in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let date = withFraction.date(from: text) ?? withoutFraction.date(from: text) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not an ISO-8601 date: \(text)")
            }
            return date
        }
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        return try decoder.decode(WidgetSnapshot.self, from: data)
    }

    private static func makeFormatter(fractionalSeconds: Bool) -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = fractionalSeconds ? [.withInternetDateTime, .withFractionalSeconds] : [.withInternetDateTime]
        return formatter
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
/// soon as the message does. The snapshot is about 15 to 30 KB of JSON.
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
