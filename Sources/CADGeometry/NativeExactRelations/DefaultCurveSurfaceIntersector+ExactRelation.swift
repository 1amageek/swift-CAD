import CADCore

extension DefaultCurveSurfaceIntersector: NativeExactCurveSurfaceResolving {
    public func exactParameterRelation<A: ExactScalarAdmission & ~Copyable>(
        curve: BSplineCurve3D, surface: BSplineSurface3D,
        curveRange: ScalarInterval? = nil, surfaceDomain: SurfaceParameterBox? = nil,
        tolerance: ModelingTolerance, maximumPolynomialDegree: Int,
        maximumExtensionLevel: Int, cellLimits: ExactRealCellLimits,
        topologyLimits: ExactRealTopologyLimits, using admission: inout A
    ) throws(NativeExactRelationFailure) -> NativeExactParametricRelation {
        try DefaultNativeExactRelationResolver().exactParameterRelation(curve: curve, surface: surface,
            curveRange: curveRange, surfaceDomain: surfaceDomain, tolerance: tolerance,
            maximumPolynomialDegree: maximumPolynomialDegree, maximumExtensionLevel: maximumExtensionLevel,
            cellLimits: cellLimits, topologyLimits: topologyLimits, using: &admission)
    }
}
