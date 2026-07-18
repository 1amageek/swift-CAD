import CADCore

public struct ConePrimitive: Codable, Hashable, Sendable {
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
        try placement.validate(tolerance: tolerance)
        try baseRadius.validateLiteralQuantities()
        try height.validateLiteralQuantities()
    }

    private enum CodingKeys: String, CodingKey {
        case placement
        case baseRadius
        case height
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.placement, .baseRadius, .height], in: decoder)
        placement = try container.decode(PrimitivePlacement.self, forKey: .placement)
        baseRadius = try container.decode(CADExpression.self, forKey: .baseRadius)
        height = try container.decode(CADExpression.self, forKey: .height)
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
    }

    public func encode(to encoder: Encoder) throws {
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(placement, forKey: .placement)
        try container.encode(baseRadius, forKey: .baseRadius)
        try container.encode(height, forKey: .height)
    }
}
