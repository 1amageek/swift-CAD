import Foundation
import CADCore

/// A deterministic feature insertion request shared by builders, agents, and UI clients.
public struct FeatureRequest: Codable, Hashable, Sendable {
    public let id: FeatureID
    public let name: String?
    public let operation: FeatureOperation

    public init(
        id: FeatureID = FeatureID(),
        name: String? = nil,
        operation: FeatureOperation
    ) {
        self.id = id
        self.name = name
        self.operation = operation
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case operation
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.id, .name, .operation], in: decoder)
        id = try container.decode(FeatureID.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        operation = try container.decode(FeatureOperation.self, forKey: .operation)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encode(operation, forKey: .operation)
    }

    public func validate() throws {
        if let name, name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw KernelError(
                phase: .validation,
                code: .invalidInput,
                featureID: id,
                message: "Feature request names must not be empty."
            )
        }
    }
}
