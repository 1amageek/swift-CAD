import CADCore
@testable import CADGeometry

@testable import ImplicitSourcePhase
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

extension DefaultCurveSurfaceIntersector: NativeExactCurveSurfaceResolving {
    public func exactParameterRelation<A: ExactScalarAdmission & ~Copyable>(
        curve: BSplineCurve3D, surface: BSplineSurface3D,
        curveRange: ScalarInterval? = nil, surfaceDomain: SurfaceParameterBox? = nil,
        tolerance: ModelingTolerance, maximumPolynomialDegree: Int,
        maximumExtensionLevel: Int, cellLimits: ExactRealCellLimits,
        topologyLimits: ExactRealTopologyLimits, using admission: inout A
    ) throws(NativeExactRelationFailure) -> NativeExactParametricRelation {
        try DefaultNativeExactRelationResolver().exactParameterRelation(curve: curve, surface: surface,
            curveRange: curveRange, surfaceDomain: surfaceDomain, tolerance: tolerance,
            maximumPolynomialDegree: maximumPolynomialDegree, maximumExtensionLevel: maximumExtensionLevel,
            cellLimits: cellLimits, topologyLimits: topologyLimits, using: &admission)
    }
}

// The collection entry retains exact selected boundaries and all Native chart lifts.
extension DefaultCurveSurfaceIntersector {
    public func exactParameterRelations<A: ExactScalarAdmission & ~Copyable>(
        curve: OriginalBSplineDomainCover<BSplineCurve3D,ExactAlgebraicScalarDomain<ExactRationalScalarDomain>>,
        surface: OriginalBSplineDomainCover<BSplineSurface3D,ExactAlgebraicScalarDomain<ExactRationalScalarDomain>>,
        domainLimits: OriginalDomainIdentityLimits,maximumMaps: Int,maximumPairs: Int,
        cellLimits: ExactRealCellLimits,topologyLimits: ExactRealTopologyLimits,using admission: inout A
    ) throws(NativeExactRelationFailure) -> NativeExactParametricRelations<BSplineCurve3D,BSplineSurface3D> {
        try DefaultNativeExactRelationFamilyResolver().exactParameterRelations(first:curve,second:surface,kind:.curveSurface,
            domainLimits:domainLimits,maximumMaps:maximumMaps,maximumPairs:maximumPairs,
            cellLimits:cellLimits,topologyLimits:topologyLimits,using:&admission)
    }
}
