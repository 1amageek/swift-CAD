import CADCore

public struct SketchSplineEndpointReference: Codable, Sendable, Hashable {
    public var splineID: SketchEntityID
    public var endpoint: SketchSplineEndpoint

    public init(splineID: SketchEntityID, endpoint: SketchSplineEndpoint) {
        self.splineID = splineID
        self.endpoint = endpoint
    }

    private enum CodingKeys: String, CodingKey {
        case splineID
        case endpoint
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.splineID, .endpoint], in: decoder)
        splineID = try container.decode(SketchEntityID.self, forKey: .splineID)
        endpoint = try container.decode(SketchSplineEndpoint.self, forKey: .endpoint)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(splineID, forKey: .splineID)
        try container.encode(endpoint, forKey: .endpoint)
    }
}
