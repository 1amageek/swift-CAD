import CADCore

public struct SurfaceExtensionDistances: Codable, Hashable, Sendable {
    public let lowerU: CADExpression
    public let upperU: CADExpression
    public let lowerV: CADExpression
    public let upperV: CADExpression

    public init(
        lowerU: CADExpression = .constant(.length(0.0, unit: .meter)),
        upperU: CADExpression = .constant(.length(0.0, unit: .meter)),
        lowerV: CADExpression = .constant(.length(0.0, unit: .meter)),
        upperV: CADExpression = .constant(.length(0.0, unit: .meter))
    ) {
        self.lowerU = lowerU
        self.upperU = upperU
        self.lowerV = lowerV
        self.upperV = upperV
    }

    public func validate() throws {
        try lowerU.validateLiteralQuantities()
        try upperU.validateLiteralQuantities()
        try lowerV.validateLiteralQuantities()
        try upperV.validateLiteralQuantities()
    }

    public var referencedParameterIDs: Set<ParameterID> {
        lowerU.referencedParameterIDs
            .union(upperU.referencedParameterIDs)
            .union(lowerV.referencedParameterIDs)
            .union(upperV.referencedParameterIDs)
    }

    private enum CodingKeys: String, CodingKey {
        case lowerU
        case upperU
        case lowerV
        case upperV
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.lowerU, .upperU, .lowerV, .upperV], in: decoder)
        lowerU = try container.decode(CADExpression.self, forKey: .lowerU)
        upperU = try container.decode(CADExpression.self, forKey: .upperU)
        lowerV = try container.decode(CADExpression.self, forKey: .lowerV)
        upperV = try container.decode(CADExpression.self, forKey: .upperV)
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(lowerU, forKey: .lowerU)
        try container.encode(upperU, forKey: .upperU)
        try container.encode(lowerV, forKey: .lowerV)
        try container.encode(upperV, forKey: .upperV)
    }
}
