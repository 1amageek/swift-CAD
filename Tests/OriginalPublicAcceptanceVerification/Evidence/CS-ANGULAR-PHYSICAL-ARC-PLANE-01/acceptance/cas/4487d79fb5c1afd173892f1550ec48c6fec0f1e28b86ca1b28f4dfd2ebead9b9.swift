import CADCore

extension DefaultCurveSurfaceIntersector: NativeExactCurveSurfaceGeometricResolving {
    public func exactGeometricRelation<A: ExactScalarAdmission & ~Copyable>(
        curve: BSplineCurve3D, surface: BSplineSurface3D,
        curveRange: ScalarInterval? = nil, surfaceDomain: SurfaceParameterBox? = nil,
        tolerance: ModelingTolerance, maximumPolynomialDegree: Int,
        maximumExtensionLevel: Int, limits: ExactGeometricRelationLimits,
        using admission: inout A
    ) throws(NativeExactGeometricRelationFailure) -> NativeExactGeometricRelation {
        do {
            let parameters = try exactParameterRelation(curve: curve, surface: surface,
                curveRange: curveRange, surfaceDomain: surfaceDomain, tolerance: tolerance,
                maximumPolynomialDegree: maximumPolynomialDegree,
                maximumExtensionLevel: maximumExtensionLevel, cellLimits: limits.cells,
                topologyLimits: limits.topology, using: &admission)
            let result = try DefaultNativeExactGeometricRelationResolver().resolve(parameters,
                limits: limits, using: &admission)
            return result
        } catch { throw .preserving(error) }
    }
}
