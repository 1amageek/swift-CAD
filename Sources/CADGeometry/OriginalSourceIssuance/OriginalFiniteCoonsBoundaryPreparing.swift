#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Selects genuine corner charts independently of each interior position chart.
public protocol OriginalFiniteCoonsBoundaryPreparing {
    associatedtype Source: Sendable
    associatedtype Selection: Sendable
    associatedtype Field: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting where Field.Source == Field.Value
    func prepare<A: ExactScalarAdmission & ~Copyable>(source: borrowing OriginalSourceBinding<Source>,
        curves: borrowing [OriginalRationalChartReceipt<Source, Selection, Field>], field: borrowing Field,
        limits: OriginalSourceIssuanceLimits, using admission: inout A
    ) throws(OriginalSourceIssuanceFailure) -> [OriginalCoonsBoundarySelection<Source, Selection, Field>]
}
