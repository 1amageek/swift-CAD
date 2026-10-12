#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

extension OriginalBSplineDomainCover: OriginalFiniteChartFamilyQuerying {
    public func selectedMembers<A: ExactScalarAdmission & ~Copyable>(limits: OriginalDomainIdentityLimits,
        using admission: inout A) throws(OriginalDomainIdentityFailure) -> [OriginalBSplineChartOccurrence<S,F>] {
        try OriginalDomainAccess.run(&admission) { a in
            try space.frame.require(limits,&a)
            guard templateCount <= limits.maximumCharts else { throw OriginalDomainIdentityFailure.chartLimit }
            guard integerFamilyRank <= limits.maximumFamilies else { throw OriginalDomainIdentityFailure.familyLimit }
            if effective.isEmpty { return [] }
            let f = space.frame.scalarField,q = ExactRationalScalarDomain(),n = space.frame.arity
            let zero = try q.integer(0,using:&a),one = try q.integer(1,using:&a)
            let integers = try ExactParameterDomain(field:q,depth:.init(value:0,coefficient:0),using:&a)
            var result: [OriginalBSplineChartOccurrence<S,F>] = []
            for template in 0..<templateCount {
                try a.consumeWork(1)
                try OriginalDomainAccess.storage(n,ExactParameterSet<ExactRationalScalarDomain>.self,&a)
                var ranges: [ExactParameterSet<ExactRationalScalarDomain>] = []
                ranges.reserveCapacity(n)
                for axis in 0..<n {
                    try a.consumeWork(1)
                    var period: OriginalSourcePeriodReceipt<S,F>? = nil
                    for proof in space.periods { try a.consumeWork(1); if proof.axis == axis { period = proof } }
                    var candidates: [ExactParameterInterval<ExactRationalCoefficient>] = []
                    if let period {
                        let local = space.fundamental.charts[template].transport.local.axes[axis]
                        guard local.intervalCount == 1,let interval = local.intervals.first,
                            case .finite(let chartLower) = interval.lower,
                            case .finite(let chartUpper) = interval.upper else { throw OriginalDomainIdentityFailure.invalidDomain }
                        for interval in effective.axes[axis].intervals {
                            try a.consumeWork(1)
                            guard case .finite(let lower) = interval.lower,case .finite(let upper) = interval.upper else {
                                throw OriginalDomainIdentityFailure.unsupportedSourceProof
                            }
                            let lowFraction = try f.dividing(f.subtracting(lower,chartUpper,using:&a),period.period,using:&a)
                            let first = try q.negated(OriginalParameterCycle.floor(f.negated(lowFraction,using:&a),field:f,using:&a).original,using:&a)
                            let last = try OriginalParameterCycle.floor(
                                f.dividing(f.subtracting(upper,chartLower,using:&a),period.period,using:&a),field:f,using:&a).original
                            if try q.compare(first,last,using:&a) != .greater {
                                try OriginalDomainAccess.storage(1,ExactParameterInterval<ExactRationalCoefficient>.self,&a)
                                candidates.append(try integers.interval(lower:.finite(first),upper:.finite(last),using:&a))
                            }
                        }
                    } else {
                        try OriginalDomainAccess.storage(1,ExactParameterInterval<ExactRationalCoefficient>.self,&a)
                        candidates.append(try integers.interval(lower:.finite(zero),upper:.finite(zero),using:&a))
                    }
                    ranges.append(try integers.set(intervals:candidates,using:&a))
                }
                let zeroCycle = try OriginalParameterCycle(exact:zero,using:&a)
                try OriginalDomainAccess.storage(n,OriginalParameterCycle.self,&a)
                var cycles = [OriginalParameterCycle](repeating:zeroCycle,count:n)
                var sharesRetainedOccurrence = false
                func visit(_ axis: Int,_ a: inout A) throws {
                    try a.consumeWork(1)
                    if axis == n {
                        let occurrence = try member(template:template,cycles:cycles,limits:limits,using:&a)
                        if !occurrence.selectedImage.isEmpty {
                            guard result.count < limits.maximumCharts else { throw OriginalDomainIdentityFailure.chartLimit }
                            try OriginalDomainAccess.storage(1,OriginalBSplineChartOccurrence<S,F>.self,&a)
                            result.append(occurrence)
                            sharesRetainedOccurrence = true
                        }
                        return
                    }
                    for range in ranges[axis].intervals {
                        guard case .finite(let lower) = range.lower,case .finite(let upper) = range.upper else {
                            throw OriginalDomainIdentityFailure.invalidDomain
                        }
                        var value = lower
                        while try q.compare(value,upper,using:&a) != .greater {
                            try a.consumeWork(1)
                            if sharesRetainedOccurrence {
                                // Admit the actual COW successor before mutation;
                                // a final retained occurrence needs no successor.
                                try OriginalDomainAccess.storage(n,OriginalParameterCycle.self,&a)
                                sharesRetainedOccurrence = false
                            }
                            cycles[axis] = try OriginalParameterCycle(exact:value,using:&a)
                            try visit(axis+1,&a)
                            value = try q.adding(value,one,using:&a)
                        }
                    }
                }
                try visit(0,&a)
            }
            guard !result.isEmpty else { throw OriginalDomainIdentityFailure.incompleteCoverage }
            return result
        }
    }
}
