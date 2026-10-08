import CADCore

/// Source-bound complete UV/UV relation with independently certified image and fiber dimensions.
public protocol NativeExactSurfaceSurfaceGeometricResolving: Sendable {
    func exactGeometricRelation<A: ExactScalarAdmission & ~Copyable>(
        first: BSplineSurface3D, second: BSplineSurface3D,
        firstDomain: SurfaceParameterBox?, secondDomain: SurfaceParameterBox?,
        tolerance: ModelingTolerance, maximumPolynomialDegree: Int,
        maximumExtensionLevel: Int, limits: ExactGeometricRelationLimits,
        using admission: inout A
    ) throws(NativeExactGeometricRelationFailure) -> NativeExactGeometricRelation
}
