#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

public protocol OriginalOffsetLawIssuing {
    associatedtype Source:OriginalOffsetSourceReading
    associatedtype ChildSelection:Sendable
    associatedtype Field:ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting where Field.Source == Field.Value
    func issue<A:ExactScalarAdmission & ~Copyable>(source:borrowing OriginalSourceBinding<Source>,
        child:borrowing OriginalRationalChartReceipt<Source.Child,ChildSelection,Field>,field:borrowing Field,
        limits:OriginalSourceIssuanceLimits,using a:inout A) throws(OriginalSourceIssuanceFailure)
        -> OriginalOffsetLawReceipt<Source,ChildSelection,Field>
}
