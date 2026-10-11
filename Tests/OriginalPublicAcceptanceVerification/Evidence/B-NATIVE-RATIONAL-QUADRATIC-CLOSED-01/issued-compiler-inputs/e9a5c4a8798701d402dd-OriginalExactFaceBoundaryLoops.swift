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

/// Retains every original loop and authored pcurve without a second reversal.
struct OriginalExactFaceBoundaryLoops {
    let retained: [Loop]
    let directed: [OriginalNativeBoundaryDomain.Loop]
    init<A: ExactScalarAdmission & ~Copyable>(face: Face,original: ValidatedBRepModel,using a: inout A) throws {
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:face.loops.count,of:Loop.self))
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:face.loops.count,of:OriginalNativeBoundaryDomain.Loop.self))
        var retained: [Loop] = [],directed: [OriginalNativeBoundaryDomain.Loop] = []
        retained.reserveCapacity(face.loops.count);directed.reserveCapacity(face.loops.count)
        for identifier in face.loops {
            try a.consumeWork(1)
            guard let loop = original.model.loops[identifier],loop.id == identifier,!loop.coedges.isEmpty else {
                throw Self.failure(.missingReference,original.tolerance,"An original exact boundary loop is absent or empty.")
            }
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:loop.coedges.count,of:SurfaceParameterCurve.self))
            var curves: [SurfaceParameterCurve] = [];curves.reserveCapacity(loop.coedges.count)
            for coedge in loop.coedges {
                try a.consumeWork(1)
                guard let edge = original.model.edges[coedge.edgeID],original.model.geometry.curves[edge.curveID] != nil,
                    original.model.vertices[edge.startVertexID] != nil,original.model.vertices[edge.endVertexID] != nil else {
                    throw Self.failure(.missingReference,original.tolerance,"An original exact boundary lost its edge or endpoint owner.")
                }
                // FIXME(INCOMPLETE_IMPLEMENTATION): Missing authored pcurves require an
                // original complete correspondence issuer before this public exact route can succeed.
                guard let curve = coedge.surfaceParameterCurve else {
                    throw Self.failure(.unsupportedCapability,original.tolerance,"An exact boundary needs its retained authored lifted pcurve.")
                }
                curves.append(curve)
            }
            retained.append(loop);directed.append(.init(isInner:loop.role == .inner,curves:curves))
        }
        self.retained = retained;self.directed = directed
        try a.checkpoint()
    }
    private static func failure(_ code: KernelErrorCode,_ tolerance: ModelingTolerance,_ message: String) -> KernelError {
        .init(phase:.geometry,code:code,tolerance:tolerance,message:message)
    }
}
