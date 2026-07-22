import CADCore

public struct BridgeSurfaceFeature: Codable, Sendable, Hashable {
    public enum EndOrientation: String, Codable, Sendable, Hashable {
        case forward
        case reversed
    }

    public var startBoundary: BSplineCurve3D
    public var endBoundary: BSplineCurve3D
    public var endOrientation: EndOrientation
    public var material: MaterialID?

    public init(
        startBoundary: BSplineCurve3D,
        endBoundary: BSplineCurve3D,
        endOrientation: EndOrientation = .forward,
        material: MaterialID? = nil
    ) {
        self.startBoundary = startBoundary
        self.endBoundary = endBoundary
        self.endOrientation = endOrientation
        self.material = material
    }

    private enum CodingKeys: String, CodingKey {
        case startBoundary
        case endBoundary
        case endOrientation
        case material
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys(
            [.startBoundary, .endBoundary, .endOrientation, .material],
            in: decoder
        )
        startBoundary = try container.decode(
            BSplineCurve3D.self,
            forKey: .startBoundary
        )
        endBoundary = try container.decode(
            BSplineCurve3D.self,
            forKey: .endBoundary
        )
        endOrientation = try container.decode(
            EndOrientation.self,
            forKey: .endOrientation
        )
        material = try container.decodeIfPresent(MaterialID.self, forKey: .material)
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
    }

    public func encode(to encoder: Encoder) throws {
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(startBoundary, forKey: .startBoundary)
        try container.encode(endBoundary, forKey: .endBoundary)
        try container.encode(endOrientation, forKey: .endOrientation)
        try container.encodeIfPresent(material, forKey: .material)
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        try startBoundary.validate(tolerance: tolerance)
        try endBoundary.validate(tolerance: tolerance)
    }
}
