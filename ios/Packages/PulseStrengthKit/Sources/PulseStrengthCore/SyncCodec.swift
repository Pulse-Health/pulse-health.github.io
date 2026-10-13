import Foundation

// MARK: - Errors

/// Why a WatchConnectivity payload could not be turned into a `SyncMessage`.
public enum SyncCodecError: Error, Equatable, Sendable {
    /// The payload has no `"m"` entry holding JSON `Data`.
    case missingPayload
    /// The `"m"` entry is not a valid encoded `SyncMessage` (the text describes the decoding problem).
    case undecodablePayload(String)
}

// MARK: - Codec

/// Converts `SyncMessage` values to and from the `[String: Any]` dictionaries WatchConnectivity transports.
///
/// The dictionary holds one entry, `"m"`, whose value is the message as JSON `Data` (ISO-8601 dates, sorted keys).
public enum SyncCodec {
    /// The dictionary key that holds the encoded message.
    public static let payloadKey = "m"

    /// Encodes `message` as `["m": <JSON Data>]`.
    public static func encode(_ message: SyncMessage) throws -> [String: Any] {
        let data = try StrengthJSON.makeEncoder().encode(message)
        return [payloadKey: data]
    }

    /// Decodes a payload made by `encode`; throws `SyncCodecError` when the `"m"` entry is missing or garbled.
    public static func decode(_ payload: [String: Any]) throws -> SyncMessage {
        guard let data = payload[payloadKey] as? Data else {
            throw SyncCodecError.missingPayload
        }
        do {
            return try StrengthJSON.makeDecoder().decode(SyncMessage.self, from: data)
        } catch {
            throw SyncCodecError.undecodablePayload(String(describing: error))
        }
    }
}

// MARK: - Duplicate filter

/// Remembers the most recent command ids so a command that WatchConnectivity redelivers runs only once.
public struct SeenCommands: Sendable {
    private let capacity: Int
    private var ring: [UUID] = []
    private var head = 0
    private var members = Set<UUID>()

    /// A filter that remembers the last `capacity` ids (at least one).
    public init(capacity: Int = 256) {
        self.capacity = max(1, capacity)
    }

    /// True when `id` has not been seen among the remembered ids (and remembers it); false for a duplicate.
    @discardableResult
    public mutating func insertIfNew(_ id: UUID) -> Bool {
        guard members.insert(id).inserted else { return false }
        if ring.count < capacity {
            ring.append(id)
        } else {
            members.remove(ring[head])
            ring[head] = id
            head = (head + 1) % capacity
        }
        return true
    }
}

// MARK: - JSON configuration shared by sync and persistence

/// JSON encoder / decoder configuration used for sync messages and for the files on disk.
enum StrengthJSON {
    /// Sorted keys, ISO-8601 dates with milliseconds, non-finite numbers written as strings instead of failing.
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            guard let text = ISO8601Text.string(from: date) else {
                throw EncodingError.invalidValue(
                    date, EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "The date is not finite.")
                )
            }
            try container.encode(text)
        }
        encoder.nonConformingFloatEncodingStrategy = .convertToString(
            positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan"
        )
        return encoder
    }

    /// Reads what `makeEncoder` writes, and ISO-8601 dates with or without fractional seconds and with any UTC offset.
    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let date = ISO8601Text.date(from: text) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not an ISO-8601 date: \(text)")
            }
            return date
        }
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan"
        )
        return decoder
    }
}

// MARK: - ISO-8601 text

/// Hand-written ISO-8601 conversion (UTC, millisecond precision) so the output does not depend on any formatter or locale.
enum ISO8601Text {
    private static let millisecondsPerDay: Int64 = 86_400_000
    /// 0000-01-01T00:00:00.000Z in milliseconds since 1970.
    private static let firstMillisecond: Int64 = daysFromCivil(year: 0, month: 1, day: 1) * millisecondsPerDay
    /// 9999-12-31T23:59:59.999Z in milliseconds since 1970.
    private static let lastMillisecond: Int64 = daysFromCivil(year: 9999, month: 12, day: 31) * millisecondsPerDay + millisecondsPerDay - 1

    /// "2026-10-13T19:30:00.250Z"; nil for a non-finite date. Dates outside years 0000...9999 clamp to the ends.
    static func string(from date: Date) -> String? {
        let seconds = date.timeIntervalSince1970
        guard seconds.isFinite else { return nil }
        let scaled = (seconds * 1000).rounded()
        var milliseconds: Int64
        if scaled >= Double(lastMillisecond) {
            milliseconds = lastMillisecond
        } else if scaled <= Double(firstMillisecond) {
            milliseconds = firstMillisecond
        } else {
            milliseconds = Int64(scaled)
        }
        let days = floorDivide(milliseconds, millisecondsPerDay)
        let ofDay = milliseconds - days * millisecondsPerDay
        let (year, month, day) = civilFromDays(days)
        let hour = Int(ofDay / 3_600_000)
        let minute = Int(ofDay % 3_600_000 / 60_000)
        let second = Int(ofDay % 60_000 / 1000)
        let millisecond = Int(ofDay % 1000)
        return pad(year, 4) + "-" + pad(month, 2) + "-" + pad(day, 2) + "T" + pad(hour, 2) + ":" + pad(minute, 2) + ":"
            + pad(second, 2) + "." + pad(millisecond, 3) + "Z"
    }

    /// Parses "yyyy-MM-ddTHH:mm:ss" with optional fractional seconds and a "Z" or "+HH:MM" / "+HHMM" / "+HH" offset.
    static func date(from text: String) -> Date? {
        let bytes = Array(text.utf8)
        var index = 0

        func digits(_ count: Int) -> Int? {
            guard index + count <= bytes.count else { return nil }
            var value = 0
            for offset in 0..<count {
                let byte = bytes[index + offset]
                guard byte >= 48, byte <= 57 else { return nil }
                value = value * 10 + Int(byte - 48)
            }
            index += count
            return value
        }
        func expect(_ byte: UInt8) -> Bool {
            guard index < bytes.count, bytes[index] == byte else { return false }
            index += 1
            return true
        }

        guard let year = digits(4), expect(45), let month = digits(2), expect(45), let day = digits(2) else { return nil }
        guard expect(84) || expect(116) || expect(32) else { return nil }
        guard let hour = digits(2), expect(58), let minute = digits(2), expect(58), let second = digits(2) else { return nil }
        guard (1...12).contains(month), day >= 1, day <= daysInMonth(year: year, month: month) else { return nil }
        guard hour <= 23, minute <= 59, second <= 60 else { return nil }

        var fraction = 0.0
        if expect(46) || expect(44) {
            var numerator = 0.0
            var divisor = 1.0
            var count = 0
            while index < bytes.count, bytes[index] >= 48, bytes[index] <= 57 {
                if count < 9 {
                    numerator = numerator * 10 + Double(bytes[index] - 48)
                    divisor *= 10
                }
                count += 1
                index += 1
            }
            if count == 0 { return nil }
            fraction = numerator / divisor
        }

        var offsetSeconds = 0
        if index < bytes.count, bytes[index] == 90 || bytes[index] == 122 {
            index += 1
        } else if index < bytes.count, bytes[index] == 43 || bytes[index] == 45 {
            let sign = bytes[index] == 45 ? -1 : 1
            index += 1
            guard let offsetHour = digits(2), offsetHour <= 23 else { return nil }
            var offsetMinute = 0
            if index < bytes.count {
                _ = expect(58)
                guard let value = digits(2), value <= 59 else { return nil }
                offsetMinute = value
            }
            offsetSeconds = sign * (offsetHour * 3600 + offsetMinute * 60)
        } else {
            return nil
        }
        guard index == bytes.count else { return nil }

        let days = daysFromCivil(year: year, month: month, day: day)
        let wholeSeconds = days * 86_400 + Int64(hour * 3600 + minute * 60 + second - offsetSeconds)
        return Date(timeIntervalSince1970: Double(wholeSeconds) + fraction)
    }

    // MARK: Calendar arithmetic (proleptic Gregorian, days since 1970-01-01)

    private static func daysFromCivil(year: Int, month: Int, day: Int) -> Int64 {
        let y = Int64(month <= 2 ? year - 1 : year)
        let era = (y >= 0 ? y : y - 399) / 400
        let yearOfEra = y - era * 400
        let shiftedMonth = Int64(month > 2 ? month - 3 : month + 9)
        let dayOfYear = (153 * shiftedMonth + 2) / 5 + Int64(day) - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    private static func civilFromDays(_ days: Int64) -> (year: Int, month: Int, day: Int) {
        let z = days + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let dayOfEra = z - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let monthPart = (5 * dayOfYear + 2) / 153
        let day = Int(dayOfYear - (153 * monthPart + 2) / 5 + 1)
        let month = Int(monthPart < 10 ? monthPart + 3 : monthPart - 9)
        let year = Int(yearOfEra + era * 400) + (month <= 2 ? 1 : 0)
        return (year, month, day)
    }

    private static func daysInMonth(year: Int, month: Int) -> Int {
        switch month {
        case 2: return (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }

    private static func floorDivide(_ value: Int64, _ divisor: Int64) -> Int64 {
        let quotient = value / divisor
        return (value % divisor != 0 && (value < 0) != (divisor < 0)) ? quotient - 1 : quotient
    }

    private static func pad(_ value: Int, _ width: Int) -> String {
        let text = String(value)
        return String(repeating: "0", count: max(0, width - text.count)) + text
    }
}
