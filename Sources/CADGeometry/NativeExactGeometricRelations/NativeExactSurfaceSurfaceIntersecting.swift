import CADCore

/// Existing numerical publication with explicit exact caller resources.
public protocol NativeExactSurfaceSurfaceIntersecting: Sendable {
    func intersectionResult<A: ExactScalarAdmission & ~Copyable>(
        first: BSplineSurface3D, second: BSplineSurface3D,
        firstDomain: SurfaceParameterBox?, secondDomain: SurfaceParameterBox?,
        options: SurfaceSurfaceIntersectionOptions, tolerance: ModelingTolerance,
        maximumPolynomialDegree: Int, maximumExtensionLevel: Int,
        limits: ExactGeometricRelationLimits, using admission: inout A
    ) throws -> SurfaceSurfaceIntersectionResult
    func intersections<A: ExactScalarAdmission & ~Copyable>(
        first: BSplineSurface3D, second: BSplineSurface3D,
        firstDomain: SurfaceParameterBox?, secondDomain: SurfaceParameterBox?,
        options: SurfaceSurfaceIntersectionOptions, tolerance: ModelingTolerance,
        maximumPolynomialDegree: Int, maximumExtensionLevel: Int,
        limits: ExactGeometricRelationLimits, using admission: inout A
    ) throws -> [SurfaceSurfaceIntersection]
}
