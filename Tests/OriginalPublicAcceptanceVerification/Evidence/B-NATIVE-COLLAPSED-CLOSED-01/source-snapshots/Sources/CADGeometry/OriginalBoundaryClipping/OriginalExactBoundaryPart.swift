#if NATIVE_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
import L4
import L5
import DI0
import DI
import SourceIssuer
import SourceGeometryAdapters
import struct CADGeometry.BSplineCurve3D
import struct CADGeometry.BSplineSurface3D
import enum CADGeometry.SurfaceParameterCurve
@testable import class CADGeometry.OriginalNativeBoundaryDomain
#endif

/// One retained pair's surface chart in the existing L5 local parameter coordinates.
struct OriginalExactBoundaryPart {
    typealias Field = ExactAlgebraicScalarDomain<ExactRationalScalarDomain>
    let relation: ExactParametricRelation<ExactRationalScalarDomain>
    let surface: OriginalDomainBoundRationalChart<BSplineSurface3D,Field>
    let uAxis: Int
}
