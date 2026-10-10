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

extension DefaultOriginalFaceBoundaryClipper: OriginalExactFaceBoundaryClipping {
    public func clip<A: ExactScalarAdmission & ~Copyable>(_ source: OriginalExactNativeBoundarySource,
        to faceID: FaceID,in original: ValidatedBRepModel,selection: OriginalNativeBoundaryDomain.Selection = .closed,
        domainLimits: OriginalDomainIdentityLimits,cellLimits: ExactRealCellLimits,topologyLimits: ExactRealTopologyLimits,
        using admission: inout A
    ) throws(NativeExactRelationFailure) -> OriginalExactFaceClippedParameters {
        try clip(source,to:faceID,in:original,selection:selection,consumer:DefaultOriginalExactNativeBoundaryClipper(),
            domainLimits:domainLimits,cellLimits:cellLimits,topologyLimits:topologyLimits,using:&admission)
    }
    public func clip<C: OriginalExactNativeBoundaryClipping,A: ExactScalarAdmission & ~Copyable>(
        _ source: OriginalExactNativeBoundarySource,to faceID: FaceID,in original: ValidatedBRepModel,
        selection: OriginalNativeBoundaryDomain.Selection,consumer: C,domainLimits: OriginalDomainIdentityLimits,
        cellLimits: ExactRealCellLimits,topologyLimits: ExactRealTopologyLimits,using admission: inout A
    ) throws(NativeExactRelationFailure) -> OriginalExactFaceClippedParameters {
        do {
            try admission.checkpoint()
            let issuer = try OriginalExactFaceBoundaryIssuer(source:source,faceID:faceID,original:original,domainLimits:domainLimits,using:&admission)
            let selected = try consumer.clip(issuer.domain,selection:selection,domainLimits:domainLimits,
                cellLimits:cellLimits,topologyLimits:topologyLimits,using:&admission)
            // The concrete result has no public initializer; the consumer retains the sealed source.
            guard selected.boundary === issuer.domain,selected.selection == selection else { throw NativeExactRelationFailure.invalidDomain }
            try admission.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalExactFaceClippedParameters.self))
            let result = OriginalExactFaceClippedParameters(original:original,faceID:faceID,loops:issuer.loops,parameters:selected)
            try admission.checkpoint();return result
        } catch { throw .preserving(error) }
    }
}
