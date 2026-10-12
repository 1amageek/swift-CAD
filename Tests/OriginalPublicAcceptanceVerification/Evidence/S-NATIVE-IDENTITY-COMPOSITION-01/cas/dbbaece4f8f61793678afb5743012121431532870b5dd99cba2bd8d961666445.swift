#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

/// Whole intrinsic sphere parameter cover. The longitude family is all integers;
/// its two-coordinate domain is unchanged at both collapsed latitude boundaries.
public struct OriginalIntrinsicSphereDomainCover<S: OriginalIntrinsicSphereSourceReading,F: ExactScalarArithmetic & ExactScalarOrdering>: OriginalChartFamilyQuerying {
    public typealias Source = S
    public typealias Field = F
    public typealias Occurrence = OriginalParameterPeriodicLift<S,F>
    public var source: OriginalSourceBinding<S> { frame.source }
    public let support: OriginalParameterSelection<S,F>
    public var templateCount: Int { 1 }
    public var integerFamilyRank: Int { 1 }
    public let frame: OriginalParameterFrame<S,F>
    public let request: OriginalParameterSelection<S,F>
    public let effective: OriginalParameterSelection<S,F>
    public let period: OriginalSourcePeriodReceipt<S,F>
    init(frame: OriginalParameterFrame<S,F>,support: OriginalParameterSelection<S,F>,request: OriginalParameterSelection<S,F>,effective: OriginalParameterSelection<S,F>,period: OriginalSourcePeriodReceipt<S,F>) {
        self.frame = frame; self.support = support; self.request = request; self.effective = effective; self.period = period
    }
    public func member<A: ExactScalarAdmission & ~Copyable>(template: Int,
        cycles: borrowing [OriginalParameterCycle],limits: OriginalDomainIdentityLimits,
        using admission: inout A) throws(OriginalDomainIdentityFailure) -> OriginalParameterPeriodicLift<S,F> {
        let cycles = copy cycles
        return try OriginalDomainAccess.run(&admission) { a in
            guard limits.maximumFamilies >= 1 else { throw OriginalDomainIdentityFailure.familyLimit }
            guard limits.maximumCharts >= 1 else { throw OriginalDomainIdentityFailure.chartLimit }
            guard template == 0,cycles.count == 2 else { throw OriginalDomainIdentityFailure.invalidDomain }
            let q = ExactRationalScalarDomain()
            guard try q.sign(of:cycles[1].original,using:&a) == .zero else { throw OriginalDomainIdentityFailure.invalidDomain }
            let d = frame.axisDomains[0]
            let interval = try d.interval(lower:.finite(period.lower),upper:.finite(period.upper),using:&a)
            try OriginalDomainAccess.storage(2,[ExactParameterInterval<F.Value>].self,&a)
            try OriginalDomainAccess.storage(1,ExactParameterInterval<F.Value>.self,&a)
            try OriginalDomainAccess.storage(effective.axes[1].intervalCount,ExactParameterInterval<F.Value>.self,&a)
            // Latitude selection is independent of the longitude family. The
            // original two-coordinate domain remains two-dimensional at a pole.
            let fundamental = try frame.selection(intervals:[[interval],Array(effective.axes[1].intervals)],limits:limits,using:&a)
            let t = DefaultOriginalParameterTransporter<S,F>()
            let lift = try t.periodicLift(from:fundamental,to:frame,period:period,cycle:cycles[0],limits:limits,using:&a)
            let selected = try lift.transport.image.intersection(effective,limits:limits,using:&a)
            let inverse = try t.inverse(lift.transport,limits:limits,using:&a)
            let local = try t.restrict(inverse,to:selected,limits:limits,using:&a)
            let map = try t.inverse(local,limits:limits,using:&a)
            return .init(transport:map,period:period,cycle:cycles[0])
        }
    }
    public func incident<A: ExactScalarAdmission & ~Copyable>(at tuple: borrowing [F.Value],limits: OriginalDomainIdentityLimits,
        using admission: inout A) throws(OriginalDomainIdentityFailure) -> [OriginalParameterPeriodicLift<S,F>] {
        let tuple = copy tuple
        return try OriginalDomainAccess.run(&admission) { a in
            guard limits.maximumFamilies >= 1 else { throw OriginalDomainIdentityFailure.familyLimit }
            guard try effective.contains(tuple,limits:limits,using:&a) else { return [] }
            let f = frame.scalarField
            let cycle = try OriginalParameterCycle.floor(f.dividing(f.subtracting(tuple[0],period.lower,using:&a),period.period,using:&a),field:f,using:&a)
            let local = try f.subtracting(tuple[0],f.multiplying(cycle.scalar(in:f,using:&a),period.period,using:&a),using:&a)
            let seam = try f.compare(local,period.lower,using:&a) == .equal
            let count = seam ? 2 : 1
            guard count <= limits.maximumCharts else { throw OriginalDomainIdentityFailure.chartLimit }
            let q = ExactRationalScalarDomain()
            let zero = try OriginalParameterCycle(exact:q.integer(0,using:&a),using:&a)
            try OriginalDomainAccess.storage(count,OriginalParameterPeriodicLift<S,F>.self,&a)
            try OriginalDomainAccess.storage(try OriginalDomainAccess.multiplied(count,2),OriginalParameterCycle.self,&a)
            var result = [try member(template:0,cycles:[cycle,zero],limits:limits,using:&a)]
            if seam {
                let before = try OriginalParameterCycle(exact:q.subtracting(cycle.original,q.integer(1,using:&a),using:&a),using:&a)
                result.append(try member(template:0,cycles:[before,zero],limits:limits,using:&a))
            }
            return result
        }
    }
}
