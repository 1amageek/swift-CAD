#if L6_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
import L4
import L5
#endif

public struct ExactGeometricRelation<Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: Sendable where Base.Source == Base.Value {
    let owner: ExactGeometricRelationStorage<Base>
    public var original: ExactParametricRelation<Base> { owner.payload.original }
    public var evidenceKind: ExactGeometricEvidenceKind { owner.payload.kind }
    public var strata: ExactGeometricStratumView<Base> { .init(owner: owner) }
    public var curveParameterSpans: [ExactCurveParameterSpan<Base>] { owner.payload.spans }
    public var isEmpty: Bool { owner.payload.records.isEmpty }
    public var graph: ExactRealCellPullback<Base>? { owner.payload.pullback }
    public var mapProofs: [ExactPolynomial<ExactAlgebraicScalarDomain<Base>>] { owner.payload.proofs }
    public var depth: ExactScalarDepth { owner.payload.depth }
    init(owner: ExactGeometricRelationStorage<Base>) { self.owner = owner }

    public func identifier(at ordinal: Int) throws(ExactGeometricRelationFailure) -> ExactGeometricStratumID<Base> {
        guard ordinal >= 0, ordinal < strata.count else { throw .foreignHandle }
        return .init(owner: owner, ordinal: ordinal)
    }
    public func sourceCell(of handle: ExactGeometricStratumID<Base>) throws(ExactGeometricRelationFailure) -> ExactRealCellID<Base> {
        guard handle.owner === owner, handle.ordinal >= 0, handle.ordinal < strata.count else { throw .foreignHandle }
        return original.selection.cells[owner.payload.sourceOrdinals[handle.ordinal]]
    }

    public borrowing func withStrata<Result: ~Copyable, Failure: Error>(
        _ body: (Span<ExactGeometricStratumRecord>) throws(Failure) -> Result
    ) throws(Failure) -> Result {
        let records = owner.payload.records
        return try body(records.span)
    }
}
