import CADCore

public struct SurfaceSurfaceIntersectionPoint: Codable, Hashable, Sendable {
    public let point: Point3D
    public let firstSurfaceParameter: SurfaceParameterProjection
    public let secondSurfaceParameter: SurfaceParameterProjection
    public let residual: Double

    public init(
        point: Point3D,
        firstSurfaceParameter: SurfaceParameterProjection,
        secondSurfaceParameter: SurfaceParameterProjection,
        residual: Double,
        tolerance: ModelingTolerance
    ) throws {
        try tolerance.validate()
        try point.validate()
        guard residual.isFinite,
              residual >= 0.0,
              residual <= tolerance.distance,
              firstSurfaceParameter.residual <= tolerance.distance,
              secondSurfaceParameter.residual <= tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: residual,
                tolerance: tolerance,
                message: "Surface-surface intersection point failed residual verification."
            )
        }
        self.point = point
        self.firstSurfaceParameter = firstSurfaceParameter
        self.secondSurfaceParameter = secondSurfaceParameter
        self.residual = residual
    }
}
