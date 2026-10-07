import CADCore

/// Complete original UV/UV topology; parameter dimension is not image dimension.
public protocol NativeExactSurfaceSurfaceResolving: Sendable {
    func exactParameterRelation<A: ExactScalarAdmission & ~Copyable>(
        first: BSplineSurface3D, second: BSplineSurface3D,
        firstDomain: SurfaceParameterBox?, secondDomain: SurfaceParameterBox?,
        tolerance: ModelingTolerance, maximumPolynomialDegree: Int,
        maximumExtensionLevel: Int, cellLimits: ExactRealCellLimits,
        topologyLimits: ExactRealTopologyLimits, using admission: inout A
    ) throws(NativeExactRelationFailure) -> NativeExactParametricRelation
}
