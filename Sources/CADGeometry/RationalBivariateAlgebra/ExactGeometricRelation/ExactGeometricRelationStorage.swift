#if L6_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
import L4
import L5
#endif

struct ExactGeometricRelationPayload<Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: Sendable where Base.Source == Base.Value {
    let original: ExactParametricRelation<Base>
    let kind: ExactGeometricEvidenceKind
    let proofs: [ExactPolynomial<ExactAlgebraicScalarDomain<Base>>]
    let pullback: ExactRealCellPullback<Base>?
    let records: [ExactGeometricStratumRecord]
    let sourceOrdinals: [Int]
    let regionOrdinals: [Int]
    let spans: [ExactCurveParameterSpan<Base>]
    let depth: ExactScalarDepth
}

/// All retained state is immutable; builders cannot reach it after publication.
final class ExactGeometricRelationStorage<Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: Sendable where Base.Source == Base.Value {
    let payload: ExactGeometricRelationPayload<Base>
    init(_ payload: consuming ExactGeometricRelationPayload<Base>) { self.payload = payload }
}
