#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Imports one original coefficient without changing source or chart ownership.
public protocol OriginalSourceCoefficientImporting: Sendable {
    associatedtype Field: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting
    func importing<A: ExactScalarAdmission & ~Copyable>(
        _ value: borrowing Field.Source, into field: borrowing Field, using admission: inout A
    ) throws(ExactScalarFailure) -> Field.Value
}
