#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

extension DefaultOriginalParameterTransporter: OriginalParameterFieldQueryTransporting {
    public func forward<A: ExactScalarAdmission & ~Copyable>(_ tuple: borrowing [F.Value],
        through map: borrowing OriginalParameterTransport<Source,F>, queryField: F,
        limits: OriginalDomainIdentityLimits, using admission: inout A)
        throws(OriginalDomainIdentityFailure) -> [F.Value] {
        let input = copy tuple, map = copy map
        return try OriginalDomainAccess.run(&admission) { a in
            try require(map, limits, &a)
            _ = try queryField.sign(of: map.image.frame.scalarField.integer(1, using: &a), using: &a)
            guard try map.local.contains(input, queryField: queryField, limits: limits, using: &a) else {
                throw OriginalDomainIdentityFailure.outsideSupport
            }
            try OriginalDomainAccess.storage(input.count, F.Value.self, &a)
            var output: [F.Value] = []; output.reserveCapacity(input.count)
            for i in input.indices {
                try a.consumeWork(1)
                output.append(try queryField.adding(queryField.multiplying(input[map.permutation[i]],
                    map.gains[i], using: &a), map.offsets[i], using: &a))
            }
            return output
        }
    }
}
