#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

/// Complete requested-domain cover from a sealed whole normalized generator family.
public protocol OriginalRevolutionDomainIssuing: Sendable {
    associatedtype Source: OriginalRevolutionSourceReading
    associatedtype GeneratorSelection: Sendable
    associatedtype Field: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting where Field.Source == Field.Value
    func frame<A: ExactScalarAdmission & ~Copyable>(
        family: borrowing OriginalFiniteRevolutionLawFamily<Source,GeneratorSelection,Field>,
        limits: OriginalDomainIdentityLimits,using admission: inout A
    ) throws(OriginalDomainIdentityFailure) -> OriginalParameterFrame<Source,Field>
    func issue<A: ExactScalarAdmission & ~Copyable>(
        request: borrowing OriginalParameterSelection<Source,Field>,
        family: borrowing OriginalFiniteRevolutionLawFamily<Source,GeneratorSelection,Field>,
        limits: OriginalDomainIdentityLimits,using admission: inout A
    ) throws(OriginalDomainIdentityFailure) -> OriginalRevolutionDomainCover<Source,GeneratorSelection,Field>
}
