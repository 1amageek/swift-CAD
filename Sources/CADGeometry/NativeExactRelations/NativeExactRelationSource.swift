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

/// Immutable value snapshots of authored inputs and their original selections.
public enum NativeExactRelationSource: Sendable {
    case curveSurface(curve: BSplineCurve3D, surface: BSplineSurface3D,
        curveRange: ScalarInterval?, surfaceDomain: SurfaceParameterBox?)
    case surfaceSurface(first: BSplineSurface3D, second: BSplineSurface3D,
        firstDomain: SurfaceParameterBox?, secondDomain: SurfaceParameterBox?)
}
