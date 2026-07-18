import CADCore

public struct PrimitiveFeature: Codable, Hashable, Sendable {
    public let definition: PrimitiveDefinition

    public init(definition: PrimitiveDefinition) {
        self.definition = definition
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try definition.validate(tolerance: tolerance)
    }

    private enum CodingKeys: String, CodingKey {
        case definition
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.definition], in: decoder)
        definition = try container.decode(PrimitiveDefinition.self, forKey: .definition)
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
    }

    public func encode(to encoder: Encoder) throws {
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(definition, forKey: .definition)
    }
}
