import HashTreeCollections
import CADCore
import CADGeometry
import CADTopology

/// Binds every unchanged directed coedge to the selected original raw source support.
struct OriginalFaceBoundaryIssuer {
    let domain: OriginalNativeBoundaryDomain
    let loops: [Loop]

    init(source: OriginalNativeBoundaryDomain.Source, faceID: FaceID,
        original: ValidatedBRepModel, usage: inout OriginalQueryExecution) throws {
        try Self.step(&usage)
        guard original.validationLevel != .modeling,
            let face = original.model.faces[faceID],
            let stored = original.model.geometry.surfaces[face.surfaceID],
            case .bSpline(let support) = stored else {
            throw Self.failure(.invalidInput, original.tolerance,
                "Boundary clipping requires an unchanged exact original Native face support.")
        }
        let raw = source.surface
        // Charge all structural scalar comparisons before equality. The immutable
        // support buffer is borrowed; no cloned control net or sampled image is used.
        func charge(_ surface: BSplineSurface3D) throws {
            try Self.step(&usage)
            try usage.consumeWork(8)
            for _ in surface.uKnots { try Self.step(&usage) }
            for _ in surface.vKnots { try Self.step(&usage) }
            for row in surface.controlPoints {
                try Self.step(&usage)
                for _ in row { try usage.consumeWork(3); try Self.step(&usage) }
            }
            for row in surface.weights {
                try Self.step(&usage)
                for _ in row { try Self.step(&usage) }
            }
        }
        try charge(support); try charge(raw)
        guard support == raw else {
            throw Self.failure(.invalidInput, original.tolerance,
                "The selected original face is not the Native raw receipt's unchanged source surface.")
        }
        let expected = source.nativeDomains
        let axis: Int
        switch source { case .curveSurface: axis = 1; case .firstSurface: axis = 0; case .secondSurface: axis = 2 }
        guard expected.indices.contains(axis + 1) else {
            throw Self.failure(.invalidInput, original.tolerance, "The original raw receipt lost its complete native UV domains.")
        }
        // FIXME(INCOMPLETE_IMPLEMENTATION): Periodic/pole supports need their issued lifted
        // chart and seam domains. This original face issuer must not flatten or normalize
        // them into an ordinary closed rectangle and claim complete boundary clipping.
        guard !support.isUPeriodic, !support.isVPeriodic,
            case .closed(let uLower, let uUpper) = support.uDomain,
            case .closed(let vLower, let vUpper) = support.vDomain else {
            throw Self.failure(.unsupportedCapability, original.tolerance,
                "Original face clipping has no complete periodic/pole chart issuer.")
        }
        let lowerU = try ExactRationalCoefficient.originalDouble(uLower, usage: &usage)
        let upperU = try ExactRationalCoefficient.originalDouble(uUpper, usage: &usage)
        let lowerV = try ExactRationalCoefficient.originalDouble(vLower, usage: &usage)
        let upperV = try ExactRationalCoefficient.originalDouble(vUpper, usage: &usage)
        guard expected[axis].lower == lowerU, expected[axis].upper == upperU,
            expected[axis + 1].lower == lowerV, expected[axis + 1].upper == upperV else {
            throw Self.failure(.invalidInput, original.tolerance,
                "Original face clipping cannot replace the raw receipt's native domain identity.")
        }
        try RationalAlgebraStorage.retain(face.loops.count, of: Loop.self, usage: &usage)
        try RationalAlgebraStorage.retain(face.loops.count, of: OriginalNativeBoundaryDomain.Loop.self, usage: &usage)
        var retained: [Loop] = []; retained.reserveCapacity(face.loops.count)
        var directed: [OriginalNativeBoundaryDomain.Loop] = []; directed.reserveCapacity(face.loops.count)
        for loopID in face.loops {
            try Self.step(&usage)
            guard let loop = original.model.loops[loopID], loop.id == loopID, !loop.coedges.isEmpty else {
                throw Self.failure(.missingReference, original.tolerance, "An original face boundary loop is absent or empty.")
            }
            try RationalAlgebraStorage.retain(loop.coedges.count, of: SurfaceParameterCurve.self, usage: &usage)
            var curves: [SurfaceParameterCurve] = []; curves.reserveCapacity(loop.coedges.count)
            for coedge in loop.coedges {
                try Self.step(&usage)
                guard let edge = original.model.edges[coedge.edgeID],
                    original.model.geometry.curves[edge.curveID] != nil,
                    original.model.vertices[edge.startVertexID] != nil,
                    original.model.vertices[edge.endVertexID] != nil else {
                    throw Self.failure(.missingReference, original.tolerance,
                        "An original face boundary has absent coedge geometry or endpoint identity.")
                }
                // FIXME(INCOMPLETE_IMPLEMENTATION): A missing authored pcurve needs a complete
                // same-ledger original correspondence issuer. Endpoint projection or an inferred
                // polygon cannot authorize this public whole-boundary clipping route.
                guard let curve = coedge.surfaceParameterCurve else {
                    throw Self.failure(.unsupportedCapability, original.tolerance,
                        "Original face clipping requires the producer-retained directed pcurve.")
                }
                curves.append(curve)
            }
            retained.append(loop)
            directed.append(.init(isInner: loop.role == .inner, curves: curves))
        }
        let domain = try OriginalNativeBoundaryDomain(source: source, loops: directed, usage: &usage)
        try CurrentTaskCancellationChecker().checkCancellation()
        self.domain = domain; loops = retained
    }
    static func step(_ usage: inout OriginalQueryExecution) throws {
        try CurrentTaskCancellationChecker().checkCancellation()
        try usage.consumeWork(1)
        try CurrentTaskCancellationChecker().checkCancellation()
    }
    private static func failure(_ code: KernelErrorCode, _ tolerance: ModelingTolerance,
        _ message: String) -> KernelError {
        KernelError(phase: .geometry, code: code, tolerance: tolerance, message: message)
    }
}
