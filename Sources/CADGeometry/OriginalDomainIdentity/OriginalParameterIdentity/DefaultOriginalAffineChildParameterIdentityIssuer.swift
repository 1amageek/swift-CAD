#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

public struct DefaultOriginalAffineChildParameterIdentityIssuer<S: Sendable,C: OriginalChartFamilyQuerying>: OriginalAffineChildParameterIdentityIssuing {
    public typealias Source = S
    public typealias ChildFamily = C
    public init() {}
    public func lifted<A: ExactScalarAdmission & ~Copyable>(
        _ identity: borrowing OriginalParameterIdentity<C.Source,C.Field>,
        through cover: borrowing OriginalAffineChildDomainCover<S,C>,
        limits: OriginalDomainIdentityLimits, using admission: inout A
    ) throws(OriginalDomainIdentityFailure) -> OriginalParameterIdentity<S,C.Field> {
        try DefaultOriginalAffinePairedParameterIdentityIssuer<S,C,C>().compose(identity,
            left:copy cover,right:copy cover,leftAction:nil,rightAction:nil,sharedCover:true,limits:limits,using:&admission)
    }
}
