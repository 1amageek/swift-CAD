import CADIR

/// The complete endpoint and tolerance contract for an exact bridge curve.
public struct CurveBridgeRequest: Codable, Sendable, Hashable {
    public var start: CurveBridgeEndpointConstraint
    public var end: CurveBridgeEndpointConstraint
    public var continuityTolerances: CurveContinuityTolerances

    public init(
        start: CurveBridgeEndpointConstraint,
        end: CurveBridgeEndpointConstraint,
        continuityTolerances: CurveContinuityTolerances
    ) {
        self.start = start
        self.end = end
        self.continuityTolerances = continuityTolerances
    }
}
