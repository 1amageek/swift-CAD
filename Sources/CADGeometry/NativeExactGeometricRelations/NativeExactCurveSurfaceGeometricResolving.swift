import CADCore

/// Source-bound geometric image, fibers, and complete selected-domain coverage.
public protocol NativeExactCurveSurfaceGeometricResolving: Sendable {
    func exactGeometricRelation<A: ExactScalarAdmission & ~Copyable>(
        curve: BSplineCurve3D, surface: BSplineSurface3D,
        curveRange: ScalarInterval?, surfaceDomain: SurfaceParameterBox?,
        tolerance: ModelingTolerance, maximumPolynomialDegree: Int,
        maximumExtensionLevel: Int, limits: ExactGeometricRelationLimits,
        using admission: inout A
    ) throws(NativeExactGeometricRelationFailure) -> NativeExactGeometricRelation
}
