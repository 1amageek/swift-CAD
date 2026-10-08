import CADCore

extension DefaultNativeExactGeometricRelationResolver: NativeExactSurfaceSurfaceGeometricResolving {
    public func exactGeometricRelation<A: ExactScalarAdmission & ~Copyable>(
        first: BSplineSurface3D, second: BSplineSurface3D,
        firstDomain: SurfaceParameterBox? = nil, secondDomain: SurfaceParameterBox? = nil,
        tolerance: ModelingTolerance, maximumPolynomialDegree: Int,
        maximumExtensionLevel: Int, limits: ExactGeometricRelationLimits,
        using admission: inout A
    ) throws(NativeExactGeometricRelationFailure) -> NativeExactGeometricRelation {
        do {
            let parameters = try DefaultNativeExactRelationResolver().exactParameterRelation(
                first: first, second: second, firstDomain: firstDomain, secondDomain: secondDomain,
                tolerance: tolerance, maximumPolynomialDegree: maximumPolynomialDegree,
                maximumExtensionLevel: maximumExtensionLevel, cellLimits: limits.cells,
                topologyLimits: limits.topology, using: &admission)
            return try resolve(parameters, limits: limits, using: &admission)
        } catch { throw .preserving(error) }
    }
}
