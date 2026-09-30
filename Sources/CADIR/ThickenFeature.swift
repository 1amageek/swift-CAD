import CADCore

/// Thicken: a sheet grown into a solid, `front` along its normal and `back` against it; either may
/// be zero, not both.
public struct ThickenFeature: Codable, Hashable, Sendable {
    public let target: ThickenTargetReference
    public let front: CADExpression
    public let back: CADExpression

    public init(
        target: ThickenTargetReference,
        front: CADExpression,
        back: CADExpression
    ) {
        self.target = target
        self.front = front
        self.back = back
    }

    public func validate() throws {
        try target.validate()
        try front.validateLiteralQuantities()
        try back.validateLiteralQuantities()
    }

    private enum CodingKeys: String, CodingKey {
        case target
        case front
        case back
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.target, .front, .back], in: decoder)
        target = try container.decode(ThickenTargetReference.self, forKey: .target)
        front = try container.decode(CADExpression.self, forKey: .front)
        back = try container.decode(CADExpression.self, forKey: .back)
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(target, forKey: .target)
        try container.encode(front, forKey: .front)
        try container.encode(back, forKey: .back)
    }
}
