#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

extension DefaultOriginalParameterTransporter: OriginalParameterAffineCoordinateQuerying {
    public func affineCoordinates<A: ExactScalarAdmission & ~Copyable>(
        of map: borrowing OriginalParameterTransport<Source,F>,
        limits: OriginalDomainIdentityLimits, using admission: inout A
    ) throws(OriginalDomainIdentityFailure) -> OriginalParameterAffineCoordinates<Source,F> {
        let retained = copy map
        return try OriginalDomainAccess.run(&admission) { a in
            try require(retained,limits,&a)
            // No coefficient payload is generated: the value retains the original word.
            return .init(transport:retained)
        }
    }
}
