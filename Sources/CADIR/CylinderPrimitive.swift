import CADCore
import CADGeometry

public struct CylinderPrimitive: Hashable, Sendable {
    public let placement: PrimitivePlacement
    public let radius: CADExpression
    public let height: CADExpression

    public init(
        placement: PrimitivePlacement = .identity,
        radius: CADExpression,
        height: CADExpression
    ) {
        self.placement = placement
        self.radius = radius
        self.height = height
    }

    public func validate(tolerance: ModelingTolerance) throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try validate(tolerance: tolerance, using: &execution)
    }

    public func validate(tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        try placement.validate(tolerance: tolerance, using: &execution)
        try radius.validateDocumentLiteralQuantities(using: &execution)
        try height.validateDocumentLiteralQuantities(using: &execution)
    }

#if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey {
        case placement
        case radius
        case height
    }
#endif

#if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.placement, .radius, .height], in: decoder)
        placement = try container.decode(PrimitivePlacement.self, forKey: .placement)
        radius = try container.decode(CADExpression.self, forKey: .radius)
        height = try container.decode(CADExpression.self, forKey: .height)
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
    }
#endif

#if !hasFeature(Embedded)
    public func encode(to encoder: Encoder) throws {
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(placement, forKey: .placement)
        try container.encode(radius, forKey: .radius)
        try container.encode(height, forKey: .height)
    }
#endif
}

#if !hasFeature(Embedded)
extension CylinderPrimitive: Codable {}
#endif
