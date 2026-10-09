#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Preserves every issued child chart and its original parameter correspondence.
public protocol OriginalFiniteSpatialChartPreparing {
    associatedtype Source: OriginalSpatialSourceReading
    associatedtype ChildSelection: Sendable
    associatedtype Field: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting
        where Field.Source == Field.Value, Source.Coefficient == Field.Value
    typealias Selection = OriginalSpatialChartSelection<Source.Child, ChildSelection, Field>
    func prepare<C: OriginalSourceCoefficientImporting, A: ExactScalarAdmission & ~Copyable>(source: borrowing OriginalSourceBinding<Source>,
        children: borrowing [OriginalRationalChartReceipt<Source.Child, ChildSelection, Field>],
        field: borrowing Field, coefficients: borrowing C, maximumCharts: Int, limits: OriginalSourceIssuanceLimits,
        using admission: inout A
    ) throws(OriginalSourceIssuanceFailure) -> [OriginalRationalChartReceipt<Source, Selection, Field>] where C.Field == Field
}
