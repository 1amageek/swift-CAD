import CADCore

public struct TorusPrimitive: Codable, Hashable, Sendable {
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
        try placement.validate(tolerance: tolerance)
        try majorRadius.validateLiteralQuantities()
        try minorRadius.validateLiteralQuantities()
    }

    private enum CodingKeys: String, CodingKey {
        case placement
        case majorRadius
        case minorRadius
    }

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

    public func encode(to encoder: Encoder) throws {
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(placement, forKey: .placement)
        try container.encode(majorRadius, forKey: .majorRadius)
        try container.encode(minorRadius, forKey: .minorRadius)
    }
}
