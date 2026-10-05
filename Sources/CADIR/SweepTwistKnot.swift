import CADCore

/// An absolute angle at a normalized position on the applied Sweep path.
public struct SweepTwistKnot: Hashable, Sendable {
    public var position: Double
    public var angle: CADExpression

    public init(position: Double, angle: CADExpression) {
        self.position = position
        self.angle = angle
    }

#if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey { case position, angle }
#endif

#if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.position, .angle], in: decoder)
        position = try container.decode(Double.self, forKey: .position)
        angle = try container.decode(CADExpression.self, forKey: .angle)
    }
#endif
}

#if !hasFeature(Embedded)
extension SweepTwistKnot: Codable {}
#endif
