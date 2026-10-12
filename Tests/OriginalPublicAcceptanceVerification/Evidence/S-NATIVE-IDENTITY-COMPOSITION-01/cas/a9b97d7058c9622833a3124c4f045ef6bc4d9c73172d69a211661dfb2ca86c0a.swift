import CADCore
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
import NativeDomainAdapters
import struct CADGeometry.BSplineSurface3D
import enum CADGeometry.SurfaceParameterCurve
@testable import class CADGeometry.OriginalNativeBoundaryDomain
@testable import struct CADKernel.DefaultOriginalFaceBoundaryClipper
#else
import CADGeometry
#endif
import CADTopology

/// Face-issued complete boundary refinement over retained Native L5 families.
public protocol OriginalExactFaceBoundaryClipping: Sendable {
    func clip<C: OriginalExactNativeBoundaryClipping,A: ExactScalarAdmission & ~Copyable>(
        _ source: OriginalExactNativeBoundarySource,to faceID: FaceID,in original: ValidatedBRepModel,
        selection: OriginalNativeBoundaryDomain.Selection,consumer: C,domainLimits: OriginalDomainIdentityLimits,
        cellLimits: ExactRealCellLimits,topologyLimits: ExactRealTopologyLimits,using admission: inout A
    ) throws(NativeExactRelationFailure) -> OriginalExactFaceClippedParameters
}
