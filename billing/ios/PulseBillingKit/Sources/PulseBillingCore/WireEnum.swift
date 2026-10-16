import Foundation

/// A string enum that never fails to decode: values the server adds later land in the `unknown` case instead of
/// breaking old app versions. Conformers provide the mapping; Codable comes for free.
public protocol WireEnum: Codable, Equatable, Sendable {
    init(wire: String)
    var wire: String { get }
}

public extension WireEnum {
    init(from decoder: Decoder) throws {
        self.init(wire: try decoder.singleValueContainer().decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wire)
    }
}
