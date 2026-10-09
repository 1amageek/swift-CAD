#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

public struct DefaultOriginalParameterImageDomainIssuer<S: OriginalParameterImageSourceReading,
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
            let word = source.original, n = child.support.arity, f = child.support.frame.scalarField
            guard word.originalChild.owns(child.support.frame.owner.anchor) else { throw OriginalDomainIdentityFailure.foreignOwner }
            guard word.parameterCount == n else { throw OriginalDomainIdentityFailure.invalidDomain }
            try OriginalDomainAccess.storage(n, Int.self, &a)
            try OriginalDomainAccess.storage(try OriginalDomainAccess.multiplied(n, 2), C.Field.Value.self, &a)
            var permutation: [Int] = [], gains: [C.Field.Value] = [], offsets: [C.Field.Value] = []
            permutation.reserveCapacity(n); gains.reserveCapacity(n); offsets.reserveCapacity(n)
            for axis in 0..<n {
                try a.consumeWork(1)
                permutation.append(word.childAxis(forOriginalAxis: axis))
                let g = try word.originalGain(in: axis, field: f, using: &a)
                guard try f.sign(of: g, using: &a) != .zero else { throw OriginalDomainIdentityFailure.singularTransport }
                gains.append(try f.dividing(f.integer(1, using: &a), g, using: &a))
                offsets.append(try f.negated(f.dividing(word.originalOffset(in: axis, field: f, using: &a), g, using: &a), using: &a))
            }
            return try .prepared(source: source, child: child, childSupport: child.support, permutation: permutation,
                gains: gains, offsets: offsets, requested: requested, limits: limits, using: &a)
        }
    }
}
