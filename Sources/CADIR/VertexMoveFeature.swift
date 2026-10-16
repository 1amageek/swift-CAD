import CADCore
import CADGeometry

public struct VertexMoveFeature: Hashable, Sendable {
    public let target: VertexMoveTargetReference
    public let vertex: StableSubshapeReference
    public let translation: DirectMoveVector

    public init(
        target: VertexMoveTargetReference,
        vertex: StableSubshapeReference,
        translation: DirectMoveVector
    ) {
        self.target = target
        self.vertex = vertex
        self.translation = translation
    }

    public func validate(tolerance: ModelingTolerance) throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try validate(tolerance: tolerance, using: &execution)
    }

    public func validate(tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        try target.validate()
        try vertex.validate(using: &execution)
        try translation.validate(tolerance: tolerance, using: &execution)
        try execution.checkpoint()
    }

#if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey {
        case target
        case vertex
        case translation
    }
#endif

#if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.target, .vertex, .translation], in: decoder)
        target = try container.decode(VertexMoveTargetReference.self, forKey: .target)
        vertex = try container.decode(StableSubshapeReference.self, forKey: .vertex)
        translation = try container.decode(DirectMoveVector.self, forKey: .translation)
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
    }
#endif

#if !hasFeature(Embedded)
    public func encode(to encoder: Encoder) throws {
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(target, forKey: .target)
        try container.encode(vertex, forKey: .vertex)
        try container.encode(translation, forKey: .translation)
    }
#endif
}

#if !hasFeature(Embedded)
extension VertexMoveFeature: Codable {}
#endif
