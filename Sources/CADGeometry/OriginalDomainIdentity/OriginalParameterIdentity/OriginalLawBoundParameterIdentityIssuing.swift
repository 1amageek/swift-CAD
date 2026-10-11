#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

public protocol OriginalLawBoundParameterIdentityIssuing: OriginalParameterIdentityIssuing where Field: ExactScalarImporting {
    func declaredBoundary<L: Sendable,R: Sendable,A: ExactScalarAdmission & ~Copyable>(
        declaration: borrowing OriginalRationalSourceBoundaryDeclaration<Source,L,R,Field>,
        scope: borrowing OriginalParameterSelection<Source,Field>,rightFrame: borrowing OriginalParameterFrame<Source,Field>,
        permutation: [Int],gains: [Field.Value],offsets: [Field.Value],
        limits: OriginalDomainIdentityLimits,using admission: inout A)
        throws(OriginalDomainIdentityFailure) -> OriginalParameterIdentity<Source,Field>
}
