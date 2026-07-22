import CADCore

public enum SketchTangentOrientation: String, Codable, CaseIterable, Hashable, Sendable {
    case aligned
    case opposed
}

public struct SketchSplineLineTangencyConstraint: Codable, Hashable, Sendable {
    public var splineEndpoint: SketchSplineEndpointReference
    public var line: SketchEntityID
    public var orientation: SketchTangentOrientation

    public init(
        splineEndpoint: SketchSplineEndpointReference,
        line: SketchEntityID,
        orientation: SketchTangentOrientation
    ) {
        self.splineEndpoint = splineEndpoint
        self.line = line
        self.orientation = orientation
    }

    public func validate() throws {
        guard splineEndpoint.splineID != line else {
            throw SketchError.invalidReference(
                "Spline-line tangency requires distinct spline and line entities."
            )
        }
    }

    private enum CodingKeys: String, CodingKey {
        case splineEndpoint
        case line
        case orientation
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys(
            [.splineEndpoint, .line, .orientation],
            in: decoder
        )
        splineEndpoint = try container.decode(
            SketchSplineEndpointReference.self,
            forKey: .splineEndpoint
        )
        line = try container.decode(SketchEntityID.self, forKey: .line)
        orientation = try container.decode(SketchTangentOrientation.self, forKey: .orientation)
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(splineEndpoint, forKey: .splineEndpoint)
        try container.encode(line, forKey: .line)
        try container.encode(orientation, forKey: .orientation)
    }
}

public struct SketchSplineEndpointTangencyConstraint: Codable, Hashable, Sendable {
    public var first: SketchSplineEndpointReference
    public var second: SketchSplineEndpointReference
    public var orientation: SketchTangentOrientation

    public init(
        first: SketchSplineEndpointReference,
        second: SketchSplineEndpointReference,
        orientation: SketchTangentOrientation
    ) {
        self.first = first
        self.second = second
        self.orientation = orientation
    }

    public func validate() throws {
        guard first != second else {
            throw SketchError.invalidReference(
                "Spline endpoint tangency requires two distinct endpoints."
            )
        }
    }

    private enum CodingKeys: String, CodingKey {
        case first
        case second
        case orientation
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.first, .second, .orientation], in: decoder)
        first = try container.decode(SketchSplineEndpointReference.self, forKey: .first)
        second = try container.decode(SketchSplineEndpointReference.self, forKey: .second)
        orientation = try container.decode(SketchTangentOrientation.self, forKey: .orientation)
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(first, forKey: .first)
        try container.encode(second, forKey: .second)
        try container.encode(orientation, forKey: .orientation)
    }
}
