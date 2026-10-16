import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The one place the kit touches the network. Tests substitute it.
public protocol BillingTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: BillingTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        // dataTask + continuation rather than `session.data(for:)`: the latter is not available in swift-corelibs-foundation on every toolchain.
        try await withCheckedThrowingContinuation { continuation in
            let task = session.dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data, let http = response as? HTTPURLResponse {
                    continuation.resume(returning: (data, http))
                } else {
                    continuation.resume(throwing: BillingError.invalidResponse("no HTTP response"))
                }
            }
            task.resume()
        }
    }
}
