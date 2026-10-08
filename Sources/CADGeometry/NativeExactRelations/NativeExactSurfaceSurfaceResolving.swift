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
