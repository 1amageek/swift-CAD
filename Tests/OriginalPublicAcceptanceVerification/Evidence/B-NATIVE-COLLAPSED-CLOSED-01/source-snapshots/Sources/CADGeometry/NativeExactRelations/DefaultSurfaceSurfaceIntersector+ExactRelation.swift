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

// The collection entry retains exact selected boundaries and all Native chart lifts.
extension DefaultSurfaceSurfaceIntersector {
    public func exactParameterRelations<A: ExactScalarAdmission & ~Copyable>(
        first: OriginalBSplineDomainCover<BSplineSurface3D,ExactAlgebraicScalarDomain<ExactRationalScalarDomain>>,
        second: OriginalBSplineDomainCover<BSplineSurface3D,ExactAlgebraicScalarDomain<ExactRationalScalarDomain>>,
        domainLimits: OriginalDomainIdentityLimits,maximumMaps: Int,maximumPairs: Int,
        cellLimits: ExactRealCellLimits,topologyLimits: ExactRealTopologyLimits,using admission: inout A
    ) throws(NativeExactRelationFailure) -> NativeExactParametricRelations<BSplineSurface3D,BSplineSurface3D> {
        try DefaultNativeExactRelationFamilyResolver().exactParameterRelations(first:first,second:second,kind:.surfaceSurface,
            domainLimits:domainLimits,maximumMaps:maximumMaps,maximumPairs:maximumPairs,
            cellLimits:cellLimits,topologyLimits:topologyLimits,using:&admission)
    }
}
