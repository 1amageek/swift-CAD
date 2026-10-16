import CADGeometry
import CADCore

public struct BSplineSurfaceFeature: Sendable, Hashable {
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
        var execution = try OriginalQueryExecution.independentGeometry()
        try validate(tolerance: tolerance, using: &execution)
    }

    public func validate(tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        try surface.validate(tolerance: tolerance, using: &execution)
        try parameterDomain?.validate(containedIn: surface, tolerance: tolerance, using: &execution)

        try execution.checkpoint()
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

#if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey {
        case surface
        case material
        case parameterDomain
    }
#endif

#if !hasFeature(Embedded)
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
#endif

#if !hasFeature(Embedded)
    public func encode(to encoder: Encoder) throws {
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(surface, forKey: .surface)
        try container.encodeIfPresent(material, forKey: .material)
        try container.encodeIfPresent(parameterDomain, forKey: .parameterDomain)
    }
#endif
}

#if !hasFeature(Embedded)
extension BSplineSurfaceFeature: Codable {}
#endif
