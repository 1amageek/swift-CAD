#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Composes all normalized boundary-chart combinations, retaining distinct corner witnesses.
public protocol OriginalFiniteCoonsChartPreparing {
    associatedtype Source: OriginalCoonsSourceReading
    associatedtype BottomSelection: Sendable
    associatedtype TopSelection: Sendable
    associatedtype LeftSelection: Sendable
    associatedtype RightSelection: Sendable
    associatedtype Field: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting where Field.Source == Field.Value
    typealias Selection = OriginalCoonsChartSelection<Source.Bottom, BottomSelection, Source.Top, TopSelection,
        Source.Left, LeftSelection, Source.Right, RightSelection, Field>
    func prepare<A: ExactScalarAdmission & ~Copyable>(source: borrowing OriginalSourceBinding<Source>,
        bottom: borrowing [OriginalCoonsBoundarySelection<Source.Bottom, BottomSelection, Field>],
        top: borrowing [OriginalCoonsBoundarySelection<Source.Top, TopSelection, Field>],
        left: borrowing [OriginalCoonsBoundarySelection<Source.Left, LeftSelection, Field>],
        right: borrowing [OriginalCoonsBoundarySelection<Source.Right, RightSelection, Field>],
        field: borrowing Field, maximumCharts: Int, limits: OriginalSourceIssuanceLimits,
        using admission: inout A
    ) throws(OriginalSourceIssuanceFailure) -> [OriginalRationalChartReceipt<Source, Selection, Field>]
}
