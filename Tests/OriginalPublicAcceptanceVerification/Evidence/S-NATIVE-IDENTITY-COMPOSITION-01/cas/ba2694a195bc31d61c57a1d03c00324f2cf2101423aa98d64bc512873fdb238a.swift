import HashTreeCollections
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

/// Validates unchanged topology and supplies every authored lifted pcurve to Geometry.
struct OriginalExactFaceBoundaryIssuer {
    let domain: OriginalExactNativeBoundaryDomain
    let loops: [Loop]
    init<A: ExactScalarAdmission & ~Copyable>(source: OriginalExactNativeBoundarySource,faceID: FaceID,
        original: ValidatedBRepModel,domainLimits: OriginalDomainIdentityLimits,using a: inout A) throws {
        try a.checkpoint()
        try source.admitted(limits:domainLimits,using:&a)
        guard original.validationLevel != .modeling,let face = original.model.faces[faceID],
            let stored = original.model.geometry.surfaces[face.surfaceID],case .bSpline(let support) = stored else {
            throw Self.failure(.invalidInput,original.tolerance,"Exact boundary clipping requires the unchanged original Native face support.")
        }
        func charge(_ surface: BSplineSurface3D) throws {
            try a.consumeWork(8)
            for _ in surface.uKnots { try a.consumeWork(1) }
            for _ in surface.vKnots { try a.consumeWork(1) }
            for row in surface.controlPoints { try a.consumeWork(1);for _ in row { try a.consumeWork(3) } }
            for row in surface.weights { try a.consumeWork(1);for _ in row { try a.consumeWork(1) } }
        }
        try charge(support);try charge(source.surface)
        guard support == source.surface else {
            throw Self.failure(.invalidInput,original.tolerance,"The face support does not own the selected exact source surface.")
        }
        let retained = try OriginalExactFaceBoundaryLoops(face:face,original:original,using:&a)
        domain = try .init(source:source,loops:retained.directed,using:&a);loops = retained.retained
        try a.checkpoint()
    }
    private static func failure(_ code: KernelErrorCode,_ tolerance: ModelingTolerance,_ message: String) -> KernelError {
        .init(phase:.geometry,code:code,tolerance:tolerance,message:message)
    }
}
