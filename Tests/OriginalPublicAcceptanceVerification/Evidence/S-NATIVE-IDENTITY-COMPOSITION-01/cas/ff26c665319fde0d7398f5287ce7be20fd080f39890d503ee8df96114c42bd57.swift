#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

/// Evaluates an admitted original map in a compatible query arithmetic field.
public protocol OriginalParameterFieldQueryTransporting: OriginalParameterTransporting {
    func forward<A: ExactScalarAdmission & ~Copyable>(_ tuple: borrowing [Field.Value],
        through map: borrowing OriginalParameterTransport<Source,Field>, queryField: Field,
        limits: OriginalDomainIdentityLimits, using admission: inout A)
        throws(OriginalDomainIdentityFailure) -> [Field.Value]
}
