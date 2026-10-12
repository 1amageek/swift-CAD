#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

/// Coordinates declared on a retained source. Creating a frame does not prove a
/// source law or whole-source support; checked family issuers own that obligation.
public struct OriginalParameterFrame<Source: Sendable, F: ExactScalarArithmetic & ExactScalarOrdering>: Sendable {
    final class Owner: Sendable {
        let anchor: OriginalSourceChart<Source, Int>
        let field: F
        let domains: [ExactParameterDomain<F>]
        let support: [ExactParameterSet<F>]
        let semantics: [OriginalCoordinateSemantics]
        init(anchor: OriginalSourceChart<Source, Int>, field: F, domains: [ExactParameterDomain<F>],
            support: [ExactParameterSet<F>], semantics: [OriginalCoordinateSemantics]) {
            self.anchor = anchor; self.field = field; self.domains = domains
            self.support = support; self.semantics = semantics
        }
    }
    let owner: Owner
    public var source: OriginalSourceBinding<Source> { owner.anchor.binding }
    public var scalarField: F { owner.field }
    public var axisDomains: ArraySlice<ExactParameterDomain<F>> { owner.domains[...] }
    public var arity: Int { owner.support.count }
    public var axes: ArraySlice<ExactParameterSet<F>> { owner.support[...] }
    public var coordinateSemantics: ArraySlice<OriginalCoordinateSemantics> { owner.semantics[...] }
    init(owner: Owner) { self.owner = owner }
    func require<A: ExactScalarAdmission & ~Copyable>(_ limits: OriginalDomainIdentityLimits, _ a: inout A) throws {
        guard source.sourceDepth <= limits.source.remainingSourceDepth else { throw OriginalDomainIdentityFailure.sourceDepthLimit }
        _ = try owner.field.integer(0,using:&a)
        for axis in owner.support {
            try a.consumeWork(1); try a.admitDepth(value: axis.depth.value, coefficient: axis.depth.coefficient)
        }
    }
    public func selection<A: ExactScalarAdmission & ~Copyable>(
        intervals: borrowing [[ExactParameterInterval<F.Value>]], limits: OriginalDomainIdentityLimits,
        using admission: inout A) throws(OriginalDomainIdentityFailure) -> OriginalParameterSelection<Source,F> {
        let input = copy intervals
        return try OriginalDomainAccess.run(&admission) { a in
            try require(limits,&a)
            guard input.count == arity else { throw OriginalDomainIdentityFailure.invalidDomain }
            try OriginalDomainAccess.storage(arity,ExactParameterSet<F>.self,&a)
            var axes: [ExactParameterSet<F>] = []; axes.reserveCapacity(arity)
            for index in input.indices {
                try a.consumeWork(1); axes.append(try owner.domains[index].set(intervals:input[index],using:&a))
            }
            return try .init(frame:self,axes:axes,using:&a)
        }
    }
    public func fullSelection<A: ExactScalarAdmission & ~Copyable>(limits: OriginalDomainIdentityLimits,
        using admission: inout A) throws(OriginalDomainIdentityFailure) -> OriginalParameterSelection<Source,F> {
        try OriginalDomainAccess.run(&admission) { a in try require(limits,&a); return try .init(frame:self,axes:owner.support,using:&a) }
    }
}
