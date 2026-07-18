import CADCore

public struct ThickenFeature: Codable, Hashable, Sendable {
    public let target: ThickenTargetReference
    public let thickness: CADExpression
    public let side: ThickenSide

    public init(
        target: ThickenTargetReference,
        thickness: CADExpression,
        side: ThickenSide = .symmetric
    ) {
        self.target = target
        self.thickness = thickness
        self.side = side
    }

    public func validate() throws {
        try target.validate()
        try thickness.validateLiteralQuantities()
    }

    private enum CodingKeys: String, CodingKey {
        case target
        case thickness
        case side
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.target, .thickness, .side], in: decoder)
        target = try container.decode(ThickenTargetReference.self, forKey: .target)
        thickness = try container.decode(CADExpression.self, forKey: .thickness)
        side = try container.decode(ThickenSide.self, forKey: .side)
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(target, forKey: .target)
        try container.encode(thickness, forKey: .thickness)
        try container.encode(side, forKey: .side)
    }
}
