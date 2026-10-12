#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

public protocol OriginalPeriodicParameterIdentityIssuing: OriginalParameterIdentityIssuing where Source: OriginalBSplineSourceReading {
    func periodic<A: ExactScalarAdmission & ~Copyable>(cover: borrowing OriginalBSplineDomainCover<Source,Field>,
        from selected: borrowing OriginalParameterSelection<Source,Field>,axis: Int,cycle: OriginalParameterCycle,
        limits: OriginalDomainIdentityLimits,using admission: inout A) throws(OriginalDomainIdentityFailure) -> OriginalParameterIdentity<Source,Field>
}
