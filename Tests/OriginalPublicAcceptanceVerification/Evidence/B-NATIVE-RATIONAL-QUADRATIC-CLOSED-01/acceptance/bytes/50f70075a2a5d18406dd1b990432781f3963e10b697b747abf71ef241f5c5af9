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

/// Keeps the family-issued original law alive throughout relation construction.
enum NativeExactIssuedSourceLaw: Sendable {
    typealias Field = ExactAlgebraicScalarDomain<ExactRationalScalarDomain>
    case curve(OriginalRationalChartReceipt<BSplineCurve3D, OriginalBSplineChartSelection, Field>)
    case surface(OriginalRationalChartReceipt<BSplineSurface3D, OriginalBSplineChartSelection, Field>)
}
