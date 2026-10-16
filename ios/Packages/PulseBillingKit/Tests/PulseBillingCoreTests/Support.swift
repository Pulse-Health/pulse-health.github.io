import Foundation
import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import PulseBillingCore

/// The contract fixtures shared with the server and the Android client: billing/contract/fixtures at the repository root.
enum Fixtures {
    static var directory: URL {
        // .../ios/Packages/PulseBillingKit/Tests/PulseBillingCoreTests/Support.swift -> repository root is five levels up.
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { url.deleteLastPathComponent() }
        return url.appendingPathComponent("billing/contract/fixtures", isDirectory: true)
    }

    static var isAvailable: Bool { FileManager.default.fileExists(atPath: directory.path) }

    static func names() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasSuffix(".json") }.sorted()
    }

    static func data(_ name: String) throws -> Data {
        try Data(contentsOf: directory.appendingPathComponent(name))
    }

    static func decode<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
        try BillingJSON.makeDecoder().decode(type, from: data(name))
    }
}

/// A scripted transport: answers from a queue per "METHOD path" and records every request.
final class MockTransport: BillingTransport, @unchecked Sendable {
    struct Reply {
        var status: Int
        var body: Data
        init(_ status: Int = 200, json: String = "{}") { self.status = status; self.body = Data(json.utf8) }
        init(_ status: Int = 200, fixture: String) throws { self.status = status; self.body = try Fixtures.data(fixture) }
    }

    private let lock = NSLock()
    private var queues: [String: [Result<Reply, Error>]] = [:]
    private(set) var requests: [URLRequest] = []

    func enqueue(_ key: String, _ reply: Reply) { lock.withLock { queues[key, default: []].append(.success(reply)) } }
    func enqueue(_ key: String, error: Error) { lock.withLock { queues[key, default: []].append(.failure(error)) } }

    private func next(for request: URLRequest, key: String) throws -> Reply {
        try lock.withLock {
            requests.append(request)
            guard var queue = queues[key], !queue.isEmpty else {
                throw BillingError.network("MockTransport has no reply queued for \(key)")
            }
            let next = queue.removeFirst()
            queues[key] = queue
            return try next.get()
        }
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let key = "\(request.httpMethod ?? "GET") \(request.url?.path ?? "")"
        let reply = try next(for: request, key: key)
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        return (reply.body, response)
    }
}

final class CountingTokens: SessionTokenProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    var failing = false

    var count: Int { lock.withLock { calls } }

    private func bump() -> Int { lock.withLock { calls += 1; return calls } }

    func sessionToken() async throws -> String {
        let n = bump()
        if failing { throw BillingError.network("no clerk session") }
        return "token-\(n)"
    }
}

func XCTAssertThrowsBillingError(_ expression: @autoclosure () async throws -> some Any, _ expected: BillingError, file: StaticString = #filePath, line: UInt = #line) async {
    do {
        _ = try await expression()
        XCTFail("expected \(expected) but nothing was thrown", file: file, line: line)
    } catch {
        XCTAssertEqual(error as? BillingError, expected, file: file, line: line)
    }
}
