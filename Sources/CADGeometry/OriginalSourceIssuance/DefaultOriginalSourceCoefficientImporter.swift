#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Preserves the existing ordinary field-compatibility contract.
public struct DefaultOriginalSourceCoefficientImporter<Field: ExactScalarArithmetic &
    ExactScalarOrdering & ExactScalarImporting>: OriginalSourceCoefficientImporting {
    public init() {}
    public func importing<A: ExactScalarAdmission & ~Copyable>(
        _ value: borrowing Field.Source, into field: borrowing Field, using admission: inout A
    ) throws(ExactScalarFailure) -> Field.Value {
        try field.importing(copy value, using: &admission)
    }
}
