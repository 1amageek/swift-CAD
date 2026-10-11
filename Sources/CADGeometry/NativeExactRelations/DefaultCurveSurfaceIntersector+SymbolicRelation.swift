import CADCore
#if NATIVE_DOMAIN_ISOLATED_VERIFICATION
import struct CADGeometry.BSplineCurve3D
import struct CADGeometry.BSplineSurface3D
import struct CADGeometry.DefaultCurveSurfaceIntersector
import SourceGeometryAdapters
#endif
#if NATIVE_FAMILY_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
import L4
import L5
import DI0
import SourceIssuer
import DI
#endif

extension DefaultCurveSurfaceIntersector {
    public func exactParameterRelationFamily<A: ExactScalarAdmission & ~Copyable>(
        curve: OriginalBSplineDomainCover<BSplineCurve3D,ExactAlgebraicScalarDomain<ExactRationalScalarDomain>>,
        surface: OriginalBSplineDomainCover<BSplineSurface3D,ExactAlgebraicScalarDomain<ExactRationalScalarDomain>>,
        domainLimits: OriginalDomainIdentityLimits,maximumMaps: Int,maximumPairs: Int,
        cellLimits: ExactRealCellLimits,topologyLimits: ExactRealTopologyLimits,using admission: inout A
    ) throws(NativeExactRelationFailure) -> NativeExactSymbolicRelationFamily<BSplineCurve3D,BSplineSurface3D> {
        try DefaultNativeExactRelationFamilyResolver().exactParameterRelationFamily(first:curve,second:surface,kind:.curveSurface,
            domainLimits:domainLimits,maximumMaps:maximumMaps,maximumPairs:maximumPairs,
            cellLimits:cellLimits,topologyLimits:topologyLimits,using:&admission)
    }
}
