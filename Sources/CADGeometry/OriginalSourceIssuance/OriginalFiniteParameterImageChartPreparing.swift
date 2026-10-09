#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Preserves every issued child chart and its original parameter correspondence.
public protocol OriginalFiniteParameterImageChartPreparing {
    associatedtype Source: OriginalParameterImageSourceReading
    associatedtype ChildSelection: Sendable
    associatedtype Field: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting
        where Field.Source == Field.Value
    typealias Selection = OriginalParameterImageChartSelection<Source.Child, ChildSelection, Field>
    func prepare<A: ExactScalarAdmission & ~Copyable>(source: borrowing OriginalSourceBinding<Source>,
        children: borrowing [OriginalRationalChartReceipt<Source.Child, ChildSelection, Field>],
        field: borrowing Field, maximumCharts: Int, limits: OriginalSourceIssuanceLimits,
        using admission: inout A
    ) throws(OriginalSourceIssuanceFailure) -> [OriginalRationalChartReceipt<Source, Selection, Field>]
}
