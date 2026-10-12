#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

/// Complete aggregate scope with every retained original closed traversal side.
public struct OriginalGuideDomainCover<S: OriginalGuideSourceReading,C: Sendable,
    F: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: OriginalFiniteChartFamilyQuerying where F.Source == F.Value {
    public typealias Source=S
    public typealias Field=F
    public typealias Occurrence=OriginalGuideChartOccurrence<S,C,F>
    public let family: OriginalFiniteGuideChartFamily<S,C,F>
    public let coverage: OriginalDomainCover<S,F>
    let maps: [OriginalParameterTransport<S,F>]
    public var source: OriginalSourceBinding<S> { family.source }
    public var support: OriginalParameterSelection<S,F> { coverage.support }
    public var request: OriginalParameterSelection<S,F> { coverage.request }
    public var effective: OriginalParameterSelection<S,F> { coverage.effective }
    public var templateCount: Int { family.laws.count }
    public var integerFamilyRank: Int { 0 }
    init(family: OriginalFiniteGuideChartFamily<S,C,F>,coverage: OriginalDomainCover<S,F>,maps: [OriginalParameterTransport<S,F>]) {
        self.family=family;self.coverage=coverage;self.maps=maps
    }
    func admitted<A: ExactScalarAdmission & ~Copyable>(_ limits: OriginalDomainIdentityLimits,_ a: inout A) throws {
        try DefaultOriginalGuideDomainIssuer<S,C,F>().admitted(family,limits,&a)
        try support.frame.require(limits,&a)
    }
    public func member<A: ExactScalarAdmission & ~Copyable>(template: Int,cycles: borrowing [OriginalParameterCycle],
        limits: OriginalDomainIdentityLimits,using admission: inout A) throws(OriginalDomainIdentityFailure) -> Occurrence {
        let cycles=copy cycles
        return try OriginalDomainAccess.run(&admission) { a in
            try admitted(limits,&a)
            guard maps.indices.contains(template),cycles.count == 1 else { throw OriginalDomainIdentityFailure.invalidDomain }
            guard try ExactRationalScalarDomain().sign(of:cycles[0].original,using:&a) == .zero else { throw OriginalDomainIdentityFailure.invalidDomain }
            try DefaultOriginalParameterTransporter<S,F>().admitted(maps[template],limits:limits,using:&a)
            return .init(family:family,template:template,transport:maps[template])
        }
    }
    public func incident<A: ExactScalarAdmission & ~Copyable>(at tuple: borrowing [F.Value],limits: OriginalDomainIdentityLimits,
        using admission: inout A) throws(OriginalDomainIdentityFailure) -> [Occurrence] {
        let tuple=copy tuple
        return try OriginalDomainAccess.run(&admission) { a in
            try admitted(limits,&a)
            guard try effective.contains(tuple,limits:limits,using:&a) else { return [] }
            var result: [Occurrence]=[]
            for index in maps.indices {
                try a.consumeWork(1)
                if try maps[index].image.contains(tuple,limits:limits,using:&a) {
                    try DefaultOriginalParameterTransporter<S,F>().admitted(maps[index],limits:limits,using:&a)
                    try OriginalDomainAccess.storage(1,Occurrence.self,&a)
                    result.append(.init(family:family,template:index,transport:maps[index]))
                }
            }
            guard !result.isEmpty else { throw OriginalDomainIdentityFailure.incompleteCoverage }
            return result
        }
    }
    public func selectedMembers<A: ExactScalarAdmission & ~Copyable>(limits: OriginalDomainIdentityLimits,
        using admission: inout A) throws(OriginalDomainIdentityFailure) -> [Occurrence] {
        return try OriginalDomainAccess.run(&admission) { a in
            try admitted(limits,&a)
            var result: [Occurrence]=[]
            for index in maps.indices {
                try a.consumeWork(1)
                if !maps[index].image.isEmpty {
                    try DefaultOriginalParameterTransporter<S,F>().admitted(maps[index],limits:limits,using:&a)
                    try OriginalDomainAccess.storage(1,Occurrence.self,&a)
                    result.append(.init(family:family,template:index,transport:maps[index]))
                }
            }
            guard effective.isEmpty || !result.isEmpty else { throw OriginalDomainIdentityFailure.incompleteCoverage }
            return result
        }
    }
}
