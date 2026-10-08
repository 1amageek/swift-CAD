import CADCore
#if NATIVE_DOMAIN_ISOLATED_VERIFICATION
import struct CADGeometry.ScalarInterval
import struct CADGeometry.BSplineCurve3D
import struct CADGeometry.BSplineSurface3D
import struct CADGeometry.DefaultCurveSurfaceIntersector
import struct CADGeometry.DefaultSurfaceSurfaceIntersector
import struct CADGeometry.SurfaceParameterBox
import L0
import L1
import L2
import L3
import L4
import L5
import DI0
import SourceIssuer
import DI
import SourceGeometryAdapters
#endif

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
