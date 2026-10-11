#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Issues the exact axis section and its complementary exclusion for one original line.
public protocol OriginalRevolutionAxisSectionIssuing {
    associatedtype Source: OriginalRevolutionSourceReading
    associatedtype GeneratorSelection: Sendable
    associatedtype Field: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting where Field.Source == Field.Value
    associatedtype Line: OriginalLinearSourceReading
    func issue<A: ExactScalarAdmission & ~Copyable>(family: borrowing OriginalFiniteRevolutionLawFamily<Source,GeneratorSelection,Field>,
        line: borrowing OriginalSourceBinding<Line>,limits: OriginalSourceIssuanceLimits,using admission: inout A)
        throws(OriginalSourceIssuanceFailure) -> OriginalRevolutionAxisSectionReceipt<Source,GeneratorSelection,Field,Line>
}
