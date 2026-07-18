import CADIR

/// One exact continuity condition imposed on a bridge-curve endpoint.
public struct CurveBridgeEndpointConstraint: Codable, Sendable, Hashable {
    public var target: CurveContinuityTarget
    public var requiredLevel: CurveContinuityLevel
    public var derivativeMagnitude: Double?

    public init(
        target: CurveContinuityTarget,
        requiredLevel: CurveContinuityLevel,
        derivativeMagnitude: Double? = nil
    ) {
        self.target = target
        self.requiredLevel = requiredLevel
        self.derivativeMagnitude = derivativeMagnitude
    }
}
