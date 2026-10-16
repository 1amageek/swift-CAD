import CADCore
import CADGeometry

public struct BoxPrimitive: Hashable, Sendable {
    public let placement: PrimitivePlacement
    public let width: CADExpression
    public let depth: CADExpression
    public let height: CADExpression

    public init(
        placement: PrimitivePlacement = .identity,
        width: CADExpression,
        depth: CADExpression,
        height: CADExpression
    ) {
        self.placement = placement
        self.width = width
        self.depth = depth
        self.height = height
    }

    public func validate(tolerance: ModelingTolerance) throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try validate(tolerance: tolerance, using: &execution)
    }

    public func validate(tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        try placement.validate(tolerance: tolerance, using: &execution)
        try width.validateDocumentLiteralQuantities(using: &execution)
        try depth.validateDocumentLiteralQuantities(using: &execution)
        try height.validateDocumentLiteralQuantities(using: &execution)
    }

#if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey {
        case placement
        case width
        case depth
        case height
    }
#endif

#if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys(
            [.placement, .width, .depth, .height],
            in: decoder
        )
        placement = try container.decode(PrimitivePlacement.self, forKey: .placement)
        width = try container.decode(CADExpression.self, forKey: .width)
        depth = try container.decode(CADExpression.self, forKey: .depth)
        height = try container.decode(CADExpression.self, forKey: .height)
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
    }
#endif

#if !hasFeature(Embedded)
    public func encode(to encoder: Encoder) throws {
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(placement, forKey: .placement)
        try container.encode(width, forKey: .width)
        try container.encode(depth, forKey: .depth)
        try container.encode(height, forKey: .height)
    }
#endif
}

#if !hasFeature(Embedded)
extension BoxPrimitive: Codable {}
#endif
