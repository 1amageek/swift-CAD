#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

public protocol OriginalGuideDomainIssuing: Sendable {
    associatedtype Source: OriginalGuideSourceReading
    associatedtype ChildSelection: Sendable
    associatedtype Field: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting where Field.Source == Field.Value
    func frame<A: ExactScalarAdmission & ~Copyable>(family: borrowing OriginalFiniteGuideChartFamily<Source,ChildSelection,Field>,
        limits: OriginalDomainIdentityLimits,using admission: inout A)
        throws(OriginalDomainIdentityFailure) -> OriginalParameterFrame<Source,Field>
    func issue<A: ExactScalarAdmission & ~Copyable>(request: borrowing OriginalParameterSelection<Source,Field>,
        family: borrowing OriginalFiniteGuideChartFamily<Source,ChildSelection,Field>,limits: OriginalDomainIdentityLimits,
        using admission: inout A) throws(OriginalDomainIdentityFailure) -> OriginalGuideDomainCover<Source,ChildSelection,Field>
}
