#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

/// Complete original analytic parameter family, retaining the source pullback
/// and all collapsed fibers. Chart correspondence never removes original UV.
public struct OriginalAnalyticDomainCover<S: OriginalAnalyticCoordinateReading,F: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: OriginalChartFamilyQuerying {
    public typealias Source = S
    public typealias Field = F
    public typealias Occurrence = OriginalParameterTransport<S,F>
    public let law: OriginalAnalyticCoordinateLawReceipt<S,F>
    public let support: OriginalParameterSelection<S,F>
    public let request: OriginalParameterSelection<S,F>
    public let effective: OriginalParameterSelection<S,F>
    public var source: OriginalSourceBinding<S> { law.source }
    public var templateCount: Int { 1 }
    public var integerFamilyRank: Int { law.periods.count }
    init(law: OriginalAnalyticCoordinateLawReceipt<S,F>,support: OriginalParameterSelection<S,F>,request: OriginalParameterSelection<S,F>,effective: OriginalParameterSelection<S,F>) {
        self.law = law; self.support = support; self.request = request; self.effective = effective
    }
    public func member<A: ExactScalarAdmission & ~Copyable>(template: Int,cycles: borrowing [OriginalParameterCycle],limits: OriginalDomainIdentityLimits,
        using admission: inout A) throws(OriginalDomainIdentityFailure) -> Occurrence {
        let cycles = copy cycles
        return try OriginalDomainAccess.run(&admission) { a in
            guard limits.maximumFamilies >= integerFamilyRank else { throw OriginalDomainIdentityFailure.familyLimit }
            guard limits.maximumCharts >= 1 else { throw OriginalDomainIdentityFailure.chartLimit }
            guard template == 0,cycles.count == support.arity else { throw OriginalDomainIdentityFailure.invalidDomain }
            try law.admitProof(limits:limits.source,using:&a)
            let n = cycles.count,f = support.frame.scalarField,q = ExactRationalScalarDomain()
            try OriginalDomainAccess.storage(n,[ExactParameterInterval<F.Value>].self,&a)
            try OriginalDomainAccess.storage(n,Int.self,&a)
            try OriginalDomainAccess.storage(try OriginalDomainAccess.multiplied(n,2),F.Value.self,&a)
            var intervals: [[ExactParameterInterval<F.Value>]] = [],permutation: [Int] = [],gains: [F.Value] = [],offsets: [F.Value] = []
            for axis in 0..<n {
                try a.consumeWork(1); permutation.append(axis); gains.append(try f.integer(1,using:&a))
                var period: OriginalSourcePeriodReceipt<S,F>? = nil
                for p in law.periods { try a.consumeWork(1); if p.axis == axis { period = p } }
                if let p = period {
                    let interval = try support.frame.axisDomains[axis].interval(lower:.finite(p.lower),upper:.finite(p.upper),using:&a)
                    try OriginalDomainAccess.storage(1,ExactParameterInterval<F.Value>.self,&a); intervals.append([interval])
                    offsets.append(try f.multiplying(cycles[axis].scalar(in:f,using:&a),p.period,using:&a))
                } else {
                    guard try q.sign(of:cycles[axis].original,using:&a) == .zero else { throw OriginalDomainIdentityFailure.invalidDomain }
                    try OriginalDomainAccess.storage(effective.axes[axis].intervalCount,ExactParameterInterval<F.Value>.self,&a)
                    intervals.append(Array(effective.axes[axis].intervals)); offsets.append(try f.integer(0,using:&a))
                }
            }
            let t = DefaultOriginalParameterTransporter<S,F>()
            // A finite authored arc may clip a translated fundamental interval.
            // Build its exact preimage first: an oversized intermediate image
            // must not be admitted into the bounded original source frame.
            let whole = try ExactParameterInterval<F.Value>.checked(field:f,lower:.negativeInfinity,upper:.positiveInfinity,depth:.init(value:0,coefficient:0),using:&a)
            try OriginalDomainAccess.storage(n,[ExactParameterInterval<F.Value>].self,&a)
            try OriginalDomainAccess.storage(n,ExactParameterInterval<F.Value>.self,&a)
            try OriginalDomainAccess.storage(n,OriginalCoordinateSemantics.self,&a)
            let localFrame = try t.frame(source:source,field:f,support:Array(repeating:[whole],count:n),
                semantics:Array(support.frame.coordinateSemantics),limits:limits,using:&a)
            let fundamental = try localFrame.selection(intervals:intervals,limits:limits,using:&a)
            try OriginalDomainAccess.storage(n,F.Value.self,&a)
            var negativeOffsets: [F.Value] = []
            for offset in offsets { try a.consumeWork(1); negativeOffsets.append(try f.negated(offset,using:&a)) }
            let reverse = try t.affine(from:effective,to:localFrame,permutation:permutation,gains:gains,offsets:negativeOffsets,limits:limits,using:&a)
            let selected = try reverse.image.intersection(fundamental,limits:limits,using:&a)
            let map = try t.inverse(reverse,limits:limits,using:&a)
            return try t.restrict(map,to:selected,limits:limits,using:&a)
        }
    }
    public func incident<A: ExactScalarAdmission & ~Copyable>(at tuple: borrowing [F.Value],limits: OriginalDomainIdentityLimits,
        using admission: inout A) throws(OriginalDomainIdentityFailure) -> [Occurrence] {
        let tuple = copy tuple
        return try OriginalDomainAccess.run(&admission) { a in
            guard limits.maximumFamilies >= integerFamilyRank else { throw OriginalDomainIdentityFailure.familyLimit }
            guard try effective.contains(tuple,limits:limits,using:&a) else { return [] }
            let n = support.arity,f = support.frame.scalarField,q = ExactRationalScalarDomain()
            let zero = try OriginalParameterCycle(exact:q.integer(0,using:&a),using:&a)
            try OriginalDomainAccess.storage(n,OriginalParameterCycle.self,&a)
            try OriginalDomainAccess.storage(1,[OriginalParameterCycle].self,&a)
            var alternatives = [Array(repeating:zero,count:n)]
            for p in law.periods {
                try a.consumeWork(1)
                let fraction = try f.dividing(f.subtracting(tuple[p.axis],p.lower,using:&a),p.period,using:&a)
                let cycle = try OriginalParameterCycle.floor(fraction,field:f,using:&a)
                let local = try f.subtracting(tuple[p.axis],f.multiplying(cycle.scalar(in:f,using:&a),p.period,using:&a),using:&a)
                let seam = try f.compare(local,p.lower,using:&a) == .equal
                var next: [[OriginalParameterCycle]] = []
                for candidate in alternatives {
                    try a.consumeWork(1); try OriginalDomainAccess.storage(n,OriginalParameterCycle.self,&a)
                    var base = candidate; base[p.axis] = cycle
                    try OriginalDomainAccess.storage(1,[OriginalParameterCycle].self,&a); next.append(base)
                    if seam {
                        guard next.count < limits.maximumCharts else { throw OriginalDomainIdentityFailure.chartLimit }
                        try OriginalDomainAccess.storage(n,OriginalParameterCycle.self,&a)
                        var before = base; before[p.axis] = try .init(exact:q.subtracting(cycle.original,q.integer(1,using:&a),using:&a),using:&a)
                        try OriginalDomainAccess.storage(1,[OriginalParameterCycle].self,&a); next.append(before)
                    }
                }
                alternatives = next
            }
            var result: [Occurrence] = []
            for cycles in alternatives {
                try a.consumeWork(1)
                let map = try member(template:0,cycles:cycles,limits:limits,using:&a)
                if try map.image.contains(tuple,limits:limits,using:&a) {
                    guard result.count < limits.maximumCharts else { throw OriginalDomainIdentityFailure.chartLimit }
                    try OriginalDomainAccess.storage(1,Occurrence.self,&a); result.append(map)
                }
            }
            guard !result.isEmpty else { throw OriginalDomainIdentityFailure.incompleteCoverage }
            return result
        }
    }
}
