/// Issues a whole-support exclusion from the original implicit common-root relation.
public protocol OriginalImplicitHostPlaneSeparationIssuing: Sendable {
    func issue<A: ExactScalarAdmission & ~Copyable>(
        source: borrowing OriginalSourceBinding<OriginalImplicitCurveSnapshot>,
        plane: borrowing OriginalPlaneBasisReceipt<OriginalPlaneSnapshot, OriginalExactScalarDomain>,
        maximumCells: Int, limits: OriginalSourceIssuanceLimits, using a: inout A
    ) throws(OriginalSourceIssuanceFailure) -> OriginalImplicitHostPlaneSeparationReceipt
}
