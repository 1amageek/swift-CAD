#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

extension OriginalBSplineDomainCover {
    public func member<A: ExactScalarAdmission & ~Copyable>(template index: Int, cycles: borrowing [OriginalParameterCycle],
        limits: OriginalDomainIdentityLimits,using admission: inout A) throws(OriginalDomainIdentityFailure) -> OriginalBSplineChartOccurrence<S,F> {
        let cycles = copy cycles
        return try OriginalDomainAccess.run(&admission) { a in
            guard space.sourceCharts.count <= limits.maximumCharts else { throw OriginalDomainIdentityFailure.chartLimit }
            guard space.periods.count <= limits.maximumFamilies else { throw OriginalDomainIdentityFailure.familyLimit }
            guard index >= 0, index < space.sourceCharts.count, cycles.count == space.frame.arity else { throw OriginalDomainIdentityFailure.invalidDomain }
            let f = space.frame.scalarField, q = ExactRationalScalarDomain(), n = cycles.count
            try OriginalDomainAccess.storage(n,Int.self,&a)
            try OriginalDomainAccess.storage(try OriginalDomainAccess.multiplied(n,2),F.Value.self,&a)
            var permutation: [Int] = [], gains: [F.Value] = [], offsets: [F.Value] = []
            for axis in 0..<n {
                try a.consumeWork(1); permutation.append(axis); gains.append(try f.integer(1,using:&a))
                var period: OriginalSourcePeriodReceipt<S,F>? = nil
                for p in space.periods { try a.consumeWork(1); if p.axis == axis { period = p } }
                if let p = period { offsets.append(try f.multiplying(cycles[axis].scalar(in:f,using:&a),p.period,using:&a)) }
                else {
                    guard try q.sign(of:cycles[axis].original,using:&a) == .zero else { throw OriginalDomainIdentityFailure.invalidDomain }
                    offsets.append(try f.integer(0,using:&a))
                }
            }
            let map = try DefaultOriginalParameterTransporter<S,F>().affine(
                from:space.fundamental.charts[index].transport.local,to:space.frame,
                permutation:permutation,gains:gains,offsets:offsets,limits:limits,using:&a)
            let selected = try map.image.intersection(effective,limits:limits,using:&a)
            return .init(sourceChart:space.sourceCharts[index],cycles:cycles,correspondence:map,selectedImage:selected)
        }
    }

    /// Every incident one-sided Native owner is returned, including all seam lifts.
    public func incident<A: ExactScalarAdmission & ~Copyable>(at tuple: borrowing [F.Value],
        limits: OriginalDomainIdentityLimits,using admission: inout A) throws(OriginalDomainIdentityFailure) -> [OriginalBSplineChartOccurrence<S,F>] {
        let tuple = copy tuple
        return try OriginalDomainAccess.run(&admission) { a in
            guard space.sourceCharts.count <= limits.maximumCharts else { throw OriginalDomainIdentityFailure.chartLimit }
            guard space.periods.count <= limits.maximumFamilies else { throw OriginalDomainIdentityFailure.familyLimit }
            guard try effective.contains(tuple,limits:limits,using:&a) else { return [] }
            let n = space.frame.arity, f = space.frame.scalarField, q = ExactRationalScalarDomain()
            let zero = try OriginalParameterCycle(exact:q.integer(0,using:&a),using:&a)
            try OriginalDomainAccess.storage(n,OriginalParameterCycle.self,&a)
            var base = [OriginalParameterCycle](repeating:zero,count:n)
            try OriginalDomainAccess.storage(1,[OriginalParameterCycle].self,&a)
            var alternatives: [[OriginalParameterCycle]] = [base]
            for p in space.periods {
                try a.consumeWork(1)
                let fraction = try f.dividing(f.subtracting(tuple[p.axis],p.lower,using:&a),p.period,using:&a)
                let cycle = try OriginalParameterCycle.floor(fraction,field:f,using:&a)
                let local = try f.subtracting(tuple[p.axis],f.multiplying(cycle.scalar(in:f,using:&a),p.period,using:&a),using:&a)
                let seam = try f.compare(local,p.lower,using:&a) == .equal
                var next: [[OriginalParameterCycle]] = []
                for candidate in alternatives {
                    try a.consumeWork(1)
                    try OriginalDomainAccess.storage(n,OriginalParameterCycle.self,&a)
                    base = candidate; base[p.axis] = cycle
                    try OriginalDomainAccess.storage(1,[OriginalParameterCycle].self,&a); next.append(base)
                    if seam {
                        try OriginalDomainAccess.storage(n,OriginalParameterCycle.self,&a)
                        var before = base
                        before[p.axis] = try .init(exact:q.subtracting(cycle.original,q.integer(1,using:&a),using:&a),using:&a)
                        try OriginalDomainAccess.storage(1,[OriginalParameterCycle].self,&a); next.append(before)
                    }
                }
                alternatives = next
            }
            var result: [OriginalBSplineChartOccurrence<S,F>] = []
            for cycles in alternatives {
                for index in space.sourceCharts.indices {
                    try a.consumeWork(1)
                    let chart = try member(template:index,cycles:cycles,limits:limits,using:&a)
                    if try chart.selectedImage.contains(tuple,limits:limits,using:&a) {
                        guard result.count < limits.maximumCharts else { throw OriginalDomainIdentityFailure.chartLimit }
                        try OriginalDomainAccess.storage(1,OriginalBSplineChartOccurrence<S,F>.self,&a); result.append(chart)
                    }
                }
            }
            guard !result.isEmpty else { throw OriginalDomainIdentityFailure.incompleteCoverage }
            return result
        }
    }
}
