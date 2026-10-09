#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

/// Authored directed endpoints select the child before normalized traversal.
public struct DefaultOriginalTraversalDomainIssuer<S: OriginalTraversalSourceReading,
    C: OriginalChartFamilyQuerying>: OriginalAffineChildDomainIssuing
    where S.Child == C.Source, C.Field: ExactScalarImporting, S.Coefficient == C.Field.Source {
    public typealias Source = S
    public typealias ChildFamily = C
    public init() {}
    public func issue<A: ExactScalarAdmission & ~Copyable>(source: borrowing OriginalSourceBinding<S>,
        child: borrowing C, requested: borrowing [[ExactParameterInterval<C.Field.Value>]]? = nil,
        limits: OriginalDomainIdentityLimits, using admission: inout A
    ) throws(OriginalDomainIdentityFailure) -> OriginalAffineChildDomainCover<S, C> {
        let source = copy source, child = copy child, requested = copy requested
        return try OriginalDomainAccess.run(&admission) { a in
            let word = source.original, f = child.support.frame.scalarField
            guard word.originalChild.owns(child.support.frame.owner.anchor) else { throw OriginalDomainIdentityFailure.foreignOwner }
            guard child.support.arity == 1 else { throw OriginalDomainIdentityFailure.invalidDomain }
            let start = try f.importing(word.originalStart, using: &a), end = try f.importing(word.originalEnd, using: &a)
            let extent = try f.subtracting(end, start, using: &a), sign = try f.sign(of: extent, using: &a)
            guard sign != .zero else { throw OriginalDomainIdentityFailure.singularTransport }
            let interval = try child.support.frame.axisDomains[0].interval(lower: .finite(sign == .positive ? start : end),
                upper: .finite(sign == .positive ? end : start), using: &a)
            try OriginalDomainAccess.storage(1, [ExactParameterInterval<C.Field.Value>].self, &a)
            try OriginalDomainAccess.storage(1, ExactParameterInterval<C.Field.Value>.self, &a)
            let selected = try child.support.frame.selection(intervals: [[interval]], limits: limits, using: &a)
            let support = try selected.intersection(child.support, limits: limits, using: &a)
            try OriginalDomainAccess.storage(1, Int.self, &a)
            try OriginalDomainAccess.storage(2, C.Field.Value.self, &a)
            return try .prepared(source: source, child: child, childSupport: support, permutation: [0],
                gains: [f.dividing(f.integer(1, using: &a), extent, using: &a)],
                offsets: [f.negated(f.dividing(start, extent, using: &a), using: &a)],
                requested: requested, limits: limits, using: &a)
        }
    }
}
