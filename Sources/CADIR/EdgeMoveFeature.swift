import CADCore

public struct EdgeMoveFeature: Codable, Hashable, Sendable {
    public let target: EdgeMoveTargetReference
    public let edge: StableSubshapeReference
    public let translation: DirectMoveVector

    public init(
        target: EdgeMoveTargetReference,
        edge: StableSubshapeReference,
        translation: DirectMoveVector
    ) {
        self.target = target
        self.edge = edge
        self.translation = translation
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try target.validate()
        try edge.validate()
        try translation.validate(tolerance: tolerance)
    }

    private enum CodingKeys: String, CodingKey {
        case target
        case edge
        case translation
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.target, .edge, .translation], in: decoder)
        target = try container.decode(EdgeMoveTargetReference.self, forKey: .target)
        edge = try container.decode(StableSubshapeReference.self, forKey: .edge)
        translation = try container.decode(DirectMoveVector.self, forKey: .translation)
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
    }

    public func encode(to encoder: Encoder) throws {
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(target, forKey: .target)
        try container.encode(edge, forKey: .edge)
        try container.encode(translation, forKey: .translation)
    }
}
