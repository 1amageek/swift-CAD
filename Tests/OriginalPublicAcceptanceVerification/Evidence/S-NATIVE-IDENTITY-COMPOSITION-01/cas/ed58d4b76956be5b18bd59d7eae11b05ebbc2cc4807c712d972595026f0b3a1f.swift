#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

public protocol OriginalIntrinsicParameterIdentityIssuing: OriginalParameterIdentityIssuing where Source: OriginalIntrinsicSphereSourceReading {
    func periodic<A: ExactScalarAdmission & ~Copyable>(cover: borrowing OriginalIntrinsicSphereDomainCover<Source,Field>,
        from selected: borrowing OriginalParameterSelection<Source,Field>,cycle: OriginalParameterCycle,
        limits: OriginalDomainIdentityLimits,using admission: inout A) throws(OriginalDomainIdentityFailure) -> OriginalParameterIdentity<Source,Field>
    func intrinsicPole<A: ExactScalarAdmission & ~Copyable>(cover: borrowing OriginalIntrinsicSphereDomainCover<Source,Field>,
        on selected: borrowing OriginalParameterSelection<Source,Field>,latitude: Field.Value,limits: OriginalDomainIdentityLimits,
        using admission: inout A) throws(OriginalDomainIdentityFailure) -> OriginalParameterIdentity<Source,Field>
}
