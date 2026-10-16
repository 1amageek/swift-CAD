import CADCore
import CADGeometry

public struct TorusPrimitive: Hashable, Sendable {
    public let placement: PrimitivePlacement
    public let majorRadius: CADExpression
    public let minorRadius: CADExpression

    public init(
        placement: PrimitivePlacement = .identity,
        majorRadius: CADExpression,
        minorRadius: CADExpression
    ) {
        self.placement = placement
        self.majorRadius = majorRadius
        self.minorRadius = minorRadius
    }

    public func validate(tolerance: ModelingTolerance) throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try validate(tolerance: tolerance, using: &execution)
    }

    public func validate(tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        try placement.validate(tolerance: tolerance, using: &execution)
        try majorRadius.validateDocumentLiteralQuantities(using: &execution)
        try minorRadius.validateDocumentLiteralQuantities(using: &execution)
    }

#if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey {
        case placement
        case majorRadius
        case minorRadius
    }
#endif

#if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys(
            [.placement, .majorRadius, .minorRadius],
            in: decoder
        )
        placement = try container.decode(PrimitivePlacement.self, forKey: .placement)
        majorRadius = try container.decode(CADExpression.self, forKey: .majorRadius)
        minorRadius = try container.decode(CADExpression.self, forKey: .minorRadius)
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
    }
#endif

#if !hasFeature(Embedded)
    public func encode(to encoder: Encoder) throws {
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(placement, forKey: .placement)
        try container.encode(majorRadius, forKey: .majorRadius)
        try container.encode(minorRadius, forKey: .minorRadius)
    }
#endif
}

#if !hasFeature(Embedded)
extension TorusPrimitive: Codable {}
#endif
