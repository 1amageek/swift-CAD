import CADCore

extension DefaultSurfaceSurfaceIntersector: NativeExactSurfaceSurfaceResolving {
    public func exactParameterRelation<A: ExactScalarAdmission & ~Copyable>(
        first: BSplineSurface3D, second: BSplineSurface3D,
        firstDomain: SurfaceParameterBox? = nil, secondDomain: SurfaceParameterBox? = nil,
        tolerance: ModelingTolerance, maximumPolynomialDegree: Int,
        maximumExtensionLevel: Int, cellLimits: ExactRealCellLimits,
        topologyLimits: ExactRealTopologyLimits, using admission: inout A
    ) throws(NativeExactRelationFailure) -> NativeExactParametricRelation {
        try DefaultNativeExactRelationResolver().exactParameterRelation(first: first, second: second,
            firstDomain: firstDomain, secondDomain: secondDomain, tolerance: tolerance,
            maximumPolynomialDegree: maximumPolynomialDegree, maximumExtensionLevel: maximumExtensionLevel,
            cellLimits: cellLimits, topologyLimits: topologyLimits, using: &admission)
    }
}
