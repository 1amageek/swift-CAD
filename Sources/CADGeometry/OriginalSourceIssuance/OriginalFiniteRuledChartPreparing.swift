#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Enumerates every compatible boundary chart under one cumulative admission.
public protocol OriginalFiniteRuledChartPreparing {
    associatedtype Source: OriginalRuledSourceReading
    associatedtype FirstSelection: Sendable
    associatedtype SecondSelection: Sendable
    associatedtype Field: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting
        where Field.Source == Field.Value
    typealias Selection = OriginalRuledChartSelection<Source.First, FirstSelection, Source.Second, SecondSelection, Field>
    func prepare<A: ExactScalarAdmission & ~Copyable>(source: borrowing OriginalSourceBinding<Source>,
        first: borrowing [OriginalRationalChartReceipt<Source.First, FirstSelection, Field>],
        second: borrowing [OriginalRationalChartReceipt<Source.Second, SecondSelection, Field>],
        field: borrowing Field, maximumCharts: Int, limits: OriginalSourceIssuanceLimits,
        using admission: inout A
    ) throws(OriginalSourceIssuanceFailure) -> [OriginalRationalChartReceipt<Source, Selection, Field>]
}
