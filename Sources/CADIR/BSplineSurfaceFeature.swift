import CADCore

public struct BSplineSurfaceFeature: Codable, Sendable, Hashable {
    public var surface: BSplineSurface3D
    public var material: MaterialID?
    public var parameterDomain: SurfaceParameterDomain2D?

    public init(
        surface: BSplineSurface3D,
        material: MaterialID? = nil,
        parameterDomain: SurfaceParameterDomain2D? = nil
    ) {
        self.surface = surface
        self.material = material
        self.parameterDomain = parameterDomain
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try surface.validate(tolerance: tolerance)
        try parameterDomain?.validate(containedIn: surface, tolerance: tolerance)
    }

    public func resolvedParameterDomain(
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterDomain2D {
        if let parameterDomain {
            try parameterDomain.validate(containedIn: surface, tolerance: tolerance)
            return parameterDomain
        }
        return try SurfaceParameterDomain2D.fullDomain(of: surface, tolerance: tolerance)
    }

    private enum CodingKeys: String, CodingKey {
        case surface
        case material
        case parameterDomain
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.surface, .material, .parameterDomain], in: decoder)
        surface = try container.decode(BSplineSurface3D.self, forKey: .surface)
        material = try container.decodeIfPresent(MaterialID.self, forKey: .material)
        parameterDomain = try container.decodeIfPresent(
            SurfaceParameterDomain2D.self,
            forKey: .parameterDomain
        )
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
    }

    public func encode(to encoder: Encoder) throws {
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(surface, forKey: .surface)
        try container.encodeIfPresent(material, forKey: .material)
        try container.encodeIfPresent(parameterDomain, forKey: .parameterDomain)
    }
}
