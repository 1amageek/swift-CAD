import CADCore
import CADGeometry

public struct PrimitiveFeature: Hashable, Sendable {
    public let definition: PrimitiveDefinition

    public init(definition: PrimitiveDefinition) {
        self.definition = definition
    }

    public func validate(tolerance: ModelingTolerance) throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try validate(tolerance: tolerance, using: &execution)
    }

    public func validate(tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        try definition.validate(tolerance: tolerance, using: &execution)
        try execution.checkpoint()
    }

#if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey {
        case definition
    }
#endif

#if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.definition], in: decoder)
        definition = try container.decode(PrimitiveDefinition.self, forKey: .definition)
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
    }
#endif

#if !hasFeature(Embedded)
    public func encode(to encoder: Encoder) throws {
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(definition, forKey: .definition)
    }
#endif
}

#if !hasFeature(Embedded)
extension PrimitiveFeature: Codable {}
#endif
