import CADIR

/// One exact continuity condition imposed on a bridge-curve endpoint, with the three tensions
/// the official Bridge Curve names: the first scales the end speed (and so moves control points
/// one to three), the second moves control point two (and three) along the tangent, the third
/// moves control point three along the tangent. Each keeps the continuity it acts within.
public struct CurveBridgeEndpointConstraint: Codable, Sendable, Hashable {
    public var target: CurveContinuityTarget
    public var requiredLevel: CurveContinuityLevel
    /// |B′| at this end; nil takes the chord length.
    public var derivativeMagnitude: Double?
    public var secondTension: Double
    public var thirdTension: Double

    public init(
        target: CurveContinuityTarget,
        requiredLevel: CurveContinuityLevel,
        derivativeMagnitude: Double? = nil,
        secondTension: Double = 1,
        thirdTension: Double = 1
    ) {
        self.target = target
        self.requiredLevel = requiredLevel
        self.derivativeMagnitude = derivativeMagnitude
        self.secondTension = secondTension
        self.thirdTension = thirdTension
    }

    private enum CodingKeys: String, CodingKey {
        case target, requiredLevel, derivativeMagnitude, secondTension, thirdTension
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        target = try container.decode(CurveContinuityTarget.self, forKey: .target)
        requiredLevel = try container.decode(CurveContinuityLevel.self, forKey: .requiredLevel)
        derivativeMagnitude = try container.decodeIfPresent(Double.self, forKey: .derivativeMagnitude)
        // Requests written before the second and third tensions existed took both as 1.
        secondTension = try container.decodeIfPresent(Double.self, forKey: .secondTension) ?? 1
        thirdTension = try container.decodeIfPresent(Double.self, forKey: .thirdTension) ?? 1
    }
}
