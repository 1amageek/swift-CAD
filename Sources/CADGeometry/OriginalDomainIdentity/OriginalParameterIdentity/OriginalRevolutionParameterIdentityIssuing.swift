#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

/// Consumes the source period and preserves the selected original UV scope.
public protocol OriginalRevolutionParameterIdentityIssuing: OriginalParameterIdentityIssuing
where Source: OriginalRevolutionSourceReading, Field: ExactScalarImporting, Field.Source == Field.Value {
    func periodic<C: Sendable,A: ExactScalarAdmission & ~Copyable>(cover: borrowing OriginalRevolutionDomainCover<Source,C,Field>,
        from selected: borrowing OriginalParameterSelection<Source,Field>,cycle: OriginalParameterCycle,
        limits: OriginalDomainIdentityLimits,using admission: inout A)
        throws(OriginalDomainIdentityFailure) -> OriginalParameterIdentity<Source,Field>
}
