#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

/// Complete source-bound U/V cover. Angular lifts and generator sides remain distinct.
public struct OriginalRevolutionDomainCover<S: OriginalRevolutionSourceReading,C: Sendable,
    F: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: OriginalChartFamilyQuerying where F.Source == F.Value {
    public typealias Source = S
    public typealias Field = F
    public typealias Occurrence = OriginalRevolutionChartOccurrence<S,C,F>
    public let family: OriginalFiniteRevolutionLawFamily<S,C,F>
    public let support: OriginalParameterSelection<S,F>
    public let request: OriginalParameterSelection<S,F>
    public let effective: OriginalParameterSelection<S,F>
    public var source: OriginalSourceBinding<S> { family.source }
    public var templateCount: Int { family.laws.count }
    public var integerFamilyRank: Int { 1 }
    init(family: OriginalFiniteRevolutionLawFamily<S,C,F>,support: OriginalParameterSelection<S,F>,
        request: OriginalParameterSelection<S,F>,effective: OriginalParameterSelection<S,F>) {
        self.family = family;self.support = support;self.request = request;self.effective = effective
    }
    func admitted<A: ExactScalarAdmission & ~Copyable>(_ limits: OriginalDomainIdentityLimits,_ a: inout A) throws {
        try DefaultOriginalRevolutionDomainIssuer<S,C,F>().admitted(family,limits:limits,using:&a)
        try support.frame.require(limits,&a)
    }
    func occurrence<A: ExactScalarAdmission & ~Copyable>(template: Int,cycles: [OriginalParameterCycle],
        limits: OriginalDomainIdentityLimits,_ a: inout A) throws -> Occurrence {
        guard family.laws.indices.contains(template),cycles.count == 2 else { throw OriginalDomainIdentityFailure.invalidDomain }
        let q = ExactRationalScalarDomain(),f = family.field,law = family.laws[template]
        guard try q.sign(of:cycles[1].original,using:&a) == .zero else { throw OriginalDomainIdentityFailure.invalidDomain }
        let shift = try f.multiplying(cycles[0].scalar(in:f,using:&a),family.period.period,using:&a)
        let whole = try ExactParameterInterval<F.Value>.checked(field:f,lower:.negativeInfinity,upper:.positiveInfinity,
            depth:family.proofDepth,using:&a)
        try OriginalDomainAccess.storage(2,[ExactParameterInterval<F.Value>].self,&a)
        try OriginalDomainAccess.storage(2,OriginalCoordinateSemantics.self,&a)
        let t = DefaultOriginalParameterTransporter<S,F>()
        let localFrame = try t.frame(source:source,field:f,support:[[whole],[whole]],
            semantics:[.intrinsicAngularLabel,.authoredScalar],limits:limits,using:&a)
        try OriginalDomainAccess.storage(2,[ExactParameterInterval<F.Value>].self,&a)
        try OriginalDomainAccess.storage(2,ExactParameterInterval<F.Value>.self,&a)
        let fundamental = try localFrame.selection(intervals:[
            [.checked(field:f,lower:.finite(family.period.lower),upper:.finite(family.period.upper),depth:family.proofDepth,using:&a)],
            [.checked(field:f,lower:.finite(law.support[1].lower),upper:.finite(law.support[1].upper),depth:law.proofDepth,using:&a)]
        ],limits:limits,using:&a)
        try OriginalDomainAccess.storage(2,Int.self,&a)
        try OriginalDomainAccess.storage(4,F.Value.self,&a)
        let one = try f.integer(1,using:&a),zero = try f.integer(0,using:&a)
        let reverse = try t.affine(from:effective,to:localFrame,permutation:[0,1],gains:[one,one],
            offsets:[f.negated(shift,using:&a),zero],limits:limits,using:&a)
        let selected = try reverse.image.intersection(fundamental,limits:limits,using:&a)
        let map = try t.inverse(reverse,limits:limits,using:&a)
        return .init(family:family,template:template,transport:try t.restrict(map,to:selected,limits:limits,using:&a))
    }
    public func member<A: ExactScalarAdmission & ~Copyable>(template: Int,cycles: borrowing [OriginalParameterCycle],
        limits: OriginalDomainIdentityLimits,using admission: inout A) throws(OriginalDomainIdentityFailure) -> Occurrence {
        let cycles = copy cycles
        return try OriginalDomainAccess.run(&admission) { a in
            try admitted(limits,&a)
            return try occurrence(template:template,cycles:cycles,limits:limits,&a)
        }
    }
    public func incident<A: ExactScalarAdmission & ~Copyable>(at tuple: borrowing [F.Value],limits: OriginalDomainIdentityLimits,
        using admission: inout A) throws(OriginalDomainIdentityFailure) -> [Occurrence] {
        let tuple = copy tuple
        return try OriginalDomainAccess.run(&admission) { a in
            try admitted(limits,&a)
            guard try effective.contains(tuple,limits:limits,using:&a) else { return [] }
            let f = family.field,q = ExactRationalScalarDomain()
            let fraction = try f.dividing(f.subtracting(tuple[0],family.period.lower,using:&a),family.period.period,using:&a)
            let cycle = try OriginalParameterCycle.floor(fraction,field:f,using:&a)
            let local = try f.subtracting(tuple[0],f.multiplying(cycle.scalar(in:f,using:&a),family.period.period,using:&a),using:&a)
            let seam = try f.compare(local,family.period.lower,using:&a) == .equal
            let zero = try OriginalParameterCycle(exact:q.integer(0,using:&a),using:&a)
            try OriginalDomainAccess.storage(seam ? 2 : 1,OriginalParameterCycle.self,&a)
            var angular = [cycle]
            if seam { angular.append(try .init(exact:q.subtracting(cycle.original,q.integer(1,using:&a),using:&a),using:&a)) }
            var result: [Occurrence] = []
            for template in family.laws.indices {
                let law = family.laws[template]
                try a.consumeWork(1)
                guard try f.compare(tuple[1],law.support[1].lower,using:&a) != .less,
                    try f.compare(tuple[1],law.support[1].upper,using:&a) != .greater else { continue }
                for angularCycle in angular {
                    try a.consumeWork(1);try OriginalDomainAccess.storage(2,OriginalParameterCycle.self,&a)
                    let item = try occurrence(template:template,cycles:[angularCycle,zero],limits:limits,&a)
                    if try item.transport.image.contains(tuple,limits:limits,using:&a) {
                        guard result.count < limits.maximumCharts else { throw OriginalDomainIdentityFailure.chartLimit }
                        try OriginalDomainAccess.storage(1,Occurrence.self,&a);result.append(item)
                    }
                }
            }
            guard !result.isEmpty else { throw OriginalDomainIdentityFailure.incompleteCoverage }
            return result
        }
    }
}
