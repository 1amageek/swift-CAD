#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

/// Complete selected UV enclosure with the original auxiliary-fiber guards retained.
public struct OriginalRollingBallGraphDomainCover<S: OriginalRollingBallChildSourceReading,E: Sendable,C: Sendable>: Sendable {
    public typealias Field = OriginalExactScalarDomain
    public typealias Member = OriginalDomainBoundParametricGraph<S,Field,OriginalRollingBallChildGraphEvidence<S,E>>
    public let family: OriginalFiniteRollingBallGraphs<S,E,C>
    public let enclosingSupport: OriginalParameterSelection<S,Field>
    public let request: OriginalParameterSelection<S,Field>
    public let effectiveEnclosure: OriginalParameterSelection<S,Field>
    public var source: OriginalSourceBinding<S> { family.source }
    public var templateCount: Int { family.graphs.count }
    init(family: OriginalFiniteRollingBallGraphs<S,E,C>,enclosingSupport: OriginalParameterSelection<S,Field>,
        request: OriginalParameterSelection<S,Field>,effectiveEnclosure: OriginalParameterSelection<S,Field>) {
        self.family = family; self.enclosingSupport = enclosingSupport
        self.request = request; self.effectiveEnclosure = effectiveEnclosure
    }
    public func member<A: ExactScalarAdmission & ~Copyable>(template: Int,limits: OriginalDomainIdentityLimits,
        using admission: inout A) throws(OriginalDomainIdentityFailure) -> Member {
        try OriginalDomainAccess.run(&admission) { a in
            try DefaultOriginalRollingBallGraphDomainIssuer<S,E,C>().admitted(family,limits:limits,&a)
            guard family.graphs.indices.contains(template) else { throw OriginalDomainIdentityFailure.invalidDomain }
            return try DefaultOriginalParametricGraphDomainBinder().bind(graph:family.graphs[template],
                request:effectiveEnclosure,limits:limits,using:&a)
        }
    }
    public func liftedPositionIncidents<A: ExactScalarAdmission & ~Copyable>(at tuple: borrowing [Field.Value],
        limits: OriginalDomainIdentityLimits,using admission: inout A)
        throws(OriginalDomainIdentityFailure) -> [Member] {
        let tuple = copy tuple
        return try OriginalDomainAccess.run(&admission) { a in
            try DefaultOriginalRollingBallGraphDomainIssuer<S,E,C>().admitted(family,limits:limits,&a)
            var matchesLayout=false
            for graph in family.graphs {
                try a.consumeWork(1)
                if tuple.count == graph.layout.variableCount { matchesLayout=true }
            }
            guard matchesLayout else { throw OriginalDomainIdentityFailure.invalidDomain }
            try OriginalDomainAccess.storage(tuple.count,Field.Value.self,&a)
            var coordinates:[Field.Value]=[];coordinates.reserveCapacity(tuple.count)
            for value in tuple { try a.consumeWork(1);coordinates.append(try family.field.importing(value,using:&a)) }
            try OriginalDomainAccess.storage(2,Field.Value.self,&a)
            let parameters = [coordinates[0],coordinates[1]]
            guard try effectiveEnclosure.contains(parameters,limits:limits,using:&a) else { return [] }
            var result: [Member] = []
            for template in family.graphs.indices {
                try a.consumeWork(1)
                if family.graphs[template].layout.variableCount == coordinates.count,try family.graphs[template].admits(coordinates,limits:limits.source,using:&a) {
                    guard result.count < limits.maximumCharts else { throw OriginalDomainIdentityFailure.chartLimit }
                    try OriginalDomainAccess.storage(1,Member.self,&a)
                    result.append(try member(template:template,limits:limits,using:&a))
                }
            }
            return result
        }
    }
}
