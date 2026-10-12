#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

extension DefaultOriginalParameterIdentityIssuer: OriginalPeriodicParameterIdentityIssuing where S: OriginalBSplineSourceReading {
    public func periodic<A: ExactScalarAdmission & ~Copyable>(cover: borrowing OriginalBSplineDomainCover<S,F>,
        from selected: borrowing OriginalParameterSelection<S,F>,axis: Int,cycle: OriginalParameterCycle,
        limits: OriginalDomainIdentityLimits,using admission: inout A) throws(OriginalDomainIdentityFailure) -> OriginalParameterIdentity<S,F> {
        let cover = copy cover, selected = copy selected
        return try OriginalDomainAccess.run(&admission) { a in
            guard cover.space.periods.count <= limits.maximumFamilies else { throw OriginalDomainIdentityFailure.familyLimit }
            var period: OriginalSourcePeriodReceipt<S,F>? = nil
            for p in cover.space.periods { try a.consumeWork(1); if p.axis == axis { period = p } }
            guard let period else { throw OriginalDomainIdentityFailure.unsupportedSourceProof }
            return try orbit(period:period,from:selected,effective:cover.effective,cycle:cycle,limits:limits,&a)
        }
    }
}

// Only a source-owned period theorem reaches this proof construction.
extension DefaultOriginalParameterIdentityIssuer {
    func orbit<A: ExactScalarAdmission & ~Copyable>(period: OriginalSourcePeriodReceipt<S,F>,
        from selected: OriginalParameterSelection<S,F>,effective: OriginalParameterSelection<S,F>,
        cycle: OriginalParameterCycle,limits: OriginalDomainIdentityLimits,_ a: inout A) throws -> OriginalParameterIdentity<S,F> {
            let left = try effective.intersection(selected,limits:limits,using:&a)
            let t = DefaultOriginalParameterTransporter<S,F>()
            let lift = try t.periodicLift(from:left,to:effective.frame,period:period,cycle:cycle,limits:limits,using:&a)
            let right = try lift.transport.image.intersection(effective,limits:limits,using:&a)
            let inverse = try t.inverse(lift.transport,limits:limits,using:&a)
            let restricted = try t.restrict(inverse,to:right,limits:limits,using:&a)
            let map = try t.inverse(restricted,limits:limits,using:&a)
            try OriginalDomainAccess.storage(1,OriginalSourcePeriodReceipt<S,F>.self,&a)
            return try make(kind:.periodicOrbit,left:map.local,right:map.image,permutation:map.permutation,gains:map.gains,offsets:map.offsets,
                periods:[period],depth:map.depth,using:&a,limits:limits)
    }
}
