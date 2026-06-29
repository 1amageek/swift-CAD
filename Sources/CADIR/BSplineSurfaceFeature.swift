import CADCore

public struct BSplineSurfaceFeature: Codable, Sendable, Hashable {
    public var surface: BSplineSurface3D
    public var material: MaterialID?
    public var outerTrimDomain: BSplineSurfaceTrimDomain?

    public init(
        surface: BSplineSurface3D,
        material: MaterialID? = nil,
        outerTrimDomain: BSplineSurfaceTrimDomain? = nil
    ) {
        self.surface = surface
        self.material = material
        self.outerTrimDomain = outerTrimDomain
    }

    public func validate(tolerance: ModelingTolerance = .standard) throws {
        try surface.validate(tolerance: tolerance)
        try outerTrimDomain?.validate(containedIn: surface, tolerance: tolerance)
    }

    public func resolvedOuterTrimDomain(
        tolerance: ModelingTolerance = .standard
    ) throws -> BSplineSurfaceTrimDomain {
        if let outerTrimDomain {
            try outerTrimDomain.validate(containedIn: surface, tolerance: tolerance)
            return outerTrimDomain
        }
        return try BSplineSurfaceTrimDomain.fullSurfaceDomain(for: surface, tolerance: tolerance)
    }
}
