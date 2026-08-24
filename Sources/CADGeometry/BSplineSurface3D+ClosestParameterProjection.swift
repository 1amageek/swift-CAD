import CADCore

extension BSplineSurface3D {
    /// Returns a globally certified closest point on this bounded surface.
    public func closestParameterProjection(
        of point: Point3D,
        options: SurfaceParameterProjectionOptions = .init(),
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterProjection {
        try ProceduralSurfaceParameterProjector().closestProjection(
            of: point,
            on: .bSpline(self),
            options: options,
            tolerance: tolerance
        )
    }
}
