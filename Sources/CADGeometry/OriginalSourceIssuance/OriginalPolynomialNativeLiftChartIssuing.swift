import CADCore

/// Issues a rational child law only when the complete original graph guards hold.
public protocol OriginalPolynomialNativeLiftChartIssuing: Sendable {
    func issue<A: ExactScalarAdmission & ~Copyable>(
        family: borrowing OriginalFiniteNativeSurfaceLiftGraphs<OriginalNativeSurfaceLiftSnapshot>,
        limits: OriginalSourceIssuanceLimits, using admission: inout A
    ) throws(OriginalSourceIssuanceFailure) -> OriginalRationalChartReceipt<
        OriginalNativeSurfaceLiftSnapshot, OriginalPolynomialNativeLiftChart, OriginalExactScalarDomain>
}
