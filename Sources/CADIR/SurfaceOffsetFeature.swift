import CADCore

public struct SurfaceOffsetFeature: Codable, Hashable, Sendable {
    public let target: SurfaceOperationTargetReference
    public let distance: CADExpression

    public init(
        target: SurfaceOperationTargetReference,
        distance: CADExpression
    ) {
        self.target = target
        self.distance = distance
    }

    public func validate() throws {
        try target.validate()
        try distance.validateLiteralQuantities()
    }

    private enum CodingKeys: String, CodingKey {
        case target
        case distance
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.target, .distance], in: decoder)
        target = try container.decode(SurfaceOperationTargetReference.self, forKey: .target)
        distance = try container.decode(CADExpression.self, forKey: .distance)
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(target, forKey: .target)
        try container.encode(distance, forKey: .distance)
    }
}
