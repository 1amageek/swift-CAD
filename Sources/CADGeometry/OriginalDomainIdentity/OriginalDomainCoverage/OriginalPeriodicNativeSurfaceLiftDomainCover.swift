#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

public struct OriginalPeriodicNativeSurfaceLiftDomainCover<S: OriginalSurfaceLiftSourceReading>: OriginalPeriodicNativeSurfaceLiftDomainQuerying {
    public typealias Source=S
    public typealias Occurrence=OriginalPeriodicNativeSurfaceLiftChartOccurrence<S>
    public let space: OriginalPeriodicNativeSurfaceLiftDomainSpace<S>
    public let enclosingSupport: OriginalParameterSelection<S,OriginalExactScalarDomain>
    public let request: OriginalParameterSelection<S,OriginalExactScalarDomain>
    public let effectiveEnclosure: OriginalParameterSelection<S,OriginalExactScalarDomain>
    public var source: OriginalSourceBinding<S> { space.family.source }
    public var templateCount: Int { space.family.templateCount }
    public var surfaceCycleRank: Int { space.family.integerFamilyRank }
    init(space: OriginalPeriodicNativeSurfaceLiftDomainSpace<S>,enclosingSupport: OriginalParameterSelection<S,OriginalExactScalarDomain>,
        request: OriginalParameterSelection<S,OriginalExactScalarDomain>,effectiveEnclosure: OriginalParameterSelection<S,OriginalExactScalarDomain>) {
        self.space=space;self.enclosingSupport=enclosingSupport;self.request=request;self.effectiveEnclosure=effectiveEnclosure
    }
    public func member<A: ExactScalarAdmission & ~Copyable>(template: Int,cycles: borrowing [OriginalParameterCycle],
        limits: OriginalDomainIdentityLimits,using admission: inout A) throws(OriginalDomainIdentityFailure) -> Occurrence {
        let cycles=copy cycles
        return try OriginalDomainAccess.run(&admission) { a in
            try DefaultOriginalPeriodicNativeSurfaceLiftDomainIssuer<S>().admitted(space.family,limits:limits,&a)
            guard (0..<templateCount).contains(template),cycles.count==2 else { throw OriginalDomainIdentityFailure.invalidDomain }
            try OriginalDomainAccess.storage(2,ExactRationalCoefficient.self,&a)
            var indices:[ExactRationalCoefficient]=[];indices.reserveCapacity(2)
            for cycle in cycles { try a.consumeWork(1);indices.append(cycle.original) }
            let graph=try space.family.graph(template:template,cycles:indices,maximumCharts:limits.maximumCharts,limits:limits.source,using:&a)
            let relation=try DefaultOriginalParametricGraphDomainBinder().bind(graph:graph,request:effectiveEnclosure,limits:limits,using:&a)
            try OriginalDomainAccess.storage(1,Occurrence.self,&a)
            return .init(family:space.family,template:template,cycles:cycles,relation:relation)
        }
    }
    public func liftedPositionIncidents<A: ExactScalarAdmission & ~Copyable>(at tuple: borrowing [OriginalExactScalar],
        limits: OriginalDomainIdentityLimits,using admission: inout A) throws(OriginalDomainIdentityFailure) -> [Occurrence] {
        let tuple=copy tuple
        return try OriginalDomainAccess.run(&admission) { a in
            let family=space.family
            try DefaultOriginalPeriodicNativeSurfaceLiftDomainIssuer<S>().admitted(family,limits:limits,&a)
            guard tuple.count==3 else { throw OriginalDomainIdentityFailure.invalidDomain }
            for value in tuple { try a.consumeWork(1);_=try family.field.sign(of:value,using:&a) }
            try OriginalDomainAccess.storage(1,OriginalExactScalar.self,&a)
            guard try effectiveEnclosure.contains([tuple[0]],limits:limits,using:&a) else { return [] }
            try OriginalDomainAccess.storage(2,OriginalExactScalar.self,&a)
            let candidates=try space.surface.incident(at:[tuple[1],tuple[2]],limits:limits,using:&a)
            var result:[Occurrence]=[]
            for candidate in candidates {
                var lawOrdinal:Int?=nil
                for index in space.surface.space.sourceCharts.indices {
                    try a.consumeWork(1)
                    if candidate.sourceChart.selection.spans==space.surface.space.sourceCharts[index].selection.spans {
                        lawOrdinal=space.lawOrdinals[index];break
                    }
                }
                guard let lawOrdinal else { throw OriginalDomainIdentityFailure.incompleteCoverage }
                for pcurve in family.pcurve.laws.indices {
                    try a.consumeWork(1)
                    // The source preparer already checked this complete pair product.
                    let template=lawOrdinal*family.pcurve.laws.count+pcurve
                    let occurrence=try member(template:template,cycles:candidate.cycles,limits:limits,using:&a)
                    if try occurrence.relation.graph.admits(tuple,limits:limits.source,using:&a) {
                        guard result.count<limits.maximumCharts else { throw OriginalDomainIdentityFailure.chartLimit }
                        try OriginalDomainAccess.storage(1,Occurrence.self,&a);result.append(occurrence)
                    }
                }
            }
            return result
        }
    }
}
