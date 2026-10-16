import CADCore
import CADGeometry

public struct ConePrimitive: Hashable, Sendable {
    public let placement: PrimitivePlacement
    public let baseRadius: CADExpression
    public let height: CADExpression

    public init(
        placement: PrimitivePlacement = .identity,
        baseRadius: CADExpression,
        height: CADExpression
    ) {
        self.placement = placement
        self.baseRadius = baseRadius
        self.height = height
    }

    public func validate(tolerance: ModelingTolerance) throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try validate(tolerance: tolerance, using: &execution)
    }

    public func validate(tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        try placement.validate(tolerance: tolerance, using: &execution)
        try baseRadius.validateDocumentLiteralQuantities(using: &execution)
        try height.validateDocumentLiteralQuantities(using: &execution)
    }

#if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey {
        case placement
        case baseRadius
        case height
    }
#endif

#if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.placement, .baseRadius, .height], in: decoder)
        placement = try container.decode(PrimitivePlacement.self, forKey: .placement)
        baseRadius = try container.decode(CADExpression.self, forKey: .baseRadius)
        height = try container.decode(CADExpression.self, forKey: .height)
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
    }
#endif

#if !hasFeature(Embedded)
    public func encode(to encoder: Encoder) throws {
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(placement, forKey: .placement)
        try container.encode(baseRadius, forKey: .baseRadius)
        try container.encode(height, forKey: .height)
    }
#endif
}

#if !hasFeature(Embedded)
extension ConePrimitive: Codable {}
#endif
