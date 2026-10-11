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
/// Preparation owns source provenance and the checked L5 map together.
struct NativeExactPreparedMap: Sendable {
    let map: ExactParametricMap<ExactRationalScalarDomain>
    let sourceLaw: NativeExactIssuedSourceLaw
}
