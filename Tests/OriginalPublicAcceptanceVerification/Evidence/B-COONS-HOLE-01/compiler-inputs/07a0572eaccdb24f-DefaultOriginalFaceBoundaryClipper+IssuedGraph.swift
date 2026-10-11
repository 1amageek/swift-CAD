import CADCore
import CADGeometry
import CADTopology
import HashTreeCollections

extension DefaultOriginalFaceBoundaryClipper: OriginalIssuedGraphFaceBoundaryClipping {
    public func clip<S: Sendable, E: Sendable, C: Sendable, T: Sendable, F: Sendable, D: Sendable,
        A: ExactScalarAdmission & ~Copyable>(
        _ source: OriginalIssuedGraphBoundarySource<S, E, C, T, F, D>, to faceID: FaceID,
        in original: ValidatedBRepModel, selection: OriginalNativeBoundaryDomain.Selection = .closed,
        domainLimits: OriginalDomainIdentityLimits, cellLimits: ExactRealCellLimits,
        topologyLimits: ExactRealTopologyLimits, using admission: inout A
    ) throws(NativeExactRelationFailure) -> OriginalIssuedGraphFaceClippedParameters<S, E, C, T, F, D> {
        try clip(source, to: faceID, in: original, selection: selection,
            consumer: DefaultOriginalIssuedGraphBoundaryClipper<S, E, C, T, F, D>(),
            domainLimits: domainLimits, cellLimits: cellLimits, topologyLimits: topologyLimits, using: &admission)
    }

    public func clip<S: Sendable, E: Sendable, C: Sendable, T: Sendable, F: Sendable, D: Sendable,
        Consumer: OriginalIssuedGraphBoundaryClipping, A: ExactScalarAdmission & ~Copyable>(
        _ source: OriginalIssuedGraphBoundarySource<S, E, C, T, F, D>, to faceID: FaceID,
        in original: ValidatedBRepModel, selection: OriginalNativeBoundaryDomain.Selection, consumer: Consumer,
        domainLimits: OriginalDomainIdentityLimits, cellLimits: ExactRealCellLimits,
        topologyLimits: ExactRealTopologyLimits, using admission: inout A
    ) throws(NativeExactRelationFailure) -> OriginalIssuedGraphFaceClippedParameters<S, E, C, T, F, D>
        where Consumer.First == S, Consumer.FirstEvidence == E, Consumer.FirstCover == C,
              Consumer.Second == T, Consumer.SecondEvidence == F, Consumer.SecondCover == D {
        do {
            try admission.checkpoint()
            guard original.validationLevel != .modeling, let face = original.model.faces[faceID],
                let stored = original.model.geometry.surfaces[face.surfaceID],
                try source.matches(stored, limits: domainLimits, using: &admission) else {
                throw KernelError(phase: .geometry, code: .invalidInput, tolerance: original.tolerance,
                    message: "The original face does not own the selected issued graph support.")
            }
            let loops = try OriginalExactFaceBoundaryLoops(face: face, original: original, using: &admission)
            let boundary = try OriginalIssuedGraphBoundaryDomain(source: source, loops: loops.directed, using: &admission)
            let selected = try consumer.clip(boundary, selection: selection, domainLimits: domainLimits,
                cellLimits: cellLimits, topologyLimits: topologyLimits, using: &admission)
            guard selected.boundary === boundary, selected.selection == selection else { throw NativeExactRelationFailure.invalidDomain }
            try admission.retainStorage(bytes: exactScalarPayloadBytes(count: 1,
                of: OriginalIssuedGraphFaceClippedParameters<S, E, C, T, F, D>.self))
            let result = OriginalIssuedGraphFaceClippedParameters(original: original, faceID: faceID,
                loops: loops.retained, parameters: selected)
            try admission.checkpoint()
            return result
        } catch { throw .preserving(error) }
    }
}
