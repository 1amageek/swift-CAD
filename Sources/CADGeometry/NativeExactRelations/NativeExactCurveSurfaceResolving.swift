import CADCore

/// Complete original parameter topology for a finite single-span Native pair.
public protocol NativeExactCurveSurfaceResolving: Sendable {
    func exactParameterRelation<A: ExactScalarAdmission & ~Copyable>(
        curve: BSplineCurve3D, surface: BSplineSurface3D,
        curveRange: ScalarInterval?, surfaceDomain: SurfaceParameterBox?,
        tolerance: ModelingTolerance, maximumPolynomialDegree: Int,
        maximumExtensionLevel: Int, cellLimits: ExactRealCellLimits,
        topologyLimits: ExactRealTopologyLimits, using admission: inout A
    ) throws(NativeExactRelationFailure) -> NativeExactParametricRelation
}
