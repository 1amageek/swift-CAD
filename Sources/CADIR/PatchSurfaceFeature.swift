import CADCore

public struct PatchSurfaceFeature: Codable, Sendable, Hashable {
    public enum BoundaryOrientation: String, Codable, Sendable, Hashable {
        case forward
        case reversed
    }

    public var vMinimumBoundary: BSplineCurve3D
    public var vMaximumBoundary: BSplineCurve3D
    public var uMinimumBoundary: BSplineCurve3D
    public var uMaximumBoundary: BSplineCurve3D
    public var vMinimumOrientation: BoundaryOrientation
    public var vMaximumOrientation: BoundaryOrientation
    public var uMinimumOrientation: BoundaryOrientation
    public var uMaximumOrientation: BoundaryOrientation
    public var material: MaterialID?

    public init(
        vMinimumBoundary: BSplineCurve3D,
        vMaximumBoundary: BSplineCurve3D,
        uMinimumBoundary: BSplineCurve3D,
        uMaximumBoundary: BSplineCurve3D,
        vMinimumOrientation: BoundaryOrientation = .forward,
        vMaximumOrientation: BoundaryOrientation = .forward,
        uMinimumOrientation: BoundaryOrientation = .forward,
        uMaximumOrientation: BoundaryOrientation = .forward,
        material: MaterialID? = nil
    ) {
        self.vMinimumBoundary = vMinimumBoundary
        self.vMaximumBoundary = vMaximumBoundary
        self.uMinimumBoundary = uMinimumBoundary
        self.uMaximumBoundary = uMaximumBoundary
        self.vMinimumOrientation = vMinimumOrientation
        self.vMaximumOrientation = vMaximumOrientation
        self.uMinimumOrientation = uMinimumOrientation
        self.uMaximumOrientation = uMaximumOrientation
        self.material = material
    }

    private enum CodingKeys: String, CodingKey {
        case vMinimumBoundary
        case vMaximumBoundary
        case uMinimumBoundary
        case uMaximumBoundary
        case vMinimumOrientation
        case vMaximumOrientation
        case uMinimumOrientation
        case uMaximumOrientation
        case material
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys(
            [
                .vMinimumBoundary,
                .vMaximumBoundary,
                .uMinimumBoundary,
                .uMaximumBoundary,
                .vMinimumOrientation,
                .vMaximumOrientation,
                .uMinimumOrientation,
                .uMaximumOrientation,
                .material,
            ],
            in: decoder
        )
        vMinimumBoundary = try container.decode(
            BSplineCurve3D.self,
            forKey: .vMinimumBoundary
        )
        vMaximumBoundary = try container.decode(
            BSplineCurve3D.self,
            forKey: .vMaximumBoundary
        )
        uMinimumBoundary = try container.decode(
            BSplineCurve3D.self,
            forKey: .uMinimumBoundary
        )
        uMaximumBoundary = try container.decode(
            BSplineCurve3D.self,
            forKey: .uMaximumBoundary
        )
        vMinimumOrientation = try container.decode(
            BoundaryOrientation.self,
            forKey: .vMinimumOrientation
        )
        vMaximumOrientation = try container.decode(
            BoundaryOrientation.self,
            forKey: .vMaximumOrientation
        )
        uMinimumOrientation = try container.decode(
            BoundaryOrientation.self,
            forKey: .uMinimumOrientation
        )
        uMaximumOrientation = try container.decode(
            BoundaryOrientation.self,
            forKey: .uMaximumOrientation
        )
        material = try container.decodeIfPresent(MaterialID.self, forKey: .material)
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
    }

    public func encode(to encoder: Encoder) throws {
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(vMinimumBoundary, forKey: .vMinimumBoundary)
        try container.encode(vMaximumBoundary, forKey: .vMaximumBoundary)
        try container.encode(uMinimumBoundary, forKey: .uMinimumBoundary)
        try container.encode(uMaximumBoundary, forKey: .uMaximumBoundary)
        try container.encode(vMinimumOrientation, forKey: .vMinimumOrientation)
        try container.encode(vMaximumOrientation, forKey: .vMaximumOrientation)
        try container.encode(uMinimumOrientation, forKey: .uMinimumOrientation)
        try container.encode(uMaximumOrientation, forKey: .uMaximumOrientation)
        try container.encodeIfPresent(material, forKey: .material)
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        try vMinimumBoundary.validate(tolerance: tolerance)
        try vMaximumBoundary.validate(tolerance: tolerance)
        try uMinimumBoundary.validate(tolerance: tolerance)
        try uMaximumBoundary.validate(tolerance: tolerance)
    }
}
