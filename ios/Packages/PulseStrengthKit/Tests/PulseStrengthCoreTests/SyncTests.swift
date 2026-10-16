import Foundation
import XCTest
@testable import PulseStrengthCore

/// Runs `body` on the main actor. XCTest on Linux cannot run main-actor isolated test methods, so the tests call this instead.
func svcMain<T>(_ body: @MainActor () throws -> T) rethrows -> T {
    try MainActor.assumeIsolated(body)
}

/// Deterministic pseudo random numbers (64-bit LCG) for the service tests.
struct SvcLCG {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state >> 24
    }

    /// A value in `0..<count`.
    mutating func int(_ count: Int) -> Int {
        Int(next() % UInt64(max(1, count)))
    }

    /// A value in `range` (inclusive).
    mutating func int(in range: ClosedRange<Int>) -> Int {
        range.lowerBound + int(range.upperBound - range.lowerBound + 1)
    }
}

/// Fixtures shared by the sync tests.
enum SvcSyncFix {
    /// 2026-10-13T19:30:00Z.
    static let epoch = Date(timeIntervalSince1970: 1_791_919_800)

    static func at(_ offset: TimeInterval) -> Date { epoch.addingTimeInterval(offset) }

    static func uuid(_ n: Int) -> UUID {
        var hex = String(n, radix: 16, uppercase: true)
        hex = String(repeating: "0", count: 12 - hex.count) + hex
        return UUID(uuidString: "0000FEED-0000-4000-8000-" + hex)!
    }

    /// A workout started from "Upper A · Push" with some progress, a rest, an undo entry and heart-rate data.
    static func richState() -> WorkoutState {
        var state = WorkoutFactory.makeWorkout(from: SampleData.templates()[0], now: epoch, id: uuid(1))
        var now = epoch.addingTimeInterval(60)
        for _ in 0..<3 {
            WorkoutReducer.reduce(&state, .logNextSet, now: now)
            now = now.addingTimeInterval(90)
        }
        WorkoutReducer.reduce(&state, .toggleLastSetRIR(2), now: now)
        WorkoutReducer.reduce(&state, .updateHeartRate(131), now: now)
        WorkoutReducer.reduce(&state, .setNote(exerciseID: state.exercises[1].id, note: "Slow tempo — \"quotes\" and ünïcode"), now: now)
        WorkoutReducer.reduce(&state, .removeExercise(exerciseID: state.exercises[5].id), now: now)
        WorkoutReducer.reduce(&state, .pause, now: now)
        return state
    }

    static func allMessages() -> [SyncMessage] {
        let state = richState()
        let target = state.exercises[0]
        return [
            .state(SyncEnvelope(state: state, endedWorkoutID: nil, sentAt: at(5))),
            .state(SyncEnvelope(state: nil, endedWorkoutID: uuid(9), sentAt: at(6))),
            .state(SyncEnvelope(state: state, endedWorkoutID: nil, sentAt: at(5.5), ackedCommandIDs: [uuid(2), uuid(3), uuid(4)])),
            .state(SyncEnvelope(state: nil, endedWorkoutID: uuid(9), sentAt: at(6.5), ackedCommandIDs: [uuid(4)])),
            .command(RemoteCommand(id: uuid(2), action: .logSet(exerciseID: target.id, setID: target.sets[3].id), origin: .watch, issuedAt: at(7))),
            .command(RemoteCommand(id: uuid(3), action: .nudgeNextSet(weightSteps: -1, repsSteps: 2), origin: .liveActivity, issuedAt: at(8))),
            .command(RemoteCommand(id: uuid(4), action: .skipRest, origin: .watch, issuedAt: at(8.5), workoutID: state.id)),
            .heartRate(HeartRateSample(bpm: 142, at: at(9.5))),
            .watchSession(isRecording: true),
            .watchSession(isRecording: false),
            .requestState,
        ]
    }

    static func allActions() -> [WorkoutAction] {
        let exerciseID = uuid(20)
        let setID = uuid(21)
        let bench = ExerciseLibrary.exercise(id: "bench")!
        return [
            .toggleSet(exerciseID: exerciseID, setID: setID), .logSet(exerciseID: exerciseID, setID: setID), .logNextSet,
            .setWeight(exerciseID: exerciseID, setID: setID, kg: 82.5), .setReps(exerciseID: exerciseID, setID: setID, reps: 6),
            .nudgeNextSet(weightSteps: 1, repsSteps: -1), .setSetType(exerciseID: exerciseID, setID: setID, type: .failure),
            .setRIR(exerciseID: exerciseID, setID: setID, rir: 3), .setRIR(exerciseID: exerciseID, setID: setID, rir: nil),
            .toggleLastSetRIR(4), .addSet(exerciseID: exerciseID), .deleteSet(exerciseID: exerciseID, setID: setID),
            .setNote(exerciseID: exerciseID, note: "felt strong"), .goTo(index: 2), .nextExercise, .previousExercise,
            .addExercises([bench]), .removeExercise(exerciseID: exerciseID), .moveExercise(from: 0, to: 2),
            .moveExerciseBy(exerciseID: exerciseID, delta: -1), .replaceExercise(exerciseID: exerciseID, with: bench),
            .toggleSuperset(exerciseID: exerciseID), .setRest(exerciseID: exerciseID, seconds: 90), .adjustRest(seconds: -15),
            .skipRest, .setAutoStartRest(false), .setAlertWhenRestEnds(true), .pause, .resume, .undo,
            .updateHeartRate(120), .updateHeartRate(nil), .setUsedWatch(true), .rename("Leg day"), .setWeightUnit(.lb), .setWeightUnit(.kg),
        ]
    }
}

final class SyncCodecTests: XCTestCase {
    func testEncodeProducesOneJSONDataEntryUnderKeyM() throws {
        for message in SvcSyncFix.allMessages() {
            let payload = try SyncCodec.encode(message)
            XCTAssertEqual(Array(payload.keys), ["m"])
            let data = try XCTUnwrap(payload["m"] as? Data)
            XCTAssertNoThrow(try JSONSerialization.jsonObject(with: data))
        }
    }

    func testRoundTripOfEveryMessageKind() throws {
        for message in SvcSyncFix.allMessages() {
            let decoded = try SyncCodec.decode(try SyncCodec.encode(message))
            XCTAssertEqual(decoded, message)
        }
    }

    func testRoundTripOfEveryActionInsideACommand() throws {
        for (index, action) in SvcSyncFix.allActions().enumerated() {
            let command = RemoteCommand(id: SvcSyncFix.uuid(100 + index), action: action, origin: .watch, issuedAt: SvcSyncFix.at(Double(index)))
            let decoded = try SyncCodec.decode(try SyncCodec.encode(.command(command)))
            XCTAssertEqual(decoded, .command(command), "action \(action)")
        }
    }

    func testEveryActionOriginSurvives() throws {
        for origin in [ActionOrigin.phone, .watch, .liveActivity, .system] {
            let command = RemoteCommand(id: SvcSyncFix.uuid(7), action: .skipRest, origin: origin, issuedAt: SvcSyncFix.epoch)
            XCTAssertEqual(try SyncCodec.decode(try SyncCodec.encode(.command(command))), .command(command))
        }
    }

    // MARK: Acknowledgements (sync protocol, ARCHITECTURE 3.4)

    /// Encodes `message`, lets `edit` change the JSON object inside `.state` / `.command`, and decodes it again.
    private func decodeEdited(_ message: SyncMessage, payloadKey: String, _ edit: (inout [String: Any]) -> Void) throws -> SyncMessage {
        let data = try XCTUnwrap(try SyncCodec.encode(message)["m"] as? Data)
        var root = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        var wrapper = try XCTUnwrap(root[payloadKey] as? [String: Any])
        var body = try XCTUnwrap(wrapper["_0"] as? [String: Any])
        edit(&body)
        wrapper["_0"] = body
        root[payloadKey] = wrapper
        return try SyncCodec.decode(["m": try JSONSerialization.data(withJSONObject: root)])
    }

    func testAcknowledgementsKeepTheirOrderAndSurviveTheRoundTrip() throws {
        let ids = (10..<20).map { SvcSyncFix.uuid($0) }
        let envelope = SyncEnvelope(state: SvcSyncFix.richState(), sentAt: SvcSyncFix.epoch, ackedCommandIDs: ids)
        guard case let .state(decoded) = try SyncCodec.decode(try SyncCodec.encode(.state(envelope))) else { return XCTFail("not a state message") }
        XCTAssertEqual(decoded.ackedCommandIDs, ids)
        XCTAssertEqual(decoded, envelope)
        let empty = SyncEnvelope(state: nil, endedWorkoutID: SvcSyncFix.uuid(9), sentAt: SvcSyncFix.epoch)
        XCTAssertEqual(empty.ackedCommandIDs, [], "the default is no acknowledgements")
        XCTAssertEqual(try SyncCodec.decode(try SyncCodec.encode(.state(empty))), .state(empty))
    }

    func testAnEnvelopeWrittenBeforeAcknowledgementsExistedStillDecodes() throws {
        let envelope = SyncEnvelope(state: SvcSyncFix.richState(), endedWorkoutID: nil, sentAt: SvcSyncFix.at(3), ackedCommandIDs: [SvcSyncFix.uuid(5)])
        let message = try decodeEdited(.state(envelope), payloadKey: "state") { body in
            XCTAssertNotNil(body["ackedCommandIDs"])
            body.removeValue(forKey: "ackedCommandIDs")
        }
        guard case let .state(old) = message else { return XCTFail("not a state message") }
        XCTAssertEqual(old.ackedCommandIDs, [])
        XCTAssertEqual(old.state, envelope.state)
        XCTAssertEqual(old.sentAt, envelope.sentAt)

        let ended = SyncEnvelope(state: nil, endedWorkoutID: SvcSyncFix.uuid(9), sentAt: SvcSyncFix.at(4), ackedCommandIDs: [SvcSyncFix.uuid(6)])
        guard case let .state(oldEnd) = try decodeEdited(.state(ended), payloadKey: "state", { $0.removeValue(forKey: "ackedCommandIDs") }) else {
            return XCTFail("not a state message")
        }
        XCTAssertEqual(oldEnd, SyncEnvelope(state: nil, endedWorkoutID: SvcSyncFix.uuid(9), sentAt: SvcSyncFix.at(4)))
    }

    func testAMalformedAcknowledgementListIsRejected() throws {
        let envelope = SyncEnvelope(state: nil, sentAt: SvcSyncFix.epoch, ackedCommandIDs: [SvcSyncFix.uuid(5)])
        for garbage: Any in ["text", 5, ["not a uuid"], [1, 2]] {
            let data = try XCTUnwrap(try SyncCodec.encode(.state(envelope))["m"] as? Data)
            var root = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            var wrapper = try XCTUnwrap(root["state"] as? [String: Any])
            var body = try XCTUnwrap(wrapper["_0"] as? [String: Any])
            body["ackedCommandIDs"] = garbage
            wrapper["_0"] = body
            root["state"] = wrapper
            let payload = ["m": try JSONSerialization.data(withJSONObject: root)]
            XCTAssertThrowsError(try SyncCodec.decode(payload), "\(garbage)") { error in
                guard case .undecodablePayload = error as? SyncCodecError else { return XCTFail("unexpected error \(error)") }
            }
        }
    }

    func testACommandCarriesItsWorkoutAndAnOldOneWithoutDecodesToNil() throws {
        let named = RemoteCommand(id: SvcSyncFix.uuid(7), action: .skipRest, origin: .watch, issuedAt: SvcSyncFix.at(2), workoutID: SvcSyncFix.uuid(1))
        XCTAssertEqual(try SyncCodec.decode(try SyncCodec.encode(.command(named))), .command(named))
        guard case let .command(old) = try decodeEdited(.command(named), payloadKey: "command", { body in
            XCTAssertEqual(body["workoutID"] as? String, SvcSyncFix.uuid(1).uuidString)
            body.removeValue(forKey: "workoutID")
        }) else { return XCTFail("not a command") }
        XCTAssertNil(old.workoutID)
        XCTAssertEqual(old.id, named.id)
        XCTAssertEqual(old.action, named.action)
        XCTAssertEqual(old.issuedAt, named.issuedAt)
        XCTAssertNil(RemoteCommand(action: .skipRest, origin: .watch).workoutID, "the initializer's default")
    }

    func testDatesAreWrittenAsISO8601Text() throws {
        let envelope = SyncEnvelope(state: nil, endedWorkoutID: nil, sentAt: SvcSyncFix.epoch.addingTimeInterval(0.25))
        let data = try XCTUnwrap(try SyncCodec.encode(.state(envelope))["m"] as? Data)
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(text.contains("\"2026-10-13T19:30:00.250Z\""), text)
    }

    func testEncodingIsDeterministic() throws {
        let message = SyncMessage.state(SyncEnvelope(state: SvcSyncFix.richState(), endedWorkoutID: nil, sentAt: SvcSyncFix.epoch))
        let first = try XCTUnwrap(try SyncCodec.encode(message)["m"] as? Data)
        let second = try XCTUnwrap(try SyncCodec.encode(message)["m"] as? Data)
        XCTAssertEqual(first, second)
    }

    func testDecodeThrowsWhenThePayloadIsMissing() {
        XCTAssertThrowsError(try SyncCodec.decode([:])) { error in
            XCTAssertEqual(error as? SyncCodecError, .missingPayload)
        }
        XCTAssertThrowsError(try SyncCodec.decode(["other": Data()])) { error in
            XCTAssertEqual(error as? SyncCodecError, .missingPayload)
        }
    }

    func testDecodeThrowsWhenThePayloadIsNotData() {
        for value: Any in ["text", 42, [1, 2, 3], ["m": "nested"], NSNull()] {
            XCTAssertThrowsError(try SyncCodec.decode(["m": value])) { error in
                XCTAssertEqual(error as? SyncCodecError, .missingPayload)
            }
        }
    }

    func testDecodeThrowsOnGarbledData() throws {
        let garbled: [Data] = [
            Data(),
            Data("not json".utf8),
            Data("{}".utf8),
            Data("[1,2,3]".utf8),
            Data("{\"requestState\":5}".utf8),
            Data(repeating: 0xFF, count: 64),
        ]
        for data in garbled {
            XCTAssertThrowsError(try SyncCodec.decode(["m": data])) { error in
                guard case .undecodablePayload = error as? SyncCodecError else {
                    return XCTFail("unexpected error \(error)")
                }
            }
        }
        // A truncated valid payload fails too.
        let valid = try XCTUnwrap(try SyncCodec.encode(.state(SyncEnvelope(state: SvcSyncFix.richState(), sentAt: SvcSyncFix.epoch)))["m"] as? Data)
        XCTAssertThrowsError(try SyncCodec.decode(["m": valid.prefix(valid.count / 2)]))
    }

    func testDecodeIgnoresExtraDictionaryEntries() throws {
        var payload = try SyncCodec.encode(.requestState)
        payload["extra"] = "ignored"
        XCTAssertEqual(try SyncCodec.decode(payload), .requestState)
    }

    func testDecodeAcceptsDatesWithoutFractionAndWithAnOffset() throws {
        let json = "{\"heartRate\":{\"_0\":{\"at\":\"2026-10-13T21:30:00+02:00\",\"bpm\":99}}}"
        let message = try SyncCodec.decode(["m": Data(json.utf8)])
        XCTAssertEqual(message, .heartRate(HeartRateSample(bpm: 99, at: SvcSyncFix.epoch)))
    }

    func testStateSurvivesTheRoundTripBitForBit() throws {
        let state = SvcSyncFix.richState()
        guard case let .state(envelope) = try SyncCodec.decode(try SyncCodec.encode(.state(SyncEnvelope(state: state, sentAt: SvcSyncFix.epoch)))) else {
            return XCTFail("not a state message")
        }
        XCTAssertEqual(envelope.state, state)
    }
}

final class ISO8601TextTests: XCTestCase {
    func testKnownInstants() {
        let cases: [(TimeInterval, String)] = [
            (0, "1970-01-01T00:00:00.000Z"),
            (-1, "1969-12-31T23:59:59.000Z"),
            (1_700_000_000, "2023-11-14T22:13:20.000Z"),
            (1_709_208_000, "2024-02-29T12:00:00.000Z"),
            (1_791_919_800, "2026-10-13T19:30:00.000Z"),
            (1_791_919_800.25, "2026-10-13T19:30:00.250Z"),
            (946_684_799.999, "1999-12-31T23:59:59.999Z"),
            (951_782_400, "2000-02-29T00:00:00.000Z"),
            (4_102_444_800, "2100-01-01T00:00:00.000Z"),
            (-62_135_596_800, "0001-01-01T00:00:00.000Z"),
            (253_402_300_799, "9999-12-31T23:59:59.000Z"),
        ]
        for (seconds, expected) in cases {
            XCTAssertEqual(ISO8601Text.string(from: Date(timeIntervalSince1970: seconds)), expected)
            XCTAssertEqual(ISO8601Text.date(from: expected)?.timeIntervalSince1970 ?? .nan, seconds, accuracy: 0.0005, expected)
        }
    }

    func testOutOfRangeAndNonFiniteDates() {
        XCTAssertNil(ISO8601Text.string(from: Date(timeIntervalSince1970: .nan)))
        XCTAssertNil(ISO8601Text.string(from: Date(timeIntervalSince1970: .infinity)))
        XCTAssertEqual(ISO8601Text.string(from: .distantFuture), "4001-01-01T00:00:00.000Z")
        XCTAssertEqual(ISO8601Text.string(from: Date(timeIntervalSince1970: 1e15)), "9999-12-31T23:59:59.999Z")
        XCTAssertEqual(ISO8601Text.string(from: Date(timeIntervalSince1970: -1e15)), "0000-01-01T00:00:00.000Z")
    }

    func testParsingVariants() {
        let expected = 1_791_919_800.0
        let accepted = [
            "2026-10-13T19:30:00Z", "2026-10-13T19:30:00.000Z", "2026-10-13t19:30:00z", "2026-10-13 19:30:00Z",
            "2026-10-13T21:30:00+02:00", "2026-10-13T21:30:00+0200", "2026-10-13T21:30:00+02",
            "2026-10-13T17:00:00-02:30", "2026-10-13T19:30:00.0000000000Z",
        ]
        for text in accepted {
            XCTAssertEqual(ISO8601Text.date(from: text)?.timeIntervalSince1970 ?? .nan, expected, accuracy: 1e-6, text)
        }
        XCTAssertEqual(ISO8601Text.date(from: "2026-10-13T19:30:00.5Z")?.timeIntervalSince1970 ?? .nan, expected + 0.5, accuracy: 1e-9)
        XCTAssertEqual(ISO8601Text.date(from: "2026-10-13T19:30:00,125Z")?.timeIntervalSince1970 ?? .nan, expected + 0.125, accuracy: 1e-9)
    }

    func testRejectedText() {
        let rejected = [
            "", "garbage", "2026-10-13", "2026-10-13T19:30:00", "2026-10-13T19:30Z", "2026-13-01T00:00:00Z", "2026-00-10T00:00:00Z",
            "2026-02-30T00:00:00Z", "2025-02-29T00:00:00Z", "2026-04-31T00:00:00Z", "2026-10-13T24:00:00Z", "2026-10-13T19:60:00Z",
            "2026-10-13T19:30:61Z", "2026-10-13T19:30:00.Z", "2026-10-13T19:30:00Zjunk", "2026-10-13T19:30:00+2", "2026-10-13T19:30:00+25:00",
            "2026-10-13T19:30:00+02:75", "26-10-13T19:30:00Z", "2026/10/13T19:30:00Z", "２０２６-10-13T19:30:00Z",
        ]
        for text in rejected {
            XCTAssertNil(ISO8601Text.date(from: text), text)
        }
        XCTAssertNotNil(ISO8601Text.date(from: "2024-02-29T00:00:00Z"))
        XCTAssertNotNil(ISO8601Text.date(from: "2000-02-29T00:00:00Z"))
        XCTAssertNil(ISO8601Text.date(from: "1900-02-29T00:00:00Z"))
    }

    func testMatchesTheSystemFormatterForWholeSeconds() {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        var random = SvcLCG(seed: 20_261_013)
        for _ in 0..<500 {
            let seconds = TimeInterval(random.int(in: -600_000_000...7_000_000_000))
            let date = Date(timeIntervalSince1970: seconds)
            let reference = formatter.string(from: date)
            XCTAssertEqual(ISO8601Text.string(from: date), String(reference.dropLast()) + ".000Z")
            XCTAssertEqual(formatter.date(from: reference), ISO8601Text.date(from: reference))
        }
    }

    func testRoundTripOfRandomMillisecondDates() {
        var random = SvcLCG(seed: 7)
        for _ in 0..<2000 {
            let milliseconds = random.int(in: -62_000_000_000_000...253_000_000_000_000)
            let date = Date(timeIntervalSince1970: Double(milliseconds) / 1000)
            let text = ISO8601Text.string(from: date)
            XCTAssertNotNil(text)
            let back = text.flatMap { ISO8601Text.date(from: $0) }
            XCTAssertEqual(back?.timeIntervalSince1970 ?? .nan, date.timeIntervalSince1970, accuracy: 0.0006, text ?? "")
        }
    }

    func testDatesBeforeEpochKeepTheirMilliseconds() {
        let date = Date(timeIntervalSince1970: -0.001)
        XCTAssertEqual(ISO8601Text.string(from: date), "1969-12-31T23:59:59.999Z")
        XCTAssertEqual(ISO8601Text.string(from: Date(timeIntervalSince1970: -86_400.5)), "1969-12-30T23:59:59.500Z")
    }

    func testPrecisionOfDatesOnAQuarterSecondGridIsExact() {
        var random = SvcLCG(seed: 99)
        for _ in 0..<500 {
            let date = SvcSyncFix.epoch.addingTimeInterval(Double(random.int(in: -4_000_000...4_000_000)) / 4)
            let text = ISO8601Text.string(from: date) ?? ""
            XCTAssertEqual(ISO8601Text.date(from: text), date, text)
        }
    }
}

final class SeenCommandsTests: XCTestCase {
    func testDuplicatesAreRejected() {
        var seen = SeenCommands()
        let id = SvcSyncFix.uuid(1)
        XCTAssertTrue(seen.insertIfNew(id))
        XCTAssertFalse(seen.insertIfNew(id))
        XCTAssertFalse(seen.insertIfNew(id))
        XCTAssertTrue(seen.insertIfNew(SvcSyncFix.uuid(2)))
    }

    func testTheOldestIdIsForgottenFirst() {
        var seen = SeenCommands(capacity: 3)
        let ids = (1...6).map { SvcSyncFix.uuid($0) }
        for id in ids.prefix(3) { XCTAssertTrue(seen.insertIfNew(id)) }
        XCTAssertTrue(seen.insertIfNew(ids[3]))          // evicts 1
        XCTAssertFalse(seen.insertIfNew(ids[1]))         // 2 still known
        XCTAssertFalse(seen.insertIfNew(ids[2]))
        XCTAssertTrue(seen.insertIfNew(ids[0]))          // 1 was forgotten; evicts 2
        XCTAssertTrue(seen.insertIfNew(ids[1]))          // 2 was forgotten; evicts 3
        XCTAssertFalse(seen.insertIfNew(ids[3]))
        XCTAssertFalse(seen.insertIfNew(ids[0]))
    }

    func testADuplicateDoesNotRefreshItsPosition() {
        var seen = SeenCommands(capacity: 2)
        let a = SvcSyncFix.uuid(1), b = SvcSyncFix.uuid(2), c = SvcSyncFix.uuid(3)
        XCTAssertTrue(seen.insertIfNew(a))
        XCTAssertTrue(seen.insertIfNew(b))
        XCTAssertFalse(seen.insertIfNew(a))
        XCTAssertTrue(seen.insertIfNew(c))                // evicts a (still the oldest)
        XCTAssertTrue(seen.insertIfNew(a))
    }

    func testCapacityIsAtLeastOne() {
        for capacity in [0, -5, 1] {
            var seen = SeenCommands(capacity: capacity)
            let a = SvcSyncFix.uuid(1), b = SvcSyncFix.uuid(2)
            XCTAssertTrue(seen.insertIfNew(a))
            XCTAssertFalse(seen.insertIfNew(a))
            XCTAssertTrue(seen.insertIfNew(b))
            XCTAssertTrue(seen.insertIfNew(a))
        }
    }

    func testDefaultCapacityRemembersTheLast256() {
        var seen = SeenCommands()
        let ids = (0..<300).map { SvcSyncFix.uuid($0) }
        for id in ids { XCTAssertTrue(seen.insertIfNew(id)) }
        for id in ids.suffix(256) { XCTAssertFalse(seen.insertIfNew(id)) }
        XCTAssertTrue(seen.insertIfNew(ids[0]))
    }

    func testBehavesLikeAnOrderedWindowOfDistinctIds() {
        for seed in 1...20 {
            var random = SvcLCG(seed: UInt64(seed))
            let capacity = random.int(in: 1...8)
            var seen = SeenCommands(capacity: capacity)
            var model: [UUID] = []
            for _ in 0..<300 {
                let id = SvcSyncFix.uuid(random.int(in: 1...14))
                let expectedNew = !model.contains(id)
                if expectedNew {
                    model.append(id)
                    if model.count > capacity { model.removeFirst() }
                }
                XCTAssertEqual(seen.insertIfNew(id), expectedNew, "seed \(seed)")
            }
        }
    }
}

final class SyncReconcilerTests: XCTestCase {
    private func state(id: Int, revision: Int) -> WorkoutState {
        WorkoutState(id: SvcSyncFix.uuid(id), name: "W", startedAt: SvcSyncFix.epoch, revision: revision)
    }

    func testNoLocalStateAlwaysLoses() {
        XCTAssertTrue(SyncReconciler.isNewer(state(id: 1, revision: 0), than: nil))
    }

    func testADifferentWorkoutWins() {
        XCTAssertTrue(SyncReconciler.isNewer(state(id: 2, revision: 0), than: state(id: 1, revision: 50)))
    }

    func testHigherRevisionWinsLowerAndEqualDoNot() {
        let local = state(id: 1, revision: 5)
        XCTAssertTrue(SyncReconciler.isNewer(state(id: 1, revision: 6), than: local))
        XCTAssertFalse(SyncReconciler.isNewer(state(id: 1, revision: 5), than: local))
        XCTAssertFalse(SyncReconciler.isNewer(state(id: 1, revision: 4), than: local))
    }

    func testAHeartRateOnlyDifferenceIsNotNewer() {
        var incoming = state(id: 1, revision: 5)
        incoming.heartRate = 150
        XCTAssertFalse(SyncReconciler.isNewer(incoming, than: state(id: 1, revision: 5)))
    }
}
