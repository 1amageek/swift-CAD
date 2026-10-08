import CADCore

/// Existing numerical publication with explicit exact caller resources.
public protocol NativeExactCurveSurfaceIntersecting: Sendable {
    func intersectionResult<A: ExactScalarAdmission & ~Copyable>(
        curve: BSplineCurve3D, surface: BSplineSurface3D,
        options: CurveSurfaceIntersectionOptions, tolerance: ModelingTolerance,
        maximumExtensionLevel: Int, limits: ExactGeometricRelationLimits,
        using admission: inout A
    ) throws -> CurveSurfaceIntersectionResult
    func intersections<A: ExactScalarAdmission & ~Copyable>(
        curve: BSplineCurve3D, surface: BSplineSurface3D,
        options: CurveSurfaceIntersectionOptions, tolerance: ModelingTolerance,
        maximumExtensionLevel: Int, limits: ExactGeometricRelationLimits,
        using admission: inout A
    ) throws -> [CurveSurfaceIntersection]
}
