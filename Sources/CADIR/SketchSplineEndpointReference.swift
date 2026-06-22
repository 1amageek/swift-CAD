import CADCore

public struct SketchSplineEndpointReference: Codable, Sendable, Hashable {
    public var splineID: SketchEntityID
    public var endpoint: SketchSplineEndpoint

    public init(splineID: SketchEntityID, endpoint: SketchSplineEndpoint) {
        self.splineID = splineID
        self.endpoint = endpoint
    }
}
