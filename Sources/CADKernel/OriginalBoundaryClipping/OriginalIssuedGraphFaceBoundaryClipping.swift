import CADCore
import CADGeometry
import CADTopology

/// Clips a complete issued graph to a validated original face without changing its source.
public protocol OriginalIssuedGraphFaceBoundaryClipping: Sendable {
    func clip<S: Sendable, E: Sendable, C: Sendable, T: Sendable, F: Sendable, D: Sendable,
        Consumer: OriginalIssuedGraphBoundaryClipping, A: ExactScalarAdmission & ~Copyable>(
        _ source: OriginalIssuedGraphBoundarySource<S, E, C, T, F, D>, to faceID: FaceID,
        in original: ValidatedBRepModel, selection: OriginalNativeBoundaryDomain.Selection, consumer: Consumer,
        domainLimits: OriginalDomainIdentityLimits, cellLimits: ExactRealCellLimits,
        topologyLimits: ExactRealTopologyLimits, using admission: inout A
    ) throws(NativeExactRelationFailure) -> OriginalIssuedGraphFaceClippedParameters<S, E, C, T, F, D>
        where Consumer.First == S, Consumer.FirstEvidence == E, Consumer.FirstCover == C,
              Consumer.Second == T, Consumer.SecondEvidence == F, Consumer.SecondCover == D
}
