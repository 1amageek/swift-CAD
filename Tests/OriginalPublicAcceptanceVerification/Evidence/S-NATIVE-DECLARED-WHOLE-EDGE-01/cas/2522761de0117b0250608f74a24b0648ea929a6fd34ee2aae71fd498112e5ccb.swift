@testable import NativeDomainAdapters
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

/// Subtracts only proved structural identities from a retained complete Native self relation.
public protocol OriginalExactNativeSelfContactQuerying: Sendable {
    func contacts<A: ExactScalarAdmission & ~Copyable>(
        in raw: NativeExactParametricRelations<BSplineSurface3D,BSplineSurface3D>,
        excluding identities: [OriginalParameterIdentity<BSplineSurface3D,ExactAlgebraicScalarDomain<ExactRationalScalarDomain>>],
        domainLimits: OriginalDomainIdentityLimits,cellLimits: ExactRealCellLimits,
        topologyLimits: ExactRealTopologyLimits,using admission: inout A
    ) throws(NativeExactRelationFailure) -> OriginalExactNativeSelfContacts
}
