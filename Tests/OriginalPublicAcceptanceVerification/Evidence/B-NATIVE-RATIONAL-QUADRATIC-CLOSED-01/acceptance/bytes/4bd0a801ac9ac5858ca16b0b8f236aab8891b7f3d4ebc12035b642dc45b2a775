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

/// Complete exact material refinement over retained Native L5 cells and lifted UV.
public protocol OriginalExactNativeBoundaryClipping: Sendable {
    func clip<A: ExactScalarAdmission & ~Copyable>(_ boundary: OriginalExactNativeBoundaryDomain,
        selection: OriginalNativeBoundaryDomain.Selection,domainLimits: OriginalDomainIdentityLimits,
        cellLimits: ExactRealCellLimits,topologyLimits: ExactRealTopologyLimits,using admission: inout A
    ) throws(NativeExactRelationFailure) -> OriginalExactClippedNativeParameters
}
