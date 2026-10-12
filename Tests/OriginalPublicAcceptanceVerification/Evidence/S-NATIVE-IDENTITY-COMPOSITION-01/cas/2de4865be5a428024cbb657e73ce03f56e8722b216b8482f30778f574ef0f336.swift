#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

/// Consumes source-certified analytic periods and constant fibers; it proves no new shape law.
public protocol OriginalAnalyticParameterIdentityIssuing: OriginalParameterIdentityIssuing
where Source: OriginalAnalyticCoordinateReading, Field: ExactScalarImporting {
    func periodic<A: ExactScalarAdmission & ~Copyable>(cover: borrowing OriginalAnalyticDomainCover<Source,Field>,
        from selected: borrowing OriginalParameterSelection<Source,Field>,axis: Int,cycle: OriginalParameterCycle,
        limits: OriginalDomainIdentityLimits,using admission: inout A)
        throws(OriginalDomainIdentityFailure) -> OriginalParameterIdentity<Source,Field>
    func collapsed<A: ExactScalarAdmission & ~Copyable>(cover: borrowing OriginalAnalyticDomainCover<Source,Field>,
        on selected: borrowing OriginalParameterSelection<Source,Field>,fiber: Int,
        limits: OriginalDomainIdentityLimits,using admission: inout A)
        throws(OriginalDomainIdentityFailure) -> OriginalParameterIdentity<Source,Field>
}
