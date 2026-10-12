#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

public protocol OriginalRevolutionLawIssuing {
    associatedtype Source: OriginalRevolutionSourceReading
    associatedtype GeneratorSelection: Sendable
    associatedtype Field: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting where Field.Source == Field.Value
    func issue<A: ExactScalarAdmission & ~Copyable>(source: borrowing OriginalSourceBinding<Source>,
        generator: borrowing OriginalRationalChartReceipt<Source.Generator,GeneratorSelection,Field>,
        field: borrowing Field,axisLength: Field.Value,limits: OriginalSourceIssuanceLimits,
        using admission: inout A) throws(OriginalSourceIssuanceFailure) -> OriginalRevolutionLawReceipt<Source,GeneratorSelection,Field>
}
