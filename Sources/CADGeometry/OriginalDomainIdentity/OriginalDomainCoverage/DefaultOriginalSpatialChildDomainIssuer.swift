#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

/// Spatial words change geometry, not their descendant parameter domain.
public struct DefaultOriginalSpatialChildDomainIssuer<S: OriginalSpatialSourceReading,
    C: OriginalChartFamilyQuerying>: OriginalAffineChildDomainIssuing where S.Child == C.Source {
    public typealias Source = S
    public typealias ChildFamily = C
    public init() {}
    public func issue<A: ExactScalarAdmission & ~Copyable>(source: borrowing OriginalSourceBinding<S>,
        child: borrowing C, requested: borrowing [[ExactParameterInterval<C.Field.Value>]]? = nil,
        limits: OriginalDomainIdentityLimits, using admission: inout A
    ) throws(OriginalDomainIdentityFailure) -> OriginalAffineChildDomainCover<S, C> {
        let source = copy source, child = copy child, requested = copy requested
        return try OriginalDomainAccess.run(&admission) { a in
            guard source.original.originalChild.owns(child.support.frame.owner.anchor) else { throw OriginalDomainIdentityFailure.foreignOwner }
            let n = child.support.arity, f = child.support.frame.scalarField
            try OriginalDomainAccess.storage(n, Int.self, &a)
            try OriginalDomainAccess.storage(try OriginalDomainAccess.multiplied(n, 2), C.Field.Value.self, &a)
            let permutation = Array(0..<n)
            let gains = Array(repeating: try f.integer(1, using: &a), count: n)
            let offsets = Array(repeating: try f.integer(0, using: &a), count: n)
            return try .prepared(source: source, child: child, childSupport: child.support, permutation: permutation,
                gains: gains, offsets: offsets, requested: requested, limits: limits, using: &a)
        }
    }
}
