import CADCore

extension DefaultSurfaceSurfaceIntersector: NativeExactSurfaceSurfaceGeometricResolving {
    public func exactGeometricRelation<A: ExactScalarAdmission & ~Copyable>(
        first: BSplineSurface3D, second: BSplineSurface3D,
        firstDomain: SurfaceParameterBox? = nil, secondDomain: SurfaceParameterBox? = nil,
        tolerance: ModelingTolerance, maximumPolynomialDegree: Int,
        maximumExtensionLevel: Int, limits: ExactGeometricRelationLimits,
        using admission: inout A
    ) throws(NativeExactGeometricRelationFailure) -> NativeExactGeometricRelation {
        try DefaultNativeExactGeometricRelationResolver().exactGeometricRelation(
            first: first, second: second, firstDomain: firstDomain, secondDomain: secondDomain,
            tolerance: tolerance, maximumPolynomialDegree: maximumPolynomialDegree,
            maximumExtensionLevel: maximumExtensionLevel, limits: limits,
            using: &admission)
    }
}
