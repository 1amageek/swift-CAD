import CADCore

public struct BSplineSurfaceTrimDomain: Codable, Sendable, Hashable {
    public var uLowerBound: Double
    public var uUpperBound: Double
    public var vLowerBound: Double
    public var vUpperBound: Double

    public init(
        uLowerBound: Double,
        uUpperBound: Double,
        vLowerBound: Double,
        vUpperBound: Double
    ) {
        self.uLowerBound = uLowerBound
        self.uUpperBound = uUpperBound
        self.vLowerBound = vLowerBound
        self.vUpperBound = vUpperBound
    }

    public static func fullSurfaceDomain(
        for surface: BSplineSurface3D,
        tolerance: ModelingTolerance = .standard
    ) throws -> BSplineSurfaceTrimDomain {
        try surface.validate(tolerance: tolerance)
        guard case let .closed(uLowerBound, uUpperBound) = surface.uDomain,
              case let .closed(vLowerBound, vUpperBound) = surface.vDomain else {
            throw GeometryError.invalidDistance(0.0)
        }
        return BSplineSurfaceTrimDomain(
            uLowerBound: uLowerBound,
            uUpperBound: uUpperBound,
            vLowerBound: vLowerBound,
            vUpperBound: vUpperBound
        )
    }

    public func validate(
        containedIn surface: BSplineSurface3D,
        tolerance: ModelingTolerance = .standard
    ) throws {
        try tolerance.validate()
        try surface.validate(tolerance: tolerance)
        guard uLowerBound.isFinite else {
            throw GeometryError.invalidCoordinate(uLowerBound)
        }
        guard uUpperBound.isFinite else {
            throw GeometryError.invalidCoordinate(uUpperBound)
        }
        guard vLowerBound.isFinite else {
            throw GeometryError.invalidCoordinate(vLowerBound)
        }
        guard vUpperBound.isFinite else {
            throw GeometryError.invalidCoordinate(vUpperBound)
        }
        guard uUpperBound - uLowerBound > tolerance.distance else {
            throw GeometryError.invalidDistance(uUpperBound - uLowerBound)
        }
        guard vUpperBound - vLowerBound > tolerance.distance else {
            throw GeometryError.invalidDistance(vUpperBound - vLowerBound)
        }
        guard try surface.uDomain.containsSpan(
            from: uLowerBound,
            to: uUpperBound,
            tolerance: tolerance
        ) else {
            throw GeometryError.invalidDistance(uUpperBound - uLowerBound)
        }
        guard try surface.vDomain.containsSpan(
            from: vLowerBound,
            to: vUpperBound,
            tolerance: tolerance
        ) else {
            throw GeometryError.invalidDistance(vUpperBound - vLowerBound)
        }
    }

    public func isFullSurfaceDomain(
        of surface: BSplineSurface3D,
        tolerance: ModelingTolerance = .standard
    ) throws -> Bool {
        let fullDomain = try Self.fullSurfaceDomain(for: surface, tolerance: tolerance)
        return abs(uLowerBound - fullDomain.uLowerBound) <= tolerance.distance
            && abs(uUpperBound - fullDomain.uUpperBound) <= tolerance.distance
            && abs(vLowerBound - fullDomain.vLowerBound) <= tolerance.distance
            && abs(vUpperBound - fullDomain.vUpperBound) <= tolerance.distance
    }
}
