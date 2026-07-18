import CADCore

public struct SpherePrimitive: Codable, Hashable, Sendable {
    public let placement: PrimitivePlacement
    public let radius: CADExpression

    public init(
        placement: PrimitivePlacement = .identity,
        radius: CADExpression
    ) {
        self.placement = placement
        self.radius = radius
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try placement.validate(tolerance: tolerance)
        try radius.validateLiteralQuantities()
    }

    private enum CodingKeys: String, CodingKey {
        case placement
        case radius
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.placement, .radius], in: decoder)
        placement = try container.decode(PrimitivePlacement.self, forKey: .placement)
        radius = try container.decode(CADExpression.self, forKey: .radius)
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
    }

    public func encode(to encoder: Encoder) throws {
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(placement, forKey: .placement)
        try container.encode(radius, forKey: .radius)
    }
}
