#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

/// Checked affine words for consumers that compile parameter-space predicates.
public protocol OriginalParameterAffineCoordinateQuerying: OriginalParameterTransporting {
    func affineCoordinates<A: ExactScalarAdmission & ~Copyable>(
        of map: borrowing OriginalParameterTransport<Source,Field>,
        limits: OriginalDomainIdentityLimits, using admission: inout A
    ) throws(OriginalDomainIdentityFailure) -> OriginalParameterAffineCoordinates<Source,Field>
}
