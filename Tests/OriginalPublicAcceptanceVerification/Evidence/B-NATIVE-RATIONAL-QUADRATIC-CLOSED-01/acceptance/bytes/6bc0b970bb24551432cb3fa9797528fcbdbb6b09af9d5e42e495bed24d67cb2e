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

import CADCore

/// Original face-issued loops sealed to a complete L5 family and one surface side.
public final class OriginalExactNativeBoundaryDomain: Sendable {
    public let source: OriginalExactNativeBoundarySource
    package let loops: [OriginalNativeBoundaryDomain.Loop]
    package init<A: ExactScalarAdmission & ~Copyable>(source: OriginalExactNativeBoundarySource,
        loops: [OriginalNativeBoundaryDomain.Loop],using admission: inout A
    ) throws(NativeExactRelationFailure) {
        do {
            try admission.checkpoint()
            guard !loops.isEmpty,loops.contains(where:{ !$0.isInner }) else { throw NativeExactRelationFailure.invalidDomain }
            let validator = try OriginalExactBoundaryCompiler(field:source.surfaceCover.space.frame.scalarField,using:&admission)
            try validator.validate(loops,using:&admission)
            let fields = MemoryLayout<OriginalExactNativeBoundarySource>.stride.addingReportingOverflow(MemoryLayout<[OriginalNativeBoundaryDomain.Loop]>.stride)
            let bytes = fields.partialValue.addingReportingOverflow(2*MemoryLayout<UInt>.stride)
            guard !fields.overflow,!bytes.overflow else { throw ExactScalarFailure.countOverflow }
            try admission.retainStorage(bytes:bytes.partialValue)
            self.source = source;self.loops = loops
            try admission.checkpoint()
        } catch { throw .preserving(error) }
    }
}
