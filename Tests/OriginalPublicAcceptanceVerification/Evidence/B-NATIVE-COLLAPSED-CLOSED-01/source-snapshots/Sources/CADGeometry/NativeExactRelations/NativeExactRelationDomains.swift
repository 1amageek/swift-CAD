import CADCore
#if NATIVE_DOMAIN_ISOLATED_VERIFICATION
import struct CADGeometry.ScalarInterval
import struct CADGeometry.BSplineCurve3D
import struct CADGeometry.BSplineSurface3D
import L0
import L2
import DI
import SourceGeometryAdapters
#endif

/// Complete requested/native domain proof retained by the public relation owner.
public enum NativeExactRelationDomains: Sendable {
    public typealias Field = ExactAlgebraicScalarDomain<ExactRationalScalarDomain>
    case curveSurface(curve: OriginalBSplineDomainCover<BSplineCurve3D,Field>,
        surface: OriginalBSplineDomainCover<BSplineSurface3D,Field>)
    case surfaceSurface(first: OriginalBSplineDomainCover<BSplineSurface3D,Field>,
        second: OriginalBSplineDomainCover<BSplineSurface3D,Field>)
}
