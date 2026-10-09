#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

/// Complete requested guarded domain retaining every original child chart.
public struct OriginalNativeOffsetDomainCover<S: OriginalOffsetSourceReading>: OriginalGuardedChartFamilyQuerying where S.Child: OriginalBSplineSourceReading {
    public typealias Source = S
    public typealias Field = OriginalExactScalarDomain
    public typealias Occurrence = OriginalNativeOffsetChartOccurrence<S>
    public let family: OriginalFiniteNativeOffsetLawFamily<S>
    public let enclosingSupport: OriginalParameterSelection<S,Field>
    public let request: OriginalParameterSelection<S,Field>
    public let effectiveEnclosure: OriginalParameterSelection<S,Field>
    public var source: OriginalSourceBinding<S> { family.source }
    public var templateCount: Int { family.laws.count }
    init(family: OriginalFiniteNativeOffsetLawFamily<S>,enclosingSupport: OriginalParameterSelection<S,Field>,
        request: OriginalParameterSelection<S,Field>,effectiveEnclosure: OriginalParameterSelection<S,Field>) {
        self.family = family;self.enclosingSupport = enclosingSupport;self.request = request;self.effectiveEnclosure = effectiveEnclosure
    }
    func occurrence<A: ExactScalarAdmission & ~Copyable>(template: Int,limits: OriginalDomainIdentityLimits,
        _ a: inout A) throws -> Occurrence {
        guard family.laws.indices.contains(template) else { throw OriginalDomainIdentityFailure.invalidDomain }
        let law = family.laws[template],issuer = DefaultOriginalNativeOffsetDomainIssuer<S>()
        let enclosure = try enclosingSupport.frame.selection(intervals:issuer.intervals(law.enclosingSupport,
            field:family.field,depth:law.proofDepth,&a),limits:limits,using:&a)
        return .init(family:family,template:template,
            enclosingSelection:try enclosure.intersection(effectiveEnclosure,limits:limits,using:&a))
    }
    public func member<A: ExactScalarAdmission & ~Copyable>(template: Int,limits: OriginalDomainIdentityLimits,
        using admission: inout A) throws(OriginalDomainIdentityFailure) -> Occurrence {
        return try OriginalDomainAccess.run(&admission) { a in
            try DefaultOriginalNativeOffsetDomainIssuer<S>().admitted(family,limits:limits,&a)
            return try occurrence(template:template,limits:limits,&a)
        }
    }
    func incidents<A: ExactScalarAdmission & ~Copyable>(tuple: [OriginalExactScalar],lifted: Bool,
        limits: OriginalDomainIdentityLimits,_ a: inout A) throws -> [Occurrence] {
        try DefaultOriginalNativeOffsetDomainIssuer<S>().admitted(family,limits:limits,&a)
        guard tuple.count == (lifted ? 3 : 2) else { throw OriginalDomainIdentityFailure.invalidDomain }
        try OriginalDomainAccess.storage(2,OriginalExactScalar.self,&a)
        let parameters = [tuple[0],tuple[1]]
        guard try effectiveEnclosure.contains(parameters,limits:limits,using:&a) else { return [] }
        var result: [Occurrence] = []
        for template in family.laws.indices {
            try a.consumeWork(1)
            let law = family.laws[template]
            let included = try lifted ? law.admitsLiftedPosition(at:tuple,limits:limits.source,using:&a)
                : law.admitsPosition(at:parameters,limits:limits.source,using:&a)
            if included {
                guard result.count < limits.maximumCharts else { throw OriginalDomainIdentityFailure.chartLimit }
                try OriginalDomainAccess.storage(1,Occurrence.self,&a)
                result.append(try occurrence(template:template,limits:limits,&a))
            }
        }
        return result
    }
    public func positionIncidents<A: ExactScalarAdmission & ~Copyable>(at tuple: borrowing [OriginalExactScalar],
        limits: OriginalDomainIdentityLimits,using admission: inout A)
        throws(OriginalDomainIdentityFailure) -> [Occurrence] {
        let tuple = copy tuple
        return try OriginalDomainAccess.run(&admission) { a in try incidents(tuple:tuple,lifted:false,limits:limits,&a) }
    }
    public func liftedPositionIncidents<A: ExactScalarAdmission & ~Copyable>(at tuple: borrowing [OriginalExactScalar],
        limits: OriginalDomainIdentityLimits,using admission: inout A)
        throws(OriginalDomainIdentityFailure) -> [Occurrence] {
        let tuple = copy tuple
        return try OriginalDomainAccess.run(&admission) { a in try incidents(tuple:tuple,lifted:true,limits:limits,&a) }
    }
}
