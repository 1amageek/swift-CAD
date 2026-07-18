import CADCore

public struct BoxPrimitive: Codable, Hashable, Sendable {
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
        try placement.validate(tolerance: tolerance)
        try width.validateLiteralQuantities()
        try depth.validateLiteralQuantities()
        try height.validateLiteralQuantities()
    }

    private enum CodingKeys: String, CodingKey {
        case placement
        case width
        case depth
        case height
    }

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

    public func encode(to encoder: Encoder) throws {
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(placement, forKey: .placement)
        try container.encode(width, forKey: .width)
        try container.encode(depth, forKey: .depth)
        try container.encode(height, forKey: .height)
    }
}
