#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

public struct OriginalPeriodicNativeOffsetDomainCover<S: OriginalOffsetSourceReading>: OriginalPeriodicGuardedChartFamilyQuerying where S.Child: OriginalBSplineSourceReading {
    public typealias Source=S
    public typealias Field=OriginalExactScalarDomain
    public typealias Occurrence=OriginalPeriodicNativeOffsetChartOccurrence<S>
    public let space: OriginalPeriodicNativeOffsetDomainSpace<S>
    public let child: OriginalBSplineDomainCover<S.Child,Field>
    public let enclosingSupport: OriginalParameterSelection<S,Field>
    public let request: OriginalParameterSelection<S,Field>
    public let effectiveEnclosure: OriginalParameterSelection<S,Field>
    public var source: OriginalSourceBinding<S> { space.family.source }
    public var templateCount: Int { child.templateCount }
    public var integerFamilyRank: Int { child.integerFamilyRank }
    init(space: OriginalPeriodicNativeOffsetDomainSpace<S>,child: OriginalBSplineDomainCover<S.Child,Field>,
        enclosingSupport: OriginalParameterSelection<S,Field>,request: OriginalParameterSelection<S,Field>,
        effectiveEnclosure: OriginalParameterSelection<S,Field>) {
        self.space=space;self.child=child;self.enclosingSupport=enclosingSupport;self.request=request;self.effectiveEnclosure=effectiveEnclosure
    }
    func occurrence<A: ExactScalarAdmission & ~Copyable>(_ child: OriginalBSplineChartOccurrence<S.Child,Field>,
        template: Int,limits: OriginalDomainIdentityLimits,_ a: inout A) throws -> Occurrence {
        let issuer=DefaultOriginalPeriodicNativeOffsetDomainIssuer<S>()
        let selected=try space.frame.selection(intervals:issuer.intervals(child.selectedImage,&a),limits:limits,using:&a)
        try OriginalDomainAccess.storage(1,Occurrence.self,&a)
        return .init(family:space.family,template:template,lawOrdinal:space.lawOrdinals[template],child:child,enclosingSelection:selected)
    }
    public func member<A: ExactScalarAdmission & ~Copyable>(template: Int,cycles: borrowing [OriginalParameterCycle],
        limits: OriginalDomainIdentityLimits,using admission: inout A) throws(OriginalDomainIdentityFailure) -> Occurrence {
        let cycles=copy cycles
        return try OriginalDomainAccess.run(&admission) { a in
            try DefaultOriginalPeriodicNativeOffsetDomainIssuer<S>().admitted(space.family,limits:limits,&a)
            let member=try child.member(template:template,cycles:cycles,limits:limits,using:&a)
            return try occurrence(member,template:template,limits:limits,&a)
        }
    }
    func incidents<A: ExactScalarAdmission & ~Copyable>(_ tuple: [OriginalExactScalar],mode: Int,
        limits: OriginalDomainIdentityLimits,_ a: inout A) throws -> [Occurrence] {
        try DefaultOriginalPeriodicNativeOffsetDomainIssuer<S>().admitted(space.family,limits:limits,&a)
        guard tuple.count==(mode==2 ? 3:2) else { throw OriginalDomainIdentityFailure.invalidDomain }
        for value in tuple { try a.consumeWork(1);_=try space.family.field.sign(of:value,using:&a) }
        try OriginalDomainAccess.storage(2,OriginalExactScalar.self,&a)
        let uv=[tuple[0],tuple[1]]
        let candidates=try child.incident(at:uv,limits:limits,using:&a)
        var result: [Occurrence]=[]
        for candidate in candidates {
            var template: Int?=nil
            for index in space.child.sourceCharts.indices {
                try a.consumeWork(1)
                if candidate.sourceChart.selection.spans==space.child.sourceCharts[index].selection.spans { template=index;break }
            }
            guard let template else { throw OriginalDomainIdentityFailure.incompleteCoverage }
            let law=space.family.laws[space.lawOrdinals[template]]
            if mode != 0 {
                let transporter=DefaultOriginalParameterTransporter<S.Child,Field>()
                let inverse=try transporter.inverse(candidate.correspondence,limits:limits,using:&a)
                let local=try transporter.forward(uv,through:inverse,limits:limits,using:&a)
                if mode==2 {
                    try OriginalDomainAccess.storage(3,OriginalExactScalar.self,&a)
                    if try !law.admitsLiftedPosition(at:[local[0],local[1],tuple[2]],limits:limits.source,using:&a) { continue }
                } else if try !law.admitsPosition(at:local,limits:limits.source,using:&a) { continue }
            }
            guard result.count<limits.maximumCharts else { throw OriginalDomainIdentityFailure.chartLimit }
            try OriginalDomainAccess.storage(1,Occurrence.self,&a)
            result.append(try occurrence(candidate,template:template,limits:limits,&a))
        }
        return result
    }
    public func enclosureIncidents<A: ExactScalarAdmission & ~Copyable>(at tuple: borrowing [OriginalExactScalar],
        limits: OriginalDomainIdentityLimits,using admission: inout A) throws(OriginalDomainIdentityFailure) -> [Occurrence] {
        let tuple=copy tuple
        return try OriginalDomainAccess.run(&admission) { a in try incidents(tuple,mode:0,limits:limits,&a) }
    }
    public func positionIncidents<A: ExactScalarAdmission & ~Copyable>(at tuple: borrowing [OriginalExactScalar],
        limits: OriginalDomainIdentityLimits,using admission: inout A) throws(OriginalDomainIdentityFailure) -> [Occurrence] {
        let tuple=copy tuple
        return try OriginalDomainAccess.run(&admission) { a in try incidents(tuple,mode:1,limits:limits,&a) }
    }
    public func liftedPositionIncidents<A: ExactScalarAdmission & ~Copyable>(at tuple: borrowing [OriginalExactScalar],
        limits: OriginalDomainIdentityLimits,using admission: inout A) throws(OriginalDomainIdentityFailure) -> [Occurrence] {
        let tuple=copy tuple
        return try OriginalDomainAccess.run(&admission) { a in try incidents(tuple,mode:2,limits:limits,&a) }
    }
}
