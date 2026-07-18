import CADCore

public struct BSplineSurfaceFeature: Codable, Sendable, Hashable {
    public var surface: BSplineSurface3D
    public var material: MaterialID?
    public var outerTrimDomain: BSplineSurfaceTrimDomain?
    public var trimLoops: [BSplineSurfaceTrimLoop]

    public init(
        surface: BSplineSurface3D,
        material: MaterialID? = nil,
        outerTrimDomain: BSplineSurfaceTrimDomain? = nil,
        trimLoops: [BSplineSurfaceTrimLoop] = []
    ) {
        self.surface = surface
        self.material = material
        self.outerTrimDomain = outerTrimDomain
        self.trimLoops = trimLoops
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try surface.validate(tolerance: tolerance)
        guard trimLoops.isEmpty || outerTrimDomain == nil else {
            throw GeometryError.invalidDistance(Double(trimLoops.count))
        }
        try outerTrimDomain?.validate(containedIn: surface, tolerance: tolerance)
        try validateTrimLoops(tolerance: tolerance)
    }

    public func resolvedOuterTrimDomain(
        tolerance: ModelingTolerance
    ) throws -> BSplineSurfaceTrimDomain {
        if let outerTrimDomain {
            try outerTrimDomain.validate(containedIn: surface, tolerance: tolerance)
            return outerTrimDomain
        }
        return try BSplineSurfaceTrimDomain.fullSurfaceDomain(for: surface, tolerance: tolerance)
    }

    public func resolvedTrimLoops(
        tolerance: ModelingTolerance
    ) throws -> [BSplineSurfaceTrimLoop] {
        try validate(tolerance: tolerance)
        if trimLoops.isEmpty == false {
            return trimLoops
        }
        let domain = try resolvedOuterTrimDomain(tolerance: tolerance)
        return [BSplineSurfaceTrimLoop.rectangularOuterLoop(domain: domain)]
    }

    private func validateTrimLoops(tolerance: ModelingTolerance) throws {
        guard trimLoops.isEmpty == false else {
            return
        }
        try BSplineSurfaceTrimLoopValidator(tolerance: tolerance).validate(trimLoops, on: surface)
    }
}
