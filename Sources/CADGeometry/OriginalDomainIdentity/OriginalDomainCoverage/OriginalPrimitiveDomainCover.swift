#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

/// One whole nonperiodic source chart; the retained law proves source coverage.
public struct OriginalPrimitiveDomainCover<S: Sendable,F: ExactScalarArithmetic & ExactScalarOrdering,Law: Sendable>: OriginalChartFamilyQuerying {
    public typealias Source = S
    public typealias Field = F
    public typealias Occurrence = OriginalParameterTransport<S,F>
    public let law: Law
    public let support: OriginalParameterSelection<S,F>
    public let request: OriginalParameterSelection<S,F>
    public let effective: OriginalParameterSelection<S,F>
    public var source: OriginalSourceBinding<S> { support.frame.source }
    public var templateCount: Int { 1 }
    public var integerFamilyRank: Int { 0 }
    init(law: Law,support: OriginalParameterSelection<S,F>,request: OriginalParameterSelection<S,F>,effective: OriginalParameterSelection<S,F>) {
        self.law = law; self.support = support; self.request = request; self.effective = effective
    }
    public func member<A: ExactScalarAdmission & ~Copyable>(template: Int,cycles: borrowing [OriginalParameterCycle],
        limits: OriginalDomainIdentityLimits,using admission: inout A) throws(OriginalDomainIdentityFailure) -> Occurrence {
        let cycles = copy cycles
        return try OriginalDomainAccess.run(&admission) { a in
            guard limits.maximumCharts >= 1 else { throw OriginalDomainIdentityFailure.chartLimit }
            guard template == 0,cycles.count == support.arity else { throw OriginalDomainIdentityFailure.invalidDomain }
            let q = ExactRationalScalarDomain()
            for cycle in cycles { try a.consumeWork(1); guard try q.sign(of:cycle.original,using:&a) == .zero else { throw OriginalDomainIdentityFailure.invalidDomain } }
            let f = effective.frame.scalarField
            try OriginalDomainAccess.storage(effective.arity,Int.self,&a)
            try OriginalDomainAccess.storage(try OriginalDomainAccess.multiplied(effective.arity,2),F.Value.self,&a)
            let one = try f.integer(1,using:&a),zero = try f.integer(0,using:&a)
            return try DefaultOriginalParameterTransporter<S,F>().affine(from:effective,to:effective.frame,
                permutation:Array(0..<effective.arity),gains:Array(repeating:one,count:effective.arity),
                offsets:Array(repeating:zero,count:effective.arity),limits:limits,using:&a)
        }
    }
    public func incident<A: ExactScalarAdmission & ~Copyable>(at tuple: borrowing [F.Value],limits: OriginalDomainIdentityLimits,
        using admission: inout A) throws(OriginalDomainIdentityFailure) -> [Occurrence] {
        let tuple = copy tuple
        return try OriginalDomainAccess.run(&admission) { a in
            guard try effective.contains(tuple,limits:limits,using:&a) else { return [] }
            let q = ExactRationalScalarDomain()
            try OriginalDomainAccess.storage(support.arity,OriginalParameterCycle.self,&a)
            let zero = try OriginalParameterCycle(exact:q.integer(0,using:&a),using:&a)
            try OriginalDomainAccess.storage(1,Occurrence.self,&a)
            return [try member(template:0,cycles:Array(repeating:zero,count:support.arity),limits:limits,using:&a)]
        }
    }
}
