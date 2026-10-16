import CADCore
import CADGeometry

public struct EdgeMoveFeature: Hashable, Sendable {
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
        var execution = try OriginalQueryExecution.independentGeometry()
        try validate(tolerance: tolerance, using: &execution)
    }

    public func validate(tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        try target.validate()
        try edge.validate(using: &execution)
        try translation.validate(tolerance: tolerance, using: &execution)

        try execution.checkpoint()
    }

#if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey {
        case target
        case edge
        case translation
    }
#endif

#if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.target, .edge, .translation], in: decoder)
        target = try container.decode(EdgeMoveTargetReference.self, forKey: .target)
        edge = try container.decode(StableSubshapeReference.self, forKey: .edge)
        translation = try container.decode(DirectMoveVector.self, forKey: .translation)
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
    }
#endif

#if !hasFeature(Embedded)
    public func encode(to encoder: Encoder) throws {
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(target, forKey: .target)
        try container.encode(edge, forKey: .edge)
        try container.encode(translation, forKey: .translation)
    }
#endif
}

#if !hasFeature(Embedded)
extension EdgeMoveFeature: Codable {}
#endif
